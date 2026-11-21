require('util.string.string')
local lua = require('model.syntax.lua')
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

  it('tells a # statement to use -- and places it at #',
    function()
      local msg = '# cannot go here. A comment starts with --.'
      local cases = {
        { { '# note' }, 1, 1 },
        { { 'print("hi")', '# say hi' }, 2, 1 },
        { { 'x = 1 # n' }, 1, 7 },
        { { 'print(1)', '#!/usr/bin/lua' }, 2, 1 },
        { { '#!/usr/bin/lua', '#!/usr/bin/lua' }, 2, 1 },
      }
      for _, case in ipairs(cases) do
        local ok, err = parser.parse(case[1])
        assert.is_false(ok)
        assert.same({ case[2], case[3], msg },
          { err.l, err.c, err.msg })
        local f = lua.failure(case[1], err)
        assert.same({ case[2], case[3], false, msg },
          { f.l, f.c, f.at_end or false, f.msg })
      end
      assert.is_true(
        lua.submission({ '#!/usr/bin/lua', 'print(1)' }, 64, 14).ok)
      local v = lua.submission({ '# note' }, 64, 14)
      assert.is_false(v.ok)
      assert.same({ 1, 1, msg },
        { v.failure.l, v.failure.c, v.failure.msg })
    end)

  it('refuses a non-target before = at the target itself',
    function()
      local msg = 'Only a variable like score or scores[1] can go before =.'
      local bad = {
        { { 'x + 1 = 2' }, 1, 1 },
        { { 'f() = 1' }, 1, 1 },
        { { '(x) = 1' }, 1, 1 },
        { { '1 = 2' }, 1, 1 },
        { { 'a, f() = 1, 2' }, 1, 4 },
      }
      for _, case in ipairs(bad) do
        local ok, err = parser.parse(case[1])
        assert.is_false(ok)
        assert.same({ case[2], case[3], msg },
          { err.l, err.c, err.msg })
        local f = lua.failure(case[1], err)
        assert.same({ case[2], case[3], false, msg },
          { f.l, f.c, f.at_end or false, f.msg })
      end
      assert.same({ 1, 9, false }, failure({ 't["é"], f() = 1, 2' }))
      for _, code in ipairs({
        'x = 1', 't.a = 1', 't[1] = 2', 'a, b = 1, 2',
        't.a.b = 1', 'f().x = 1', 'f()[1] = 1',
      }) do
        assert.is_true((parser.parse({ code })), code)
        assert.is_true(lua.submission({ code }, 64, 14).ok, code)
      end
    end)
end)

--- The editor's rules around the language layer's verdict
describe('the editor on Lua text #editor', function()
  --- the formatter decides a draft's empty lines (the ruling
  --- "The formatter decides a draft's empty lines"): one of a
  --- run, at a draft's start and end too
  it('takes the empty lines of a draft as the gate leaves them',
    function()
      local function kinds_of(lines)
        local verdict = lua.submission(lines, 64, 14)
        local kinds = {}
        for _, b in ipairs(verdict.blocks) do
          table.insert(kinds, b:is_empty() and 'empty' or 'code')
        end
        return kinds, verdict.lines
      end
      assert.same({ 'code', 'empty' }, (kinds_of({ 'a = 1', '' })))
      local kinds, lines = kinds_of({ 'a = 1', '', '', '' })
      assert.same({ 'code', 'empty' }, kinds)
      assert.same({ 'a = 1', '' }, lines)
      assert.same({ 'empty', 'code' },
        (kinds_of({ '', '', 'a = 1' })))
      assert.same({ 'code', 'empty', 'code' },
        (kinds_of({ 'a = 1', '', '', 'b = 2' })))
      assert.same({ 'empty' }, (kinds_of({ '', '', '' })))
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
      local refs = lua.references({
        'local m = require("mod")',
        'dofile("level.lua")',
        'require(name)',
        'local f = function() return require "deep" end',
        'require("lib.util")',
      })
      local got = {}
      for _, r in ipairs(refs) do
        got[#got + 1] = { r.line, r.name, r.file }
      end
      assert.same({
        { 1, 'mod', 'mod.lua' },
        { 2, 'level.lua', 'level.lua' },
        { 4, 'deep', 'deep.lua' },
        { 5, 'lib.util', 'lib/util.lua' },
      }, got)
    end)
end)
