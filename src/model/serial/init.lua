require('model.serial.line_reader')
require('model.serial.dispatcher')
require('model.serial.echo')
require('model.serial.dap_flash')

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

local FLASHING = 'The micro:bit is taking a file. Wait until'
    .. ' the Compy says how it went.'

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
local PERMISSION = 'The Compy is asking whether it may use the'
    .. ' micro:bit. Answer the question on the screen, then try'
    .. ' again.'
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
local FAULTS = {
  ['cut short'] = CUT_SHORT, universal = UNIVERSAL,
  ['early end'] = EARLY_END, damaged = DAMAGED,
  overlap = OVERLAP, empty = EMPTY, outside = OUTSIDE,
  ['too small'] = TOO_SMALL,
  interface = INTERFACE,
}
local NOT_READY = 'The Compy cannot send files to this micro:bit'
    .. ' yet. Unplug it, plug it back in, then try again.'
local NO_FLASHING = 'This micro:bit cannot take files from the'
    .. ' Compy. Put the file on it from a computer instead.'

--- Put a hex file on the board through its interface chip,
--- without its drive. The file is read first and written
--- afresh in the shape the chip reads right (Dap.prepare), so
--- a damaged one never reaches the board. Returns at once; the work runs a share
--- per update, and say gives the progress and the verdict.
--- Tests may set self.clock to the chip's time.
--- @param data string
--- @param say function
--- @return boolean? ok
--- @return string? err in plain words
function Serial:flash(data, say)
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
  local t0 = clock()
  local text, fault = Dap.prepare(data)
  Dap.log(string.format('file prepared in %.0f ms: %s',
    1000 * (clock() - t0), fault or (#text .. ' bytes')))
  if not text then return nil, FAULTS[fault] or DAMAGED end
  local link, err = self.backend:dap()
  if not link then
    Dap.log('flash refused: ' .. tostring(err))
    return nil, self:cannot(err)
  end
  -- the board restarts with the new firmware, and what was
  -- queued for the old one would be typed into its new REPL
  self:drop()
  self.job = DapFlash.new(text, link, say, Dap.log,
    self.clock or clock)
  return true
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
  -- a board taking a file is halted and says nothing: the
  -- backend need not wait on its serial output
  self:fault(self.backend:poll(self.job ~= nil))
  if self.job and self.job:step(dt) ~= 'running' then
    self.job = nil
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
  if self.job then self.job:abandon(STOP_S, CLOSING) end
  self.job = nil
end

function Serial:stop()
  if self.job then self.job:abandon(STOP_S) end
  self.job = nil
  self.backend:stop()
  self.connected = false
end
