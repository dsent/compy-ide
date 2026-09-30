-- A program draws on the console's canvas, and the canvas is
-- drawn over the console every frame. When the run ends, what
-- it drew goes with it, or a stopped program's picture stays
-- over the console and its history. A paused program has not
-- ended: its picture stays until it stops.
--
-- Spec justification (dev testing policy): the stop paths are
-- a critical dispatch seam, many callers funnelling into one
-- teardown, and a path that skips it fails on a device only,
-- as a picture left over the console.

local F = require('tests.helpers.input_fixture')

local canvas, drawing, clear

--- A canvas that remembers whether anything is drawn on it
local function fake_canvas()
  local c = { picture = false }
  function c.renderTo(_, f)
    drawing = true
    f()
    drawing = false
  end
  return c
end

--- What a program does in a handler or at its top level
local function draw() canvas.picture = true end

--- A running program that has drawn
local function run_drawing()
  F.activate_project({ update = function() end })
  draw()
  assert.is_true(canvas.picture)
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

describe('a program\'s canvas after it stops #canvas', function()
  local o_model, o_clear
  setup(function()
    F.setup()
    o_model = F.cc.model.output.canvas
    o_clear = love.graphics.clear
  end)
  teardown(function()
    F.cc.model.output.canvas = o_model
    love.graphics.clear = o_clear
    F.teardown()
  end)
  before_each(function()
    F.reset()
    canvas = fake_canvas()
    F.cc.model.output.canvas = canvas
    love.graphics.clear = function()
      if drawing then canvas.picture = false end
    end
  end)

  it('Ctrl+S clears it', function()
    run_drawing()
    press({ 'lctrl', 's' })
    assert.equal('ready', love.state.app_state)
    assert.is_false(canvas.picture)
  end)

  it('Ctrl+T clears it', function()
    run_drawing()
    press({ 'lctrl', 't' })
    assert.are_not.equal('running', love.state.app_state)
    assert.is_false(canvas.picture)
  end)

  -- Ctrl+Q closes the open project, then opens the default
  -- one; the fixture has none open, so one is set here, with
  -- the close and the open stood in for.
  it('Ctrl+Q clears it', function()
    local undo = project(function() end)
    local P = F.cc.model.projects
    local close = P.close
    local open_project = F.cc.open_project
    P.close = function() P.current = nil return true end
    F.cc.open_project = function() return true end
    run_drawing()
    press({ 'lctrl', 'q' })
    P.close = close
    F.cc.open_project = open_project
    undo()
    assert.is_false(canvas.picture)
  end)

  it('the program\'s stop() clears it', function()
    run_drawing()
    F.cc:get_project_env().stop()
    assert.is_false(canvas.picture)
  end)

  it('the program\'s own quit clears it', function()
    run_drawing()
    assert.is_true(love.quit())
    assert.equal('ready', love.state.app_state)
    assert.is_false(canvas.picture)
  end)

  it('Ctrl+Alt+R starts the program again on a blank canvas',
    function()
      local seen
      local undo = project(function() seen = canvas.picture end)
      run_drawing()
      press({ 'lctrl', 'lalt', 'r' })
      undo()
      assert.is_false(seen)
    end)

  it('a run starts on a blank canvas', function()
    draw()
    local seen
    F.run_project(function() seen = canvas.picture end)
    assert.is_false(seen)
  end)

  it('an error in top-level code clears what it drew', function()
    F.run_project(function()
      draw()
      error('boom')
    end)
    assert.equal('ready', love.state.app_state)
    assert.is_false(canvas.picture)
  end)

  it('what a before_exit hook draws is cleared too', function()
    run_drawing()
    F.cc:get_project_env().compy.before_exit = draw
    press({ 'lctrl', 's' })
    assert.is_false(canvas.picture)
  end)

  it('a paused program keeps it, and continue() draws on it',
    function()
      F.activate_project({
        update = function() error('boom') end,
      })
      draw()
      F.love_update(0.1)
      F.cc:suspend()
      assert.equal('inspect', love.state.app_state)
      assert.is_true(canvas.picture)
      canvas.picture = false
      F.cc:get_project_env().continue()
      assert.equal('running', love.state.app_state)
      F.cc:use_canvas(draw)
      assert.is_true(canvas.picture)
    end)
end)
