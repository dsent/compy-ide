--- Putting a hex file on the micro:bit through its interface
--- chip: what goes down the cable is a protocol, and a wrong
--- byte in it, a lost reply or a command the chip drops
--- erases the board, so the packets, the pipelining, the
--- reply matching and every way out are held here against a
--- chip that answers as the DAPLink 0257 source does
--- (tests/helpers/fake_daplink.lua).

-- LÖVE brings utf8, which the echo in Serial loads; nothing
-- here reaches it.
package.preload['utf8'] = package.preload['utf8']
    or function() return { len = function(s) return #s end } end

require('model.serial.dap')
require('model.serial.dap_link')
require('model.serial.dap_flash')
require('model.serial.usbfs')
require('model.serial.init')
require('model.serial.backend_fake')
local F = require('tests.helpers.fake_daplink')
local ffi = require('ffi')

local EP_OUT, EP_IN = 0x05, 0x85

local function quiet() end

--- A link to a fake chip, on the chip's clock, in step
--- with it unless told otherwise
local function linkTo(chip, logged, unsynced)
  local log = logged and function(l) logged[#logged + 1] = l end
      or quiet
  local io = F.bus(chip)
  local link = DapLink.new(io, EP_OUT, EP_IN, log,
    function() return chip.now end)
  if not unsynced then
    link:start()
    local t = chip.now
    while not link.synced and not link.fault do
      link:pump(1)
      chip.now = chip.now + 0.01
      assert.is_true(chip.now - t < 10, 'link never in step')
    end
    chip.got = {}
  end
  return link, io
end

--- A flash of data onto the chip
local function job(data, chip)
  local said, logged = {}, {}
  local link, io = linkTo(chip, logged)
  local j = DapFlash.new(data, link,
    function(l) said[#said + 1] = l end,
    function(l) logged[#logged + 1] = l end,
    function() return chip.now end)
  return j, said, logged, link, io
end

--- Steps at 30 updates a second until the flash ends; the
--- chip's clock moves on between updates, as the kernel's
--- transfers do
local function run(j, chip, limit)
  local steps = 0
  while j:step(1 / 30) == 'running' do
    steps = steps + 1
    chip.now = chip.now + 1 / 30
    assert.is_true(steps < (limit or 20000), 'flash never ended')
  end
  return j.state, steps
end

local function joined(t) return table.concat(t, '\n') end

local function count(list, cmd)
  local n = 0
  for _, c in ipairs(list) do if c == cmd then n = n + 1 end end
  return n
end

describe('Dap packets', function()
  it('are 64 bytes: command, payload, zeros', function()
    local p = Dap.packet(Dap.OPEN, string.char(1))
    assert.same(64, #p)
    assert.same(0x8A, p:byte(1))
    assert.same(1, p:byte(2))
    assert.same(string.rep('\0', 62), p:sub(3))
  end)

  it('carry 62 bytes of file at most in a write', function()
    local p = Dap.writePacket(string.rep('x', 62))
    assert.same(64, #p)
    assert.same(0x8C, p:byte(1))
    assert.same(62, p:byte(2))
    assert.has_error(function()
      Dap.writePacket(string.rep('x', 63))
    end)
  end)

  it('take the status from a reply to the same command',
    function()
      assert.same(19, Dap.status(0x8C, string.char(0x8C, 19)))
      local st, err = Dap.status(0x8C, string.char(0x8A, 0))
      assert.is_nil(st)
      assert.truthy(err:find('0x8A', 1, true))
    end)

  it('read the unique id and the firmware version', function()
    assert.same('9904', Dap.text(0x80, string.char(0x80, 4)
      .. '9904\0\0'))
    assert.same('0257', Dap.text(0x00, string.char(0, 5)
      .. '0257\0'))
  end)

  it('tell a V1 from a V2 by the board id', function()
    assert.same('V1', Dap.boardVersion('9900abc'))
    assert.same('V1', Dap.boardVersion('9901abc'))
    assert.same('V2', Dap.boardVersion('9903abc'))
    assert.same('V2', Dap.boardVersion('9906abc'))
    assert.is_nil(Dap.boardVersion('1234'))
  end)
end)

describe('Dap status', function()
  it('names the codes as error.h numbers them', function()
    assert.same('SUCCESS (0)', Dap.statusName(0))
    assert.same('TRANSFER_TIMEOUT (4)', Dap.statusName(4))
    assert.same('WRITE_VERIFY (18)', Dap.statusName(18))
    assert.same('SUCCESS_DONE (19)', Dap.statusName(19))
    assert.same('HEX_CKSUM (21)', Dap.statusName(21))
    assert.same('FD_INCOMPATIBLE_IMAGE (29)', Dap.statusName(29))
  end)

  it('says what a status means in plain words', function()
    assert.truthy(Dap.plain(21):find('damaged', 1, true))
    assert.truthy(Dap.plain(24):find('not made for', 1, true))
    assert.truthy(Dap.plain(17):find('memory', 1, true))
    assert.truthy(Dap.plain(99):find('refused', 1, true))
  end)

  it('keeps raw codes out of the plain words', function()
    for code = -1, 40 do
      local words = Dap.plain(code):gsub('micro:bit V2', '')
      assert.is_nil(words:find('%d'))
    end
  end)
end)

describe('Usbfs', function()
  it('uses the kernel\'s ioctl numbers', function()
    if ffi.abi('64bit') then
      -- <linux/usbdevice_fs.h> on x86_64 and arm64
      assert.same(56, Usbfs.URB_SIZE)
      assert.same(0x8038550A, Usbfs.SUBMITURB)
      assert.same(0x4008550D, Usbfs.REAPURBNDELAY)
    else
      assert.same(44, Usbfs.URB_SIZE)
      assert.same(0x802C550A, Usbfs.SUBMITURB)
      assert.same(0x4004550D, Usbfs.REAPURBNDELAY)
    end
  end)

  --- a kernel that finishes what was submitted, in order
  local function kernel()
    local k = { queue = {}, errno = 0 }
    k.sys = {
      ioctl = function(_, req, arg)
        if req == Usbfs.SUBMITURB then
          if k.refuse then k.errno = k.refuse return -1 end
          k.queue[#k.queue + 1] = ffi.cast('void *', arg)
          return 0
        elseif req == Usbfs.REAPURBNDELAY then
          local p = table.remove(k.queue, 1)
          if not p then k.errno = k.gone or 11 return -1 end
          local urb = ffi.cast('struct compy_usbfs_urb *', p)
          urb.status = 0
          if urb.endpoint >= 0x80 then
            ffi.copy(urb.buffer, 'ok', 2)
            urb.actual_length = 2
          else
            urb.actual_length = urb.buffer_length
          end
          ffi.cast('void **', arg)[0] = p
          return 0
        end
        return -1
      end,
      poll = function() return #k.queue > 0 and 1 or 0 end,
      errno = function() return k.errno end,
    }
    return k
  end

  it('hands back what a transfer carried in', function()
    local k = kernel()
    local u = Usbfs.new(7, k.sys)
    assert.is_true(u:submit(0x05, string.rep('x', 64)))
    assert.is_true(u:submit(0x85, 64))
    assert.same(2, u:inFlight())
    local out = u:reap()
    assert.same({ endpoint = 0x05, status = 0, actual = 64 }, out)
    local back = u:reap()
    assert.same('ok', back.data)
    assert.same(0, u:inFlight())
  end)

  it('says nothing yet, or why, when there is nothing',
    function()
      local k = kernel()
      local u = Usbfs.new(7, k.sys)
      -- nothing yet is not an error: a link would break on it
      local none, why = u:reap()
      assert.is_nil(none)
      assert.is_nil(why)
      k.gone = 19
      local done, err = u:reap()
      assert.is_nil(done)
      assert.same('reap errno 19', err)
      k.refuse = 19
      local ok, err2 = u:submit(0x05, 'x')
      assert.is_nil(ok)
      assert.same('submit errno 19', err2)
    end)
end)

describe('DapLink', function()
  it('keeps no more than DEPTH commands unanswered', function()
    local chip = F.chip({ latency = 1 })
    local link = linkTo(chip)
    for _ = 1, DapLink.DEPTH do
      assert.is_true(link:send(Dap.packet(0x80), quiet))
    end
    assert.same(0, link:room())
    local ok, err = link:send(Dap.packet(0x80), quiet)
    assert.is_nil(ok)
    assert.truthy(err:find('in flight', 1, true))
    assert.is_true(DapLink.DEPTH < 5)
  end)

  it('hands each reply to its command, in order', function()
    local chip = F.chip()
    local link = linkTo(chip)
    local got = {}
    link:send(Dap.packet(0x80), function(r) got[1] = r:byte(1) end)
    link:send(Dap.packet(0x00, '\9'), function(r)
      got[2] = r:byte(1)
    end)
    link:pump()
    assert.same({ 0x80, 0x00 }, got)
    assert.same(0, link:unanswered())
  end)

  it('keeps a late reply, however late', function()
    local chip = F.chip({ latency = 3 })
    local link = linkTo(chip)
    local got
    link:send(Dap.packet(0x80), function(r) got = r end)
    for _ = 1, 10 do link:pump() end
    assert.is_nil(got)
    chip.now = chip.now + 3
    link:pump()
    assert.truthy(got)
    assert.is_nil(link.fault)
  end)

  it('waits up to the time it is given', function()
    local chip = F.chip({ latency = 0.002 })
    local link, io = linkTo(chip)
    local got
    local t0, waits = chip.now, io.waits
    link:send(Dap.packet(0x80), function(r) got = r end)
    link:pump(5)
    assert.truthy(got)
    assert.same(waits + 1, io.waits)
    assert.is_true(chip.now - t0 <= 0.005 + 1e-9)
  end)

  --- a reply that is not the waiting command's is passed
  --- over, even with a command waiting
  it('passes over replies left from before', function()
    local chip = F.chip()
    local logged = {}
    local link = linkTo(chip, logged, true)
    link.synced = true
    chip:leftover(string.char(0x8C, 0))
    chip:leftover(string.char(0x81, 0))
    local got
    link:send(Dap.packet(0x80), function(r) got = r end)
    link:pump()
    assert.same(0x80, got:byte(1))
    assert.same(2, link.stale)
    assert.truthy(joined(logged):find('passed over a reply to'
      .. ' 0x8C, waiting for 0x80', 1, true))
  end)

  --- a process that died with four commands in flight leaves
  --- their replies in the chip; new commands on top of them
  --- would fill its queue and be dropped
  it('sends one command alone until it is in step', function()
    local chip = F.chip({ latency = 0.001 })
    for _ = 1, 4 do chip:leftover(string.char(0x8C, 0)) end
    local link = linkTo(chip, nil, true)
    assert.same(0, link:room())
    assert.is_nil(link:send(Dap.packet(0x80), quiet))
    link:start()
    link:pump()
    assert.same({}, chip.got)
    assert.same(0, link:room())
    chip.now = chip.now + DapLink.DRAIN_S
    link:pump()
    assert.same({ 0x81 }, chip.got)
    for _ = 1, 10 do link:pump(1) end
    assert.is_true(link.synced)
    assert.same(DapLink.DEPTH, link:room())
    assert.same(4, link.stale)
    assert.same(0, chip.drops)
  end)

  --- a chip that keeps talking must not keep the link from
  --- getting in step
  it('sends its sync by DRAIN_MAX_S however long replies'
    .. ' come', function()
      local chip = F.chip()
      local link, io = linkTo(chip, nil, true)
      link:start()
      local t0 = chip.now
      while #chip.got == 0 and chip.now - t0 < 5 do
        -- one more reply every 50 ms, and a transfer to take it
        chip:leftover(string.char(0x8C, 0))
        io:submit(EP_IN, Dap.PACKET)
        link.posted = link.posted + 1
        link:pump()
        chip.now = chip.now + 0.05
      end
      local took = chip.now - t0
      assert.is_true(took >= DapLink.DRAIN_MAX_S)
      assert.is_true(took <= DapLink.DRAIN_MAX_S + 0.1)
      assert.same(0x81, chip.got[1])
    end)

  --- an IDE that died while it synced leaves sync replies
  --- behind; one of them must not open the window early
  it('drains old sync replies before its own sync', function()
    local chip = F.chip({ latency = 0.001 })
    for _ = 1, 5 do
      chip:leftover(string.char(0x81, 0, 0xC2, 1, 0, 0, 0, 8))
    end
    local link = linkTo(chip, nil, true)
    link:start()
    link:pump()
    assert.is_false(link.synced)
    assert.same(5, link.stale)
    chip.now = chip.now + DapLink.DRAIN_S
    link:pump()
    for _ = 1, 10 do link:pump(1) end
    assert.is_true(link.synced)
    local got = {}
    link:send(Dap.packet(0x80), function(r) got[1] = r end)
    link:send(Dap.packet(0x00, '\9'), function(r) got[2] = r end)
    for _ = 1, 10 do link:pump(1) end
    assert.same(0x80, got[1]:byte(1))
    assert.same(0x00, got[2]:byte(1))
    assert.same(0, chip.drops)
  end)

  it('breaks on a transfer error, and then stays still',
    function()
      local chip = F.chip()
      local link, io = linkTo(chip)
      chip.outStatus = -71
      link:send(Dap.packet(0x80), quiet)
      link:pump()
      assert.truthy(link.fault:find('-71', 1, true))
      local before = io.submits
      assert.is_nil(link:send(Dap.packet(0x80), quiet))
      link:pump()
      assert.same(before, io.submits)
    end)

  it('touches nothing once killed', function()
    local chip = F.chip()
    local link, io = linkTo(chip)
    link:kill()
    local before = io.submits
    assert.is_nil(link:send(Dap.packet(0x80), quiet))
    link:pump(5)
    assert.same(before, io.submits)
    assert.same(0, io.waits)
    assert.same('device gone', link.fault)
  end)

  it('breaks when the kernel says the device went', function()
    local chip = F.chip()
    local link = linkTo(chip)
    chip.reapError = 'reap errno 19'
    link:pump()
    assert.same('reap errno 19', link.fault)
  end)
end)

describe('DapFlash', function()
  it('asks, opens, writes, closes and resets, in order',
    function()
      local chip = F.chip()
      local data = F.hex(60)
      local j, said = job(data, chip)
      assert.same('done', run(j, chip))
      assert.same({ 0x80, 0x00, 0x8A }, { chip.got[1],
        chip.got[2], chip.got[3] })
      local n = #chip.got
      assert.same(0x8B, chip.got[n - 1])
      assert.same(0x89, chip.got[n])
      assert.same(1, chip.streamType)
      assert.same(data, chip.written)
      assert.same(math.ceil(#data / 62), count(chip.got, 0x8C))
      assert.same('CLOSED', chip.stream)
      assert.truthy(said[#said]:find('took the file', 1, true))
    end)

  it('never fills the chip\'s reply queue', function()
    local chip = F.chip({ latency = 0.001 })
    local j = job(F.hex(300), chip)
    assert.same('done', run(j, chip))
    assert.same(0, chip.drops)
    assert.is_true(chip.most <= DapLink.DEPTH)
    assert.is_true(chip.most > 1)
  end)

  it('keeps each update within its time', function()
    local chip = F.chip({ latency = 0.003 })
    local j = job(F.hex(300), chip)
    for _ = 1, 40 do
      local t0 = chip.now
      j:step(1 / 30)
      assert.is_true(chip.now - t0 <= j.budget + 0.001)
      assert.is_true(j.budget <= DapFlash.BUDGET + 1e-9)
      chip.now = chip.now + 1 / 30
    end
  end)

  --- a frame on a 60 Hz screen: the IDE's own work, then the
  --- flash's, rounded up to the next refresh
  local function frames(ownWork, latency)
    local chip = F.chip({ latency = latency })
    local j = job(F.hex(2000), chip)
    local dt, late, n = 1 / 60, 0, 0
    while j:step(dt) == 'running' do
      local spent = ownWork + j.lastSpent
      dt = math.ceil(spent * 60 - 1e-9) / 60
      chip.now = chip.now + dt - j.lastSpent
      n = n + 1
      if dt > DapFlash.FRAME_MAX then late = late + 1 end
    end
    return late, n, j
  end

  --- the screen goes down to about 30 frames a second, and
  --- no frame runs past FRAME_MAX for the flash's sake
  it('takes the screen down to about 30 frames a second, no'
    .. ' further', function()
      local late, n, j = frames(0.010, 0.0005)
      assert.same(0, late)
      assert.is_true(n > 10)
      assert.same(DapFlash.BUDGET, j.budget)
      assert.is_true(0.010 + DapFlash.BUDGET <= DapFlash.FRAME_MAX)
    end)

  it('halves its time when a frame runs long, and takes it'
    .. ' back after', function()
      local chip = F.chip({ latency = 0.001 })
      local j = job(F.hex(300), chip)
      j:adapt(1 / 30)
      assert.same(DapFlash.BUDGET, j.budget)
      j:adapt(0.2)
      assert.same(DapFlash.BUDGET / 2, j.budget)
      for _ = 1, 10 do j:adapt(0.2) end
      assert.same(DapFlash.BUDGET_MIN, j.budget)
      for _ = 1, 20 do j:adapt(1 / 30) end
      assert.same(DapFlash.BUDGET, j.budget)
    end)

  it('logs once a second where the time went', function()
    local chip = F.chip({ latency = 0.0005 })
    local j, _, logged = job(F.hex(2000), chip)
    run(j, chip)
    local lines = {}
    for _, l in ipairs(logged) do
      if l:find('^pace: ') then lines[#lines + 1] = l end
    end
    assert.is_true(#lines >= 1)
    assert.truthy(lines[1]:find('chunks/update', 1, true))
    assert.truthy(lines[1]:find('chunks/s', 1, true))
    assert.truthy(lines[1]:find('unanswered', 1, true))
  end)

  --- a chip that never lets the link get in step must still
  --- end the flash with a verdict
  it('gives up on a link that never gets in step', function()
    local chip = F.chip()
    local said = {}
    local link = linkTo(chip, nil, true)
    local j = DapFlash.new(F.hex(5), link,
      function(l) said[#said + 1] = l end, quiet,
      function() return chip.now end)
    assert.same('failed', run(j, chip))
    assert.same(0, #chip.got)
    assert.truthy(joined(said):find('stopped answering', 1,
      true))
  end)

  it('writes many chunks per update when the chip is quick',
    function()
      local chip = F.chip({ latency = 0.0005 })
      local j = job(F.hex(2000), chip)
      local state, steps = run(j, chip)
      assert.same('done', state)
      local chunks = count(chip.got, 0x8C)
      -- four in flight between updates, many more within one
      assert.is_true(chunks / steps > 16)
    end)

  it('refuses a micro:bit V1 before opening anything',
    function()
      local chip = F.chip({ id = '9900' .. string.rep('0', 44) })
      local j, said = job(F.hex(5), chip)
      assert.same('failed', run(j, chip))
      assert.same(0, count(chip.got, 0x8A))
      assert.truthy(joined(said):find('micro:bit V1', 1, true))
    end)

  it('refuses a board that is not a micro:bit, before'
    .. ' opening anything', function()
      for _, id in ipairs({ '', '1234' .. string.rep('0', 44) })
      do
        local chip = F.chip({ id = id })
        local j, said = job(F.hex(5), chip)
        assert.same('failed', run(j, chip))
        assert.same(0, count(chip.got, 0x8A))
        assert.truthy(joined(said):find('not a micro:bit V2', 1,
          true))
      end
    end)

  it('goes on when the chip does not say its version',
    function()
      local chip = F.chip({ firmware = '' })
      local j = job(F.hex(5), chip)
      assert.same('done', run(j, chip))
    end)

  it('closes a stream left open, then opens again', function()
    local chip = F.chip()
    chip.stream = 'OPEN'
    local j = job(F.hex(5), chip)
    assert.same('done', run(j, chip))
    assert.same({ 0x8A, 0x8B, 0x8A }, { chip.got[3],
      chip.got[4], chip.got[5] })
  end)

  it('closes and gives up when open stays refused', function()
    local chip = F.chip()
    chip.over[0x8A] = function() return string.char(0x8A, 2) end
    local j, said = job(F.hex(5), chip)
    assert.same('failed', run(j, chip))
    assert.same(2, count(chip.got, 0x8A))
    assert.same(0x8B, chip.got[#chip.got])
    assert.truthy(joined(said):find('busy', 1, true))
  end)

  it('closes after an open that failed', function()
    local chip = F.chip()
    chip.over[0x8A] = function(_, c)
      c.stream = 'ERROR'
      return string.char(0x8A, 11)
    end
    local j, said = job(F.hex(5), chip)
    assert.same('failed', run(j, chip))
    assert.same('CLOSED', chip.stream)
    assert.truthy(joined(said):find('memory', 1, true))
  end)

  it('stops on a damaged first record: closes, the old'
    .. ' program stays', function()
      local chip = F.chip()
      local data = F.hex(40):gsub('^(:10001000)', ':10001001')
      local j, said, logged = job(data, chip)
      assert.same('failed', run(j, chip))
      assert.same('CLOSED', chip.stream)
      assert.same(0x8B, chip.got[#chip.got])
      assert.same(0, count(chip.got, 0x89))
      local s = joined(said)
      assert.truthy(s:find('damaged', 1, true))
      assert.is_nil(s:find('old program', 1, true))
      assert.is_nil(s:find('21', 1, true))
      assert.truthy(joined(logged):find('HEX_CKSUM (21)', 1, true))
    end)

  it('stops on a damaged record halfway: says the old program'
    .. ' may be gone', function()
      local chip = F.chip()
      local data = F.hex(400)
      local at = data:find(':10', #data / 2, true)
      data = data:sub(1, at + 8) .. 'F' .. data:sub(at + 10)
      local j, said = job(data, chip)
      assert.same('failed', run(j, chip))
      assert.same('CLOSED', chip.stream)
      assert.truthy(joined(said):find('old program', 1, true))
    end)

  it('fails when the close reports an error', function()
    local chip = F.chip()
    chip.over[0x8B] = function(_, c)
      c.stream = 'CLOSED'
      return string.char(0x8B, 17)
    end
    local j, said = job(F.hex(5), chip)
    assert.same('failed', run(j, chip))
    assert.same(0, count(chip.got, 0x89))
    assert.truthy(joined(said):find('memory', 1, true))
  end)

  it('tells to unplug a chip that stopped answering',
    function()
      local chip = F.chip()
      local j, said, logged = job(F.hex(200), chip)
      j:step(1 / 30)
      chip.silent = true
      assert.same('failed', run(j, chip))
      assert.truthy(joined(said):find('stopped answering', 1,
        true))
      assert.truthy(joined(said):find('Unplug', 1, true))
      assert.truthy(joined(logged):find('no reply in 5 s', 1,
        true))
    end)

  --- the chip erases nothing before it starts writing: 48
  --- bytes in a row, or a second run
  it('says the old program may be gone only once the chip'
    .. ' may have erased it', function()
      local chip = F.chip()
      chip.over[0x8C] = function(packet, c)
        c.n = (c.n or 0) + 1
        if c.n == 2 then return string.char(0x8C, 21) end
      end
      local j, said = job(F.hex(40), chip)
      assert.is_true(j.eraseChunk >= 2)
      assert.same('failed', run(j, chip))
      assert.is_nil(joined(said):find('old program', 1, true))
    end)

  --- a micro:bit V2 erases the whole chip within the write
  --- that carries the erase point, whatever its reply
  it('says the old program may be gone once the chunk that'
    .. ' erases went', function()
      local function refusing(status)
        local chip = F.chip()
        local j
        chip.over[0x8C] = function(_, c)
          c.n = (c.n or 0) + 1
          if c.n == j.eraseChunk then
            return string.char(0x8C, status)
          end
        end
        local said
        j, said = job(F.hex(40), chip)
        assert.same('failed', run(j, chip))
        return joined(said):find('old program', 1, true) ~= nil
      end
      assert.is_true(refusing(17))
      assert.is_true(refusing(16))
      assert.is_true(refusing(13))
      -- a bad record may come after records that started the
      -- erase in the same chunk
      assert.is_true(refusing(21))
      assert.is_true(refusing(22))
      for _, before in ipairs({ 26, 27, 28, 29 }) do
        assert.is_false(refusing(before), before)
      end

      local quiet_chip = F.chip()
      local j
      quiet_chip.over[0x8C] = function(_, c)
        c.n = (c.n or 0) + 1
        if c.n >= j.eraseChunk then c.silent = true end
      end
      local said
      j, said = job(F.hex(40), quiet_chip)
      assert.same('failed', run(j, quiet_chip))
      assert.truthy(joined(said):find('old program', 1, true))
    end)

  it('says so when the erase point is in the last chunk and'
    .. ' the close fails', function()
      local chip = F.chip()
      chip.over[0x8B] = function(_, c)
        c.stream = 'CLOSED'
        return string.char(0x8B, 17)
      end
      local j, said = job(F.hex(3), chip)
      assert.same(j.chunks, j.eraseChunk)
      assert.same('failed', run(j, chip))
      assert.same(j.chunks, j.sent)
      assert.truthy(joined(said):find('old program', 1, true))
    end)

  it('finds the chunk that starts the chip writing', function()
    local text = assert(Dap.prepare(
      io.open('src/examples/microbit/MICROBIT.hex'):read('*a')))
    -- a type 04 record, then 16-byte records: the third holds
    -- the 48th byte
    local third = select(2, text:find(':10002000%x+\n'))
    assert.same(math.ceil(third / 62), Dap.eraseChunk(text))
    local two = IntelHex.encode({ { at = 0, data = 'abcd' },
      { at = 0x100, data = 'efgh' } })
    local second = select(2, two:find(':04010000%x+\n'))
    assert.same(math.ceil(second / 62), Dap.eraseChunk(two))
  end)

  it('says the board was unplugged when the link dies',
    function()
      local chip = F.chip()
      local j, said, _, link = job(F.hex(200), chip)
      j:step(1 / 30)
      link:kill()
      assert.same('failed', run(j, chip))
      assert.truthy(joined(said):find('was unplugged', 1, true))
    end)

  it('says the Compy lost the board on a transfer error',
    function()
      local chip = F.chip()
      local j, said = job(F.hex(200), chip)
      j:step(1 / 30)
      chip.outShort = 10
      assert.same('failed', run(j, chip))
      assert.truthy(joined(said):find('lost touch', 1, true))
    end)

  --- the close's reply comes after the flash gave up on it:
  --- it must not turn the failure into a success
  it('ignores replies that come after the verdict', function()
    local chip = F.chip({ slow = { [0x8B] = 10 } })
    local j, said, _, link = job(F.hex(5), chip)
    assert.same('failed', run(j, chip))
    local told = #said
    chip.now = chip.now + 10
    link:pump()
    assert.same(0, link:unanswered())
    assert.same('failed', j.state)
    assert.same(told, #said)
    assert.is_nil(joined(said):find('took the file', 1, true))
  end)

  --- a close the chip reported done means the board has the
  --- whole file, whatever happens to the reset after it
  it('says the board took the file when only the reset\'s'
    .. ' reply is missing', function()
      for _, case in ipairs({ 'late', 'unplugged' }) do
        local chip = F.chip(case == 'late'
          and { slow = { [0x89] = 10 } } or nil)
        if case == 'unplugged' then
          chip.over[0x89] = function(_, c) c.silent = true end
        end
        local j, said, _, link = job(F.hex(5), chip)
        if case == 'unplugged' then
          local send = link.send
          link.send = function(l, packet, f)
            if packet:byte(1) == 0x89 then l:kill() end
            return send(l, packet, f)
          end
        end
        assert.same('done', run(j, chip), case)
        assert.same('CLOSED', chip.stream)
        local told = joined(said)
        assert.truthy(told:find('took the file', 1, true), case)
        assert.truthy(told:find('reset button', 1, true), case)
        assert.is_nil(told:find('did not take', 1, true), case)
      end
    end)

  --- an end of file on an earlier chunk leaves chunks the chip
  --- will not take
  it('fails when the end of file comes before the last chunk',
    function()
      local chip = F.chip()
      chip.over[0x8C] = function(_, c)
        c.n = (c.n or 0) + 1
        if c.n == 2 then return string.char(0x8C, 19) end
      end
      local j, said = job(F.hex(40), chip)
      assert.same('failed', run(j, chip))
      assert.same(0, count(chip.got, 0x89))
      assert.is_nil(joined(said):find('took the file', 1, true))
    end)

  --- the chip reports the end of the file on the last chunk;
  --- without that report it has not read the whole file
  it('fails when the last chunk brings no end of file',
    function()
      local chip = F.chip()
      chip.over[0x8C] = function(packet, c)
        local chunk = packet:sub(3, 2 + packet:byte(2))
        c.written = c.written .. chunk
        return string.char(0x8C, 0)
      end
      local j, said = job(F.hex(5), chip)
      assert.same('failed', run(j, chip))
      assert.same('CLOSED', chip.stream)
      assert.same(0, count(chip.got, 0x89))
      assert.is_nil(joined(said):find('took the file', 1, true))
    end)

  --- a board that left the bus reads as unplugged, whichever
  --- way the link learns it
  it('tells an unplug from a lost link', function()
    local cases = {
      { 'reap errno 19', nil, 'was unplugged' },
      { 'reply transfer status -108', nil, 'was unplugged' },
      { 'reply transfer status -2', nil, 'was unplugged' },
      { 'reply transfer status -22', nil, 'lost touch' },
      { 'reap errno 191', nil, 'lost touch' },
      { 'reply transfer status -71', true, 'was unplugged' },
      { 'reply transfer status -84', true, 'was unplugged' },
      { 'reply transfer status -32', false, 'was unplugged' },
      { 'reply transfer status -32', true, 'lost touch' },
      { 'reply transfer status -32', nil, 'lost touch' },
    }
    for _, c in ipairs(cases) do
      local chip = F.chip()
      local j, said, _, link = job(F.hex(200), chip)
      if c[2] ~= nil then
        link.present = function() return c[2] end
      end
      j:step(1 / 30)
      link:broke(c[1])
      assert.same('failed', run(j, chip))
      assert.truthy(joined(said):find(c[3], 1, true), c[1])
    end
  end)

  it('says the board was unplugged while it closed after a'
    .. ' refusal', function()
      local chip = F.chip()
      local data = F.hex(40):gsub('^(:10001000)', ':10001001')
      chip.over[0x8B] = function(_, c) c.silent = true end
      local j, said, _, link = job(data, chip)
      local send = link.send
      link.send = function(l, packet, f)
        if packet:byte(1) == 0x8B then
          l:kill()
          return nil, 'device gone'
        end
        return send(l, packet, f)
      end
      assert.same('failed', run(j, chip))
      assert.truthy(joined(said):find('was unplugged', 1, true))
    end)

  --- the IDE may be put in the background for a while: the
  --- replies that came meanwhile are taken before any wait
  --- is counted
  it('goes on after a long pause', function()
    local chip = F.chip({ latency = 0.001 })
    local j, said = job(F.hex(300), chip)
    for _ = 1, 20 do
      j:step(1 / 30)
      chip.now = chip.now + 1 / 30
    end
    chip.now = chip.now + 60
    assert.are_not.same('failed', j:step(60))
    assert.same('done', run(j, chip))
    assert.is_nil(joined(said):find('did not take', 1, true))
  end)

  --- the frame that prepared the file is long and says nothing
  --- about the frames after it
  it('keeps its time after a long first frame', function()
    local chip = F.chip({ latency = 0.001 })
    local j, _, logged = job(F.hex(300), chip)
    j:step(0.4)
    assert.same(DapFlash.BUDGET, j.budget)
    assert.truthy(joined(logged):find('first update: the frame'
      .. ' before it took 400 ms', 1, true))
    j:step(0.4)
    assert.same(DapFlash.BUDGET / 2, j.budget)
  end)

  it('says why when it is stopped with words', function()
    local chip = F.chip({ latency = 0.001 })
    local j, said = job(F.hex(300), chip)
    for _ = 1, 100 do
      if chip.stream == 'OPEN' and j.accepted >= j.eraseChunk then
        break
      end
      j:step(1 / 30)
      chip.now = chip.now + 1 / 30
    end
    j:abandon(1, 'The Compy was being closed.')
    assert.same('CLOSED', chip.stream)
    local told = joined(said)
    assert.truthy(told:find('did not take the file. The Compy was'
      .. ' being closed.', 1, true))
    assert.truthy(told:find('old program', 1, true))
  end)

  it('closes the stream when the IDE stops mid-flash',
    function()
      local chip = F.chip({ latency = 0.001 })
      local j, said = job(F.hex(300), chip)
      for _ = 1, 100 do
        if chip.stream == 'OPEN' then break end
        j:step(1 / 30)
        chip.now = chip.now + 1 / 30
      end
      assert.same('OPEN', chip.stream)
      local t0 = chip.now
      local told = #said
      j:abandon(1)
      assert.same('CLOSED', chip.stream)
      assert.same('failed', j.state)
      assert.same(told, #said)
      assert.is_true(chip.now - t0 < 1)
    end)

  --- a close with no stream open trips an assert in the chip
  it('sends no close on stop when no stream is open',
    function()
      local chip = F.chip({ latency = 0.5 })
      local j = job(F.hex(300), chip)
      j:step(1 / 30)
      assert.same('ask', j.phase)
      j:abandon(1)
      assert.same(0, count(chip.got, 0x8B))
      local chip2 = F.chip({ slow = { [0x89] = 10 } })
      local j2 = job(F.hex(5), chip2)
      for _ = 1, 200 do
        if j2.phase == 'reset' then break end
        j2:step(1 / 30)
        chip2.now = chip2.now + 1 / 30
      end
      assert.same('reset', j2.phase)
      j2:abandon(1)
      assert.same(1, count(chip2.got, 0x8B))
    end)

  it('stops at once when the link is not yet in step',
    function()
      local chip = F.chip()
      local link = linkTo(chip, nil, true)
      link:start()
      local j = DapFlash.new(F.hex(5), link, quiet, quiet,
        function() return chip.now end)
      j:step(1 / 30)
      j:abandon(1)
      assert.same('failed', j.state)
      assert.same({}, chip.got)
    end)

  it('waits no longer than it may for a close on stop',
    function()
      local chip = F.chip()
      local j = job(F.hex(300), chip)
      j:step(1 / 30)
      chip.silent = true
      local t0 = chip.now
      j:abandon(1)
      assert.is_true(chip.now - t0 <= 1 + 1e-9)
    end)

  it('passes over replies left from an earlier flash, and'
    .. ' the chip drops nothing', function()
      local chip = F.chip({ latency = 0.002 })
      for _ = 1, 3 do chip:leftover(string.char(0x8C, 0)) end
      chip:leftover(string.char(0x80, 4) .. '9904')
      local j = job(F.hex(300), chip)
      assert.same('done', run(j, chip))
      assert.same('CLOSED', chip.stream)
      assert.same(0, chip.drops)
    end)

  it('says how far it has got every few seconds', function()
    local chip = F.chip({ latency = 0.05 })
    local j, said = job(F.hex(300), chip)
    run(j, chip)
    local lines = 0
    for _, l in ipairs(said) do
      if l:find('%% done') then lines = lines + 1 end
    end
    assert.is_true(lines >= 1)
  end)
end)

describe('Serial flash', function()
  local kept
  before_each(function()
    kept = Dap.log
    Dap.log = quiet
  end)
  after_each(function() Dap.log = kept end)

  --- a board on the chip's clock
  local function connected(chip)
    local b = FakeBackend.new()
    local s = Serial.new(b)
    b:attach()
    if chip then
      b.link = linkTo(chip)
      s.clock = function() return chip.now end
    end
    return s, b
  end

  it('refuses a hex without its end record, sending nothing',
    function()
      local chip = F.chip()
      local s = connected(chip)
      local body = F.hex(3):gsub(':00000001FF\r\n$', '')
      local ok, err = s:flash(body, quiet)
      assert.is_nil(ok)
      assert.truthy(err:find('cut short', 1, true))
      assert.same(0, #chip.got)
    end)

  it('refuses a Universal Hex', function()
    local s = connected(F.chip())
    local ok, err = s:flash(':0400000A9900C0DEBB\r\n'
      .. ':00000001FF\r\n', quiet)
    assert.is_nil(ok)
    assert.truthy(err:find('both micro:bit versions', 1, true))
    assert.truthy(err:find('from a computer', 1, true))
  end)

  it('says to plug the board in when there is none', function()
    local s = Serial.new(FakeBackend.new())
    local ok, err = s:flash(F.hex(1), quiet)
    assert.is_nil(ok)
    assert.truthy(err:find('Plug the micro:bit into the Compy',
      1, true))
  end)

  it('says how to leave maintenance mode', function()
    local b = FakeBackend.new()
    local s = Serial.new(b)
    b.why = 'maintenance mode'
    local ok, err = s:flash(F.hex(1), quiet)
    assert.is_nil(ok)
    assert.truthy(err:find('without holding the button', 1,
      true))
  end)

  it('says what to do about a board plugged in but not open',
    function()
      local b = FakeBackend.new()
      local s = Serial.new(b)
      b.why = 'permission'
      local _, err = s:flash(F.hex(3), quiet)
      assert.truthy(err:find('If the question is on the screen,'
        .. ' answer it', 1, true))
      assert.truthy(err:find('plug it back in to be asked again',
        1, true))
      b.why = 'CDC interface set incomplete'
      _, err = s:flash(F.hex(3), quiet)
      assert.truthy(err:find('plugged in, but the Compy could not'
        .. ' reach it', 1, true))
      b.why = nil
      _, err = s:flash(F.hex(3), quiet)
      assert.truthy(err:find('No micro:bit is plugged in', 1,
        true))
    end)

  it('refuses a second flash, and a restart, while one runs',
    function()
      local s = connected(F.chip({ latency = 1 }))
      assert.is_true(s:flash(F.hex(50), quiet))
      assert.is_true(s:isFlashing())
      local ok, err = s:flash(F.hex(1), quiet)
      assert.is_nil(ok)
      assert.truthy(err:find('taking a file', 1, true))
      ok, err = s:reset()
      assert.is_nil(ok)
      assert.truthy(err:find('taking a file', 1, true))
    end)

  it('sends the file as Dap.prepare wrote it', function()
    local chip = F.chip()
    local s = connected(chip)
    local data = F.hex(40):gsub('\r\n', '\n') .. '\n\n'
    assert.is_true(s:flash(data, quiet))
    for _ = 1, 200 do
      s:update(1 / 30)
      chip.now = chip.now + 1 / 30
    end
    assert.is_false(s:isFlashing())
    assert.same(Dap.prepare(data), chip.written)
    assert.are_not.same(data, chip.written)
  end)

  it('returns at once and flashes over updates', function()
    local chip = F.chip()
    local s, b = connected(chip)
    local said = {}
    assert.is_true(s:flash(F.hex(40),
      function(l) said[#said + 1] = l end))
    assert.same(0, #chip.got)
    assert.same(1, b.drops)
    for _ = 1, 200 do
      s:update(1 / 30)
      chip.now = chip.now + 1 / 30
    end
    assert.is_false(s:isFlashing())
    assert.truthy(said[#said]:find('took the file', 1, true))
  end)

  it('says what helps when it cannot flash the board',
    function()
      local cases = {
        { 'drive not held', nil, 'plug it back in' },
        { 'CMSIS-DAP interface not claimed',
          '9904' .. string.rep('0', 44), 'plug it back in' },
        { 'no CMSIS-DAP interface', '9900' .. string.rep('0', 44),
          'micro:bit V1' },
        { 'no CMSIS-DAP interface', '9904' .. string.rep('0', 44),
          'cannot take files from the Compy' },
        { 'no CMSIS-DAP interface', nil,
          'cannot take files from the Compy' },
      }
      for _, c in ipairs(cases) do
        local s, b = connected()
        b.dapRefuse = c[1]
        b.id = c[2]
        local ok, err = s:flash(F.hex(3), quiet)
        assert.is_nil(ok)
        assert.truthy(err:find(c[3], 1, true), c[3])
      end
    end)

  it('gives the words for a flash a stop cut off', function()
    local chip = F.chip({ latency = 0.001 })
    local s = connected(chip)
    assert.is_nil(s:stop())
    local s2 = connected(chip)
    assert.is_true(s2:flash(F.hex(300), quiet))
    for _ = 1, 200 do
      if s2.job and s2.job.sent >= s2.job.eraseChunk then break end
      s2:update(1 / 30)
      chip.now = chip.now + 1 / 30
    end
    local cut = s2:stop()
    assert.truthy(cut:find('did not take it', 1, true))
    assert.truthy(cut:find('old program', 1, true))
  end)

  it('ends a flash with words when the Compy is closed',
    function()
      local chip = F.chip({ latency = 0.001 })
      local said = {}
      local s = connected(chip)
      assert.is_true(s:flash(F.hex(300),
        function(l) said[#said + 1] = l end))
      for _ = 1, 100 do
        if chip.stream == 'OPEN' then break end
        s:update(1 / 30)
        chip.now = chip.now + 1 / 30
      end
      s:abandon()
      assert.is_false(s:isFlashing())
      assert.same('CLOSED', chip.stream)
      assert.truthy(joined(said):find('being closed', 1, true))
      assert.is_true(s:isConnected())
    end)

  it('refuses a file too small for the chip to write',
    function()
      local chip = F.chip()
      local s = connected(chip)
      local ok, err = s:flash(':0400000001020304F2\n'
        .. ':00000001FF\n', quiet)
      assert.is_nil(ok)
      assert.truthy(err:find('too little to be a program', 1,
        true))
      assert.is_nil(err:find('Get the file again', 1, true))
      assert.same(0, #chip.got)
    end)

  it('refuses a damaged file before sending anything',
    function()
      local chip = F.chip()
      local s = connected(chip)
      local bad = F.hex(40):gsub('ABAB', 'ABAC', 1)
      local ok, err = s:flash(bad, quiet)
      assert.is_nil(ok)
      assert.truthy(err:find('damaged', 1, true))
      assert.same(0, #chip.got)
    end)

  it('refuses a file with an end record in the middle',
    function()
      local chip = F.chip()
      local s = connected(chip)
      local ok, err = s:flash(F.hex(2) .. F.hex(2), quiet)
      assert.is_nil(ok)
      assert.truthy(err:find('damaged', 1, true))
      assert.same(0, #chip.got)
    end)

  it('closes the stream when stopped mid-flash', function()
    local chip = F.chip({ latency = 0.001 })
    local s = connected(chip)
    assert.is_true(s:flash(F.hex(300), quiet))
    for _ = 1, 100 do
      if chip.stream == 'OPEN' then break end
      s:update(1 / 30)
      chip.now = chip.now + 1 / 30
    end
    assert.same('OPEN', chip.stream, s.job and s.job.phase)
    s:stop()
    assert.same('CLOSED', chip.stream)
    assert.is_false(s:isFlashing())
  end)

  --- the board is halted; what waited would reach the new
  --- program as lines typed into it
  it('takes nothing to send while a flash runs', function()
    local chip = F.chip()
    local s, b = connected(chip)
    assert.is_true(s:flash(F.hex(40), quiet))
    local ok, err = s:send('print(1)\r')
    assert.is_nil(ok)
    assert.truthy(err:find('taking a file', 1, true))
    assert.same({}, b.sent)
    for _ = 1, 200 do
      s:update(1 / 30)
      chip.now = chip.now + 1 / 30
    end
    assert.is_false(s:isFlashing())
    assert.same({}, b.sent)
    assert.is_true(s:send('print(2)\r'))
  end)

  it('tells a program whether a flash runs', function()
    local s = connected(F.chip({ latency = 1 }))
    local t = s:table_for('program')
    assert.is_false(t.isFlashing())
    s:flash(F.hex(5), quiet)
    assert.is_true(t.isFlashing())
  end)
end)
