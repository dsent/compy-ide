--- A hex file is read with its standard meaning and written
--- afresh, and the chip must place every byte of what is
--- written exactly where the file meant it: a byte misplaced
--- is a program corrupted without a word. The chip's reading
--- is modelled here from DAPLink 0257
--- source/daplink/drag-n-drop/intelhex.c.

require('model.serial.intel_hex')
require('model.serial.dap')

--- The chip's reading of a hex text (parse_hex_blob):
--- - CR and LF are skipped wherever they are; ':' starts a
---   record; its digits are handled once all are in;
--- - a data record's bytes go to (next & 0xFFFF0000) | offset,
---   and next moves on past them;
--- - type 04 sets next to its value << 16, type 02 to
---   (value >> 8) << 12 | (value & 0xFF) << 4;
--- - the end-of-file record stops the parse;
--- - next starts at 0 (reset_hex_parser).
--- @param text string
--- @return table memory address -> byte
--- @return boolean ended
local function chipRead(text)
  local mem, nextAt, ended = {}, 0, false
  local digits = text:gsub('[\r\n]', '')
  for rec in digits:gmatch(':(%x*)') do
    local b = {}
    for i = 1, #rec, 2 do b[#b + 1] = tonumber(rec:sub(i, i + 1), 16) end
    local count, kind = b[1], b[4]
    local offset = b[2] * 256 + b[3]
    if kind == 0 then
      local at = nextAt - nextAt % 0x10000 + offset
      for i = 1, count do mem[at + i - 1] = b[4 + i] end
      nextAt = at + count
    elseif kind == 4 then
      nextAt = b[5] * 0x1000000 + b[6] * 0x10000
    elseif kind == 2 then
      nextAt = b[5] * 0x1000 + b[6] * 0x10
    elseif kind == 1 then
      ended = true
      break
    end
  end
  return mem, ended
end

--- @param image table[]
--- @return table memory address -> byte
local function memoryOf(image)
  local mem = {}
  for _, run in ipairs(image) do
    for i = 1, #run.data do mem[run.at + i - 1] = run.data:byte(i) end
  end
  return mem
end

--- The chip, reading what the Compy writes, places exactly
--- the image
local function placesExactly(image)
  local text = IntelHex.encode(image)
  local mem, ended = chipRead(text)
  assert.is_true(ended)
  assert.same(memoryOf(image), mem)
  return text
end

--- One record's text
local function rec(kind, offset, bytes)
  local sum = #bytes + math.floor(offset / 256) + offset % 256
      + kind
  local hex = ''
  for _, v in ipairs(bytes) do
    sum = sum + v
    hex = hex .. string.format('%02X', v)
  end
  return string.format(':%02X%04X%02X%s%02X\r\n', #bytes, offset,
    kind, hex, (256 - sum % 256) % 256)
end

local function seq(n, from)
  local t = {}
  for i = 1, n do t[i] = ((from or 0) + i) % 256 end
  return t
end

local EOF = ':00000001FF\r\n'

local function example()
  local f = assert(io.open('src/examples/microbit/MICROBIT.hex',
    'rb'))
  local data = f:read('*a')
  f:close()
  return data
end

describe('IntelHex', function()
  it('reads the example firmware, and the chip places what is'
    .. ' written exactly', function()
      local image = assert(IntelHex.parse(example()))
      local n = 0
      for _, run in ipairs(image) do n = n + #run.data end
      assert.same(231996, n)
      placesExactly(image)
    end)

  it('writes the same text every time, and reads it back'
    .. ' as the same image', function()
      local image = assert(IntelHex.parse(example()))
      local a = IntelHex.encode(image)
      local b = IntelHex.encode(assert(IntelHex.parse(example())))
      assert.equal(a, b)
      assert.same(image, IntelHex.parse(a))
    end)

  it('writes only what the chip reads right', function()
    local text = IntelHex.encode(assert(IntelHex.parse(example())))
    local blocks, last = 0, nil
    for line in text:gmatch('[^\n]+') do
      local count = tonumber(line:sub(2, 3), 16)
      local offset = tonumber(line:sub(4, 7), 16)
      local kind = tonumber(line:sub(8, 9), 16)
      assert.is_true(kind == 0 or kind == 1 or kind == 4)
      if kind == 0 then
        assert.is_true(count <= 16)
        assert.is_true(offset + count <= 0x10000)
      elseif kind == 4 then
        blocks = blocks + 1
      end
      last = line
    end
    assert.same(':00000001FF', last)
    assert.is_true(blocks >= 2)
  end)

  --- the case the third review found: the chip keeps a
  --- segment base only above 64 KB
  it('places data after a segment base off a 64 KB boundary',
    function()
      local image = assert(IntelHex.parse(rec(2, 0, { 0x12, 0x34 })
        .. rec(0, 0, { 0xAA, 0xBB, 0xCC, 0xDD }) .. EOF))
      assert.same({ { at = 0x12340, data = '\170\187\204\221' } },
        image)
      placesExactly(image)
    end)

  --- the case the fourth review found: the chip's address runs
  --- on past a 64 KB boundary, where the file's does not
  it('places a record after one that ends at FFFF', function()
    local text = rec(4, 0, { 0, 0 }) .. rec(0, 0xFFF0, seq(16))
        .. rec(0, 0x0100, seq(4, 100)) .. EOF
    local image = assert(IntelHex.parse(text))
    assert.same(0x0100, image[1].at)
    assert.same(0xFFF0, image[2].at)
    local original = chipRead(text)
    assert.is_nil(original[0x0100])
    placesExactly(image)
  end)

  it('splits a run at a 64 KB boundary with a new base',
    function()
      local text = rec(4, 0, { 0, 0 }) .. rec(0, 0xFFF0, seq(16))
          .. rec(4, 0, { 0, 1 }) .. rec(0, 0, seq(16, 16)) .. EOF
      local image = assert(IntelHex.parse(text))
      assert.same(1, #image)
      assert.same(32, #image[1].data)
      local out = placesExactly(image)
      assert.truthy(out:find(':020000040001F9', 1, true))
    end)

  --- rows start where the run does, so a run that starts off
  --- a 16-byte row reaches a boundary mid-row
  it('ends a record at a 64 KB boundary, whatever the row',
    function()
      local text = rec(4, 0, { 0, 0 }) .. rec(0, 0xFFF8, seq(8))
          .. rec(4, 0, { 0, 1 }) .. rec(0, 0, seq(24, 8)) .. EOF
      local out = placesExactly(assert(IntelHex.parse(text)))
      for line in out:gmatch('[^\n]+') do
        local count = tonumber(line:sub(2, 3), 16)
        local offset = tonumber(line:sub(4, 7), 16)
        if line:sub(8, 9) == '00' then
          assert.is_true(offset + count <= 0x10000, line)
        end
      end
    end)

  it('wraps a record past FFFF to the start of its block',
    function()
      local text = rec(4, 0, { 0, 2 }) .. rec(0, 0xFFF8, seq(16))
          .. EOF
      local image = assert(IntelHex.parse(text))
      assert.same(0x20000, image[1].at)
      assert.same(8, #image[1].data)
      assert.same(0x2FFF8, image[2].at)
      placesExactly(image)
    end)

  it('leaves holes as holes', function()
    local text = rec(0, 0x0000, seq(4)) .. rec(0, 0x2000, seq(4))
        .. EOF
    local image = assert(IntelHex.parse(text))
    assert.same(2, #image)
    local mem = chipRead(IntelHex.encode(image))
    assert.is_nil(mem[0x0004])
    assert.is_nil(mem[0x1FFF])
    placesExactly(image)
  end)

  it('takes a byte given twice alike, and refuses one given'
    .. ' twice differently', function()
      local same = rec(0, 0, seq(8)) .. rec(0, 4, seq(8, 4)) .. EOF
      local image = assert(IntelHex.parse(same))
      assert.same(1, #image)
      assert.same(12, #image[1].data)
      local differ = rec(0, 0, seq(8)) .. rec(0, 4, seq(8)) .. EOF
      local no, why = IntelHex.parse(differ)
      assert.is_nil(no)
      assert.same('overlap', why)
    end)

  it('reads records of any length the format allows',
    function()
      local image = assert(IntelHex.parse(rec(0, 0, seq(255))
        .. EOF))
      assert.same(255, #image[1].data)
      placesExactly(image)
    end)

  it('leaves out start address records', function()
    local text = rec(3, 0, { 0, 0, 0, 0 }) .. rec(5, 0, { 0, 0, 0, 0 })
        .. rec(0, 0, seq(4)) .. EOF
    assert.same(1, #assert(IntelHex.parse(text)))
  end)

  it('says what is wrong with a file', function()
    local cases = {
      { rec(0, 0, seq(4)), 'cut short' },
      { rec(0, 0, seq(4)) .. EOF .. rec(0, 8, seq(4)), 'early end' },
      { rec(0, 0, seq(4)) .. EOF .. '\r\n  \r\n\0', nil },
      { rec(0, 0, seq(4)):gsub('%x%x\r', '00\r'), 'damaged' },
      { rec(0x0A, 0, { 0x99, 0x03, 0xC0, 0xDE }) .. EOF,
        'universal' },
      { rec(7, 0, seq(2)) .. EOF, 'damaged' },
      { ' ' .. rec(0, 0, seq(4)) .. EOF, 'damaged' },
      { ':0000\r\n0001FF\r\n', 'damaged' },
    }
    for i, c in ipairs(cases) do
      local image, why = IntelHex.parse(c[1])
      assert.same(c[2], why, 'case ' .. i)
      if not c[2] then assert.truthy(image) end
    end
  end)
end)

describe('Dap.prepare', function()
  it('writes the example firmware afresh', function()
    local text = assert(Dap.prepare(example()))
    assert.same(':00000001FF\n', text:sub(-12))
  end)

  it('keeps the firmware version the example tools read',
    function()
      local hex = require('examples.microbit.hex')
      local marked = hex.write({ {
        addr = 0x1000,
        data = 'microbit-lua firmware abc1234\0',
      } })
      local text = assert(Dap.prepare(marked))
      assert.same('abc1234', hex.version(hex.parse(text)))
      local plain = assert(Dap.prepare(example()))
      assert.is_true(hex.version(hex.parse(plain))
        == hex.version(hex.parse(example())))
    end)

  it('takes the last byte of the program flash and of the'
    .. ' UICR page, and nothing past them', function()
      local last = rec(4, 0, { 0, 7 }) .. rec(0, 0xFFFF, { 1 })
      assert.truthy(Dap.prepare(last .. EOF))
      local past = rec(4, 0, { 0, 8 }) .. rec(0, 0, { 1 })
      assert.same('outside', select(2, Dap.prepare(past .. EOF)))
      local uicr = rec(4, 0, { 0x10, 0 }) .. rec(0, 0x1FFF, { 1 })
      assert.truthy(Dap.prepare(uicr .. EOF))
      local ficr = rec(4, 0, { 0x10, 0 }) .. rec(0, 0x0FFF, { 1 })
      assert.same('outside', select(2, Dap.prepare(ficr .. EOF)))
      local ram = rec(4, 0, { 0x20, 0 }) .. rec(0, 0, { 1 })
      assert.same('outside', select(2, Dap.prepare(ram .. EOF)))
    end)

  it('refuses a file with no data', function()
    assert.same('empty', select(2, Dap.prepare(EOF)))
  end)

  --- the chip reads its HIC id at 0x24 of the first data and
  --- takes such a file for software of its own
  it('refuses software for the micro:bit\'s USB chip',
    function()
      for _, hic in ipairs({ { 0x0B, 0x99, 0x96, 0x97 },
        { 0x20, 0x28, 0x05, 0x6E } }) do
        local bytes = seq(48)
        for i = 1, 4 do bytes[0x24 + i] = hic[i] end
        local text = rec(0, 0, { unpack(bytes, 1, 32) })
            .. rec(0, 32, { unpack(bytes, 33, 48) }) .. EOF
        assert.same('interface', select(2, Dap.prepare(text)))
      end
      assert.truthy(Dap.prepare(rec(0, 0, seq(32))
        .. rec(0, 32, seq(16, 32)) .. EOF))
    end)
end)
