require('util.string.string')
local lua = require('model.editor.luaLayer')
local parser = lua.parser()

--- Where a draft fails to parse (editor principles, IS3.4 and
--- IS3.5): before the first character the failure names, or
--- at the draft's end when it is only unfinished.
describe('parse failure boundary #parser', function()
  --- @param lines string[]
  --- @return table --- {line, column, at_end}
  local function failure(lines)
    local ok, err = parser.parse(lines)
    assert.is_false(ok)
    local f = lua.failure(lines, err)
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

  it('is the first character after spaces or empty lines',
    function()
      assert.same({ 1, 2, false }, failure({ ' x' }))
      assert.same({ 2, 1, false }, failure({ '', 'hello' }))
      assert.same({ 2, 7, false }, failure({ '', '  x = = 1' }))
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
    lua.failure(lines, err)
    assert.same({ l, c }, { err.l, err.c })
  end)
end)

--- The editor's rules around the language layer's verdict
describe('the editor on Lua text #editor', function()
  --- editor principles, IS3.7: every empty line of a draft
  --- becomes an empty-line block, the trailing ones too
  it('keeps every empty line of a draft as a block', function()
    local function kinds_of(lines)
      local verdict = lua.submission(lines, 64, 14)
      local kinds = {}
      for _, b in ipairs(verdict.blocks) do
        table.insert(kinds, b:is_empty() and 'empty' or 'code')
      end
      return kinds, verdict.lines
    end
    assert.same({ 'code', 'empty' }, (kinds_of({ 'a = 1', '' })))
    assert.same({ 'code', 'empty', 'empty' },
      (kinds_of({ 'a = 1', '', '' })))
    local kinds, lines = kinds_of({ 'a = 1', '', '', '' })
    assert.same({ 'code', 'empty', 'empty', 'empty' }, kinds)
    assert.same({ 'a = 1', '', '', '' }, lines)
    assert.same({ 'empty', 'empty', 'code' },
      (kinds_of({ '', '', 'a = 1' })))
    assert.same({ 'code', 'empty', 'empty', 'code' },
      (kinds_of({ 'a = 1', '', '', 'b = 2' })))
  end)

  it('measures the blocks of a draft with its empty lines',
    function()
      local lines = { 'a = 1', '', '', 'function f()' }
      for i = 1, 13 do lines[#lines + 1] = '  b' .. i .. ' = ' .. i end
      lines[#lines + 1] = 'end'
      local verdict = lua.submission(lines, 64, 14)
      assert.is_false(verdict.ok)
      local big = verdict.blocks[verdict.oversized[1]]
      assert.same(15, big.pos:len())
    end)

  it('takes a draft of blank lines for empty-line blocks',
    function()
      assert.is_nil(lua.empty_blocks({ '' }))
      assert.is_nil(lua.empty_blocks({ 'a = 1', '' }))
      assert.same(2, #lua.empty_blocks({ '', '' }))
      assert.same(1, #lua.empty_blocks({ '  ' }))
      assert.is_true(lua.empty_blocks({ '', ' ' })[2]:is_empty())
    end)

  it('keeps a draft of two lines that opens with # as typed',
    function()
      local lines = { '#speed = 5', 'speed = 10' }
      local verdict = lua.submission(lines, 64, 14)
      assert.same('#speed = 5', verdict.lines[1])
    end)

  it('names the line over the limit and its length', function()
    local long = string.rep('a', 70) .. ' = 1'
    local verdict = lua.submission({ 'x = 1', long }, 64, 14)
    assert.is_false(verdict.ok)
    assert.same(2, verdict.long_line.l)
  end)

  it('names the files of require and dofile written out',
    function()
      local _, ast = parser.parse({
        'local m = require("mod")',
        'dofile("level.lua")',
        'require(name)',
        'local f = function() return require "deep" end',
      })
      local refs = lua.references(ast)
      local got = {}
      for _, r in ipairs(refs) do
        got[#got + 1] = { r.line, r.name, r.file or false }
      end
      assert.same({
        { 1, 'mod', false },
        { 2, 'level.lua', true },
        { 4, 'deep', false },
      }, got)
    end)
end)
