require('util.string.string')
local parser = require('model.lang.lua.parser')()

--- Where a draft fails to parse (editor principles, IS3.4 and
--- IS3.5): before the first character the failure names, or
--- at the draft's end when it is only unfinished.
describe('parse failure boundary #parser', function()
  --- @param lines string[]
  --- @return table --- {line, column, at_end}
  local function failure(lines)
    local ok, err = parser.parse(lines)
    assert.is_false(ok)
    local f = parser.failure(lines, err)
    return { f.l, f.c, f.at_end or false }
  end

  it('is before the failing character', function()
    assert.same({ 1, 5, false }, failure({ 'z = = 1 + 2' }))
    assert.same({ 1, 7, false }, failure({ 'x = 1 1' }))
    assert.same({ 2, 5, false }, failure({ 'a = 1', 'b = = 2' }))
  end)

  it('is the first character of what is no statement',
    function()
      assert.same({ 1, 1, false }, failure({ 'print 1' }))
    end)

  it('counts characters, not bytes', function()
    assert.same({ 1, 9, false }, failure({ 'x = "é" = 1' }))
  end)

  it('is the end of an unfinished draft', function()
    assert.same({ 1, 16, true }, failure({ 'for i = 1, 2 do' }))
    assert.same({ 2, 8, true },
      failure({ 'function f()', '  a = 1' }))
    assert.same({ 2, 1, true }, failure({ 'if x then ', '' }))
  end)

  it('passes over a comment', function()
    assert.same({ 1, 24, true },
      failure({ 'for i = 1, 2 do -- loop' }))
    assert.same({ 2, 1, false }, failure({ 'x = -- c', '= 2' }))
    assert.same({ 1, 12, false }, failure({ 'x = --[[c]]= 2' }))
    assert.same({ 2, 5, false },
      failure({ 'x = 1 -- c', 'y = = 2' }))
    assert.same({ 1, 14, false },
      failure({ 's = "a -- b" = 2' }))
  end)

  it('is the token the parser stopped at', function()
    assert.same({ 1, 7, false }, failure({ 'x = 1 )' }))
    assert.same({ 2, 1, false }, failure({ 'x = 1', ')' }))
    assert.same({ 1, 1, false }, failure({ 'end' }))
    assert.same({ 1, 7, false }, failure({ 'local local' }))
    assert.same({ 1, 1, false }, failure({ '= 3' }))
    assert.same({ 1, 1, false }, failure({ ')' }))
    assert.same({ 1, 5, false }, failure({ 'for = 1' }))
    assert.same({ 1, 7, false }, failure({ 'x = 1 end' }))
  end)

  it('is the token read last when that one failed', function()
    assert.same({ 1, 8, false }, failure({ 'x = 1 +* 2' }))
    assert.same({ 1, 3, false }, failure({ 'f(,)' }))
    assert.same({ 1, 5, false }, failure({ 'x = = ' }))
    assert.same({ 1, 5, false }, failure({ 'f(1 2)' }))
    assert.same({ 1, 5, false }, failure({ 'f(1 2' }))
    assert.same({ 1, 6, false }, failure({ 'if x y = 1 end' }))
    assert.same({ 1, 1, false }, failure({ 'goto' }))
  end)

  it('is the end only when the text wants more', function()
    assert.same({ 1, 15, true }, failure({ 'local function' }))
    assert.same({ 1, 4, true }, failure({ 'f(1' }))
    assert.same({ 1, 10, true }, failure({ 'x = {1, 2' }))
    assert.same({ 1, 8, true }, failure({ 'x = 1 +' }))
  end)

  it('leaves the error parse returned as it was', function()
    local lines = { 'z = = 1' }
    local _, err = parser.parse(lines)
    local l, c = err.l, err.c
    parser.failure(lines, err)
    assert.same({ l, c }, { err.l, err.c })
  end)
end)
