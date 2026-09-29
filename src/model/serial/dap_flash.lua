require('model.serial.dap')

--- A hex file onto the micro:bit through its interface
--- chip's vendor commands, a share per update: ask the
--- board's unique id and the chip's firmware version, open a
--- hex stream, write the file in chunks, close, reset the
--- board. Writes go out as fast as the chip answers them, up
--- to DapLink.DEPTH in flight, for a bounded time each
--- update; between updates the kernel keeps the chunks in
--- flight moving, and the chip works through them.
---
--- The time an update may spend adapts to the frame: it
--- grows by STEP_UP while frames keep the pace they had
--- before the flash, and halves when a frame takes longer
--- than SLACK times that pace, so the screen keeps its frame
--- rate. A budget that made a frame late becomes a ceiling
--- just below it, which rises again by STEP_UP every
--- RELAX frames that keep the pace. It stays between
--- BUDGET_MIN and SHARE_MAX of the pace.
---
--- Every way out leaves the chip in a known state: nothing
--- open (a refusal before open, or a close after one that
--- was refused), or, when it stops answering, a message
--- that says to unplug the board, which resets the chip.
---
--- say prints a line for the person; log writes a line for
--- the developer.

--- @class DapFlash
--- @field new function
--- @field step function
DapFlash = {}
DapFlash.__index = DapFlash

DapFlash.BUDGET_MIN = 0.002
DapFlash.STEP_UP = 0.001
DapFlash.SLACK = 1.15
DapFlash.SHARE_MAX = 0.6
DapFlash.RELAX = 60
--- How long the oldest command may wait for its reply.
--- Erasing and writing a page holds a reply back for the
--- time the chip takes to do it.
DapFlash.REPLY_S = 5
--- How often the share done is said
DapFlash.PROGRESS_S = 3

local AGAIN = 'Unplug the micro:bit, plug it back in, then'
    .. ' send the file again.'
local NO_ANSWER = 'The micro:bit stopped answering. ' .. AGAIN
local UNPLUGGED = 'The micro:bit was unplugged before it had'
    .. ' the whole file. Plug it back in, then send the file'
    .. ' again.'
local LOST = 'The Compy lost touch with the micro:bit. '
    .. AGAIN
local OLD_BOARD = 'This is a micro:bit V1, and the file is made'
    .. ' for a micro:bit V2. Use a micro:bit V2, or a file'
    .. ' made for the V1.'
local NOT_V2 = 'This board is not a micro:bit V2, and the file'
    .. ' is made for one. Plug in a micro:bit V2, then send the'
    .. ' file again.'
local GONE = 'Its old program may be gone until a file goes'
    .. ' onto it.'

--- @param data string a hex Dap.prepare wrote
--- @param link DapLink
--- @param say function
--- @param log function
--- @param clock function seconds
--- @param pace number? seconds a frame took before the flash
--- @return DapFlash
function DapFlash.new(data, link, say, log, clock, pace)
  local self = setmetatable({}, DapFlash)
  self.data = data
  self.chunks = math.ceil(#self.data / Dap.CHUNK)
  self.link = link
  self.say = say
  self.log = log
  self.clock = clock
  self.phase = 'ask'
  self.sent = 0
  self.acked = 0
  self.accepted = 0
  self.retried = false
  self.statuses = {}
  self.started = clock()
  self.phaseStarted = self.started
  self.told = self.started
  self.pace = pace
  self.budget = DapFlash.BUDGET_MIN
  self.state = 'running'
  say('Sending the file to the micro:bit. Its light'
    .. ' blinks while it takes it.')
  log(string.format('start: %d bytes, %d chunks of %d',
    #self.data, self.chunks, Dap.CHUNK))
  return self
end

--- @param phase string
function DapFlash:enter(phase)
  local now = self.clock()
  self.log(string.format('phase %s done in %.3f s',
    self.phase, now - self.phaseStarted))
  self.phase = phase
  self.phaseStarted = now
  self.asked = false
end

--- @param code integer
--- @return string
function DapFlash:name(code)
  return Dap.statusName(code)
end

--- The verdict, said once
--- @param plain string
--- @param why string
function DapFlash:fail(plain, why)
  if self.state ~= 'running' then return end
  self.state = 'failed'
  self.log(string.format('FAILED in phase %s after %.3f s,'
    .. ' %d of %d bytes taken: %s', self.phase,
    self.clock() - self.started,
    math.min(self.acked * Dap.CHUNK, #self.data),
    #self.data, why))
  self.say('The micro:bit did not take the file. ' .. plain)
  if self.accepted > 0 then self.say(GONE) end
end

function DapFlash:succeed()
  self.state = 'done'
  self.log(string.format('DONE in %.3f s, %d bytes,'
    .. ' open %s, last write %s, close %s',
    self.clock() - self.started, #self.data,
    tostring(self.statuses.open),
    tostring(self.statuses.write),
    tostring(self.statuses.close)))
  self.say('The micro:bit took the file. It restarts with'
    .. ' it now.')
end

--- A refusal after the stream opened: the stream is closed
--- once every command in flight has its reply, then the
--- verdict comes
--- @param plain string
--- @param why string
function DapFlash:refuse(plain, why)
  self.refusal = { plain = plain, why = why }
  self:enter('unwind')
end

--- Send a command; a link that refuses it has broken, which
--- the next look at the link reports
--- @param packet string
--- @param onReply function
--- @return boolean
function DapFlash:send(packet, onReply)
  local function guarded(raw)
    if self.state == 'running' then onReply(raw) end
  end
  return self.link:send(packet, guarded) == true
end

--- The status byte of a reply; -1 when it has none
--- @param cmd integer
--- @param raw string
--- @return integer
local function statusOf(cmd, raw)
  return Dap.status(cmd, raw) or -1
end

--- Whether the phase may send n commands now: once per
--- phase, when the link has room for them
--- @param n integer
--- @return boolean
function DapFlash:ready(n)
  if self.asked or self.link:room() < n then return false end
  self.asked = true
  return true
end

function DapFlash:askPhase()
  if self.asked then
    if self.id and self.fwText then self:check() end
    return
  end
  if not self:ready(2) then return end
  self:send(Dap.packet(Dap.UNIQUE_ID), function(raw)
    self.id = Dap.text(Dap.UNIQUE_ID, raw) or ''
  end)
  self:send(Dap.packet(Dap.INFO, string.char(Dap.INFO_FIRMWARE)),
    function(raw)
      self.fwText = Dap.text(Dap.INFO, raw) or ''
    end)
end

--- The board, before anything is opened: a V2 only, since
--- the file is made for one, and any other board on the same
--- USB vendor id would take it and lose its own program
function DapFlash:check()
  local version = Dap.boardVersion(self.id)
  self.log(string.format('board %s (%s), interface firmware %s',
    self.id, tostring(version), self.fwText ~= ''
    and self.fwText or 'not said (before 0257)'))
  if version == 'V1' then
    return self:fail(OLD_BOARD, 'board is a V1')
  end
  if version ~= 'V2' then
    return self:fail(NOT_V2, 'board id not a micro:bit V2')
  end
  self:enter('open')
end

--- @param status integer
function DapFlash:onOpen(status)
  self.statuses.open = self:name(status)
  self.log('open: ' .. self:name(status))
  if status == Dap.SUCCESS then
    return self:enter('write')
  end
  if status == Dap.INTERNAL and not self.retried then
    self.retried = true
    self.log('open refused as busy: closing a stream left'
      .. ' open, then opening again')
    return self:enter('reopen')
  end
  -- a stream that failed to open is in its error state
  -- until it is closed
  self:refuse(Dap.plain(status), 'open ' .. self:name(status))
end

function DapFlash:openPhase()
  if not self:ready(1) then return end
  self:send(Dap.packet(Dap.OPEN, string.char(Dap.STREAM_HEX)),
    function(raw) self:onOpen(statusOf(Dap.OPEN, raw)) end)
end

function DapFlash:reopenPhase()
  if not self:ready(1) then return end
  self:send(Dap.packet(Dap.CLOSE), function(raw)
    self.log('close of the stream left open: '
      .. self:name(statusOf(Dap.CLOSE, raw)))
    self:enter('open')
  end)
end

--- The reply to chunk i
--- @param i integer
--- @param status integer
function DapFlash:wrote(i, status)
  if self.phase ~= 'write' then return end
  self.acked = i
  self.statuses.write = self:name(status)
  local last = i == self.chunks
  if status == Dap.SUCCESS then self.accepted = i end
  if status == Dap.SUCCESS and not last then return end
  if last and status == Dap.DONE then
    self.log('write: end of file reported by the chip')
    return self:enter('close')
  end
  if last and status == Dap.SUCCESS then
    self.log('write: all bytes sent, no end of file reported')
    return self:enter('close')
  end
  self.log(string.format('write %d of %d refused: %s', i,
    self.chunks, self:name(status)))
  self:refuse(Dap.plain(status), 'write ' .. self:name(status))
end

function DapFlash:writePhase()
  while self.sent < self.chunks and self.link:room() > 0 do
    local i = self.sent + 1
    local at = (i - 1) * Dap.CHUNK
    local chunk = self.data:sub(at + 1, at + Dap.CHUNK)
    if not self:send(Dap.writePacket(chunk), function(raw)
          self:wrote(i, statusOf(Dap.WRITE, raw))
        end) then
      return
    end
    self.sent = i
  end
end

--- @param status integer
function DapFlash:closed(status)
  self.statuses.close = self:name(status)
  self.log('close: ' .. self:name(status))
  if status ~= Dap.SUCCESS then
    return self:fail(Dap.plain(status),
      'close ' .. self:name(status))
  end
  self:enter('reset')
end

function DapFlash:closePhase()
  if self.link:unanswered() > 0 or not self:ready(1) then
    return
  end
  self:send(Dap.packet(Dap.CLOSE), function(raw)
    self:closed(statusOf(Dap.CLOSE, raw))
  end)
end

--- After a refusal: the chunks still in flight are answered
--- as refused too, then the stream is closed
function DapFlash:unwindPhase()
  if self.link:unanswered() > 0 or not self:ready(1) then
    return
  end
  self:send(Dap.packet(Dap.CLOSE), function(raw)
    self.log('close after refusal: '
      .. self:name(statusOf(Dap.CLOSE, raw)))
    local r = self.refusal
    self:fail(r.plain, r.why)
  end)
end

function DapFlash:resetPhase()
  if not self:ready(1) then return end
  self:send(Dap.packet(Dap.RESET_TARGET), function(raw)
    self.log('reset: reply ' .. statusOf(Dap.RESET_TARGET, raw))
    self:enter('done')
    self:succeed()
  end)
end

local PHASES = {
  ask = DapFlash.askPhase,
  open = DapFlash.openPhase,
  reopen = DapFlash.reopenPhase,
  write = DapFlash.writePhase,
  close = DapFlash.closePhase,
  unwind = DapFlash.unwindPhase,
  reset = DapFlash.resetPhase,
}

--- The link has broken, or the chip has gone quiet
--- @return boolean ended
function DapFlash:watch()
  local fault = self.link.fault
  if fault then
    self:fail(fault == 'device gone' and UNPLUGGED or LOST,
      'link: ' .. fault)
    return true
  end
  local waited = self.link:waited()
  if waited and waited > DapFlash.REPLY_S then
    self:fail(NO_ANSWER, string.format(
      'no reply in %d s, %d commands unanswered',
      DapFlash.REPLY_S, self.link:unanswered()))
    return true
  end
  return false
end

function DapFlash:progress()
  local now = self.clock()
  if now - self.told < DapFlash.PROGRESS_S then return end
  self.told = now
  if self.phase == 'write' then
    self.say(string.format('Sending to the micro:bit: %d%%'
      .. ' done.', math.floor(100 * self.acked / self.chunks)))
  end
end

--- The time this update may spend, from the last frame's
--- @param dt number? seconds
function DapFlash:adapt(dt)
  if not dt or dt <= 0 then return end
  self.pace = self.pace or dt
  local top = DapFlash.SHARE_MAX * self.pace
  if dt <= self.pace * DapFlash.SLACK then
    self.kept = (self.kept or 0) + 1
    if self.ceiling and self.kept % DapFlash.RELAX == 0 then
      self.ceiling = self.ceiling + DapFlash.STEP_UP
    end
    self.budget = math.min(self.budget + DapFlash.STEP_UP, top,
      self.ceiling or top)
  else
    self.ceiling = self.budget - DapFlash.STEP_UP
    self.kept = 0
    self.budget = self.budget / 2
  end
  self.budget = math.max(DapFlash.BUDGET_MIN, self.budget)
end

--- The IDE is stopping with the flash under way: close the
--- stream, waiting at most `seconds` in all, so the chip is
--- not left with it open. No verdict is said; the log has it.
--- @param seconds number
function DapFlash:abandon(seconds)
  if self.state ~= 'running' then return end
  self.state = 'failed'
  self.log(string.format('ABANDONED in phase %s, %d of %d'
    .. ' chunks answered', self.phase, self.acked, self.chunks))
  local link = self.link
  local deadline = self.clock() + seconds
  local function left()
    return math.floor((deadline - self.clock()) * 1000)
  end
  while link:room() == 0 and not link.fault and left() > 0 do
    link:pump(left())
  end
  local closed = false
  if link:send(Dap.packet(Dap.CLOSE), function(raw)
        closed = true
        self.log('close on stop: '
          .. self:name(statusOf(Dap.CLOSE, raw)))
      end) then
    while not closed and not link.fault and left() > 0 do
      link:pump(left())
    end
  end
  if not closed then self.log('close on stop: no reply') end
end

--- One update's share of the work: take in replies, send
--- what the phase allows, wait for replies while the budget
--- lasts
--- @param dt number? the last frame's seconds
--- @return string state running, done or failed
function DapFlash:step(dt)
  if self.state ~= 'running' then return self.state end
  self:adapt(dt)
  local began = self.clock()
  local deadline = began + self.budget
  while true do
    self.link:pump()
    if self.state ~= 'running' or self:watch() then break end
    PHASES[self.phase](self)
    if self.state ~= 'running' or self:watch() then break end
    local left = deadline - self.clock()
    local ms = math.floor(left * 1000)
    if ms < 1 or self.link:unanswered() == 0 then break end
    self.link:pump(ms)
  end
  self.lastSpent = self.clock() - began
  if self.state == 'running' then self:progress() end
  return self.state
end
