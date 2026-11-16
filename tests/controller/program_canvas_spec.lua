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

  -- no reserved key since 2026-11-14: the program runs on
  it('Ctrl+S leaves it', function()
    run_drawing()
    press({ 'lctrl', 's' })
    assert.equal('running', love.state.app_state)
    assert.is_true(shown())
  end)

  it('Ctrl+T clears it', function()
    run_drawing()
    press({ 'lctrl', 't' })
    assert.are_not.equal('running', love.state.app_state)
    assert.is_false(shown())
  end)

  -- Ctrl+Q stops the program and keeps its project open; the
  -- fixture has none open, so one is set here, and a close
  -- would show.
  it('Ctrl+Q clears it, the project still open', function()
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
    assert.is_false(shown())
    assert.is_false(closed)
    assert.is_true(still_open)
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

  it('an error in top-level code clears what it drew', function()
    F.run_project(function()
      draw()
      error('boom')
    end)
    assert.equal('ready', love.state.app_state)
    assert.is_false(shown())
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

  it('what a before_exit hook draws is cleared too', function()
    run_drawing()
    F.cc:get_project_env().compy.before_exit = paint
    press({ 'lctrl', 'q' })
    assert.is_false(shown())
  end)

  describe('whatever graphics state the program left', function()
    it('a scissor does not spare part of it on a stop',
      function()
        run_drawing()
        F.cc:get_project_env().compy.before_exit = restrict
        press({ 'lctrl', 'q' })
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

    --- The outgoing handler keeps drawing after its replacement
    --- ended too: the canvas is nobody's.
    for name, top in pairs({
      ['stops'] = function() F.cc:get_project_env().stop() end,
      ['fails'] = function() error('boom') end,
    }) do
      it('clears it when the run it started ' .. name
        .. ' before it draws again', function()
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

  -- One console line that stops and then would draw: the stop
  -- ends the line (design B), so nothing after it draws, and
  -- the stop's clear is the last word on the canvas.
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

  it('the same line after a run that finished: the stop clears'
    .. ' its picture, and nothing after it draws', function()
      F.run_project(function() draw('prog') end)
      assert.equal('prog', who())
      submit_stop_and_draw()
      assert.is_false(shown())
    end)

  -- Enter reaches the program's input hook, which here stops the
  -- run and lets the key fall through: the key is the stop's
  -- (design B), and the console's line waits for the next Enter.
  it('a key whose input hook stopped the run is the stop\'s; the'
    .. ' console\'s line runs at the next Enter', function()
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
      press({ 'return' })
      env.love.update = nil
      env.compy.input.hooks.keypressed = nil
      assert.equal('ready', love.state.app_state)
      assert.is_false(shown())
      press({ 'return' })
      assert.equal('typed', who())
    end)

  it('the same line over a program with an update handler keeps'
    .. ' what it drew', function()
      F.run_project(function()
        draw('prog')
        F.cc:get_project_env().love.update = function() end
      end)
      assert.equal('running', love.state.app_state)
      submit_stop_and_draw()
      F.cc:get_project_env().love.update = nil
      assert.equal('ready', love.state.app_state)
      assert.is_false(shown())
    end)

  it('the same line over a run with a live handler keeps what'
    .. ' it drew', function()
      F.run_project(function()
        draw('prog')
        F.cc:get_project_env().love.mousepressed = function() end
      end)
      submit_stop_and_draw()
      assert.is_false(shown())
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
  -- stop ends it (design B), so no error comes, and the stop
  -- clears what it drew.
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
      assert.is_false(shown())
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
  -- picture stays; Ctrl+Q stops it as it stops a running one.
  it('a run in ready with a live handler keeps it through'
    .. ' Ctrl+S, until Ctrl+Q stops it', function()
      F.run_project(function()
        draw()
        F.cc:get_project_env().love.mousepressed = function() end
      end)
      assert.equal('ready', love.state.app_state)
      press({ 'lctrl', 's' })
      assert.is_true(shown())
      press({ 'lctrl', 'q' })
      assert.equal('ready', love.state.app_state)
      assert.is_false(shown())
    end)

  it('a run that finished with nothing live keeps its picture'
    .. ' until Ctrl+Q stops it', function()
      F.run_project(draw)
      assert.is_true(shown())
      press({ 'lctrl', 'q' })
      assert.is_false(shown())
    end)
end)
