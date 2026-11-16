-- The run seam (the maintainer's ruling "A run starts from a
-- clean environment", Beads
-- compy-ide-run-keeps-earlier-runs-love-handlers): a run ends
-- whatever is live exactly as a stop does, makes the project's
-- environment anew in place, and starts. The cases are the
-- eighth review round's reproducers (Codex), most of them run
-- again with no stop in between, and the preservation cases it
-- checked. Keys only, through the K helper.

local K = require('tests.helpers.editor_keys')
local F = require('tests.helpers.input_fixture')

local old_prints
local function reset(files)
  K.reset(files)
  local base, env = K.cc:get_base_env(), K.cc:get_project_env()
  old_prints = { base.print, env.print }
  base.print, env.print = print, print
end
local function run(line)
  K.type(line)
  K.keys('return')
  K.frame()
end
local function env() return K.cc:get_project_env() end
local function said(s) return K.console_text():find(s, 1, true) ~= nil end

describe('the run seam #console', function()
  after_each(function()
    if old_prints then
      K.cc:get_base_env().print = old_prints[1]
      env().print = old_prints[2]
      old_prints = nil
    end
    K.cleanup()
  end)

  it('clears a deleted release handler on an idle rerun', function()
    reset({['main.lua'] = [[
function love.keyreleased(k)
  if k == 'f2' then print('OLD_KEY') end
end
]]})
    run('run()')
    assert.equal('ready', K.app_state())
    K.write_outside('main.lua', 'fresh = true\n')
    run('run()')
    assert.is_true(env().fresh, K.console_text() .. '\nSTATE:' .. K.app_state())
    assert.is_nil(env().love.keyreleased)
    K.keys('f2')
    assert.is_false(said('OLD_KEY'), K.console_text())
  end)

  it('clears an idle run shortcut', function()
    reset({['main.lua'] = [[
compy.input.shortcuts.keypressed.f2 = function()
  print('OLD_SHORTCUT')
  return true
end
]]})
    run('run()')
    K.write_outside('main.lua', 'fresh = true\n')
    run('run()')
    assert.is_true(env().fresh)
    K.keys('f2')
    assert.is_false(said('OLD_SHORTCUT'), K.console_text())
  end)

  --- the rerun ends the idle run as a stop does, so its exit
  --- hook runs then, once, and never again
  it('clears an idle run before_exit', function()
    reset({['main.lua'] = [[
compy.before_exit = function() print('OLD_EXIT') end
]]})
    run('run()')
    K.write_outside('main.lua', 'fresh = true\n')
    run('run()')
    assert.is_true(env().fresh)
    K.keys('lctrl', 'q')
    K.frame()
    local n = select(2, K.console_text():gsub('OLD_EXIT', ''))
    assert.equal(1, n, K.console_text())
  end)

  it('clears an idle run serial handler', function()
    reset({['main.lua'] = [[
compy.serial.onLine = function(s) print('OLD_LINE:' .. s) end
]]})
    run('run()')
    K.write_outside('main.lua', 'fresh = true\n')
    run('run()')
    assert.is_true(env().fresh)
    SerialPort.dispatcher:push('line', 'hello')
    assert.same({}, SerialPort.dispatcher:pump())
    assert.is_false(said('OLD_LINE:hello'), K.console_text())
  end)

  it('has no published widget from before the run', function()
    reset({['main.lua'] = [[
compy.input.callbacks.on_text_entered = function() run() end
compy.input.show({text = 'OLD_WIDGET'})
]]})
    run('run()')
    assert.is_true(F.is_widget_visible())
    local previous = love.state.user_input_controller
    K.write_outside('main.lua', 'fresh = true\n')
    K.keys('return')
    assert.is_true(env().fresh)
    assert.is_not.equal(previous, love.state.user_input_controller)
    assert.is_false(F.is_widget_visible())
  end)

  it('keeps inspection globals after a top-level error', function()
    reset({['main.lua'] = "x = 42\nerror('first')\n"})
    run('run()')
    assert.equal('ready', K.app_state())
    run("print('READ:' .. x)")
    assert.is_true(said('READ:42'), K.console_text())
  end)

  it('keeps inspection globals after a handler error then stop', function()
    reset({['main.lua'] = [[
x = 42
function love.update() error('later') end
]]})
    run('run()')
    K.cc:suspend()
    assert.equal('inspect', K.app_state())
    run('x = 43')
    K.keys('lctrl', 'q')
    run("print('READ:' .. x)")
    assert.is_true(said('READ:43'), K.console_text())
  end)

  it('refuses run while paused without resetting globals', function()
    reset({['main.lua'] = 'x = 42\nfunction love.update() pause() end\n'})
    run('run()')
    K.cc:suspend()
    assert.equal('inspect', K.app_state())
    run('typed = 7')
    local previous = env()
    run('run()')
    assert.is_true(said('A project is already running'), K.console_text())
    assert.equal(previous, env())
    assert.equal(7, env().typed)
  end)

  --- a run's environment is a new table: a metatable the last
  --- run set on its _G goes with it
  it('drops a metatable the last run set on its environment',
    function()
      reset({['main.lua'] = [[
setmetatable(_G, {
  __newindex = function(t, k, v) rawset(t, k, v) end,
  __index = function() return 'LEAKED' end,
})
]]})
      run('run()')
      K.write_outside('main.lua', 'fresh = true\nprobe = missing\n')
      run('run()')
      assert.is_true(env().fresh, K.console_text())
      assert.is_nil(env().probe)
      assert.is_nil(getmetatable(env()))
    end)

  --- with nothing live there is nothing to end: what a typed
  --- line queued for the board, and an exit hook it set, stay
  it('ends nothing when nothing is live', function()
    reset({['main.lua'] = 'fresh = true\n'})
    local drops, drop = 0, SerialPort.drop
    SerialPort.drop = function(...)
      drops = drops + 1
      return drop(...)
    end
    finally(function() SerialPort.drop = drop end)
    run("compy.before_exit = function() print('TYPED_EXIT') end")
    run('run()')
    assert.is_true(env().fresh)
    assert.equal(0, drops)
    -- the line's own echo names it once; the hook printed nothing
    local n = select(2, K.console_text():gsub('TYPED_EXIT', ''))
    assert.equal(1, n, K.console_text())
  end)

  --- a stopped invocation whose nested run failed to load
  --- installs nothing: Ctrl+Q could not stop what it would
  it('installs nothing for code that stopped its own run',
    function()
      reset({['main.lua'] = [[
writefile("main.lua", "this does not parse (")
stop()
run()
function love.update()
  writefile("ghost.txt", "it ran")
end
]]})
      run('run()')
      for _ = 1, 3 do K.frame() end
      K.keys('lctrl', 'q')
      for _ = 1, 3 do K.frame() end
      assert.is_false(K.cc.run_live)
      -- seen outside any environment: the file it would write
      assert.is_nil(K.file('ghost.txt'))
    end)

  --- a run started from inside a drawing or a handler leaves
  --- the graphics stack to its callers: the draw wrapper's
  --- push('all') and a program's own balanced push both pop
  --- after it (the tenth review round)
  local function counted_stack()
    local depth = 0
    local graphics = { love.graphics, K.cc:get_base_env().gfx,
      K.cc:get_base_env().love.graphics }
    local saved = { }
    for _, g in ipairs(graphics) do
      saved[#saved + 1] = { g, g.push, g.pop, g.getStackDepth }
      g.push = function() depth = depth + 1 end
      g.pop = function()
        if depth == 0 then error('Minimum stack depth reached') end
        depth = depth - 1
      end
      g.getStackDepth = function() return depth end
    end
    finally(function()
      for _, s in ipairs(saved) do
        s[1].push, s[1].pop, s[1].getStackDepth = s[2], s[3], s[4]
      end
    end)
  end

  --- LÖVE's reset counted, on every table the run reaches
  local function counted_reset()
    local resets = { n = 0 }
    local graphics = { love.graphics, K.cc:get_base_env().gfx,
      K.cc:get_base_env().love.graphics }
    local saved = { }
    for _, g in ipairs(graphics) do
      saved[#saved + 1] = { g, g.reset }
      g.reset = function() resets.n = resets.n + 1 end
    end
    finally(function()
      for _, s in ipairs(saved) do s[1].reset = s[2] end
    end)
    return resets
  end

  --- a run that ends for good resets the graphics state the
  --- IDE then draws under; a pause does not, so continue()
  --- resumes with it
  for _, case in ipairs({
    { "Ctrl+Q", function() K.keys('lctrl', 'q') end },
    { "stop()", function() run('stop()') end },
    -- the close itself: close_project() would reopen the
    -- default project from the real directory
    { "a project's close", function() K.cc:_close_project() end },
  }) do
    it('resets graphics when ' .. case[1] .. ' ends a run', function()
      reset({['main.lua'] = 'function love.update() end\n'})
      run('run()')
      local resets = counted_reset()
      case[2]()
      assert.is_true(resets.n >= 1)
      assert.is_false(K.cc.run_live)
    end)
  end

  it('resets graphics when the first lines raise', function()
    reset({['main.lua'] = "error('top')\n"})
    local resets = counted_reset()
    run('run()')
    -- one at the run's start, one as the error ends it
    assert.equal(2, resets.n)
  end)

  it('keeps graphics through a pause and continue()', function()
    reset({['main.lua'] = [[
local n = 0
function love.update()
  n = n + 1
  if n == 1 then pause() end
end
]]})
    run('run()')
    local resets = counted_reset()
    K.frame()
    K.cc:suspend()
    assert.equal('inspect', K.app_state())
    run('continue()')
    assert.equal('running', K.app_state())
    assert.equal(0, resets.n)
    env().love.update = nil
  end)

  --- a scissor kept as LÖVE keeps it: push('all') saves it,
  --- pop puts it back, reset takes it off
  local function stateful_scissor()
    local scissor, stack = nil, { }
    local graphics = { love.graphics, K.cc:get_base_env().gfx,
      K.cc:get_base_env().love.graphics }
    local saved = { }
    for _, g in ipairs(graphics) do
      saved[#saved + 1] = { g, g.setScissor, g.getScissor, g.push,
        g.pop, g.reset, g.getStackDepth }
      g.setScissor = function(x, y, w, h)
        scissor = x and { x, y, w, h } or nil
      end
      g.getScissor = function()
        if scissor then return unpack(scissor) end
      end
      g.push = function() stack[#stack + 1] = scissor end
      g.pop = function()
        assert(#stack > 0, 'Minimum stack depth reached')
        scissor = stack[#stack]
        stack[#stack] = nil
      end
      g.reset = function() scissor = nil end
      g.getStackDepth = function() return #stack end
    end
    finally(function()
      for _, s in ipairs(saved) do
        s[1].setScissor, s[1].getScissor, s[1].push, s[1].pop,
            s[1].reset, s[1].getStackDepth =
            s[2], s[3], s[4], s[5], s[6], s[7]
      end
    end)
    return function() return scissor end
  end

  --- The IDE draws its own things in its own graphics state
  --- (View.draw, and the program's field): a program's
  --- scissor, running or paused, reaches none of the IDE's
  --- pixels, and is the program's again after
  describe("the IDE's own drawing", function()
    it('is in its own state, the program\'s given back', function()
      reset()
      local scissor = stateful_scissor()
      -- the real view module: the fixture stubs it
      local stub, newFont = View, love.graphics.newFont
      love.graphics.newFont = function() return { } end
      local view = assert(loadfile('src/view/view.lua'))
      view()
      local real = View
      View, love.graphics.newFont = stub, newFont
      gfx.setScissor(0, 0, 300, 300)
      local seen = 'not drawn'
      local C = {
        cfg = { view = { font = { } } },
        get_terminal = function() end,
        get_canvas = function() end,
      }
      local CV = { draw = function()
        seen = scissor() == nil and 'clean' or 'clipped'
      end }
      real.draw(C, CV)
      assert.same('clean', seen)
      assert.same({ 0, 0, 300, 300 }, scissor())
    end)

    it('draws a program\'s field in its own state', function()
      reset({['main.lua'] = [[
gfx.setScissor(0, 0, 300, 300)
compy.input.show({ text = 'x' })
function love.draw() end
function love.update() end
]]})
      local scissor = stateful_scissor()
      run('run()')
      K.frame()
      local seen = 'not drawn'
      love.state.user_input_controller.view.draw = function()
        seen = scissor() == nil and 'clean' or 'clipped'
      end
      gfx.setScissor(0, 0, 300, 300)
      love.draw()
      assert.same('clean', seen)
      assert.same({ 0, 0, 300, 300 }, scissor())
      env().love.update = nil
    end)
  end)

  --- the IDE's drawing is its own, but what a typed line or
  --- the next run draws under is the state left after the
  --- draw: a run the draw ended or replaced leaves none, though
  --- the draw's own pop puts back what it saved
  it('leaves no scissor after stop() from love.draw', function()
    reset({['main.lua'] = [[
gfx.setScissor(0, 0, 300, 300)
function love.draw()
  stop()
end
]]})
    local scissor = stateful_scissor()
    run('run()')
    K.frame()
    assert.is_not_nil(scissor())
    love.draw()
    assert.is_false(K.cc.run_live)
    assert.is_nil(scissor())
  end)

  it('starts the run love.draw started with no scissor', function()
    reset({['main.lua'] = [[
gfx.setScissor(0, 0, 300, 300)
function love.draw()
  stop()
  run("menu")
end
]]})
    local scissor = stateful_scissor()
    run('run()')
    K.next_project('menu', {['main.lua'] = 'function love.update() end\n'})
    K.frame()
    love.draw()
    assert.equal('running', K.app_state())
    assert.is_nil(scissor())
    env().love.update = nil
  end)

  it('lets stop() from love.draw unwind the draw', function()
    reset({['main.lua'] = 'function love.draw() stop() end\n'})
    counted_stack()
    run('run()')
    K.frame()
    local ok, err = pcall(love.draw)
    assert.is_true(ok, tostring(err))
    assert.is_false(K.cc.run_live)
  end)

  it('lets a run started from love.draw unwind the draw',
    function()
      reset({['main.lua'] = [[
function love.draw()
  stop()
  run("menu")
end
]]})
      counted_stack()
      run('run()')
      K.next_project('menu', {['main.lua'] = 'function love.update() end\n'})
      K.frame()
      local ok, err = pcall(love.draw)
      assert.is_true(ok, tostring(err))
      env().love.update = nil
    end)

  it('lets a handler pop what it pushed around a run', function()
    reset({['main.lua'] = [[
function love.keypressed(k)
  if k == 'x' then
    gfx.push()
    stop()
    run("menu")
    gfx.pop()
  end
end
]]})
    counted_stack()
    run('run()')
    K.next_project('menu', {['main.lua'] = 'function love.update() end\n'})
    K.keys('x')
    K.frame()
    assert.equal('running', K.app_state())
    env().love.update = nil
  end)

  --- a bundled library the program loaded first is its own:
  --- the next run gets a new copy. (One the IDE had loaded
  --- itself stays shared; the IDE loads hump.timer only in
  --- Harmony.)
  it('does not run a cached library timer from a previous run', function()
    reset({['main.lua'] = [[
local Timer = require('lib.hump.timer')
Timer.after(10, function() print('OLD_TIMER') end)
function love.update(dt) Timer.update(dt) end
]]})
    local was = package.loaded['lib.hump.timer']
    package.loaded['lib.hump.timer'] = nil
    finally(function() package.loaded['lib.hump.timer'] = was end)
    run('run()')
    K.keys('lctrl', 'q')
    K.write_outside('main.lua', [[
local Timer = require('lib.hump.timer')
function love.update(dt) Timer.update(dt) end
]])
    run('run()')
    K.frame(11)
    assert.is_false(said('OLD_TIMER'), K.console_text())
  end)

  it('cleans registrations typed before Ctrl+R when no run is live', function()
    reset({['main.lua'] = 'fresh = true\n'})
    run("compy.input.shortcuts.keypressed.f2 = function() print('OLD_TYPED') end")
    K.keys('lctrl', 'r')
    assert.is_true(env().fresh)
    K.keys('f2')
    assert.is_false(said('OLD_TYPED'), K.console_text())
  end)

  it('keeps project files open across editor run and return', function()
    reset({['main.lua'] = 'x = 42\n'})
    K.open('main.lua')
    local file = K.cc.editor:get_active_buffer()
    assert.is_not_nil(file)
    K.keys('lctrl', 'r')
    assert.equal(42, env().x)
    K.keys('lctrl', 't')
    assert.equal('editor', K.app_state())
    assert.equal(file, K.cc.editor:get_active_buffer())
  end)

  it('keeps the nested new run handlers when the old top-level returns', function()
    reset({['main.lua'] = [[
function love.update() print('OLD_UPDATE') end
writefile('main.lua', "function love.update() print('NEW_UPDATE') end")
stop()
run()
]]})
    run('run()')
    assert.is_false(said('OLD_UPDATE'), K.console_text())
    assert.is_true(said('NEW_UPDATE'), K.console_text())
  end)

  it('clears graphics colour before the next run', function()
    reset({['main.lua'] = [[
gfx.setColor(1, 0, 0, 1)
]]})
    local colour = {1, 1, 1, 1}
    local graphics = {love.graphics, K.cc:get_base_env().gfx,
      K.cc:get_base_env().love.graphics}
    local saved = {}
    for _, g in ipairs(graphics) do
      saved[#saved + 1] = {g, g.setColor, g.getColor, g.reset}
      g.setColor = function(...) colour = {...} end
      g.getColor = function() return unpack(colour) end
      -- LÖVE's reset makes the colour white
      g.reset = function() colour = {1, 1, 1, 1} end
    end
    finally(function()
      for _, s in ipairs(saved) do
        s[1].setColor, s[1].getColor, s[1].reset = s[2], s[3], s[4]
      end
    end)
    run('run()')
    K.keys('lctrl', 'q')
    K.write_outside('main.lua', 'observed_colour = {gfx.getColor()}\n')
    run('run()')
    assert.same({1, 1, 1, 1}, env().observed_colour)
  end)

  it('starts the next run with the console mouse modes', function()
    reset({['main.lua'] = [[
love.mouse.setRelativeMode(true)
love.mouse.setGrabbed(true)
love.mouse.setVisible(false)
love.mouse.setCursor('custom')
function love.mousereleased() end
]]})
    run('run()')
    K.write_outside('main.lua', [[
observed_mouse = {
  love.mouse.getRelativeMode(), love.mouse.isGrabbed(),
  love.mouse.isVisible(), love.mouse.getCursor()
}
]])
    run('run()')
    assert.same({false, false, true}, env().observed_mouse)
  end)

  it('clears graphics scissor before the next run', function()
    reset({['main.lua'] = 'gfx.setScissor(0, 0, 1, 1)\n'})
    local scissor = {}
    local graphics = {love.graphics, K.cc:get_base_env().gfx,
      K.cc:get_base_env().love.graphics}
    local saved = {}
    for _, g in ipairs(graphics) do
      saved[#saved + 1] = {g, g.setScissor, g.getScissor, g.reset}
      g.setScissor = function(...) scissor = {...} end
      g.getScissor = function() return unpack(scissor) end
      -- LÖVE's reset takes the scissor off
      g.reset = function() scissor = {} end
    end
    finally(function()
      for _, s in ipairs(saved) do
        s[1].setScissor, s[1].getScissor, s[1].reset = s[2], s[3], s[4]
      end
    end)
    run('run()')
    K.keys('lctrl', 'q')
    K.write_outside('main.lua', 'observed_scissor = {gfx.getScissor()}\n')
    run('run()')
    assert.same({}, env().observed_scissor)
  end)

  --- a program reaches its environment as _G (the tixy
  --- example compiles its formulas there)
  it('leaves _G naming the environment the run is in', function()
    reset({['main.lua'] = "_G.flag = 7\nseen = flag\n"})
    run('run()')
    run('run()')
    assert.equal(env(), env()._G)
    assert.equal(7, env().seen)
  end)

  it('restarts the same mouse counter at zero after a stop too',
    function()
      reset({['main.lua'] = [[
clicks = 0
function love.mousepressed()
  clicks = clicks + 1
  print('CLICKS:' .. clicks)
end
]]})
      run('run()')
      F.session.mousepressed(10, 10, 1, false, 1)
      F.session.mousereleased(10, 10, 1, false, 1)
      K.keys('lctrl', 'q')
      run('run()')
      F.session.mousepressed(10, 10, 1, false, 1)
      F.session.mousereleased(10, 10, 1, false, 1)
      assert.equal(1, env().clicks, K.console_text())
    end)

  it('restarts the same mouse counter at zero', function()
    reset({['main.lua'] = [[
clicks = 0
function love.mousepressed()
  clicks = clicks + 1
  print('CLICKS:' .. clicks)
end
]]})
    run('run()')
    F.session.mousepressed(10, 10, 1, false, 1)
    F.session.mousereleased(10, 10, 1, false, 1)
    assert.equal(1, env().clicks)
    run('run()')
    assert.equal(0, env().clicks)
    F.session.mousepressed(10, 10, 1, false, 1)
    F.session.mousereleased(10, 10, 1, false, 1)
    assert.equal(1, env().clicks, K.console_text())
  end)

  --- one stop, one reset, one module clear for each way in
  it('makes the environment once and clears modules once', function()
    reset({['main.lua'] = 'x = 42\n'})
    local cc = K.cc
    local reset_env, evacuate = cc._reset_executor_env, cc.evacuate_required
    local resets, clears = 0, 0
    cc._reset_executor_env = function(self)
      resets = resets + 1
      return reset_env(self)
    end
    cc.evacuate_required = function(self)
      clears = clears + 1
      return evacuate(self)
    end
    finally(function()
      cc._reset_executor_env, cc.evacuate_required = reset_env, evacuate
    end)
    run('run()')
    assert.same({1, 1}, {resets, clears})
    resets, clears = 0, 0
    K.keys('lctrl', 'r')
    assert.same({1, 1}, {resets, clears})
    resets, clears = 0, 0
    K.next_project('other', {['main.lua'] = 'x = 43\n'})
    run("run('other')")
    assert.same({1, 1}, {resets, clears})
  end)

  it('keeps typed writes during a run and after stopping it', function()
    reset({['main.lua'] = 'x = 42\nfunction love.update() end\n'})
    run('run()')
    local previous = env()
    run('y = 43')
    assert.equal(previous, env())
    assert.equal(43, env().y)
    K.keys('lctrl', 'q')
    assert.equal(previous, env())
    run("print('READ:' .. x .. ':' .. y)")
    assert.is_true(said('READ:42:43'), K.console_text())
  end)

  it('keeps globals after a pause and stop', function()
    reset({['main.lua'] = 'x = 42\nfunction love.update() pause() end\n'})
    run('run()')
    K.cc:suspend()
    assert.equal('inspect', K.app_state())
    local previous = env()
    K.keys('lctrl', 'q')
    assert.equal(previous, env())
    run("print('READ:' .. x)")
    assert.is_true(said('READ:42'), K.console_text())
  end)
end)
