-- A program may capture the mouse: relative mode (pointer
-- capture on Android, where the pointer hides and moves a
-- cursor nobody sees), a grab, a hidden or custom cursor. That
-- is device state, so it outlives the program unless the IDE
-- puts it back. Whatever ends the run, the console gets the
-- mouse it needs, without the program's help; a paused program
-- gets its own back on continue().
--
-- Spec justification (dev testing policy): the stop paths are
-- a critical dispatch seam, many callers funnelling into one
-- teardown, and a path that skips it fails on a device only,
-- as a pointer that clicks somewhere else.

local F = require('tests.helpers.input_fixture')

--- What paint does when it starts
local function capture()
  love.mouse.setRelativeMode(true)
  love.mouse.setGrabbed(true)
  love.mouse.setVisible(false)
  love.mouse.setCursor('crosshair')
end

--- @return table
local function mouse()
  return {
    relative = love.mouse.getRelativeMode(),
    grabbed = love.mouse.isGrabbed(),
    visible = love.mouse.isVisible(),
    cursor = love.mouse.getCursor(),
  }
end

local CONSOLE = { relative = false, grabbed = false,
  visible = true }
local CAPTURED = { relative = true, grabbed = true,
  visible = false, cursor = 'crosshair' }

--- A running program that has captured the mouse
local function run_capturing()
  F.activate_project({ update = function() end })
  capture()
  assert.same(CAPTURED, mouse())
end

--- @param keys string[] pressed in order, then all let go
local function press(keys)
  for _, k in ipairs(keys) do F.session.press(k) end
  for i = #keys, 1, -1 do F.session.release(keys[i]) end
end

--- A project on disk, as far as run_project asks: its top-level
--- code is `fn`, left in place for restart() to run again.
--- @param fn function
--- @return function undo
local function project(fn)
  local P = F.cc.model.projects
  local cur, run = P.current, P.run
  P.current = { name = 'p', required = { } }
  P.run = function()
    return fn, nil, '/tmp/p'
  end
  return function() P.current, P.run = cur, run end
end

describe('a program\'s mouse after it stops #input', function()
  setup(function() F.setup() end)
  teardown(function() F.teardown() end)
  before_each(function() F.reset() end)

  it('Ctrl+Q gives the console its mouse', function()
    run_capturing()
    press({ 'lctrl', 'q' })
    assert.same(CONSOLE, mouse())
  end)

  it('Ctrl+S gives the console its mouse', function()
    run_capturing()
    press({ 'lctrl', 's' })
    assert.equal('ready', love.state.app_state)
    assert.same(CONSOLE, mouse())
  end)

  it('Ctrl+T gives the editor the mouse', function()
    run_capturing()
    press({ 'lctrl', 't' })
    assert.are_not.equal('running', love.state.app_state)
    assert.same(CONSOLE, mouse())
  end)

  -- love.event.quit() from the program reaches love.quit, as
  -- LÖVE delivers the quit event it pushes
  it('the program\'s own quit gives the console its mouse',
    function()
      run_capturing()
      assert.is_true(love.quit())
      assert.equal('ready', love.state.app_state)
      assert.same(CONSOLE, mouse())
    end)

  it('the program\'s stop() gives the console its mouse',
    function()
      run_capturing()
      F.cc:get_project_env().stop()
      assert.same(CONSOLE, mouse())
    end)

  -- open_project closes the current project before it opens
  -- the next; the next one here fails to open, which leaves the
  -- close under test and nothing else.
  it('switching projects closes the running one onto the'
    .. ' console\'s mouse', function()
      local undo = project(function() end)
      run_capturing()
      local P = F.cc.model.projects
      local opreate, close = P.opreate, P.close
      P.opreate = function() return false, false, 'no q' end
      P.close = function() P.current = nil return true end
      F.cc:open_project('q')
      P.opreate, P.close = opreate, close
      undo()
      assert.same(CONSOLE, mouse())
    end)

  it('an error in top-level code gives the console its mouse',
    function()
      F.run_project(function()
        capture()
        error('boom')
      end)
      assert.equal('ready', love.state.app_state)
      assert.same(CONSOLE, mouse())
    end)

  it('a program that ends with nothing live gives the console'
    .. ' its mouse', function()
      F.run_project(capture)
      assert.equal('ready', love.state.app_state)
      assert.same(CONSOLE, mouse())
    end)

  -- Idle, not ended: its pointer handler still answers, so the
  -- mouse stays as it set it until it stops.
  it('a program that ends its code with a pointer handler'
    .. ' keeps its mouse', function()
      F.run_project(function()
        capture()
        F.cc:get_project_env().love.mousepressed = function() end
      end)
      assert.equal('ready', love.state.app_state)
      assert.same(CAPTURED, mouse())
      press({ 'lctrl', 'q' })
      assert.same(CONSOLE, mouse())
    end)

  it('an error in a handler pauses the program with the'
    .. ' console\'s mouse; continue() gives it its own back',
    function()
      F.activate_project({
        update = function() error('boom') end,
      })
      capture()
      F.love_update(0.1)
      F.cc:suspend()
      assert.equal('inspect', love.state.app_state)
      assert.same(CONSOLE, mouse())
      F.cc:get_project_env().continue()
      assert.equal('running', love.state.app_state)
      assert.same(CAPTURED, mouse())
    end)

  -- setCursor raises on a cursor the program released after
  -- setting it, as LÖVE does
  it('continue() gives the program its handlers back even when'
    .. ' its mouse cannot be restored', function()
      local released = { }
      local set_cursor = love.mouse.setCursor
      local updates = 0
      F.activate_project({
        update = function()
          updates = updates + 1
          if updates == 1 then error('boom') end
        end,
      })
      capture()
      love.mouse.setCursor(released)
      F.love_update(0.1)
      F.cc:suspend()
      love.mouse.setCursor = function(c)
        if c == released then
          error('Cannot use object after it has been released.')
        end
        set_cursor(c)
      end
      local ok = pcall(F.cc:get_project_env().continue)
      love.mouse.setCursor = set_cursor
      assert.is_false(ok)
      assert.equal('running', love.state.app_state)
      F.love_update(0.1)
      assert.equal(2, updates)
    end)

  -- evacuate_required runs ahead of the reset in the stop
  it('a stop that raises before the reset still gives the'
    .. ' console its mouse', function()
      run_capturing()
      F.cc.evacuate_required = function() error('broken') end
      local ok = pcall(F.cc.stop_project_run, F.cc)
      F.cc.evacuate_required = nil
      assert.is_false(ok)
      assert.same(CONSOLE, mouse())
    end)

  it('Ctrl+Alt+R starts the program again on the console\'s'
    .. ' mouse', function()
      local seen
      local undo = project(function() seen = mouse() end)
      run_capturing()
      press({ 'lctrl', 'lalt', 'r' })
      undo()
      assert.same(CONSOLE, seen)
    end)

  -- A path that ended a run without the teardown, or a mouse
  -- changed with nothing running: the next run still starts
  -- from the console's mouse.
  it('run() starts a program on the console\'s mouse',
    function()
      capture()
      local seen
      F.run_project(function() seen = mouse() end)
      assert.same(CONSOLE, seen)
    end)
end)
