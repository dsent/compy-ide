-- Availability: changed by the Compy input API
-- (1.0.0-rc20260712).

-- What this file is about, in one paragraph.
--
-- A program that can still act owns all input (the
-- maintainer's ruling of November 17, 2026: "hide the console
-- when any program runs/all input is the program's while it
-- runs"). While it has an update or a draw, a hook or a
-- shortcut on any channel, its own shown field, or a serial
-- handler, no key, text, pointer or touch event it leaves
-- reaches the console: the event goes nowhere. A program that
-- can no longer act has ended at its last line, and the input
-- is the console's again, so a program whose whole body is
-- `print('help')` leaves the prompt below it typeable.

local F = require('tests.helpers.input_fixture')

describe('input surface: inbound events — the console has them'
  .. ' only from a program that cannot act #input', function()
  setup(function() F.setup() end)
  teardown(function() F.teardown() end)
  before_each(function() F.reset() end)

  -- Backspace is the witness: it mutates the console's own
  -- content, and it travels love.handlers exactly as a real
  -- keystroke does (tests/helpers/input_session.lua). 'ab'
  -- becomes 'a' if the key arrived and stays 'ab' if the
  -- project route ate it.
  local function backspace_at_the_prompt()
    F.console:clear()
    F.console:add_text('ab')
    F.session.press('backspace')
    F.session.release('backspace')
    return F.console:get_text()
  end

  local function text_at_the_prompt()
    F.console:clear()
    F.console:add_text('ab')
    F.session.type('x')
    return F.console:get_text()
  end

  -- The regression this pays: at the PR base a project that
  -- defined no keyboard handler never took love.keypressed,
  -- so the prompt stayed live once the run returned
  -- (doc/development/technical_debt/input.md,
  -- T-ROUTE-EATS-UNCONSUMED).
  it('a program that can do nothing leaves the prompt live',
    function()
      F.activate_project({ })
      assert.same({ 'a' }, backspace_at_the_prompt())
      assert.same({ 'abx' }, text_at_the_prompt())
    end)

  it('a program that owns the screen keeps the console deaf',
    function()
      F.activate_project({ draw = function() end })
      assert.same({ 'ab' }, backspace_at_the_prompt())
    end)

  --- the program's input, whether or not it takes the key: an
  --- update is enough (November 17)
  it('a program with an update keeps the console deaf', function()
    F.activate_project({ update = function() end })
    assert.same({ 'ab' }, backspace_at_the_prompt())
    assert.same({ 'ab' }, text_at_the_prompt())
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

  it('an explicit hook returning falsey keeps the console deaf',
    function()
      local input = F.activate_project({ })
      input.hooks.keypressed = function() return false end
      assert.same({ 'ab' }, backspace_at_the_prompt())
    end)

  describe('every way a program can act owns all input', function()
    local TAKERS = {
      { 'a keypressed hook', function(input)
        input.hooks.keypressed = function() return false end
      end },
      { 'a textinput hook', function(input)
        input.hooks.textinput = function() return false end
      end },
      { 'a pointer hook', function(input)
        input.hooks.mousepressed = function() end
      end },
      { 'a touch hook', function(input)
        input.hooks.touchpressed = function() end
      end },
      { 'a key shortcut for another key', function(input)
        input.shortcuts.keypressed['ctrl+k'] = function() return true end
      end },
      { 'a pointer shortcut', function(input)
        input.shortcuts.mousepressed['ctrl+*'] = function() end
      end },
      { 'a serial handler', function()
        SerialPort:table_for('program').onLine = function() end
      end },
    }
    for _, t in ipairs(TAKERS) do
      it(t[1] .. ': neither a key nor its text reaches the console',
        function()
          t[2](F.activate_project({ }))
          finally(function()
            SerialPort:table_for('program').onLine = nil
          end)
          assert.same({ 'ab' }, backspace_at_the_prompt())
          assert.same({ 'ab' }, text_at_the_prompt())
        end)
    end

    it('its own shown field: nothing reaches the console', function()
      F.activate_project({ })
      F.show_widget({ })
      assert.same({ 'ab' }, backspace_at_the_prompt())
    end)

    it('a pointer event reaches no console behind it', function()
      local x, y = F.cfg.view.fw * 1.2,
          love.graphics.getHeight() - F.cfg.view.fh * 0.5
      F.activate_project({ update = function() end })
      F.console:clear()
      F.console:add_text('abcd')
      F.session.mousepressed(x, y, 1, false, 1)
      F.session.mousereleased(x, y, 1, false, 1)
      assert.same({ 1, 5 }, { F.cc.input:get_cursor_pos() })
    end)
  end)

  --- the same predicate, asked as each event comes
  it('a hook taken away gives the input back to the console',
    function()
      local input = F.activate_project({ })
      input.hooks.keypressed = function() return false end
      assert.same({ 'ab' }, backspace_at_the_prompt())
      input.hooks.keypressed = nil
      assert.same({ 'a' }, backspace_at_the_prompt())
    end)

  it('an own handler whose hook was taken away cannot act',
    function()
      local input = F.activate_project({
        keyreleased = function() end,
      })
      input.hooks.keyreleased = nil
      assert.same({ 'a' }, backspace_at_the_prompt())
    end)

  -- The other side of the same boundary, and the reason a
  -- seeded handler is wrapped at all
  -- (doc/development/decisions/input.md, D-HOOKS-SEEDED,
  -- "AMENDED 2026-09-08 — a seeded handler consumes").
  it('a seeded legacy handler shields the console too',
    function()
      local got = 0
      F.activate_project({
        keypressed = function() got = got + 1 end,
      })
      assert.same({ 'ab' }, backspace_at_the_prompt())
      assert.equal(1, got)
    end)

  -- The console installs ten channels and the project route
  -- binds twelve, the two derived clicks having no console
  -- default by design (controller.lua, `_defaults`: "The derived
  -- clicks have none"). So an unconsumed derived click goes
  -- nowhere, and that path must not raise.
  it('an unconsumed derived click goes nowhere', function()
    F.activate_project({ })
    F.set_mouse_pos(10, 540)
    F.session.mousereleased(10, 540, 1, false, 1)
    assert.has_no.errors(function() F.love_update(0.5) end)
  end)
end)
