--- Warranted under the testing policy as a developer tool whose
--- output silently affects other code: compyfmt --fix rewrites
--- files in place, and agents run it on game code.

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
      assert.equal(0, compyfmt.main({ '--fix', p }))
      assert.same('a = 1\n\nfunction f()\n  return 1\nend\n', read(p))
      assert.same({}, printed)
      assert.equal(0, compyfmt.main({ p }))
    end)

  it('by default writes nothing, naming the file and exiting 1',
    function()
      local text = 'a  =  1\n'
      local p = new_file(text)
      assert.equal(1, compyfmt.main({ p }))
      assert.same(text, read(p))
      assert.same({ p .. ': not formatted' }, printed)
    end)

  it('refuses an option other than --fix, writing nothing',
    function()
      local text = 'a  =  1\n'
      local p = new_file(text)
      assert.equal(2, compyfmt.main({ '--check', p }))
      assert.same(text, read(p))
      assert.same({}, printed)
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
    assert.equal(1, compyfmt.main({ '--fix', p }))
    assert.same(text, read(p))
    assert.equal(1, #printed)
    assert.truthy(string.find(printed[1], p .. ':1: ', 1, true))
  end)

  it('leaves a file it cannot format byte for byte', function()
    local text = 'local colors = {\n  black = 0, -- #000000\n}'
    local p = new_file(text)
    assert.equal(1, compyfmt.main({ '--fix', p }))
    assert.same(text, read(p))
  end)

  it('names every block over the limit beside a long line',
    function()
      local body = {}
      for i = 1, 15 do table.insert(body, '  print(' .. i .. ')') end
      local p = new_file('function f()\n' .. table.concat(body, '\n')
        .. '\nend\n' .. string.rep('x', 70) .. ' = 1\n')
      assert.equal(1, compyfmt.main({ '--fix', p }))
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

  describe('reports the game conventions', function()
    --- the reports of one rule, strict rules included
    local function of(rule, ...)
      local text = table.concat({ ... }, '\n')
      local _, found = compyfmt.inspect(string.lines(text), true)
      local mine = {}
      for _, r in ipairs(found) do
        if string.sub(r, -#rule - 2) == '(' .. rule .. ')' then
          table.insert(mine, string.sub(r, 1, -#rule - 4))
        end
      end
      return mine
    end

    it('module-local: a local at file level', function()
      assert.same({
        '1: local score, lives at file level; drop local so the'
        .. ' console can see them',
      }, of('module-local',
        'local score, lives = 0, 3',
        'function f()',
        '  local n = 1',
        '  return n',
        'end'))
      assert.same({}, of('module-local', 'score = 0'))
    end)

    it('love-load: love.load defined', function()
      assert.same({
        '1: set things up at the top of the file instead of in'
        .. ' love.load',
      }, of('love-load',
        'function love.load()',
        '  SCORE = 0',
        'end'))
      assert.same({}, of('love-load', 'function love.draw()', 'end'))
    end)

    it('metatable: setmetatable or getmetatable', function()
      assert.same({
        '1: uses a metatable; use a plain table instead',
        '2: uses a metatable; use a plain table instead',
      }, of('metatable',
        'T = setmetatable({ }, MT)',
        'MT = getmetatable(T)'))
      assert.same({}, of('metatable', 'T = { }'))
    end)

    it('raw-color: setColor given numbers', function()
      local msg = 'color given as numbers; use a Color entry,'
          .. ' as in Color[Color.red]'
      assert.same({ '1: ' .. msg, '2: ' .. msg }, of('raw-color',
        'gfx.setColor(1, 0, 0)',
        'love.graphics.setColor({',
        '  1,',
        '  1,',
        '  1',
        '})'))
      assert.same({}, of('raw-color',
        'gfx.setColor(Color[Color.red])',
        'gfx.setColor(red, green, blue)'))
    end)

    it('injected-global: assigning a global the Compy sets',
      function()
        assert.same({
          '1: gfx is set by the Compy already; remove this'
          .. ' assignment',
          '2: utf8 is set by the Compy already; remove this'
          .. ' assignment',
        }, of('injected-global',
          'gfx = love.graphics',
          'local utf8 = require("utf8")'))
        assert.same({}, of('injected-global',
          'gfx.circle("fill", 1, 2, 3)',
          'Color[20] = { 0, 0, 0 }'))
      end)

    it('injected-global: compy.audio used often without sfx',
      function()
        local beep = 'compy.audio.beep()'
        assert.same({
          '1: compy.audio is used 4 times; set sfx = compy.audio'
          .. ' once and use sfx',
        }, of('injected-global', beep, beep, beep, beep))
        assert.same({}, of('injected-global', beep, beep, beep))
        assert.same({}, of('injected-global',
          'sfx = compy.audio', beep, beep, beep, beep))
      end)

    it('compound-condition: a test joined with and/or', function()
      local msg = 'the test joins conditions with and/or; name it'
          .. ' first, as in local hit = left or right'
      assert.same({
        '1: ' .. msg, '3: ' .. msg, '6: ' .. msg, '11: ' .. msg,
      }, of('compound-condition',
        'if a and b then',
        '  x = 1',
        'elseif (c or d) then',
        '  x = 2',
        'end',
        'while e or f do',
        '  x = 3',
        'end',
        'repeat',
        '  x = 4',
        'until g and h'))
      assert.same({}, of('compound-condition',
        'hit = a or b',
        'if hit then',
        'end',
        'if not (a and b) then',
        'end'))
    end)

    it('one-char-name: a one-letter name outside x y t r i j k',
      function()
        local function msg(l, name)
          return l .. ': one-letter name ' .. name
              .. '; name it for what it holds'
        end
        assert.same({
          msg(1, 'n'), msg(2, 'f'), msg(2, 'a'), msg(3, 'q'),
          msg(6, 'c'),
        }, of('one-char-name',
          'n = 0',
          'function f(a, ...)',
          '  for q = 1, 2 do',
          '    n = n + q',
          '  end',
          '  local c = n',
          '  n = n + c',
          'end'))
        assert.same({}, of('one-char-name',
          'x, y, t, r = 0, 0, 0, 0',
          'for i = 1, 2 do',
          '  for _, k in ipairs(t) do',
          '  end',
          'end',
          'G = { }'))
      end)

    it('hot-path-allocation: a new table or function per frame',
      function()
        assert.same({
          '2: makes a new table on every frame; make it once,'
          .. ' outside love.draw',
          '6: makes a new function on every frame; make it once,'
          .. ' outside love.update',
        }, of('hot-path-allocation',
          'function love.draw()',
          '  local points = { }',
          '  gfx.points(points)',
          'end',
          'function love.update(dt)',
          '  local f = function()',
          '    return { }',
          '  end',
          '  f()',
          'end'))
        assert.same({}, of('hot-path-allocation',
          'POINTS = { 0, 0, 1, 1 }',
          'function love.draw()',
          '  gfx.polygon("fill", POINTS)',
          'end',
          'function love.keypressed(key)',
          '  local t = { }',
          'end'))
      end)

    it('function-name: an underscore in a function name',
      function()
        local function msg(l, name, as)
          return l .. ': ' .. name .. ' has an underscore; write'
              .. ' function names in camelCase, as in ' .. as
        end
        assert.same({
          msg(1, 'draw_ball', 'drawBall'),
          msg(4, '_helper', 'helper'),
          msg(7, 'move_it', 'moveIt'),
          msg(10, 'update_all', 'updateAll'),
        }, of('function-name',
          'function draw_ball()',
          '  return 1',
          'end',
          'local function _helper()',
          '  return 2',
          'end',
          'function M.move_it()',
          '  return 3',
          'end',
          'update_all = function()',
          '  return 4',
          'end'))
        assert.same({}, of('function-name',
          'function drawBall()',
          'end',
          'function love.keypressed(key)',
          'end',
          'speed_x = 1'))
      end)

    it('variable-name: a capital inside a variable name',
      function()
        local function msg(l, name, as)
          return l .. ': ' .. name .. ' has a capital inside; write'
              .. ' variable names in snake_case, as in ' .. as
        end
        assert.same({
          msg(1, 'cellSize', 'cell_size'),
          msg(2, 'ballX', 'ball_x'),
          msg(3, 'newGrid', 'new_grid'),
        }, of('variable-name',
          'cellSize = 16',
          'function move(ballX)',
          '  local newGrid = { }',
          '  return newGrid, ballX',
          'end'))
        assert.same({}, of('variable-name',
          'cell_size = 16',
          'WIDTH = 1024',
          'Color2 = 1',
          'function drawBall()',
          'end'))
      end)
  end)

  describe('game conventions, edge cases', function()
    local function of(rule, lines)
      local _, found = compyfmt.inspect(lines, true)
      local mine = {}
      for _, r in ipairs(found) do
        if string.sub(r, -#rule - 2) == '(' .. rule .. ')' then
          table.insert(mine, string.sub(r, 1, -#rule - 4))
        end
      end
      return mine
    end

    it('see through parentheses', function()
      local text = {
        'drawBall = (function()',
        '  return 1',
        'end)',
        'G = ({ })',
        'gfx.setColor({',
        '  (1),',
        '  (0),',
        '  (0)',
        '})',
        'love.draw = (function()',
        '  local points = { }',
        'end)',
      }
      assert.same({}, of('variable-name', text))
      assert.same({}, of('one-char-name', text))
      assert.same({
        '5: color given as numbers; use a Color entry, as in'
        .. ' Color[Color.red]',
      }, of('raw-color', text))
      assert.same({
        '11: makes a new table on every frame; make it once,'
        .. ' outside love.draw',
      }, of('hot-path-allocation', text))
    end)

    it('function-name: fields, bare locals, odd underscores',
      function()
        local function msg(l, name, as)
          return l .. ': ' .. name .. ' has an underscore; write'
              .. ' function names in camelCase'
              .. (as and ', as in ' .. as or '')
        end
        assert.same({
          msg(1, 'draw_ball', 'drawBall'),
          msg(6, 'draw_it', 'drawIt'),
          msg(10, 'draw_', 'draw'),
          msg(13, '_'),
        }, of('function-name', {
          'local draw_ball',
          'function draw_ball()',
          '  return 1',
          'end',
          'HANDLERS = {',
          '  draw_it = function()',
          '    return 2',
          '  end',
          '}',
          'function draw_()',
          '  return 3',
          'end',
          'function _()',
          '  return 4',
          'end',
        }))
        assert.same({}, of('variable-name', {
          'local drawBall',
          'function drawBall()',
          '  return 1',
          'end',
        }))
      end)

    it('a loop variable keeps its kind when set later', function()
      assert.same({
        '1: stepCount has a capital inside; write variable names'
        .. ' in snake_case, as in step_count',
      }, of('variable-name', {
        'for stepCount = 1, 3 do',
        '  stepCount = function()',
        '    return 1',
        '  end',
        'end',
      }))
    end)
  end)

  describe('strict rules', function()
    it('are reported with --strict only', function()
      local p = new_file('local score = 0\n')
      assert.equal(0, compyfmt.main({ p }))
      assert.same({}, printed)
      assert.equal(1, compyfmt.main({ '--strict', p }))
      assert.same({
        p .. ':1: local score at file level; drop local so the'
        .. ' console can see it (module-local)',
      }, printed)
    end)
  end)

  it('exits 2 for a file it cannot read', function()
    assert.equal(2, compyfmt.main({ '/nonexistent/compy.lua' }))
    assert.equal(2, compyfmt.main({ '/tmp' }))
  end)
end)
