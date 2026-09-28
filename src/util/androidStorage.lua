--- Finds the SD card among Android's portable volumes.
---
--- Android mounts USB mass storage like the SD card, so a
--- micro:bit plugged in over USB shows up as a second
--- /storage/XXXX-XXXX volume. The block device behind
--- each volume's vold mount tells them apart: MMC devices,
--- the SD card slot among them, use major 179, and USB
--- storage is a SCSI disk. An SD card in a USB card
--- reader is a SCSI disk too, so only a card in the
--- built-in slot is chosen.
---
--- A volume is the card only when its vold line shows the
--- MMC device. A volume without one may be a micro:bit
--- drive or a card reader, so it is never chosen; with no
--- card found the IDE uses internal storage.

local MMC_BLOCK_MAJOR = 179

local hex4 = string.rep('[0-9A-F]', 4)
local fuse_root = '^/dev/fuse (/storage/('
  .. hex4 .. '%-' .. hex4 .. ')) '
local vold_mount = '^/dev/block/vold/public:(%d+),%d+ '
  .. '/mnt/media_rw/(%S+) '

--- @param mounts string the text of /proc/mounts
--- @return string? root the SD card's storage root, nil
---   when no volume shows the MMC device
local function find_card(mounts)
  if type(mounts) ~= 'string' then return nil end
  local roots = {}
  local majors = {}
  for line in string.gmatch(mounts .. '\n', '([^\n]*)\n') do
    local root, uuid = line:match(fuse_root)
    if root then
      table.insert(roots, { path = root, uuid = uuid })
    end
    local major, mounted = line:match(vold_mount)
    if major then
      majors[string.upper(mounted)] = tonumber(major)
    end
  end
  for _, r in ipairs(roots) do
    if majors[r.uuid] == MMC_BLOCK_MAJOR then return r.path end
  end
  return nil
end

return {
  find_card = find_card,
}
