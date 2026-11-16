-- Availability: changed by the Compy input API
-- (1.0.0-rc20260712).

-- What this file is about, in one paragraph.
--
-- A project run takes every input channel for the whole run
-- (doc/development/internals/event_dispatch_layers.md,
-- "Layer 2 — `love.<event>`, the active route's handler").
-- The route's walk already reports whether anybody consumed
-- (doc/development/internals/user_input.md, "Dispatch chain"),
-- and this file is about the event nobody did: it goes back
-- to the console, so a project whose whole body is
-- `print('help')` leaves the prompt below it typeable.
--
-- Two gates. The SCREEN: a project that owns love.draw is
-- painting over the console, so nothing falls through to a
-- prompt the user cannot see. And the KEYBOARD (the
-- maintainer's ruling of November 16, 2026: "'Falling through'
-- of only unhandled keys to the console sounds quite
-- unintuitive"): a program that takes keys owns the keyboard,
-- so no key or text it leaves reaches the console. A program
-- that wants typing shows its own field.

local F = require('tests.helpers.input_fixture')

describe('input surface: inbound events — what nobody'
  .. ' consumed reaches the console #input', function()
  setup(function() F.setup() end)
  teardown(function() F.teardown() end)
  before_each(function() F.reset() end)

  -- Backspace is the witness: it mutates the console's own
  -- content, and it travels love.handlers exactly as a real
  -- keystroke does (tests/helpers/input_session.lua). 'ab'
  -- becomes 'a' if the key arrived and stays 'ab' if the
  -- project route ate it.
  local function backspace_at_the_prompt()
    F.console:add_text('ab')
    F.session.press('backspace')
    return F.console:get_text()
  end

  -- The regression this pays: at the PR base a project that
  -- defined no keyboard handler never took love.keypressed,
  -- so the prompt stayed live once the run returned
  -- (doc/development/technical_debt/input.md,
  -- T-ROUTE-EATS-UNCONSUMED).
  it('a project that hooks nothing leaves the prompt live',
    function()
      F.activate_project({ })
      assert.same({ 'a' }, backspace_at_the_prompt())
    end)

  it('a project that owns the screen keeps the console deaf',
    function()
      F.activate_project({ draw = function() end })
      assert.same({ 'ab' }, backspace_at_the_prompt())
    end)

  -- The walk's own contract, restated from the other side:
  -- truthy consumes, and consuming means the console is not
  -- reached (doc/development/decisions/input.md,
  -- D-CHAIN-OF-3).
  it('a hook that consumes stops the walk at the project',
    function()
      local seen = 0
      local input = F.activate_project({ })
      input.hooks.keypressed = function()
        seen = seen + 1
        return true
      end
      assert.same({ 'ab' }, backspace_at_the_prompt())
      assert.equal(1, seen)
    end)

  -- Turned around on November 16, 2026: a hook the project
  -- registered itself and which returns falsey no longer lets
  -- the key through. A program with a key hook takes keys, and
  -- what its chain leaves goes nowhere.
  it('an explicit hook returning falsey keeps the console deaf',
    function()
      local input = F.activate_project({ })
      input.hooks.keypressed = function() return false end
      assert.same({ 'ab' }, backspace_at_the_prompt())
    end)

  --- one predicate for the key and the text paths, asked as each
  --- event comes, since hooks and shortcuts come and go
  describe('a program that takes keys owns the keyboard', function()
    local function text_at_the_prompt()
      F.console:clear()
      F.console:add_text('ab')
      F.session.type('x')
      return F.console:get_text()
    end

    local TAKERS = {
      { 'a keypressed hook', function(input)
        input.hooks.keypressed = function() return false end
      end },
      { 'a keyreleased hook', function(input)
        input.hooks.keyreleased = function() return false end
      end },
      { 'a textinput hook', function(input)
        input.hooks.textinput = function() return false end
      end },
      { 'a key shortcut for another key', function(input)
        input.shortcuts.keypressed['ctrl+k'] = function() return true end
      end },
      { 'a text shortcut', function(input)
        input.shortcuts.textinput['alt+*'] = function() return true end
      end },
    }
    for _, t in ipairs(TAKERS) do
      it(t[1] .. ': neither a key nor its text falls through',
        function()
          t[2](F.activate_project({ }))
          assert.same({ 'ab' }, backspace_at_the_prompt())
          assert.same({ 'ab' }, text_at_the_prompt())
        end)
    end

    for _, own in ipairs({ 'keypressed', 'keyreleased', 'textinput' }) do
      it('its own love.' .. own .. ': neither a key nor its text'
        .. ' falls through', function()
          F.activate_project({ [own] = function() end })
          assert.same({ 'ab' }, backspace_at_the_prompt())
          assert.same({ 'ab' }, text_at_the_prompt())
        end)
    end

    it('its own shown field: nothing reaches the console', function()
      F.activate_project({ })
      F.show_widget({ })
      assert.same({ 'ab' }, backspace_at_the_prompt())
    end)

    --- the shortcut tables are there and empty by default
    it('empty shortcut tables and a pointer hook take no keys',
      function()
        local input = F.activate_project({ })
        assert.is_nil(next(input.shortcuts.keypressed))
        input.hooks.mousepressed = function() end
        assert.same({ 'a' }, backspace_at_the_prompt())
        assert.same({ 'abx' }, text_at_the_prompt())
      end)

    --- round 19: ownership is the program's as the event comes,
    --- not as its chain leaves it
    it('a hook that removes itself keeps that event from the'
      .. ' console', function()
        local input = F.activate_project({ })
        input.hooks.keypressed = function()
          input.hooks.keypressed = nil
          return false
        end
        assert.same({ 'ab' }, backspace_at_the_prompt())
        input.hooks.textinput = function()
          input.hooks.textinput = nil
          return false
        end
        assert.same({ 'ab' }, text_at_the_prompt())
      end)

    --- round 19: the hook table is the one record; an own
    --- handler whose seeded hook the program took away takes no
    --- keys
    it('an own handler whose hook was taken away takes no keys',
      function()
        local input = F.activate_project({
          keyreleased = function() end,
        })
        input.hooks.keyreleased = nil
        assert.same({ 'a' }, backspace_at_the_prompt())
      end)

    it('a hook set and taken back again leaves the keys as it found'
      .. ' them', function()
        local input = F.activate_project({ })
        input.hooks.keypressed = function() return false end
        assert.same({ 'ab' }, backspace_at_the_prompt())
        input.hooks.keypressed = nil
        F.console:clear()
        assert.same({ 'a' }, backspace_at_the_prompt())
      end)
  end)

  -- The other side of the same boundary, and the reason a
  -- seeded handler is wrapped at all
  -- (doc/development/decisions/input.md, D-HOOKS-SEEDED,
  -- "AMENDED 2026-09-08 — a seeded handler consumes"). This
  -- handler returns nothing, as handlers written for LÖVE do;
  -- without the wrap that incidental return would decide
  -- whether the console hears the key, which is base parity
  -- lost by accident.
  it('a seeded legacy handler shields the console too',
    function()
      local got = 0
      F.activate_project({
        keypressed = function() got = got + 1 end,
      })
      assert.same({ 'ab' }, backspace_at_the_prompt())
      assert.equal(1, got)
    end)

  -- Ten against twelve: the console installs ten channels and
  -- the project route binds twelve, the two derived clicks
  -- having no console default by design
  -- (controller.lua, `_defaults`: "The derived clicks have
  -- none"). So an unconsumed derived click falls through to
  -- nothing, and that path must not raise.
  it('an unconsumed derived click falls through to nothing',
    function()
      F.activate_project({ })
      F.set_mouse_pos(10, 540)
      F.session.mousereleased(10, 540, 1, false, 1)
      assert.has_no.errors(function() F.love_update(0.5) end)
    end)
end)
