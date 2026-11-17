-- A program draws on its canvas, a record kept apart from the
-- console's text and shown in a screen mode that shows it
-- (spec: screen_modes_spec.lua). The canvas survives a stop, as
-- the console's output does: a stopped program's picture is
-- there to look at. A run's start, Ctrl+R and reset() clear it
-- (the maintainer's ruling "The picture and the text: the shape
-- is approved", built as if accepted on November 17, 2026). A
-- program's love.draw draws on it, each frame on a cleared
-- canvas, as LÖVE clears the screen before love.draw.
--
-- Spec justification (dev testing policy): the run, stop and
-- reset paths are a critical dispatch seam, many callers
-- funnelling into one teardown, and a path that clears or keeps
-- the wrong way fails on a device only, as a picture lost or
-- one carried into the next run.

local F = require('tests.helpers.input_fixture')

local gfx

-- Two pixels: one inside any scissor, one outside it. Each
-- holds the tag of what drew it. Drawing lands where the render
-- target says: the canvas, or the screen, which is not watched.
local canvas, pixels, drawing, scissor, mask, target
--- what the program's canvas was last cleared to
local cleared

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
  local names = { 'setCanvas', 'getCanvas', 'clear', 'getScissor',
    'setScissor', 'getColorMask', 'setColorMask', 'push', 'pop',
    'getStackDepth', 'setBlendMode', 'getBackgroundColor',
    'setBackgroundColor', 'reset' }
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
    gfx.getCanvas = function() return target end
    -- push('all') keeps the render target, and pop puts it back,
    -- as LÖVE's do
    -- push('all') keeps the render target and the background
    -- colour, and pop puts them back
    local stack = { }
    local bg = { 0, 0, 0, 1 }
    gfx.push = function()
      stack[#stack + 1] = { target, bg }
    end
    gfx.pop = function()
      assert(#stack > 0, 'Minimum stack depth reached')
      target, bg = stack[#stack][1], stack[#stack][2]
      stack[#stack] = nil
    end
    gfx.getStackDepth = function() return #stack end
    -- LÖVE's reset makes no canvas active, and the ground black
    gfx.reset = function()
      target = nil
      bg = { 0, 0, 0, 1 }
    end
    gfx.getBackgroundColor = function() return unpack(bg) end
    gfx.setBackgroundColor = function(r, g, b, a)
      bg = { r, g, b, a or 1 }
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
    gfx.clear = function(...)
      if target == canvas then cleared = { ... } end
      if not (drawing or target == canvas) then return end
      if mask[1] and mask[2] and mask[3] and mask[4] then
        pixels.inside = false
        if not scissor then pixels.outside = false end
      end
    end
  end)

  -- no reserved key since 2026-11-14: the program runs on
  it('Ctrl+S leaves it', function()
    run_drawing()
    press({ 'lctrl', 's' })
    assert.equal('running', love.state.app_state)
    assert.is_true(shown())
  end)

  it('Ctrl+T keeps it', function()
    run_drawing()
    press({ 'lctrl', 't' })
    assert.are_not.equal('running', love.state.app_state)
    assert.is_true(shown())
  end)

  -- Ctrl+Q stops the program and keeps its project open; the
  -- fixture has none open, so one is set here, and a close
  -- would show.
  it('Ctrl+Q keeps it, the project still open', function()
    local undo = project(function() end)
    local P = F.cc.model.projects
    local open = P.current
    local close = P.close
    local closed = false
    P.close = function() closed = true return true end
    local ok, err = pcall(function()
      run_drawing()
      press({ 'lctrl', 'q' })
    end)
    local still_open = P.current == open
    P.close = close
    undo()
    assert(ok, err)
    assert.equal('ready', love.state.app_state)
    assert.is_true(shown())
    assert.is_false(closed)
    assert.is_true(still_open)
  end)

  it('the program\'s stop() keeps it', function()
    run_drawing()
    F.cc:get_project_env().stop()
    assert.is_true(shown())
  end)

  it('the program\'s own quit keeps it', function()
    run_drawing()
    assert.is_true(love.quit())
    assert.equal('ready', love.state.app_state)
    assert.is_true(shown())
  end)

  it('reset() clears it', function()
    run_drawing()
    F.cc:reset()
    assert.is_false(shown())
  end)

  it('reset() clears it with nothing run', function()
    paint()
    F.cc:reset()
    assert.is_false(shown())
  end)

  it('Ctrl+R starts the program again on a blank canvas',
    function()
      local seen
      local undo = project(function() seen = shown() end)
      local ok, err = pcall(function()
        run_drawing()
        press({ 'lctrl', 'r' })
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

  it('an error in top-level code keeps what it drew', function()
    F.run_project(function()
      draw()
      error('boom')
    end)
    assert.equal('ready', love.state.app_state)
    assert.is_true(shown())
    assert.is_false(F.cc.run_live)
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

  it('what a before_exit hook draws stays too', function()
    run_drawing()
    F.cc:get_project_env().compy.before_exit = function()
      draw('exit')
    end
    press({ 'lctrl', 'q' })
    assert.equal('exit', who())
  end)

  describe('whatever graphics state the program left', function()
    it('a scissor does not spare part of it at reset()',
      function()
        run_drawing()
        F.cc:get_project_env().compy.before_exit = restrict
        F.cc:reset()
        assert.is_false(shown())
      end)

    it('a scissor does not spare part of it at the next run',
      function()
        F.run_project(function()
          draw()
          restrict()
          error('boom')
        end)
        local seen
        F.run_project(function() seen = shown() end)
        assert.is_false(seen)
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

  describe('a handler that would go on drawing after its stop',
    function()
    it('draws nothing after it', function()
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

    --- The outgoing handler's stop ends it (design B): nothing
    --- after it runs, whatever the run it started does.
    for name, top in pairs({
      ['stops'] = function() F.cc:get_project_env().stop() end,
      ['fails'] = function() error('boom') end,
    }) do
      it('draws nothing when the run it started ' .. name,
        function()
          local undo = project(top)
          F.activate_project({
            update = function()
              F.cc:get_project_env().stop()
              F.cc:run_project()
              canvas:renderTo(function() draw('late') end)
            end,
          })
          F.love_update(0.1)
          undo()
          assert.is_false(shown())
        end)
    end

    it('applies to a run the real run path started', function()
      F.run_project(function()
        F.cc:get_project_env().love.update = function()
          F.cc:get_project_env().stop()
          draw('late')
        end
      end)
      F.love_update(0.1)
      -- the project env outlives the case
      F.cc:get_project_env().love.update = nil
      assert.is_false(shown())
    end)

    it('keeps what a restart whose top-level code fails drew',
      function()
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
      assert.equal('new', who())
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

  -- One console line that stops and then would draw: the stop
  -- ends the line (design B), so nothing after it draws, and
  -- the picture is the program's as it left it.
  --- The line is submitted with Enter, which runs inside the
  --- program's own call while a run exists, idle or not.
  local function submit_stop_and_draw()
    F.cc:get_project_env().mark = function() draw('typed') end
    F.session.type('stop() mark()')
    press({ 'return' })
  end

  it('a console line whose stop is refused, nothing running,'
    .. ' draws on', function()
      paint('old')
      submit_stop_and_draw()
      assert.equal('typed', who())
    end)

  it('the same line after a run that finished: the stop keeps'
    .. ' its picture, and nothing after it draws', function()
      F.run_project(function() draw('prog') end)
      assert.equal('prog', who())
      submit_stop_and_draw()
      assert.equal('prog', who())
    end)

  -- Enter reaches the program's input hook, which here stops the
  -- run: the key is the stop's (design B). Typed while the
  -- program ran, the line went nowhere, the program owning the
  -- keyboard (November 16); typed after the stop, it runs.
  it('a key whose input hook stopped the run is the stop\'s; the'
    .. ' console takes typing after it', function()
      F.run_project(function()
        local env = F.cc:get_project_env()
        draw('prog')
        env.love.update = function() end
        env.compy.input.hooks.keypressed = function(k)
          if k == 'return' then env.stop() end
          return false
        end
      end)
      local env = F.cc:get_project_env()
      -- the stop on Enter makes the environment anew from the
      -- base (the terminate flush): the line's helper is there
      local base = F.cc:get_base_env()
      base.mark = function() draw('typed') end
      finally(function() base.mark = nil end)
      F.session.type('mark()')
      assert.same({ '' }, F.console:get_text())
      press({ 'return' })
      env.love.update = nil
      env.compy.input.hooks.keypressed = nil
      assert.equal('ready', love.state.app_state)
      assert.equal('prog', who())
      F.session.type('mark()')
      press({ 'return' })
      assert.equal('typed', who())
    end)

  --- turned around on November 17: a program that can act owns
  --- the input, so the line reaches no console; the program runs
  --- on with its picture
  it('the same line over a program with an update reaches nothing',
    function()
      F.run_project(function()
        draw('prog')
        F.cc:get_project_env().love.update = function() end
      end)
      assert.equal('running', love.state.app_state)
      submit_stop_and_draw()
      assert.equal('running', love.state.app_state)
      assert.equal('prog', who())
      F.cc:get_project_env().love.update = nil
    end)

  it('the same line over a run with a pointer handler reaches'
    .. ' nothing', function()
      F.run_project(function()
        draw('prog')
        F.cc:get_project_env().love.mousepressed = function() end
      end)
      submit_stop_and_draw()
      assert.is_true(F.cc.run_live)
      assert.equal('prog', who())
      F.cc:get_project_env().love.mousepressed = nil
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

  -- Top-level code that stops its run and would then fail: the
  -- stop ends it (design B), so no error comes, and what it drew
  -- before the stop stays.
  it('top-level code that stops draws and fails no more', function()
      local undo = project(function()
        draw('old')
        F.cc:get_project_env().stop()
        draw('after')
        error('outgoing')
      end)
      local ok, err = pcall(F.cc.run_project, F.cc)
      undo()
      assert(ok, err)
      assert.equal('ready', love.state.app_state)
      assert.equal('old', who())
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

  -- Ready with a handler live: the program idles behind the
  -- console, not stopped. Ctrl+S is no reserved key, so its
  -- picture stays; Ctrl+Q stops it, and the picture stays.
  it('a run in ready with a live handler keeps it through'
    .. ' Ctrl+S and Ctrl+Q', function()
      F.run_project(function()
        draw()
        F.cc:get_project_env().love.mousepressed = function() end
      end)
      assert.equal('ready', love.state.app_state)
      press({ 'lctrl', 's' })
      assert.is_true(shown())
      press({ 'lctrl', 'q' })
      assert.equal('ready', love.state.app_state)
      assert.is_true(shown())
    end)

  it('a run that finished with nothing live keeps its picture'
    .. ' until reset()', function()
      F.run_project(draw)
      assert.is_true(shown())
      press({ 'lctrl', 'q' })
      assert.is_true(shown())
      F.cc:reset()
      assert.is_false(shown())
    end)

  describe('a program\'s love.draw', function()
    it('draws its frame on the canvas', function()
      F.run_project(function()
        F.cc:get_project_env().love.draw = function()
          draw('frame')
        end
      end)
      love.draw()
      F.cc:get_project_env().love.draw = nil
      assert.equal('frame', who())
    end)

    it('draws each frame on a cleared canvas, as LÖVE clears the'
      .. ' screen', function()
        local frames = 0
        F.run_project(function()
          F.cc:get_project_env().love.draw = function()
            frames = frames + 1
            if frames == 1 then draw('first') end
          end
        end)
        love.draw()
        assert.equal('first', who())
        love.draw()
        F.cc:get_project_env().love.draw = nil
        assert.equal(2, frames)
        assert.is_false(shown())
      end)

    it('is not drawn while paused: the last frame stays',
      function()
        F.run_project(function()
          F.cc:get_project_env().love.draw = function()
            draw('frame')
          end
        end)
        love.draw()
        F.cc:suspend_run('paused')
        F.love_update(0.1)
        assert.equal('inspect', love.state.app_state)
        pixels.outside = 'kept'
        love.draw()
        F.cc:get_project_env().love.draw = nil
        assert.equal('kept', who())
      end)
  end)

  it('a program\'s setCanvas() with no target binds its canvas',
    function()
      F.run_project(function()
        local g = F.cc:get_project_env().love.graphics
        g.setCanvas({ })
        g.setCanvas()
        draw('back')
      end)
      assert.equal('back', who())
    end)

  it('a program\'s setCanvas() with an empty table binds its canvas,'
    .. ' as a target saved with { getCanvas() } is', function()
      F.run_project(function()
        local g = F.cc:get_project_env().love.graphics
        local saved = { g.getCanvas() }
        g.setCanvas({ })
        g.setCanvas(saved)
        draw('back')
      end)
      assert.equal('back', who())
    end)

  it('a stop in a love.draw that pushed and never popped leaves the'
    .. ' screen the target, and nothing pushed', function()
      F.run_project(function()
        local env = F.cc:get_project_env()
        env.love.draw = function()
          -- LÖVE's own push, which the environment's is
          gfx.push('all')
          env.stop()
        end
      end)
      love.draw()
      assert.is_false(F.cc.run_live)
      assert.is_nil(target)
      assert.equal(0, gfx.getStackDepth())
    end)

  --- c2's first finding: before_exit runs on the canvas, and a
  --- push it leaves behind kept that binding
  it('a before_exit that pushed and raised leaves the screen the'
    .. ' target after the stop', function()
      run_drawing()
      F.cc:get_project_env().compy.before_exit = function()
        gfx.push('all')
        error('x')
      end
      press({ 'lctrl', 'q' })
      assert.equal('ready', love.state.app_state)
      assert.is_nil(target)
      assert.equal(0, gfx.getStackDepth())
    end)

  --- Program code runs on its canvas through one helper
  --- (use_canvas), which unwinds what the code pushed and did not
  --- pop before it gives the target back: no push of the
  --- program's outlives the call that made it, whatever entry
  --- point ran it (the lead's ruling on round c2)
  describe('program code that pushes and never pops leaves nothing'
    .. ' pushed after it, the screen the target', function()
    local function clean()
      assert.equal(0, gfx.getStackDepth())
      assert.is_nil(target)
    end

    it('its top-level code', function()
      F.run_project(function() gfx.push('all') end)
      clean()
    end)

    it('its love.update', function()
      F.run_project(function()
        F.cc:get_project_env().love.update = function()
          gfx.push('all')
        end
      end)
      F.love_update(0.1)
      F.cc:get_project_env().love.update = nil
      clean()
    end)

    it('its key handler', function()
      F.run_project(function()
        F.cc:get_project_env().love.keypressed = function()
          gfx.push('all')
        end
        F.cc:get_project_env().love.update = function() end
      end)
      F.session.press('a')
      F.session.release('a')
      F.cc:get_project_env().love.keypressed = nil
      F.cc:get_project_env().love.update = nil
      clean()
    end)

    it('a typed line', function()
      F.cc:get_project_env().mark = function() gfx.push('all') end
      F.session.type('mark()')
      press({ 'return' })
      clean()
    end)

    it('its before_exit at a stop', function()
      run_drawing()
      F.cc:get_project_env().compy.before_exit = function()
        gfx.push('all')
      end
      F.cc:stop_project_run()
      clean()
    end)
  end)

  --- c3's first finding: serial callbacks are program code, run
  --- on its canvas through the one helper
  it('a serial callback that binds the program\'s screen leaves the'
    .. ' screen the target after it', function()
      local update = SerialPort.update
      SerialPort.update = function()
        F.cc:get_project_env().love.graphics.setCanvas()
        return { }
      end
      finally(function() SerialPort.update = update end)
      F.love_update(0.1)
      assert.is_nil(target)
    end)

  --- c3's second finding: a program's reset() makes no canvas
  --- active under LÖVE, which for a program is its own
  it('a program\'s reset() leaves its canvas the target', function()
    F.run_project(function()
      F.cc:get_project_env().love.graphics.reset()
      draw('after')
    end)
    assert.equal('after', who())
  end)

  --- c3's fourth finding: the canvas holds premultiplied colour
  it('clears a love.draw frame to a translucent ground'
    .. ' premultiplied', function()
      F.run_project(function()
        local env = F.cc:get_project_env()
        env.love.graphics.setBackgroundColor(.2, .4, .6, .5)
        env.love.draw = function() end
      end)
      love.draw()
      F.cc:get_project_env().love.draw = nil
      assert.same({ .1, .2, .3, .5 }, cleared)
    end)

  it('a love.draw that pushes and never pops leaves nothing pushed'
    .. ' after its frame', function()
      F.run_project(function()
        local env = F.cc:get_project_env()
        env.love.draw = function()
          gfx.push('all')
        end
      end)
      love.draw()
      love.draw()
      F.cc:get_project_env().love.draw = nil
      assert.equal(0, gfx.getStackDepth())
      assert.is_nil(target)
    end)

  describe('the ground the program chose', function()
    it('is kept as the program sets it, before any stop', function()
      F.run_project(function()
        F.cc:get_project_env().love.graphics.setBackgroundColor(1, 0, 0)
        draw()
        F.cc:get_project_env().love.update = function() end
      end)
      assert.same({ 1, 0, 0, 1 }, F.cc.model.output:get_background())
      F.cc:get_project_env().love.update = nil
    end)

    it('stays through a second flush', function()
      F.run_project(function()
        F.cc:get_project_env().love.graphics.setBackgroundColor(1, 0, 0)
        draw()
        F.cc:get_project_env().love.update = function() end
      end)
      F.cc:get_project_env().love.update = nil
      F.cc:stop_project_run()
      gfx.setBackgroundColor(0, 0, 0)
      F.cc:stop_project_run()
      assert.same({ 1, 0, 0, 1 }, F.cc.model.output:get_background())
    end)

    it('stays through a typed line that does not set it', function()
      F.run_project(function()
        F.cc:get_project_env().love.graphics.setBackgroundColor(1, 0, 0)
        draw()
      end)
      gfx.setBackgroundColor(0, 0, 0)
      F.cc:get_project_env().mark = function() end
      F.session.type('mark()')
      press({ 'return' })
      assert.same({ 1, 0, 0, 1 }, F.cc.model.output:get_background())
    end)

    --- c2's second finding: the flush's reset leaves black, and a
    --- typed line that sets black is a choice all the same
    it('is what a typed line sets after a stop, black included',
      function()
        F.run_project(function()
          F.cc:get_project_env().love.graphics.setBackgroundColor(1, 0, 0)
          draw()
        end)
        F.cc:stop_project_run()
        gfx.setBackgroundColor(0, 0, 0)
        F.session.type('love.graphics.setBackgroundColor(0, 0, 0)')
        press({ 'return' })
        assert.same({ 0, 0, 0, 1 }, F.cc.model.output:get_background())
      end)

    it('is what a love.draw sets, though its state is given back'
      .. ' after the frame', function()
        F.run_project(function()
          local env = F.cc:get_project_env()
          env.love.draw = function()
            env.love.graphics.setBackgroundColor(0, 0, 1)
          end
        end)
        love.draw()
        F.cc:get_project_env().love.draw = nil
        assert.same({ 0, 0, 1, 1 }, F.cc.model.output:get_background())
      end)

    --- c3's third finding: a pop of the program's gives the ground
    --- back as LÖVE does
    it('is the one a pop of the program\'s puts back', function()
      F.run_project(function()
        local g = F.cc:get_project_env().love.graphics
        g.setBackgroundColor(1, 0, 0)
        -- LÖVE's own push, which the environment's is
        gfx.push('all')
        g.setBackgroundColor(0, 0, 1)
        g.pop()
        draw()
      end)
      assert.same({ 1, 0, 0, 1 }, F.cc.model.output:get_background())
    end)

    it('is black after a program\'s reset()', function()
      F.run_project(function()
        local g = F.cc:get_project_env().love.graphics
        g.setBackgroundColor(1, 0, 0)
        g.reset()
        draw()
      end)
      assert.same({ 0, 0, 0, 1 }, F.cc.model.output:get_background())
    end)

    it('goes with the picture at reset()', function()
      F.run_project(function()
        F.cc:get_project_env().love.graphics.setBackgroundColor(1, 0, 0)
        draw()
      end)
      F.cc:reset()
      assert.same({ 0, 0, 0, 1 }, F.cc.model.output:get_background())
    end)
  end)

  it('a program\'s getCanvas() answers nil on its own canvas',
    function()
      local seen = 'unset'
      F.run_project(function()
        seen = F.cc:get_project_env().love.graphics.getCanvas()
      end)
      assert.is_nil(seen)
    end)
end)
