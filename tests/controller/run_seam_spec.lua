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
    local previous = env()
    run('run()')
    assert.equal(previous, env())
    assert.equal(42, env().x)
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

  it('makes the remainder of a console line see the run globals', function()
    reset({['main.lua'] = 'x = 42\n'})
    run("run(); print('NEW_X:' .. tostring(x))")
    assert.equal(42, env().x)
    assert.is_true(said('NEW_X:42'), K.console_text())
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
      saved[#saved + 1] = {g, g.setColor, g.getColor}
      g.setColor = function(...) colour = {...} end
      g.getColor = function() return unpack(colour) end
    end
    finally(function()
      for _, s in ipairs(saved) do s[1].setColor, s[1].getColor = s[2], s[3] end
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
      saved[#saved + 1] = {g, g.setScissor, g.getScissor}
      g.setScissor = function(...) scissor = {...} end
      g.getScissor = function() return unpack(scissor) end
    end
    finally(function()
      for _, s in ipairs(saved) do s[1].setScissor, s[1].getScissor = s[2], s[3] end
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
