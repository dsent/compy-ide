--- A micro:bit interface chip and the USB bus to it, for
--- the flash tests. It answers as DAPLink 0257 does:
---
--- - a command runs as its packet arrives, and its reply
---   waits in a queue of DAP_PACKET_COUNT (5 on the KL27)
---   until a reply transfer reads it; a command that arrives
---   when the queue is full is dropped without a word
---   (usbd_bulk.c, DAP_queue.c);
--- - the stream is CLOSED, OPEN, END or ERROR, and open,
---   write and close answer as file_stream.c does;
--- - a write reports SUCCESS_DONE (19) on the chunk that
---   completes the end record, HEX_CKSUM (21) on a record
---   whose checksum is wrong, and INTERNAL (2) in any state
---   but OPEN.
---
--- Status numbers are written out here, not taken from the
--- code under test. Time is the test's: the chip serves one
--- command at a time, each for `latency` seconds, and a
--- write that completes a page of the board's memory (every
--- `page` writes) for `program` seconds more; wait(ms) moves
--- the clock on.

local M = {}

M.SUCCESS, M.INTERNAL, M.DONE, M.CKSUM = 0, 2, 19, 21

--- A hex text of n data records, then the end record
--- @param n integer
--- @return string
function M.hex(n)
  local out = {}
  for i = 1, n do
    local bytes = { 16, math.floor(i * 16 / 256) % 256,
      (i * 16) % 256, 0 }
    local body = ''
    for _, b in ipairs(bytes) do
      body = body .. string.format('%02X', b)
    end
    local sum = 16 + bytes[2] + bytes[3]
    for _ = 1, 16 do
      body = body .. 'AB'
      sum = sum + 0xAB
    end
    out[i] = ':' .. body .. string.format('%02X',
      (256 - sum % 256) % 256) .. '\r\n'
  end
  return table.concat(out) .. ':00000001FF\r\n'
end

--- Does a record's checksum hold?
--- @param rec string the hex digits after ':'
--- @return boolean
local function checks(rec)
  local sum = 0
  for i = 1, #rec - 1, 2 do
    sum = sum + tonumber(rec:sub(i, i + 1), 16)
  end
  return sum % 256 == 0
end

--- @param opts table? queue (5), latency (0), page,
---   program, id, firmware
--- @return table chip
function M.chip(opts)
  opts = opts or {}
  local c = {
    now = 0,
    queue = {},
    size = opts.queue or 5,
    latency = opts.latency or 0,
    id = opts.id or '9904000044444444444444444444444444444444',
    firmware = opts.firmware or '0257',
    stream = 'CLOSED',
    text = '',
    record = '',
    got = {},
    drops = 0,
    most = 0,
    written = '',
    silent = false,
    gone = false,
    over = {},
  }

  --- The parser's view of a chunk: whole records are checked
  --- as their last digit arrives
  --- @param chunk string
  --- @return integer status
  function c:parse(chunk)
    for ch in chunk:gmatch('.') do
      if ch == ':' then
        self.record = ''
      elseif ch ~= '\r' and ch ~= '\n' then
        self.record = self.record .. ch
        local len = tonumber(self.record:sub(1, 2), 16)
        if len and #self.record == (len + 5) * 2 then
          if not checks(self.record) then return 21 end
          if self.record:sub(7, 8) == '01' then return 19 end
          self.record = ''
        end
      end
    end
    return 0
  end

  --- @param packet string
  --- @return string? reply
  function c:run(packet)
    local cmd = packet:byte(1)
    local o = self.over[cmd]
    if o then
      local r = o(packet, self)
      if r ~= nil then return r end
    end
    if cmd == 0x80 then
      return string.char(cmd, #self.id) .. self.id
    elseif cmd == 0x00 then
      if packet:byte(2) == 9 and self.firmware ~= '' then
        local s = self.firmware .. '\0'
        return string.char(0, #s) .. s
      end
      return string.char(0, 0)
    elseif cmd == 0x8A then
      self.streamType = packet:byte(2)
      if self.stream ~= 'CLOSED' then
        return string.char(cmd, 2)
      end
      self.stream = 'OPEN'
      self.record = ''
      return string.char(cmd, 0)
    elseif cmd == 0x8C then
      if self.stream ~= 'OPEN' then
        return string.char(cmd, 2)
      end
      local chunk = packet:sub(3, 2 + packet:byte(2))
      self.written = self.written .. chunk
      local st = self:parse(chunk)
      if st == 19 then self.stream = 'END'
      elseif st ~= 0 then self.stream = 'ERROR' end
      return string.char(cmd, st)
    elseif cmd == 0x8B then
      if self.stream == 'CLOSED' then
        return string.char(cmd, 2)
      end
      self.stream = 'CLOSED'
      self.closes = (self.closes or 0) + 1
      return string.char(cmd, opts.closeStatus or 0)
    elseif cmd == 0x89 then
      self.resets = (self.resets or 0) + 1
      return string.char(cmd, 1)
    end
    return string.char(cmd, 0xFF)
  end

  --- A packet arrives on the out endpoint
  --- @param packet string
  function c:receive(packet)
    assert(#packet == 64, 'packet of ' .. #packet .. ' bytes')
    self.got[#self.got + 1] = packet:byte(1)
    if self.silent then return end
    if #self.queue >= self.size then
      self.drops = self.drops + 1
      return
    end
    local reply = self:run(packet)
    local cost = self.latency
    if opts.page and packet:byte(1) == 0x8C then
      self.writes = (self.writes or 0) + 1
      if self.writes % opts.page == 0 then
        cost = cost + (opts.program or 0)
      end
    end
    self.busy = math.max(self.now, self.busy or 0) + cost
    self.queue[#self.queue + 1] = {
      data = reply, ready = self.busy }
    self.most = math.max(self.most, #self.queue)
  end

  --- Put replies in the queue as if left from before
  --- @param raw string
  function c:leftover(raw)
    self.queue[#self.queue + 1] = { data = raw, ready = 0 }
  end

  --- @return string? reply the oldest one that is ready
  function c:take()
    local head = self.queue[1]
    if head and head.ready <= self.now then
      table.remove(self.queue, 1)
      return head.data
    end
  end

  return c
end

--- The kernel side: transfers as Usbfs sees them
--- @param chip table
--- @return table io submit, reap, wait
function M.bus(chip)
  local io = { ins = {}, done = {}, submits = 0, waits = 0 }

  function io:flow()
    while #self.ins > 0 do
      local r = chip:take()
      if not r then break end
      local u = table.remove(self.ins, 1)
      self.done[#self.done + 1] = { endpoint = u, status = 0,
        actual = #r, data = r }
    end
  end

  function io:submit(endpoint, data)
    self.submits = self.submits + 1
    if chip.gone then return nil, 'submit errno 19' end
    if type(data) == 'string' then
      chip:receive(data)
      self.done[#self.done + 1] = { endpoint = endpoint,
        status = chip.outStatus or 0,
        actual = chip.outShort or #data }
    else
      self.ins[#self.ins + 1] = endpoint
    end
    return true
  end

  function io:reap()
    if chip.reapError then return nil, chip.reapError end
    self:flow()
    return table.remove(self.done, 1)
  end

  --- As poll does: back as soon as a transfer finishes,
  --- or when ms have gone by
  function io:wait(ms)
    self.waits = self.waits + 1
    if #self.done > 0 then return true end
    local limit = chip.now + ms / 1000
    local head = chip.queue[1]
    if #self.ins > 0 and head and head.ready <= limit then
      chip.now = math.max(chip.now, head.ready)
    else
      chip.now = limit
    end
    self:flow()
    return #self.done > 0
  end

  return io
end

return M
