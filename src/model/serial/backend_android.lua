require('util.jni')
require('model.serial.dap')
require('model.serial.dap_link')
require('model.serial.usbfs')

--- USB CDC-ACM over the Android USB host API, driven from
--- Lua through the LuaJIT FFI. Ported from the robot USB
--- prototype, which runs this sequence on the device; the
--- blocking parts are now steps of poll().
---
--- THREADING: JNIEnv is thread-local and cached here, so
--- the backend must be created and polled on one thread.
---
--- Verified on the device: scan, permission, open, write,
--- detach on unplug and a clean reconnect all run. Nothing
--- has come back from the board yet, so the read path is
--- exercised but not confirmed.

--- @class AndroidBackend
--- @field new function
--- @field start function
--- @field poll function
--- @field send function
--- @field takeStorage function
--- @field giveStorage function
--- @field dap function
--- @field board function
--- @field stop function
AndroidBackend = {}
AndroidBackend.__index = AndroidBackend

local VID_MICROBIT = 0x0D28
local CDC_COMM = 2
local CDC_DATA = 10
--- The board's drive. The IDE holds it for as long as it
--- has the board open, so Android never mounts it: files go
--- to the board through its interface chip instead.
local MASS_STORAGE = 8
--- CMSIS-DAP v2: the vendor interface with bulk endpoints,
--- the one the micro:bit Foundation's own tools use. A V2
--- also lists a vendor interface without endpoints (WebUSB)
--- and HID (CMSIS-DAP v1); neither is used.
local VENDOR = 0xFF
local EP_BULK = 2
local DIR_IN = 0x80
local RX_SIZE = 64
local READ_MS = 5
local WRITE_MS = 1000
--- Bytes per poll on the way out. The board's Lua REPL is
--- an interactive terminal and drops the tail of anything
--- written faster than it reads.
---
--- The firmware has since grown a serial RX ring of 254
--- bytes where it had twenty, and over pyserial on a Mac a
--- whole command now arrives ten times out of ten — so this
--- was taken out. It goes back in: from Compy the writes go
--- through JNI in one bulk transfer, which is not the same
--- path, and there a command still arrives cut short and
--- its tail turns up with the next one. What was measured
--- on a Mac says nothing about this one.
local TX_PER_POLL = 1
local CTRL_MS = 1000
--- PendingIntent.FLAG_IMMUTABLE, required on Android 12+
local PI_IMMUTABLE = 0x04000000
local ACM_CLASS_IFACE = 0x21
local ACM_LINE_CODING = 0x20
local ACM_LINE_STATE = 0x22
local ACM_DTR_AND_RTS = 0x03
local ACM_SEND_BREAK = 0x23
--- The micro:bit's USB chip (DAPLink) holds the board in
--- reset from a break's start and lets it go at its end, a
--- break of length 0.
local BREAK_MS = 100
local PERMISSION_S = 60
local SCAN_S = 1
local PRESENCE_S = 1

local function now()
  if love and love.timer then return love.timer.getTime() end
  return os.time()
end

--- @param msg string
local function log(msg) Dap.log(msg) end

--- @return AndroidBackend
function AndroidBackend.new()
  local self = setmetatable({}, AndroidBackend)
  self.state = 'idle'
  self.sink = nil
  self.port = nil
  self.dev = nil
  self.due = 0
  self.extras_told = false
  self.tx = ''
  return self
end

function AndroidBackend:start(sink)
  self.sink = sink
  jniSelfCheck()
  self.env = jniEnv()
  self.activity = jniActivity()
  self.manager = self:usbManager()
  self.state = 'idle'
  self.due = 0
end

--- android.content.Context.getSystemService('usb')
function AndroidBackend:usbManager()
  local env = self.env
  local ctx = jniClass(env, 'android/content/Context')
  local gss = jniMethod(env, ctx, 'getSystemService',
    '(Ljava/lang/String;)Ljava/lang/Object;')
  local m = jniCallObj(env, self.activity, gss,
    jniStr(env, 'usb'))
  assert(m ~= nil, 'no UsbManager')
  return jniGlobal(env, m)
end

--- Every micro:bit currently on the bus, in bus order
--- @return table[] list of { dev, name }
--- Walk the micro:bits on the bus and drop every local ref
--- this makes. The device handed to fn is a local reference,
--- valid only inside the call.
--- @param fn function
function AndroidBackend:eachDevice(fn)
  local env = self.env
  local mgr = jniClass(env, 'android/hardware/usb/UsbManager')
  local dl = jniMethod(env, mgr, 'getDeviceList',
    '()Ljava/util/HashMap;')
  local map = jniCallObj(env, self.manager, dl)
  local mapCls = jniClass(env, 'java/util/HashMap')
  local values = jniMethod(env, mapCls, 'values',
    '()Ljava/util/Collection;')
  local coll = jniCallObj(env, map, values)
  local collCls = jniClass(env, 'java/util/Collection')
  local itm = jniMethod(env, collCls, 'iterator',
    '()Ljava/util/Iterator;')
  local it = jniCallObj(env, coll, itm)
  local itCls = jniClass(env, 'java/util/Iterator')
  local hasNext = jniMethod(env, itCls, 'hasNext', '()Z')
  local nextM = jniMethod(env, itCls, 'next',
    '()Ljava/lang/Object;')
  local devCls = jniClass(env, 'android/hardware/usb/UsbDevice')
  local getVid = jniMethod(env, devCls, 'getVendorId', '()I')
  local getName = jniMethod(env, devCls, 'getDeviceName',
    '()Ljava/lang/String;')
  while jniCallBool(env, it, hasNext) do
    local dev = jniCallObj(env, it, nextM)
    if jniCallInt(env, dev, getVid) == VID_MICROBIT then
      local js = jniCallObj(env, dev, getName)
      fn(dev, jniText(env, js))
      jniDropLocal(env, js)
    end
    jniDropLocal(env, dev)
  end
  jniDropLocal(env, it)
  jniDropLocal(env, coll)
  jniDropLocal(env, map)
  jniDropLocal(env, devCls)
  jniDropLocal(env, itCls)
  jniDropLocal(env, collCls)
  jniDropLocal(env, mapCls)
  jniDropLocal(env, mgr)
end

--- Devices to choose from; each holds a global ref the
--- caller owns and must drop
--- @return table
function AndroidBackend:scan()
  local env = self.env
  local found = {}
  self:eachDevice(function(dev, name)
    found[#found + 1] = {
      dev = jniGlobal(env, dev),
      name = name,
    }
  end)
  return found
end

--- @return boolean granted
function AndroidBackend:hasPermission(dev)
  local env = self.env
  local mgr = jniClass(env, 'android/hardware/usb/UsbManager')
  local has = jniMethod(env, mgr, 'hasPermission',
    '(Landroid/hardware/usb/UsbDevice;)Z')
  local granted = jniCallBool(env, self.manager, has, dev)
  jniDropLocal(env, mgr)
  return granted
end

--- Fire the permission dialog. The answer is not waited for;
--- poll() checks hasPermission on later ticks.
function AndroidBackend:askPermission(dev)
  local env = self.env
  local intCls = jniClass(env, 'android/content/Intent')
  local ctor = jniMethod(env, intCls, '<init>',
    '(Ljava/lang/String;)V')
  local action = jniStr(env, 'net.compy.USB_PERMISSION')
  local intent = jniNewObj(env, intCls, ctor, action)
  jniDropLocal(env, action)
  local piCls = jniClass(env, 'android/app/PendingIntent')
  local getB = jniStaticMethod(env, piCls, 'getBroadcast',
    '(Landroid/content/Context;ILandroid/content/Intent;I)' ..
    'Landroid/app/PendingIntent;')
  local pi = jniCallStaticObj(env, piCls, getB,
    self.activity, 0, intent, PI_IMMUTABLE)
  local mgr = jniClass(env, 'android/hardware/usb/UsbManager')
  local req = jniMethod(env, mgr, 'requestPermission',
    '(Landroid/hardware/usb/UsbDevice;' ..
    'Landroid/app/PendingIntent;)V')
  jniCallVoid(env, self.manager, req, dev, pi)
  jniDropLocal(env, pi)
  jniDropLocal(env, intent)
  jniDropLocal(env, mgr)
  jniDropLocal(env, piCls)
  jniDropLocal(env, intCls)
end

--- The CMSIS-DAP interface to use, the first candidate; the
--- refs of the others are dropped
--- @param daps table[]
--- @return table? dap
local function pickDap(env, daps)
  local pick = daps[1]
  for _, d in ipairs(daps) do
    if d ~= pick then jniDropGlobal(env, d.iface) end
  end
  return pick
end

--- CDC control interface id, data interface, bulk
--- endpoints, the drive's interface, the CMSIS-DAP
--- interface, and a line on every interface for the log
--- @return table
function AndroidBackend:endpoints(dev)
  local env = self.env
  local devCls = jniClass(env, 'android/hardware/usb/UsbDevice')
  local ifCount = jniMethod(env, devCls,
    'getInterfaceCount', '()I')
  local getIf = jniMethod(env, devCls, 'getInterface',
    '(I)Landroid/hardware/usb/UsbInterface;')
  local ifCls = jniClass(env,
    'android/hardware/usb/UsbInterface')
  local ifClass = jniMethod(env, ifCls,
    'getInterfaceClass', '()I')
  local ifId = jniMethod(env, ifCls, 'getId', '()I')
  local ifSub = jniMethod(env, ifCls,
    'getInterfaceSubclass', '()I')
  local ifProto = jniMethod(env, ifCls,
    'getInterfaceProtocol', '()I')
  local epCount = jniMethod(env, ifCls,
    'getEndpointCount', '()I')
  local getEp = jniMethod(env, ifCls, 'getEndpoint',
    '(I)Landroid/hardware/usb/UsbEndpoint;')
  local epCls = jniClass(env,
    'android/hardware/usb/UsbEndpoint')
  local epType = jniMethod(env, epCls, 'getType', '()I')
  local epDir = jniMethod(env, epCls, 'getDirection', '()I')
  local epAddr = jniMethod(env, epCls, 'getAddress', '()I')
  local epMax = jniMethod(env, epCls,
    'getMaxPacketSize', '()I')
  local found = { lines = {}, daps = {} }
  for i = 0, jniCallInt(env, dev, ifCount) - 1 do
    local iface = jniCallObj(env, dev, getIf, i)
    local cls = jniCallInt(env, iface, ifClass)
    local eps = {}
    local line = string.format(
      'interface index %d id %d class %d subclass %d'
      .. ' protocol %d endpoints', i,
      jniCallInt(env, iface, ifId), cls,
      jniCallInt(env, iface, ifSub),
      jniCallInt(env, iface, ifProto))
    for j = 0, jniCallInt(env, iface, epCount) - 1 do
      local ep = jniCallObj(env, iface, getEp, j)
      local e = {
        type = jniCallInt(env, ep, epType),
        dirIn = jniCallInt(env, ep, epDir) == DIR_IN,
        addr = jniCallInt(env, ep, epAddr),
        max = jniCallInt(env, ep, epMax),
        index = j,
      }
      eps[#eps + 1] = e
      line = line .. string.format(' 0x%02X/%s/%d', e.addr,
        ({ [0] = 'ctrl', 'iso', 'bulk', 'int' })[e.type]
        or tostring(e.type), e.max)
      jniDropLocal(env, ep)
    end
    found.lines[#found.lines + 1] = line
    if cls == VENDOR then
      local inE, outE
      for _, e in ipairs(eps) do
        if e.type == EP_BULK then
          if e.dirIn and not inE then inE = e end
          if not e.dirIn and not outE then outE = e end
        end
      end
      if inE and outE then
        found.daps[#found.daps + 1] = {
          iface = jniGlobal(env, iface),
          id = jniCallInt(env, iface, ifId),
          inAddr = inE.addr, outAddr = outE.addr,
        }
      end
    end
    if cls == MASS_STORAGE and not found.msc then
      found.msc = jniGlobal(env, iface)
    elseif cls == CDC_COMM and not found.commId then
      found.commId = jniCallInt(env, iface, ifId)
      found.comm = jniGlobal(env, iface)
    elseif cls == CDC_DATA and not found.data then
      found.data = jniGlobal(env, iface)
      for j = 0, jniCallInt(env, iface, epCount) - 1 do
        local ep = jniCallObj(env, iface, getEp, j)
        if jniCallInt(env, ep, epType) == EP_BULK then
          if jniCallInt(env, ep, epDir) == DIR_IN then
            found.epIn = jniGlobal(env, ep)
          else
            found.epOut = jniGlobal(env, ep)
          end
        end
        jniDropLocal(env, ep)
      end
    end
    jniDropLocal(env, iface)
  end
  jniDropLocal(env, epCls)
  jniDropLocal(env, ifCls)
  jniDropLocal(env, devCls)
  found.dap = pickDap(env, found.daps)
  return found
end

--- 115200 baud, 8N1, then DTR/RTS. Both requests address the
--- control interface, which is why it is claimed too. A
--- refusal is recorded, not fatal: the interface chip already
--- runs the target UART at the protocol rate.
--- @return string? refusal
function AndroidBackend:configureAcm(port)
  local env = self.env
  local coding = string.char(0x00, 0xC2, 0x01, 0x00, 0, 0, 8)
  local arr = jniBytes(env, coding)
  local rc = jniCallInt(env, port.conn, port.ctrlM,
    ACM_CLASS_IFACE, ACM_LINE_CODING, 0, port.commId,
    arr, #coding, CTRL_MS)
  local rc2 = jniCallInt(env, port.conn, port.ctrlM,
    ACM_CLASS_IFACE, ACM_LINE_STATE, ACM_DTR_AND_RTS,
    port.commId, nil, 0, CTRL_MS)
  jniDropLocal(env, arr)
  if rc < 0 or rc2 < 0 then
    return 'line coding ' .. rc .. ', dtr ' .. rc2
  end
end

--- Connection, interface claims, ACM setup
--- @return table? port
--- @return string? fault
function AndroidBackend:openDevice(entry)
  local env = self.env
  local mgr = jniClass(env, 'android/hardware/usb/UsbManager')
  local openM = jniMethod(env, mgr, 'openDevice',
    '(Landroid/hardware/usb/UsbDevice;)' ..
    'Landroid/hardware/usb/UsbDeviceConnection;')
  local conn = jniCallObj(env, self.manager, openM, entry.dev)
  jniDropLocal(env, mgr)
  if conn == nil then
    return nil, 'openDevice returned null'
  end
  local connCls = jniClass(env,
    'android/hardware/usb/UsbDeviceConnection')
  local eps = self:endpoints(entry.dev)
  for _, line in ipairs(eps.lines) do log(line) end
  if not (eps.comm and eps.data and eps.epIn and eps.epOut
      and eps.commId) then
    jniCallVoid(env, conn,
      jniMethod(env, connCls, 'close', '()V'))
    jniDropLocal(env, conn)
    jniDropLocal(env, connCls)
    for _, k in ipairs({ 'comm', 'data', 'epIn', 'epOut',
      'msc' }) do
      jniDropGlobal(env, eps[k])
    end
    if eps.dap then jniDropGlobal(env, eps.dap.iface) end
    -- the interface chip's maintenance mode, entered when
    -- the board is plugged in with its reset button held,
    -- lists its drive and nothing else
    if eps.msc and not eps.comm and not eps.data then
      return nil, 'maintenance mode'
    end
    return nil, 'CDC interface set incomplete'
  end
  local port = {
    conn = jniGlobal(env, conn),
    comm = eps.comm,
    data = eps.data,
    epIn = eps.epIn,
    epOut = eps.epOut,
    commId = eps.commId,
    msc = eps.msc,
    dap = eps.dap,
    claimM = jniMethod(env, connCls, 'claimInterface',
      '(Landroid/hardware/usb/UsbInterface;Z)Z'),
    releaseM = jniMethod(env, connCls, 'releaseInterface',
      '(Landroid/hardware/usb/UsbInterface;)Z'),
    closeM = jniMethod(env, connCls, 'close', '()V'),
    fdM = jniMethod(env, connCls, 'getFileDescriptor', '()I'),
    bulkM = jniMethod(env, connCls, 'bulkTransfer',
      '(Landroid/hardware/usb/UsbEndpoint;[BII)I'),
    ctrlM = jniMethod(env, connCls, 'controlTransfer',
      '(IIII[BII)I'),
  }
  jniDropLocal(env, conn)
  jniDropLocal(env, connCls)
  local rx = env[0].NewByteArray(env, RX_SIZE)
  port.rx = jniGlobal(env, rx)
  jniDropLocal(env, rx)
  if not jniCallBool(env, port.conn, port.claimM,
      port.comm, true) then
    self:release(port)
    return nil, 'control interface refused'
  end
  if not jniCallBool(env, port.conn, port.claimM,
      port.data, true) then
    self:release(port)
    return nil, 'data interface refused'
  end
  port.acm = self:configureAcm(port)
  self:claimDap(port)
  return port
end

--- The CMSIS-DAP interface, claimed with force on the same
--- connection, and the link to the chip on it. Its absence
--- or a refusal is logged, not fatal: the serial terminal
--- works without it.
function AndroidBackend:claimDap(port)
  local env = self.env
  local dap = port.dap
  if not dap then
    log('no CMSIS-DAP v2 interface: no vendor interface with'
      .. ' bulk endpoints')
    return
  end
  log(string.format('chose interface id %d: vendor class,'
    .. ' bulk endpoints (CMSIS-DAP v2); in 0x%02X, out 0x%02X',
    dap.id, dap.inAddr, dap.outAddr))
  local ok, took = pcall(jniCallBool, env, port.conn,
    port.claimM, dap.iface, true)
  if not (ok and took) then
    log('claim of the CMSIS-DAP interface refused: '
      .. tostring(took))
    return
  end
  dap.claimed = true
  local fok, fd = pcall(jniCallInt, env, port.conn, port.fdM)
  if not fok or fd < 0 then
    log('no file descriptor for the connection: '
      .. tostring(fd))
    return
  end
  port.link = DapLink.new(Usbfs.new(fd), dap.outAddr,
    dap.inAddr, log, now)
  port.link:start()
  log('CMSIS-DAP interface claimed, descriptor ' .. fd)
end

--- The one close path: interfaces, connection, refs. A
--- drive still taken is handed back first: closing alone
--- would leave it with no driver until the board is
--- plugged in again.
function AndroidBackend:release(port)
  local env = self.env
  if port.storageTaken then
    port.storageTaken = false
    local ok, gave = pcall(jniCallBool, env, port.conn,
      port.releaseM, port.msc)
    log('drive handed back on close: ' .. tostring(ok and gave))
  end
  -- the link stops touching the descriptor before it closes
  if port.link then
    port.link:kill()
    port.link = nil
  end
  local dap = port.dap
  if dap then
    if dap.claimed then
      pcall(jniCallBool, env, port.conn, port.releaseM,
        dap.iface)
    end
    jniDropGlobal(env, dap.iface)
    port.dap = nil
  end
  if port.claimed ~= false then
    pcall(jniCallBool, env, port.conn, port.releaseM,
      port.comm)
    pcall(jniCallBool, env, port.conn, port.releaseM,
      port.data)
  end
  pcall(jniCallVoid, env, port.conn, port.closeM)
  jniDropGlobal(env, port.msc)
  jniDropGlobal(env, port.rx)
  jniDropGlobal(env, port.epIn)
  jniDropGlobal(env, port.epOut)
  jniDropGlobal(env, port.comm)
  jniDropGlobal(env, port.data)
  jniDropGlobal(env, port.conn)
end

--- One bulk-in slice; '' when the slice brought nothing
--- @return string
function AndroidBackend:read()
  local env = self.env
  local port = self.port
  local n = jniCallInt(env, port.conn, port.bulkM,
    port.epIn, port.rx, RX_SIZE, READ_MS)
  if n <= 0 then return '' end
  return jniReadBytes(env, port.rx, n)
end

--- Queued, not written here: the bytes leave one per poll,
--- see TX_PER_POLL. A refusal therefore arrives as a fault
--- on the poll that does the write, not from this call.
--- @param data string
--- @return boolean? ok
--- @return string? err
function AndroidBackend:send(data)
  if self.state ~= 'open' then
    return nil, 'no device connected'
  end
  self.tx = self.tx .. data
  return true
end

--- One slice of the outgoing queue
--- @return string? fault
function AndroidBackend:write()
  if self.tx == '' then return end
  local env = self.env
  local port = self.port
  local out = self.tx:sub(1, TX_PER_POLL)
  local arr = jniBytes(env, out)
  local n = jniCallInt(env, port.conn, port.bulkM,
    port.epOut, arr, #out, WRITE_MS)
  jniDropLocal(env, arr)
  if n ~= #out then
    self.tx = ''
    return 'bulk write sent ' .. n .. ' of ' .. #out
  end
  self.tx = self.tx:sub(#out + 1)
end

--- Is the open device still on the bus? Takes no global
--- refs: this runs every second for as long as a port is open
function AndroidBackend:present()
  local here = false
  self:eachDevice(function(_, name)
    if name == self.dev.name then here = true end
  end)
  return here
end

function AndroidBackend:dropDevice()
  self.port = nil
  self.dev = nil
  self.state = 'idle'
  self.extras_told = false
end

--- What send queued and has not written yet goes
function AndroidBackend:drop()
  self.tx = ''
end

--- A break of the given length, 0 to end one
--- @param ms integer
--- @return integer rc
function AndroidBackend:sendBreak(ms)
  return jniCallInt(self.env, self.port.conn,
    self.port.ctrlM, ACM_CLASS_IFACE, ACM_SEND_BREAK, ms,
    self.port.commId, nil, 0, CTRL_MS)
end

--- The board restarts, as its reset button makes it: a break
--- down the cable, then its end, which the micro:bit's USB
--- chip answers with a reset. The end goes even when the
--- start was refused; if the end itself is refused, the
--- board may stay held until its reset button is pressed.
--- The chip ignores a break while it writes new firmware, and
--- takes it without a word, so true means sent, not done.
--- @return boolean? ok
--- @return string? err
function AndroidBackend:reset()
  if self.state ~= 'open' then
    return nil, 'no device connected'
  end
  local rc = self:sendBreak(BREAK_MS)
  local rc2 = self:sendBreak(0)
  if rc < 0 or rc2 < 0 then
    return nil, 'break ' .. rc .. ', end ' .. rc2
  end
  return true
end

--- Take the board's drive from Android: claimed with force,
--- which detaches Android's storage driver, so Android lets
--- go of the drive. The serial interfaces stay as they are.
--- @return boolean? ok
--- @return string? err
function AndroidBackend:takeStorage()
  if self.state ~= 'open' then
    return nil, 'no device connected'
  end
  local port = self.port
  if not port.msc then
    return nil, 'no mass-storage interface'
  end
  local ok, took = pcall(jniCallBool, self.env, port.conn,
    port.claimM, port.msc, true)
  if not ok then return nil, tostring(took) end
  if not took then
    return nil, 'mass-storage interface refused'
  end
  port.storageTaken = true
  return true
end

--- Give the drive back. Android's release hands the
--- interface to its storage driver again, which reads the
--- drive afresh.
--- @return boolean? ok
--- @return string? err
function AndroidBackend:giveStorage()
  if self.state ~= 'open' then
    return nil, 'no device connected'
  end
  local port = self.port
  if not port.storageTaken then
    return nil, 'mass-storage interface not taken'
  end
  port.storageTaken = false
  local ok, gave = pcall(jniCallBool, self.env, port.conn,
    port.releaseM, port.msc)
  if not ok then return nil, tostring(gave) end
  if not gave then
    return nil, 'mass-storage interface not released'
  end
  return true
end

--- The link to the board's interface chip, for a flash
--- @return DapLink? link
--- @return string? err
function AndroidBackend:dap()
  if self.state ~= 'open' then
    return nil, 'no device connected'
  end
  if not self.port.link then
    return nil, 'no CMSIS-DAP interface'
  end
  -- a drive Android still has mounted is one it may write to
  -- while the chip takes a file
  if not self.port.storageTaken then
    return nil, 'drive not held'
  end
  return self.port.link
end

--- Why the board on the bus could not be opened, when one
--- was there at the last look: 'maintenance mode', or
--- another reason for the log
--- @return string?
function AndroidBackend:absence()
  if self.state == 'open' then return nil end
  return self.refused
end

--- What the chip said about the board on open: its unique
--- id and the interface firmware's version, once answered
--- @return table? info { id, firmware }
function AndroidBackend:board()
  if self.state ~= 'open' then return nil end
  return self.port.board
end

--- Ask the chip who it is, without waiting, once the link is
--- in step with it: the answers come through pollOpen. The
--- first proof that commands arrive.
function AndroidBackend:probe(port)
  local link = port.link
  if not link or port.probed or link:room() < 2 then return end
  port.probed = true
  local t0 = now()
  local board = {}
  link:send(Dap.packet(Dap.UNIQUE_ID), function(raw)
    board.id = Dap.text(Dap.UNIQUE_ID, raw)
    log(string.format('unique id: %s (%.3f s)',
      tostring(board.id), now() - t0))
  end)
  link:send(Dap.packet(Dap.INFO, string.char(Dap.INFO_FIRMWARE)),
    function(raw)
      board.firmware = Dap.text(Dap.INFO, raw)
      log(string.format('interface firmware: %s (%.3f s)',
        board.firmware ~= '' and tostring(board.firmware)
        or 'not said', now() - t0))
      port.board = board
    end)
end

--- Called on detach and on stop
function AndroidBackend:closePort(notify)
  self:drop()
  if self.port then self:release(self.port) end
  jniDropGlobal(self.env, self.dev and self.dev.dev)
  self:dropDevice()
  if notify then self.sink.detach() end
end

--- Nothing on the bus yet, or a candidate to open
--- @return string? fault
function AndroidBackend:pollIdle()
  if now() < self.due then return end
  self.due = now() + SCAN_S
  local found = self:scan()
  if #found == 0 then
    self.refused = nil
    return
  end
  self.dev = found[1]
  for i = 2, #found do
    jniDropGlobal(self.env, found[i].dev)
  end
  if #found > 1 then
    self.extras_told = true
  end
  if not self:hasPermission(self.dev.dev) then
    self:askPermission(self.dev.dev)
    self.state = 'permission'
    self.due = now() + PERMISSION_S
    return
  end
  return self:openReady()
end

--- Permission is in hand; open and announce
--- @return string? fault
function AndroidBackend:openReady()
  local port, fault = self:openDevice(self.dev)
  self.refused = fault
  if not port then
    jniDropGlobal(self.env, self.dev.dev)
    self:dropDevice()
    self.due = now() + SCAN_S
    return fault
  end
  self.port = port
  self.state = 'open'
  local ok, err = self:takeStorage()
  log('drive hold on open: ' .. (ok and 'taken'
    or ('not taken, ' .. tostring(err))))
  self.sink.attach({ name = self.dev.name, acm = port.acm })
  if self.extras_told then
    return 'extra micro:bit ignored'
  end
end

--- @return string? fault
function AndroidBackend:pollPermission()
  if self:hasPermission(self.dev.dev) then
    return self:openReady()
  end
  if now() < self.due then return end
  jniDropGlobal(self.env, self.dev.dev)
  self:dropDevice()
  self.due = now() + SCAN_S
  return 'permission not granted'
end

--- A detached device answers no control request, while the
--- bus list can keep the entry for minutes: the framework
--- holds it as long as this process keeps the connection
--- open, and this process waits for the entry to go.
--- Skipped when the board refused ACM setup, since then a
--- refusal says nothing about presence.
--- @return boolean
function AndroidBackend:answers()
  if self.port.acm then return true end
  local rc = jniCallInt(self.env, self.port.conn,
    self.port.ctrlM, ACM_CLASS_IFACE, ACM_LINE_STATE,
    ACM_DTR_AND_RTS, self.port.commId, nil, 0, CTRL_MS)
  return rc >= 0
end

--- @return string? fault
function AndroidBackend:pollOpen()
  if self.port.link then
    self.port.link:pump()
    self:probe(self.port)
  end
  local chunk = self:read()
  if chunk ~= '' then self.sink.bytes(chunk) end
  local fault = self:write()
  if fault then return fault end
  if now() < self.due then return end
  self.due = now() + PRESENCE_S
  local listed = self:present()
  if listed and self:answers() then return end
  self:closePort(true)
  if listed then
    return 'device stopped answering, still on the bus'
  end
end

--- One step of device work; call once per update loop
--- @return string? fault
function AndroidBackend:poll()
  if self.state == 'open' then return self:pollOpen() end
  if self.state == 'permission' then
    return self:pollPermission()
  end
  return self:pollIdle()
end

function AndroidBackend:stop()
  if self.state ~= 'idle' then self:closePort(false) end
  jniDropGlobal(self.env, self.manager)
  self.manager = nil
end
