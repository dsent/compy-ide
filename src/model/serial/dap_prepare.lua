require('model.serial.dap')

--- A hex file read and written afresh for the chip
--- (Dap.prepare), a share per update, so the screen keeps
--- moving while a big file is read: each update gives it at
--- most BUDGET seconds.
---
--- It answers as a flash does (step, erased, abandon), and
--- comes before one: once step says 'ready', text holds the
--- file to send.
---
--- on, when given, holds what the caller wants to hear:
--- on.read(image) once the file passed every check, with its
--- runs { at, data }, and on.sending() as the flash begins.
--- A fault in either is logged and does not stop the flash.

--- @class DapPrepare
DapPrepare = {}
DapPrepare.__index = DapPrepare

--- The most one update spends reading the file
DapPrepare.BUDGET = 0.020
--- Lines, pieces or records read between looks at the clock
DapPrepare.CHECK_EVERY = 16

--- A call to what the caller gave, whose fault is logged
--- @param log function
--- @param fn function?
local function tell(log, fn, ...)
  if not fn then return end
  local ok, err = pcall(fn, ...)
  if not ok then
    log('what was asked to hear about the flash failed: '
      .. tostring(err))
  end
end
DapPrepare.tell = tell

--- @param data string the hex file as given
--- @param say function a line for the person
--- @param log function a line for the device log
--- @param clock function seconds
--- @param on table? { read = fn(image), sending = fn() }
--- @return DapPrepare
function DapPrepare.new(data, say, log, clock, on)
  local self = setmetatable({}, DapPrepare)
  self.say = say
  self.log = log
  self.on = on or {}
  self.clock = clock
  self.state = 'running'
  self.updates = 0
  self.spent = 0
  self.longest = 0
  local n = 0
  local function pause()
    n = n + 1
    if n % DapPrepare.CHECK_EVERY == 0
        and clock() >= self.deadline then
      coroutine.yield()
    end
  end
  local function seen(image)
    tell(log, self.on.read, image)
  end
  -- a fault of the Compy's own, not of the file, comes back
  -- with where it was raised
  self.co = coroutine.create(function()
    local ok, text, why = xpcall(function()
      return Dap.prepare(data, pause, seen)
    end, debug.traceback)
    if not ok then return nil, 'internal', text end
    return text, why
  end)
  say('Reading the file before it goes to the micro:bit.')
  return self
end

--- One update's share of the reading
--- @param dt number? the last frame's seconds
--- @return string state running, ready or failed
function DapPrepare:step(dt)
  if self.state ~= 'running' then return self.state end
  if self.updates == 0 then
    -- the frame that asked for the flash, and read the file
    -- from the card
    self.log(string.format('preparing: the frame that asked'
      .. ' took %.0f ms', 1000 * (dt or 0)))
  end
  self.updates = self.updates + 1
  local began = self.clock()
  self.deadline = began + DapPrepare.BUDGET
  local ok, text, why, trace = coroutine.resume(self.co)
  local took = self.clock() - began
  self.spent = self.spent + took
  self.longest = math.max(self.longest, took)
  if coroutine.status(self.co) ~= 'dead' then
    return self.state
  end
  if not ok then
    text, why, trace = nil, 'internal', text
  end
  if why == 'internal' then
    self.log('preparing failed: ' .. tostring(trace))
  end
  self.log(string.format('file prepared in %.0f ms over %d'
    .. ' updates, the longest %.0f ms: %s',
    1000 * self.spent, self.updates, 1000 * self.longest,
    why or (#text .. ' bytes')))
  if not text then
    self.why = why
    self.state = 'failed'
    return self.state
  end
  self.text = text
  self.state = 'ready'
  return self.state
end

--- Nothing has gone to the board yet
--- @return boolean
function DapPrepare:erased()
  return false
end

--- Stop reading; the board was never touched
--- @param _ number? seconds, as for a flash
--- @param plain string? words for the person
function DapPrepare:abandon(_, plain)
  if self.state ~= 'running' then return end
  self.state = 'failed'
  if plain then
    self.say('The micro:bit did not take the file. ' .. plain)
  end
  self.log('ABANDONED while preparing the file')
end
