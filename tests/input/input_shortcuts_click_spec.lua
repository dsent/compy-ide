-- Availability: global shortcuts and click detection predate
-- the Compy input API (introduced in 1.0.0-rc20260712); the
-- combo normalisation they read arrived with it, and the legacy
-- text solicitation globals were removed by it.

-- Non-consuming global shortcuts, framework click detection,
-- project-stop console handback, and the legacy poll-idiom
-- removal (doc/development/internals/user_input.md, "Dispatch
-- chain"; doc/input_api.md, "Migration from the legacy
-- globals").

local F    = require('tests.helpers.input_fixture')
local mock = require('tests.mock')

describe('input surface: inbound events — shortcuts and clicks'
  .. ' #input', function()
  setup(function() F.setup() end)
  teardown(function() F.teardown() end)
  before_each(function() F.reset() end)

  -- Global shortcuts are non-consuming
  -- (doc/development/internals/user_input.md, "Dispatch chain":
  -- "None of these consume the key: it still reaches the active
  -- route afterward"): a framework shortcut fires its effect
  -- and the key still reaches its route.
  describe('global shortcuts do not consume the key (#disputable)',
    function()

      it('a shortcut fires but does not consume', function()
        love.state.app_state = 'running'
        local n = 0
        local orig = love.keypressed
        love.keypressed = function(k) n = n + 1; orig(k) end
        mock.keystroke('C-pause', F.session.press, false)
        love.keypressed = orig
        assert.equal('snapshot', love.state.app_state)
        assert.equal(1, n)
      end)

      -- cfg.mode is a global framework state: 'play' means the
      -- framework runs on an end device for a player, 'dev'
      -- that a developer runs it to work on it. 'play' narrows
      -- the shortcut set so a player cannot manage projects:
      -- restart/profile stay live, quit/stop/quickswitch do not
      -- (doc/development/decisions/input.md, D-ROUTE-OWNS;
      -- doc/development/internals/user_input.md, "Dispatch
      -- chain"). The shared fixture is built in dev mode, so
      -- this test wires a private play-mode stub controller and
      -- saves/restores the shared love.handlers around it.
      it('#play mode narrows the active shortcut set', function()
          local calls = { }
          local stub = {
            cfg = { mode = 'play' },
            restart = function() calls.restart = true end,
            quit_project = function() calls.quit = true end,
            stop_project_run = function() end,
            keypressed = function() end,
          }
          local saved    = table.clone(love.handlers)
          local saved_kp = love.keypressed
          love.keypressed = function() end
          love.state.app_state = 'running'
          Controller.setup_callback_handlers(stub)
          local kp = love.handlers.keypressed
          mock.keystroke('C-M-r', kp, false)
          mock.keystroke('C-q', kp, false)
          for k, v in pairs(saved) do love.handlers[k] = v end
          love.keypressed = saved_kp
          assert.is_true(calls.restart)
          assert.is_nil(calls.quit)
        end)
    end)

  -- Pointer shortcuts. A pointer event names no trigger key, so
  -- its combo is the held modifiers plus the wildcard: 'ctrl+*'
  -- is a ctrl-click. Nothing else about the tier differs — same
  -- table, same walk, same truthy-consumes rule.
  describe('pointer shortcuts', function()

    it('a modifier combo fires and consumes', function()
      local fired, reached_hook = false, false
      local input = F.activate_project()
      input.shortcuts.mousepressed['ctrl+*'] =
          function() fired = true; return true end
      input.hooks.mousepressed =
          function() reached_hook = true end
      F.session.press('lctrl')
      F.session.mousepressed(10, 10, 1, false, 1)
      assert.is_true(fired)
      assert.is_false(reached_hook)
    end)

    -- The control: an unmatched combo falls through untouched.
    -- Without this case a shortcut tier that fired on EVERY
    -- pointer event would pass the case above.
    it('an unmatched pointer combo reaches the hook',
      function()
        local fired, reached_hook = false, false
        local input = F.activate_project()
        input.shortcuts.mousepressed['ctrl+*'] =
            function() fired = true; return true end
        input.hooks.mousepressed =
            function() reached_hook = true end
        F.session.mousepressed(10, 10, 1, false, 1)
        assert.is_false(fired)
        assert.is_true(reached_hook)
      end)

    -- The button is the trigger the channel names, serialised
    -- as 'mouseN' — so an unmodified right-click is bindable,
    -- which is what a project reaching for a context action
    -- wants.
    it('the button is the trigger: mouse2 is a right-click',
      function()
        local hits = { }
        local input = F.activate_project()
        input.shortcuts.mousepressed['mouse2'] =
            function() hits[#hits + 1] = 'right'; return true end
        F.session.mousepressed(10, 10, 2, false, 1)
        assert.same({ 'right' }, hits)
      end)

    -- Discriminating: the same binding must be SILENT for
    -- another button. A tier that keyed on the channel alone
    -- would pass the case above and fail this one.
    it('a button trigger is silent for another button',
      function()
        local fired, reached_hook = false, false
        local input = F.activate_project()
        input.shortcuts.mousepressed['mouse2'] =
            function() fired = true; return true end
        input.hooks.mousepressed =
            function() reached_hook = true end
        F.session.mousepressed(10, 10, 1, false, 1)
        assert.is_false(fired)
        assert.is_true(reached_hook)
      end)

    -- Modifiers compose with the button exactly as they do with
    -- a key, and exact beats the class (D-COMBO-SHAPE) — the
    -- same rule the keyboard channels follow.
    it('exact modifier+button wins over the modifier class',
      function()
        local hit
        local input = F.activate_project()
        input.shortcuts.mousepressed['ctrl+*'] =
            function() hit = 'class'; return true end
        input.shortcuts.mousepressed['ctrl+mouse2'] =
            function() hit = 'exact'; return true end
        F.session.press('lctrl')
        F.session.mousepressed(10, 10, 2, false, 1)
        assert.equal('exact', hit)
      end)

    -- A channel with no discrete trigger to name stays
    -- modifier-only: mousemoved has no button, so its combos
    -- are classes and an unmodified move never consults the
    -- tier at all (which is also why it allocates nothing).
    it('a channel with no trigger matches on modifiers alone',
      function()
        local hits = { }
        local input = F.activate_project()
        input.shortcuts.mousemoved['ctrl+*'] =
            function() hits[#hits + 1] = 'moved'; return true end
        F.session.mousemoved(10, 10, 1, 1, false)
        assert.same({ }, hits)
        F.session.press('lctrl')
        F.session.mousemoved(11, 11, 1, 1, false)
        assert.same({ 'moved' }, hits)
      end)

    -- The button is LÖVE's own third argument, not part of the
    -- combo: one vocabulary for combos (modifiers), and the
    -- button read where LÖVE already delivers it.
    it('the handler receives LOVE arguments, button included',
      function()
        local seen
        local input = F.activate_project()
        input.shortcuts.mousepressed['ctrl+*'] =
            function(x, y, btn) seen = { x, y, btn }; return true end
        F.session.press('lctrl')
        F.session.mousepressed(10, 20, 2, false, 1)
        assert.same({ 10, 20, 2 }, seen)
      end)
  end)

  -- Framework click detection
  -- (doc/development/internals/user_input.md, "Framework-level
  -- click handling"): a derived path over raw pointer delivery,
  -- asserted on outcomes against the project-defined handlers
  -- (default no-ops). The 0.4s / 2.5px constants are mechanism;
  -- this is a regression surface, not a routing rule.
  describe('framework click detection', function()
    local seen
    local function release(x, y)
      F.session.mousepressed(x, y, 1, false, 1)
      F.session.mousereleased(x, y, 1, false, 1)
    end
    before_each(function()
      seen = {}
      local input = F.activate_project()
      input.hooks.singleclick = function(x, y)
        seen[#seen + 1] = { 'single', x, y }
      end
      input.hooks.doubleclick = function(x, y)
        seen[#seen + 1] = { 'double', x, y }
      end
    end)

    it('waits for a single and retains its release position', function()
      release(10, 540)
      F.love_update(0.1)
      assert.equal(0, #seen)
      F.set_mouse_pos(400, 400)
      F.session.mousemoved(400, 400, 390, -140, false)
      assert.same({ { 'single', 10, 540 } }, seen)
      F.love_update(0.31)
      assert.same({ { 'single', 10, 540 } }, seen)
    end)

    it('keeps a nearby release eligible for a double', function()
      release(10, 540)
      F.session.mousemoved(12, 540, 2, 0, false)
      assert.equal(0, #seen)
      release(12, 540)
      assert.same({ { 'double', 12, 540 } }, seen)
    end)

    it('does not pair after moving out and back', function()
      release(10, 540)
      F.session.mousemoved(13, 540, 3, 0, false)
      F.session.mousemoved(10, 540, -3, 0, false)
      release(10, 540)
      F.love_update(0.5)
      assert.same({ { 'single', 10, 540 }, { 'single', 10, 540 } }, seen)
    end)

    it('rejects movement while held even if it returns', function()
      F.session.mousepressed(10, 540, 1, false, 1)
      F.session.mousemoved(13, 540, 3, 0, false)
      F.session.mousemoved(10, 540, -3, 0, false)
      F.session.mousereleased(10, 540, 1, false, 1)
      F.love_update(0.5)
      assert.equal(0, #seen)
    end)

    it('checks press/release displacement without motion events', function()
      F.session.mousepressed(10, 540, 1, false, 1)
      F.session.mousereleased(13, 540, 1, false, 1)
      F.love_update(0.5)
      assert.equal(0, #seen)
    end)

    it('delivers a double immediately on the second release', function()
      release(10, 540)
      F.love_update(0.2)
      F.session.mousepressed(11, 540, 1, false, 2)
      assert.equal(0, #seen)
      F.session.mousereleased(11, 540, 1, false, 2)
      assert.same({ { 'double', 11, 540 } }, seen)
      F.love_update(0.5)
      assert.equal(1, #seen)
    end)

    it('pairs a rapid series without swallowing later pairs', function()
      for i = 1, 6 do
        release(10, 540)
        F.love_update(0.08)
      end
      assert.equal(3, #seen)
      for _, event in ipairs(seen) do assert.equal('double', event[1]) end
    end)

    it('keeps two separate positions as two singles', function()
      release(10, 540)
      F.love_update(0.1)
      release(40, 540)
      F.love_update(0.5)
      assert.same({ { 'single', 10, 540 }, { 'single', 40, 540 } }, seen)
    end)

    it('does not pair clicks outside the window', function()
      release(10, 540)
      F.love_update(0.41)
      release(10, 540)
      F.love_update(0.41)
      assert.same({ { 'single', 10, 540 }, { 'single', 10, 540 } }, seen)
    end)

    it('drops pending clicks when the project stops', function()
      release(10, 540)
      F.cc:stop_project_run()
      F.love_update(0.5)
      assert.equal(0, #seen)
    end)

    it('does not transfer a press into a newly activated project', function()
      F.session.mousepressed(10, 540, 1, false, 1)
      F.cc:stop_project_run()
      local input = F.activate_project()
      input.hooks.singleclick = function() seen[#seen + 1] = true end
      F.session.mousereleased(10, 540, 1, false, 1)
      F.love_update(0.5)
      assert.equal(0, #seen)
    end)
  end)

  -- Project stop returns input to the console
  -- (doc/development/decisions/input.md, D-ROUTE-LIFETIME): a
  -- project's the project handler is installed while it runs;
  -- after stop it receives nothing and typing lands in the
  -- console again. Asserted end-to-end on behaviour — who
  -- receives — not on handler identity.
  describe('project stop returns input to the console',
    function()

      it('the console receives after stop', function()
        local got = 0
        F.activate_project({ keypressed = function()
          got = got + 1
        end })
        F.cc:stop_project_run()
        F.console:add_text('ab')
        F.session.press('backspace')
        assert.equal(0, got)
        assert.same({ 'a' }, F.console:get_text())
      end)
    end)

  -- Legacy text solicitation (doc/input_api.md, "Migration
  -- from the legacy globals"): the five poll-idiom globals +
  -- the debug-only
  -- astv_input (a sixth global on the same machinery) are
  -- gone from the project environment — an ordinary nil
  -- field, no shim, no deprecation path (same section).
  describe('legacy text solicitation is removed #legacy',
    function()

    it('every legacy global is an ordinary nil field',
      function()
        F.activate_project()
        local env = F.cc:get_project_env()
        assert.is_nil(env.user_input)
        assert.is_nil(env.input_code)
        assert.is_nil(env.input_text)
        assert.is_nil(env.write_to_input)
        assert.is_nil(env.validated_input)
        assert.is_nil(env.astv_input)
      end)
  end)
end)
