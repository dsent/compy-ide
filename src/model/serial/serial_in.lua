--- What the board says on its serial port, read by transfers
--- kept in the kernel.
---
--- The interface chip holds 512 bytes of the board's output
--- and drops what comes on top (DAPLink nrf52820 uart.c,
--- BUFFER_SIZE), and the board says up to 11.5 KB a second:
--- the chip must be read every 44 ms. A read once a frame,
--- about every 60 ms while output scrolls on a Compy, lost
--- lines. Transfers posted to the kernel are answered by the
--- USB host between frames, and wait there, data and all,
--- until the next poll takes them and posts them again. The
--- chip sends what it has about once a millisecond, a packet
--- a transfer, so COUNT transfers last COUNT ms of steady
--- output between two polls.

--- @class SerialIn
--- @field new function
SerialIn = {}
SerialIn.__index = SerialIn

SerialIn.COUNT = 512
--- The endpoint's packet: a transfer longer than a packet
--- would keep a full packet back until the next one came
SerialIn.SIZE = 64

--- @param io table submit(endpoint, size), reap(); see Usbfs
--- @param endpoint integer the bulk-in endpoint's address
--- @param log function
--- @return SerialIn
function SerialIn.new(io, endpoint, log)
  local self = setmetatable({}, SerialIn)
  self.io = io
  self.endpoint = endpoint
  self.log = log
  self.posted = 0
  self.most = 0
  return self
end

--- Post the transfers
--- @return boolean? ok
--- @return string? err
function SerialIn:start()
  while self.posted < SerialIn.COUNT do
    local ok, err = self.io:submit(self.endpoint, SerialIn.SIZE)
    if not ok then
      self:stop(err)
      return nil, err
    end
    self.posted = self.posted + 1
  end
  return true
end

--- No more transfers are posted. Those in the kernel are
--- still taken: the board's output goes to them first.
--- @param why string
function SerialIn:stop(why)
  if self.dead then return end
  self.dead = why
  self.log('serial reads stopped: ' .. why)
end

--- What came since the last take; each transfer taken is
--- posted again until the reads stop. Nil once they have
--- stopped and none is left in the kernel.
--- @return string? data
function SerialIn:take()
  if self.dead and self.posted == 0 then return end
  local parts, came = {}, 0
  while true do
    local done, err = self.io:reap()
    if err then
      self:stop(err)
      self.posted = 0
      break
    end
    if not done then break end
    came = came + 1
    self.posted = self.posted - 1
    if done.status ~= 0 then
      -- not posted again: one the kernel fails at once would
      -- come straight back, poll after poll
      self.failed = (self.failed or 0) + 1
      if self.failed == 1 then
        self.log('serial read status ' .. done.status)
      end
      if self.posted == 0 then
        self:stop(string.format('%d reads failed, the last'
          .. ' with status %d', self.failed, done.status))
      end
    else
      if done.data then parts[#parts + 1] = done.data end
      if not self.dead then
        local ok, why = self.io:submit(self.endpoint,
          SerialIn.SIZE)
        if ok then
          self.posted = self.posted + 1
        else
          self:stop(why)
        end
      end
    end
  end
  self:measure(came)
  return table.concat(parts)
end

--- Says how many transfers came back between two polls, each
--- time that doubles, and the first time all did: then the
--- chip may have dropped output
--- @param came integer
function SerialIn:measure(came)
  if came >= SerialIn.COUNT then
    self.overruns = (self.overruns or 0) + 1
    if self.overruns == 1 then
      self.log(string.format('all %d serial reads came back'
        .. ' between two polls: output may have been lost',
        SerialIn.COUNT))
    end
  elseif came >= 2 * math.max(self.most, 8) then
    self.most = came
    self.log(string.format('%d serial reads came back between'
      .. ' two polls, of %d', came, SerialIn.COUNT))
  end
end
