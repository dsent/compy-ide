local OS = require("util.os") --- pulls in string
local FS = require("util.filesystem")

--- Detect a connected USB mass-storage device (micro:bit,
--- or a flashdrive configured via conf.lua). Runs on demand so
--- devices plugged in after startup are found (hot-plug).
--- Works on Linux and Android (Android is the main target).
local usb = {}

usb.MICROBIT_LABEL = 'MICROBIT'
--- DAPLink drives (micro:bit v1/v2) ship this file at the root
usb.MICROBIT_MARKER = 'DETAILS.TXT'

local supported_os = {
  Linux = true,
  Android = true,
}


--- @param n integer|string
--- @return string
local function hex4(n)
  if type(n) == 'string' then
    local h = string.match(n, '0?[xX]?(%x+)')
    if h then
      n = tonumber(h, 16) or 0
    end
  end
  return string.format('%04x', tonumber(n) or 0)
end

--- @return string vid
--- @return string pid
local function vid_pid()
  local l = (type(love) == 'table') and love or {}
  return hex4(l.microbit_vid or 0x0d28),
      hex4(l.microbit_pid or 0x0204)
end

--- Parse /proc/mounts-style lines.
--- @param mounts string
--- @return table {device=..., path=..., type=...}[]
function usb.parse_mounts(mounts)
  local out = {}
  for _, line in ipairs(string.lines(mounts or '')) do
    local dev, path, fstype = line:match('^(%S+) (%S+) (%S+)')
    if dev and path and fstype then
      table.insert(out, {
        device = dev,
        path = path,
        type = fstype,
      })
    end
  end
  return out
end

--- Candidate removable-storage mount
--- @param fstype string
--- @param path string
--- @return boolean
function usb.is_removable_fat(fstype, path)
  if fstype ~= 'vfat' and fstype ~= 'exfat' and fstype ~= 'msdos'
      and fstype ~= 'fuseblk' and fstype ~= 'fuse' then
    return false
  end
  return string.matches_r(path, '^/storage/')
      or string.matches_r(path, '^/mnt/')
      or string.matches_r(path, '^/media/')
      or string.matches_r(path, '^/run/media/')
end

--- VID/PID via udevadm (Linux desktop only)
--- @param dev string
--- @return string? vid
--- @return string? pid
local function vidpid_udevadm(dev)
  local _, out = OS.runcmd(
    string.format('udevadm info --query=property --name=%s 2>/dev/null', dev))
  local vid, pid
  for line in (out or ''):gmatch('[^\n]+') do
    vid = line:match('^ID_USB_VENDOR_ID=(.*)$') or vid
    pid = line:match('^ID_USB_MODEL_ID=(.*)$') or pid
  end
  return vid, pid
end

--- @param path string
--- @return string? first line
local function read_small(path)
  local f = io.open(path, 'r')
  if not f then return nil end
  local c = f:read('*l')
  f:close()
  return c
end

--- Resolve a block device (e.g. /dev/sdb1, /dev/block/vold/8:1)
--- to its sysfs path.
--- @param dev string
--- @return string? sysfs path
local function block_sysfs(dev)
  local base = dev:match('([^/]+)$')
  if not base or base == '' then return nil end
  if base:match('%d+:%d+') then
    --- Android vold style: /sys/dev/block/8:1
    local ok, r = OS.runcmd('readlink -f /sys/dev/block/' .. base)
    if ok and r and r ~= '' then return r end
  end
  local ok, r = OS.runcmd('readlink -f /sys/class/block/' .. base)
  if ok and r and r ~= '' then return r end
  return nil
end

--- Walk sysfs up to the USB device to find idVendor/idProduct.
--- Works on Linux and Android (no udevadm needed).
--- @param dev string
--- @return string? vid
--- @return string? pid
local function vidpid_sysfs(dev)
  local bp = block_sysfs(dev)
  if not bp then return nil, nil end
  for _ = 1, 14 do
    local v = read_small(bp .. '/idVendor')
    local p = read_small(bp .. '/idProduct')
    if v and p then return v, p end
    local parent = bp:match('^(.*/)[^/]+$')
    if not parent then return nil, nil end
    bp = parent:gsub('/+$', '')
  end
  return nil, nil
end

--- @param dev string
--- @return string? vid
--- @return string? pid
local function vidpid_for(dev)
  local vid, pid = vidpid_udevadm(dev)
  if vid and pid then return vid, pid end
  return vidpid_sysfs(dev)
end

--- @param path string
--- @return boolean
local function label_matches(path)
  return (string.match(path, '/([^/]+)$') or ''):upper()
      == usb.MICROBIT_LABEL
end

--- @param path string
--- @return boolean
local function marker_present(path)
  return FS.exists(FS.join_path(path, usb.MICROBIT_MARKER), 'file')
end

--- Detect a USB mass-storage device matching the configured
--- VID/PID (conf.lua), falling back to the MICROBIT volume label
--- and then the DAPLink marker file.
--- Re-runs every call, so a device plugged in later is found.
--- @return string? path mount point (root of the device)
function usb.detect()
  local os_name = OS.get_name()
  if not supported_os[os_name] then
    return nil
  end
  local vid, pid = vid_pid()
  local _, mounts = OS.runcmd('cat /proc/mounts')
  local candidates = {}
  for _, m in ipairs(usb.parse_mounts(mounts or '')) do
    if usb.is_removable_fat(m.type, m.path) then
      table.insert(candidates, m)
    end
  end

  --- VID/PID match first (also the flashdrive test case)
  for _, m in ipairs(candidates) do
    local v, p = vidpid_for(m.device)
    if v and p and string.lower(v) == vid
        and string.lower(p) == pid then
      return m.path
    end
  end
  --- then the volume label
  for _, m in ipairs(candidates) do
    if label_matches(m.path) then
      return m.path
    end
  end
  --- then the DAPLink marker file (real micro:bit, VID/PID read
  --- may have failed on Android)
  for _, m in ipairs(candidates) do
    if marker_present(m.path) then
      return m.path
    end
  end
  return nil
end

return usb
