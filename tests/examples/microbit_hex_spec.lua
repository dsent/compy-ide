--- hex.lua parses the firmware files the micro:bit tools read
--- and rewrite; a wrong byte would go onto the board unnoticed
local hex = require('examples.microbit.hex')

describe('micro:bit hex files #microbit', function()
  local file = ':020000040000FA\n'
      .. ':0400000001020304F2\n'
      .. ':00000001FF\n'

  it('reads a record into its bytes', function()
    local blocks = hex.parse(file)
    assert.are.equal(1, #blocks)
    assert.are.equal(0, blocks[1].addr)
    assert.are.equal('\1\2\3\4', blocks[1].data)
  end)

  it('writes what it reads', function()
    local blocks = hex.parse(file)
    assert.are.same(blocks, hex.parse(hex.write(blocks)))
  end)

  it('refuses a record with a character that is not hex',
    function()
      assert.has_error(function()
        hex.parse(':02000000ZZ00FE\n')
      end, 'bad hex record')
    end)

  it('reads the version the firmware keeps after its mark',
    function()
      local blocks = { {
        addr = 0,
        data = 'xx microbit-lua firmware 86c8e16-drift\0yy',
      } }
      assert.are.equal('86c8e16-drift', hex.version(blocks))
    end)

  --- @return string the shipped firmware's hex file
  local function shipped()
    local f = assert(io.open('src/examples/microbit/MICROBIT.hex'))
    local text = f:read('*a')
    f:close()
    return text
  end

  it('reads the version the shipped firmware carries', function()
    assert.truthy(hex.version(hex.parse(shipped())):match('^%x+'))
  end)

  --- a firmware from before the mark: the shipped one, its mark
  --- worn off
  it('reads no version from firmware built before the mark',
    function()
      local blocks = hex.parse(shipped())
      for _, b in ipairs(blocks) do
        b.data = b.data:gsub('microbit%-lua firmware ',
          ('-'):rep(22))
      end
      assert.is_nil(hex.version(hex.parse(hex.write(blocks))))
    end)

  --- a little-endian word
  local function word(n)
    return string.char(n % 256, math.floor(n / 256) % 256,
      math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
  end

  --- The metadata's block: its magic, then start, end, size and
  --- space
  local function metaBlock(addr, start, stop, space)
    return { addr = addr, data = word(0x4C554131) .. word(start)
      .. word(stop) .. word(stop - start) .. word(space) }
  end

  --- a block cut short after the size: no space word, and so
  --- no metadata (Codex round 11, M4)
  it('takes no metadata that lacks a field', function()
    local m = metaBlock(0, 0x64, 0x65, 0x100)
    m.data = m.data:sub(1, 16)
    local blocks = { m, { addr = 0x64, data = ' ' } }
    assert.is_nil(hex.meta(blocks))
    blocks[1] = metaBlock(0, 0x64, 0x65, 0x100)
    assert.equal(0, (hex.meta(blocks)))
  end)

  it('takes no metadata whose script is larger than its space',
    function()
      local blocks = { metaBlock(0, 0x64, 0x74, 8),
        { addr = 0x64, data = (' '):rep(16) } }
      assert.is_nil(hex.meta(blocks))
    end)

  --- the shipped firmware puts its metadata just before the
  --- script: the script may take all the space
  it('fills the shipped firmware\'s space to its end, and no'
    .. ' further', function()
      local blocks = hex.parse(shipped())
      local addr, meta = hex.meta(blocks)
      assert.is_true(addr < meta.start)
      local room = hex.room(addr, meta)
      assert.equal(meta.space, room)
      hex.embed(blocks, ('-'):rep(room))
      local _, after = hex.meta(blocks)
      assert.equal(room, after.size)
      assert.equal(after.stop - after.start, after.size)
      assert.has_error(function()
        hex.embed(hex.parse(shipped()), ('-'):rep(room + 1))
      end)
    end)

  --- a layout with the metadata at the end of flash, inside
  --- the space it reports: the script stops short of it
  it('keeps a script short of metadata inside its space',
    function()
      local blocks = {
        { addr = 0x1000, data = 'print(1)' },
        metaBlock(0x1064, 0x1000, 0x1008, 0x200),
      }
      local addr, meta = hex.meta(blocks)
      assert.equal(0x1064, addr)
      assert.equal(0x64, hex.room(addr, meta))
      hex.embed(blocks, ('-'):rep(0x64))
      local _, after = hex.meta(hex.parse(hex.write(blocks)))
      assert.equal(0x64, after.size)
      assert.has_error(function()
        hex.embed({
          { addr = 0x1000, data = 'print(1)' },
          metaBlock(0x1064, 0x1000, 0x1008, 0x200),
        }, ('-'):rep(0x65))
      end)
    end)

  --- as hextract's embed: what follows the old script in its
  --- block stays after the new one
  it('keeps what follows the script in its block', function()
    local blocks = {
      metaBlock(0x1000, 0x1014, 0x1018, 0x100),
    }
    blocks[1].data = blocks[1].data .. 'old!' .. 'tail'
    hex.embed(blocks, 'new script')
    assert.equal('new scripttail', blocks[1].data:sub(21))
    local _, meta = hex.meta(blocks)
    assert.equal(10, meta.size)
    assert.equal(0x1014 + 10, meta.stop)
  end)

  it('refuses a record whose checksum does not agree', function()
    assert.has_error(function()
      hex.parse(':00000001FE\n')
    end, 'bad hex checksum')
  end)

  it('refuses a line that is not a record', function()
    assert.has_error(function()
      hex.parse(';0400000001020304F2\n')
    end, 'bad hex record')
  end)

  --- 0F would do, and a lone F reads as the same number
  it('refuses a checksum cut short', function()
    assert.are.equal(1, #hex.parse(':01000000F00F\n'))
    assert.has_error(function()
      hex.parse(':01000000F0F\n')
    end, 'bad hex record')
  end)

  it('refuses a record shorter than its count', function()
    assert.has_error(function()
      hex.parse(':0400000000FF\n')
    end, 'bad hex record')
  end)
end)
