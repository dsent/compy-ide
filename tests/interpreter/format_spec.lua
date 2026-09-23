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

  it('refuses to change what a string holds', function()
    local text = {
      'local s = [[one \\\\n two, and a line long enough that the',
      'printer splits it into pieces]]',
    }
    local out, ok = format.format(text, W)
    assert.is_false(ok)
    assert.equal(text, out)
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
    end
  end)
end)
