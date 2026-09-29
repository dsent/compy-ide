require('model.serial.line_reader')
require('model.serial.dispatcher')
require('model.serial.echo')
require('model.serial.dap_flash')

--- Backend contract:
---   backend:start(sink)  sink.attach(info), sink.detach(),
---                        sink.bytes(chunk)
---   backend:poll() -> nil | fault, one step per update
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
local MAINTENANCE = 'The micro:bit started in maintenance'
    .. ' mode, because its reset button was held as it was'
    .. ' plugged in. Unplug it, then plug it back in without'
    .. ' holding the button.'
local NO_FILE = 'There is no file to send.'
local CUT_SHORT = 'The file is cut short: its last line is'
    .. ' missing. Get the file again, then send it once more.'
local UNIVERSAL = 'This file holds programs for both'
    .. ' micro:bit versions, and the Compy sends only a file'
    .. ' made for a micro:bit V2.'
local EARLY_END = 'The file is damaged: it ends before its'
    .. ' last line. Get the file again, then send it once more.'
local NOT_READY = 'The Compy cannot send files to this micro:bit'
    .. ' yet. Unplug it, plug it back in, then try again.'

--- Put a hex file on the board through its interface chip,
--- without its drive. Returns at once; the work runs a share
--- per update, and say gives the progress and the verdict.
--- @param data string
--- @param say function
--- @return boolean? ok
--- @return string? err in plain words
function Serial:flash(data, say)
  if self.job then return nil, FLASHING end
  if not self.connected then
    local why = self.backend.absence and self.backend:absence()
    if why == 'maintenance mode' then return nil, MAINTENANCE end
    return nil, NOT_CONNECTED
  end
  if type(data) ~= 'string' or data == '' then
    return nil, NO_FILE
  end
  local fault = Dap.hexFault(data)
  if fault == 'cut short' then return nil, CUT_SHORT end
  if fault == 'universal' then return nil, UNIVERSAL end
  if fault then return nil, EARLY_END end
  local link, err = self.backend:dap()
  if not link then
    Dap.log('flash refused: ' .. tostring(err))
    return nil, NOT_READY
  end
  -- the board restarts with the new firmware, and what was
  -- queued for the old one would be typed into its new REPL
  self:drop()
  self.job = DapFlash.new(data, link, say, Dap.log,
    self.clock or clock, self.pace)
  return true
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
  self:fault(self.backend:poll())
  if self.job then
    if self.job:step(dt) ~= 'running' then self.job = nil end
  elseif dt and dt > 0 then
    -- the frame's pace without a flash, which a flash keeps
    self.pace = self.pace and (0.9 * self.pace + 0.1 * dt)
        or dt
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

function Serial:stop()
  if self.job then self.job:abandon(STOP_S) end
  self.job = nil
  self.backend:stop()
  self.connected = false
end
