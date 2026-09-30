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

local gfx

-- Two pixels: one inside any scissor, one outside it. Each
-- holds the tag of what drew it. Drawing lands where the render
-- target says: the canvas, or the screen, which is not watched.
local canvas, pixels, drawing, scissor, mask, target

--- A canvas that remembers what is drawn on it
local function fake_canvas()
  local c = {}
  function c.renderTo(_, f)
    local prev = target
    target, drawing = c, true
    f()
    target, drawing = prev, false
  end
  return c
end

--- @return boolean anything is drawn on the canvas
local function shown()
  return (pixels.inside or pixels.outside) and true or false
end

--- @return string? tag of what is drawn outside any scissor
local function who() return pixels.outside end

--- What a program does in a handler or at its top level: it
--- lands on whatever is bound
--- @param tag string?
local function draw(tag)
  if target == canvas then
    pixels.inside, pixels.outside = tag or 'p', tag or 'p'
  end
end

--- What was on the canvas before the case began
--- @param tag string?
local function paint(tag)
  pixels.inside, pixels.outside = tag or 'p', tag or 'p'
end

--- What a program leaves in the graphics state
local function restrict()
  scissor = true
  mask = { false, false, false, false }
end

--- A running program that has drawn
local function run_drawing()
  F.activate_project({ update = function() end })
  paint()
  assert.is_true(shown())
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
  local saved = {}
  local names = { 'setCanvas', 'clear', 'getScissor', 'setScissor',
    'getColorMask', 'setColorMask' }
  local o_canvas
  setup(function()
    F.setup()
    gfx = love.graphics
    o_canvas = F.cc.model.output.canvas
    for _, n in ipairs(names) do saved[n] = gfx[n] end
  end)
  teardown(function()
    F.cc.model.output.canvas = o_canvas
    for _, n in ipairs(names) do gfx[n] = saved[n] end
    F.teardown()
  end)
  before_each(function()
    F.reset()
    canvas = fake_canvas()
    pixels = { inside = false, outside = false }
    scissor, mask, target = false, { true, true, true, true }, nil
    gfx.setCanvas = function(t)
      target = t and (t[1] or t) or nil
    end
    F.cc.model.output.canvas = canvas
    gfx.getScissor = function()
      if scissor then return 0, 0, 1, 1 end
    end
    gfx.setScissor = function(x) scissor = x ~= nil end
    gfx.getColorMask = function() return unpack(mask) end
    gfx.setColorMask = function(...) mask = { ... } end
    -- as LÖVE clears: the scissor spares what is outside it, a
    -- color mask spares what it does not write
    gfx.clear = function()
      if not drawing then return end
      if mask[1] and mask[2] and mask[3] and mask[4] then
        pixels.inside = false
        if not scissor then pixels.outside = false end
      end
    end
  end)

  it('Ctrl+S clears it', function()
    run_drawing()
    press({ 'lctrl', 's' })
    assert.equal('ready', love.state.app_state)
    assert.is_false(shown())
  end)

  it('Ctrl+T clears it', function()
    run_drawing()
    press({ 'lctrl', 't' })
    assert.are_not.equal('running', love.state.app_state)
    assert.is_false(shown())
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
    local ok, err = pcall(function()
      run_drawing()
      press({ 'lctrl', 'q' })
    end)
    P.close = close
    F.cc.open_project = open_project
    undo()
    assert(ok, err)
    assert.is_false(shown())
  end)

  it('the program\'s stop() clears it', function()
    run_drawing()
    F.cc:get_project_env().stop()
    assert.is_false(shown())
  end)

  it('the program\'s own quit clears it', function()
    run_drawing()
    assert.is_true(love.quit())
    assert.equal('ready', love.state.app_state)
    assert.is_false(shown())
  end)

  it('Ctrl+Alt+R starts the program again on a blank canvas',
    function()
      local seen
      local undo = project(function() seen = shown() end)
      local ok, err = pcall(function()
        run_drawing()
        press({ 'lctrl', 'lalt', 'r' })
      end)
      undo()
      assert(ok, err)
      assert.is_false(seen)
    end)

  it('a run starts on a blank canvas', function()
    paint()
    local seen
    F.run_project(function() seen = shown() end)
    assert.is_false(seen)
  end)

  it('an error in top-level code clears what it drew', function()
    F.run_project(function()
      draw()
      error('boom')
    end)
    assert.equal('ready', love.state.app_state)
    assert.is_false(shown())
  end)

  it('a project that fails to load leaves no picture under'
    .. ' its error', function()
      paint()
      local P = F.cc.model.projects
      local cur, run = P.current, P.run
      P.current = { name = 'p', required = { } }
      P.run = function() return nil, 'syntax error' end
      local ok, err = pcall(F.cc.run_project, F.cc, 'p')
      P.current, P.run = cur, run
      assert(ok, err)
      assert.is_false(shown())
    end)

  it('what a before_exit hook draws is cleared too', function()
    run_drawing()
    F.cc:get_project_env().compy.before_exit = paint
    press({ 'lctrl', 's' })
    assert.is_false(shown())
  end)

  describe('whatever graphics state the program left', function()
    it('a scissor does not spare part of it on a stop',
      function()
        run_drawing()
        F.cc:get_project_env().compy.before_exit = restrict
        press({ 'lctrl', 's' })
        assert.is_false(shown())
      end)

    it('a scissor does not spare part of it after a top-level'
      .. ' error', function()
        F.run_project(function()
          draw()
          restrict()
          error('boom')
        end)
        assert.is_false(shown())
      end)

    it('a color mask does not keep the old picture into the'
      .. ' next run', function()
        paint()
        restrict()
        local seen
        F.run_project(function() seen = shown() end)
        assert.is_false(seen)
      end)

    it('the program\'s own scissor and mask come back', function()
      paint()
      restrict()
      F.cc.model.output:clear_canvas()
      assert.is_false(shown())
      assert.is_true(scissor)
      assert.same({ false, false, false, false }, mask)
    end)
  end)

  describe('a handler that goes on drawing after its stop', function()
    it('leaves no picture', function()
      F.activate_project({
        update = function()
          F.cc:get_project_env().stop()
          draw()
        end,
      })
      F.love_update(0.1)
      assert.equal('ready', love.state.app_state)
      assert.is_false(shown())
    end)

    it('does not clear the run it restarted', function()
      local undo = project(function() draw('new') end)
      F.activate_project({
        update = function() F.cc:restart() end,
      })
      F.love_update(0.1)
      undo()
      assert.equal('new', who())
    end)

    it('clears a restart whose top-level code fails', function()
      local undo = project(function()
        draw('new')
        error('boom')
      end)
      F.activate_project({
        update = function() F.cc:restart() end,
      })
      F.love_update(0.1)
      undo()
      assert.equal('ready', love.state.app_state)
      assert.is_false(shown())
    end)

    it('leaves the console\'s own drawing working', function()
      F.activate_project({
        update = function() F.cc:get_project_env().stop() end,
      })
      F.love_update(0.1)
      F.cc:use_canvas(draw, true)
      assert.is_true(shown())
    end)
  end)

  -- One console line that stops and then draws: the console
  -- owns no run, so its drawing after the stop stays.
  it('a console line that stops and then draws keeps what it'
    .. ' drew', function()
      paint('old')
      F.cc:get_project_env().mark = function() draw('typed') end
      F.session.type('stop() mark()')
      press({ 'return' })
      assert.equal('typed', who())
    end)

  it('console code run over a live program keeps what it draws'
    .. ' after a stop', function()
      run_drawing()
      F.cc:use_canvas(function()
        F.cc:get_project_env().stop()
        draw('typed')
      end, true)
      assert.equal('typed', who())
    end)

  -- Top-level code that stops its run, starts it again, and
  -- then fails: the failed call is the old run's, the canvas
  -- the new one's.
  it('a top-level error after a rerun leaves the rerun\'s'
    .. ' picture', function()
      local calls = 0
      local undo = project(function()
        calls = calls + 1
        if calls == 1 then
          F.cc:get_project_env().stop()
          F.cc:run_project()
          error('outgoing')
        else
          draw('new')
        end
      end)
      local ok, err = pcall(F.cc.run_project, F.cc)
      undo()
      assert(ok, err)
      assert.equal(2, calls)
      assert.equal('new', who())
    end)

  it('a paused program keeps it, and continue() gives it its'
    .. ' handlers back', function()
      local updates = 0
      F.activate_project({
        update = function()
          updates = updates + 1
          if updates == 1 then error('boom') end
          draw('resumed')
        end,
      })
      paint('before')
      F.love_update(0.1)
      F.cc:suspend()
      assert.equal('inspect', love.state.app_state)
      assert.equal('before', who())
      F.cc:get_project_env().continue()
      assert.equal('running', love.state.app_state)
      assert.equal('before', who())
      F.love_update(0.1)
      assert.equal(2, updates)
      assert.equal('resumed', who())
    end)

  -- Finished its top-level code with nothing live: idle, not
  -- stopped, as the sine example is.
  it('a run that finishes with nothing live keeps it', function()
    F.run_project(draw)
    assert.equal('ready', love.state.app_state)
    assert.is_true(shown())
  end)

  -- Ready with a handler live: Ctrl+S stops a running program
  -- only, so this one keeps its picture until it stops.
  it('a run in ready with a live handler keeps it through'
    .. ' Ctrl+S', function()
      F.run_project(function()
        draw()
        F.cc:get_project_env().love.mousepressed = function() end
      end)
      assert.equal('ready', love.state.app_state)
      press({ 'lctrl', 's' })
      assert.is_true(shown())
      F.cc:get_project_env().stop()
      assert.is_false(shown())
    end)
end)
