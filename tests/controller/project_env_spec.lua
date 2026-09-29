--- Headless ConsoleController tests for the unified project
--- environment (issue #106): single env for console + project,
--- env reset on switch, close redirects to the scratchpad, reset_scratchpad.
--- Uses the "Web" FS branch with an lfs-backed mock on a tmpdir.
--- @diagnostic disable: invisible

local lfs = require('lfs')

describe('ConsoleController project env #project', function()
  local FS
  local tmp
  local CC

  local function rm_rf(path)
    if lfs.attributes(path, 'mode') == 'directory' then
      for entry in lfs.dir(path) do
        if entry ~= '.' and entry ~= '..' then
          rm_rf(path .. '/' .. entry)
        end
      end
    end
    return os.remove(path)
  end

  local function mock_love_fs()
    local function attr(path, filtertype)
      local mode = lfs.attributes(path, 'mode')
      if not mode then return nil end
      if filtertype and mode ~= filtertype then return nil end
      return { type = mode }
    end
    return {
      read = function(path)
        local f = io.open(path, 'r')
        if not f then return nil end
        local c = f:read('*a')
        f:close()
        return c
      end,
      write = function(path, data)
        local f = io.open(path, 'w')
        if not f then return nil end
        f:write(data)
        f:close()
        return true
      end,
      lines = function(path) return io.lines(path) end,
      getInfo = attr,
      createDirectory = function(path) return lfs.mkdir(path) end,
      getDirectoryItems = function(path)
        local items = {}
        for entry in lfs.dir(path) do
          if entry ~= '.' and entry ~= '..' then
            table.insert(items, entry)
          end
        end
        return items
      end,
      mount = function() return true end,
      getRequirePath = function() return '' end,
      setRequirePath = function() end,
    }
  end

  local noop = function() end
  --- main_ctrl stub: exactly the methods the touched paths call
  local function fake_main_ctrl()
    return {
      set_default_handlers = noop,
      save_user_handlers = noop,
      clear_user_handlers = noop,
      restore_user_handlers = noop,
      set_love_update = noop,
      set_love_draw = noop,
      user_is_blocking = function() return false end,
      user_is_interactive = function() return false end,
      report = noop,
    }
  end

  setup(function()
    _G.love = _G.love or {}
    love.system = love.system or {
      getOS = function() return 'Web' end,
    }
    love.filesystem = mock_love_fs()
    love.state = { app_state = 'ready' }
    love.graphics = love.graphics or {
      newCanvas = function()
        return {
          renderTo = function(_, f) if f then f() end return true end,
        }
      end,
      getCanvas = function() return nil end,
      setCanvas = function() end,
      clear = function() end,
      origin = function() end,
      push = function() end,
      pop = function() end,
      draw = function() end,
      print = function() end,
      rectangle = function() end,
      setColor = function() end,
      getColor = function() return 0, 0, 0, 0 end,
      setFont = function() end,
      getWidth = function() return 1024 end,
      getHeight = function() return 600 end,
    }
    love.audio = love.audio or {
      newSource = function() return {} end,
    }
    package.preload['utf8'] = function()
      return require('lua-utf8')
    end
    --- metalua lives under src/lib, which LÖVE adds to its own
    --- require path; in tests, extend package.path instead
    package.path = './src/lib/?.lua;./src/lib/?/?.lua;' ..
        './src/lib/metalua/?.lua;' .. package.path
    package.loaded['util.filesystem'] = nil
    FS = require('util.filesystem')
    FS.rm = function(target) return rm_rf(target) end
    require('util.table')
    require('util.dequeue')
    package.loaded['model.project.project'] = nil
    require('model.project.project')
    package.loaded['model.consoleModel'] = nil
    require('model.consoleModel')
    package.loaded['controller.consoleController'] = nil
    require('controller.consoleController')
    --- view.view pulls in real rendering; stub the one call used
    _G.View = { clear_snapshot = function() end }
  end)

  before_each(function()
    tmp = '/tmp/compy_cc_' .. tostring(math.floor(os.clock() * 1e6))
    lfs.mkdir(tmp)
    love.paths = { project_path = tmp }
    love.state.app_state = 'ready'
    ProjectService.path = tmp
    local colors = require('conf.colors')
    local cfg = {
      view = {
        drawableChars = 64,
        lines = 16,
        input_max = 14,
        fh = 32,
        lh = 1,
        w = 1024,
        h = 600,
        font = {
          getWidth = function() return 16 end,
          getHeight = function() return 32 end,
          setLineHeight = function() end,
          setFallbacks = function() end,
        },
        colors = colors,
      },
      editor = {},
      mode = 'ide',
    }
    local M = ConsoleModel(cfg)
    CC = ConsoleController(M, fake_main_ctrl())
  end)

  after_each(function()
    --- close while THIS CC instance (and its loader cache)
    --- is alive, so the project loader is actually removed
    --- from package.loaders
    if CC then
      CC:_close_project()
    end
    if tmp and lfs.attributes(tmp, 'mode') then
      rm_rf(tmp)
    end
  end)

  teardown(function()
    _G.love = nil
    _G.LFS = nil
    package.loaded['util.filesystem'] = nil
  end)

  it('has a single unified env with console commands #project', function()
    CC:open_project(ProjectService.DEFAULT)
    local env = CC:get_project_env()
    for _, k in ipairs({
      'project', 'list_projects', 'current_project', 'close_project',
      'reset_scratchpad', 'readfile', 'readlines', 'writefile', 'loadfile',
      'dofile', 'edit', 'run', 'run_project', 'list_contents',
      'example_projects', 'clone', 'appver', 'quit',
      'pause', 'stop', 'continue', 'eval',
    }) do
      assert.is_function(env[k], k .. ' missing')
    end
    assert.is_table(env.compy)
    assert.is_table(env.tty)
    assert.is_table(env.gfx)
  end)

  it('tidy formats a file of the open project #project', function()
    CC:open_project(ProjectService.DEFAULT)
    local env = CC:get_project_env()
    assert.is_true(FS.write(tmp .. '/' .. ProjectService.DEFAULT
      .. '/tidy_me.lua', 'a  =  1\n\n\n\nb = 2'))
    assert.is_true(env.tidy('tidy_me.lua'))
    assert.same('a = 1\n\nb = 2\n', env.readfile('tidy_me.lua'))
  end)

  it('get_effective_env is always the project env #project', function()
    assert.are.equal(CC:get_project_env(), CC:get_effective_env())
    love.state.app_state = 'running'
    assert.are.equal(CC:get_project_env(), CC:get_effective_env())
    love.state.app_state = 'inspect'
    assert.are.equal(CC:get_project_env(), CC:get_effective_env())
    love.state.app_state = 'ready'
  end)

  it('resets the env on project switch #project', function()
    CC:open_project(ProjectService.DEFAULT)
    CC:get_project_env().x = 5
    CC:open_project('clock')
    assert.is_nil(CC:get_project_env().x)
    --- console commands survive the reset
    assert.is_function(CC:get_project_env().project)
    assert.is_function(CC:get_project_env().reset_scratchpad)
    assert.is_nil(CC:get_project_env().reset_scratch)
  end)

  it('close_project returns to the default project #project', function()
    CC:open_project('clock')
    local ok = CC:close_project()
    assert.is_true(ok)
    assert.are.equal(ProjectService.DEFAULT,
      CC:get_current_project().name)
    assert.are.equal('ready', love.state.app_state)
  end)

  it('close_project from the scratchpad reopens it #project', function()
    CC:open_project(ProjectService.DEFAULT)
    CC:get_project_env().x = 5
    assert.is_true(CC:close_project())
    assert.are.equal(ProjectService.DEFAULT,
      CC:get_current_project().name)
    assert.is_nil(CC:get_project_env().x)
  end)

  it('reset_scratchpad restores factory contents #project', function()
    CC:open_project(ProjectService.DEFAULT)
    CC:get_current_project():writefile('extra.lua', '-- extra')
    assert.is_true(CC:reset_scratchpad())
    assert.are.equal(ProjectService.DEFAULT,
      CC:get_current_project().name)
    local p = FS.join_path(tmp, ProjectService.DEFAULT, 'extra.lua')
    assert.is_false(FS.exists(p))
    local rok, content =
      CC:get_current_project():readfile(ProjectService.MAIN)
    assert.is_true(rok)
    assert.are.equal("print('Hello world!')\n", content)
  end)

  it('reset_scratchpad keeps the old scratchpad, numbered #project',
    function()
      local old = ProjectService.DEFAULT .. '.old'
      CC:open_project(ProjectService.DEFAULT)
      CC:get_current_project():writefile('extra.lua', '-- one')
      assert.is_true(CC:reset_scratchpad())
      CC:get_current_project():writefile('extra.lua', '-- two')
      assert.is_true(CC:reset_scratchpad())
      local function kept(name)
        local f = io.open(FS.join_path(tmp, name, 'extra.lua'))
        if not f then return nil end
        local text = f:read('*a')
        f:close()
        return text
      end
      assert.are.equal('-- one', kept(old))
      assert.are.equal('-- two', kept(old .. '.1'))
      assert.is_nil(kept(ProjectService.DEFAULT))
    end)

  it('close_project says closed before it opens scratchpad #project',
    function()
      CC:open_project(ProjectService.DEFAULT)
      CC:open_project('clock')
      local said = { }
      local print_ = _G.print
      _G.print = function(s) said[#said + 1] = s end
      CC:get_project_env().close_project()
      _G.print = print_
      assert.are.same({
        'Project closed',
        'Project ' .. ProjectService.DEFAULT .. ' opened',
      }, said)
    end)

  it('reset_scratchpad from another project keeps that project #project',
    function()
      CC:open_project('clock')
      assert.is_true(CC:reset_scratchpad())
      assert.are.equal(ProjectService.DEFAULT,
        CC:get_current_project().name)
      assert.is_not_nil(ProjectService.is_project(tmp, 'clock'))
    end)

  it('never enters the project_open state #project', function()
    CC:open_project(ProjectService.DEFAULT)
    assert.are.equal('ready', love.state.app_state)
    CC:open_project('clock')
    assert.are.equal('ready', love.state.app_state)
    CC:close_project()
    assert.are.equal('ready', love.state.app_state)
  end)

  it('old console env is gone #project', function()
    assert.is_nil(CC.main_env)
    assert.is_nil(ConsoleController.get_console_env)
  end)

  it('resets the env exactly once on close #project', function()
    CC:open_project('clock')
    local n = 0
    local orig = CC._reset_executor_env
    CC._reset_executor_env = function(self, ...)
      n = n + 1
      return orig(self, ...)
    end
    CC:close_project()
    assert.are.equal(1, n)
    CC._reset_executor_env = orig
  end)

  it('eval works in the merged env #project', function()
    assert.are.equal(2, CC:get_project_env().eval('1+1'))
  end)

  --- Closing a project ends its run, paused or going, the way
  --- stopping it does: nothing is left for continue() to resume
  describe('closing ends the run #project', function()
    local stops
    local orig

    before_each(function()
      stops = 0
      orig = CC.stop_project_run
      CC.stop_project_run = function(self, ...)
        stops = stops + 1
        return orig(self, ...)
      end
    end)

    after_each(function()
      CC.stop_project_run = orig
      love.state.app_state = 'ready'
    end)

    it('close_project while paused stops the run', function()
      CC:open_project('clock')
      love.state.app_state = 'inspect'
      CC:close_project()
      assert.are.equal(1, stops)
      assert.are.equal('ready', love.state.app_state)
    end)

    it('continue has nothing to resume after the close', function()
      CC:open_project('clock')
      love.state.app_state = 'inspect'
      CC:close_project()
      local said = { }
      local print_ = _G.print
      _G.print = function(s) said[#said + 1] = s end
      CC:get_project_env().continue()
      _G.print = print_
      assert.are.same({ 'No project halted' }, said)
      assert.are.equal('ready', love.state.app_state)
    end)

    it('opening another project while paused stops the run',
      function()
        CC:open_project('clock')
        love.state.app_state = 'inspect'
        CC:open_project('other')
        assert.are.equal(1, stops)
        assert.are.equal('ready', love.state.app_state)
      end)

    it('closing an idle run stops it', function()
      CC:open_project('clock')
      love.state.app_state = 'ready'
      CC:close_project()
      assert.are.equal(1, stops)
    end)

    it('a before_exit hook that closes the project runs once',
      function()
        CC:open_project('clock')
        local env = CC:get_project_env()
        local hooks = 0
        env.compy.before_exit = function()
          hooks = hooks + 1
          env.close_project()
        end
        love.state.app_state = 'running'
        CC:close_project()
        assert.are.equal(1, hooks)
        assert.are.equal(ProjectService.DEFAULT,
          CC:get_current_project().name)
        assert.are.equal('ready', love.state.app_state)
      end)
  end)

  --- Output queued for the board and not sent yet would reach
  --- it where it no longer makes sense: after the program that
  --- sent it, or in the REPL of new firmware
  describe('unsent serial output #project', function()
    local port, fake

    --- the controller reads the IDE's global, not this file's
    before_each(function()
      require('model.serial.backend_fake')
      port = _G.SerialPort
      fake = FakeBackend.new()
      _G.SerialPort = Serial.new(fake)
    end)

    after_each(function()
      _G.SerialPort = port
      love.state.app_state = 'ready'
    end)

    it('goes when the run stops', function()
      CC:open_project('clock')
      love.state.app_state = 'running'
      local before = fake.drops
      CC:stop_project_run()
      assert.are.equal(before + 1, fake.drops)
    end)

    it('goes before the before_exit hook, which may still send',
      function()
        CC:open_project('clock')
        local before = fake.drops
        local at_hook
        CC:get_project_env().compy.before_exit = function()
          at_hook = fake.drops
        end
        love.state.app_state = 'running'
        CC:stop_project_run()
        assert.are.equal(before + 1, at_hook)
        assert.are.equal(before + 1, fake.drops)
      end)

    it('goes when the top-level code raises', function()
      CC:open_project(ProjectService.DEFAULT)
      CC:get_current_project():writefile(ProjectService.MAIN,
        'error("boom")')
      CC.main_ctrl.release_keyboard_route = function() end
      local before = fake.drops
      local print_ = _G.print
      _G.print = function() end
      CC:run_project()
      _G.print = print_
      assert.are.equal('ready', love.state.app_state)
      assert.are.equal(before + 1, fake.drops)
    end)

    it('goes before a flash begins', function()
      CC:open_project(ProjectService.DEFAULT)
      local before = fake.drops
      local at_flash
      CC:get_current_project().flash_microbit = function()
        at_flash = fake.drops
        return true
      end
      assert.is_true(CC:flash_microbit(':data:'))
      assert.are.equal(before + 1, at_flash)
    end)
  end)

  --- A module the project requires runs in the project's env;
  --- the env is new after every switch, so a module kept from
  --- before would leave its globals missing
  describe('require after the project is reopened #project', function()
    local function write_module()
      CC:get_current_project():writefile('counter.lua',
        'runs = (runs or 0) + 1\nreturn true')
    end

    after_each(function()
      package.loaded['counter'] = nil
    end)

    it('runs the module again after close_project', function()
      CC:open_project('clock')
      write_module()
      CC:get_project_env().require('counter')
      assert.are.equal(1, CC:get_project_env().runs)
      CC:close_project()
      CC:open_project('clock')
      CC:get_project_env().require('counter')
      assert.are.equal(1, CC:get_project_env().runs)
    end)

    it('runs the module again after another project was open',
      function()
        CC:open_project('clock')
        write_module()
        CC:get_project_env().require('counter')
        CC:open_project('other')
        CC:open_project('clock')
        CC:get_project_env().require('counter')
        assert.are.equal(1, CC:get_project_env().runs)
      end)

    it('does not hand the module to another project', function()
      CC:open_project('clock')
      write_module()
      CC:get_project_env().require('counter')
      CC:open_project('other')
      local ok = pcall(CC:get_project_env().require, 'counter')
      assert.is_false(ok)
    end)

    it('keeps an IDE module that shares a project file name',
      function()
        local ide_module = { }
        package.loaded['util.shared_name'] = ide_module
        CC:open_project('clock')
        CC:get_current_project():writefile('util.shared_name.lua',
          'return { }')
        CC:close_project()
        assert.are.equal(ide_module,
          package.loaded['util.shared_name'])
        package.loaded['util.shared_name'] = nil
      end)

    it('runs a module from a subfolder again', function()
      CC:open_project('clock')
      local dir = FS.join_path(tmp, 'clock', 'lib')
      lfs.mkdir(dir)
      assert.is_true(FS.write(FS.join_path(dir, 'x.lua'),
        'runs = (runs or 0) + 1\nreturn true'))
      CC:get_project_env().require('lib/x')
      CC:close_project()
      CC:open_project('clock')
      CC:get_project_env().require('lib/x')
      assert.are.equal(1, CC:get_project_env().runs)
      package.loaded['lib/x'] = nil
    end)
  end)
end)
