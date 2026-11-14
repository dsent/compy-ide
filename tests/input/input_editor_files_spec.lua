-- The editor across files: what one file's buffer, draft,
-- history and position must never carry into another. Every
-- case opens files through the real ConsoleController:edit
-- over a project held in memory, and drives keys through the
-- full route (F.session).

local F    = require('tests.helpers.input_fixture')
local mock = require('tests.mock')
local FS   = require('util.filesystem')

describe('the editor across files #input', function()
  --- these tests start at the first block (pre-IS1.1)
  local open_as_before
  setup(function()
    F.setup()
    open_as_before =
        require('tests.helpers.open_at_first').install()
  end)
  teardown(function()
    open_as_before()
    F.teardown()
  end)

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

  --- load the viewed block with Edit and put `text` in the
  --- field
  local function draft(text)
    chord('f2')
    ed.input:set_text(text)
  end

  local function field()
    return string.unlines(ed.input:get_text())
  end

  before_each(function()
    F.reset()
    cc = F.cc
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

  describe('a write that fails', function()
    local stubbed = { 'quit_project', 'reset', 'restart', 'run_project' }
    local took

    before_each(function()
      files['main.lua'] = 'x = 1\ny = 1\n'
      love.state.prev_state = 'ready'
      cc.model.projects.current.writefile = function()
        return false, 'the card is full'
      end
      took = {}
      for _, f in ipairs(stubbed) do
        local orig = cc[f]
        cc[f] = function() took[#took + 1] = f end
        undo[#undo + 1] = function() cc[f] = orig end
      end
    end)

    it('keeps the draft, the target and the file as they were',
      function()
        open()
        draft('x = 99')
        chord('return')

        assert.is_true(ed.input:has_error())
        assert.same(1, ed:get_active_buffer().loaded)
        assert.same({ 'x = 1', 'y = 1' },
          ed:get_active_buffer():get_text_content())
        assert.same('x = 99', field())
        --- the notice blocks nothing: a key that changes no
        --- text dismisses it, and the edit goes on
        chord('left')
        assert.is_false(ed.input:has_error())
        assert.same('x = 99', field())
        assert.same(1, ed:get_active_buffer().loaded)
      end)

    it('keeps an insertion in the field', function()
      open()
      ed.input:set_text('newvalue = 99')
      chord('return')

      assert.is_true(ed.input:has_error())
      assert.same({ 'x = 1', 'y = 1' },
        ed:get_active_buffer():get_text_content())
      assert.same('newvalue = 99', field())
      chord('left')
      assert.is_false(ed.input:has_error())
      assert.same('newvalue = 99', field())
    end)

    it('leaves no require of the draft behind', function()
      open()
      ed.input:set_text("local lib = require('lib')")
      chord('return')
      assert.is_true(ed.input:has_error())

      local sem = ed:get_active_buffer().semantic
      assert.same({}, sem and sem.requires or {})
    end)

    --- no exit asks a question (H-NFR4.6). During the edit
    --- the exit is refused with a notice, the draft kept; once
    --- the edit is aborted the exit is taken (IS1.7: the draft
    --- is kept until the user submits, aborts or leaves)
    for _, c in ipairs({
      { 'Ctrl+T', { 'lctrl', 't' }, 'run_project' },
      { 'Ctrl+Q', { 'lctrl', 'q' }, 'quit_project' },
      { 'Ctrl+Shift+R', { 'lctrl', 'lshift', 'r' }, 'reset' },
      { 'Ctrl+Alt+R', { 'lctrl', 'lalt', 'r' }, 'restart' },
    }) do
      it(c[1] .. ' waits for the edit to end, and asks nothing',
        function()
          open()
          draft('x = 99')
          chord('return')
          --- the failed write's notice goes at the next key
          chord('left')
          chord(unpack(c[2]))
          assert.same({}, took)
          assert.is_true(ed.input:has_error())
          assert.same('x = 99', field())

          --- one Escape: the notice goes and the edit with it
          chord('escape')
          assert.is_false(ed.input:has_error())
          assert.same('', field())
          assert.same('browsing', ed:state_name())
          assert.same('editor', love.state.app_state)
          chord(unpack(c[2]))
          assert.same({ c[3] }, took)
        end)
    end

    it('Escape lets the file go and asks nothing', function()
      open()
      draft('x = 99')
      chord('return')
      --- the notice and the edit, then the file
      chord('escape')
      assert.same('editor', love.state.app_state)
      assert.same('', field())
      chord('escape')
      assert.same('ready', love.state.app_state)
    end)

    it('a failed format of a saved file asks about nothing',
      function()
        files['main.lua'] = 'x=1\n'
        open()
        chord('lctrl', 'lshift', 'f')
        assert.is_true(ed.input:has_error())

        --- the notice blocks no exit
        chord('lctrl', 'q')
        assert.same({ 'quit_project' }, took)
      end)
  end)

  describe('a cut block in the field', function()
    --- the field holds the block's only copy (IS6.2): no exit
    --- may drop it
    local exits = {
      { 'Ctrl+Shift+S', { 'lctrl', 'lshift', 's' } },
      { 'Ctrl+T', { 'lctrl', 't' } },
      { 'Ctrl+Q', { 'lctrl', 'q' } },
    }
    for _, e in ipairs(exits) do
      it('keeps ' .. e[1] .. ' from leaving', function()
        local keep = { run = cc.run_project, quit = cc.quit_project }
        undo[#undo + 1] = function()
          cc.run_project, cc.quit_project = keep.run, keep.quit
        end
        local took = false
        cc.run_project = function() took = true end
        cc.quit_project = function() took = true end
        files['main.lua'] = 'x = 1\ny = 2\n'
        love.state.prev_state = 'ready'
        open()
        chord('lctrl', 'delete')
        assert.same('y = 2\n', files['main.lua'])
        assert.same('x = 1', field())

        chord(unpack(e[2]))

        assert.is_false(took)
        assert.same('editor', love.state.app_state)
        assert.same('x = 1', field())
        assert.is_true(ed.input:has_error())
      end)
    end
  end)

  describe('text undo', function()
    it('ends with the editor', function()
      open()
      draft('x = 1')
      F.session.type(' -- the old draft')
      chord('lctrl', 'lshift', 's')

      files['new.lua'] = 'fresh = 1\n'
      open('new.lua')
      chord('lctrl', 'z')
      assert.same('', field())
    end)
  end)

  describe('a file open already', function()
    --- the editor spec is silent here; Luditor, its reference
    --- implementation, refuses with "<name> is already open."
    --- (src/editor.rs, action_follow_reference), which also
    --- keeps two copies from saving over each other
    it('is on the stack once: Ctrl+J to it is refused', function()
      files['main.lua'] = "local lib = require('lib')\nx = 1\n"
      files['lib.lua'] = "local main = require('main')\n"
      open()
      chord('lctrl', 'j')
      assert.same('lib.lua', ed:get_active_buffer().name)
      chord('lctrl', 'j')

      assert.same('lib.lua', ed:get_active_buffer().name)
      assert.is_true(ed.input:has_error())
      assert.same(2, ed.model.buffers:length())
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
        chord('escape')

        local other = { ['main.lua'] = six }
        cc.model.projects.current = project('b', other)
        files = other
        love.state.app_state = 'ready'
        open()
        assert.same(1, ed:get_active_buffer():get_selection())
      end)

    it('lets a file it leaves go', function()
      files['main.lua'] = "local lib = require('lib')\n"
      files['lib.lua'] = 'libvalue = 1\n'
      open()
      chord('lctrl', 'j')
      chord('escape')

      local views = 0
      for _ in pairs(ed.view.buffers) do views = views + 1 end
      assert.same(1, views)
    end)
  end)

  describe('a project switch', function()
    it("forgets Ctrl+T's way back into the old project", function()
      local P = cc.model.projects
      local close, opreate = P.close, P.opreate
      undo[#undo + 1] = function() P.close, P.opreate = close, opreate end
      local b = project('b', { ['main.lua'] = 'b = 1\n' })
      b.get_loader = function() return function() end end
      P.close = function() P.current = nil; return true end
      P.opreate = function() P.current = b; return true end
      files['other.lua'] = 'a = 1\n'
      open('other.lua')

      assert.is_true(cc:open_project('b'))
      assert.same('b', P.current.name)
      assert.is_nil(love.state.editor)
    end)
  end)

  describe('a program ending', function()
    it('opens no file from its exit hook', function()
      local P = cc.model.projects
      local close = P.close
      undo[#undo + 1] = function() P.close = close end
      P.close = function() P.current = nil; return true end
      cc:get_project_env().compy.before_exit = function()
        cc:edit('main.lua')
      end
      cc:_close_project()

      assert.same('ready', love.state.app_state)
      assert.is_nil(cc.editor:get_active_buffer())
    end)
  end)

  describe('Ctrl+J', function()
    before_each(function()
      files['main.lua'] = "local lib = require('lib')\n"
      files['lib.lua'] = 'libvalue = 1\n'
    end)

    it('during an edit is refused, the draft where it was (IS1.5)',
      function()
        open()
        draft("local lib = require('lib')\nkept = 99")
        chord('lctrl', 'j')

        assert.same('main.lua', ed:get_active_buffer().name)
        assert.is_true(ed.input:has_error())
        assert.same(1, ed:get_active_buffer().loaded)
        assert.same("local lib = require('lib')\nkept = 99", field())
        assert.same({}, writes)
      end)

    it('to a file the project lacks is refused', function()
      files['lib.lua'] = nil
      open()
      chord('lctrl', 'j')

      assert.same('main.lua', ed:get_active_buffer().name)
      assert.is_true(ed.input:has_error())
      assert.same({}, writes)
    end)

    it('steps back with Escape to where the caller was', function()
      files['main.lua'] = "x = 1\nlocal lib = require('lib')\n"
      open()
      chord('lctrl', 'down')
      chord('lctrl', 'j')
      assert.same('lib.lua', ed:get_active_buffer().name)
      chord('escape')

      assert.same('main.lua', ed:get_active_buffer().name)
      assert.same(2, ed:get_active_buffer():get_selection())
    end)

    it('leaves an error message behind', function()
      open()
      ed:refuse({ 'a message about main.lua' })
      chord('lctrl', 'j')

      assert.is_false(ed.input:has_error())
    end)
  end)
end)
