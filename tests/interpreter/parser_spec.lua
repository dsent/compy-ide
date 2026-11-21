local parser = require("model.lang.lua.parser")('metalua')
local term = require("util.termcolor")
require("util.color")
require("util.debug")

local inputs = require("tests.interpreter.parser_inputs")

if not orig_print then
  _G.orig_print = print
end

-- when testing with Lua5.3
if not _G.unpack then
  _G.unpack = table.unpack
end

local parser_debug = os.getenv("PARSER_DEBUG")
local highlighter_debug = os.getenv("HL_DEBUG")

describe('parse #parser', function()
  -- print(Debug.print_t(parser))
  for i, input in ipairs(inputs) do
    local tag = 'input #' .. i
    it('parses ' .. tag, function()
      local ok, r = parser.parse(input.code)
      local l, c, err
      if not ok then
        --- @type Error
        local p_err = r
        if highlighter_debug then
          Log.error(Debug.terse_t(r, nil, nil, true))
        end
        if input.error then
          local el = input.error.l
          local ec = input.error.c
          assert.are_equal(el, p_err.l)
          assert.are_equal(ec, p_err.c)
        end
      end
      if parser_debug then
        if not ok then
          print(tag, string.join(input.code, '⏎ '))
          local error = string.format("%s:%s | %s",
            l or '', c or '', err or '')
          if string.is_non_empty_string(err) then
            term.print_c(Color.red, error)
          end
          for ln, line in pairs(input.code) do
            if ln == l then
              if c == 1 then
                term.print_c(Color.magenta, line)
              else
                local ll = string.ulen(line)
                for ch = 1, ll do
                  if ch <= c then
                    term.print_c(Color.white,
                      string.usub(line, ch, ch), true)
                  else
                    term.print_c(Color.magenta,
                      string.usub(line, ch, ch), true)
                  end
                end
                print()
                for _ = 1, c do io.write(' ') end
              end
              term.print_c(Color.red, '^')
            elseif l and ln > l then
              term.print_c(Color.magenta, line)
            else
              term.print_c(Color.white, line)
            end
          end
          print()
        else
          print(tag, string.join(input.code, '⏎ '))
          local pp = parser.pprint(input.code)
          if string.is_non_empty_string_array(pp) then
            term.print_c(Color.green, string.unlines(pp or ''))
          end
        end
      end
      assert.are_equal(input.compiles, ok)
    end)
  end
end)

describe('highlight #parser', function()
  for i, input in ipairs(inputs) do
    local tag = 'input #' .. i
    it('parses ' .. tag, function()
      local hl = parser.highlighter(input.code)
      -- print(Debug.text_table(input.code, true))
      if highlighter_debug then
        for l, line in ipairs(input.code) do
          local rowc = hl[l] or {}
          for j = 1, #line do
            local c = rowc[j]
            term.print_c(c, string.sub(line, j, j), true)
          end
          print()
        end
        print(term.reset)
      end
    end)
  end

  it('does not propagate lexer errors', function()
    local invalid = 'local s = "\\999"'
    local ok, hl = pcall(parser.highlighter, invalid)
    assert.is_true(ok)
    assert.are_equal('table', type(hl))
  end)
end)

--- A failed parse names the token the parser stopped at: the
--- editor places its cursor from it, and only the parser knows
--- it.
describe('a failed parse #parser', function()
  local function token(code)
    local ok, err = parser.parse(code)
    assert.is_false(ok)
    return err.token
  end

  it('names the token it stopped at', function()
    assert.same({ l = 1, c = 7, eof = false },
      token({ 'local = 1' }))
    assert.same({ l = 2, c = 3, eof = false },
      token({ 'x = 1', 'y z' }))
  end)

  --- the parser has read the token that cannot start an
  --- expression; it stopped at the one after it
  it('names the token after one that starts no expression',
    function()
      assert.same({ l = 1, c = 7, eof = false },
        token({ 'x = = 1' }))
    end)

  it('names the end of the text when it wanted more', function()
    assert.same({ l = 1, c = 8, eof = true },
      token({ 'x = 1 +' }))
    assert.is_true(token({ 'function f()', '  return 1' }).eof)
  end)

  it('names the token it stopped at below a #! line', function()
    assert.same({ l = 2, c = 7, eof = false },
      token({ '#!/usr/bin/lua', 'local = 1' }))
  end)

  --- the lexer has read on past the failure: what it would
  --- give next is no token the parser stopped at
  it('names no token when the lexer failed', function()
    assert.is_nil(token({ 'x = "\\999" y = 1' }))
    assert.is_nil(token({ 'x = "\\999"' }))
    assert.is_nil(token({ 'x = 1', 'y = "\\999"', 'z = 2' }))
    assert.is_nil(token({ '"\\999"' }))
  end)

  it('gives a success no token', function()
    local ok, ast = parser.parse({ 'x = 1' })
    assert.is_true(ok)
    assert.is_nil(ast.token)
  end)

  it('fails with words when # follows a call', function()
    local ok, err = parser.parse({ 'print("hi")', '# say hi' })
    assert.is_false(ok)
    assert.same({ 2, 1 }, { err.l, err.c })
    assert.is_true(string.is_non_empty_string(err.msg))
  end)
end)

--- LuaJIT skips a first line starting with `#!`, the whole
--- line, and no other line: a first line such as `# note` is
--- no Lua. The gate formats what the parser reads, so a line
--- the parser skipped was written back empty.
describe('a first line starting with # #parser', function()
  local check = require('model.lang.lua.check')

  --- @param code string[]
  --- @return string[] --- the lines the gate would write
  local function gated(code)
    return check.gate(code).lines
  end

  it('is skipped whole when it starts with #!', function()
    local ok, ast = parser.parse({
      '#!/usr/bin/lua', 'x = 1', 'y = 2',
    })
    assert.is_true(ok)
    assert.same(2, #ast)
    assert.same(2, ast[1].lineinfo.first.line)
    assert.same(3, ast[2].lineinfo.first.line)
  end)

  it('is all a file may be when it starts with #!', function()
    for _, code in ipairs({
      '#!/usr/bin/lua', '#!/usr/bin/lua\n',
    }) do
      local ok, ast = parser.parse(code)
      assert.is_true(ok, code)
      assert.same(0, #ast)
    end
  end)

  it('is no Lua when it starts with # alone', function()
    for _, code in ipairs({
      { '# note', 'x = 1' },
      { '', '# note', 'x = 1' },
      { ' # note', 'x = 1' },
    }) do
      assert.is_false((parser.parse(code)))
      local verdict = check.gate(code)
      assert.is_false(verdict.ok)
      assert.same(code, verdict.lines)
    end
  end)

  --- the parser takes `#x = 1` as an assignment, as it takes
  --- any expression before `=`, which LuaJIT refuses: that is
  --- no matter of the first line
  it('keeps a line #x = 1 where it is written', function()
    for _, code in ipairs({
      { '#speed = 5', 'speed = 10' },
      { '', '#x = 1', 'y = 2' },
      { ' #x = 1', 'y = 2' },
    }) do
      local n = code[1] == '' and 2 or 1
      local ok, ast = parser.parse(code)
      assert.is_true(not ok or ast[1].lineinfo.first.line == n)
      assert.same(string.match(code[n], '#.*'), gated(code)[n])
    end
  end)

  it('is no Lua below a #! line', function()
    local ok, err = parser.parse({
      '#!/usr/bin/lua', '# y', 'x = 1',
    })
    assert.is_false(ok)
    assert.same(2, err.l)
  end)

  --- with no token before it, a failure at the first token is
  --- placed at the start of the text
  it('leaves a failure at the first token at the start',
    function()
      for _, code in ipairs({ ' q', '\nq', ' \n x y' }) do
        local ok, err = parser.parse(code)
        assert.is_false(ok)
        assert.same({ 1, 1 }, { err.l, err.c }, code)
      end
    end)
end)

--- Children type Cyrillic and other scripts. A letter outside
--- ASCII where Lua expects code fails the parse, and the
--- message names the whole letter: one of its bytes alone is
--- no text the screen can draw, and drawing it stopped the IDE.
describe('letters outside ASCII #parser', function()
  local check = require('model.lang.lua.check')

  local drafts = {
    { 'é = 1', 'é' },
    { 'п = 1', 'п' },
    { 'élet = 3', 'é' },
    { 'x = ж', 'ж' },
    { 'x = 😀', '😀' },
    { 'x = 1 + ∑', '∑' },
  }

  for _, d in ipairs(drafts) do
    local code, letter = d[1], d[2]
    it('fail on ' .. code .. ' naming the letter', function()
      local ok, err = parser.parse({ code })
      assert.is_false(ok)
      assert.is_not_nil(string.ulen(err.msg), err.msg)
      assert.truthy(err.msg:find('`' .. letter .. "'", 1, true),
        err.msg)
    end)

    it('fail the gate on ' .. code .. ' with text', function()
      local verdict = check.gate({ code })
      assert.is_false(verdict.ok)
      for _, e in ipairs(verdict.errors) do
        assert.is_not_nil(string.ulen(e.msg), e.msg)
      end
    end)

    it('highlight ' .. code .. ' without an error', function()
      local ok, hl = pcall(parser.highlighter, { code })
      assert.is_true(ok, hl)
    end)
  end

  it('are no failure in a string or a comment', function()
    assert.is_true((parser.parse({ 'x = "ж" -- ж' })))
    assert.is_true((parser.parse({ '--[[ п ]] y = "😀"' })))
  end)

  it('leave a byte that is no UTF-8 one token', function()
    local ok, err = parser.parse({ 'x = \255' })
    assert.is_false(ok)
    assert.truthy(err.msg:find("`\255'", 1, true), err.msg)
  end)
end)
