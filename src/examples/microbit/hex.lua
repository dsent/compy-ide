-- Intel HEX, as much of it as the board's firmware needs.
--
-- A file is a list of records; each carries a few bytes and
-- where they go. Records that follow one another in memory
-- are one block here: an address and the bytes as a string,
-- which is what a string in Lua is anyway.

local hex = { }

local ROW = 16
-- "LUA1", least significant byte first
local MAGIC = "1AUL"
-- The firmware keeps its version after this text, ended by a
-- zero byte
local VERSION_MARK = "microbit-lua firmware "

--- Two hex digits as the byte they spell
--- @param pair string
--- @return string
local function unhex(pair)
  return string.char(tonumber(pair, 16))
end

--- The checksum byte of a record
--- @param addr integer
--- @param kind integer
--- @param body string
--- @return integer
local function sum_of(addr, kind, body)
  local sum = #body + math.floor(addr / 256) + addr % 256 + kind
  for i = 1, #body do
    sum = sum + body:byte(i)
  end
  return (-sum) % 256
end

--- The digits of a record after its colon, all of them: as
--- many as its count says, and nothing after them
--- @param line string
--- @return string digits
--- @return integer count
local function digitsOf(line)
  local digits = line:match("^:(%x+)%s*$")
  local count = digits and tonumber(digits:sub(1, 2), 16)
  local whole = count and #digits == 10 + count * 2
  assert(whole, "bad hex record")
  return digits, count
end

--- One record: what kind it is, where its bytes go, and the
--- bytes, or nothing for a blank line. Any other line must be a
--- whole record whose checksum agrees, so a file damaged on the
--- way is refused before any of it reaches the board.
--- @param line string
local function record(line)
  if not line:find("%S") then
    return
  end
  local digits, count = digitsOf(line)
  local addr = tonumber(digits:sub(3, 6), 16)
  local kind = tonumber(digits:sub(7, 8), 16)
  local body = digits:sub(9, 8 + count * 2):gsub("%x%x", unhex)
  local sum = tonumber(digits:sub(-2), 16)
  assert(sum == sum_of(addr, kind, body), "bad hex checksum")
  return kind, addr, body
end

--- The address a type 02 or 04 record sets
--- @param kind integer
--- @param body string
--- @return integer
local function base_of(kind, body)
  local n = body:byte(1) * 256 + body:byte(2)
  if kind == 4 then
    return n * 65536
  end
  return n * 16
end

--- Bytes onto the run they continue, or onto a new one. A
--- run keeps its pieces apart and its length as it goes;
--- settle joins them.
--- @param gathered table[]
--- @param last table?
--- @param at integer
--- @param body string
--- @return table the run they went to
local function newRun(gathered, at, body)
  local run = {
    addr = at,
    parts = { body },
    len = #body
  }
  gathered[#gathered + 1] = run
  return run
end

local function add(gathered, last, at, body)
  local continues = last and last.addr + last.len == at
  if continues then
    last.parts[#(last.parts) + 1] = body
    last.len = last.len + #body
    return last
  end
  return newRun(gathered, at, body)
end

--- The blocks, each with its pieces joined into what it
--- holds. They are gathered as they come and joined once: a
--- block grows by a dozen bytes at a time, and rebuilding
--- the whole string each time would take the length of the
--- firmware squared.
--- @param gathered table[]
--- @return table[] blocks
local function settle(gathered)
  local blocks = { }
  for i, g in ipairs(gathered) do
    blocks[i] = {
      addr = g.addr,
      data = table.concat(g.parts)
    }
  end
  return blocks
end

--- The blocks of a hex file, in the order they appear
--- @param text string
--- @return table[] blocks
function hex.parse(text)
  local gathered, base, last = { }, 0, nil
  for line in text:gmatch("[^\r\n]+") do
    local kind, addr, body = record(line)
    local sets_base = kind == 2 or kind == 4
    if sets_base then
      base = base_of(kind, body)
    elseif kind == 0 then
      last = add(gathered, last, base + addr, body)
    end
  end
  return settle(gathered)
end

-- Every byte as the two digits that spell it, looked up
-- rather than formatted: a firmware image is a quarter of a
-- million of them.
local DIGITS = { }
for i = 0, 255 do
  DIGITS[string.char(i)] = string.format("%02X", i)
end

--- One record as a line
--- @param addr integer
--- @param kind integer
--- @param body string
--- @return string
local function line_of(addr, kind, body)
  return string.format(":%02X%04X%02X", #body, addr, kind) ..
    (body:gsub(".", DIGITS)) .. DIGITS[string.char(
    sum_of(addr, kind, body)
  )]
end

--- The block holding an address, and where in it
--- @param blocks table[]
--- @param addr integer
--- @return table? block
--- @return integer? at one-based offset into its data
function hex.at(blocks, addr)
  for _, block in ipairs(blocks) do
    local at = addr - block.addr
    local inside = 0 <= at and at < #(block.data)
    if inside then
      return block, at + 1
    end
  end
end

--- A little-endian word
--- @param blocks table[]
--- @param addr integer
--- @return integer?
local function word(blocks, addr)
  local block, at = hex.at(blocks, addr)
  local short = not block or #(block.data) < at + 3
  if short then
    return
  end
  local b1, b2, b3, b4 = block.data:byte(at, at + 3)
  return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

--- A word as four bytes, least significant first
--- @param n integer
--- @return string
local function le_word(n)
  return string.char(
    n % 256,
    math.floor(n / 256) % 256,
    math.floor(n / 65536) % 256,
    math.floor(n / 16777216) % 256
  )
end

--- The metadata at an address, if that is what is there.
--- The magic can turn up in ordinary data as well, so a
--- candidate counts only when its fields agree with each
--- other and point somewhere real.
--- @param blocks table[]
--- @param addr integer
--- @return table? meta
local function fieldsAgree(blocks, m)
  return m.start and m.stop and m.size
       and m.start < m.stop
       and m.size == m.stop - m.start
       and hex.at(blocks, m.start)
end

local function meta_at(blocks, addr)
  local m = {
    start = word(blocks, addr + 4),
    stop = word(blocks, addr + 8),
    size = word(blocks, addr + 12),
    space = word(blocks, addr + 16)
  }
  if fieldsAgree(blocks, m) then
    return m
  end
end

--- Where the firmware says its Lua script lives
--- @param blocks table[]
--- @return integer? addr of the metadata
--- @return table? meta
local function candidate(blocks, block, i)
  local addr = block.addr + i - 1
  local m = addr % 4 == 0 and meta_at(blocks, addr)
  if m then
    return addr, m
  end
end

local function metaIn(blocks, block)
  local at = 1
  while true do
    local i = block.data:find(MAGIC, at, true)
    if not i then
      break
    end
    local addr, m = candidate(blocks, block, i)
    if addr then
      return addr, m
    end
    at = i + 1
  end
end

function hex.meta(blocks)
  for _, block in ipairs(blocks) do
    local addr, m = metaIn(blocks, block)
    if addr then
      return addr, m
    end
  end
end

--- One row of data, with the base record it needs first
--- @param out string[]
--- @param addr integer
--- @param data string
--- @param base integer the upper half already written
--- @return integer base after it
local function row(out, addr, data, base)
  local upper = math.floor(addr / 65536)
  if upper ~= base then
    base = upper
    out[#out + 1] = line_of(
      0,
      4,
      string.char(math.floor(upper / 256), upper % 256)
    )
  end
  out[#out + 1] = line_of(addr % 65536, 0, data)
  return base
end

--- The blocks back as a hex file
--- @param blocks table[]
--- @return string
local function writeBlock(out, block, base)
  local at = 0
  while at < #(block.data) do
    local take = math.min(ROW, #(block.data) - at)
    base = row(
      out,
      block.addr + at,
      block.data:sub(at + 1, at + take),
      base
    )
    at = at + take
  end
  return base
end

function hex.write(blocks)
  local out, base = { }, -1
  for _, block in ipairs(blocks) do
    base = writeBlock(out, block, base)
  end
  out[#out + 1] = line_of(0, 1, "")
  return table.concat(out, "\n") .. "\n"
end

--- Where the script lives, or an end to it
--- @param blocks table[]
--- @return integer addr
--- @return table meta
local function must_meta(blocks)
  local addr, meta = hex.meta(blocks)
  assert(addr, "no Lua metadata in this hex")
  return addr, meta
end

--- The script the firmware carries
--- @param blocks table[]
--- @return string
function hex.script(blocks)
  local _, meta = must_meta(blocks)
  local block, at = hex.at(blocks, meta.start)
  return block.data:sub(at, at + meta.size - 1)
end

--- Say in the metadata where the script now ends and how
--- long it is
--- @param blocks table[]
--- @param addr integer of the metadata
--- @param stop integer
--- @param size integer
local function restate(blocks, addr, stop, size)
  local head, at = hex.at(blocks, addr)
  head.data = head.data:sub(1, at + 7) .. le_word(stop) ..
      le_word(size) .. head.data:sub(at + 16)
end

--- How long a script may be: the space the metadata reports,
--- from the script's start to the end of flash, less what of
--- it the metadata itself takes when it sits there. The
--- firmware puts it just before the script; a layout that
--- puts it at the end of flash keeps the script short of it.
--- @param addr integer of the metadata
--- @param meta table
--- @return integer
function hex.room(addr, meta)
  local after = meta.start <= addr
  local within = addr < meta.start + meta.space
  local inside = after and within
  if inside then
    return addr - meta.start
  end
  return meta.space
end

--- Put a script in place of the one that is there, and say
--- so in the metadata. The script sits last in flash, so it
--- may grow into the room the metadata leaves it.
--- @param blocks table[]
--- @param script string
function hex.embed(blocks, script)
  local addr, meta = must_meta(blocks)
  local room = hex.room(addr, meta)
  assert(
    #script <= room,
    "script is " .. #script .. ", room is " .. room
  )
  -- what follows the old script in its block stays after the
  -- new one, as hextract's embed keeps it
  local block, at = hex.at(blocks, meta.start)
  local after = block.data:sub(at + meta.size)
  block.data = block.data:sub(1, at - 1) .. script .. after
  restate(blocks, addr, meta.start + #script, #script)
end

--- The version of the firmware a hex file holds, or nil for
--- one built before the firmware carried it
--- @param blocks table[]
--- @return string?
function hex.version(blocks)
  for _, block in ipairs(blocks) do
    local _, at = block.data:find(VERSION_MARK, 1, true)
    if at then
      return block.data:match("^[^%z]*", at + 1)
    end
  end
end

return hex
