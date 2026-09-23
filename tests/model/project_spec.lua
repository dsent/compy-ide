--- ProjectService tests.
--- Uses the "Web" branch of FS (plain love.filesystem calls)
--- with an lfs-backed mock on a real tmpdir. `love` is mocked
--- just enough, and FS is required only AFTER the mock exists,
--- since the branch is chosen at load time.
--- NOTE: ProjectService.path is a class-level field; it is
--- reset per test to avoid cross-test pollution.

local lfs = require('lfs')

describe('ProjectService #project', function()
  local FS
  local tmp
  local PS

  --- minimal love.filesystem over lfs, matching the
  --- signatures used by util.filesystem's web branch
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
      lines = function(path)
        return io.lines(path)
      end,
      getInfo = attr,
      createDirectory = function(path)
        return lfs.mkdir(path)
      end,
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
    }
  end

  --- recursive delete over lfs
  local function rm_rf(path)
    local mode = lfs.attributes(path, 'mode')
    if mode == 'directory' then
      for entry in lfs.dir(path) do
        if entry ~= '.' and entry ~= '..' then
          rm_rf(path .. '/' .. entry)
        end
      end
      return os.remove(path)
    end
    return os.remove(path)
  end

  local saved_fs_module
  local saved_love

  setup(function()
    saved_fs_module = package.loaded['util.filesystem']
    saved_love = _G.love
    _G.love = _G.love or {}
    love.system = love.system or {
      getOS = function() return 'Web' end,
    }
    love.filesystem = mock_love_fs()
    --- LÖVE ships its own utf8; in tests, alias the luarocks one
    package.preload['utf8'] = function()
      return require('lua-utf8')
    end
    package.loaded['util.filesystem'] = nil
    FS = require('util.filesystem')
    require('util.table')
    require('util.dequeue')
    package.loaded['model.project.project'] = nil
    --- the flasher looks for the board through this FS too
    package.loaded['util.usb'] = nil
    require('model.project.project')
    --- ProjectService:remove uses FS.rm, which the web FS branch
    --- gets from love.filesystem.remove — provide it via rm_rf
    FS.rm = function(target) return rm_rf(target) end
  end)

  before_each(function()
    tmp = '/tmp/compy_ps_' .. tostring(math.floor(os.clock() * 1e6))
    lfs.mkdir(tmp)
    love.paths = { project_path = tmp }
    PS = ProjectService()
    ProjectService.path = tmp
  end)

  after_each(function()
    if tmp and FS.exists(tmp) then
      FS.rm(tmp)
    end
  end)

  teardown(function()
    --- restore globals as they were before this spec ran
    _G.love = saved_love
    _G.LFS = nil
    package.loaded['util.filesystem'] = saved_fs_module
  end)

  teardown(function()
    --- restore the non-love FS branch for subsequent spec files
    _G.love = nil
    package.loaded['util.filesystem'] = nil
    require('util.filesystem')
  end)

  describe('opreate', function()
    it('creates and opens the default project #project', function()
      local open, create = PS:opreate(ProjectService.DEFAULT)
      assert.is_false(open)
      assert.is_true(create)
      assert.are.equal(ProjectService.DEFAULT, PS.current.name)

      local main = FS.join_path(tmp, ProjectService.DEFAULT, ProjectService.MAIN)
      assert.is_true(FS.exists(main))
      local rok, content = PS.current:readfile(ProjectService.MAIN)
      assert.is_true(rok)
      assert.are.equal("print('Hello world!')\n", content)

      local readme = FS.join_path(tmp, ProjectService.DEFAULT, ProjectService.README)
      assert.is_true(FS.exists(readme))
    end)

    it('opens an existing project idempotently #project', function()
      PS:opreate(ProjectService.DEFAULT)
      local open, create = PS:opreate(ProjectService.DEFAULT)
      assert.is_true(open)
      assert.is_false(create)
    end)
  end)

  describe('remove', function()
    it('deletes an existing project #project', function()
      PS:opreate(ProjectService.DEFAULT)
      local ok, err = PS:remove(ProjectService.DEFAULT)
      assert.is_true(ok)
      assert.is_nil(err)
      assert.is_false(FS.exists(FS.join_path(tmp, ProjectService.DEFAULT)))
      assert.is_nil(PS.is_project(ProjectService.path, ProjectService.DEFAULT))
    end)

    it('fails for a nonexistent project #project', function()
      local ok, err = PS:remove('nonexistent')
      assert.is_false(ok)
      assert.is_string(err)
    end)

    it('refuses invalid names #project', function()
      assert.is_false(PS:remove('..'))
      assert.is_false(PS:remove('a/b'))
      assert.is_false(PS:remove(''))
    end)

    it('does not clear a stale current project #project', function()
      --- pins the "close before remove" contract
      PS:opreate(ProjectService.DEFAULT)
      assert.is_true(PS:remove(ProjectService.DEFAULT))
      assert.is_not_nil(PS.current)
      local rok = PS.current:readfile(ProjectService.MAIN)
      assert.is_false(rok)
    end)
  end)

  describe('list', function()
    it('excludes removed projects #project', function()
      PS:opreate(ProjectService.DEFAULT)
      PS:opreate('clock')
      assert.is_true(PS:remove(ProjectService.DEFAULT))
      local names = {}
      for _, p in ipairs(PS:list()) do
        table.insert(names, p.name)
      end
      assert.are.same({ 'clock' }, names)
    end)
  end)

  describe('close', function()
    it('clears current #project', function()
      PS:opreate(ProjectService.DEFAULT)
      assert.is_true(PS:close())
      assert.is_nil(PS.current)
    end)
  end)

  describe('flash_microbit', function()
    --- the instance setup loaded, which the flasher holds
    local usb, now, pause

    before_each(function()
      usb = require('util.usb')
      now, pause = usb.now, usb.pause
    end)

    after_each(function()
      usb.now, usb.pause = now, pause
    end)

    --- A board on a folder. It holds DETAILS.TXT; once a file
    --- is on it, it takes the drive away, keeping what it took,
    --- and brings it back, with FAIL.TXT if asked to refuse.
    --- `never` stops it at 'take' or at 'back'.
    --- @return function what the board took, and what else
    ---   was on its drive then
    local function board(ddir, fail, never)
      lfs.mkdir(ddir)
      local function put(name, text)
        local f = assert(io.open(ddir .. '/' .. name, 'w'))
        f:write(text)
        f:close()
      end
      put('DETAILS.TXT', 'Unique ID: 9904')
      local clock, took, beside = 0, nil, {}
      usb.now = function() return clock end
      usb.pause = function(seconds)
        clock = clock + seconds
        if not took then
          if never == 'take' then return end
          for entry in lfs.dir(ddir) do
            if entry ~= '.' and entry ~= '..' then
              beside[#beside + 1] = entry
            end
          end
          took = FS.combined_read(ddir .. '/microbit.hex')
          rm_rf(ddir)
          return
        end
        if never == 'back' then return end
        lfs.mkdir(ddir)
        put('DETAILS.TXT', 'Unique ID: 9904')
        if fail then put('FAIL.TXT', fail) end
      end
      return function() return took, beside end
    end

    it('refuses empty data #project', function()
      PS:opreate(ProjectService.DEFAULT)
      love.paths.microbit_path = tmp .. '/microbit'
      local ok, err = PS.current:flash_microbit('')
      assert.is_false(ok)
      assert.is_not_nil(err)
    end)

    it('writes microbit.hex to the detected device root #project', function()
      local ddir = tmp .. '/microbit'
      local taken = board(ddir)
      love.paths.microbit_path = ddir
      PS:opreate(ProjectService.DEFAULT)
      local ok, err = PS.current:flash_microbit(':firmware:data:')
      assert.is_true(ok)
      assert.is_nil(err)
      local content, beside = taken()
      assert.are.equal(':firmware:data:', content)
      --- no temp file left behind (temp has no extension, so it
      --- can't be mistaken for a hex flash by the micro:bit)
      for _, entry in ipairs(beside) do
        assert.is_true(entry == 'microbit.hex'
          or entry == 'DETAILS.TXT',
          'unexpected leftover: ' .. entry)
      end
    end)

    it('says why the board refused the file #project', function()
      local ddir = tmp .. '/microbit'
      board(ddir, 'error: The hex file cannot be decoded.\r\n'
        .. 'type: user\r\n')
      love.paths.microbit_path = ddir
      PS:opreate(ProjectService.DEFAULT)
      local ok, err = PS.current:flash_microbit(':firmware:data:')
      assert.is_false(ok)
      assert.are.equal(usb.messages.refused(
        'The hex file cannot be decoded.'), err)
    end)

    it('says when the board does not take the file #project',
      function()
        local ddir = tmp .. '/microbit'
        board(ddir, nil, 'take')
        love.paths.microbit_path = ddir
        PS:opreate(ProjectService.DEFAULT)
        local ok, err = PS.current:flash_microbit(':data:')
        assert.is_false(ok)
        assert.are.equal(usb.messages.not_taken, err)
      end)

    it('says when the board does not come back #project',
      function()
        local ddir = tmp .. '/microbit'
        board(ddir, nil, 'back')
        love.paths.microbit_path = ddir
        PS:opreate(ProjectService.DEFAULT)
        local ok, err = PS.current:flash_microbit(':data:')
        assert.is_false(ok)
        assert.are.equal(usb.messages.not_back, err)
      end)

    it('reports when no device is present #project', function()
      love.paths.microbit_path = nil
      PS:opreate(ProjectService.DEFAULT)
      local ok, err = PS.current:flash_microbit('data')
      assert.is_false(ok)
      assert.is_not_nil(err)
    end)
  end)
end)
