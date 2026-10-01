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
--- An update may spend BUDGET on the flash: at most four
--- chunks can wait for the chip between updates, so the
--- flash moves mostly while an update waits on it, and the
--- screen goes down to about 30 frames a second while it
--- runs. A frame longer than FRAME_MAX halves the budget,
--- down to BUDGET_MIN; each shorter one gives back
--- STEP_UP, up to BUDGET. Once a second the log says where
--- the time went.
---
--- Every way out leaves the chip in a known state: nothing
--- open (a refusal before open, or a close after one that
--- was refused), or, when it stops answering, commands left
--- unanswered, which the next flash gives up before it
--- starts (DapLink:resync); unplugging the board resets the
--- chip when that is not enough.
---
--- say prints a line for the person; log writes a line for
--- the developer.

--- @class DapFlash
--- @field new function
--- @field step function
DapFlash = {}
DapFlash.__index = DapFlash

DapFlash.BUDGET = 0.020
DapFlash.BUDGET_MIN = 0.004
DapFlash.STEP_UP = 0.002
DapFlash.FRAME_MAX = 0.050
--- How often the log says where the time went
DapFlash.PACE_S = 1
--- How long the oldest command may wait for its reply.
--- Erasing and writing a page holds a reply back for the
--- time the chip takes to do it.
DapFlash.REPLY_S = 5
--- How often the share done is said
DapFlash.PROGRESS_S = 3

local AGAIN = 'Unplug the micro:bit, plug it back in, then'
    .. ' send the file again.'
--- A chip that missed one command answers the next flash once
--- the link is back in step: sending again comes first
local RETRY = 'Send the file again. If the micro:bit still does'
    .. ' not take it, unplug it, plug it back in, then send the'
    .. ' file once more.'
local NO_ANSWER = 'The micro:bit stopped answering. ' .. RETRY
--- The chip said it had the end of the file on a chunk before
--- the last, with all of them sent and as many replies
--- missing: one reply was lost, and each after it taken for
--- the chunk before its own. The whole file most likely went
--- on, but a command the chip dropped looks the same from its
--- replies, and nothing reads the board's memory back.
local UNSURE = 'The Compy cannot tell whether the micro:bit took'
    .. ' the file: one of the micro:bit\'s answers was lost. '
    .. RETRY
local NOTHING_SENT = 'It did not answer, and nothing went to it,'
    .. ' so it keeps its program. ' .. RETRY
local UNPLUGGED = 'The micro:bit was unplugged before it had'
    .. ' the whole file. Plug it back in, then send the file'
    .. ' again.'
local LOST = 'The Compy lost touch with the micro:bit. '
    .. AGAIN
local NOT_V2 = 'This board is not a micro:bit V2, and the file'
    .. ' is made for one. Plug in a micro:bit V2, then send the'
    .. ' file again.'
local GONE = 'Its old program may be gone until a file goes'
    .. ' onto it.'
DapFlash.GONE = GONE
local RESET_NOTE = 'If it does not start with the new program,'
    .. ' press its reset button, on the back next to the USB'
    .. ' socket.'

--- @param data string a hex Dap.prepare wrote
--- @param link DapLink
--- @param say function
--- @param log function
--- @param clock function seconds
--- @param sending function? called once the board is checked
---   and the stream is open, as the words for it are said
--- @return DapFlash
function DapFlash.new(data, link, say, log, clock, sending)
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
  self.answered = 0
  self.accepted = 0
  self.eraseChunk = Dap.eraseChunk(data)
  self.retried = false
  self.statuses = {}
  self.started = clock()
  self.phaseStarted = self.started
  self.told = self.started
  self.budget = DapFlash.BUDGET
  self.pace = { since = self.started, steps = 0, frame = 0,
    spent = 0, waited = 0, sent = 0 }
  self.state = 'running'
  self.sending = sending
  log(string.format('start: %d bytes, %d chunks of %d',
    #self.data, self.chunks, Dap.CHUNK))
  -- a flash before this one ended with commands unanswered
  link:resync()
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
    .. ' %d of %d bytes taken, %d of %d chunks accepted: %s',
    self.phase, self.clock() - self.started,
    math.min(self.acked * Dap.CHUNK, #self.data),
    #self.data, self.accepted, self.chunks, why))
  local lead = self.unsure and ''
      or 'The micro:bit did not take the file. '
  self.say(lead .. plain)
  self:mayBeGone()
end

--- The old program may be gone once the chip took the chunk
--- that starts it writing the board's memory
--- Refusals the chip makes before it erases, which it does in
--- flash_manager_init (flash_manager.c: erase_chip): an image
--- it will not take, 26 to 28 from flash_decoder_get_flash and
--- 29 from flash_decoder_validate_target_image, both before
--- flash_manager_init in flash_decoder_write. A bad record,
--- 21 or 22, may come after it: the hex reader hands on the
--- records before it in the same chunk (file_stream.c
--- write_hex), which can start the erase. 13 comes after the
--- erase (target_flash.c), and 23 to 25 are not raised in
--- 0257.
local BEFORE_ERASE = { [26] = true, [27] = true, [28] = true,
  [29] = true }

--- The old program may be gone once the chunk that carries the
--- erase point went to the chip: a micro:bit V2 erases the
--- whole chip within that write, whatever its reply, or none.
--- Not when the chip refused an earlier chunk, which leaves
--- its stream in error, nor when it refused that chunk before
--- reading its data through. A refusal names its chunk only
--- once every chunk sent has had its reply: replies carry no
--- number, and after a lost one each is taken for the chunk
--- before its own. A flash on the same link that ended so
--- leaves the program gone for all anyone knows, until one
--- succeeds (link.wiped).
--- @return boolean
function DapFlash:erased()
  if self.link.wiped then return true end
  if self.sent < self.eraseChunk then return false end
  local at = self.refusedAt
  if at and self.answered < self.sent then return true end
  if at and at < self.eraseChunk then return false end
  if at == self.eraseChunk and BEFORE_ERASE[self.refusedStatus]
  then
    return false
  end
  return true
end

function DapFlash:mayBeGone()
  if self:erased() then
    self.link.wiped = true
    self.say(GONE)
  end
end

--- The verdict after a close the chip reported done: the
--- board has the whole file. When the reset's reply does not
--- come, the note says what to do if the board does not
--- start with it.
--- @param note string?
function DapFlash:succeed(note)
  if self.state ~= 'running' then return end
  self.state = 'done'
  self.link.wiped = false
  self.log(string.format('DONE in %.3f s, %d bytes,'
    .. ' open %s, last write %s, close %s',
    self.clock() - self.started, #self.data,
    tostring(self.statuses.open),
    tostring(self.statuses.write),
    tostring(self.statuses.close)))
  self.say('The micro:bit took the file. It restarts with'
    .. ' it now.')
  if note then
    self.log('reset: ' .. note)
    self.say(RESET_NOTE)
  end
end

--- A refusal after the stream opened: the stream is closed
--- once every command in flight has its reply, then the
--- verdict comes. The writes still in flight after a refused
--- one meet a stream in its error state, which trips an
--- assert in the chip (file_stream.c); the chip keeps it and
--- shows ASSERT.TXT on its drive the next time the drive is
--- mounted. The flash itself is not harmed, and sending one
--- write at a time to avoid it would cost most of the speed.
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
    return self:fail(Dap.V1_BOARD, 'board is a V1')
  end
  if version ~= 'V2' then
    return self:fail(NOT_V2, 'board id not a micro:bit V2')
  end
  self:enter('open')
end

--- The board is checked and its stream open: the file is on
--- its way, said once, with whatever the caller hears then
function DapFlash:sayStart()
  if self.started_said then return end
  self.started_said = true
  -- two lines, each short enough for the console's width
  self.say('Sending the file to the micro:bit.')
  self.say('Its light blinks while it takes it.')
  if self.sending then
    local ok, err = pcall(self.sending)
    if not ok then
      self.log('sending hook failed: ' .. tostring(err))
    end
  end
end

--- @param status integer
function DapFlash:onOpen(status)
  self.statuses.open = self:name(status)
  self.log('open: ' .. self:name(status))
  if status == Dap.SUCCESS then
    -- a stop that took this answer in says how it ended, and
    -- nothing more goes: no start is said for it
    if not self.abandoning then self:sayStart() end
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
  self.mayBeOpen = true
  self:send(Dap.packet(Dap.OPEN, string.char(Dap.STREAM_HEX)),
    function(raw) self:onOpen(statusOf(Dap.OPEN, raw)) end)
end

function DapFlash:reopenPhase()
  if not self:ready(1) then return end
  self.mayBeOpen = false
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
  self.answered = i
  if self.phase ~= 'write' then return end
  self.acked = i
  self.statuses.write = self:name(status)
  local last = i == self.chunks
  if status == Dap.SUCCESS or status == Dap.DONE then
    self.accepted = i
  end
  if status == Dap.SUCCESS and not last then return end
  if last and status == Dap.DONE then
    self.log('write: end of file reported by the chip')
    return self:enter('close')
  end
  -- the chip reports the end of the file on the chunk that
  -- carries the end record, the last one (IntelHex.encode);
  -- without that report the chip has not read the whole file
  if last and status == Dap.SUCCESS then
    self.log('write: all bytes sent, no end of file reported')
    return self:refuse(Dap.plain(-1),
      'no end of file reported')
  end
  self.log(string.format('write %d of %d refused: %s', i,
    self.chunks, self:name(status)))
  self.refusedAt, self.refusedStatus = i, status
  self.unsure = self:lostReply(i, status)
  self:refuse(Dap.plain(status), 'write ' .. self:name(status))
end

--- Whether the chip's end of the file came booked to chunk i
--- because replies were lost: every chunk sent, and as many
--- replies missing as the chunks after i
--- @param i integer
--- @param status integer
--- @return boolean
function DapFlash:lostReply(i, status)
  local all = self.sent == self.chunks
  local missing = self.link:unanswered() == self.chunks - i
  return status == Dap.DONE and all and missing
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
  -- a stop waits for this answer itself (abandon)
  if self.stopping then
    self.stopping.close = status
    return
  end
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
  self.mayBeOpen = false
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
  self.mayBeOpen = false
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

--- ENOENT (killed), EPROTO and EILSEQ (a transfer cut off, the
--- first an unplug usually brings), ENODEV, ESHUTDOWN
local GONE_STATUS = { [-2] = true, [-19] = true, [-71] = true,
  [-84] = true, [-108] = true }

--- Did the board leave the bus? The link says so outright
--- when the port closed under it, the kernel through
--- ENODEV or ESHUTDOWN; otherwise the bus is asked, when the
--- link can.
--- @param fault string
--- @return boolean
function DapFlash:unplugged(fault)
  local status = tonumber(fault:match('status (%-%d+)'))
  local errno = tonumber(fault:match('errno (%d+)'))
  if fault == 'device gone' or errno == 19
      or GONE_STATUS[status] then
    return true
  end
  local present = self.link.present
  return present ~= nil and not present()
end

--- The link has broken, or the chip has gone quiet. Once the
--- chip has closed the stream as done, the board has the
--- whole file, and only the reset's reply is missing.
--- @return boolean ended
function DapFlash:watch()
  local fault = self.link.fault
  local waited = self.link:waited()
  if not self.link.synced then
    waited = self.clock() - self.started
  end
  local late = waited and waited > DapFlash.REPLY_S
  if not fault and not late then return false end
  if self.phase == 'reset' then
    self:succeed(fault and ('link: ' .. fault)
      or 'no reply to the reset')
    return true
  end
  if fault then
    self:fail(self:unplugged(fault) and UNPLUGGED or LOST,
      'link: ' .. fault)
  else
    -- replies carry no number: once one is lost, each reply
    -- after it is taken for the command before its own
    local n = self.link:unanswered()
    local kept = self.sent == 0 and not self.link.wiped
    local plain = kept and NOTHING_SENT or NO_ANSWER
    self:fail(self.unsure and UNSURE or plain,
      string.format('no reply in %d s, %d commands unanswered;'
        .. ' a lost reply makes the chunk numbers since it up'
        .. ' to %d low', DapFlash.REPLY_S, n, n))
  end
  return true
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
  if dt > DapFlash.FRAME_MAX then
    self.budget = math.max(DapFlash.BUDGET_MIN, self.budget / 2)
  else
    self.budget = math.min(DapFlash.BUDGET,
      self.budget + DapFlash.STEP_UP)
  end
end

--- Where the time went, once every PACE_S: the frame, the
--- flash's share of it, the part of that spent waiting on
--- the chip, chunks per update and per second, commands
--- still unanswered
--- @param dt number?
--- @param spent number
--- @param waited number
--- @param sent integer
function DapFlash:account(dt, spent, waited, sent)
  local p = self.pace
  p.steps = p.steps + 1
  p.frame = p.frame + (dt or 0)
  p.spent = p.spent + spent
  p.waited = p.waited + waited
  p.sent = p.sent + sent
  local now = self.clock()
  local span = now - p.since
  if span < DapFlash.PACE_S then return end
  self.log(string.format('pace: %d updates, frame %.1f ms,'
    .. ' flash %.1f ms of it (%.1f waiting), budget %.1f ms,'
    .. ' %.1f chunks/update, %.0f chunks/s, %d unanswered',
    p.steps, 1000 * p.frame / p.steps, 1000 * p.spent / p.steps,
    1000 * p.waited / p.steps, 1000 * self.budget,
    p.sent / p.steps, p.sent / span, self.link:unanswered()))
  self.pace = { since = now, steps = 0, frame = 0, spent = 0,
    waited = 0, sent = 0 }
end

--- A stop leaves the board unrestarted: the reset was never
--- sent, or its answer never came. A press restarts it, and
--- does no harm if it already has.
DapFlash.TOOK = 'The micro:bit took the file. Press its reset'
    .. ' button, on the back next to the USB socket, to start'
    .. ' the new program.'

--- A stop that finds the chip with the whole file: the flash
--- is done, and only the board's restart is left undone
--- @param plain string? said when given, as for a failure
--- @return boolean true
function DapFlash:tookOnStop(plain)
  self.state = 'done'
  self.link.wiped = false
  self.log(string.format('DONE on stop in phase %s after %.3f s,'
    .. ' close %s', self.phase, self.clock() - self.started,
    tostring(self.statuses.close)))
  if plain then self.say(DapFlash.TOOK) end
  return true
end

--- The flash stops where it is: close the stream, waiting at
--- most `seconds` in all, so the chip is not left with it
--- open. With `plain`, the verdict is said in those words;
--- without, only the log has it. A chip that already has the
--- whole file makes it a success, said in its own words.
--- @param seconds number
--- @param plain string?
--- @return boolean? took the board has the whole file
function DapFlash:abandon(seconds, plain)
  if self.state ~= 'running' then return end
  self.abandoning = true
  local link = self.link
  local deadline = self.clock() + seconds
  local function left()
    return math.floor((deadline - self.clock()) * 1000)
  end
  -- with a stream that may be open, the answers still on
  -- their way come first, within the same deadline, before
  -- any verdict: the last one's end of file moves the flash
  -- on to its close, and a refusal among them says where the
  -- chip stopped, which decides whether its old program may
  -- be gone
  if self.mayBeOpen then
    while self.state == 'running' and link:unanswered() > 0
        and not link.fault and left() > 0 do
      link:pump(left())
    end
  end
  if self.state ~= 'running' then
    return self.state == 'done' or nil
  end
  -- the chip has the whole file once it closed the stream as
  -- done (phase reset), or when it does so now: the end of
  -- the file was reported, and the close goes, or has gone,
  -- before the stop
  if self.phase == 'close' then
    self.stopping = {}
    if self.mayBeOpen then
      while link:room() == 0 and not link.fault and left() > 0 do
        link:pump(left())
      end
      -- the stream stays open for all anyone knows until a
      -- close has gone
      if link:send(Dap.packet(Dap.CLOSE), function(raw)
            self:closed(statusOf(Dap.CLOSE, raw))
          end) then
        self.mayBeOpen = false
      end
    end
    while self.stopping.close == nil and not self.mayBeOpen
        and not link.fault and left() > 0 do
      link:pump(left())
    end
    self.log('close on stop, end of file reported: '
      .. (self.stopping.close and self:name(self.stopping.close)
        or 'no reply'))
    if self.stopping.close == Dap.SUCCESS then
      -- the reset goes once, not waited for: the words still
      -- say to press the button, which does no harm
      if not link.fault and link:room() > 0
          and link:send(Dap.packet(Dap.RESET_TARGET),
            function() end) then
        self.log('reset on stop: sent')
      end
      return self:tookOnStop(plain)
    end
  elseif self.phase == 'reset' then
    return self:tookOnStop(plain)
  end
  if plain then
    self.say('The micro:bit did not take the file. ' .. plain)
    self:mayBeGone()
  end
  self.state = 'failed'
  if self:erased() then self.link.wiped = true end
  self.log(string.format('ABANDONED in phase %s, %d of %d'
    .. ' chunks answered', self.phase, self.acked, self.chunks))
  -- a close with no stream open trips an assert in the chip,
  -- which it keeps and shows on its drive; an OPEN goes only
  -- once the link is in step
  if not self.mayBeOpen then
    -- a close that went on the way here: its answer, if any,
    -- is already in the log
    if not self.stopping then
      self.log('close on stop: no stream open')
    elseif self.stopping.close == nil then
      self.log('close on stop: no reply')
    end
    return
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
  if self.updates then
    self:adapt(dt)
  else
    -- the frame before the first update read the file's
    -- last share, and says nothing about the frames to come
    self.updates = 0
    self.log(string.format('first update: the frame before it'
      .. ' took %.0f ms', 1000 * (dt or 0)))
  end
  self.updates = self.updates + 1
  local began = self.clock()
  local deadline = began + self.budget
  local sentBefore, waited = self.sent, 0
  while true do
    self.link:pump()
    if self.state ~= 'running' or self:watch() then break end
    PHASES[self.phase](self)
    if self.state ~= 'running' or self:watch() then break end
    local t = self.clock()
    local ms = math.floor((deadline - t) * 1000)
    if ms < 1 or self.link:unanswered() == 0 then break end
    self.link:pump(ms)
    waited = waited + self.clock() - t
  end
  self.lastSpent = self.clock() - began
  if self.state == 'running' then
    self:account(dt, self.lastSpent, waited,
      self.sent - sentBefore)
    self:progress()
  end
  return self.state
end
