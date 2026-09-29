--- Asynchronous transfers on a USB device's file descriptor,
--- through Linux usbfs, which the Android USB host API is
--- built on. A transfer is submitted and returns at once; it
--- completes in the kernel whenever the device answers, and
--- stays there, data and all, until it is reaped. Nothing
--- is lost to a timeout, as a short blocking read can lose a
--- reply that arrives just as it gives up.
---
--- The kernel copies a reply into its buffer only while it is
--- reaped, so a buffer stays referenced from `live` until
--- then; closing the descriptor drops what was never reaped.
---
--- Source: linux include/uapi/linux/usbdevice_fs.h and
--- drivers/usb/core/devio.c; AOSP libusbhost usbhost.c reaps
--- the same way.

local ffi = require('ffi')
local bit = require('bit')

--- Each alone: a declaration another module made first must
--- not keep the others out
for _, decl in ipairs({
  [[struct compy_usbfs_urb {
    unsigned char type;
    unsigned char endpoint;
    int status;
    unsigned int flags;
    void *buffer;
    int buffer_length;
    int actual_length;
    int start_frame;
    int number_of_packets;
    int error_count;
    unsigned int signr;
    void *usercontext;
  };]],
  [[struct compy_pollfd { int fd; short events; short revents; };]],
  [[int ioctl(int fd, unsigned long request, ...);]],
  [[int poll(struct compy_pollfd *fds, unsigned int n,
    int timeout);]],
}) do
  pcall(ffi.cdef, decl)
end

--- @class Usbfs
--- @field new function
Usbfs = {}
Usbfs.__index = Usbfs

--- _IOC for arm, arm64 and x86: direction in the top two
--- bits, then the size, the type 'U' and the number
--- @param dir integer 0 none, 1 write, 2 read
--- @param nr integer
--- @param size integer
--- @return number
local function ioc(dir, nr, size)
  return dir * 2 ^ 30 + size * 2 ^ 16 + 0x55 * 2 ^ 8 + nr
end

Usbfs.URB_SIZE = ffi.sizeof('struct compy_usbfs_urb')
Usbfs.SUBMITURB = ioc(2, 10, Usbfs.URB_SIZE)
Usbfs.REAPURBNDELAY = ioc(1, 13, ffi.sizeof('void *'))

local URB_TYPE_BULK = 3
local POLLOUT = 0x0004
local EAGAIN = 11

--- @param fd integer the connection's file descriptor
--- @param sys table? ioctl, poll and errno, for tests;
---   the C library when absent
--- @return Usbfs
function Usbfs.new(fd, sys)
  local self = setmetatable({}, Usbfs)
  self.fd = fd
  self.live = {}
  self.sys = sys or {
    ioctl = ffi.C.ioctl,
    poll = ffi.C.poll,
    errno = ffi.errno,
  }
  return self
end

--- @param p any a pointer
--- @return number
local function key(p)
  return tonumber(ffi.cast('uintptr_t', p))
end

--- Submit one bulk transfer. Out when data is a string, in
--- for a reply of up to data bytes when it is a number.
--- @param endpoint integer the endpoint address
--- @param data string|integer
--- @return boolean? ok
--- @return string? err
function Usbfs:submit(endpoint, data)
  local len = type(data) == 'string' and #data or data
  local buf = ffi.new('uint8_t[?]', math.max(len, 1))
  if type(data) == 'string' then ffi.copy(buf, data, len) end
  -- an array of one: ioctl takes varargs, where LuaJIT
  -- passes a struct by value and an array as a pointer
  local urb = ffi.new('struct compy_usbfs_urb[1]')
  urb[0].type = URB_TYPE_BULK
  urb[0].endpoint = endpoint
  urb[0].buffer = buf
  urb[0].buffer_length = len
  local rc = self.sys.ioctl(self.fd, Usbfs.SUBMITURB, urb)
  if rc < 0 then
    return nil, 'submit errno ' .. self.sys.errno()
  end
  self.live[key(urb)] = { urb = urb, buf = buf,
    endpoint = endpoint }
  return true
end

--- One finished transfer, or nil when none has finished
--- @return table? done endpoint, status, actual, data (in)
--- @return string? err
function Usbfs:reap()
  local out = ffi.new('void *[1]')
  local rc = self.sys.ioctl(self.fd, Usbfs.REAPURBNDELAY, out)
  if rc < 0 then
    local e = self.sys.errno()
    if e == EAGAIN then return nil end
    return nil, 'reap errno ' .. e
  end
  local k = key(out[0])
  local entry = self.live[k]
  if not entry then return nil, 'reaped an unknown transfer' end
  self.live[k] = nil
  local urb = entry.urb[0]
  local done = {
    endpoint = entry.endpoint,
    status = urb.status,
    actual = urb.actual_length,
  }
  if bit.band(entry.endpoint, 0x80) ~= 0 and urb.status == 0
  then
    done.data = ffi.string(entry.buf, urb.actual_length)
  end
  return done
end

--- Wait up to ms for a transfer to finish
--- @param ms integer
--- @return boolean ready
function Usbfs:wait(ms)
  local p = ffi.new('struct compy_pollfd[1]')
  p[0].fd = self.fd
  p[0].events = POLLOUT
  return self.sys.poll(p, 1, ms) > 0
end

--- How many transfers are still in the kernel
--- @return integer
function Usbfs:inFlight()
  local n = 0
  for _ in pairs(self.live) do n = n + 1 end
  return n
end
