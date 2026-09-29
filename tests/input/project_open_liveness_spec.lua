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

  --- the micro:bit link: a quit lets the board go, closing
  --- its connection, and waits while a file goes to the board
  --- when the person asked for it
  describe('with a micro:bit', function()
    local kept, keptSerial, port
    before_each(function()
      kept, keptSerial = _G.SerialPort, _G.Serial
      _G.Serial = _G.Serial or {}
      port = { flashing = false, stops = 0, abandons = 0 }
      function port:isFlashing() return self.flashing end
      function port:stop() self.stops = self.stops + 1 end
      function port:abandon()
        self.abandons = self.abandons + 1
        self.flashing = false
      end
      _G.SerialPort = port
    end)
    after_each(function()
      _G.SerialPort, _G.Serial = kept, keptSerial
    end)

    it('lets the board go as the app quits', function()
      stub_stop()
      local aborted = love.quit()
      assert.is_not_true(aborted)
      assert.are.equal(1, port.stops)
    end)

    --- the error screen can leave without love.quit
    it('lets the board go before an error is shown, once',
      function()
        local shown
        local kept = love.errhand
        love.errhand = function(msg) shown = msg return 'loop' end
        Controller.set_love_quit(F.cc)
        Controller.set_love_quit(F.cc)
        local result = love.errhand('boom')
        love.errhand = kept
        assert.are.equal(1, port.stops)
        assert.are.equal('boom', shown)
        assert.are.equal('loop', result)
      end)

    --- the error screen is the one thing the person sees then
    it('says on the error screen that a flash was cut off',
      function()
        local shown
        local kept = love.errhand
        love.errhand = function(msg) shown = msg end
        Controller.set_love_quit(F.cc)
        port.stop = function() return 'A file was going.' end
        love.errhand('boom')
        love.errhand = kept
        assert.are.equal('boom\n\nA file was going.', shown)
      end)

    it('shows the error even when letting the board go fails',
      function()
        local shown
        local kept = love.errhand
        love.errhand = function(msg) shown = msg end
        Controller.set_love_quit(F.cc)
        port.stop = function() error('usb gone') end
        love.errhand('boom')
        love.errhand = kept
        assert.are.equal('boom', shown)
      end)

    --- a quit the person asked for (Ctrl+Esc, quit()) goes
    --- through Application.request_exit
    local function asked_quit()
      local event = love.event
      love.event = { quit = function() end }
      require('util.application').request_exit()
      love.event = event
      return love.quit()
    end

    it('stays, and says so, when asked to quit while a file'
      .. ' goes to the board', function()
        local calls = stub_stop()
        port.flashing = true
        local print_ = _G.print
        local said
        _G.print = function(text) said = text end
        local aborted = asked_quit()
        _G.print = print_
        assert.is_true(aborted)
        assert.are.equal(0, port.stops)
        assert.are.equal(0, port.abandons)
        assert.are.equal(0, calls.n)
        assert.truthy(said:find('still going to the micro:bit', 1,
          true))
        assert.truthy(said:find('quit again', 1, true))
      end)

    --- Android closing the IDE waits for it: refusing could
    --- hang the app
    it('never refuses a quit Android asks for: the flash ends'
      .. ' first', function()
        stub_stop()
        port.flashing = true
        local aborted = love.quit()
        assert.is_not_true(aborted)
        assert.are.equal(1, port.abandons)
        assert.are.equal(1, port.stops)
      end)

    --- a quit that only stops a project leaves the IDE, and the
    --- flash in it, running
    it('leaves a flash going when the quit only stops a project',
      function()
        local calls = stub_stop()
        port.flashing = true
        love.state.app_state = 'running'
        local aborted = love.quit()
        assert.is_true(aborted)
        assert.are.equal(1, calls.n)
        assert.are.equal(0, port.abandons)
        assert.are.equal(0, port.stops)
      end)

    it('takes a project\'s push of quit as asked for', function()
      stub_stop()
      local event = love.event
      love.event = { quit = function() end, push = function() end }
      Controller.set_love_quit(F.cc)
      port.flashing = true
      local print_ = _G.print
      _G.print = function() end
      love.event.push('quit')
      local stay = love.quit()
      _G.print = print_
      love.event = event
      assert.is_true(stay)
      assert.are.equal(0, port.abandons)
    end)

    --- Ctrl+Esc refused during a flash must not close the IDE
    --- on a later quit that only stops a project
    it('forgets a refused Ctrl+Esc', function()
      local calls = stub_stop()
      port.flashing = true
      local print_ = _G.print
      _G.print = function() end
      local event = love.event
      love.event = { quit = function() end }
      require('util.application').request_application_exit()
      love.event = event
      assert.is_true(love.quit())
      _G.print = print_
      port.flashing = false
      love.state.app_state = 'running'
      assert.is_true(love.quit())
      assert.are.equal(1, calls.n)
    end)

    --- a project's own love.event.quit, as pong's Esc, is a
    --- quit asked for from inside the app
    it('takes a project\'s quit as asked for', function()
      stub_stop()
      local event = love.event
      love.event = { quit = function() end }
      Controller.set_love_quit(F.cc)
      port.flashing = true
      local print_ = _G.print
      local said
      _G.print = function(text) said = text end
      love.event.quit()
      local stay = love.quit()
      _G.print = print_
      love.event = event
      assert.is_true(stay)
      assert.are.equal(0, port.abandons)
      assert.truthy(said:find('quit again', 1, true))
    end)

    it('asks once: the next quit is Android\'s', function()
      stub_stop()
      port.flashing = true
      local print_ = _G.print
      _G.print = function() end
      asked_quit()
      _G.print = print_
      local aborted = love.quit()
      assert.is_not_true(aborted)
      assert.are.equal(1, port.abandons)
    end)
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
