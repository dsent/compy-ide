--- Warranted under the testing policy as a developer tool whose
--- output silently affects other code: compyfmt rewrites files
--- in place, and agents run it on game code.

local compyfmt = require("util.compyfmt")

--- @param text string
--- @return string path
local function file_with(text)
  local path = os.tmpname()
  local f = assert(io.open(path, 'wb'))
  f:write(text)
  f:close()
  return path
end

--- @param path string
--- @return string
local function read(path)
  local f = assert(io.open(path, 'rb'))
  local text = f:read('*a')
  f:close()
  return text
end

describe('compyfmt #compyfmt', function()
  local paths, printed

  before_each(function()
    paths, printed = {}, {}
    stub(_G, 'print', function(s) table.insert(printed, s) end)
  end)

  after_each(function()
    _G.print:revert()
    for _, p in ipairs(paths) do os.remove(p) end
  end)

  local function new_file(text)
    local p = file_with(text)
    table.insert(paths, p)
    return p
  end

  it('fixes a file in place and then has nothing to report',
    function()
      local p = new_file('a  =  1\n\n\n\nfunction f()   return 1 end')
      assert.equal(0, compyfmt.main({ p }))
      assert.same('a = 1\n\nfunction f()\n  return 1\nend\n', read(p))
      assert.same({}, printed)
      assert.equal(0, compyfmt.main({ '--check', p }))
    end)

  it('checks without writing, naming the file and exiting 1',
    function()
      local text = 'a  =  1\n'
      local p = new_file(text)
      assert.equal(1, compyfmt.main({ '--check', p }))
      assert.same(text, read(p))
      assert.same({ p .. ': not formatted' }, printed)
    end)

  it('reports what formatting cannot resolve, by line', function()
    local body = {}
    for i = 1, 14 do table.insert(body, '  x' .. i .. ' = ' .. i) end
    local p = new_file('x = 0\nfunction f()\n'
      .. table.concat(body, '\n') .. '\nend\n')
    assert.equal(1, compyfmt.main({ p }))
    assert.same({
      p .. ':2: block of 16 lines, 2 over the limit of 14',
      p .. ':2: function of 16 lines; keep it to 14'
      .. ' (function-length)',
    }, printed)
  end)

  it('leaves a file with an error, reporting it', function()
    local text = 'function f(\n'
    local p = new_file(text)
    assert.equal(1, compyfmt.main({ p }))
    assert.same(text, read(p))
    assert.equal(1, #printed)
    assert.truthy(string.find(printed[1], p .. ':1: ', 1, true))
  end)

  it('leaves a file it cannot format byte for byte', function()
    local text = 'local colors = {\n  black = 0, -- #000000\n}'
    local p = new_file(text)
    assert.equal(1, compyfmt.main({ p }))
    assert.same(text, read(p))
  end)

  it('names every block over the limit beside a long line',
    function()
      local body = {}
      for i = 1, 15 do table.insert(body, '  print(' .. i .. ')') end
      local p = new_file('function f()\n' .. table.concat(body, '\n')
        .. '\nend\n' .. string.rep('x', 70) .. ' = 1\n')
      assert.equal(1, compyfmt.main({ p }))
      assert.same({
        p .. ':1: block of 17 lines, 3 over the limit of 14',
        p .. ':1: function of 17 lines; keep it to 14'
        .. ' (function-length)',
        p .. ':18: line too long!',
      }, printed)
    end)

  describe('reports the lints of code.md', function()
    local function reports(text)
      local _, found = compyfmt.inspect(string.lines(text))
      return found
    end

    it('parameters: more than 4, counting ..., not self', function()
      assert.same({
        '4: function takes 5 parameters; keep it to 4,'
        .. ' or pass a table (parameters)',
      }, reports(table.concat({
        'function obj:m(a, b, c, d)',
        'end',
        'function g(a, b, c, d, ...)',
        'end',
      }, '\n')))
    end)

    it('nesting: deeper than 4, counted afresh in a function',
      function()
        local ok_deep = table.concat({
          'if a then',
          '  local k = function()',
          '    if b then',
          '      if c then',
          '        if d then',
          '          if e then',
          '            print(1)',
          '          end',
          '        end',
          '      end',
          '    end',
          '  end',
          'end',
        }, '\n')
        assert.same({}, reports(ok_deep))
        local too_deep = ok_deep:gsub('  local k = function%(%)',
          '  while k do')
        assert.same({
          '5: 5 levels deep; keep it to 4, or move the inner part'
          .. ' into a function (nesting)',
        }, reports(too_deep))
      end)

    it('beside a line the gate refuses', function()
      assert.same({
        '1: line too long!',
        '3: function takes 5 parameters; keep it to 4,'
        .. ' or pass a table (parameters)',
      }, reports(string.rep('a', 65) .. ' = 1\n'
        .. 'function f(a, b, c, d, e)\nend'))
    end)

    it('function length: more than 14 lines', function()
      local body = {}
      for i = 1, 13 do table.insert(body, '    print(' .. i .. ')') end
      local text = 't = {\n  f = function()\n'
        .. table.concat(body, '\n') .. '\n  end\n}'
      assert.same({
        '1: block of 17 lines, 3 over the limit of 14',
        '2: function of 15 lines; keep it to 14 (function-length)',
      }, reports(text))
    end)
  end)

  it('exits 2 for a file it cannot read', function()
    assert.equal(2, compyfmt.main({ '/nonexistent/compy.lua' }))
    assert.equal(2, compyfmt.main({ '/tmp' }))
  end)
end)
