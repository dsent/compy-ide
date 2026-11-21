--- Warranted under the testing policy as a developer tool whose
--- output silently affects other code: the formatter rewrites
--- whole source files from the editor, the REPL and compyfmt.

local format = require("model.lang.lua.format")
local parser = require("model.lang.lua.parser")()
local display = require("conf.display")

local W = display.columns
local it_luajit = jit and it or pending

--- @param path string
--- @return string[]
local function read_lines(path)
  local f = assert(io.open(path))
  local text = f:read('*a')
  f:close()
  return string.lines(text)
end

--- @return string[]
local function bundled_examples()
  local found = {}
  local ls = assert(io.popen("find src/examples -name '*.lua' | sort"))
  for path in ls:lines() do table.insert(found, path) end
  ls:close()
  return found
end

describe('lua format #format', function()
  it('rewrites code the way the editor writes it', function()
    local out, ok = format.format({ 'function f()   return  1 end' }, W)
    assert.is_true(ok)
    assert.same({ 'function f()', '  return 1', 'end' }, out)
  end)

  it('accepts lone and repeated semicolons', function()
    for _, case in ipairs({
      { { ';' }, { '' } },
      { { ';;;' }, { '' } },
      { { 'x = 1;;' }, { 'x = 1' } },
      { { '; x = 1; ; y = 2;;' }, { 'x = 1', 'y = 2' } },
      { { 'if x then ; end' }, { 'if x then', '  ', 'end' } },
      { { 'if x then', '  -- note', '  ;', 'end' },
        { 'if x then', '  -- note', 'end' } },
    }) do
      local out, ok = format.format(case[1], W)
      assert.is_true(ok, table.concat(case[1], '\n'))
      assert.same(case[2], out)
      assert.same(out, (format.format(out, W)))
    end
  end)

  it('keeps a semicolon before a statement starting with (', function()
    for _, case in ipairs({
      { { 'f();(g)()' }, { 'f(); (g)()' } },
      { { 'x = a; (t).k = 1' }, { 'x = a; (t).k = 1' } },
      { { 'f(); (g):m()' }, { 'f(); (g):m()' } },
      { { 'f(); (t).m().k = 1' }, { 'f(); (t).m().k = 1' } },
      { { 'f(); "s":gsub()' }, { 'f(); ("s"):gsub()' } },
    }) do
      local out, ok = format.format(case[1], W)
      assert.is_true(ok, table.concat(case[1], '\n'))
      assert.same(case[2], out)
      assert.same(out, (format.format(out, W)))
    end
    local with_comment = { 'f() -- c', ';(g)()' }
    local out, ok = format.format(with_comment, W)
    if ok then
      assert.same(out, (format.format(out, W)))
      assert.is_truthy(table.concat(out, '\n'):find('-- c', 1, true))
      local before = assert(loadstring(table.concat(with_comment, '\n')))
      local after = assert(loadstring(table.concat(out, '\n')))
      assert.equal(string.dump(before, true), string.dump(after, true))
    else
      assert.equal(with_comment, out)
    end
  end)

  it('ends a return with no values at the keyword', function()
    local text = { 'function f(x)', '  if x then', '    return',
      '  end', 'end' }
    local out, ok = format.format(text, W)
    assert.is_true(ok)
    assert.same(text, out)
  end)

  it('keeps an empty line in a run of comments empty', function()
    local text = { '-- first', '--', '-- second', 'x = 1' }
    local out, ok = format.format(text, W)
    assert.is_true(ok)
    assert.same(text, out)
  end)

  it('keeps the spaces ending a comment where a line breaks',
    function()
      local text = { 'return a -- why   ',
        'and ' .. string.rep('b', 59) }
      local out, ok = format.format(text, W)
      assert.is_true(ok)
      local comment
      for _, l in ipairs(out) do
        comment = comment or string.match(l, '%-%-.*$')
      end
      assert.equal('-- why   ', comment)
    end)

  it('wraps a comment wider than the line between words', function()
    local out, ok = format.format({
      'function f()',
      '  -- the hook runs BEFORE the widget, so without the guard'
      .. ' every i typed into it',
      '  go()',
      'end',
    }, W)
    assert.is_true(ok)
    assert.same({
      'function f()',
      '  -- the hook runs BEFORE the widget, so without the guard every',
      '  -- i typed into it',
      '  go()',
      'end',
    }, out)
  end)

  it('cuts a word wider than the line at the column', function()
    --- a URL has no space to break at; the dash it is cut before
    --- stays text, and does not join the `--`
    local out, ok = format.format({
      '-- see https://github.com/Aethelios/'
      .. 'Conway-s-Game-of-Life-in-Lua-and-Love2D',
      'x = 1',
    }, W)
    assert.is_true(ok)
    assert.same({
      '-- see',
      '-- https://github.com/Aethelios/Conway-s-Game-of-Life-in-Lua-and',
      '-- -Love2D',
      'x = 1',
    }, out)
  end)

  it('keeps a comment as wide as the line on one line', function()
    local rule = '-- send, exec ' .. string.rep('-', 50)
    local text = { rule, 'x = 1' }
    local out, ok = format.format(text, W)
    assert.is_true(ok)
    assert.same(text, out)
    assert.equal(W, #rule)
  end)

  it('wraps a continued line again when it fills up', function()
    local text = { 'help = "Hint:\\n" .. "left click for next example\\n"'
      .. ' .. "shift + left click to go back\\n"'
      .. ' .. "right click for a random one"' }
    local out, ok = format.format(text, W)
    assert.is_true(ok)
    assert.is_true(#out > 2)
    for n, l in ipairs(out) do
      assert.is_true(string.ulen(l) <= W, n .. ': ' .. l)
    end
    local function run(lines)
      return assert(loadstring(table.concat(lines, '\n')
        .. '\nreturn help'))()
    end
    assert.equal(run(text), run(out))
  end)

  it("keeps a call's parenthesis on the line of what it calls",
    function()
      --- a `(` starting a line would begin a new statement
      for _, src in ipairs({
        'return a + ' .. string.rep('b', 60) .. '(1)',
        'return a + ' .. string.rep('b', 58) .. ':m(1)',
      }) do
        local out, ok = format.format({ src }, W)
        assert.is_true(ok)
        assert(loadstring(table.concat(out, '\n')))
        for _, l in ipairs(out) do
          assert.is_nil(string.match(l, '^%s*%('), l)
        end
      end
    end)

  it('keeps a block comment before a call\'s parenthesis in place',
    function()
      for _, src in ipairs({
        'return f --[[ c ]] (1)',
        'g(x) --[[ c ]] (y)',
      }) do
        local out, ok = format.format({ src }, W)
        assert.is_true(ok)
        assert.same({ src }, out)
        assert(loadstring(src))
      end
      --- a trailing block comment elsewhere still takes a line
      local out = format.format({ 'x = 1 --[[ note ]]' }, W)
      assert.same({ 'x = 1', '--[[ note ]]' }, out)
    end)

  it('opens the parenthesis before a comment over several lines',
    function()
      --- legal before a string or table argument, which the
      --- printer puts in parentheses
      local out, ok = format.format(
        { 'return f --[[ a', 'b ]] "abc"' }, W)
      assert.is_true(ok)
      assert.same({ 'return f(--[[ a', 'b ]]', '"abc")' }, out)
      assert(loadstring(table.concat(out, '\n')))
      --- indented, such a comment settles as well
      local src = { 'function h()', '  return f --[[ a', 'b ]] "s"',
        'end' }
      local out2, ok2 = format.format(src, W)
      assert.is_true(ok2)
      assert.same(
        { 'function h()', '  return f(--[[ a', 'b ]]', '  "s")', 'end' },
        out2
      )
      assert(loadstring(table.concat(out2, '\n')))
    end)

  it('settles on a multi-line block comment in an indented body',
    function()
      local text = {
        'function f()',
        '  --[[',
        '  a',
        '  ]]',
        '  y = 2',
        'end',
      }
      local out, ok = format.format(text, W)
      assert.is_true(ok)
      assert.same(text, out)
    end)

  it('opens the parenthesis before a line comment', function()
    --- the comment ends its line, so the argument starts the next
    local cases = {
      { { 'return f -- one', '  "s"' },
        { 'return f(-- one', '"s")' } },
      { { 'function h()', '  return f -- one', '    "s"', 'end' },
        { 'function h()', '  return f(-- one', '  "s")', 'end' } },
      --- two comments open it once
      { { 'return f --[[ a', 'b ]] -- two', '  { 1 }' },
        { 'return f(--[[ a', 'b ]]', '-- two', '{ 1 })' } },
    }
    for _, c in ipairs(cases) do
      local out, ok = format.format(c[1], W)
      assert.is_true(ok)
      assert.same(c[2], out)
      assert(loadstring(table.concat(out, '\n')))
    end
  end)

  it('leaves text that does not parse as it is', function()
    local text = { 'function f(', '  return 1' }
    local out, ok = format.format(text, W)
    assert.is_false(ok)
    assert.equal(text, out)
  end)

  --- LuaJIT skips a `#!` first line, and so does the parser:
  --- it is in no program the printer prints from
  describe('with a #! first line', function()
    local H = '#!/usr/bin/env luajit -b whatever'

    it('keeps it byte for byte and formats the rest',
      function()
        local out, ok = format.format({ H, 'x=1', 'y  =  2' }, W)
        assert.is_true(ok)
        assert.same({ H, 'x = 1', 'y = 2' }, out)
      end)

    it('formats the rest as it formats it alone', function()
      for _, code in ipairs({
        { 'x=1' },
        { '', 'x=1' },
        { '-- note', 'function f() return 1 end' },
        { 'a = 1', '', '', 'b = 2', '', '' },
        { '' },
      }) do
        local alone, ok = format.format(code, W)
        local with = { H }
        for _, l in ipairs(code) do table.insert(with, l) end
        local out, ok2 = format.format(with, W)
        assert.equal(ok, ok2)
        assert.same(H, out[1])
        assert.same(alone, table.slice(out, 2, #out))
        assert.same(out, (format.format(out, W)))
      end
    end)

    it('is formatted alone, and stays as it is', function()
      for _, text in ipairs({ { H }, { H, '' } }) do
        local out, ok = format.format(text, W)
        assert.is_true(ok)
        assert.same(text, out)
      end
    end)

    it('keeps a carriage return ending it', function()
      local out, ok = format.format({ H .. '\r', 'x = 1\r' }, W)
      assert.is_true(ok)
      assert.same({ H .. '\r', 'x = 1' }, out)
    end)

    it('leaves the text as it is when the rest fails', function()
      for _, text in ipairs({
        { H, 'x = = 1' },
        { H, '#!/usr/bin/lua', 'x = 1' },
        { H, '# note' },
        { 'x = 1', H },
      }) do
        local out, ok = format.format(text, W)
        assert.is_false(ok)
        assert.equal(text, out)
      end
    end)
  end)

  it('collapses every run of blank lines to one', function()
    local out = format.format({
      '', '', 'a = 1', '', '', '', 'b = 2', '', '',
    }, W)
    assert.same({ '', 'a = 1', '', 'b = 2', '' }, out)
  end)

  it('keeps code that follows a comment inside an expression',
    function()
      local out, ok = format.format({ 'x = a -- why', '  + b' }, W)
      assert.is_true(ok)
      local _, ast = parser.parse(out)
      assert.equal('Op', ast[1][2][1].tag)
    end)

  --- the editor's input keeps only UTF-8, so a raw byte would
  --- be gone the next time the block is opened
  it('writes bytes that are not UTF-8 as escapes', function()
    local out, ok = format.format({ 's = "\\255"' }, W)
    assert.is_true(ok)
    assert.same({ 's = "\\255"' }, out)
    local _, ast = parser.parse(out)
    assert.equal('\255', ast[1][2][1][1])
  end)

  it('reads a long string the way Lua does, whatever its breaks',
    function()
      local text = { 'return [[\r\nabc\rdef\n\rghi]]' }
      local out, ok = format.format(text, W)
      assert.is_true(ok)
      local run = function(lines)
        return assert(loadstring(table.concat(lines, '\n')))()
      end
      assert.equal(run(text), run(out))
    end)

  it('refuses to drop a comment the printer cannot place', function()
    for _, text in ipairs({
      { 'function f(', '  -- note', ')', '  return 1', 'end' },
      { 'f();--', ';' },
      { 't = {a = 1, --[[last]] --', '}' },
    }) do
      local out, ok = format.format(text, W)
      assert.is_false(ok, table.concat(text, '\n'))
      assert.equal(text, out)
    end
  end)

  it('keeps comments before a table closing brace', function()
    for _, case in ipairs({
      { { 't = {', '  a = 1, -- last', '}' },
        { 't = {', '  a = 1', '  -- last', '}' } },
      { { 't = {', '  a = 1, --', '}' },
        { 't = {', '  a = 1', '  --', '}' } },
      { { 't = {', '  a = 1,', '', '  -- last', '}' },
        { 't = {', '  a = 1', '', '  -- last', '}' } },
      { { 't = {', '  -- only', '}' },
        { 't = {', '  -- only', '}' } },
      { { 't = {', '  --', '}' },
        { 't = {', '  --', '}' } },
    }) do
      local out, ok = format.format(case[1], W)
      assert.is_true(ok, table.concat(case[1], '\n'))
      assert.same(case[2], out)
      assert.same(out, (format.format(out, W)))
    end
  end)

  it('keeps comments on keyed table fields and in empty bodies',
    function()
      for _, text in ipairs({
        { 't = {', '  -- c', '  a = 1,', '}' },
        { 't = {', '  a = 1, -- c', '  b = 2,', '}' },
        { 'return { -- c', '  a = 1 }' },
      }) do
        local out, ok = format.format(text, W)
        assert.is_true(ok, table.concat(text, '\n'))
        assert.same(out, (format.format(out, W)))
      end
      for _, text in ipairs({
        { 'if x then', '  -- c', 'end' },
        { 'if x then', '  -- c1', '', '  -- c2', 'end' },
        { 'if x then', '  -- c1', 'elseif y then', '  -- c2',
          'else', '  -- c3', 'end' },
        { 'while x do', '  -- c', 'end' },
        { 'for i = 1, 2 do', '  -- c', 'end' },
        { 'for k in pairs(t) do', '  -- c', 'end' },
        { 'repeat', '  -- c', 'until x' },
        { 'do', '  -- c', 'end' },
        { 'do', '  -- c1', '', '  -- c2', 'end' },
        { 'function f()', '  -- c', 'end' },
        { 'local function f()', '  -- c', 'end' },
        { 'function t:m()', '  -- c', 'end' },
        { 'local f = function()', '  -- c', 'end' },
      }) do
        local out, ok = format.format(text, W)
        assert.is_true(ok, table.concat(text, '\n'))
        assert.same(text, out)
        assert.same(out, (format.format(out, W)))
      end
      --- an empty body without comments keeps its indented line
      local empty, ok = format.format({ 'function f() end' }, W)
      assert.is_true(ok)
      assert.same({ 'function f()', '  ', 'end' }, empty)
    end)

  it('writes escapes as written, and settles on them', function()
    local text = { [[s = "a\r\nb\t\0\0001\27[0m\a\b\f\v\127"]] }
    local out, ok = format.format(text, W)
    assert.is_true(ok)
    assert.same(text, out)
  end)

  it_luajit('decodes \\u{...} escapes as LuaJIT does', function()
    for _, lit in ipairs({ '"\\u{48}"', '"\\u{10FFFF}"' }) do
      local src = 'return ' .. lit
      local out, ok = format.format({ src }, W)
      assert.is_true(ok, lit)
      assert.equal(
        assert(loadstring(src))(),
        assert(loadstring(table.concat(out, '\n')))(),
        lit
      )
    end
  end)

  it('reports line, column and message on invalid escapes', function()
    for _, bad in ipairs({
      's = "\\q"',
      's = "\\u{D800}"',
      's = "\\u{110000}"',
      's = "\\x4"',
      's = "\\256"',
    }) do
      local ok, err = parser.parse({ 'x = 1', bad })
      assert.is_false(ok, bad)
      assert.equal(2, err.l, bad)
      assert.is_true(err.c >= 5 and err.c <= #bad, bad)
      assert.is_truthy(
        string.find(err.msg, 'invalid escape sequence', 1, true),
        bad
      )
    end
  end)

  it_luajit('scans string escapes left to right as LuaJIT does', function()
    for _, lit in ipairs({
      '"\\0\\z  1"',
      '"\\z  \\65"',
      '"\\\\z"',
      '"\\092z  1"',
      '"\\x5cn"',
      '"\\0921"',
    }) do
      local src = 'return ' .. lit
      local out, ok = format.format({ src }, W)
      assert.is_true(ok, lit)
      assert.equal(
        assert(loadstring(src))(),
        assert(loadstring(table.concat(out, '\n')))(),
        lit
      )
    end
  end)

  it('prints numbers so they read back as the same value', function()
    for _, lit in ipairs({
      '3.14159265358979',
      '9007199254740993',
      '0xffffffffffffffff',
      '398492087598247598237529834759827345928375928734958729387459283787459837452987345982375',
      '1e309',
    }) do
      local src = 'return ' .. lit
      local out, ok = format.format({ src }, W)
      assert.is_true(ok, lit)
      assert.equal(
        assert(loadstring(src))(),
        assert(loadstring(table.concat(out, '\n')))(),
        lit
      )
    end
    local out, ok = format.format({ 'x = 1e309' }, W)
    assert.is_true(ok)
    assert.same({ 'x = 1e999' }, out)
  end)

  it_luajit('keeps LuaJIT FFI number literals as typed', function()
    for _, lit in ipairs({
      '1LL', '1ll', '1ULL', '1ull', '1LLu',
      '0x1e2LL', '0x1000000000000000ULL',
      '12i', '12I', '1.5i', '1e2i', '0x1p2i',
    }) do
      local src = 'return ' .. lit
      local out, ok = format.format({ src }, W)
      assert.is_true(ok, lit)
      assert.same({ src }, out, lit)
      local fn_before = assert(loadstring(src))
      local fn_after = assert(loadstring(table.concat(out, '\n')))
      assert.equal(
        string.dump(fn_before, true),
        string.dump(fn_after, true),
        lit
      )
      assert.equal(tostring(fn_before()), tostring(fn_after()), lit)
    end
    for _, bad in ipairs({
      '1.5LL', '1e2LL', '0x1.5LL', '0x1p2LL',
      '1LL..2', '1ULL..2', '12i..2',
    }) do
      local text = { 'x = ' .. bad }
      local out, ok = format.format(text, W)
      assert.is_false(ok, bad)
      assert.equal(text, out)
    end
    --- a suffixed literal is distinct from a plain number in the AST
    local _, ast_ll = parser.parse({ 'x = 1LL' })
    local _, ast_n = parser.parse({ 'x = 1' })
    assert.are_not.equal(ast_ll[1][2][1][1], ast_n[1][2][1][1])
  end)

  it('formats not eq and not "eq" without confusing them for ==',
    function()
      for _, text in ipairs({
        { 'if not eq then', '  ', 'end' },
        { 'x = not "eq"' },
        { 'x = not (eq)' },
        { 'x = not ("eq")' },
      }) do
        local out, ok = format.format(text, W)
        assert.is_true(ok, table.concat(text, '\n'))
        assert.same(text, out)
      end
    end)

  it('parenthesizes a split string on the left of ..', function()
    local long = string.rep('a', 90)
    local cases = {
      { 'return function(a) return "' .. long .. '" .. a end' },
      { 'return function(t, l) return t .. [[' .. long .. ']] .. l end' },
      read_lines('tests/interpreter/markdown_inputs.lua'),
    }
    for _, text in ipairs(cases) do
      local out, ok = format.format(text, W)
      assert.is_true(ok, text[1])
      assert.same(out, (format.format(out, W)))
      if #text == 1 then
        local before = assert(loadstring(text[1]))()
        local after = assert(loadstring(table.concat(out, '\n')))()
        assert.equal(before('X', 'Y'), after('X', 'Y'))
      end
    end
  end)

  it('parenthesizes a split string under unary and arithmetic operators',
    function()
      local a96 = string.rep('a', 96)
      local d96 = string.rep('1', 96)
      for _, expr in ipairs({
        '#"' .. a96 .. '"',
        'not "' .. a96 .. '"',
        '-"' .. d96 .. '"',
        '1 + "' .. d96 .. '"',
        '"' .. d96 .. '" + 1',
        '2 * "' .. d96 .. '"',
        '"' .. d96 .. '" ^ 1',
      }) do
        local src = 'return ' .. expr
        local out, ok = format.format({ src }, W)
        assert.is_true(ok, expr)
        assert.same(out, (format.format(out, W)))
        assert.equal(
          assert(loadstring(src))(),
          assert(loadstring(table.concat(out, '\n')))(),
          expr
        )
      end
    end)

  --- every byte, in a string long enough to be split into
  --- pieces: the printed literal holds the same bytes
  it('keeps the value of a string holding every byte', function()
    local bytes, escaped = {}, {}
    for b = 0, 255 do
      table.insert(bytes, string.char(b))
      table.insert(escaped, string.format('\\%03d', b))
    end
    local text = { 'return "' .. table.concat(escaped) .. '"' }
    local out, ok = format.format(text, W)
    assert.is_true(ok)
    assert.are_not.same(text, out)
    local run = assert(loadstring(table.concat(out, '\n')))
    assert.equal(table.concat(bytes), run())
  end)

  it('keeps what a long string holds, backslashes and all',
    function()
      local text = {
        'return [[one \\\\n two, and a line long enough that the',
        'printer splits it into pieces]]',
      }
      local out, ok = format.format(text, W)
      assert.is_true(ok)
      local run = function(lines)
        return assert(loadstring(table.concat(lines, '\n')))()
      end
      assert.equal(run(text), run(out))
    end)

  it_luajit('preserves LuaJIT bytecode across ast_inputs and bundled examples',
    function()
      local ast_inputs = require('tests.interpreter.ast_inputs')
      local allowed_diff = {
        ['wrap[3]'] = 'long string split into .. pieces',
        ['wrap[13]'] = 'long string split into .. pieces',
        ['wrap[40]'] = 'long string split into .. pieces',
        ['wrap[41]'] = 'long string split into .. pieces',
        ['wrap[42]'] = 'long string split into .. pieces',
      }
      local expected_refused = {}
      local actual_diff, actual_refused = {}, {}

      local function check(name, lines, expected)
        local src = table.concat(lines, '\n')
        local before = loadstring(src)
        if not before then return end
        local out, ok = format.format(lines, W)
        if not ok then
          assert.same(lines, out, name)
          table.insert(actual_refused, name)
          return
        end
        local after = assert(loadstring(table.concat(out, '\n')), name)
        local exp_fn = expected and allowed_diff[name]
            and assert(loadstring(table.concat(expected, '\n')), name)
        local bc_before = string.dump(before, true)
        local bc_after = string.dump(after, true)
        local bc_exp = exp_fn and string.dump(exp_fn, true)
        assert.is_function(before)
        assert.is_function(after)
        if exp_fn then assert.is_function(exp_fn) end
        if bc_before ~= bc_after then
          if allowed_diff[name] then
            assert.equal(bc_exp, bc_after, name)
          end
          actual_diff[name] = allowed_diff[name] or 'unexpected diff'
        end
      end

      for _, group in ipairs(ast_inputs) do
        local tag, cases = group[1], group[2]
        for i, tc in ipairs(cases) do
          check(string.format('%s[%d]', tag, i), tc[1], tc[2])
        end
      end
      for _, path in ipairs(bundled_examples()) do
        check(path, read_lines(path))
      end

      assert.same(allowed_diff, actual_diff)
      assert.same(expected_refused, actual_refused)
    end)

  describe('on the bundled examples', function()
    for _, path in ipairs(bundled_examples()) do
      it('formats ' .. path .. ', and a second time changes nothing',
        function()
          local once, ok = format.format(read_lines(path), W)
          assert.is_true(ok, 'formats')
          local twice = format.format(once, W)
          assert.same(once, twice)
        end)
      --- a comment keeps what its source line holds
      it('ends no code line of ' .. path .. ' in a space', function()
        local once = format.format(read_lines(path), W)
        for n, l in ipairs(once) do
          local code = not string.match(l, '^%s*%-%-')
          if code and string.match(l, '%S%s+$') then
            error(path .. ':' .. n .. ' ends in a space')
          end
        end
      end)
    end
  end)
end)
