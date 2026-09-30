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
    -- Entering reorder or search saves the clipboard state
    -- (EditorController:set_mode -> save_state), and the
    -- input fixture's love has no `system` — the same stub
    -- editor_spec.lua sets per case.
    love.system = {
      getClipboardText = function() return '' end,
      setClipboardText = function() end,
    }
    ed = open_file()
  end)

  --- Load the selected block and modify it: Enter opens it
  --- (the rework's spec 2.2), and the edit makes it dirty.
  local function open_dirty_block()
    F.session.press('return')
    ed.input:set_text(
      string.lines(mock_func_snippet('renamed')))
  end

  describe('bare Escape', function()
    -- D-EDITOR-KEYS row 2: bare Escape does NOTHING in
    -- navigation and in editing. The tree used to disagree in
    -- both, through one path — the key is unclaimed in
    -- _normal_mode_keys, falls through to the widget, and the
    -- widget turned it into a destructive cancel. The key
    -- still falls through; what changed is that the editor's
    -- widget seats no lifecycle flags, so the cancel does
    -- nothing (doc/development/decisions/input.md,
    -- D-LIFECYCLE-FLAGS, statement 3). Navigation's half is
    -- pinned next door, in input_widget_callbacks_spec.lua,
    -- "editor Escape falls through to the widget"; this is
    -- the editing half, and it is the one that cost a user
    -- something.

    -- FLIPPED as its FLIP comment said it would be: the case
    -- asserted the loss until D-LIFECYCLE-FLAGS landed, and
    -- now asserts the contract. It is the breaking test for
    -- the edit-mode data loss (that decision's acceptance
    -- criterion 2), so it asserts the block's CONTENT rather
    -- than which callback fired — the pins that assert order
    -- stayed green all the way through the defect.
    it('leaves the open block untouched', function()
      open_dirty_block()
      -- A COPY, not the model's own table: comparing the
      -- widget's text against a reference into it would pass
      -- whatever the cancel did to it.
      local block = string.lines(mock_func_snippet('renamed'))
      assert.same(block, ed.input:get_text())

      F.session.press('escape')

      assert.same(block, ed.input:get_text())
      assert.same('edit', ed:get_mode())
    end)

    -- The fourth of the four states the contract says bare
    -- Escape IS claimed in, and the only one the suite did
    -- not hold: editor_spec.lua presses it at a reorder edge
    -- as setup and asserts nothing about it. Contract-
    -- conforming today, so no FLIP — it must survive
    -- D-LIFECYCLE-FLAGS untouched, which is what makes it
    -- worth pinning before that lands.
    it('cancels a block reorder', function()
      F.session.press('lctrl')
      F.session.press('m')
      assert.same('reorder', ed:get_mode())

      F.session.press('escape')

      assert.same('nav', ed:get_mode())
    end)
  end)

  describe('the whole-editor exits', function()
    -- D-EDITOR-KEYS statement 6. Both leave the editor
    -- through ConsoleController:finish_edit, which stores
    -- the clipboard and drops the buffers with no acceptance
    -- step. Both ask the rework's discard question first
    -- when an open block holds a change
    -- (EditorController:ask_to_leave).
    local left, ran, orig_finish, orig_run

    before_each(function()
      left, ran = false, false
      orig_finish = F.cc.finish_edit
      orig_run = F.cc.run_project
      F.cc.finish_edit = function() left = true end
      F.cc.run_project = function() ran = true end
    end)

    after_each(function()
      F.cc.finish_edit = orig_finish
      F.cc.run_project = orig_run
    end)

    -- FLIPPED: this case pinned the silent loss until the
    -- chord learned to ask, as the gate's exits did.
    it('Ctrl+Shift+S asks before it drops a changed block', function()
      open_dirty_block()

      F.session.press('lctrl')
      F.session.press('lshift')
      F.session.press('s')
      F.session.release('s')
      F.session.release('lshift')
      F.session.release('lctrl')

      assert.is_false(left)
      assert.same('discard', ed.pending_confirm)
      assert.same('edit', ed:get_mode())

      F.session.press('return')
      assert.is_true(left)
      --- confirmed: the change is discarded, not written
      assert.same({}, saved)
    end)

    it('Ctrl+Shift+S held keeps its question open', function()
      open_dirty_block()
      F.session.press('lctrl')
      F.session.press('lshift')
      F.session.press('s')
      for _ = 1, 3 do
        F.session.repeat_press('s')
        assert.same('discard', ed.pending_confirm)
      end
      F.session.release('s')
      F.session.release('lshift')
      F.session.release('lctrl')
      assert.is_false(left)
    end)

    for _, mode in ipairs({ 'search', 'reorder' }) do
      it('Ctrl+T leaves nothing from ' .. mode, function()
        F.session.press('lctrl')
        F.session.press(mode == 'search' and 'f' or 'm')
        F.session.release(mode == 'search' and 'f' or 'm')
        assert.same(mode, ed:get_mode())
        F.session.press('t')
        F.session.release('t')
        F.session.release('lctrl')
        assert.is_false(left)
        assert.is_false(ran)
      end)
    end

    it('a space typed after Enter answered Shift+Esc is kept', function()
      open_dirty_block()
      F.session.press('lshift')
      F.session.press('escape')
      F.session.release('escape')
      F.session.release('lshift')
      F.session.press('return')
      F.session.release('return')
      assert.same('nav', ed:get_mode())

      F.session.type(' ')
      --- in navigation a glyph opens the block, with it
      assert.is_truthy(string.unlines(ed.input:get_text()):find('^ '))
    end)

    it('a held Shift+Esc keeps its question open', function()
      open_dirty_block()
      F.session.press('lshift')
      F.session.press('escape')
      assert.same('discard', ed.pending_confirm)
      for _ = 1, 3 do
        F.session.repeat_press('escape')
        assert.same('discard', ed.pending_confirm)
      end
      F.session.release('escape')
      F.session.release('lshift')
    end)

    it('Ctrl+Shift+S asks, and Escape keeps the block', function()
      open_dirty_block()
      local draft = ed.input:get_text():items()
      F.session.press('lctrl')
      F.session.press('lshift')
      F.session.press('s')
      F.session.release('s')
      F.session.release('lshift')
      F.session.release('lctrl')

      F.session.press('escape')
      assert.is_false(left)
      assert.is_nil(ed.pending_confirm)
      assert.same('edit', ed:get_mode())
      assert.same(draft, ed.input:get_text():items())
    end)

    -- FLIPPED: this case pinned the silent loss until the
    -- gate's exits learned to ask.
    it('Ctrl+T asks before it drops a changed block', function()
      open_dirty_block()

      F.session.press('lctrl')
      F.session.press('t')
      F.session.release('t')
      F.session.release('lctrl')

      assert.is_false(left)
      assert.is_false(ran)
      assert.same('discard', ed.pending_confirm)
      assert.same('edit', ed:get_mode())

      F.session.press('return')
      assert.is_true(left)
      assert.is_true(ran)
      --- confirmed: the change is discarded, not written
      assert.same({}, saved)
    end)
  end)

  describe('the project exits ask first', function()
    -- Ctrl+T and the project chords reach the console before
    -- the editor sees their key. With a changed block open,
    -- each asks Shift+Esc's question; Enter or Space takes
    -- the exit, anything else keeps the block.
    local stubbed = { 'quit_project', 'reset', 'restart', 'run_project' }
    local orig, took = {}, {}

    before_each(function()
      love.state.prev_state = 'ready'
      took = {}
      for _, f in ipairs(stubbed) do
        orig[f] = F.cc[f]
        F.cc[f] = function() took[#took + 1] = f end
      end
    end)

    after_each(function()
      for _, f in ipairs(stubbed) do F.cc[f] = orig[f] end
      F.cc.swallow_key, F.cc.swallow_glyph = nil, nil
    end)

    local function chord(keys)
      for _, k in ipairs(keys) do F.session.press(k) end
      for i = #keys, 1, -1 do F.session.release(keys[i]) end
    end

    local chords = {
      { 'Ctrl+T', { 'lctrl', 't' }, 'run_project' },
      { 'Ctrl+Q', { 'lctrl', 'q' }, 'quit_project' },
      { 'Ctrl+Shift+R', { 'lctrl', 'lshift', 'r' }, 'reset' },
      { 'Ctrl+Alt+R', { 'lctrl', 'lalt', 'r' }, 'restart' },
    }
    for _, c in ipairs(chords) do
      local name, keys, exit = c[1], c[2], c[3]

      it(name .. ' asks, and Escape keeps the block', function()
        open_dirty_block()
        local draft = ed.input:get_text():items()
        chord(keys)
        assert.same('discard', ed.pending_confirm)
        assert.same({}, took)

        F.session.press('escape')
        assert.is_nil(ed.pending_confirm)
        assert.same('edit', ed:get_mode())
        assert.same(draft, ed.input:get_text():items())
        assert.same({}, took)
      end)

      it(name .. ' asks, and Enter discards and leaves', function()
        open_dirty_block()
        chord(keys)
        F.session.press('return')

        assert.same({ exit }, took)
        assert.same({}, saved)
      end)
    end

    it('the Space that confirms types nowhere after', function()
      --- a quit closes the editor, so the glyph meets the
      --- console
      F.cc.quit_project = function()
        took[#took + 1] = 'quit_project'
        orig.quit_project(F.cc)
      end
      local closed = F.cc.close_project
      finally(function() F.cc.close_project = closed end)
      F.cc.close_project = function() end
      open_dirty_block()
      chord({ 'lctrl', 'q' })
      --- a desktop keyboard: the key, then its glyph
      F.session.press('space')
      F.session.type(' ')
      assert.same({ 'quit_project' }, took)
      assert.same('ready', love.state.app_state)
      assert.same('', string.unlines(F.cc.input:get_text()))
    end)

    for _, between in ipairs({
      { 'a Shift press', function() F.session.press('lshift') end },
      { "the Space's repeat",
        function() F.session.repeat_press('space') end },
    }) do
      it('the Space that confirms types nowhere after '
        .. between[1], function()
          F.cc.quit_project = function()
            took[#took + 1] = 'quit_project'
            orig.quit_project(F.cc)
          end
          local closed = F.cc.close_project
          finally(function() F.cc.close_project = closed end)
          F.cc.close_project = function() end
          open_dirty_block()
          chord({ 'lctrl', 'q' })
          F.session.press('space')
          between[2]()
          F.session.type(' ')
          assert.same({ 'quit_project' }, took)
          assert.same('', string.unlines(F.cc.input:get_text()))
        end)
    end

    it('the Space that confirms presses nothing after', function()
      open_dirty_block()
      chord({ 'lctrl', 'q' })
      --- the device: the glyph, then the key
      F.session.type(' ')
      assert.same({ 'quit_project' }, took)
      local route = love.keypressed
      local reached = {}
      finally(function() love.keypressed = route end)
      love.keypressed = function(k) reached[#reached + 1] = k end
      F.session.press('space')
      assert.same({}, reached)
    end)

    it('a glyph with no key press after it swallows nothing later',
      function()
        open_dirty_block()
        chord({ 'lctrl', 'q' })
        --- an on-screen keyboard: the glyph alone
        F.session.type(' ')
        assert.same({ 'quit_project' }, took)
        F.session.type('a')
        local route = love.keypressed
        local reached = {}
        finally(function() love.keypressed = route end)
        love.keypressed = function(k) reached[#reached + 1] = k end
        F.session.press('space')
        assert.same({ 'space' }, reached)
      end)

    it('a glyph-only confirmation holds back no later Space press',
      function()
        open_dirty_block()
        chord({ 'lctrl', 't' })
        --- an on-screen keyboard: the glyph, and no key press
        F.session.type(' ')
        assert.same({ 'run_project' }, took)
        F.love_update(1)
        local route = love.keypressed
        local reached = {}
        finally(function() love.keypressed = route end)
        love.keypressed = function(k) reached[#reached + 1] = k end
        --- the next frame, a physical Space: key first
        F.session.press('space')
        assert.same({ 'space' }, reached)
      end)

    it('Ctrl+Space confirms and holds no glyph back', function()
      open_dirty_block()
      chord({ 'lctrl', 'q' })
      F.session.press('lctrl')
      F.session.press('space')
      F.session.release('space')
      F.session.release('lctrl')
      assert.same({ 'quit_project' }, took)
      assert.is_nil(F.cc.swallow_glyph)
    end)

    it("the chord's own glyph answers nothing", function()
      open_dirty_block()
      F.session.press('lctrl')
      F.session.press('q')
      --- the device leaks a chord's glyph after its key
      F.session.type('q')
      assert.same('discard', ed.pending_confirm)
      assert.same({}, took)
    end)

    it('an unchanged open block leaves without asking', function()
      F.session.press('return')
      assert.same('edit', ed:get_mode())
      chord({ 'lctrl', 'q' })
      assert.same({ 'quit_project' }, took)
      assert.is_nil(ed.pending_confirm)
    end)
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
      '_normal_mode_keys', '_search_mode_keys', '_reorg_mode_keys',
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
      edit    = function()
        F.session.press('return')
        F.session.release('return')
      end,
      search  = function()
        F.session.press('lctrl')
        F.session.press('f')
        F.session.release('f')
        F.session.release('lctrl')
      end,
      reorder = function()
        F.session.press('lctrl')
        F.session.press('m')
        F.session.release('m')
        F.session.release('lctrl')
      end,
    }

    for _, mode in ipairs({ 'nav', 'edit', 'search', 'reorder' }) do
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

    it('a question does not outlive the editor', function()
      local cc = F.cc
      local keep = {
        run_project = cc.run_project,
        checkpoint_modtime = cc.checkpoint_modtime,
        file_modtime = cc.file_modtime,
        restore_checkpoint = cc.restore_checkpoint,
      }
      finally(function()
        for f, v in pairs(keep) do cc[f] = v end
      end)
      local restored = false
      cc.run_project = function() end
      cc.checkpoint_modtime = function() return 1752400000 end
      cc.file_modtime = function() return 1752480000 end
      cc.restore_checkpoint = function() restored = true end
      F.session.press('lctrl')
      F.session.press('lshift')
      F.session.press('k')
      F.session.release('k')
      F.session.release('lshift')
      F.session.release('lctrl')
      assert.same('restore', ed.pending_confirm)

      F.session.press('lctrl')
      F.session.press('t')
      F.session.release('t')
      F.session.release('lctrl')
      assert.same('ready', love.state.app_state)

      ed = open_file()
      love.state.app_state = 'editor'
      F.session.press('return')

      --- Enter opened the block: no hidden question took it
      assert.same('edit', ed:get_mode())
      assert.is_false(restored)
    end)

    it('a program starts with no key held back', function()
      F.cc.swallow_key = 'space'
      F.run_project()
      assert.is_nil(F.cc.swallow_key)
    end)

    it('Shift+Esc on the last buffer leaves under DEBUG', function()
      love.debug = { }
      F.session.press('lshift')
      F.session.press('escape')
      F.session.release('escape')
      F.session.release('lshift')

      assert.same('ready', love.state.app_state)
      assert.is_nil(ed:get_active_buffer())
    end)
  end)

  describe('the project boundary', function()
    -- The editor's buffers belong to the project they were
    -- opened in. The gate's project shortcuts reach the
    -- console before the editor sees the key, so they must
    -- close it themselves, or its buffers outlive the project
    -- and write into the next one.
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

    local chords = {
      ['Ctrl+Q']       = { 'lctrl', 'q' },
      ['Ctrl+Shift+R'] = { 'lctrl', 'lshift', 'r' },
      ['Ctrl+Alt+R']   = { 'lctrl', 'lalt', 'r' },
    }
    for name, keys in pairs(chords) do
      it(name .. ' closes the editor', function()
        for _, k in ipairs(keys) do F.session.press(k) end

        assert.is_not.equal('editor', love.state.app_state)
        assert.is_nil(ed:get_active_buffer())
      end)
    end

    it('Ctrl+Alt+R keeps the way back for Ctrl+T', function()
      F.session.press('lctrl')
      F.session.press('lalt')
      F.session.press('r')

      assert.same('main.lua', love.state.editor.buffer.filename)
    end)

    it('closing a project forgets the quick switch', function()
      love.state.editor = ed:get_state()
      F.cc:_close_project()
      assert.is_nil(love.state.editor)
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
