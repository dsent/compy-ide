-- Global (platform) shortcuts: controller.lua's
-- setup_callback_handlers installs these ahead of route
-- dispatch, over love.handlers.keypressed/keyreleased
-- (doc/development/internals/user_input.md, "Dispatch chain").
-- That section also states they do not consume the key —
-- characterized in tests/input/input_shortcuts_click_spec.lua,
-- which this file does not repeat.
--
-- This file's own claim: a project cannot suppress one of these
-- by registering the same combo on its own
-- compy.input.shortcuts.keypressed table. The platform effect
-- fires regardless — a property of the gateway running before
-- any route is reached, not of any one binding.
--
-- Each reserved combo's OWN effect (not the suppression claim)
-- is left as a named pending gap below — see
-- doc/development/tests.md, "Input Contract Suite" for the
-- pending-case convention this suite already follows.

local F    = require('tests.helpers.input_fixture')
local mock = require('tests.mock')

-- restart reaches real project execution (run_project) --
-- machinery this file's fixture does not stand up. A minimal
-- stub records what the raw gate invoked, isolating the
-- modifier-exactness question from project loading
-- (doc/development/decisions/input.md, D-BEHAVIOUR-TEST's
-- named-seam exception; same technique as
-- input_shortcuts_click_spec.lua's play-mode case). `reset`
-- is the method Ctrl+Shift+R called until the key was dropped
-- (2026-11-14): the stub keeps it to show nothing calls it.
-- @param combo string  mock.keystroke syntax, e.g. 'C-r'
-- @return table  {restart = true?, reset = true?}
local function drive_stub(combo)
  local calls = { }
  local stub  = {
    cfg     = { mode = 'dev' },
    restart = function() calls.restart = true end,
    reset   = function() calls.reset = true end,
    card_shows = function() return false end,
    key_released = function() end,
  }
  local saved    = table.clone(love.handlers)
  local saved_kp = love.keypressed
  love.keypressed = function() end
  Controller.setup_callback_handlers(stub)
  mock.keystroke(combo, love.handlers.keypressed, false)
  for k, v in pairs(saved) do love.handlers[k] = v end
  love.keypressed = saved_kp
  return calls
end

describe('input surface: inbound events — global platform'
  .. ' shortcuts #input', function()
  setup(function() F.setup() end)
  teardown(function() F.teardown() end)
  before_each(function() F.reset() end)

  describe('a project cannot suppress a platform combo',
    function()

      -- Route-preserving: suspend only flips app_state, so the
      -- project route is still installed afterward — BOTH the
      -- platform effect and the project's own binding run for
      -- the same event.
      it('ctrl+pause suspends despite a project claiming it',
        function()
          local project_ran = false
          local input = F.activate_project()
          input.shortcuts.keypressed['ctrl+pause'] = function()
            project_ran = true
            return true
          end
          love.state.app_state = 'running'
          F.session.press('lctrl')
          F.session.press('pause')
          assert.equal('snapshot', love.state.app_state)
          assert.is_true(project_ran)
        end)

      -- Route-destroying: the stop tears the project route down
      -- (stop_project_run reinstalls the console's handlers)
      -- BEFORE the gateway forwards the event, so the project's
      -- own binding never runs. That is the route disappearing,
      -- not the platform suppressing it — the project could
      -- not have blocked the stop either way.
      it('ctrl+q stops the run despite a project claiming it',
        function()
          local project_ran = false
          local input = F.activate_project()
          input.shortcuts.keypressed['ctrl+q'] = function()
            project_ran = true
            return true
          end
          F.session.press('lctrl')
          F.session.press('q')
          assert.equal('ready', love.state.app_state)
          assert.is_false(project_ran)
        end)
    end)

  -- The reserved map of 2026-11-14 (doc/development/decisions/
  -- input.md, D-RESERVE-TABLE's note of that date): Ctrl+Q
  -- returns to the console and the project stays open; no key
  -- closes the project; Ctrl+S and Ctrl+Shift+R are reserved
  -- no longer. Ctrl+Q in the file editor is covered where the
  -- editor's other exits are, tests/editor/spec/
  -- is1_files_spec.lua and input_editor_keys_spec.lua.
  describe('ctrl+q returns to the console', function()
    local P, closed, stops, orig_close, orig_stop

    before_each(function()
      P = F.cc.model.projects
      closed, stops = 0, 0
      orig_close = F.cc._close_project
      orig_stop = F.cc.stop_project_run
      F.cc._close_project = function(...)
        closed = closed + 1
        return orig_close(...)
      end
      F.cc.stop_project_run = function(...)
        stops = stops + 1
        return orig_stop(...)
      end
    end)

    after_each(function()
      F.cc._close_project = orig_close
      F.cc.stop_project_run = orig_stop
    end)

    local function ctrl_q()
      F.session.press('lctrl')
      F.session.press('q')
      F.session.release('q')
      F.session.release('lctrl')
    end

    it('stops a running program and keeps the project open',
      function()
        F.activate_project()
        local open = { name = 'p' }
        P.current = open
        finally(function() P.current = nil end)
        ctrl_q()
        assert.equal('ready', love.state.app_state)
        assert.equal(1, stops)
        assert.equal(0, closed)
        assert.equal(open, P.current)
      end)

    it('stops a paused program and keeps the project open',
      function()
        F.activate_project()
        local open = { name = 'p' }
        P.current = open
        finally(function() P.current = nil end)
        love.state.app_state = 'inspect'
        ctrl_q()
        assert.equal('ready', love.state.app_state)
        assert.equal(1, stops)
        assert.equal(0, closed)
        assert.equal(open, P.current)
      end)

    -- A program that finished its top-level code is idle, not
    -- stopped: its picture and its handlers are still there
    -- behind the console (ConsoleController.run_live).
    it('stops a program that idles behind the console',
      function()
        F.run_project(function() end)
        assert.equal('ready', love.state.app_state)
        assert.is_true(F.cc.run_live)
        local open = P.current
        ctrl_q()
        assert.equal('ready', love.state.app_state)
        assert.equal(1, stops)
        assert.is_false(F.cc.run_live)
        assert.equal(0, closed)
        assert.equal(open, P.current)
      end)

    it('does nothing in the console with no program running',
      function()
        local open = P.current
        assert.is_falsy(F.cc.run_live)
        F.session.type('x = 1')
        ctrl_q()
        assert.equal('ready', love.state.app_state)
        assert.equal(0, stops)
        assert.equal(0, closed)
        assert.equal(open, P.current)
        assert.same('x = 1',
          string.unlines(F.cc.input:get_text()))
      end)
  end)

  describe('keys the map no longer reserves', function()
    for _, c in ipairs({
      { 'ctrl+s', { 'lctrl' }, 's' },
      { 'ctrl+shift+r', { 'lctrl', 'lshift' }, 'r' },
    }) do
      it(c[1] .. ' reaches a running program, which goes on',
        function()
          local bound, seen = false, nil
          local input = F.activate_project({
            keypressed = function(k) seen = k end,
          })
          input.shortcuts.keypressed[c[1]] = function()
            bound = true
          end
          for _, m in ipairs(c[2]) do F.session.press(m) end
          F.session.press(c[3])
          assert.equal('running', love.state.app_state)
          assert.is_true(bound)
          assert.equal(c[3], seen)
        end)

      it(c[1] .. ' does nothing in the console', function()
        local stops, orig = 0, F.cc.stop_project_run
        F.cc.stop_project_run = function(...)
          stops = stops + 1
          return orig(...)
        end
        finally(function() F.cc.stop_project_run = orig end)
        local open = F.cc.model.projects.current
        for _, m in ipairs(c[2]) do F.session.press(m) end
        F.session.press(c[3])
        assert.equal('ready', love.state.app_state)
        assert.equal(0, stops)
        assert.equal(open, F.cc.model.projects.current)
      end)
    end
  end)

  -- A reservation matches its modifier set exactly
  -- (doc/development/decisions/input.md, D-EXACT-RESERVE): the
  -- named modifiers held, and no other. Each pair below proves
  -- the boundary, not the reserved combo's own effect (that
  -- stays a named pending gap, per P15).
  describe('a reservation matches its modifier set exactly',
    function()

      it('ctrl+escape (release) still asks love to quit',
        function()
          local quits = 0
          local orig  = love.event.quit
          love.event.quit = function() quits = quits + 1 end
          F.session.press('lctrl')
          F.session.release('escape')
          love.event.quit = orig
          assert.equal(1, quits)
        end)

      it('ctrl+shift+escape no longer quits; the project'
        .. ' binding runs instead', function()
          local quits, project_ran = 0, false
          local orig = love.event.quit
          love.event.quit = function() quits = quits + 1 end
          local input = F.activate_project()
          input.shortcuts.keyreleased['ctrl+shift+escape'] =
              function() project_ran = true; return true end
          F.session.press('lctrl')
          F.session.press('lshift')
          F.session.release('escape')
          love.event.quit = orig
          assert.equal(0, quits)
          assert.is_true(project_ran)
        end)

      it('ctrl+t still quickswitches while running', function()
        F.activate_project()
        love.state.app_state = 'running'
        F.session.press('lctrl')
        F.session.press('t')
        assert.are_not.equal('running', love.state.app_state)
      end)

      it('ctrl+shift+t no longer quickswitches; the project'
        .. ' binding runs instead', function()
          local project_ran = false
          local input = F.activate_project()
          input.shortcuts.keypressed['ctrl+shift+t'] =
              function() project_ran = true; return true end
          love.state.app_state = 'running'
          F.session.press('lctrl')
          F.session.press('lshift')
          F.session.press('t')
          assert.equal('running', love.state.app_state)
          assert.is_true(project_ran)
        end)

      it('ctrl+alt+pause no longer suspends; the project'
        .. ' binding runs instead', function()
          local project_ran = false
          local input = F.activate_project()
          input.shortcuts.keypressed['ctrl+alt+pause'] =
              function() project_ran = true; return true end
          love.state.app_state = 'running'
          F.session.press('lctrl')
          F.session.press('lalt')
          F.session.press('pause')
          assert.equal('running', love.state.app_state)
          assert.is_true(project_ran)
        end)

      it('ctrl+shift+q does not stop the run; the project'
        .. ' binding runs instead', function()
          local project_ran = false
          local input = F.activate_project()
          input.shortcuts.keypressed['ctrl+shift+q'] =
              function() project_ran = true; return true end
          F.session.press('lctrl')
          F.session.press('lshift')
          F.session.press('q')
          assert.equal('running', love.state.app_state)
          assert.is_true(project_ran)
        end)

      it('ctrl+alt+q does not stop the run; the project'
        .. ' binding runs instead', function()
          local project_ran = false
          local input = F.activate_project()
          input.shortcuts.keypressed['ctrl+alt+q'] =
              function() project_ran = true; return true end
          F.session.press('lctrl')
          F.session.press('lalt')
          F.session.press('q')
          assert.equal('running', love.state.app_state)
          assert.is_true(project_ran)
        end)

      -- Neither ctrl+shift+s nor bare ctrl+s does anything in
      -- the editor (ctrl+shift+s left it until it was dropped
      -- on 2026-11-14). The upstream editor
      -- rework deleted our close and made leaving Shift+Esc,
      -- and it holds the product authority on that key (owner,
      -- 2026-09-04). It does NOT claim the key — its
      -- checkpoint is Ctrl+K (technical_debt/input.md,
      -- T-CTRL-S-UNCLAIMED) — so what this pair
      -- pins is the exactness itself, which is the point of
      -- D-EXACT-RESERVE: two combos that share a trigger are
      -- decided separately, and a stray `not Key.shift()` here
      -- would still be wrong. CC's own methods are stubbed so
      -- the branch taken is observable without
      -- EditorController's real machinery — the same
      -- avoidance the running-state pair above takes.
      it('ctrl+shift+s leaves the editor alone', function()
          local called = false
          love.state.app_state = 'editor'
          F.cc.editor:open('t.lua', '', function()
            return true
          end)
          local orig = F.cc.finish_edit
          F.cc.finish_edit = function() called = true end
          F.session.press('lctrl')
          F.session.press('lshift')
          F.session.press('s')
          F.cc.finish_edit = orig
          assert.is_false(called)
        end)

      it('bare ctrl+s leaves the editor alone',
        function()
          local closed, finished
          love.state.app_state = 'editor'
          F.cc.editor:open('t.lua', '', function()
            return true
          end)
          local orig_c = F.cc.close_buffer
          local orig_f = F.cc.finish_edit
          F.cc.close_buffer = function() closed = true end
          F.cc.finish_edit = function() finished = true end
          F.session.press('lctrl')
          F.session.press('s')
          F.cc.close_buffer = orig_c
          F.cc.finish_edit = orig_f
          assert.is_nil(closed)
          assert.is_nil(finished)
        end)

      -- love.PROFILE is restored to false BEFORE asserting: the
      -- module-load-time guard in controller.profiler.lua
      -- captures love.PROFILE once, so leaving it truthy past a
      -- failed assertion here breaks Controller.report() in
      -- every later test's F.reset().
      it('f10 still cycles the FPS overlay unmodified',
        function()
          love.PROFILE = { fpsc = 'off' }
          F.session.press('f10')
          local fpsc = love.PROFILE.fpsc
          love.PROFILE = false
          assert.equal('T_L_B', fpsc)
        end)

      it('ctrl+f10 no longer cycles; the project binding'
        .. ' runs instead', function()
          love.PROFILE = { fpsc = 'off' }
          local project_ran = false
          local input = F.activate_project()
          input.shortcuts.keypressed['ctrl+f10'] =
              function() project_ran = true; return true end
          F.session.press('lctrl')
          F.session.press('f10')
          local fpsc = love.PROFILE.fpsc
          love.PROFILE = false
          assert.equal('off', fpsc)
          assert.is_true(project_ran)
        end)

      -- run anew is Ctrl+R since the ruling of November 14,
      -- late; Ctrl+Alt+R, the teacher's family, is nobody's
      it('ctrl+r restarts', function()
        local calls = drive_stub('C-r')
        assert.is_true(calls.restart)
      end)

      it('ctrl+alt+r no longer restarts', function()
        local calls = drive_stub('C-M-r')
        assert.is_nil(calls.restart)
      end)

      it('ctrl+alt+shift+r no longer restarts', function()
        local calls = drive_stub('C-M-S-r')
        assert.is_nil(calls.restart)
      end)

      -- Ctrl+Shift+R was the reset until 2026-11-14; the key
      -- is dropped, and its extension stays nobody's.
      it('ctrl+shift+r no longer resets', function()
        local calls = drive_stub('C-S-r')
        assert.is_nil(calls.reset)
        assert.is_nil(calls.restart)
      end)

      it('ctrl+alt+shift+r fires neither restart nor reset',
        function()
          local calls = drive_stub('C-M-S-r')
          assert.is_nil(calls.restart)
          assert.is_nil(calls.reset)
        end)
    end)

  -- Reserved combos, own effect not yet asserted here (named
  -- gaps, not failures — doc/development/tests.md, "Input
  -- Contract Suite"). ctrl+pause and ctrl+q are omitted: their
  -- own effect is already asserted live above (this file), and
  -- ctrl+pause's also in input_shortcuts_click_spec.lua — so
  -- listing them again as gaps would misstate coverage.
  -- ctrl+t left the list on 2026-09-09 for that same reason,
  -- once both its arms were covered: the running one above
  -- ("still quickswitches while running"), the editor one in
  -- input_editor_keys_spec.lua ("Ctrl+T leaves and runs").
  -- reserved_quickswitch has no third arm. ctrl+r left it on
  -- 2026-11-14, when it replaced ctrl+alt+r, for the same
  -- reason: input_run_anew_spec.lua runs the project with it
  -- from the console, the editor and over a running program,
  -- and holds it back under the editor's card; the refusal
  -- during an edit is in is1_files_spec.lua and
  -- input_editor_files_spec.lua, and program_canvas_spec.lua
  -- sees the program start again.
  describe('reserved combos, own effect not yet asserted',
    function()

      pending('ctrl+alt+p / ctrl+alt+shift+p start/stop the'
        .. ' oneshot profiler (love.PROFILE gated)')
      -- Disagreement with the enumeration read off the source
      -- by the parent session: the code has no modifier gate on
      -- f10 at all (controller.lua, the profile() local) — it
      -- cycles on bare f10 regardless of any modifier held, not
      -- only "with no modifier".
      pending('f10 cycles the FPS-corner overlay'
        .. ' (love.PROFILE gated)')
      pending('ctrl+escape (release) asks love to quit')
    end)
end)
