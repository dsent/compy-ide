-- Availability: the contract predates this feature — it is
-- @dsent's, authorized on UX grounds, and was retrofitted
-- into doc/development/decisions/input.md, D-EDITOR-KEYS on
-- 2026-09-06. What is new here is the net under it.

-- THE REGRESSION NET FOR THE EDITOR'S KEY CONTRACT, and it
-- pins what the tree DOES rather than what the contract says
-- it should. Our tree violates the bare-Escape row today, so
-- a case written against the contract would be red on arrival
-- and would read as a failure rather than as a baseline.
--
-- Every case the contract says must change carries a `FLIP:`
-- comment naming the decision that inverts it. A FLIP case
-- going red is evidence that change landed; a case going red
-- anywhere else is the regression this file exists to catch.
--
-- Cases marked `(w/o confirmation)` pin a KNOWN DEFECT at the
-- behaviour the release knowingly ships — see
-- doc/development/decisions/input.md, D-EDITOR-KEYS statement
-- 6, and doc/development/technical_debt/input.md,
-- T-EXITS-BYPASS-GUARD for the fix that is recommended and
-- not scheduled. They are pinned rather than left open so the
-- exits are inside the net; the marker is what stops a green
-- test from reading as a specification.
--
-- Every case drives the FULL ROUTE (F.session), not
-- EditorController:keypressed directly: the contract's
-- bare-Escape row binds what happens AFTER routing, and the
-- rest of the suite's Escape coverage drives the controller.
-- The states the editor already claims — an error message, a
-- confirmation dialog, search — are pinned by the imported
-- tests/editor/editor_spec.lua and are cited rather than
-- duplicated here.

local F  = require('tests.helpers.input_fixture')
local mock = require('tests.mock')
require('tests.helpers.codesnippets')

describe('editor key contract #input', function()
  setup(function() F.setup() end)
  teardown(function() F.teardown() end)

  local ed, saved

  --- Open a file in the real editor, recording every write.
  local function open_file()
    saved = {}
    local body = mock_func_snippet('one')
    F.cc.editor:open('main.lua', body .. '\n',
      function(content)
        saved[#saved + 1] = string.unlines(content)
        return true
      end)
    return F.cc.editor
  end

  before_each(function()
    F.reset()
    love.state.app_state = 'editor'
    -- A run from the editor keeps the clipboard
    -- (EditorController:hide), and the input fixture's love
    -- has no `system` — the same stub editor_spec.lua sets per
    -- case.
    love.system = {
      getClipboardText = function() return '' end,
      setClipboardText = function() end,
    }
    ed = open_file()
  end)

  --- Begin a replacement of the first block (Edit, IS5.1)
  --- and change its draft.
  local function open_dirty_block()
    ed:get_active_buffer():set_selection(1)
    F.session.press('f2')
    F.session.release('f2')
    ed.input:set_text(
      string.lines(mock_func_snippet('renamed')))
  end

  describe('bare Escape', function()
    -- IS5.7: bare Escape aborts the edit at once, with no
    -- question; the draft and the replacement target go, and
    -- the file keeps its text.
    it('drops the edit at once and writes nothing', function()
      open_dirty_block()
      assert.same('replacing', ed:state_name())

      F.session.press('escape')
      F.session.release('escape')

      assert.same('browsing', ed:state_name())
      assert.is_true(ed.input:is_empty())
      assert.is_nil(ed:get_active_buffer().loaded)
      assert.same({}, saved)
      assert.same('editor', love.state.app_state)
    end)
  end)

  describe('the whole-editor exits', function()
    -- D-EDITOR-KEYS statement 6. Ctrl+Shift+S leaves the
    -- editor through ConsoleController:finish_edit, which
    -- drops the buffers with no acceptance step; Ctrl+T steps
    -- aside for the run through hide_editor, which keeps them.
    local left, ran, orig_finish, orig_hide, orig_run

    before_each(function()
      left, ran = false, false
      orig_finish = F.cc.finish_edit
      orig_hide = F.cc.hide_editor
      orig_run = F.cc.run_project
      F.cc.finish_edit = function() left = true end
      F.cc.hide_editor = function() left = true end
      F.cc.run_project = function() ran = true end
    end)

    after_each(function()
      F.cc.finish_edit = orig_finish
      F.cc.hide_editor = orig_hide
      F.cc.run_project = orig_run
    end)

    -- H-NFR4.6 and FR1.2: no exit asks a question. During an
    -- edit the exit is refused with a notice and the edit
    -- stays; once the edit is aborted, the exit is taken.
    local function chord(mods, k)
      for _, m in ipairs(mods) do F.session.press(m) end
      F.session.press(k)
      F.session.release(k)
      for i = #mods, 1, -1 do F.session.release(mods[i]) end
    end

    --- one Escape: the refusal's notice goes and the edit
    --- with it
    local function abort_edit()
      chord({}, 'escape')
      assert.is_false(ed.input:has_error())
      assert.same('browsing', ed:state_name())
      assert.same('editor', love.state.app_state)
    end

    it('Ctrl+Shift+S is refused during an edit, then leaves',
      function()
        open_dirty_block()
        local draft = ed.input:get_text():items()

        chord({ 'lctrl', 'lshift' }, 's')

        assert.is_false(left)
        assert.is_true(ed.input:has_error())
        assert.same('replacing', ed:state_name())
        assert.same(draft, ed.input:get_text():items())

        abort_edit()
        chord({ 'lctrl', 'lshift' }, 's')
        assert.is_true(left)
        assert.same({}, saved)
      end)

    it('Ctrl+T is refused during an edit, then leaves and runs',
      function()
        open_dirty_block()

        chord({ 'lctrl' }, 't')

        assert.is_false(left)
        assert.is_false(ran)
        assert.is_true(ed.input:has_error())
        assert.same('replacing', ed:state_name())

        abort_edit()
        chord({ 'lctrl' }, 't')
        assert.is_true(left)
        assert.is_true(ran)
        assert.same({}, saved)
      end)

    -- The refusal holds back the chord's own key press and
    -- no later one: the Escape after it dismisses the notice
    -- and aborts the edit in the same press (IS5.7).
    it('a refused Ctrl+T swallows no later key', function()
      open_dirty_block()

      chord({ 'lctrl' }, 't')
      assert.is_true(ed.input:has_error())
      assert.is_nil(ed._gate_key)
      assert.same('replacing', ed:state_name())

      chord({}, 'escape')
      assert.is_false(ed.input:has_error())
      assert.same('browsing', ed:state_name())
      assert.same('editor', love.state.app_state)
    end)

    it('nor when the chord\'s key never reaches the editor',
      function()
        open_dirty_block()
        local route = love.keypressed
        love.keypressed = nil
        chord({ 'lctrl' }, 't')
        love.keypressed = route
        assert.is_true(ed.input:has_error())

        chord({}, 'escape')
        assert.is_false(ed.input:has_error())
        assert.same('browsing', ed:state_name())
        assert.same('editor', love.state.app_state)
      end)

    for _, mode in ipairs({ 'search' }) do
      it('Ctrl+T leaves nothing from ' .. mode, function()
        F.session.press('lctrl')
        F.session.press('f')
        F.session.release('f')
        assert.same(mode, ed:get_mode())
        F.session.press('t')
        F.session.release('t')
        F.session.release('lctrl')
        assert.is_false(left)
        assert.is_false(ran)
      end)
    end

  end)

  describe('leaving through the real finish_edit', function()
    -- The stubbed exits above keep the buffers, so they never
    -- saw what the key does after they are gone: the chord's
    -- own 's' went on to the mode's handler, which asked the
    -- emptied editor for its buffer and raised
    -- (editorView.lua, get_current_buffer).
    before_each(function()
      love.state.prev_state = 'ready'
    end)

    local handlers = {
      '_normal_mode_keys', '_search_mode_keys',
    }

    after_each(function()
      F.session.release('s')
      F.session.release('lshift')
      F.session.release('lctrl')
      for _, h in ipairs(handlers) do ed[h] = nil end
      love.debug = nil
    end)

    --- the key that selects each mode from navigation; the
    --- block opened for editing is unchanged, so the chord
    --- has nothing to ask
    local enter = {
      search  = function()
        F.session.press('lctrl')
        F.session.press('f')
        F.session.release('f')
        F.session.release('lctrl')
      end,
    }

    for _, mode in ipairs({ 'nav', 'search' }) do
      it('leaves from ' .. mode .. ' to the console', function()
        if enter[mode] then enter[mode]() end
        assert.same(mode, ed:get_mode())
        --- once the editor is closed, the chord's own key
        --- reaches no mode handler
        local handled = false
        for _, h in ipairs(handlers) do
          ed[h] = function(_, k) handled = handled or k == 's' end
        end

        F.session.press('lctrl')
        F.session.press('lshift')
        F.session.press('s')

        assert.is_false(handled)
        assert.same('ready', love.state.app_state)
        assert.is_nil(ed:get_active_buffer())
      end)
    end

  end)

  describe('the project boundary', function()
    -- The editor's buffers belong to the project they were
    -- opened in. The gate's shortcuts reach the console
    -- before the editor sees the key. Ctrl+Q leaves the
    -- editor for the console and keeps the project open; a
    -- run (Ctrl+Alt+R) keeps the buffers for Ctrl+T, and
    -- closing the project drops them; Ctrl+Shift+R is dropped
    -- (the reserved map of 2026-11-14).
    local stubbed = { 'close_project', 'run_project' }
    local orig = {}

    before_each(function()
      love.state.prev_state = 'ready'
      for _, f in ipairs(stubbed) do
        orig[f] = F.cc[f]
        F.cc[f] = function() end
      end
    end)

    after_each(function()
      for _, f in ipairs(stubbed) do F.cc[f] = orig[f] end
      mock.release_keys()
    end)

    it('Ctrl+Q closes the editor', function()
      F.session.press('lctrl')
      F.session.press('q')

      assert.is_not.equal('editor', love.state.app_state)
      assert.is_nil(ed:get_active_buffer())
    end)

    it('Ctrl+Q leaves from search for the console', function()
      F.session.press('lctrl')
      F.session.press('f')
      F.session.release('f')
      assert.same('search', ed:get_mode())
      F.session.press('q')

      assert.same('ready', love.state.app_state)
      assert.is_nil(ed:get_active_buffer())
      assert.same('nav', ed:get_mode())
    end)

    it('Ctrl+Q closes no project', function()
      local closed = false
      F.cc.close_project = function() closed = true end
      local P = F.cc.model.projects
      local open = P.current
      F.session.press('lctrl')
      F.session.press('q')

      assert.same('ready', love.state.app_state)
      assert.is_false(closed)
      assert.equal(open, P.current)
    end)

    it('Ctrl+Shift+R leaves the editor open', function()
      F.session.press('lctrl')
      F.session.press('lshift')
      F.session.press('r')

      assert.same('editor', love.state.app_state)
      assert.same('main.lua', ed:get_active_buffer().name)
    end)

    it('Ctrl+Alt+R keeps the way back for Ctrl+T', function()
      F.session.press('lctrl')
      F.session.press('lalt')
      F.session.press('r')

      assert.is_not.equal('editor', love.state.app_state)
      assert.same('main.lua', ed:get_active_buffer().name)
    end)

    it('closing a project forgets the quick switch', function()
      F.cc:_close_project()
      assert.is_not.equal('editor', love.state.app_state)
      assert.is_nil(ed:get_active_buffer())
    end)

    it('a buffer saves into its own project', function()
      local P = F.cc.model.projects
      local prev = P.current
      finally(function() P.current = prev end)
      local written = {}
      local function project(name)
        return {
          name = name,
          get_path = function(_, f) return '/nonexistent/' .. f end,
          readfile = function() return true, 'x = 1\n' end,
          writefile = function(_, f)
            written[#written + 1] = name .. '/' .. f
            return true
          end,
        }
      end
      ed:close()
      love.state.app_state = 'ready'
      P.current = project('a')
      F.cc:edit('main.lua')
      local buf = ed:get_active_buffer()

      P.current = project('b')
      buf.save_file({ 'x = 2' })

      assert.same({ 'a/main.lua' }, written)
    end)
  end)
end)
