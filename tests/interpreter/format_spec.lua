--- Warranted under the testing policy as a developer tool whose
--- output silently affects other code: the formatter rewrites
--- whole source files from the editor, the REPL and compyfmt.

local format = require("model.lang.lua.format")
local parser = require("model.lang.lua.parser")()
local display = require("conf.display")

local W = display.columns

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

  it('leaves text that does not parse as it is', function()
    local text = { 'function f(', '  return 1' }
    local out, ok = format.format(text, W)
    assert.is_false(ok)
    assert.equal(text, out)
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
    local text = {
      'local colors = {',
      '  black = 0, -- #000000',
      '  white = 1,',
      '}',
    }
    local out, ok = format.format(text, W)
    assert.is_false(ok)
    assert.equal(text, out)
  end)

  it('writes escapes as written, and settles on them', function()
    local text = { [[s = "a\r\nb\t\0\0001\27[0m\a\b\f\v\127"]] }
    local out, ok = format.format(text, W)
    assert.is_true(ok)
    assert.same(text, out)
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
