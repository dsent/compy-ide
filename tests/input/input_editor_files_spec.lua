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

  describe('a write that fails', function()
    before_each(function()
      files['main.lua'] = 'x = 1\ny = 1\n'
      love.state.prev_state = 'ready'
      cc.model.projects.current.writefile = function()
        return false, 'the card is full'
      end
    end)

    it('leaves the file asked about on exit', function()
      open()
      draft('x = 99')
      chord('return')
      assert.is_true(ed.input:has_error())
      chord('escape')

      chord('lctrl', 'lshift', 's')
      assert.is_not_nil(ed.pending_confirm)
      assert.same('main.lua', ed:get_active_buffer().name)
      chord('escape')
      assert.same('editor', love.state.app_state)
    end)

    describe('and an exit confirmed', function()
      local stubbed = { 'quit_project', 'reset', 'restart', 'run_project' }
      local took

      before_each(function()
        took = {}
        for _, f in ipairs(stubbed) do
          local orig = cc[f]
          cc[f] = function() took[#took + 1] = f end
          undo[#undo + 1] = function() cc[f] = orig end
        end
      end)

      it('a space typed after a second question is kept', function()
        open()
        draft('x = 99')
        chord('return')
        chord('escape')
        ed.input:set_text('x = 100')
        chord('lctrl', 't')
        assert.same('discard', ed.pending_confirm)
        --- a desktop keyboard: the key, then its glyph
        F.session.press('space')
        F.session.release('space')
        F.session.type(' ')
        assert.same('leave', ed.pending_confirm)
        chord('escape')
        assert.is_nil(ed.pending_confirm)

        F.session.type(' ')
        --- in navigation a glyph opens the block, with it
      assert.is_truthy(string.unlines(ed.input:get_text()):find('^ '))
      end)

      it('a glyph the device sent first is held back by no token',
        function()
          open()
          draft('x = 99')
          chord('return')
          chord('escape')
          ed.input:set_text('x = 100')
          chord('lctrl', 't')
          --- the device: glyph, then key, for each answer
          F.session.type(' ')
          F.session.press('space')
          F.session.release('space')
          assert.same('leave', ed.pending_confirm)
          F.session.type(' ')
          F.session.press('space')
          F.session.release('space')
          assert.same({ 'run_project' }, took)
          F.love_update(1)
          assert.is_nil(cc.swallow_glyph)
        end)

      it('a question asked in search is shown in the editor', function()
        open()
        draft('x = 99')
        chord('return')
        chord('escape')
        chord('lshift', 'escape')
        chord('lctrl', 'f')
        assert.same('search', ed:get_mode())

        chord('lctrl', 'q')
        assert.same('leave', ed.pending_confirm)
        assert.same('nav', ed:get_mode())
        assert.same('', string.unlines(ed.search.input:get_text()))
      end)

      for _, c in ipairs({
        { 'Ctrl+T', { 'lctrl', 't' }, 'run_project' },
        { 'Ctrl+Q', { 'lctrl', 'q' }, 'quit_project' },
        { 'Ctrl+Shift+R', { 'lctrl', 'lshift', 'r' }, 'reset' },
        { 'Ctrl+Alt+R', { 'lctrl', 'lalt', 'r' }, 'restart' },
      }) do
        it(c[1] .. ' takes its exit', function()
          open()
          draft('x = 99')
          chord('return')
          chord('escape')
          chord('lshift', 'escape')
          chord(unpack(c[2]))
          assert.is_not_nil(ed.pending_confirm)
          chord('return')
          assert.same({ c[3] }, took)
          assert.is_nil(ed.pending_confirm)
        end)
      end
    end)

    describe('twice, or undone', function()
      local took

      before_each(function()
        took = {}
        local orig = cc.quit_project
        cc.quit_project = function() took[#took + 1] = 'quit_project' end
        undo[#undo + 1] = function() cc.quit_project = orig end
      end)

      it('a failed fresh block keeps the earlier failure asked about',
        function()
          open()
          draft('x = 99')
          chord('return')
          chord('escape')
          chord('lshift', 'escape')
          chord('lctrl', 'return')
          ed.input:set_text('newvalue = 99')
          chord('return')
          chord('escape')
          chord('lshift', 'escape')
          assert.same('discard', ed.pending_confirm)
          chord('return')
          assert.same('nav', ed:get_mode())

          chord('lctrl', 'q')
          assert.same('leave', ed.pending_confirm)
          assert.same({}, took)
        end)

      -- FLIPPED back: a save now writes the file whole or
      -- not at all (FS.replace), so a failed write leaves the
      -- file on the card as it was.
      describe('that leaves the file as it was', function()
        before_each(function()
          cc.model.projects.current.writefile = function()
            return false, 'the card is full'
          end
        end)

        it('a failed format of a saved file asks about nothing',
          function()
            files['main.lua'] = 'x=1\n'
            open()
            chord('lctrl', 'lshift', 'f')
            assert.is_true(ed.input:has_error())
            chord('escape')

            chord('lctrl', 'q')
            assert.is_nil(ed.pending_confirm)
            assert.same({ 'quit_project' }, took)
          end)

        it('a failed fresh block in a saved file asks about nothing',
          function()
            open()
            chord('lctrl', 'return')
            ed.input:set_text('newvalue = 99')
            chord('return')
            chord('escape')
            chord('lshift', 'escape')
            chord('return')
            assert.same('nav', ed:get_mode())

            chord('lctrl', 'q')
            assert.is_nil(ed.pending_confirm)
            assert.same({ 'quit_project' }, took)
          end)
      end)
    end)

    it('says which file could not be saved when it asks', function()
      open()
      draft('x = 99')
      chord('return')
      chord('escape')
      chord('lshift', 'escape')
      chord('lshift', 'escape')

      assert.same('leave', ed.pending_confirm)
      local shown = table.concat(ed.input.model.error or {}, ' ')
      assert.is_truthy(shown:find('main.lua could not be saved', 1, true))
    end)

    it('leaves no require of the draft behind', function()
      open()
      chord('lctrl', 'return')
      ed.input:set_text("local lib = require('lib')")
      chord('return')
      assert.is_true(ed.input:has_error())

      local sem = ed:get_active_buffer().semantic
      assert.same({}, sem and sem.requires or {})
    end)

    it('keeps a fresh block open, its draft and the file as they were',
      function()
        open()
        chord('lctrl', 'return')
        ed.input:set_text('newvalue = 99')
        chord('return')

        assert.same('edit', ed:get_mode())
        assert.is_true(ed.input:has_error())
        assert.same({ 'x = 1', 'y = 1' },
          ed:get_active_buffer():get_text_content())
        chord('escape')
        assert.same('newvalue = 99',
          string.unlines(ed.input:get_text()))

        chord('lctrl', 'lshift', 's')
        assert.same('discard', ed.pending_confirm)
      end)

    it('asks before Shift+Esc lets the file go', function()
      open()
      draft('x = 99')
      chord('return')
      chord('escape')
      chord('lshift', 'escape')
      assert.same('nav', ed:get_mode())

      chord('lshift', 'escape')
      assert.is_not_nil(ed.pending_confirm)
      assert.same('main.lua', ed:get_active_buffer().name)
    end)
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

  describe('a file open already', function()
    it('comes back where it is, not where it was', function()
      files['main.lua'] = "local lib = require('lib')\na = 1\nb = 2\nc = 3\n"
      files['lib.lua'] = "local main = require('main')\n"
      open()
      chord('lctrl', 'j')
      chord('lctrl', 'j')
      for _ = 1, 3 do chord('lctrl', 'down') end
      assert.same(4, ed:get_active_buffer():get_selection())
      chord('lshift', 'escape')
      chord('lshift', 'escape')
      for _ = 1, 3 do chord('lctrl', 'up') end
      assert.same(1, ed:get_active_buffer():get_selection())

      chord('lctrl', 'j')
      chord('lctrl', 'j')
      assert.same('main.lua', ed:get_active_buffer().name)
      assert.same(1, ed:get_active_buffer():get_selection())
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

    it('lets a file it leaves go', function()
      files['main.lua'] = "local lib = require('lib')\n"
      files['lib.lua'] = 'libvalue = 1\n'
      open()
      chord('lctrl', 'j')
      chord('lshift', 'escape')

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

    describe('then an exit', function()
      local stubbed = { 'quit_project', 'reset', 'restart', 'run_project' }
      local took

      before_each(function()
        took = {}
        for _, f in ipairs(stubbed) do
          local orig = cc[f]
          cc[f] = function() took[#took + 1] = f end
          undo[#undo + 1] = function() cc[f] = orig end
        end
        love.state.prev_state = 'ready'
      end)

      local exits = {
        { 'Ctrl+Shift+S', { 'lctrl', 'lshift', 's' } },
        { 'Ctrl+T', { 'lctrl', 't' } },
        { 'Ctrl+Q', { 'lctrl', 'q' } },
        { 'Ctrl+Shift+R', { 'lctrl', 'lshift', 'r' } },
        { 'Ctrl+Alt+R', { 'lctrl', 'lalt', 'r' } },
      }
      for _, e in ipairs(exits) do
        it(e[1] .. ' asks about the draft left behind', function()
          open()
          draft("local lib = require('lib')\nkept = 99")
          chord('lctrl', 'j')
          assert.same('lib.lua', ed:get_active_buffer().name)

          chord(unpack(e[2]))

          assert.same('discard', ed.pending_confirm)
          assert.same({}, took)
          assert.same('main.lua', ed:get_active_buffer().name)
          assert.same('edit', ed:get_mode())
          assert.same("local lib = require('lib')\nkept = 99",
            string.unlines(ed.input:get_text()))
        end)
      end

      for _, m in ipairs({ { 'search', 'f' }, { 'reorder', 'm' } }) do
        it('Ctrl+Q from ' .. m[1] .. ' asks about the draft', function()
          open()
          draft("local lib = require('lib')\nkept = 99")
          chord('lctrl', 'j')
          chord('lctrl', m[2])
          assert.same(m[1], ed:get_mode())

          chord('lctrl', 'q')
          assert.same('discard', ed.pending_confirm)
          assert.same({}, took)
          assert.same('main.lua', ed:get_active_buffer().name)
          assert.same('edit', ed:get_mode())
        end)
      end

      it('Ctrl+Shift+S asks about each change in turn', function()
        open()
        draft("local lib = require('lib')\nkept = 99")
        chord('lctrl', 'j')
        draft('libvalue = 2')
        chord('lctrl', 'lshift', 's')
        assert.same('lib.lua', ed:get_active_buffer().name)
        chord('return')

        assert.same('discard', ed.pending_confirm)
        assert.same('main.lua', ed:get_active_buffer().name)
        assert.same('editor', love.state.app_state)
        chord('return')
        assert.same('ready', love.state.app_state)
      end)

      it('a second question hears the next key', function()
        open()
        draft("local lib = require('lib')\nkept = 99")
        chord('lctrl', 'j')
        draft('libvalue = 2')
        chord('lctrl', 'q')
        chord('return')
        assert.same('main.lua', ed:get_active_buffer().name)
        assert.same('discard', ed.pending_confirm)

        chord('escape')
        assert.is_nil(ed.pending_confirm)
        assert.same('edit', ed:get_mode())
        assert.same({}, took)
      end)

      it("on the device a Space's press answers one question only",
        function()
          open()
          draft("local lib = require('lib')\nkept = 99")
          chord('lctrl', 'j')
          draft('libvalue = 2')
          chord('lctrl', 'q')
          --- the glyph, then the key
          F.session.type(' ')
          F.session.press('space')
          F.session.release('space')
          assert.same('discard', ed.pending_confirm)
          assert.same('main.lua', ed:get_active_buffer().name)
          assert.same({}, took)
        end)

      it('keeping the draft stays on its file, the others closed',
        function()
          open()
          draft("local lib = require('lib')\nkept = 99")
          chord('lctrl', 'j')
          chord('lctrl', 'q')
          chord('escape')

          assert.same(1, ed.model.buffers:length())
          assert.same('main.lua', ed:get_active_buffer().name)
          assert.same('edit', ed:get_mode())
          assert.same({}, took)
        end)

      it('a Space held from before the question answers nothing',
        function()
          open()
          draft("local lib = require('lib')\nkept = 99")
          chord('lctrl', 'j')
          draft('libvalue = 2')
          F.session.press('space')
          chord('lctrl', 'q')
          assert.same('discard', ed.pending_confirm)
          for _ = 1, 3 do
            F.session.repeat_press('space')
            F.session.type(' ')
          end
          F.session.release('space')
          assert.same('discard', ed.pending_confirm)
          assert.same('lib.lua', ed:get_active_buffer().name)
          assert.same({}, took)
        end)

      it('a modifier does not let a held Space answer', function()
        open()
        draft("local lib = require('lib')\nkept = 99")
        chord('lctrl', 'j')
        draft('libvalue = 2')
        chord('lctrl', 'q')
        F.session.press('space')
        F.session.type(' ')
        assert.same('main.lua', ed:get_active_buffer().name)
        F.love_update(1)
        chord('lshift')
        F.session.repeat_press('space')
        F.session.type(' ')
        F.session.release('space')

        assert.same('discard', ed.pending_confirm)
        assert.same('main.lua', ed:get_active_buffer().name)
        assert.same({}, took)
      end)

      it('a held Enter answers one question', function()
        open()
        draft("local lib = require('lib')\nkept = 99")
        chord('lctrl', 'j')
        draft('libvalue = 2')
        chord('lctrl', 'q')
        F.session.press('return')
        for _ = 1, 3 do F.session.repeat_press('return') end
        F.session.release('return')

        assert.same('discard', ed.pending_confirm)
        assert.same('main.lua', ed:get_active_buffer().name)
        assert.same({}, took)
      end)

      it('a held Space on the device answers one question', function()
        open()
        draft("local lib = require('lib')\nkept = 99")
        chord('lctrl', 'j')
        draft('libvalue = 2')
        chord('lctrl', 'q')
        --- the glyph, then the key; then held
        F.session.type(' ')
        F.session.press('space')
        for _ = 1, 3 do
          F.session.type(' ')
          F.session.repeat_press('space')
        end
        F.session.release('space')

        assert.same('discard', ed.pending_confirm)
        assert.same('main.lua', ed:get_active_buffer().name)
        assert.same({}, took)
        --- a fresh Space answers
        F.session.type(' ')
        F.session.press('space')
        F.session.release('space')
        assert.same({ 'quit_project' }, took)
      end)

      it('takes the exit once the draft is answered', function()
        open()
        draft("local lib = require('lib')\nkept = 99")
        chord('lctrl', 'j')
        chord('lctrl', 'q')
        chord('return')

        assert.same({ 'quit_project' }, took)
        assert.same({}, writes)
      end)
    end)

    it('leaves an error message behind', function()
      open()
      ed:refuse({ 'a message about main.lua' })
      chord('lctrl', 'j')

      assert.is_false(ed.input:has_error())
    end)
  end)
end)
