--- Headless ConsoleController tests for the unified project
--- environment (issue #106): single env for console + project,
--- env reset on switch, close redirects to scratch, reset_scratch.
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
      'reset_scratch', 'readfile', 'readlines', 'writefile', 'loadfile',
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
    assert.is_function(CC:get_project_env().reset_scratch)
  end)

  it('close_project returns to the default project #project', function()
    CC:open_project('clock')
    local ok = CC:close_project()
    assert.is_true(ok)
    assert.are.equal(ProjectService.DEFAULT,
      CC:get_current_project().name)
    assert.are.equal('ready', love.state.app_state)
  end)

  it('close_project from scratch reopens scratch #project', function()
    CC:open_project(ProjectService.DEFAULT)
    CC:get_project_env().x = 5
    assert.is_true(CC:close_project())
    assert.are.equal(ProjectService.DEFAULT,
      CC:get_current_project().name)
    assert.is_nil(CC:get_project_env().x)
  end)

  it('reset_scratch restores factory contents #project', function()
    CC:open_project(ProjectService.DEFAULT)
    CC:get_current_project():writefile('extra.lua', '-- extra')
    assert.is_true(CC:reset_scratch())
    assert.are.equal(ProjectService.DEFAULT,
      CC:get_current_project().name)
    local p = FS.join_path(tmp, ProjectService.DEFAULT, 'extra.lua')
    assert.is_false(FS.exists(p))
    local rok, content =
      CC:get_current_project():readfile(ProjectService.MAIN)
    assert.is_true(rok)
    assert.are.equal("print('Hello world!')\n", content)
  end)

  it('reset_scratch keeps the old scratch, numbered #project',
    function()
      local old = ProjectService.DEFAULT .. '.old'
      CC:open_project(ProjectService.DEFAULT)
      CC:get_current_project():writefile('extra.lua', '-- one')
      assert.is_true(CC:reset_scratch())
      CC:get_current_project():writefile('extra.lua', '-- two')
      assert.is_true(CC:reset_scratch())
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

  it('close_project says closed before it opens scratch #project',
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

  it('reset_scratch from another project keeps that project #project', function()
    CC:open_project('clock')
    assert.is_true(CC:reset_scratch())
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
end)
