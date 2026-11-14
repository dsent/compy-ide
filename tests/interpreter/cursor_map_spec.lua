require('util.string.string')
local cursor_map = require('model.lang.lua.cursor_map')

--- The cursor through formatting (editor principles, IS3.9):
--- where it stands in the formatted text.
describe('cursor through formatting #check', function()
  local function at(old, new, l, c)
    return { cursor_map.cursor(old, new, l, c) }
  end

  it('stays at the start and at the end of the draft', function()
    local old, new = { '  x=1' }, { 'x = 1' }
    assert.same({ 1, 1 }, at(old, new, 1, 1))
    assert.same({ 1, 6 }, at(old, new, 1, 6))
  end)

  it('keeps the side of an element it stands beside', function()
    local old, new = { 'v1=1' }, { 'v1 = 1' }
    -- after "v1": its end
    assert.same({ 1, 3 }, at(old, new, 1, 3))
    -- between "=" and "1": the end of "=", the preceding one
    assert.same({ 1, 5 }, at(old, new, 1, 4))
  end)

  it('keeps the offset inside an element', function()
    local old = { 'local   name=1' }
    local new = { 'local name = 1' }
    assert.same({ 1, 9 }, at(old, new, 1, 11))
  end)

  it('keeps the offset in a gap that is unchanged', function()
    local old = { 'a=1', '', 'b=2' }
    local new = { 'a = 1', '', 'b = 2' }
    assert.same({ 2, 1 }, at(old, new, 2, 1))
    -- with its indentation replaced, before what follows it
    old = { 'a=1', '', '  b=2' }
    assert.same({ 3, 1 }, at(old, new, 2, 1))
  end)

  it('goes before the next element from replaced spacing',
    function()
      local old = { 'x   =   1' }
      local new = { 'x = 1' }
      assert.same({ 1, 3 }, at(old, new, 1, 3))
    end)

  it('follows the same occurrence of a repeated text', function()
    local old = { 'a=a+a' }
    local new = { 'a = a + a' }
    -- inside nothing, after the second "a"
    assert.same({ 1, 6 }, at(old, new, 1, 4))
  end)

  it('counts characters, not bytes', function()
    local old = { 's="é" x=1' }
    local new = { 's = "é"', 'x = 1' }
    assert.same({ 2, 2 }, at(old, new, 1, 8))
  end)

  it('maps a cursor in a draft of hundreds of lines', function()
    local old, new = {}, {}
    for i = 1, 600 do
      old[i] = 'local  x' .. i .. '=f( a,b ,c )'
      new[i] = 'local x' .. i .. ' = f(a, b, c)'
    end
    -- elements that differ at both ends, so the search runs
    -- on everything between them
    old[1], new[1] = 'p=(1)', 'p = 1'
    old[600], new[600] = 'q=(2)', 'q = 2'
    local before = collectgarbage('count')
    assert.same({ 300, 7 }, at(old, new, 300, 8))
    assert.same({ 600, 6 }, at(old, new, 600, 6))
    -- kilobytes: a table of every pair would take hundreds of
    -- megabytes
    assert.is_true(collectgarbage('count') - before < 20000)
  end)

  it('leaves a string and a comment whole', function()
    local old = { 'x="a  b"  -- c  d' }
    local new = { 'x = "a  b" -- c  d' }
    assert.same({ 1, 9 }, at(old, new, 1, 7))
    assert.same({ 1, 17 }, at(old, new, 1, 16))
  end)
end)
