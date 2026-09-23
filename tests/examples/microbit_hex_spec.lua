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

  it('refuses a record shorter than its count', function()
    assert.has_error(function()
      hex.parse(':0400000000FF\n')
    end, 'bad hex record')
  end)
end)
