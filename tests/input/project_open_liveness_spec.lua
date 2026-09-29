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
local mock = require('tests.mock')

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

  local saved_log
  before_each(function()
    saved_log = rawget(_G, 'orig_print')
    _G.orig_print = function() end
    F.reset()
    saved_stop = F.cc.stop_project_run
    love.state.user_input = nil
    love.state.app_state = 'ready'
    Controller.set_love_quit(F.cc)
  end)

  after_each(function()
    F.cc.stop_project_run = saved_stop
    _G.orig_print = saved_log
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
      function port:update() return {} end
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
      local value
      love.event = { quit = function(v) value = v end }
      require('util.application').request_exit()
      love.event = event
      return love.quit(value)
    end

    --- love.event as the IDE wraps it, the values of the quit
    --- events pushed kept in order
    local function wrapped_event()
      local pushed = {}
      love.event = {
        quit = function(v) pushed[#pushed + 1] = v end,
        push = function(name, v)
          if name == 'quit' then pushed[#pushed + 1] = v end
        end,
      }
      Controller.set_love_quit(F.cc)
      return pushed
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
        assert.truthy(said:find('while a file goes to the'
          .. ' micro:bit', 1, true))
        assert.truthy(said:find('you can quit', 1, true))
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
      local pushed = wrapped_event()
      port.flashing = true
      local print_ = _G.print
      _G.print = function() end
      love.event.push('quit')
      local stay = love.quit(pushed[1])
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
      local value
      love.event = { quit = function(v) value = v end }
      require('util.application').request_application_exit()
      love.event = event
      assert.is_true(love.quit(value))
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
      local pushed = wrapped_event()
      port.flashing = true
      local print_ = _G.print
      local said
      _G.print = function(text) said = text end
      love.event.quit()
      local stay = love.quit(pushed[1])
      _G.print = print_
      love.event = event
      assert.is_true(stay)
      assert.are.equal(0, port.abandons)
      assert.truthy(said:find('you can quit', 1, true))
    end)

    --- Android waits for its quit on its UI thread: an IDE
    --- that stayed would hold it for good
    it('leaves on Android\'s quit on Android, a project running',
      function()
        local calls = stub_stop()
        port.flashing = true
        love.state.app_state = 'running'
        local system = love.system
        love.system = { getOS = function() return 'Android' end }
        local window = love.window
        local minimized = 0
        love.window = {
          minimize = function() minimized = minimized + 1 end,
        }
        local aborted = love.quit()
        love.system, love.window = system, window
        assert.is_not_true(aborted)
        assert.are.equal(1, calls.n)
        assert.are.equal(1, port.abandons)
        assert.are.equal(1, port.stops)
        -- the window goes to the back, as for any quit
        assert.are.equal(1, minimized)
      end)

    --- each quit asked for is one event: a second in the same
    --- frame is asked for too
    it('refuses both of two quits asked for at once', function()
      stub_stop()
      local event = love.event
      local pushed = wrapped_event()
      port.flashing = true
      local print_ = _G.print
      _G.print = function() end
      love.event.quit()
      love.event.quit()
      local first = love.quit(pushed[1])
      local second = love.quit(pushed[2])
      _G.print = print_
      love.event = event
      assert.is_true(first)
      assert.is_true(second)
      assert.are.equal(0, port.abandons)
    end)

    --- a quit asked for whose event Android dropped takes its
    --- tag with it: Android's own quit, untagged, is not asked
    it('takes an untagged quit for Android\'s, after a dropped'
      .. ' one', function()
        stub_stop()
        local event = love.event
        wrapped_event()
        love.event.quit()
        love.event = event
        port.flashing = true
        local aborted = love.quit(nil)
        assert.is_not_true(aborted)
        assert.are.equal(1, port.abandons)
      end)

    --- a project's own quit with a status, as love.event.quit(0)
    --- or love.event.quit('restart'), is asked for too
    it('takes a project\'s quit with a status as asked for',
      function()
        stub_stop()
        local event = love.event
        local pushed = wrapped_event()
        port.flashing = true
        local print_ = _G.print
        _G.print = function() end
        love.event.quit(0)
        love.event.quit('restart')
        love.event.push('quit', 3)
        local stays = { love.quit(pushed[1]), love.quit(pushed[2]),
          love.quit(pushed[3]) }
        _G.print = print_
        love.event = event
        assert.same({ true, true, true }, stays)
        assert.are.equal(0, port.abandons)
        local app = require('util.application')
        assert.same({ true, 0 }, { app.untag(pushed[1]) })
        assert.same({ true, 'restart' }, { app.untag(pushed[2]) })
        assert.same({ true, 3 }, { app.untag(pushed[3]) })
      end)

    --- a project's quit that fails, on Android's own quit:
    --- the IDE still leaves, and says why in the log
    it('leaves on Android\'s quit even when the quit fails',
      function()
        F.cc.stop_project_run = function() error('stop broke') end
        port.flashing = true
        love.state.app_state = 'running'
        local system, window = love.system, love.window
        local minimized = 0
        love.system = { getOS = function() return 'Android' end }
        love.window = {
          minimize = function() minimized = minimized + 1 end,
        }
        local logged = ''
        _G.orig_print = function(l) logged = logged .. l end
        local aborted = love.quit()
        love.system, love.window = system, window
        assert.is_not_true(aborted)
        assert.are.equal(1, port.stops)
        assert.are.equal(1, minimized)
        assert.truthy(logged:find('stop broke', 1, true))
      end)

    it('shows the error when a quit asked for fails', function()
      F.cc.stop_project_run = function() error('stop broke') end
      love.state.app_state = 'running'
      local app = require('util.application')
      assert.has_error(function() love.quit(app.quit_tag()) end)
      assert.are.equal(0, port.stops)
    end)

    --- the error screen, once left, ends the run: its window
    --- goes to the back, so Android starts the IDE again
    it('sends the window to the back as the error screen ends',
      function()
        local kept = love.errhand
        local ends = false
        love.errhand = function()
          return function() if ends then return 1 end end
        end
        Controller.errhand = nil
        Controller.set_love_quit(F.cc)
        local loop = love.errhand('boom')
        love.errhand = kept
        local system, window = love.system, love.window
        local minimized = 0
        love.system = { getOS = function() return 'Android' end }
        love.window = {
          minimize = function() minimized = minimized + 1 end,
        }
        assert.is_nil(loop())
        assert.are.equal(0, minimized)
        ends = true
        assert.are.equal(1, loop())
        love.system, love.window = system, window
        assert.are.equal(1, minimized)
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

  --- a project quits through its own copy of love, made
  --- when the console was built: every way it has goes out
  --- tagged, so the IDE never reads it as Android's quit (which
  --- would end the IDE, where a project's quit only stops it)
  it('tags every quit a project sends through its own love',
    function()
      F.quits()
      F.run_source([[
        love.event.quit()
        love.event.quit(0)
        love.event.quit('restart')
        love.event.push('quit')
        local saved = love.event.quit
        saved(3)
      ]])
      local got = F.quits()
      local app = require('util.application')
      local statuses = {}
      for i, q in ipairs(got) do
        local asked, status = app.untag(q[1])
        assert.is_true(asked, 'quit ' .. i)
        statuses[i] = status == nil and 'none' or status
      end
      assert.same({ 'none', 0, 'restart', 'none', 3 }, statuses)
      -- the project's love is a copy, not the IDE's own
      local env = F.cc:get_project_env()
      assert.are_not.equal(love.event, env.love.event)
    end)

  --- the console is built before love.quit's wrappers go on
  --- (main.lua): the copy a project gets must already tag
  it('gives projects a love.event that tags, copied in main.lua\'s'
    .. ' order', function()
      local pre = F.cc:get_pre_env_c()
      assert.are.equal(love.event.quit, pre.love.event.quit)
      assert.are.equal(love.event.push, pre.love.event.push)
      local app = require('util.application')
      F.quits()
      pre.love.event.quit()
      assert.is_true((app.untag(F.quits()[1][1])))
    end)

  --- Android: a project's quit, love.event.quit() or a pushed
  --- one, stops the project, and the IDE stays with the
  --- console, as it always has
  for _, how in ipairs({ 'love.event.quit()',
    "love.event.push('quit')" }) do
    it('keeps the IDE when a running project on Android runs '
      .. how, function()
        local calls = stub_stop()
        F.quits()
        F.run_source(how)
        local got = F.quits()
        assert.are.equal(1, #got)
        local system, window = love.system, love.window
        local minimized = 0
        love.system = { getOS = function() return 'Android' end }
        love.window = {
          minimize = function() minimized = minimized + 1 end,
        }
        love.state.app_state = 'running'
        -- the stubs go back even when the quit raises
        local ok, stay = pcall(love.quit, got[1][1])
        love.system, love.window = system, window
        assert(ok, stay)
        assert.is_true(stay)
        assert.are.equal(1, calls.n)
        assert.are.equal(0, minimized)
      end)
  end

  --- Ctrl+Esc with a board open and no file going to it,
  --- walked as LÖVE walks it: the key's release pushes quit,
  --- love.run's loop polls it and asks love.quit, and boot
  --- runs the loop until it returns. The run must end there:
  --- a quit refused, or an error on the way out, keeps the
  --- old run going (an error screen nobody sees, on a window
  --- gone to the back) while Android starts the IDE again in
  --- the same process
  describe('Ctrl+Esc with a micro:bit open and no flash',
    function()
      local FD = require('tests.helpers.fake_daplink')
      local JNI = { 'jniCallBool', 'jniCallVoid', 'jniCallInt',
        'jniDropGlobal' }
      local kept, calls, shown, minimized, queue, logged

      --- LÖVE 11.5's boot, over the IDE's own love.run: the
      --- frame runs under the error handler, whose loop replaces
      --- it after an error, until a frame returns a value
      local function boot(frames)
        local load, graphics = love.load, love.graphics
        love.load = nil
        love.graphics = setmetatable(
          { isActive = function() return false end },
          { __index = graphics })
        local func = require('util.application').run()
        love.load = load
        local function restore() love.graphics = graphics end
        local function errhand(msg)
          func = (love.errorhandler or love.errhand)(msg)
        end
        for n = 1, frames do
          local _, retval = xpcall(func, errhand)
          if retval then
            restore()
            return retval, n
          end
        end
        restore()
      end

      before_each(function()
        kept = {
          event = love.event, errhand = love.errhand,
          system = love.system, window = love.window,
          port = _G.SerialPort, log = Dap and Dap.log,
          ctrl = Controller.errhand,
          orig_print = rawget(_G, 'orig_print'),
        }
        for _, name in ipairs(JNI) do kept[name] = _G[name] end
        require('model.serial.init')
        require('model.serial.backend_android')
        calls = {}
        _G.jniCallBool = function(_, _, mid, arg)
          calls[#calls + 1] = mid .. ':' .. tostring(arg)
          return true
        end
        _G.jniCallInt = function() return 3 end
        _G.jniCallVoid = function(_, _, mid)
          calls[#calls + 1] = mid
        end
        _G.jniDropGlobal = function() end
        Dap.log = function() end
        logged = ''
        _G.orig_print = function(text)
          logged = logged .. tostring(text) .. '\n'
        end
        queue = {}
        love.event = {
          pump = function() end,
          poll = function()
            return function()
              local e = table.remove(queue, 1)
              if e then return e[1], e[2] end
            end
          end,
          quit = function(status)
            queue[#queue + 1] = { 'quit', status }
          end,
          push = function(name, a)
            queue[#queue + 1] = { name, a }
          end,
        }
        love.system = { getOS = function() return 'Android' end }
        minimized = 0
        love.window = {
          minimize = function() minimized = minimized + 1 end,
        }
        shown = nil
        love.errhand = function(msg)
          shown = msg
          -- the error screen: it waits for a key that never
          -- comes to a window at the back
          return function() end
        end
        Controller.errhand = nil
        local chip = FD.chip()
        local p = {
          conn = 'conn', comm = 'comm', data = 'data',
          msc = 'msc', claimM = 'claim', releaseM = 'release',
          closeM = 'close', fdM = 'fd', ctrlM = 'ctrl',
          bulkM = 'bulk',
          dap = { iface = 'dap', id = 5, inAddr = 0x85,
            outAddr = 0x05, claimed = true },
        }
        p.link = DapLink.new(FD.bus(chip), 0x05, 0x85,
          function() end, function() return chip.now end)
        p.link:start()
        local b = AndroidBackend.new()
        b.start = function(self, sink)
          self.sink = sink
          self.env = 'env'
        end
        b.dev = { dev = 'dev', name = '/dev/bus/usb/001/002' }
        b.openDevice = function() return p end
        _G.SerialPort = Serial.new(b)
        b:openReady()
        Controller.set_love_quit(F.cc)
      end)

      after_each(function()
        love.event, love.errhand = kept.event, kept.errhand
        love.system, love.window = kept.system, kept.window
        _G.SerialPort, Dap.log = kept.port, kept.log
        Controller.errhand = kept.ctrl
        _G.orig_print = kept.orig_print
        for _, name in ipairs(JNI) do _G[name] = kept[name] end
        mock.release_keys()
      end)

      it('ends the run at once, the board let go', function()
        assert.is_true(SerialPort:isConnected())
        assert.is_false(SerialPort:isFlashing())
        local keys = F.session
        keys.press('lctrl')
        keys.press('escape')
        keys.release('escape')
        keys.release('lctrl')
        local retval, frames = boot(10)
        assert.is_nil(shown)
        assert.are.equal(0, retval)
        assert.are.equal(1, frames)
        assert.are.equal(1, minimized)
        assert.is_false(SerialPort:isConnected())
        assert.are.equal('close', calls[#calls])
        assert.truthy(logged:find('Quit accepted', 1, true))
      end)

      local function ctrl_esc()
        local keys = F.session
        keys.press('lctrl')
        keys.press('escape')
        keys.release('escape')
        keys.release('lctrl')
      end

      it('ends the run when the board cannot be let go',
        function()
          _G.jniDropGlobal = function() error('ref gone') end
          ctrl_esc()
          local retval, frames = boot(10)
          assert.is_nil(shown)
          assert.are.equal(0, retval)
          assert.are.equal(1, frames)
          assert.truthy(logged:find('could not be let go', 1,
            true))
        end)

      it('ends the run when the window cannot go to the back',
        function()
          love.window.minimize = function() error('no window') end
          ctrl_esc()
          local retval, frames = boot(10)
          assert.is_nil(shown)
          assert.are.equal(0, retval)
          assert.are.equal(1, frames)
          assert.truthy(logged:find('no window', 1, true))
          assert.is_false(SerialPort:isConnected())
        end)

      --- Android pauses a window at the back, and a run still
      --- going then leaves its pause behind: the window goes
      --- last, once the board is let go
      it('sends the window to the back after the board is let'
        .. ' go', function()
          local closedAtMinimize
          love.window.minimize = function()
            minimized = minimized + 1
            closedAtMinimize = calls[#calls] == 'close'
          end
          ctrl_esc()
          assert.are.equal(0, (boot(10)))
          assert.are.equal(1, minimized)
          assert.is_true(closedAtMinimize)
        end)

      --- an error screen on a window at the back would wait
      --- for a key that never comes
      it('ends the run when an error comes on the way out',
        function()
          Controller.leaving = true
          Controller.home = true
          local loop = love.errhand('boom')
          assert.is_nil(shown)
          assert.are.equal(1, loop())
          assert.are.equal(1, minimized)
          assert.truthy(logged:find('boom', 1, true))
          assert.is_false(SerialPort:isConnected())
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
