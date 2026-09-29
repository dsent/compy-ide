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
--- 0 to 28 alike; 0254 lacks FD_INCOMPATIBLE_IMAGE (29), so
--- its codes from 29 on name the entry after. Before 0254
--- the table differs from 9 on, and the flash refuses such a
--- chip.
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
--- The oldest interface firmware whose status numbers this
--- file knows
Dap.FIRMWARE_MIN = 254

--- @param code integer
--- @param firmware integer? the chip's version, as 257
--- @return string
function Dap.statusName(code, firmware)
  local at = code
  if firmware == 254 and code >= 29 then at = code + 1 end
  return (NAMES[at] or 'UNKNOWN') .. ' (' .. code .. ')'
end

local DAMAGED = 'The file is damaged, so the micro:bit could not'
    .. ' read it. Get the file again, then send it once more.'
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

--- The interface firmware's version as a number, 257 for
--- "0257"; nil when the chip did not say
--- @param text string?
--- @return integer?
function Dap.firmware(text)
  local digits = (text or ''):match('^(%d%d%d%d)$')
  return digits and tonumber(digits)
end

--- The last position that is not a line end, a blank or
--- another control character
--- @param data string
--- @return integer
local function lastVisible(data)
  local i = #data
  while i > 0 and data:byte(i) <= 32 do i = i - 1 end
  return i
end

--- Does the text end on the hex end-of-file record? The chip
--- takes a hex file as finished only on it. Line ends, blank
--- lines and other control characters may follow.
--- @param data string
--- @return boolean
function Dap.hexComplete(data)
  local i = lastVisible(data)
  local j = i
  while j > 0 and not data:sub(j, j):match('[\r\n]') do
    j = j - 1
  end
  local last = data:sub(j + 1, i):match('^%s*(.-)%s*$')
  return last:upper() == ':00000001FF'
end

--- The file as the chip gets it: everything up to the end of
--- the end-of-file record. The chip takes nothing after the
--- record, so the chunk that carries it is the last one.
--- @param data string a complete hex, see hexComplete
--- @return string
function Dap.hexBody(data)
  return data:sub(1, lastVisible(data))
end

--- A Universal Hex holds a V1 and a V2 image in blocks,
--- marked by record types 0A to 0E. The chip picks its own
--- blocks only when every write starts on a block, and a
--- write here carries 62 bytes, so it takes a plain hex for
--- its own board only.
--- @param data string
--- @return boolean
function Dap.isUniversal(data)
  for kind in data:gmatch(':%x%x%x%x%x%x(%x%x)') do
    local k = tonumber(kind, 16)
    if k >= 0x0A and k <= 0x0E then return true end
  end
  return false
end
