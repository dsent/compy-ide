--- The micro:bit's USB interface chip (DAPLink) speaks
--- CMSIS-DAP and adds vendor commands of its own. Four of
--- them put a hex file on the board without its drive: open
--- a stream, write the file into it, close it, reset the
--- board. This file builds their packets and reads their
--- replies; it touches no hardware.
---
--- Source: DAPLink interface firmware 0257 (git c782a5ba),
--- source/daplink/cmsis-dap/DAP_vendor.c and
--- daplink_vendor_commands.h; the status codes are error_t in
--- source/daplink/error.h, numbered in its order.
---
--- Every request is one packet of 64 bytes: the command, its
--- payload, zeros after. Every reply starts with the command
--- it answers.

require('model.serial.intel_hex')

--- @class Dap
Dap = {}

--- Every log line of the micro:bit's USB path starts with
--- this, so the device log can be searched for it
Dap.TAG = 'DAPFLASH '

--- A line for the device log, under TAG
--- @param msg string
function Dap.log(msg)
  local out = rawget(_G, 'orig_print') or print
  out(Dap.TAG .. msg)
end

Dap.PACKET = 64
--- The most file one write command carries: the packet less
--- the command and the length byte
Dap.CHUNK = Dap.PACKET - 2

Dap.INFO = 0x00
Dap.UNIQUE_ID = 0x80
Dap.RESET_TARGET = 0x89
Dap.OPEN = 0x8A
Dap.CLOSE = 0x8B
Dap.WRITE = 0x8C

--- DAP_Info asks: the interface firmware's own version, such
--- as "0257" (DAP_ID_PRODUCT_FW_VER); firmware before 0257
--- answers it with nothing
Dap.INFO_FIRMWARE = 0x09
--- The stream type open takes: 0 a binary image, 1 a hex file
Dap.STREAM_HEX = 1

--- error_t in 0257, in order from 0. 0254 to 0258 number
--- 0 to 28 alike (0254 lacks 29, FD_INCOMPATIBLE_IMAGE);
--- before 0254 the table differs from 9 on. Only a V2 board
--- is flashed, and V2 boards ship with 0255 or later. The
--- flash decides on 0, 2 and 19 alone; the other names are
--- for the log.
local NAMES = {
  [0] = 'SUCCESS', 'FAILURE', 'INTERNAL',
  'ERROR_DURING_TRANSFER', 'TRANSFER_TIMEOUT', 'FILE_BOUNDS',
  'OOO_SECTOR', 'RESET', 'ALGO_DL', 'ALGO_MISSING',
  'ALGO_DATA_SEQ', 'INIT', 'UNINIT', 'SECURITY_BITS',
  'UNLOCK', 'ERASE_SECTOR', 'ERASE_ALL', 'WRITE',
  'WRITE_VERIFY', 'SUCCESS_DONE', 'SUCCESS_DONE_OR_CONTINUE',
  'HEX_CKSUM', 'HEX_PARSER', 'HEX_PROGRAM',
  'HEX_INVALID_ADDRESS', 'HEX_INVALID_APP_OFFSET',
  'FD_BL_UPDT_ADDR_WRONG', 'FD_INTF_UPDT_ADDR_WRONG',
  'FD_UNSUPPORTED_UPDATE', 'FD_INCOMPATIBLE_IMAGE',
  'IAP_INIT', 'IAP_UNINIT', 'IAP_WRITE', 'IAP_ERASE_SECTOR',
  'IAP_ERASE_ALL', 'IAP_OUT_OF_BOUNDS',
  'IAP_UPDT_NOT_SUPPORTED', 'IAP_UPDT_INCOMPLETE',
  'IAP_NO_INTERCEPT', 'BL_UPDT_BAD_CRC',
}

Dap.SUCCESS = 0
Dap.INTERNAL = 2
Dap.DONE = 19
Dap.DONE_OR_CONTINUE = 20

--- @param code integer
--- @return string
function Dap.statusName(code)
  return (NAMES[code] or 'UNKNOWN') .. ' (' .. code .. ')'
end

-- the Compy writes the file the chip reads, so a record the
-- chip cannot read was damaged on its way down the cable
local DAMAGED = 'The file was damaged on its way to the'
    .. ' micro:bit. Unplug it, plug it back in, then send the'
    .. ' file again.'
local FOREIGN = 'This file is not made for this micro:bit. Use'
    .. ' a file made for a micro:bit V2.'
local MEMORY = 'The micro:bit could not write the file into'
    .. ' its memory. Unplug it, plug it back in, then send the'
    .. ' file again.'
local BUSY = 'The micro:bit was still busy with an earlier'
    .. ' file. Unplug it, plug it back in, then send the file'
    .. ' again.'
local REFUSED = 'The micro:bit refused the file. Unplug it,'
    .. ' plug it back in, then send the file again.'

local PLAIN = {
  [2] = BUSY,
  [7] = MEMORY, [8] = MEMORY, [9] = MEMORY, [10] = MEMORY,
  [11] = MEMORY, [12] = MEMORY, [14] = MEMORY, [15] = MEMORY,
  [16] = MEMORY, [17] = MEMORY, [18] = MEMORY,
  [13] = FOREIGN, [24] = FOREIGN, [25] = FOREIGN,
  [28] = FOREIGN, [29] = FOREIGN,
  [21] = DAMAGED, [22] = DAMAGED, [23] = DAMAGED,
}

--- For a micro:bit V1: the Compy sends files to a V2 only
Dap.V1_BOARD = 'This is a micro:bit V1, and the Compy sends'
    .. ' files only to a micro:bit V2. Use a micro:bit V2.'

--- What a status means for the person at the Compy
--- @param code integer
--- @return string
function Dap.plain(code)
  return PLAIN[code] or REFUSED
end

--- One request packet: command, payload, zeros to 64 bytes
--- @param cmd integer
--- @param payload string?
--- @return string
function Dap.packet(cmd, payload)
  local body = string.char(cmd) .. (payload or '')
  assert(#body <= Dap.PACKET, 'DAP packet too long')
  return body .. string.rep('\0', Dap.PACKET - #body)
end

--- A write command carrying up to CHUNK bytes of the file
--- @param chunk string
--- @return string
function Dap.writePacket(chunk)
  assert(#chunk <= Dap.CHUNK, 'DAP write chunk too long')
  return Dap.packet(Dap.WRITE, string.char(#chunk) .. chunk)
end

--- The byte after the command in a reply to cmd: a status,
--- or a length; nil and why when the reply answers another
--- command or is too short
--- @param cmd integer
--- @param raw string
--- @return integer? status
--- @return string? err
function Dap.status(cmd, raw)
  if #raw < 1 then return nil, 'empty reply' end
  if raw:byte(1) ~= cmd then
    return nil, string.format('reply to 0x%02X, not 0x%02X',
      raw:byte(1), cmd)
  end
  if #raw < 2 then return nil, 'reply without status' end
  return raw:byte(2)
end

--- The text a length-prefixed reply to cmd carries: the
--- unique id, or a DAP_Info string less its closing zero
--- @param cmd integer
--- @param raw string
--- @return string? text
--- @return string? err
function Dap.text(cmd, raw)
  local len, err = Dap.status(cmd, raw)
  if not len then return nil, err end
  if #raw < 2 + len then return nil, 'reply cut short' end
  return (raw:sub(3, 2 + len):gsub('%z.*$', ''))
end

--- The board's version from its unique id, whose first four
--- digits are the board id: 9900 and 9901 a micro:bit V1,
--- 9903 to 9906 a V2
--- @param id string
--- @return string? 'V1', 'V2', or nil when unknown
function Dap.boardVersion(id)
  local board = tonumber((id or ''):sub(1, 4), 16)
  if board == 0x9900 or board == 0x9901 then return 'V1' end
  if board and board >= 0x9903 and board <= 0x9906 then
    return 'V2'
  end
end

--- Where a program for a micro:bit V2 may put bytes, end
--- exclusive. DAPLink 0257 flashes any address with the
--- nRF52833's algorithm (target_flash.c get_flash_algo falls
--- back to the default region; flash_decoder.c leaves the
--- range check as a TODO), so the Compy sets the bounds:
--- - the program flash, 0 to 512 KB: flash_regions[0] of
---   target_device_nrf52833 (source/family/nordic/nrf52/
---   target.c);
--- - the UICR page, 4 KB from NRF_UICR_BASE 0x10001000
---   (source/hic_hal/nordic/nrf52820/cmsis/nrf52.h), which
---   CODAL programs such as MICROBIT.hex write to.
Dap.REGIONS = {
  { from = 0x00000000, to = 0x00080000 },
  { from = 0x10001000, to = 0x10002000 },
}

--- The micro:bit V2's interface chips, by DAPLINK_HIC_ID
--- (source/daplink/daplink.h): the KL27Z and the nRF52820
local OWN_HIC = { [0x9796990B] = true, [0x6E052820] = true }
--- Where DAPLink looks for an image's own info, and how much
--- it reads before it decides (daplink.h DAPLINK_INFO_OFFSET,
--- flash_decoder.h FLASH_DECODER_MIN_SIZE)
local INFO_OFFSET, DECIDE_SIZE = 0x20, 0x30

--- @param run table { at, data }
--- @return boolean
local function inside(run)
  for _, r in ipairs(Dap.REGIONS) do
    if run.at >= r.from and run.at + #run.data <= r.to then
      return true
    end
  end
  return false
end

--- Would the chip take this image for software of its own?
--- It reads the first DECIDE_SIZE bytes of the file's first
--- data, and when they carry its HIC id at INFO_OFFSET + 4
--- it treats the file as an update of itself
--- (flash_decoder.c flash_decoder_detect_type).
--- @param first table the lowest run { at, data }
--- @return boolean
local function forTheChip(first)
  if #first.data < DECIDE_SIZE then return false end
  local b1, b2, b3, b4 = first.data:byte(INFO_OFFSET + 5,
    INFO_OFFSET + 8)
  local hic = b1 + b2 * 0x100 + b3 * 0x10000 + b4 * 0x1000000
  return OWN_HIC[hic] == true
end

--- The chunk, counted from 1, after which the chip has begun
--- to write the board's memory, and so to erase its old
--- program: it starts once it has DECIDE_SIZE bytes in a row,
--- or the first byte of a second run (flash_decoder.c). A
--- text Dap.prepare wrote: data records in address order.
--- @param text string
--- @return integer
function Dap.eraseChunk(text)
  local at, got, nextAt = 0, 0, nil
  local base = 0
  for line in text:gmatch('[^\n]*\n') do
    at = at + #line
    local count = tonumber(line:sub(2, 3), 16)
    local offset = tonumber(line:sub(4, 7), 16)
    local kind = tonumber(line:sub(8, 9), 16)
    if kind == 4 then
      base = tonumber(line:sub(10, 13), 16) * 0x10000
    elseif kind == 0 then
      local addr = base + offset
      if nextAt and addr ~= nextAt then break end
      got = got + count
      nextAt = addr + count
      if got >= DECIDE_SIZE then break end
    end
  end
  return math.ceil(at / Dap.CHUNK)
end

--- The file the chip is sent: the given hex read into an
--- image (IntelHex.parse), checked, and written afresh
--- (IntelHex.encode), or why it cannot go:
--- IntelHex.parse's reasons, 'empty' for no data at all,
--- 'too small' for one run under DECIDE_SIZE bytes (the chip
--- starts writing only once it has that much in a row, or a
--- second run, so such a file is never written),
--- 'outside' for a byte outside REGIONS, 'interface' for an
--- image the chip would take for software of its own.
--- pause is passed on to the reading and the writing; seen,
--- when given, gets the image once it passed every check.
--- @param data string
--- @param pause function?
--- @param seen function?
--- @return string? text
--- @return string? why
function Dap.prepare(data, pause, seen)
  local image, why = IntelHex.parse(data, pause)
  if not image then return nil, why end
  if #image == 0 then return nil, 'empty' end
  if #image == 1 and #image[1].data < DECIDE_SIZE then
    return nil, 'too small'
  end
  for _, run in ipairs(image) do
    if not inside(run) then return nil, 'outside' end
  end
  if forTheChip(image[1]) then return nil, 'interface' end
  if seen then seen(image) end
  return IntelHex.encode(image, pause)
end
