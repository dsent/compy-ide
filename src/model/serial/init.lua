require('model.serial.line_reader')
require('model.serial.dispatcher')
require('model.serial.echo')
require('model.serial.dap_flash')
require('model.serial.dap_prepare')

--- Backend contract:
---   backend:start(sink)  sink.attach(info), sink.detach(),
---                        sink.bytes(chunk)
---   backend:poll(busy) -> nil | fault, one step per
---                        update; busy while a file goes
---                        to the board
---   backend:send(data) -> true | nil, err
---   backend:drop()       what send queued and has not
---                        written yet goes
---   backend:reset() -> true | nil, err  the board restarts
---   backend:dap() -> link | nil, err  commands to the
---                        board's interface chip, see DapLink
---   backend:board() -> { id, firmware } | nil  what the
---                        chip said about itself on open
---   backend:absence() -> why | nil  (optional) why a board
---                        on the bus is not open
---   backend:boardId() -> id | nil  (optional) the open
---                        board's unique id
---   backend:stop()

--- @class Serial
--- @field new function
--- @field fault function
--- @field table_for function
--- @field send function
--- @field drop function
--- @field reset function
--- @field isConnected function
--- @field programStarted function
--- @field programIdle function
--- @field programPaused function
--- @field programContinued function
--- @field programEnded function
--- @field echo Echo
--- @field flash function
--- @field isFlashing function
--- @field board function
--- @field update function
--- @field stop function
Serial = {}
Serial.__index = Serial

local FLASHING = 'A file is on its way to the micro:bit. Wait'
    .. ' until the Compy says how it went.'

--- @param backend table
--- @param max_line integer?
--- @return Serial
function Serial.new(backend, max_line)
  local self = setmetatable({}, Serial)
  self.backend = backend
  self.reader = LineReader.new(max_line)
  self.dispatcher = Dispatcher.new()
  self.faults = {}
  self.connected = false
  -- a flash may have erased the board's program, until one
  -- succeeds: kept here, since the link goes with the port
  self.wiped = false
  self.echo = Echo.new(io.write, print)
  for _, env in ipairs({ 'console', 'program' }) do
    local t = self.dispatcher:table_for(env)
    t.send = function(line)
      return self:send(line)
    end
    t.reset = function()
      return self:reset()
    end
    t.isConnected = function()
      return self:isConnected()
    end
    t.isFlashing = function()
      return self:isFlashing()
    end
  end
  backend:start(self:sink())
  return self
end

--- @return table
function Serial:sink()
  return {
    attach = function(info)
      self.connected = true
      self.reader:reset()
      self.dispatcher:push('connect', info)
    end,
    detach = function()
      self.connected = false
      self.reader:reset()
      self.dispatcher:push('disconnect')
    end,
    bytes = function(chunk)
      self:receive(chunk)
    end,
  }
end

--- Record something that failed outside a handler
--- @param err string?
function Serial:fault(err)
  if not err then return end
  self.faults[#self.faults + 1] = { env = 'serial', err = err }
end

--- Raw chunk first, then the lines it completed
--- @param chunk string
function Serial:receive(chunk)
  self.dispatcher:push('bytes', chunk)
  local lines, err = self.reader:feed(chunk)
  for _, l in ipairs(lines) do
    self.dispatcher:push('line', l)
  end
  self:fault(err)
end

--- The environment's compy.serial table. Handlers are its
--- fields, assigned by the code running there: onConnect,
--- onDisconnect, onBytes, onLine, and onTick, called every
--- update with the seconds since the last, after that
--- update's bytes, so a wait on the board can end when it
--- stops answering. send, reset and isConnected live in
--- the same table. Delivery reads the current field value;
--- a field left nil means nothing is delivered.
--- @param env SerialEnv
--- @return table
function Serial:table_for(env)
  return self.dispatcher:table_for(env)
end

--- Sent as given: the terminator, if the other end wants
--- one, belongs to the caller
--- @param line string
--- @return boolean? ok
--- @return string? err
function Serial:send(line)
  if not self.connected then
    return nil, 'no device connected'
  end
  -- the board is halted, and what waits would reach the
  -- new program as lines typed into it
  if self.job then return nil, FLASHING end
  return self.backend:send(line)
end

--- What was sent and has not left yet goes: the program that
--- sent it has ended, or the board is about to take new
--- firmware. Either way it would reach the board where it no
--- longer makes sense, as lines typed into a fresh REPL.
function Serial:drop()
  self.backend:drop()
end

--- The board restarts, as its reset button makes it: the way
--- back from a board that no longer reads what it is sent.
--- What waits to be sent goes first, and so do the line it
--- was in the middle of and what the console held back of
--- it, or they would run into its greeting.
--- @return boolean? ok
--- @return string? err
function Serial:reset()
  if self.job then return nil, FLASHING end
  self:drop()
  self.reader:reset()
  self.echo:clear()
  return self.backend:reset()
end

--- The board runs the file it took: what came in from the
--- old program, a line it was in the middle of or one it was
--- passing over as too long, and what the console held back
--- of it, go, as for a reset, so the new program's first line
--- is its own
function Serial:restarted()
  self.reader:reset()
  self.echo:clear()
end

--- @return boolean
function Serial:isConnected()
  return self.connected
end

--- A running program speaks for the board, so the console
--- stops listening while it does — otherwise both print what
--- arrives and every answer is shown twice.
function Serial:programStarted()
  self.dispatcher:suspend_env('console')
  self.echo:off()
end

--- The program's top-level code has finished without taking
--- the frame: nothing speaks for the board any more, so the
--- console listens again. Handlers the program set stay —
--- it has not stopped, it is only idle.
function Serial:programIdle()
  self.dispatcher:resume_env('console')
end

--- Stopped, but continue() may follow
function Serial:programPaused()
  self.dispatcher:suspend_env('program')
end

function Serial:programContinued()
  self.dispatcher:resume_env('program')
end

--- Stopped for good
function Serial:programEnded()
  self.dispatcher:resume_env('program')
  self.dispatcher:clear_env('program')
  self.dispatcher:resume_env('console')
end

local function clock()
  if love and love.timer then return love.timer.getTime() end
  return os.clock()
end

local NOT_CONNECTED = 'No micro:bit is plugged in. Plug the'
    .. ' micro:bit into the Compy with its USB cable, then try'
    .. ' again.'
local PERMISSION = 'The Compy asked whether it may use the'
    .. ' micro:bit. If the question is on the screen, answer it;'
    .. ' if it is gone, unplug the micro:bit and plug it back in'
    .. ' to be asked again. Then try again.'
local NOT_OPENED = 'The micro:bit is plugged in, but the Compy'
    .. ' could not reach it. Unplug it, plug it back in, then'
    .. ' try again.'
local MAINTENANCE = 'The micro:bit started in maintenance'
    .. ' mode, because its reset button was held as it was'
    .. ' plugged in. Unplug it, then plug it back in without'
    .. ' holding the button.'
local NO_FILE = 'There is no file to send.'
local CUT_SHORT = 'The file is cut short: its last line is'
    .. ' missing. Get the file again, then send it once more.'
local UNIVERSAL = 'This file holds programs for both'
    .. ' micro:bit versions, and the Compy sends only a file'
    .. ' made for a micro:bit V2 alone. Put it on the micro:bit'
    .. ' from a computer instead, or, if the editor that made it'
    .. ' can, save it for a micro:bit V2 only.'
local AGAIN = ' Get the file again, then send it once more.'
local EARLY_END = 'The file is damaged: more follows its last'
    .. ' line.' .. AGAIN
local DAMAGED = 'The file is damaged: some of its lines are'
    .. ' broken.' .. AGAIN
local OVERLAP = 'The file is damaged: it puts two different'
    .. ' things in the same place.' .. AGAIN
local EMPTY = 'The file holds no program.' .. AGAIN
local TOO_SMALL = 'The file holds too little to be a program'
    .. ' for the micro:bit. Use a file with a whole micro:bit'
    .. ' program in it.'
local OUTSIDE = 'This file is not made for a micro:bit V2: it'
    .. ' puts part of itself where a micro:bit V2 keeps no'
    .. ' program. Use a file made for a micro:bit V2.'
local INTERFACE = 'This file is software for the micro:bit\'s'
    .. ' USB chip, which the Compy does not change. Use a'
    .. ' program made for a micro:bit V2.'
local INTERNAL = 'The Compy could not read the file, through'
    .. ' a fault of its own. Send the file again.'
local FAULTS = {
  ['cut short'] = CUT_SHORT, universal = UNIVERSAL,
  ['early end'] = EARLY_END, damaged = DAMAGED,
  overlap = OVERLAP, empty = EMPTY, outside = OUTSIDE,
  ['too small'] = TOO_SMALL,
  interface = INTERFACE,
  internal = INTERNAL,
}
local UNPLUGGED = 'The micro:bit was unplugged before the'
    .. ' file went to it. Plug it back in, then send the file'
    .. ' again.'
local NOT_READY = 'The Compy cannot send files to this micro:bit'
    .. ' yet. Unplug it, plug it back in, then try again.'
local NO_FLASHING = 'This micro:bit cannot take files from the'
    .. ' Compy. Put the file on it from a computer instead.'

--- Put a hex file on the board through its interface chip,
--- without its drive. The file is read first and written
--- afresh in the shape the chip reads right (Dap.prepare), so
--- a damaged one never reaches the board. Returns at once:
--- the reading and then the flash run a share per update,
--- and say gives the progress and the verdict, a damaged
--- file's included. on, when given, hears the file read and
--- the sending begin (DapPrepare.new). Tests may set
--- self.clock to the chip's time.
--- @param data string
--- @param say function
--- @param on table?
--- @return boolean? ok
--- @return string? err in plain words
function Serial:flash(data, say, on)
  if self.job then return nil, FLASHING end
  if not self.connected then
    local why = self.backend.absence and self.backend:absence()
    if why == 'maintenance mode' then return nil, MAINTENANCE end
    if why == 'permission' then return nil, PERMISSION end
    if why then return nil, NOT_OPENED end
    return nil, NOT_CONNECTED
  end
  if type(data) ~= 'string' or data == '' then
    return nil, NO_FILE
  end
  local link, err = self.backend:dap()
  if not link then
    Dap.log('flash refused: ' .. tostring(err))
    return nil, self:cannot(err)
  end
  -- the board restarts with the new firmware, and what was
  -- queued for the old one would be typed into its new REPL
  self:drop()
  -- a link opened since then does not know
  if self.wiped then link.wiped = true end
  self.job = DapPrepare.new(data, say, Dap.log,
    self.clock or clock, on, link.wiped)
  return true
end

--- The file is read: it goes to the board, or the person
--- hears why not
--- @param prep DapPrepare
function Serial:prepared(prep)
  self.job = nil
  if prep.state == 'failed' then
    if prep.why then
      prep.say(FAULTS[prep.why] or DAMAGED)
    end
    return
  end
  if not self.connected then
    prep.say(UNPLUGGED)
    return
  end
  local link, err = self.backend:dap()
  if not link then
    Dap.log('flash refused: ' .. tostring(err))
    prep.say(self:cannot(err))
    return
  end
  self.job = DapFlash.new(prep.text, link, prep.say, Dap.log,
    self.clock or clock, function()
      DapPrepare.tell(Dap.log, prep.on.sending)
    end)
end

--- Words for a board the Compy cannot flash: a replug helps
--- when the drive was not taken, not when the board has no
--- way to take a file this way
--- @param err string? the backend's reason
--- @return string
function Serial:cannot(err)
  if err ~= 'no CMSIS-DAP interface' then return NOT_READY end
  local id = self.backend.boardId and self.backend:boardId()
  if Dap.boardVersion(id or '') == 'V1' then
    return Dap.V1_BOARD
  end
  return NO_FLASHING
end

--- @return boolean
function Serial:isFlashing()
  return self.job ~= nil
end

--- What the board's chip said about itself, once it has
--- @return table? info { id, firmware }
function Serial:board()
  return self.connected and self.backend:board() or nil
end

--- Call once per update loop
--- @return table[] errors
--- @param dt number
function Serial:update(dt)
  local job = self.job
  local preparing = job ~= nil
      and getmetatable(job) == DapPrepare
  -- a board taking a file is halted and says nothing: the
  -- backend need not wait on its serial output
  self:fault(self.backend:poll(job ~= nil and not preparing))
  if preparing then
    if not self.connected then
      job:abandon()
      self.job = nil
      job.say(UNPLUGGED)
    elseif job:step(dt) ~= 'running' then
      self:prepared(job)
    end
  elseif job and job:step(dt) ~= 'running' then
    self.job = nil
    self:settled(job)
    if job.state == 'done' then self:restarted() end
  end
  self.echo:tick(dt)
  self.dispatcher:push('tick', dt)
  local errors = self.dispatcher:pump()
  for _, f in ipairs(self.faults) do
    errors[#errors + 1] = f
  end
  self.faults = {}
  return errors
end

--- The longest a stop waits for the chip to close a stream
--- a flash left open
local STOP_S = 1
local CLOSING = 'The Compy was being closed while it sent the'
    .. ' file. Send the file again.'

--- End a flash under way now: its stream is closed, waiting
--- at most STOP_S, and the verdict says why. The port stays
--- open.
function Serial:abandon()
  local job = self.job
  if job and job:abandon(STOP_S, CLOSING) == true then
    self:restarted()
  end
  if job then self:settled(job) end
  self.job = nil
end

--- A flash has ended: whether it may have left the board
--- without its program is kept past the link
--- @param job table
function Serial:settled(job)
  if job.link then self.wiped = job.link.wiped == true end
end

local STOPPED_READING = 'The Compy stopped before the file went'
    .. ' to the micro:bit, which keeps its program. Send the file'
    .. ' again once the Compy is back.'
local STOPPED_GONE = 'The Compy stopped before the file went to'
    .. ' the micro:bit. ' .. DapFlash.GONE .. ' Send the file'
    .. ' again once the Compy is back.'
local CUT = 'A file was going to the micro:bit, and it did not'
    .. ' take it: the Compy stopped. Send the file again once'
    .. ' the Compy is back.'

--- Let the board go. A flash under way stops, its stream
--- closed, waiting at most STOP_S.
--- @return string? cut the words for a flash that was cut
---   off, for whoever shows them
function Serial:stop()
  local cut
  if self.job then
    if getmetatable(self.job) == DapPrepare then
      cut = self.job:erased() and STOPPED_GONE or STOPPED_READING
      self.job:abandon(STOP_S)
    elseif self.job:abandon(STOP_S) then
      cut = DapFlash.TOOK
    else
      -- the answers the stop took in say where the chip was
      cut = CUT
      if self.job:erased() then
        cut = cut .. ' ' .. DapFlash.GONE
      end
    end
    self:settled(self.job)
  end
  self.job = nil
  self.backend:stop()
  self.connected = false
  return cut
end
