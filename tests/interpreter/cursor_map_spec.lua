require('util.string.string')
local cursor_map = require('model.lang.lua.cursor_map')
--- the parser sets the path its lexer loads from, which reads
--- the strings, numbers and comments formatting respells
require('model.lang.lua.parser')()

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

  it('keeps every place in text that did not change', function()
    for _, text in ipairs({
      { '  hello' }, { 'hello  ' }, { '  a  ', '', '  b' },
      { 's = "a  b"' }, { '' },
    }) do
      for l, line in ipairs(text) do
        for c = 1, string.ulen(line) + 1 do
          assert.same({ l, c }, at(text, text, l, c))
        end
      end
    end
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

  describe('an element formatting rewrites', function()
    it('keeps the offset in a string requoted', function()
      local old, new = { "s='abc' x=1" }, { 's = "abc"', 'x = 1' }
      -- before "b"
      assert.same({ 1, 7 }, at(old, new, 1, 5))
      -- before the string: the end of "=", which precedes it
      assert.same({ 1, 4 }, at(old, new, 1, 3))
      -- after the string: its end
      assert.same({ 1, 10 }, at(old, new, 1, 8))
    end)

    it('keeps the offset in a number rewritten', function()
      local old, new = { 'x=0xff y=1' }, { 'x = 255', 'y = 1' }
      -- before the first "f"
      assert.same({ 1, 7 }, at(old, new, 1, 5))
    end)

    it('limits the offset to the new length', function()
      local old, new = { 'x=0x10 y=1' }, { 'x = 16', 'y = 1' }
      -- before the last "0": "16" is two characters long
      assert.same({ 1, 7 }, at(old, new, 1, 6))
    end)

    it('reads a number with a fraction or an exponent whole',
      function()
        local old = { 'x=1.50 y=1e-3' }
        local new = { 'x = 1.5', 'y = 0.001' }
        -- before the "0" of "1.50", limited to "1.5"
        assert.same({ 1, 8 }, at(old, new, 1, 6))
        -- before the "-" of "1e-3"
        assert.same({ 2, 7 }, at(old, new, 1, 12))
      end)

    it('follows the same occurrence of a repeated string',
      function()
        local old = { "a='x' b='x'" }
        local new = { 'a = "x"', 'b = "x"' }
        -- before the second "x"
        assert.same({ 2, 6 }, at(old, new, 1, 10))
      end)

    it('follows a comment respelled', function()
      local old, new = { '--cd', 'x=1' }, { '-- cd', 'x = 1' }
      -- at the comment's end
      assert.same({ 1, 6 }, at(old, new, 1, 5))
    end)

    it('follows a long string and a long comment', function()
      local old = { 's=[==[a]]b]==] --[=[c]=]', 'y=1' }
      local new = { 's = "a]]b" --[[c]]', 'y = 1' }
      -- at the end of each
      assert.same({ 1, 11 }, at(old, new, 1, 15))
      assert.same({ 1, 19 }, at(old, new, 1, 25))
    end)
  end)

  it('follows a string cut into pieces', function()
    local v = string.rep('abcdefghij', 9)
    local old = { "s='" .. v .. "' .. x" }
    local new = {
      's =',
      '  "' .. string.sub(v, 1, 57) .. '" ..',
      '  "' .. string.sub(v, 58) .. '" .. x',
    }
    -- before the first "b", in the first piece
    assert.same({ 2, 5 }, at(old, new, 1, 5))
    -- before the 67th character of the text, the tenth of
    -- the second piece
    assert.same({ 3, 13 }, at(old, new, 1, 70))
    -- after the string: after its last piece
    assert.same({ 3, 37 }, at(old, new, 1, 94))
    -- before what follows
    assert.same({ 3, 38 }, at(old, new, 1, 95))
  end)

  it('stays in a comment moved to a line of its own',
    function()
      local old, new = { 'x=1 -- c d' }, { 'x = 1', '-- c d' }
      -- before "d"
      assert.same({ 2, 6 }, at(old, new, 1, 10))
    end)

  it('keeps the cursor at a line end when lines join',
    function()
      local old, new = { 'x=1+', '2' }, { 'x = 1 + 2' }
      -- after "+"
      assert.same({ 1, 8 }, at(old, new, 1, 5))
      -- before "2"
      assert.same({ 1, 9 }, at(old, new, 2, 1))
    end)

  it('keeps the cursor beside an element when a line splits',
    function()
      local old, new = { 'a=1  b=2' }, { 'a = 1', 'b = 2' }
      -- after "1"
      assert.same({ 1, 6 }, at(old, new, 1, 4))
      -- in the gap that becomes a line break: before "b"
      assert.same({ 2, 1 }, at(old, new, 1, 5))
    end)

  it('follows its element when lines come and go above it',
    function()
      local old = { 'a=1 b=2', "s='xyz'" }
      local new = { 'a = 1', 'b = 2', 's = "xyz"' }
      assert.same({ 3, 7 }, at(old, new, 2, 5))
      old = { 'x=1+', '2', "s='xyz'" }
      new = { 'x = 1 + 2', 's = "xyz"' }
      assert.same({ 2, 7 }, at(old, new, 3, 5))
    end)

  it('keeps the side of the elements of a table respaced',
    function()
      local old, new = { 't={ab,  cd}' }, { 't = { ab, cd }' }
      -- inside "ab"
      assert.same({ 1, 8 }, at(old, new, 1, 5))
      -- in the gap replaced: before "cd"
      assert.same({ 1, 11 }, at(old, new, 1, 8))
    end)

  it('maps a rewritten string in a draft past the size guard',
    function()
      local old, new = {}, {}
      for i = 1, 600 do
        old[i] = 'local  s' .. i .. "='v" .. i .. "'"
        new[i] = 'local s' .. i .. ' = "v' .. i .. '"'
      end
      old[1], new[1] = 'p=(1)', 'p = 1'
      old[600], new[600] = 'q=(2)', 'q = 2'
      -- line 300, "local  s300='v300'", before the "3" of v300
      assert.same({ 300, 16 }, at(old, new, 300, 15))
    end)
end)

--- The elements of this module and the tokens of the parser's
--- lexer are the same text, in the forms the formatter meets.
describe('cursor map elements #check', function()
  local mlc = require('metalua.metalua.compiler').new()

  --- @param src string
  --- @return string[]
  local function tokens(src)
    local out = {}
    local lx = mlc:src_to_lexstream(src)
    repeat
      local tok = lx:next()
      local cs = tok.lineinfo.first.comments
      for _, c in ipairs(cs or {}) do
        local first = c.lineinfo.first.offset
        local last = c.lineinfo.last.offset
        local text = string.sub(src, first, last)
        out[#out + 1] = (string.gsub(text, '\n$', ''))
      end
      if tok.tag ~= 'Eof' then
        out[#out + 1] = string.sub(src,
          tok.lineinfo.first.offset, tok.lineinfo.last.offset)
      end
    until tok.tag == 'Eof'
    return out
  end

  --- @param src string
  --- @return string[]
  local function elements(src)
    local out = {}
    for i, el in ipairs(cursor_map.elements(src)) do
      out[i] = el.text
    end
    return out
  end

  local samples = {
    strings = [[a = 'x' .. "y" .. 'it\'s' .. "q\"q" .. 'a\
b' .. "\\" .. ''
]],
    ['long strings and comments'] = [==[
s = [[x]] .. [=[a]]b]=] .. [[
two]]
--[[ c ]] --[=[ c]]d ]=]
-- short
x = 1 -- after
]==],
    numbers = [[
n = 1 + 1.5 + .5 + 5. + 1e10 + 1E-3 + 2.5e+7 + 0xff + 0XA0
]],
    operators = [[
a = b .. c == d ~= e <= f >= g < h > i
f(...) t.x = t[1] - #t * -2 / 3 % 4 ^ 5
::top::
]],
  }

  for name, src in pairs(samples) do
    it('agree on ' .. name, function()
      assert.same(tokens(src), elements(src))
    end)
  end
end)
