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

--- The last position that is not a line end, a blank or
--- another control character
--- @param data string
--- @return integer
local function lastVisible(data)
  local i = #data
  while i > 0 and data:byte(i) <= 32 do i = i - 1 end
  return i
end

--- The value of each hex digit's byte
local DIGIT = {}
for i = 0, 15 do
  DIGIT[string.byte(string.format('%X', i))] = i
  DIGIT[string.byte(string.format('%x', i))] = i
end

--- The most data one record may carry: the chip decodes a
--- record into a buffer of 37 bytes, 32 of them data, and a
--- longer record runs past it (intelhex.c, hex_line_t)
Dap.RECORD_DATA_MAX = 32

--- One record's digits, less its ':': nil when the chip
--- reads it as the record it is, else what is wrong
--- @param rec string
--- @return string? why
--- @return integer? kind the record type
local function recordFault(rec)
  local n = #rec
  if n < 10 or n % 2 == 1 then return 'damaged' end
  local sum = 0
  for i = 1, n, 2 do
    local hi, lo = DIGIT[rec:byte(i)], DIGIT[rec:byte(i + 1)]
    if not hi or not lo then return 'damaged' end
    sum = sum + hi * 16 + lo
  end
  local count = tonumber(rec:sub(1, 2), 16)
  if n ~= (count + 5) * 2 then return 'damaged' end
  if sum % 256 ~= 0 then return 'damaged' end
  local kind = tonumber(rec:sub(7, 8), 16)
  if kind >= 0x0A and kind <= 0x0E then return 'universal' end
  if kind > 5 then return 'damaged' end
  if count > Dap.RECORD_DATA_MAX then return 'long records' end
  return nil, kind
end

--- What keeps a hex file from the chip, if anything. The file
--- is read as the chip reads it (intelhex.c): a line end
--- anywhere is skipped, a ':' starts a record, and every
--- other byte is taken for a hex digit. What follows the
--- end-of-file record is never sent (hexBody), so line ends,
--- blanks and other control characters may follow it.
---
--- - 'cut short': no end-of-file record
--- - 'early end': a record after the end-of-file record; the
---   chip would stop at it and say it took the file
--- - 'universal': a Universal Hex, which holds a V1 and a V2
---   image in blocks (record types 0A to 0E); the chip picks
---   its own blocks only when every write starts on a block,
---   and a write here carries 62 bytes
--- - 'long records': a record of more than 32 data bytes
--- - 'damaged': anything else the chip would misread: a bad
---   digit, a wrong length or checksum, an unknown type
--- @param data string
--- @return string? why
function Dap.hexFault(data)
  local text = data:sub(1, lastVisible(data)):gsub('[\r\n]', '')
  if text == '' then return 'cut short' end
  if text:sub(1, 1) ~= ':' then return 'damaged' end
  local ended = false
  for rec in text:gmatch(':([^:]*)') do
    if ended then return 'early end' end
    local why, kind = recordFault(rec)
    if why then return why end
    ended = kind == 1
  end
  if not ended then return 'cut short' end
end

--- The file as the chip gets it: everything up to the end of
--- the end-of-file record. The chip takes nothing after the
--- record, so the chunk that carries it is the last one.
--- @param data string a file hexFault finds nothing wrong in
--- @return string
function Dap.hexBody(data)
  return data:sub(1, lastVisible(data))
end
