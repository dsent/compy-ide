require('model.serial.dap')

--- Commands to the micro:bit's interface chip, several in
--- flight, each reply handed to the command it answers.
---
--- The chip runs a command as its packet arrives and queues
--- the reply until the host reads it; replies come back in
--- the order the commands went. Its queue holds
--- DAP_PACKET_COUNT replies, 5 on the KL27 of a V2.00 board
--- and 8 on the nRF52820 of a V2.2, and a command that
--- arrives when the queue is full is dropped without a word
--- (DAPLink usbd_bulk.c and DAP_queue.c). So at most DEPTH
--- commands, fewer than 5, are unanswered at any time; each
--- has a reply transfer posted for it, which the kernel
--- keeps, however late the reply comes.
---
--- A reply that does not answer the oldest command is left
--- over from before this connection (the chip keeps unread
--- replies across a closed connection) and is passed over.
--- Those replies still fill the chip's queue. So the link
--- starts by draining it: DRAIN_POSTS reply transfers go out
--- with no command, and whatever they bring is passed over,
--- until DRAIN_S go by without a reply. Then one command goes
--- alone, SYNC, which nothing else sends: once its reply is
--- back, everything left from before has come out ahead of
--- it, and the full DEPTH is open. Until then room() is 0.
---
--- The io is { submit(endpoint, data|size) -> ok, err,
--- reap() -> done | nil | nil, err, wait(ms) -> ready },
--- see Usbfs.

--- @class DapLink
--- @field new function
DapLink = {}
DapLink.__index = DapLink

DapLink.DEPTH = 4
--- ID_DAP_UART_GetLineCoding: it reads the serial line's
--- settings and changes nothing (DAP_vendor.c)
DapLink.SYNC = 0x81
--- More than the chip can hold: a queue of 8 on the
--- nRF52820 and the reply staged on its endpoint
DapLink.DRAIN_POSTS = 10
DapLink.DRAIN_S = 0.25

--- @param io table
--- @param epOut integer
--- @param epIn integer
--- @param log function
--- @param clock function seconds
--- @return DapLink
function DapLink.new(io, epOut, epIn, log, clock)
  local self = setmetatable({}, DapLink)
  self.io = io
  self.epOut = epOut
  self.epIn = epIn
  self.log = log
  self.clock = clock
  self.pending = {}
  self.posted = 0
  self.stale = 0
  self.replies = 0
  self.fault = nil
  self.synced = false
  return self
end

--- Drain what the chip kept from before; pump sends SYNC
--- once it has been quiet for DRAIN_S
function DapLink:start()
  self.draining = true
  self.quietSince = self.clock()
  for _ = 1, DapLink.DRAIN_POSTS do
    local ok, err = self.io:submit(self.epIn, Dap.PACKET)
    if not ok then return self:broke('drain: ' .. err) end
    self.posted = self.posted + 1
  end
end

--- Send SYNC once the chip has been quiet long enough
function DapLink:sync()
  if not self.draining or self.fault then return end
  if self.clock() - self.quietSince < DapLink.DRAIN_S then
    return
  end
  self.draining = false
  self:push(Dap.packet(DapLink.SYNC), function()
    self.synced = true
    self.log(string.format('in step with the chip, %d replies'
      .. ' from before passed over', self.stale))
  end)
end

--- @param why string
function DapLink:broke(why)
  if self.fault then return end
  self.fault = why
  self.log('link broken: ' .. why)
end

--- The link is dead: the port closed under it
function DapLink:kill()
  self:broke('device gone')
end

--- How many more commands may go now
--- @return integer
function DapLink:room()
  if self.fault or not self.synced then return 0 end
  return DapLink.DEPTH - #self.pending
end

--- @return integer
function DapLink:unanswered()
  return #self.pending
end

--- Seconds the oldest unanswered command has waited
--- @return number?
function DapLink:waited()
  local head = self.pending[1]
  return head and self.clock() - head.at
end

--- One reply transfer for every unanswered command
function DapLink:post()
  while not self.fault and self.posted < #self.pending do
    local ok, err = self.io:submit(self.epIn, Dap.PACKET)
    if not ok then return self:broke('post reply: ' .. err) end
    self.posted = self.posted + 1
  end
end

--- Send one request; its reply goes to onReply(raw)
--- @param packet string
--- @param onReply function
--- @return boolean? ok
--- @return string? err
function DapLink:send(packet, onReply)
  if self.fault then return nil, self.fault end
  if not self.synced then return nil, 'not in step yet' end
  if #self.pending >= DapLink.DEPTH then
    return nil, 'too many commands in flight'
  end
  return self:push(packet, onReply)
end

--- @param packet string
--- @param onReply function
--- @return boolean? ok
--- @return string? err
function DapLink:push(packet, onReply)
  if self.fault then return nil, self.fault end
  local ok, err = self.io:submit(self.epOut, packet)
  if not ok then
    self:broke('send: ' .. err)
    return nil, self.fault
  end
  self.pending[#self.pending + 1] = {
    cmd = packet:byte(1), at = self.clock(),
    onReply = onReply,
  }
  self:post()
  return true
end

--- @param raw string
function DapLink:reply(raw)
  local head = self.pending[1]
  if head and raw:byte(1) == head.cmd then
    table.remove(self.pending, 1)
    head.onReply(raw)
    return
  end
  self.stale = self.stale + 1
  self.log(string.format('passed over a reply to 0x%02X,'
    .. ' waiting for 0x%02X', raw:byte(1) or -1,
    head and head.cmd or -1))
end

--- @param done table
function DapLink:finished(done)
  if done.endpoint == self.epIn then
    self.posted = self.posted - 1
    if done.status ~= 0 then
      return self:broke('reply transfer status '
        .. done.status)
    end
    self.replies = self.replies + 1
    self.quietSince = self.clock()
    if done.actual > 0 then self:reply(done.data) end
    self:post()
  elseif done.status ~= 0 or done.actual ~= Dap.PACKET then
    self:broke(string.format('request transfer status %d,'
      .. ' %d of %d bytes', done.status, done.actual,
      Dap.PACKET))
  end
end

--- Take in every transfer that has finished. With ms > 0,
--- when no reply has come among them and a command waits
--- for one, wait up to ms, once, and take in what came.
--- @param ms integer?
--- @return integer replies taken
function DapLink:pump(ms)
  local before = self.replies
  local waited = false
  while not self.fault do
    local done, err = self.io:reap()
    if err then
      self:broke(err)
    elseif done then
      self:finished(done)
    elseif (ms or 0) > 0 and not waited
        and self.replies == before and #self.pending > 0 then
      waited = true
      if not self.io:wait(ms) then break end
    else
      break
    end
  end
  self:sync()
  self:post()
  return self.replies - before
end
