
-- Availability: predates the Compy input API (introduced in
-- 1.0.0-rc20260712).

-- NFR and mechanism guards. Routing invariant
-- (doc/development/decisions/input.md, D-ROUTE-OWNS):
-- inter-route dispatch is EXCLUSIVE — each event reaches
-- exactly ONE route, fixed by the active screen mode.
-- Vocabulary (doc/development/internals/user_input.md,
-- "Dispatch chain"): ROUTE = the controller an event is
-- dispatched to; WIDGET = the route-managed input surface and
-- terminal of the chain. Tests assert observable outcomes at
-- public seams, never method-name spies. keypressed fires for
-- every physical key, textinput only for character-producing
-- keys (doc/development/internals/user_input.md, "Data flow").

-- Guards on MECHANISM, not on behaviour: object identity and
-- allocation. Nothing here
-- is a project-facing contract — those live in the other
-- input_*_spec.lua files, and a case that turns out to be one
-- belongs there instead.
--
-- The file has been narrowed twice on that test. A wheel case
-- went to input_events_spec.lua when it became one case of
-- "every channel reaches the route"; a characterisation case
-- went entirely, having stopped discriminating.

local F = require('tests.helpers.input_fixture')

describe('input contracts: NFR and mechanism guards #input',
  function()
  setup(function() F.setup() end)
  teardown(function() F.teardown() end)
  before_each(function() F.reset() end)

  -- ====================================================
  -- Characterized behaviour (no stakeholder mandate). De-facto
  -- behaviour that predates the Compy input API, reverse-
  -- engineered and canonicalized here. Each case asserts only
  -- what is verifiably true today, so a deliberate change reads
  -- as expected while an accidental one still fails the build.
  -- (doc/development/tests.md, "Input Contract Suite")
  -- ====================================================
  -- ====================================================
  -- Mechanism / NFR guards — not behaviour contracts. Labelled
  -- so no reader mistakes them for behaviour contracts. These
  -- intentionally poke internals (identity, allocation), which
  -- is exactly what an NFR guard is for.
  -- (doc/development/tests.md, "Input Contract Suite")
  -- ====================================================
  describe('mechanism / NFR guards — not behaviour',
    function()

      -- Singleton identity across show/hide (NFR): today
      -- only the input widget is wired; wiring the
      -- console/editor widgets to it is a future
      -- consideration, deliberately out of scope (see
      -- doc/development/internals/user_input.md: "Key
      -- release", "Dispatch chain",
      -- "Cursor manipulation and \"reset\"" for the related
      -- surfaces), not asserted here.
      it('the widget keeps identity across cycles',
        function()
          F.show_widget()
          local first = love.state.user_input.C
          F.widget:hide()
          F.show_widget()
          assert.equal(first, love.state.user_input.C)
        end)

      -- No reallocation per input session
      -- (doc/development/decisions/input.md, D-WIDGET-AT-BOOT):
      -- the backing model is reused across activations.
      it('no widget model is reallocated', function()
        local m1 = F.widget.model
        F.show_widget()
        F.widget:hide()
        F.show_widget()
        assert.equal(m1, F.widget.model)
      end)

      -- What compy.input keeps for a project — the callbacks
      -- store, and the project-owned config fields — lives ON
      -- the widget, and the surface RESOLVES it rather
      -- than holding it (owner ruling 2026-07-20, re-made
      -- 2026-08-27: compy.input.callbacks resolves to the
      -- current widget's table). Identity is frozen against the
      -- project (D-FROZEN-SHELL) and stable for as long as a
      -- project can observe it; it is not frozen against the
      -- framework replacing the widget underneath.
      it('callbacks resolve to the current widget', function()
        local input = F.compy_input()
        local previous = F.widget
        local other = F.other_widget()
        local f = function() end
        input.callbacks.on_text_entered = f
        assert.equal(f, other.callbacks.on_text_entered)
        assert.not_equal(f, previous.callbacks.on_text_entered)
      end)

      -- The second witness for the same resolve-per-access
      -- rule, on the OTHER path: configure() writes the
      -- project-owned fields through to the widget rather than
      -- into a store the surface holds, so a hidden configure
      -- lands on whichever widget is current at that moment,
      -- not on the one that existed when the surface was
      -- built. (It used to witness this through a one-shot
      -- pending config, which no longer exists -- configure
      -- stopped stashing when text/cursor left its key set.
      -- Pending config itself remains: a hidden configure
      -- still holds project keys until a widget takes them.)
      it('a hidden configure resolves to the current widget',
        function()
          local input = F.compy_input()
          local previous = F.widget
          local other = F.other_widget()
          input.configure({ prompt = 'who?' })
          assert.equal('who?', other.model.custom_label)
          assert.is_nil(previous.model.custom_label)
        end)

      -- Between runs there is no widget and therefore no store.
      -- Every call stays inert rather than raising: the same
      -- rule the rest of the surface already follows.
      it('with no widget there is no store, and no raise',
        function()
          local input = F.compy_input()
          love.state.user_input_controller = nil
          input.configure({ prompt = 'who?' })
          input.show({ text = 'hi' })
          assert.is_nil(input.callbacks)
          assert.is_false(input.is_shown())
        end)
    end)

  -- ====================================================
  -- Teardown, seen from the LÖVE side. The project-facing half
  -- of D-ROUTE-LIFETIME is input_route_lifecycle_spec.lua; this
  -- case watches the same stop from below, where the wiring
  -- actually
  -- lives. ====================================================
  describe('teardown leaves the love.* wiring at defaults',
    function()

      -- D-ROUTE-LIFETIME requires full teardown: after stop no
      -- project handler remains wired in any love.* slot.
      it('stop leaves no project handler wired in any ' ..
          'love.* slot', function()
        F.activate_project()
        assert.is_not.equal(
          Controller._defaults.keypressed, love.keypressed)
        F.cc:stop_project_run()
        assert.equal(
          Controller._defaults.keypressed, love.keypressed)
      end)

    end)
end)
