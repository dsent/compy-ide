require("util.color")

describe('Color #debug', function()
  local hex = function(i)
    return Color.to_hex(Color[i])
  end

  it('gives black a bright slot of its own', function()
    assert.same('#000000FF', hex(Color.black))
    assert.same('#404040FF',
      hex(Color.black + Color.bright))
  end)

  it('moves every slot when bright is added', function()
    for d = 0, 63 do
      if d % 16 < 8 then
        assert.are_not.same(hex(d), hex(d + Color.bright),
          'slot ' .. d .. ' does not move')
      end
    end
  end)

  it('leaves the rest of the classic sixteen alone', function()
    assert.same('#0000BFFF', hex(Color.blue))
    assert.same('#0000FFFF', hex(Color.blue + Color.bright))
    assert.same('#BFBFBFFF', hex(Color.white))
    assert.same('#FFFFFFFF', hex(Color.white + Color.bright))
  end)
end)
