-- The screen shows the console's text and the program's canvas
-- in one of three modes: text, combined (the text over the
-- picture) and the full picture (docs: the proposal "The
-- Program's Canvas and the Viewing Modes", built as if
-- accepted, the maintainer's ruling of November 17, 2026).
-- Which mode shows follows what happened last: a run starts in
-- text, its first drawing switches to the picture, a typed
-- line that draws switches to combined, a pause shows text and
-- continue() brings back the mode before it, and a stop or
-- reset() shows text.
--
-- Spec justification (dev testing policy): the mode is a seam
-- every run, pause, stop and typed line goes through, and a
-- path that misses it shows only on a device, as a picture that
-- will not come up or will not go away.

local F = require('tests.helpers.input_fixture')

local gfx
--- rectangles drawn so far
local drawcalls

--- What a program or a typed line does when it draws: a
--- drawing call of its love.graphics
local function draw()
  F.cc:get_project_env().love.graphics.rectangle('fill', 0, 0, 1, 1)
end

--- @return string
local function mode()
  return F.cc.model.screen:get()
end

--- @param keys string[] pressed in order, then all let go
local function press(keys)
  for _, k in ipairs(keys) do F.session.press(k) end
  for i = #keys, 1, -1 do F.session.release(keys[i]) end
end

--- A typed line, run with Enter
--- @param line string
local function submit(line)
  F.session.type(line)
  press({ 'return' })
end

describe('the screen modes #canvas', function()
  local saved_rectangle
  setup(function()
    F.setup()
    gfx = love.graphics
    saved_rectangle = gfx.rectangle
  end)
  teardown(function()
    gfx.rectangle = saved_rectangle
    F.teardown()
  end)
  before_each(function()
    drawcalls = 0
    gfx.rectangle = function() drawcalls = drawcalls + 1 end
    F.reset()
  end)

  it('shows text with nothing run', function()
    assert.equal('text', mode())
  end)

  it('starts a run in text', function()
    local seen
    F.run_project(function() seen = mode() end)
    assert.equal('text', seen)
  end)

  it('shows the picture once a running program draws', function()
    F.run_project(draw)
    assert.equal('picture', mode())
  end)

  it('stays in text for a program that only prints', function()
    F.run_project(function() print('x') end)
    assert.equal('text', mode())
  end)

  it('shows the picture once a program draws in its update',
    function()
      local n = 0
      F.run_project(function()
        F.cc:get_project_env().love.update = function()
          n = n + 1
          if n == 2 then draw() end
        end
      end)
      F.love_update(0.1)
      assert.equal('text', mode())
      F.love_update(0.1)
      assert.equal('picture', mode())
      F.cc:get_project_env().love.update = nil
    end)

  it('shows the picture for a program with love.draw', function()
    F.run_project(function()
      F.cc:get_project_env().love.draw = draw
    end)
    love.draw()
    assert.equal('picture', mode())
    F.cc:get_project_env().love.draw = nil
  end)

  it('shows combined after a typed line that draws', function()
    F.cc:get_project_env().mark = draw
    submit('mark()')
    assert.equal('combined', mode())
  end)

  it('stays in text after a typed line that draws nothing',
    function()
      submit('x = 1')
      assert.equal('text', mode())
    end)

  it('shows text at a pause and the mode before it at continue()',
    function()
      F.run_project(function()
        F.cc:get_project_env().love.draw = draw
      end)
      love.draw()
      assert.equal('picture', mode())
      F.cc:suspend_run('paused')
      F.love_update(0.1)
      assert.equal('inspect', love.state.app_state)
      assert.equal('text', mode())
      F.cc:get_project_env().continue()
      assert.equal('running', love.state.app_state)
      assert.equal('picture', mode())
      F.cc:get_project_env().love.draw = nil
    end)

  --- c2's third finding: a pause shows the console, whatever the
  --- program draws while it waits (a serial handler, say)
  it('keeps the console through a pause, and continue() shows the'
    .. ' picture drawn in it', function()
      F.run_project(function()
        F.cc:get_project_env().love.update = function() end
      end)
      F.cc:suspend_run('paused')
      F.love_update(0.1)
      assert.equal('inspect', love.state.app_state)
      draw()
      assert.equal('text', mode())
      F.cc:get_project_env().continue()
      F.cc:get_project_env().love.update = nil
      assert.equal('picture', mode())
    end)

  --- c4's first finding: a program's handler that continue()
  --- runs (a key's owed release) is the program's drawing, though
  --- a typed line called continue()
  it('shows the picture when a release owed at continue() draws',
    function()
      F.run_project(function()
        local env = F.cc:get_project_env()
        env.love.keyreleased = function() draw() end
        env.love.update = function() end
      end)
      F.session.press('x')
      F.cc:suspend_run('paused')
      F.love_update(0.1)
      assert.equal('inspect', love.state.app_state)
      F.session.release('x')
      submit('continue()')
      F.cc:get_project_env().love.keyreleased = nil
      F.cc:get_project_env().love.update = nil
      assert.equal('picture', mode())
    end)

  for name, stop in pairs({
    ['Ctrl+Q'] = function() press({ 'lctrl', 'q' }) end,
    ['stop()'] = function() F.cc:get_project_env().stop() end,
  }) do
    it('shows text after ' .. name .. ', the canvas kept', function()
      F.run_project(function()
        draw()
        F.cc:get_project_env().love.update = function() end
      end)
      assert.equal('picture', mode())
      stop()
      F.cc:get_project_env().love.update = nil
      assert.equal('ready', love.state.app_state)
      assert.equal('text', mode())
      assert.is_true(F.cc.model.output:is_drawn())
    end)
  end

  it('shows text after an error in top-level code, the canvas kept',
    function()
      F.run_project(function()
        draw()
        error('boom')
      end)
      assert.equal('text', mode())
      assert.is_true(F.cc.model.output:is_drawn())
    end)

  it('shows text after reset(), the canvas cleared', function()
    F.run_project(function()
      draw()
      F.cc:get_project_env().love.update = function() end
    end)
    F.cc:reset()
    F.cc:get_project_env().love.update = nil
    assert.equal('text', mode())
    assert.is_false(F.cc.model.output:is_drawn())
  end)

  --- the lead's decision 1 of November 17, 2026: a program that
  --- ended by itself and drew leaves its picture on show; one that
  --- drew nothing leaves the console
  it('shows the picture after a drawing program\'s natural end',
    function()
      F.run_project(draw)
      assert.is_false(F.cc.run_live)
      assert.equal('picture', mode())
      assert.is_true(F.cc.model.output:is_drawn())
    end)

  --- round c5's second finding: Ctrl+Q acts where something of a
  --- program shows, its finished picture included
  it('leaves a finished program\'s picture with Ctrl+Q', function()
    F.run_project(draw)
    assert.equal('picture', mode())
    press({ 'lctrl', 'q' })
    assert.equal('text', mode())
  end)

  --- round c6: Ctrl+Pause and Ctrl+Q in one batch of events, no
  --- update between: the run in its pause's frame is live, and
  --- Ctrl+Q stops it (the reviewer's reproducer, turned to what the
  --- stop makes)
  it('stops a run with Ctrl+Q in the frame its pause is asked in',
    function()
      F.run_source([[function love.draw()
        gfx.rectangle('fill', 0, 0, 1, 1)
      end]])
      love.draw()
      assert.equal('picture', mode())
      press({ 'lctrl', 'pause' })
      assert.equal('snapshot', love.state.app_state)
      press({ 'lctrl', 'q' })
      F.love_update(.01)
      assert.is_false(F.cc.run_live)
      assert.equal('ready', love.state.app_state)
      assert.equal('text', mode())
      assert.is_true(F.cc.model.output:is_drawn())
    end)

  it('shows text after a printing program\'s natural end', function()
    F.run_project(function() print('x') end)
    assert.is_false(F.cc.run_live)
    assert.equal('text', mode())
  end)

  it('switches to the picture once per run', function()
    F.run_project(function()
      draw()
      F.cc:get_project_env().love.update = draw
    end)
    F.cc.model.screen:set('text')
    F.love_update(0.1)
    assert.equal('text', mode())
    F.cc:get_project_env().love.update = nil
  end)

  it('switches a new run to the picture again', function()
    F.run_project(draw)
    F.cc.model.screen:set('text')
    F.run_project(draw)
    assert.equal('picture', mode())
  end)
  describe('what each mode draws', function()
    local saved_draw
    local drawn
    local saved_meta
    setup(function()
      saved_draw = gfx.draw
      -- the rest of what drawing the screen calls does nothing
      saved_meta = getmetatable(gfx)
      setmetatable(gfx, {
        __index = function() return function() end end,
      })
    end)
    teardown(function()
      gfx.draw = saved_draw
      setmetatable(gfx, saved_meta)
    end)
    local o_canvas
    before_each(function()
      F.reset()
      drawn = { }
      gfx.draw = function(what) drawn[#drawn + 1] = what end
      o_canvas = F.cc.model.output.canvas
    end)
    after_each(function()
      F.cc.model.output.canvas = o_canvas
      F.cc.model.screen:set('text')
    end)

    --- @return integer? where the program's canvas was drawn
    --- @return integer? where the output's canvas was drawn
    local function order()
      local output = F.cc.model.output
      local pc, oc
      for i, d in ipairs(drawn) do
        if d == output.canvas and not pc then pc = i end
        if d == output.term_canvas and not oc then oc = i end
      end
      return pc, oc
    end

    local function draw_screen(m)
      F.cc.model.screen:set(m)
      local CV = F.cc.view
      CV.canvas:draw(F.cc:get_terminal(), F.cc:get_canvas(),
        F.cc.model.output.term_canvas, CV.drawable_height, m,
        F.cc.model.output)
    end

    it('text: the output, no picture', function()
      -- distinct stand-ins, so that the order shows which is which
      F.cc.model.output.canvas = { }
      draw_screen('text')
      local pc, oc = order()
      assert.is_nil(pc)
      assert.is_not_nil(oc)
    end)

    it('combined: the picture, then the output over it', function()
      F.cc.model.output.canvas = { }
      draw_screen('combined')
      local pc, oc = order()
      assert.is_not_nil(pc)
      assert.is_not_nil(oc)
      assert.is_true(pc < oc)
    end)

    --- c1's fourth finding: what is drawn on a canvas carries
    --- its alpha in its colour already
    it('draws the picture premultiplied, and the output at the'
      .. ' theme\'s opacity: each alpha counted once', function()
        local saved_blend, saved_color = gfx.setBlendMode, gfx.setColor
        local blend, color, at_draw = { }, { }, { }
        gfx.setBlendMode = function(m, a) blend = { m, a } end
        gfx.setColor = function(r, g, b, a) color = { r, g, b, a } end
        local plain_draw = gfx.draw
        local canvas = { }
        local output = F.cc.model.output
        output.canvas = canvas
        gfx.draw = function(what)
          if what == canvas then at_draw.picture = blend end
          if what == output.term_canvas then
            at_draw.text, at_draw.color = blend, color
          end
          plain_draw(what)
        end
        finally(function()
          gfx.setBlendMode, gfx.setColor, gfx.draw =
              saved_blend, saved_color, plain_draw
        end)
        local theme = F.cfg.view.colors.screen.combined
        local text = theme.text
        theme.text = .5
        draw_screen('combined')
        theme.text = text
        assert.same({ 'alpha', 'premultiplied' }, at_draw.picture)
        --- c2's fourth finding: the output's canvas, cleared to
        --- nothing over a picture, is premultiplied too, and its
        --- opacity tints it whole
        assert.same({ 'alpha', 'premultiplied' }, at_draw.text)
        assert.same({ .5, .5, .5, .5 }, at_draw.color)
      end)

    --- c4's second finding: the ground under the picture is
    --- opaque, as a screen shows a translucent clear colour, so a
    --- translucent ground counts once wherever it was set
    it('lays the picture on its ground opaque', function()
      local saved_color, saved_rect = gfx.setColor, gfx.rectangle
      local color, ground
      gfx.setColor = function(r, g, b, a)
        color = type(r) == 'table' and r or { r, g, b, a }
      end
      gfx.rectangle = function() ground = ground or color end
      finally(function()
        gfx.setColor, gfx.rectangle = saved_color, saved_rect
      end)
      F.cc.model.output:keep_background(1, 0, 0, .5)
      F.cc.model.output.canvas = { }
      draw_screen('picture')
      assert.same({ 1, 0, 0, 1 },
        { ground[1], ground[2], ground[3], ground[4] or 1 })
    end)

    it('picture: the picture alone', function()
      F.cc.model.output.canvas = { }
      draw_screen('picture')
      local pc, oc = order()
      assert.is_not_nil(pc)
      assert.is_nil(oc)
    end)
  end)

  --- the steps a key takes (F12, any key back): the model's
  describe('stepping through the modes', function()
    it('goes text, combined, picture and round again', function()
      local S = F.cc.model.screen
      local seen = { }
      for _ = 1, 4 do
        S:step()
        seen[#seen + 1] = S:get()
      end
      assert.same({ 'combined', 'picture', 'text', 'combined' }, seen)
    end)

    it('goes back from the picture to the mode before it', function()
      local S = F.cc.model.screen
      S:set('combined')
      S:step()
      assert.equal('picture', S:get())
      S:back()
      assert.equal('combined', S:get())
    end)

    --- c3's fifth finding
    it('goes back from a picture stepped to before a pause in which'
      .. ' the program first drew', function()
        F.run_project(function()
          F.cc:get_project_env().love.update = function() end
        end)
        local S = F.cc.model.screen
        S:step()
        S:step()
        assert.equal('picture', S:get())
        F.cc:suspend_run('paused')
        F.love_update(0.1)
        draw()
        F.cc:get_project_env().continue()
        F.cc:get_project_env().love.update = nil
        assert.equal('picture', S:get())
        S:back()
        assert.equal('combined', S:get())
      end)

    it('goes back to text from a picture a run brought up', function()
      F.run_project(draw)
      F.cc.model.screen:back()
      assert.equal('text', mode())
    end)
  end)

  --- compy.screen (stage 3; the maintainer ruled the shape "ok")
  describe('compy.screen', function()
    local function screen()
      return F.cc:get_project_env().compy.screen
    end

    for _, m in ipairs({ 'text', 'combined', 'picture' }) do
      it('show("' .. m .. '") shows it, and getMode() says so',
        function()
          screen().show(m)
          assert.equal(m, mode())
          assert.equal(m, screen().getMode())
        end)
    end

    it('getMode() says the mode a run\'s drawing brought up',
      function()
        local seen
        F.run_project(function()
          draw()
          seen = screen().getMode()
        end)
        assert.equal('picture', seen)
      end)

    for name, bad in pairs({
      ['a name it has not'] = 'full',
      ['no name'] = nil,
      ['a number'] = 2,
    }) do
      it('stops the program at its own line for ' .. name,
        function()
          local ok, err = pcall(function() screen().show(bad) end)
          assert.is_false(ok)
          assert.matches('screen_modes_spec.lua:%d+: ', err)
          assert.matches('"text", "combined" or "picture"', err)
        end)
    end

    it('holds against the first drawing of the run', function()
      F.run_project(function()
        screen().show('text')
        draw()
        F.cc:get_project_env().love.update = function() end
      end)
      assert.equal('text', mode())
      F.cc:get_project_env().love.update = nil
    end)

    it('is the run\'s: the next run starts in text and its drawing'
      .. ' brings up its picture', function()
        F.run_project(function() screen().show('combined') end)
        local seen
        F.run_project(function()
          seen = mode()
          draw()
        end)
        assert.equal('text', seen)
        assert.equal('picture', mode())
      end)

    it('goes at a stop', function()
      F.run_project(function()
        screen().show('combined')
        F.cc:get_project_env().love.update = function() end
      end)
      F.cc:get_project_env().stop()
      F.cc:get_project_env().love.update = nil
      assert.equal('text', mode())
    end)

    it('shows the mode from a typed line too', function()
      submit('compy.screen.show("picture")')
      assert.equal('picture', mode())
    end)
  end)
end)
