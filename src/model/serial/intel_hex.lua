--- Intel HEX, read with its standard meaning and written
--- afresh.
---
--- The micro:bit's interface chip reads a hex file its own
--- way (DAPLink intelhex.c): it keeps one running address,
--- takes the high half of a data record's address from it,
--- and so places some files wrongly without a word, such as
--- one whose data runs past a 64 KB boundary without a new
--- base, or one with a segment base off a 64 KB boundary.
--- So the Compy never sends the file it was given. It reads
--- the file into an image, bytes and where they go, and
--- writes a new file of that image in the one shape the chip
--- reads right: a type 04 record first and at every 64 KB
--- boundary, data records of at most 16 bytes that never
--- cross one, one end-of-file record last.

--- @class IntelHex
IntelHex = {}

--- Bytes per data record written
IntelHex.ROW = 16

local BLOCK = 0x10000

--- The value of each hex digit's byte
local DIGIT = {}
for i = 0, 15 do
  DIGIT[string.byte(string.format('%X', i))] = i
  DIGIT[string.byte(string.format('%x', i))] = i
end

--- The two hex digits that spell each byte
local HEX_OF = {}
for i = 0, 255 do
  HEX_OF[string.char(i)] = string.format('%02X', i)
end

--- One line as a record, or why not
--- @param line string
--- @return table? record { kind, offset, data (string) }
--- @return string? why
local function record(line)
  local digits = line:match('^:(%x*)$')
  if not digits or #digits < 10 or #digits % 2 == 1 then
    return nil, 'damaged'
  end
  local sum, bytes = 0, {}
  for i = 1, #digits, 2 do
    local b = DIGIT[digits:byte(i)] * 16
        + DIGIT[digits:byte(i + 1)]
    sum = sum + b
    bytes[#bytes + 1] = b
  end
  local count = bytes[1]
  if #bytes ~= count + 5 or sum % 256 ~= 0 then
    return nil, 'damaged'
  end
  return {
    kind = bytes[4],
    offset = bytes[2] * 256 + bytes[3],
    data = string.char(unpack(bytes, 5, 4 + count)),
    count = count,
  }
end

--- A record's two data bytes as a number
--- @param r table
--- @return integer
local function word(r)
  return r.data:byte(1) * 256 + r.data:byte(2)
end

--- The pieces a data record puts in memory. Under a linear
--- base (type 04, or none yet) byte i goes to base + offset
--- + i. Under a segment base (type 02) the offset wraps past
--- FFFF to the start of the segment, so a record makes two
--- pieces when it runs past it.
--- @param pieces table[]
--- @param base integer
--- @param r table
--- @param segment boolean
local function place(pieces, base, r, segment)
  if not segment then
    pieces[#pieces + 1] = { at = base + r.offset, data = r.data }
    return
  end
  local first = math.min(#r.data, BLOCK - r.offset)
  if first > 0 then
    pieces[#pieces + 1] = { at = base + r.offset,
      data = r.data:sub(1, first) }
  end
  if first < #r.data then
    pieces[#pieces + 1] = { at = base,
      data = r.data:sub(first + 1) }
  end
end

--- The data records of a file, placed, in file order
--- @param data string
--- @return table[]? pieces { at, data }
--- @return string? why
local function pieces(data)
  local out, base, segment, ended = {}, 0, false, false
  for line in (data .. '\n'):gmatch('([^\n]*)\n') do
    line = line:gsub('[%s%z]+$', '')
    if line ~= '' then
      if ended then return nil, 'early end' end
      local r, why = record(line)
      if not r then return nil, why end
      local k = r.kind
      if k == 0 then
        place(out, base, r, segment)
      elseif k == 1 then
        if r.count ~= 0 then return nil, 'damaged' end
        ended = true
      elseif k == 2 or k == 4 then
        if r.count ~= 2 then return nil, 'damaged' end
        segment = k == 2
        base = segment and word(r) * 16 or word(r) * BLOCK
      elseif k >= 0x0A and k <= 0x0E then
        return nil, 'universal'
      elseif k ~= 3 and k ~= 5 then
        return nil, 'damaged'
      end
    end
  end
  if not ended then return nil, 'cut short' end
  return out
end

--- The pieces as one image: runs of bytes in address order,
--- each { at, data }. A byte given twice must be given the
--- same both times.
--- @param list table[]
--- @return table[]? image
--- @return string? why
local function merge(list)
  table.sort(list, function(a, b) return a.at < b.at end)
  local image, run, parts, stop = {}, nil, nil, nil
  for _, p in ipairs(list) do
    local pend = p.at + #p.data
    if run and p.at < stop then
      local whole = table.concat(parts)
      local overlap = math.min(pend, stop) - p.at
      local from = p.at - run.at
      if whole:sub(from + 1, from + overlap)
          ~= p.data:sub(1, overlap) then
        return nil, 'overlap'
      end
      parts = { whole }
      if pend > stop then
        parts[2] = p.data:sub(overlap + 1)
        stop = pend
      end
    elseif run and p.at == stop then
      parts[#parts + 1] = p.data
      stop = pend
    else
      if run then run.data = table.concat(parts) end
      run = { at = p.at }
      image[#image + 1] = run
      parts = { p.data }
      stop = pend
    end
  end
  if run then run.data = table.concat(parts) end
  return image
end

--- Read a hex file with its standard meaning (Intel, Hexadecimal
--- Object File Format Specification, 1988): a data record's
--- byte i goes to base + offset + i under a type 04 base, the
--- value times 65536 (or before any base), and to base +
--- ((offset + i) mod 65536) under a type 02 base, the value
--- times 16; types 03 and 05 are left out; the end-of-file
--- record ends the file, and only blank lines may follow it.
--- Each record's length and checksum must hold. Lines end in
--- LF or CR LF; blanks at a line's end are left out.
--- @param data string
--- @return table[]? image runs { at, data } in address order
--- @return string? why 'cut short', 'early end', 'universal',
---   'overlap', 'damaged'
function IntelHex.parse(data)
  local list, why = pieces(data)
  if not list then return nil, why end
  return merge(list)
end

--- @param count integer
--- @param offset integer
--- @param kind integer
--- @param data string
--- @return string
local function line(count, offset, kind, data)
  local sum = count + math.floor(offset / 256) + offset % 256
      + kind
  for i = 1, #data do sum = sum + data:byte(i) end
  return string.format(':%02X%04X%02X%s%02X\n', count, offset,
    kind, data:gsub('.', HEX_OF), (256 - sum % 256) % 256)
end

--- Write an image as a hex file the chip reads right
--- @param image table[] runs { at, data } in address order
--- @return string
function IntelHex.encode(image)
  local out, block = {}, nil
  for _, run in ipairs(image) do
    local at, i = run.at, 1
    while i <= #run.data do
      local high = math.floor(at / BLOCK)
      if high ~= block then
        block = high
        out[#out + 1] = line(2, 0, 4,
          string.char(math.floor(high / 256), high % 256))
      end
      local offset = at % BLOCK
      local n = math.min(IntelHex.ROW, #run.data - i + 1,
        BLOCK - offset)
      out[#out + 1] = line(n, offset, 0, run.data:sub(i, i + n - 1))
      at, i = at + n, i + n
    end
  end
  out[#out + 1] = ':00000001FF\n'
  return table.concat(out)
end
