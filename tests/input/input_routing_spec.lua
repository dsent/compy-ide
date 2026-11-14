-- Availability: predates the Compy input API (introduced in
-- 1.0.0-rc20260712).

-- The mode x channel routing grid — console, editor, project
-- run — against the rule that each event
-- reaches exactly ONE route
-- (doc/development/decisions/input.md, D-ROUTE-OWNS).

local F = require('tests.helpers.input_fixture')

describe('input surface: inbound events — routing #input',
  function()
  setup(function() F.setup() end)
  teardown(function() F.teardown() end)
  before_each(function() F.reset() end)

  -- ====================================================
  -- Preserved routing invariant — behaviour that predates the
  -- Compy input API and was kept by it.  Keyboard, text and
  -- pointer are EXCLUSIVE on the active route
  -- (doc/development/decisions/input.md, D-ROUTE-OWNS and
  -- D-CHAIN-OF-3; doc/development/internals/user_input.md,
  -- "Dispatch chain"): the mode-fixed route receives, the
  -- others do not. One subgroup per mode below, so a missing
  -- mode x channel cell is visible on sight (the routing
  -- invariant, doc/development/decisions/input.md D-ROUTE-OWNS,
  -- applied per mode x channel). Every test in this group fires
  -- its events through the installed love.handlers entries —
  -- the same dispatch path a real keystroke takes — via the
  -- driver in tests/helpers/input_session.lua.
  -- ====================================================

  describe('routing: console mode', function()

    
    -- Setup seeds text via the model; the assertion path
    -- (backspace) travels love.handlers to the console, so
    -- routing itself is what is witnessed
    -- (doc/development/decisions/input.md, D-ROUTE-OWNS and
    -- D-CHAIN-OF-3; doc/development/internals/user_input.md,
    -- "Dispatch chain").
    it('routes keys to the console', function()
      F.console:add_text('ab')
      F.session.press('backspace')
      assert.same({ 'a' }, F.console:get_text())
      assert.is_true(F.cc.editor.input:is_empty())
    end)

    -- (doc/development/decisions/input.md, D-ROUTE-OWNS and
    -- D-CHAIN-OF-3; doc/development/internals/user_input.md,
    -- "Data flow").
    it('routes text to the console', function()
      F.session.type('Z')
      assert.same({ 'Z' }, F.console:get_text())
      assert.is_true(F.cc.editor.input:is_empty())
    end)

    -- SURFACED GAP (doc/development/internals/user_input.md,
    -- "Key release"): console delivery of a release has no
    -- observable mutation today (a release carries no text), so
    -- only the project route is directly witnessed. Named here
    -- so the cell is visible, not silent.
    pending('routes the key release to the console')

    -- A click places the console's cursor, which witnesses
    -- active-route pointer delivery: the text was set with the
    -- cursor at its end (doc/development/internals/
    -- user_input.md, "Input widget mouse").
    it('routes the pointer to the console', function()
      F.console:set_text({ 'aa', 'bb', 'cc' })
      local before = { F.console:get_cursor_pos() }
      F.session.mousepressed(10, 540, 1, false, 1)
      assert.are_not.same(before, { F.console:get_cursor_pos() })
    end)
  end)

  describe('routing: editor mode', function()

    before_each(function()
      love.state.app_state = 'editor'
      F.cc.editor:open('t.lua', '', function()
        return true
      end)
    end)

    -- The key channel witnessed on its own: text arrives via
    -- textinput, then a KEY event (backspace) mutates the
    -- editor buffer — travelling the same gate.
    -- (doc/development/decisions/input.md, D-ROUTE-OWNS and
    -- D-CHAIN-OF-3; doc/development/internals/user_input.md,
    -- "Dispatch chain").
    it('routes keys to the editor', function()
      F.session.type('q')
      F.session.press('backspace')
      assert.is_true(F.cc.editor.input:is_empty())
      assert.is_true(F.console:is_empty())
    end)

    -- (doc/development/decisions/input.md, D-ROUTE-OWNS and
    -- D-CHAIN-OF-3; doc/development/internals/user_input.md,
    -- "Data flow").
    it('routes text to the editor', function()
      F.session.type('q')
      assert.same({ 'q' }, F.cc.editor.input:get_text())
      assert.is_true(F.console:is_empty())
    end)

    -- keyreleased under editor: the editor route defines NO
    -- keyreleased entry at all (EditorController has none —
    -- only ConsoleController does, consoleController.lua
    -- "ConsoleController:keyreleased"), so there is nothing
    -- observable on the editor side to assert.
    -- Mechanism-by-omission, the same shape as the wheel gap in
    -- input_nfr_mechanism_spec. What IS assertable, and is the
    -- routing claim this grid cell exists for, is EXCLUSIVITY —
    -- the release does not leak to the console
    -- (doc/development/decisions/input.md, D-ROUTE-OWNS;
    -- doc/development/internals/user_input.md, "Key release").
    it('a key release under editor does not reach the console',
      function()
        F.console:add_text('ab')
        F.session.press('backspace')
        F.session.release('backspace')
        assert.same({ 'ab' }, F.console:get_text())
        assert.is_true(F.cc.editor.input:is_empty())
      end)

    -- Pointer under editor is routed
    -- (ConsoleController:mousepressed forwards to
    -- self.editor.input when app_state == 'editor') but the
    -- forward is CONFIG-GATED on cfg.editor.mouse_enabled,
    -- which production ships as FALSE (src/main.lua, the editor
    -- config block). So the cell is not an untested behaviour —
    -- it is a behaviour switched off by default. A test would
    -- have to flip the flag and would then assert something the
    -- shipped configuration never does; left pending
    -- deliberately, to be filled if/when editor mouse is
    -- enabled by default
    -- (doc/development/internals/user_input.md, "Input widget
    -- mouse").
    pending('routes the pointer to the editor')
  end)

  describe('routing: project run', function()

    -- The project's sandboxed love.* handler witnesses
    -- witnessing delivery to the project route.
    -- (doc/development/decisions/input.md, D-ROUTE-OWNS and
    -- D-CHAIN-OF-3; doc/development/internals/user_input.md,
    -- "Dispatch chain").
    it('routes keys to the project', function()
      local got = { }
      F.activate_project({ keypressed = function(k)
        got[#got + 1] = k
      end })
      F.session.press('a')
      assert.same({ 'a' }, got)
      assert.is_true(F.console:is_empty())
    end)

    -- (doc/development/decisions/input.md, D-ROUTE-OWNS and
    -- D-CHAIN-OF-3; doc/development/internals/user_input.md,
    -- "Data flow").
    it('routes text to the project', function()
      local got = { }
      F.activate_project({ textinput = function(t)
        got[#got + 1] = t
      end })
      F.session.type('Z')
      assert.same({ 'Z' }, got)
      assert.is_true(F.console:is_empty())
    end)

    -- A release carries no text mutation, so exclusivity is
    -- observed at the project's release callback: the active
    -- route receives exactly once.
    -- (doc/development/internals/user_input.md, "Key release").
    it('routes the key release to the project', function()
      local got = 0
      F.activate_project({ keyreleased = function()
        got = got + 1
      end })
      F.session.release('a')
      assert.equal(1, got)
    end)

    -- Negative control: the console is seeded with the SAME
    -- text and coordinates that produce a selection in the
    -- console-mode test above; with the project route active no
    -- selection may appear — the pointer went to exactly one
    -- route. (doc/development/internals/user_input.md, "Direct
    -- mouse events").
    it('routes the pointer to the project', function()
      local got = 0
      F.activate_project({ mousepressed = function()
        got = got + 1
      end })
      F.console:set_text({ 'aa', 'bb', 'cc' })
      F.session.mousepressed(10, 540, 1, false, 1)
      assert.equal(1, got)
      assert.is_false(F.console.model:has_selection())
    end)

    -- SURFACED GAP (doc/development/internals/user_input.md,
    -- "Touch"): touch has no gateway entry today and both the
    -- widget and route touch handlers are no-ops, so delivery
    -- is not black-box observable. Greens when a touch consumer
    -- lands.
    pending('touch reaches the active route')
  end)
end)
