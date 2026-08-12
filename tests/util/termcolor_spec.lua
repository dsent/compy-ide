local tc = require("util.termcolor")

--- @diagnostic disable param-type-mismatch
describe('to_control #debug', function()
  it('names the basic slots', function()
    assert.same('\27[34m', tc.to_control(Color.blue))
    assert.same('\27[1;94m',
      tc.to_control(Color.blue + Color.bright))
  end)

  it('spells the extended slots out in full', function()
    assert.same('\27[38;2;191;124;0m',
      tc.to_control(Color.orange))
    assert.same('\27[38;2;255;165;0m',
      tc.to_control(Color.orange + Color.bright))
    assert.same('\27[38;2;191;161;0m',
      tc.to_control(Color.gold))
    assert.same('\27[38;2;84;96;108m',
      tc.to_control(Color.slategray))
  end)

  it('resets what Color.valid rejects', function()
    assert.same(tc.reset, tc.to_control(-1))
    assert.same(tc.reset, tc.to_control(1.5))
    assert.same(tc.reset, tc.to_control(64))
    assert.same(tc.reset, tc.to_control('7'))
    assert.same(tc.reset, tc.to_control(nil))
  end)
end)

describe('colorize_memaddress #debug', function()
  local frame = function(s)
    return tc.reset
        .. tc.to_control(0) .. '0' .. tc.reset
        .. 'x'
        .. s
  end

  it('empty', function()
    local res = tc.colorize_memaddress('')
    assert.same(tc.reset, res)
  end)

  it('colors', function()
    local res = tc.colorize_memaddress('0x208')
    local exp = frame(''
      .. tc.to_control(2) .. '2' .. tc.reset
      .. tc.to_control(0) .. '0' .. tc.reset
      .. tc.to_control(8) .. '8' .. tc.reset
    )
    assert.same(exp, res)
  end)
  it('colors deadbeef', function()
    local res = tc.colorize_memaddress('0xdeadbeef')
    local exp = frame(''
      .. tc.to_control(tonumber('0xd')) .. 'd' .. tc.reset
      .. tc.to_control(tonumber('0xe')) .. 'e' .. tc.reset
      .. tc.to_control(tonumber('0xa')) .. 'a' .. tc.reset
      .. tc.to_control(tonumber('0xd')) .. 'd' .. tc.reset
      .. tc.to_control(tonumber('0xb')) .. 'b' .. tc.reset
      .. tc.to_control(tonumber('0xe')) .. 'e' .. tc.reset
      .. tc.to_control(tonumber('0xe')) .. 'e' .. tc.reset
      .. tc.to_control(tonumber('0xf')) .. 'f' .. tc.reset
    )
    assert.same(exp, res)
  end)

  it('colors bright', function()
    local res = tc.colorize_memaddress('0x08192a3b4c5d6e7f')
    local exp = frame(''
      .. tc.to_control(0) .. '0' .. tc.reset
      .. tc.to_control(8) .. '8' .. tc.reset
      .. tc.to_control(1) .. '1' .. tc.reset
      .. tc.to_control(9) .. '9' .. tc.reset
      .. tc.to_control(2) .. '2' .. tc.reset
      .. tc.to_control(tonumber('0xa')) .. 'a' .. tc.reset
      .. tc.to_control(3) .. '3' .. tc.reset
      .. tc.to_control(tonumber('0xb')) .. 'b' .. tc.reset
      .. tc.to_control(4) .. '4' .. tc.reset
      .. tc.to_control(tonumber('0xc')) .. 'c' .. tc.reset
      .. tc.to_control(5) .. '5' .. tc.reset
      .. tc.to_control(tonumber('0xd')) .. 'd' .. tc.reset
      .. tc.to_control(6) .. '6' .. tc.reset
      .. tc.to_control(tonumber('0xe')) .. 'e' .. tc.reset
      .. tc.to_control(7) .. '7' .. tc.reset
      .. tc.to_control(tonumber('0xf')) .. 'f' .. tc.reset
    )
    assert.same(exp, res)
  end)
end)
