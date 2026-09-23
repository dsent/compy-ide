-- Availability: changed by the Compy input API
-- (1.0.0-rc20260712).

-- What this file is about, in one paragraph.
--
-- A project's top-level code runs and finishes. Most projects
-- keep working after that because they hooked love.update or
-- love.draw — the framework calls them every frame. But a
-- project can also be a prompt or a clickable sheet of paper:
-- no update, no draw, just an input widget or a pointer
-- handler. Nothing calls it per frame, so the framework has to
-- decide whether such a project is still ALIVE or is just a
-- console sitting idle.
--
-- The answer (doc/development/technical_debt/input.md,
-- "Input-only / pointer-only projects stay live in
-- `project_open` (RESOLVED, ruling a)"): a shown input widget
-- or an installed pointer handler counts as alive. Alive means
-- two things a user can see — the project keeps receiving
-- events, so Enter still submits; and Ctrl+Esc returns to the
-- console instead of quitting the app. With neither, there is
-- nothing to return FROM and Ctrl+Esc quits.
--
-- 'ready' is the state name for "the project's code has
-- finished but the project has not been stopped".

local F = require('tests.helpers.input_fixture')

describe('input surface: inbound events — a project stays live'
  .. ' without update or draw #input', function()
  -- Fixture is built in setup (not at module load); busted 2
  -- insulates _G/package.loaded per file, so this file runs
  -- standalone too.
  setup(function() F.setup() end)
  teardown(function() F.teardown() end)

  -- Captured after the fixture is built (F.cc is nil before
  -- setup).
  local saved_stop

  local function stub_stop()
    local calls = { n = 0 }
    F.cc.stop_project_run = function() calls.n = calls.n + 1 end
    return calls
  end

  before_each(function()
    F.reset()
    saved_stop = F.cc.stop_project_run
    love.state.user_input = nil
    love.state.app_state = 'ready'
    Controller.set_love_quit(F.cc)
  end)

  after_each(function()
    F.cc.stop_project_run = saved_stop
  end)

  -- Ctrl+Esc runs love.event.quit -> the love.quit handler;
  -- returning true aborts the OS quit (drop to console), a
  -- falsy return lets the process exit. So "returns true" below
  -- reads as "went back to the console instead of quitting".
  it('Ctrl+Esc returns to the console while a widget is shown',
    function()
      local calls = stub_stop()
      love.state.app_state = 'ready'
      love.state.user_input = {}
      local aborted = love.quit()
      assert.are.equal(1, calls.n)
      assert.is_true(aborted)
    end)

  it('Ctrl+Esc quits the app when nothing is left to go back to',
    function()
      local calls = stub_stop()
      love.state.app_state = 'ready'
      love.state.user_input = nil
      local aborted = love.quit()
      assert.are.equal(0, calls.n)
      assert.is_not_true(aborted)
    end)

  it('a shown widget is what makes the project count as alive',
    function()
      love.state.user_input = nil
      assert.is_falsy(Controller.user_is_interactive())
      love.state.user_input = {}
      assert.is_truthy(Controller.user_is_interactive())
    end)

  -- The other half of the rule, and the case the ruling is
  -- named after: a project that shows no widget at all but
  -- installs a pointer handler — a clickable sheet of paper.
  -- Untested until now, though it is the first case the doc
  -- entry lists.
  it('so is a pointer handler, with no widget anywhere',
    function()
      local calls = stub_stop()
      F.activate_project({ mousepressed = function() end })
      love.state.user_input = nil
      love.state.app_state = 'ready'
      assert.is_truthy(Controller.user_is_interactive())
      local aborted = love.quit()
      assert.are.equal(1, calls.n)
      assert.is_true(aborted)
    end)

  -- Alive means events still arrive, not merely that Ctrl+Esc
  -- behaves: the project route is kept, so Enter reaches the
  -- widget and submits exactly as it did while the code ran.
  it('Enter still submits after the project code has finished',
    function()
    local seen
    local input = F.activate_project()
    input.show({
      text = 'x',
      on_text_entered = function(t) seen = t end,
    })
    love.state.app_state = 'ready' -- route NOT released
    F.session.press('return')
    assert.equal('x', seen)
  end)
end)
