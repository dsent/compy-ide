-- The editor across files: what one file's buffer, draft,
-- history and position must never carry into another. Every
-- case opens files through the real ConsoleController:edit
-- over a project held in memory, and drives keys through the
-- full route (F.session).

local F    = require('tests.helpers.input_fixture')
local mock = require('tests.mock')
local FS   = require('util.filesystem')

describe('the editor across files #input', function()
  setup(function() F.setup() end)
  teardown(function() F.teardown() end)

  local cc, ed, files, writes
  local undo = {}

  --- a project held in memory, under a path of its own
  local function project(name, contents)
    local root = '/memory-' .. name .. '/'
    return {
      name = name,
      path = root,
      required = {},
      get_path = function(_, f) return root .. f end,
      readfile = function(_, f) return true, contents[f] end,
      writefile = function(_, f, text)
        writes[#writes + 1] = name .. '/' .. f
        contents[f] = text
        return true
      end,
    }
  end

  local function chord(...)
    local keys = { ... }
    for _, k in ipairs(keys) do F.session.press(k) end
    for i = #keys, 1, -1 do F.session.release(keys[i]) end
  end

  local function open(name)
    cc:edit(name or 'main.lua')
    ed = cc.editor
  end

  --- open the selected block and put `text` in it
  local function draft(text)
    chord('return')
    ed.input:set_text(text)
  end

  before_each(function()
    F.reset()
    cc = F.cc
    cc.editor.pos_memory = {}
    cc.editor.state = nil
    files, writes = { ['main.lua'] = 'x = 1\n' }, {}
    local P = cc.model.projects
    local prev = P.current
    local exists, fsync = FS.exists, FS.fsync
    P.current = project('a', files)
    FS.exists = function(path)
      local name, f = path:match('^/memory%-([^/]+)/(.+)$')
      if name then
        local p = P.current
        return p.name == name and files[f] ~= nil
      end
      return exists(path)
    end
    FS.fsync = function() return true end
    undo = {
      function()
        P.current = prev
        FS.exists, FS.fsync = exists, fsync
        mock.release_keys()
      end,
    }
  end)

  after_each(function()
    for i = #undo, 1, -1 do undo[i]() end
  end)

  describe('text undo', function()
    it('ends with the editor', function()
      open()
      draft('x = 1')
      F.session.type(' -- the old draft')
      chord('lctrl', 'lshift', 's')

      files['new.lua'] = 'fresh = 1\n'
      open('new.lua')
      chord('lctrl', 'return')
      assert.same('edit', ed:get_mode())
      chord('lctrl', 'z')
      assert.same('', string.unlines(ed.input:get_text()))
    end)

    it('ends with its block', function()
      open()
      draft('x = 2')
      F.session.type(' -- typed')
      chord('return')
      assert.same('nav', ed:get_mode())

      chord('lctrl', 'return')
      chord('lctrl', 'z')
      assert.same('', string.unlines(ed.input:get_text()))
    end)
  end)

  describe('a file open twice', function()
    it('is one buffer, so no copy saves over another', function()
      files['main.lua'] = "local lib = require('lib')\nx = 1\ny = 1\n"
      files['lib.lua'] = "local main = require('main')\n"
      open()
      chord('lctrl', 'j')
      chord('lctrl', 'j')
      assert.same('main.lua', ed:get_active_buffer().name)
      chord('down')
      draft('x = 2')
      chord('return')
      assert.is_truthy(files['main.lua']:find('x = 2', 1, true))

      chord('lshift', 'escape')
      chord('lshift', 'escape')
      assert.same('main.lua', ed:get_active_buffer().name)
      chord('down')
      chord('down')
      draft('y = 2')
      chord('return')

      assert.is_truthy(files['main.lua']:find('x = 2', 1, true))
      assert.is_truthy(files['main.lua']:find('y = 2', 1, true))
    end)
  end)

  describe('a restore', function()
    it('reaches the file wherever it is open', function()
      files['main.lua'] = "local lib = require('lib')\nx = 1\n"
      files['lib.lua'] = "local main = require('main')\n"
      local keep = {
        checkpoint_modtime = cc.checkpoint_modtime,
        file_modtime = cc.file_modtime,
        restore_checkpoint = cc.restore_checkpoint,
      }
      undo[#undo + 1] = function()
        for f, v in pairs(keep) do cc[f] = v end
      end
      cc.checkpoint_modtime = function() return 1752400000 end
      cc.file_modtime = function() return 1752480000 end
      cc.restore_checkpoint = function(_, name)
        files[name] = "local lib = require('lib')\nx = 7\n"
        return true
      end
      open()
      chord('lctrl', 'j')
      chord('lctrl', 'j')
      chord('lctrl', 'lshift', 'k')
      chord('return')
      assert.same('x = 7', ed:get_active_buffer():get_text_content()[2])

      chord('lshift', 'escape')
      chord('lshift', 'escape')
      assert.same('main.lua', ed:get_active_buffer().name)
      assert.same('x = 7', ed:get_active_buffer():get_text_content()[2])
    end)
  end)

  describe('opening another file', function()
    it('starts its search afresh', function()
      files['main.lua'] = 'function alpha() end\n'
      files['b.lua'] = 'function beta() end\n'
      open()
      chord('lctrl', 'f')
      F.session.type('alpha')
      open('b.lua')

      chord('lctrl', 'f')
      assert.same('', string.unlines(ed.search.input:get_text()))
    end)

    it("takes nothing of another project's same-named file",
      function()
        local six = 'a = 1\nb = 2\nc = 3\nd = 4\ne = 5\nf = 6\n'
        files['main.lua'] = six
        open()
        chord('lctrl', 'down')
        chord('lctrl', 'down')
        assert.same(3, ed:get_active_buffer():get_selection())
        chord('lshift', 'escape')

        local other = { ['main.lua'] = six }
        cc.model.projects.current = project('b', other)
        files = other
        love.state.app_state = 'ready'
        open()
        assert.same(1, ed:get_active_buffer():get_selection())
      end)
  end)

  describe('Ctrl+J', function()
    before_each(function()
      files['main.lua'] = "local lib = require('lib')\n"
      files['lib.lua'] = 'libvalue = 1\n'
    end)

    it('leaves the draft with its own file', function()
      open()
      draft("local lib = require('lib')\nkept = 99")
      chord('lctrl', 'j')

      assert.same('lib.lua', ed:get_active_buffer().name)
      assert.same('nav', ed:get_mode())
      assert.same('', string.unlines(ed.input:get_text()))
      --- Enter in the required file opens its block
      chord('return')
      assert.same('edit', ed:get_mode())
      assert.same({}, writes)
    end)

    it('brings the draft back with its file', function()
      open()
      draft("local lib = require('lib')\nkept = 99")
      chord('lctrl', 'j')
      chord('lshift', 'escape')

      assert.same('main.lua', ed:get_active_buffer().name)
      assert.same('edit', ed:get_mode())
      assert.same("local lib = require('lib')\nkept = 99",
        string.unlines(ed.input:get_text()))
    end)

    it('brings the draft back when the file opens again', function()
      files['lib.lua'] = "local main = require('main')\n"
      open()
      draft("local lib = require('lib')\nkept = 99")
      chord('lctrl', 'j')
      chord('lctrl', 'j')

      assert.same('main.lua', ed:get_active_buffer().name)
      assert.same('edit', ed:get_mode())
      assert.same("local lib = require('lib')\nkept = 99",
        string.unlines(ed.input:get_text()))
      assert.is_nil(ed:get_active_buffer().parked)
      assert.same(1, ed:get_active_buffer():get_selection())
    end)

    it('leaves an error message behind', function()
      open()
      ed:refuse({ 'a message about main.lua' })
      chord('lctrl', 'j')

      assert.is_false(ed.input:has_error())
    end)
  end)
end)
