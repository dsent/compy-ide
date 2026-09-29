require('model.serial.dap')

--- A hex file read and written afresh for the chip
--- (Dap.prepare), a share per update, so the screen keeps
--- moving while a big file is read: each update gives it at
--- most BUDGET seconds.
---
--- It answers as a flash does (step, erased, abandon), and
--- comes before one: once step says 'ready', text holds the
--- file to send.

--- @class DapPrepare
DapPrepare = {}
DapPrepare.__index = DapPrepare

--- The most one update spends reading the file
DapPrepare.BUDGET = 0.020
--- Lines, pieces or records read between looks at the clock
DapPrepare.CHECK_EVERY = 16

--- @param data string the hex file as given
--- @param say function a line for the person
--- @param log function a line for the device log
--- @param clock function seconds
--- @return DapPrepare
function DapPrepare.new(data, say, log, clock)
  local self = setmetatable({}, DapPrepare)
  self.say = say
  self.log = log
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
  self.co = coroutine.create(function()
    return Dap.prepare(data, pause)
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
  local ok, text, why = coroutine.resume(self.co)
  local took = self.clock() - began
  self.spent = self.spent + took
  self.longest = math.max(self.longest, took)
  if coroutine.status(self.co) ~= 'dead' then
    return self.state
  end
  if not ok then
    self.log('preparing failed: ' .. tostring(text))
    text, why = nil, 'damaged'
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
