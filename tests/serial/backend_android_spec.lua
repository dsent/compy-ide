--- The Android backend holds the micro:bit's drive for as
--- long as it has the board open, and hands it back as it
--- lets the board go: Android rebinds its storage driver only
--- on an explicit release (AOSP
--- android_hardware_UsbDeviceConnection.cpp), so a release
--- skipped or run after the connection closed leaves the
--- board without a drive until it is plugged in again. These
--- rules, and the link to the chip that closes before the
--- connection does, are held here with the JNI calls
--- recorded instead of made.

require('model.serial.backend_android')
require('model.serial.dap_link')
local F = require('tests.helpers.fake_daplink')

local calls
local saved = {}
local STUBBED = { 'jniCallBool', 'jniCallVoid', 'jniCallInt',
  'jniDropGlobal' }

local function record(kind)
  return function(_, obj, mid, arg, force)
    calls[#calls + 1] = { kind = kind, obj = obj, mid = mid,
      arg = arg, force = force }
    if kind == 'int' then return 42 end
    if kind == 'bool' then return true end
  end
end

--- A port as openDevice builds it, with names for its parts
local function port(chip)
  local p = {
    conn = 'conn', comm = 'comm', data = 'data', msc = 'msc',
    claimM = 'claim', releaseM = 'release', closeM = 'close',
    fdM = 'fd', ctrlM = 'ctrl', bulkM = 'bulk',
    dap = { iface = 'dap', id = 5, inAddr = 0x85,
      outAddr = 0x05, claimed = true },
  }
  if chip then
    p.link = DapLink.new(F.bus(chip), 0x05, 0x85,
      function() end, function() return chip.now end)
    p.link:start()
  end
  return p
end

local function backend(p)
  local b = AndroidBackend.new()
  b.env = 'env'
  b.attached = 0
  b.sink = {
    attach = function() b.attached = b.attached + 1 end,
    detach = function() end,
  }
  b.dev = { dev = 'dev', name = '/dev/bus/usb/001/002' }
  b.openDevice = function() return p end
  return b
end

describe('AndroidBackend drive hold', function()
  before_each(function()
    calls = {}
    for _, name in ipairs(STUBBED) do saved[name] = _G[name] end
    _G.jniCallBool = record('bool')
    _G.jniCallVoid = record('void')
    _G.jniCallInt = record('int')
    _G.jniDropGlobal = function() end
    saved.log = Dap.log
    Dap.log = function() end
  end)
  after_each(function()
    for _, name in ipairs(STUBBED) do _G[name] = saved[name] end
    Dap.log = saved.log
  end)

  it('takes the drive with force before the board is'
    .. ' announced', function()
      local p = port(F.chip())
      local b = backend(p)
      local attachedAtTake
      _G.jniCallBool = function(_, obj, mid, arg, force)
        calls[#calls + 1] = { mid = mid, arg = arg,
          force = force }
        if arg == 'msc' then attachedAtTake = b.attached end
        return true
      end
      b:openReady()
      assert.same('open', b.state)
      assert.is_true(p.storageTaken)
      assert.same({ mid = 'claim', arg = 'msc', force = true },
        calls[1])
      assert.same(0, attachedAtTake)
      assert.same(1, b.attached)
    end)

  it('announces the board when the drive is refused',
    function()
      local p = port()
      local b = backend(p)
      _G.jniCallBool = function() return false end
      b:openReady()
      assert.is_falsy(p.storageTaken)
      assert.same(1, b.attached)
    end)

  it('asks the chip who it is without waiting, once in step',
    function()
      local chip = F.chip({ latency = 1 })
      local p = port(chip)
      local b = backend(p)
      b:openReady()
      b.read = function() return '' end
      b.write = function() end
      b.due = math.huge
      b:pollOpen()
      assert.same({}, chip.got)
      chip.now = DapLink.DRAIN_S
      b:pollOpen()
      assert.same({ 0x81 }, chip.got)
      chip.now = chip.now + 1
      b:pollOpen()
      assert.same({ 0x81, 0x80, 0x00 }, chip.got)
      assert.is_nil(b:board())
      chip.now = chip.now + 2
      b:pollOpen()
      assert.same(chip.id, b:board().id)
      assert.same('0257', b:board().firmware)
      b:pollOpen()
      assert.same(3, #chip.got)
    end)

  --- handed back, the drive would be mounted by Android just
  --- as the next IDE, often the same process started again,
  --- takes it with force: that hung the IDE's restart
  it('never hands the drive back, and stops the link before'
    .. ' the connection closes', function()
      local chip = F.chip()
      local p = port(chip)
      local b = backend(p)
      b:openReady()
      local link = p.link
      calls = {}
      b:closePort(false)
      assert.same('device gone', link.fault)
      local order = {}
      for _, c in ipairs(calls) do
        order[#order + 1] = c.mid .. ':' .. tostring(c.arg)
      end
      assert.same({ 'release:dap', 'release:comm',
        'release:data', 'close:nil' }, order)
      assert.is_false(p.storageTaken)
      assert.same('idle', b.state)
    end)

  --- LÖVE on Android starts again inside the same process
  --- after a quit: the next backend must open the board as
  --- the first did, and the first must be done with it
  it('lets the board go on stop, so the next start opens it'
    .. ' afresh', function()
      local chip = F.chip()
      local p = port(chip)
      local first = backend(p)
      first:openReady()
      local firstIo = p.link.io
      first:stop()
      first:stop()
      assert.same('idle', first.state)
      local submits = firstIo.submits
      local p2 = port(chip)
      local second = backend(p2)
      calls = {}
      second:openReady()
      assert.same('open', second.state)
      assert.same({ mid = 'claim', arg = 'msc', force = true },
        { mid = calls[1].mid, arg = calls[1].arg,
          force = calls[1].force })
      second.read = function() return '' end
      second.write = function() end
      second.due = math.huge
      chip.now = chip.now + DapLink.DRAIN_S
      second:pollOpen()
      assert.same(submits, firstIo.submits)
      assert.is_true(p2.link.io.submits > 0)
    end)

  it('waits on no serial output while a file goes to the'
    .. ' board', function()
      local p = port(F.chip())
      local b = backend(p)
      b:openReady()
      local reads, writes = 0, 0
      b.read = function() reads = reads + 1 return '' end
      b.write = function() writes = writes + 1 end
      b.due = math.huge
      b:poll(true)
      assert.same(0, reads)
      assert.same(0, writes)
      b:poll(false)
      assert.same(1, reads)
      assert.same(1, writes)
    end)

  it('hands back no drive it did not take', function()
    local p = port()
    local b = backend(p)
    _G.jniCallBool = function(_, _, _, arg)
      return arg ~= 'msc'
    end
    b:openReady()
    calls = {}
    _G.jniCallBool = record('bool')
    b:closePort(false)
    for _, c in ipairs(calls) do
      assert.are_not.same('msc', c.arg)
    end
  end)

  it('offers the link only while the board is open', function()
    local p = port(F.chip())
    local b = backend(p)
    local link, err = b:dap()
    assert.is_nil(link)
    assert.same('no device connected', err)
    b:openReady()
    assert.equal(p.link, b:dap())
    b:closePort(false)
    assert.is_nil(b:dap())
  end)

  it('remembers a board in maintenance mode, and forgets it'
    .. ' when it opens', function()
      local p = port()
      local b = backend(p)
      b.openDevice = function() return nil, 'maintenance mode' end
      -- the console is not told every SCAN_S; upload() says
      -- what to do
      assert.is_nil(b:openReady())
      assert.same('maintenance mode', b:absence())
      assert.same(0, b.attached)
      b.dev = { dev = 'dev', name = 'same board' }
      assert.is_nil(b:openReady())
      b.dev = { dev = 'dev', name = 'again' }
      b.openDevice = function() return p end
      b:openReady()
      assert.is_nil(b:absence())
    end)

  it('refuses the link while Android keeps the drive',
    function()
      local p = port(F.chip())
      local b = backend(p)
      _G.jniCallBool = function(_, _, _, arg)
        return arg ~= 'msc'
      end
      b:openReady()
      local link, err = b:dap()
      assert.is_nil(link)
      assert.same('drive not held', err)
    end)

  it('names the board by its serial number until the chip'
    .. ' answers', function()
      local p = port()
      local b = backend(p)
      b.serialOf = function() return '9900' .. string.rep('0', 44) end
      assert.is_nil(b:boardId())
      b:openReady()
      assert.same('9900' .. string.rep('0', 44), b:boardId())
      p.board = { id = '9904' .. string.rep('1', 44) }
      assert.same('9904' .. string.rep('1', 44), b:boardId())
    end)

  it('refuses the link on a board without the interface',
    function()
      local p = port()
      local b = backend(p)
      b:openReady()
      local link, err = b:dap()
      assert.is_nil(link)
      assert.same('no CMSIS-DAP interface', err)
    end)
end)
