--- @diagnostic disable: invisible
require("model.editor.editorModel")
require("controller.editorController")
require("view.editor.editorView")
require("view.editor.visibleContent")

local mock, TU

describe('Editor #editor', function()
  setup(function()
    mock = require("tests.mock")
    TU = require('tests.testutil')

    local love = {
      state = {
        --- @type AppState
        app_state = 'ready',
      },
    }
    mock.mock_love(love)
  end)

  local trtl =
  'Turtle graphics game inspired the LOGO family of languages.'

  local turtle_doc = {
    '',
    trtl,
    '',
  }

  --- @param cfg Config
  --- @return EditorController
  --- @return function press
  --- @return EditorView view
  local function wire(cfg)
    local model = EditorModel(cfg)
    local controller = EditorController(model)
    -- this hooks itself back into the controller
    EditorView(cfg.view, controller)
    local function press(...)
      controller:keypressed(...)
    end

    return controller, press, controller.view
  end

  local print_result = "print(sierpinski(4))"
  local sierpinski = {
    "function sierpinski(depth)",
    "  lines = { '*' }",
    "  for e = 2, depth + 1 do",
    "    sp, tmp = string.rep(' ', 2 ^ (e - 2))",
    "    tmp = {}",
    "    for idx, line in ipairs(lines) do",
    "      tmp[idx] = sp .. line .. sp",
    "      tmp[idx + #lines] = line .. ' ' .. line",
    "    end",
    "    lines = tmp",
    "  end",
    [[  return table.concat(lines, '\n')]],
    "end",
    "",
    print_result,
  }

  describe('opens', function()
    it('no wrap needed', function()
      local w = 80
      local controller = wire(TU.mock_view_cfg(w))

      local save = TU.get_save_function(turtle_doc)
      controller:open('turtle', turtle_doc, save)

      local buffer = controller:get_active_buffer()
      local bc = buffer:get_content()

      assert.same(turtle_doc, bc)
      assert.same(#turtle_doc, buffer:get_content_length())

      local sel = buffer:get_selection()
      local sel_t = buffer:get_selected_text()
      --- files open at the first line
      assert.same(1, sel)
      assert.same(turtle_doc[1], sel_t)
    end)
  end)

  describe('plaintext works', function()
    describe('with wrap', function()
      local w = 16
      love.state.app_state = 'editor'

      local controller, press = wire(TU.mock_view_cfg(w))

      local save = TU.get_save_function(turtle_doc)

      controller:open('turtle', turtle_doc, save)

      local buffer = controller:get_active_buffer()
      local start_sel = #turtle_doc

      it('opens', function()
        local bc = buffer:get_content()

        assert.same(turtle_doc, bc)
        assert.same(#turtle_doc, buffer:get_content_length())

        local sel = buffer:get_selection()
        local sel_t = buffer:get_selected_text()
        --- files open at the first line
        assert.same(1, sel)
        assert.same(turtle_doc[1], sel_t)
      end)

      it('interacts', function()
        --- files open at the top; walk to the end first,
        --- as these interactions historically assume it
        for _ = 1, start_sel - 1 do
          mock.keystroke('down', press)
        end
        --- select middle line
        mock.keystroke('up', press)
        assert.same(start_sel - 1, buffer:get_selection())
        assert.same(turtle_doc[2], buffer:get_selected_text())
        --- load it
        local input = function()
          return controller.input:get_text():items()
        end
        mock.keystroke('return', press)
        assert.same({ turtle_doc[2] }, input())
        --- crossing the edge leaves through the gate:
        --- the untouched block flows to the next line
        mock.keystroke('end', press)
        mock.keystroke('down', press)
        assert.same(start_sel, buffer:get_selection())
        assert.same({ '' }, input())
        --- drop it, compose fresh so the text inserts
        mock.keystroke('S-escape', press)
        assert.same({ '' }, input())
        --- compose text (inserted before the empty)
        controller:textinput('-')
        controller:textinput('-')
        controller:textinput(' ')
        controller:textinput('t')
        controller:textinput('e')
        controller:textinput('s')
        controller:textinput('t')
        assert.same({ '-- test' }, input())
        --- replace line with input content
        mock.keystroke('return', press)
        local new = {
          '',
          trtl,
          '-- test',
          ''
        }
        assert.same(new, buffer:get_text_content())
        --- input clears
        assert.same({ '' }, input())
        --- highlight moves down
        assert.same(start_sel + 1, buffer:get_selection())

        mock.keystroke('up', press)
        assert.same(start_sel, buffer:get_selection())
        --- compose over it, then discard and reopen
        controller:textinput('i')
        controller:textinput('n')
        controller:textinput('s')
        controller:textinput('e')
        controller:textinput('r')
        controller:textinput('t')
        assert.same({ 'insert' }, input())
        --- the compose is dirty: the discard asks
        mock.keystroke('S-escape', press)
        --- Enter confirms (repeat-proof dialogs)
        mock.keystroke('return', press)
        mock.keystroke('return', press)
        assert.same({ '-- test' }, input())
      end)
    end)


    describe('with scroll', function()
      local l = 6

      local controller, _, view = wire(TU.mock_view_cfg(80, l))
      local model = controller.model

      local save = TU.get_save_function(sierpinski)
      --- use it as plaintext for this test
      controller:open('sierpinski.txt', sierpinski, save)
      local buf = controller:get_active_buffer()
      local bv = view:open(buf)

      local visible = bv.content
      local scroll = bv.SCROLL_BY

      --- files open at the top now; these specs assume
      --- the historical EOF position, so walk down first
      for _ = 1, #sierpinski do
        controller:keypressed('down')
      end

      local off = #sierpinski - l + 1
      bv:scroll_to(off)
      local start_range = Range(off + 1, #sierpinski + 1)

      local function peek(dir)
        mock.keystroke('C-M-' .. dir, function(kk)
          controller:keypressed(kk)
        end)
      end
      it('loads', function()
        --- selection is at EOF, view at the historical offset
        assert.same(#sierpinski + 1, buf:get_selection())
        assert.same(off, bv:get_offset())
        assert.same(start_range, visible.range)
      end)
      it('follows the active line', function()
        --- walk the line up out of the viewport
        for _ = 1, l + 2 do
          buf:move_line('up')
        end
        local al = buf:get_active_line()
        assert.is_true(al < visible.range.start)
        bv:follow_line()
        assert.is_true(visible.range:inc(al))
        --- and back down below it
        for _ = 1, l + 4 do
          buf:move_line('down')
        end
        bv:follow_line()
        assert.is_true(
          visible.range:inc(buf:get_active_line()))
        --- restore the historical position for the
        --- describes that follow
        buf:move_selection('down', nil, true)
        bv:scroll_to(off)
      end)
      local base = Range(1, l)
      it('scrolls up', function()
        peek('pageup')
        assert.same(start_range:translate(-scroll), visible.range)
        peek('pageup')
        assert.same(start_range:translate(-scroll * 2), visible.range)
        peek('pageup')
        assert.same(start_range:translate(-scroll * 3), visible.range)
        peek('pageup')
      end)
      it('tops out', function()
        assert.same(base, visible.range)
      end)
      it('scrolls down', function()
        peek('pagedown')
        assert.same(base:translate(scroll), visible.range)
        peek('pagedown')
        assert.same(base:translate(scroll * 2), visible.range)
        peek('pagedown')
        assert.same(base:translate(scroll * 3), visible.range)
        peek('pagedown')
        assert.same(base:translate(scroll * 4), visible.range)
        peek('pagedown')
      end)
      it('bottoms out', function()
        local limit = #sierpinski + visible.overscroll
        -- assert.same(Range(limit - l + 2, limit), visible.range)
      end)
    end)

    describe('with scroll and wrap', function()
      local l = 6

      local controller, _, view = wire(TU.mock_view_cfg(27, l))

      local save = TU.get_save_function(sierpinski)
      controller:open('sierpinski.txt', sierpinski, save)

      local function press(...)
        controller:keypressed(...)
      end

      local buffer = controller:get_active_buffer()
      --- @type BufferView
      local bv = view:open(buffer)
      -- bv:open(buffer)

      local visible = bv.content
      local scroll = bv.SCROLL_BY

      --- files open at the top now; these specs assume
      --- the historical EOF position, so walk down first
      for _ = 1, #sierpinski do
        press('down')
      end

      local clen = visible:get_content_length()
      local off = clen - l
      bv:scroll_to(off)
      local start_range = Range(off + 1, clen)
      it('loads', function()
        --- selection is at EOF, view at the historical offset
        assert.same(#sierpinski + 1, buffer:get_selection())
        assert.same(off, bv:get_offset())
        assert.same(start_range, visible.range)
      end)
      local base = Range(1, l)
      describe('scrolls', function()
        it('scrolls up', function()
          mock.keystroke('C-M-pageup', press)
          assert.same(start_range:translate(-scroll), visible.range)
          mock.keystroke('C-M-pageup', press)
          assert.same(start_range:translate(-scroll * 2), visible.range)
          mock.keystroke('C-M-pageup', press)
          assert.same(start_range:translate(-scroll * 3), visible.range)
          mock.keystroke('C-M-pageup', press)
          assert.same(start_range:translate(-scroll * 4), visible.range)
        end)
        it('tops out', function()
          mock.keystroke('C-M-pageup', press)
          assert.same(base, visible.range)
        end)
        it('scrolls down', function()
          mock.keystroke('C-M-pagedown', press)
          assert.same(base:translate(scroll), visible.range)
          mock.keystroke('C-M-pagedown', press)
          assert.same(base:translate(scroll * 2), visible.range)
          mock.keystroke('C-M-pagedown', press)
          assert.same(base:translate(scroll * 3), visible.range)
          mock.keystroke('C-M-pagedown', press)
          assert.same(base:translate(scroll * 4), visible.range)
          mock.keystroke('C-M-pagedown', press)
          assert.same(base:translate(scroll * 5), visible.range)
        end)
        it('bottoms out', function()
          mock.keystroke('C-M-pagedown', press)
          mock.keystroke('C-M-pagedown', press)
          mock.keystroke('C-M-pagedown', press)
          local limit = clen + visible.overscroll
          assert.same(Range(limit - l + 1, limit), visible.range)
        end)

        describe('moving the selection affects scrolling', function()
          --- the walk left the selection at EOF
          assert.same(#sierpinski + 1, buffer:get_selection())

          local function line_visible()
            local al = buffer:get_active_line()
            local wl = visible.wrap_forward[al]
            if not wl then return false end
            for _, v in ipairs(wl) do
              if visible.range:inc(v) then return true end
            end
            return false
          end

          it('from below', function()
            --- scroll away, then a line move pulls it back
            mock.keystroke('C-M-pageup', press)
            mock.keystroke('up', press)
            assert.same(#sierpinski, buffer:get_selection())
            assert.is_true(line_visible())
          end)
          it('to above', function()
            --- walk a screenful up; the line stays in view
            for _ = 1, l do
              mock.keystroke('up', press)
              assert.is_true(line_visible())
            end
          end)
          it('tops out', function()
            for _ = 1, clen do
              mock.keystroke('up', press)
            end
            assert.same(1, buffer:get_selection())
            assert.same(1, buffer:get_active_line())
            assert.same(1, visible.range.start)
          end)
          it('from above', function()
            --- scroll away downwards, a line move follows
            mock.keystroke('C-M-pagedown', press)
            mock.keystroke('C-M-pagedown', press)
            mock.keystroke('down', press)
            assert.same(2, buffer:get_selection())
            assert.is_true(line_visible())
          end)
          it('to below', function()
            for _ = 1, l do
              mock.keystroke('down', press)
              assert.is_true(line_visible())
            end
          end)
          it('bottoms out', function()
            for _ = 1, clen do
              mock.keystroke('down', press)
            end
            --- capped at the phantom line past the end
            local cap = buffer:get_selection()
            mock.keystroke('down', press)
            assert.same(cap, buffer:get_selection())
          end)
        end)
      end)

      describe('peek and page moves', function()
        it('peek scrolls, the selection stays', function()
          mock.keystroke('end', press)
          local sel = buffer:get_selection()
          local r0 = visible.range.start
          mock.keystroke('C-M-pageup', press)
          assert.same(sel, buffer:get_selection())
          assert.is_true(visible.range.start < r0)
          mock.keystroke('C-M-up', press)
          assert.same(sel, buffer:get_selection())
          --- left/right double the page peek
          local r1 = visible.range.start
          mock.keystroke('C-M-right', press)
          assert.same(sel, buffer:get_selection())
          assert.is_true(visible.range.start > r1)
          mock.keystroke('C-M-left', press)
          assert.same(r1, visible.range.start)
        end)
        it('typing after a peek returns the view', function()
          controller:textinput('x')
          local al = buffer:get_active_line()
          local wl = visible.wrap_forward[al]
          local seen = false
          for _, v in ipairs(wl) do
            if visible.range:inc(v) then seen = true end
          end
          assert.is_true(seen)
          --- the typed draft asks; confirm to discard
          mock.keystroke('S-escape', press)
          --- Enter confirms (repeat-proof dialogs)
          mock.keystroke('return', press)
        end)
        it('a held chord glyph is dropped', function()
          mock.keystroke('C-M-down', press, true)
          controller:textinput('q')
          assert.same({ '' }, controller.input:get_text())
          mock.release_keys()
        end)
        it('bare pages move the active line', function()
          mock.keystroke('home', press)
          assert.same(1, buffer:get_active_line())
          mock.keystroke('pagedown', press)
          assert.same(1 + l, buffer:get_active_line())
          assert.is_true(bv:is_selection_visible())
          mock.keystroke('pageup', press)
          assert.same(1, buffer:get_active_line())
          --- restore the state the describes below assume
          mock.keystroke('end', press)
          mock.keystroke('down', press)
        end)
      end)

      describe('Home/End reach the file edges (2.7)', function()
        it('bare End goes to the last line', function()
          mock.keystroke('home', press)
          assert.same(1, buffer:get_selection())
          mock.keystroke('end', press)
          assert.same(#sierpinski + 1, buffer:get_selection())
        end)
        it('Ctrl+Home/End do not warp in nav', function()
          mock.keystroke('home', press)
          local sel = buffer:get_selection()
          mock.keystroke('C-end', press)
          assert.same(sel, buffer:get_selection())
          --- restore what the describes below assume
          mock.keystroke('end', press)
          mock.keystroke('down', press)
        end)
      end)

      describe('jumps', function()
        local sel = table.clone(buffer:get_selection())
        it('to top', function()
          mock.keystroke('C-pageup', press)
          --- scrolls to top
          assert.same(base, visible.range)
          --- and selection is unaffected
          assert.same(sel, buffer:get_selection())
        end)
        it('to bottom', function()
          -- mock.keystroke('C-pagedown', press)
          --- scrolls to bottom
          --- TODO
          -- assert.same(start_range, visible.range)
          --- and selection is unaffected
          assert.same(sel, buffer:get_selection())
        end)
      end)
      describe('warps selection', function()
        mock.keystroke('up', press)
        local sel = table.clone(buffer:get_selection())
        it('to bottom', function()
          mock.keystroke('end', press)
          --- warps to bottom, selection in view
          assert.same(#sierpinski + 1, buffer:get_selection())
          assert.is_true(bv:is_selection_visible())
          -- assert.is_not.same(sel, buffer:get_selection())
        end)
        it('to top', function()
          mock.keystroke('home', press)
          --- warps to top
          assert.same(base, visible.range)
          assert.is_not.same(sel, buffer:get_selection())
        end)
      end)
      describe('input', function()
        local inter = controller.input
        it('loads', function()
          local selected = buffer:get_selected_text()
          mock.keystroke('return', press)
          assert.same(inter:get_text(), { selected })
        end)
        it('flows to the neighbor on Ctrl+move', function()
          --- Ctrl+arrow leaves through the gate; the
          --- untouched block just opens the next one
          mock.keystroke('C-down', press)
          local now = buffer:get_selected_text()
          assert.same({ now }, inter:get_text())
        end)
        it('discards', function()
          --- the loaded text is unchanged, so no ask
          mock.keystroke('S-escape', press)
          assert.same({ '' }, inter:get_text())
        end)
      end)
    end)
  end)
  --- end plaintext

  describe('structured (lua) works', function()
    it('moves the block through the reorder mode', function()
      --- Alt+arrows are scrolling now; blocks move on
      --- Ctrl+M only
      local controller, press = wire(TU.mock_view_cfg())
      local save, savefile = TU.get_save_function(sierpinski)
      controller:open('sierpinski.lua', sierpinski, save)
      --- entering reorder saves the clipboard state
      love.system = {
        getClipboardText = function() return '' end,
        setClipboardText = function() end,
      }
      local buffer = controller:get_active_buffer()
      local first = buffer:get_selected_text()

      mock.keystroke('C-m', press)
      mock.keystroke('down', press)
      mock.keystroke('return', press)
      --- the block moved down, selection follows it,
      --- the commit is written through
      assert.same(2, buffer:get_selection())
      assert.same(first, buffer:get_selected_text())
      assert.same('', string.lines(savefile())[1])

      mock.keystroke('C-m', press)
      mock.keystroke('up', press)
      mock.keystroke('return', press)
      assert.same(1, buffer:get_selection())
      assert.same(first, buffer:get_selected_text())
    end)

    it('Alt+arrows peek without moving', function()
      local controller, press = wire(TU.mock_view_cfg())
      local save = TU.get_save_function(sierpinski)
      controller:open('sierpinski.lua', sierpinski, save)
      local buffer = controller:get_active_buffer()
      local bv = controller.view:get_current_buffer()

      local sel0 = buffer:get_selection()
      local r0 = bv.content:get_range().start
      mock.keystroke('M-down', press)
      assert.same(sel0, buffer:get_selection())
      assert.is_true(bv.content:get_range().start > r0)
      mock.keystroke('M-home', press)
      assert.same(1, bv.content:get_range().start)
      assert.same(sel0, buffer:get_selection())
    end)

    describe('checkpoints (2.6)', function()
      require("tests.helpers.codesnippets")
      local controller, press, buffer, inter
      local calls, cp_time

      before_each(function()
        local f1 = mock_func_snippet('one')
        controller, press = wire(TU.mock_view_cfg())
        local save = TU.get_save_function(f1)
        controller:open('main.lua', f1 .. '\n', save)
        buffer = controller:get_active_buffer()
        inter = controller.input
        calls, cp_time = {}, nil
        controller.console = {
          checkpoint_modtime = function() return cp_time end,
          file_modtime = function() return 1752480000 end,
          write_checkpoint = function(_, name)
            table.insert(calls, 'write:' .. name)
            return true
          end,
          restore_checkpoint = function(_, name)
            table.insert(calls, 'restore:' .. name)
            return true
          end,
          _readfile = function() return 'x = 1' end,
        }
      end)

      it('first checkpoint writes without asking', function()
        mock.keystroke('C-k', press)
        assert.same({ 'write:main.lua' }, calls)
        assert.is_false(inter:has_error())
      end)

      it('an existing one asks, Enter confirms', function()
        cp_time = 1752400000
        mock.keystroke('C-k', press)
        assert.same({}, calls)
        assert.is_true(inter:has_error())
        --- the invoking chord cancels (repeat-proof);
        --- Enter confirms
        mock.keystroke('C-k', press)
        assert.same({}, calls)
        mock.keystroke('C-k', press)
        mock.keystroke('return', press)
        assert.same({ 'write:main.lua' }, calls)
      end)

      it('any other key cancels the confirmation', function()
        cp_time = 1752400000
        mock.keystroke('C-k', press)
        mock.keystroke('escape', press)
        mock.keystroke('C-k', press)
        --- back to asking, not writing
        assert.same({}, calls)
        assert.is_true(inter:has_error())
      end)

      it('restore asks and reloads the buffer', function()
        cp_time = 1752400000
        mock.keystroke('C-S-k', press)
        assert.same({}, calls)
        mock.keystroke('return', press)
        assert.same({ 'restore:main.lua' }, calls)
        --- buffer reloaded from the checkpoint content
        --- (reload replaces the model; re-fetch it)
        local fresh = controller:get_active_buffer()
        assert.same('x = 1',
          fresh:get_text_content()[1])
      end)

      it('restore without a checkpoint refuses', function()
        mock.keystroke('C-S-k', press)
        assert.same({}, calls)
        assert.is_true(inter:has_error())
      end)

      it('in editing, accepts the block first', function()
        mock.keystroke('return', press)
        local changed = mock_func_snippet('changed')
        inter:set_text(string.lines(changed))
        mock.keystroke('C-k', press)
        assert.same('nav', controller:get_mode())
        assert.same({ 'write:main.lua' }, calls)
      end)
    end)

    it('knocks when refused', function()
      require("tests.helpers.codesnippets")
      local controller, press = wire(TU.mock_view_cfg())
      local f1 = mock_func_snippet('one')
      local save = TU.get_save_function(f1)
      controller:open('knock.lua', f1 .. '\n', save)
      local inter = controller.input

      --- walking off the end of the file
      mock.keystroke('end', press)
      local n0 = #mock.played_sounds()
      mock.keystroke('down', press)
      mock.keystroke('down', press)
      local played = mock.played_sounds()
      assert.is_true(#played > n0)
      assert.same('assets/sounds/knock.ogg', played[#played])

      --- and a refused block
      mock.keystroke('home', press)
      mock.keystroke('return', press)
      inter:set_text({ 'function broken(' })
      local n1 = #mock.played_sounds()
      mock.keystroke('C-down', press)
      played = mock.played_sounds()
      assert.is_true(#played > n1)
      assert.same('assets/sounds/knock.ogg', played[#played])
    end)

    describe('Ctrl+Enter blocks (2.7)', function()
      require("tests.helpers.codesnippets")
      local controller, press, buffer, inter

      before_each(function()
        local f1 = mock_func_snippet('one')
        local f2 = mock_func_snippet('two')
        local text = f1 .. '\n\n' .. f2 .. '\n'
        controller, press = wire(TU.mock_view_cfg())
        local save = TU.get_save_function(text)
        controller:open('ce.lua', text, save)
        buffer = controller:get_active_buffer()
        inter = controller.input
      end)

      it('does not touch the file in nav', function()
        local text0 = string.unlines(
          buffer:get_text_content())
        local n0 = buffer:get_content_length()
        mock.keystroke('C-return', press)
        --- the block appears on acceptance, not now
        assert.same(n0, buffer:get_content_length())
        assert.same(text0, string.unlines(
          buffer:get_text_content()))
      end)

      it('opens a fresh block below in nav', function()
        assert.same(1, buffer:get_selection())
        mock.keystroke('C-return', press)
        assert.same('edit', controller:get_mode())
        assert.is_true(inter:is_empty())
        --- composing lands after the first block
        assert.same(2, buffer:get_selection())
        local n = buffer:get_content_length()
        inter:set_text({ 'x = 1' })
        mock.keystroke('return', press)
        assert.same(n + 1, buffer:get_content_length())
        assert.same({ 'x = 1' },
          buffer:get_content():get(2):to_lines())
      end)

      it('opens a fresh block above with Shift', function()
        mock.keystroke('C-down', press)
        local sel = buffer:get_selection()
        mock.keystroke('C-S-return', press)
        assert.same('edit', controller:get_mode())
        assert.is_true(inter:is_empty())
        --- composing lands at the block's own place
        assert.same(sel, buffer:get_selection())
      end)

      it('accepts the open block in edit', function()
        mock.keystroke('return', press)
        local changed = mock_func_snippet('renamed')
        inter:set_text(string.lines(changed))
        mock.keystroke('C-return', press)
        assert.same('nav', controller:get_mode())
        assert.same(1, buffer:get_selection())
        assert.truthy(string.find(
          string.unlines(buffer:get_text_content()),
          'renamed', 1, true))
      end)
    end)

    describe('typing in navigation (2.1)', function()
      require("tests.helpers.codesnippets")
      local controller, press, buffer, inter

      before_each(function()
        local f1 = mock_func_snippet('one')
        local text = f1 .. '\n\n'
        controller, press = wire(TU.mock_view_cfg())
        local save = TU.get_save_function(text)
        controller:open('typing.lua', text, save)
        buffer = controller:get_active_buffer()
        inter = controller.input
      end)

      it('opens the block and makes room on the line',
        function()
          --- stand on the middle line of the function
          mock.keystroke('down', press)
          assert.same(2, buffer:get_active_line())
          local before = buffer:get_selected_text()

          controller:textinput('x')
          assert.same('edit', controller:get_mode())
          --- the block is open, one line longer, and the
          --- character sits on a fresh line 2
          local t = inter:get_text()
          assert.same(#before + 1, #t)
          assert.same('x', t[2])
          assert.same(before[1], t[1])
          assert.same(before[2], t[3])
        end)

      it('a blank line becomes a new block', function()
        --- the trailing empty block
        mock.keystroke('end', press)
        assert.is_true(
          buffer:_get_selected_block():is_empty())

        controller:textinput('y')
        assert.same('edit', controller:get_mode())
        --- nothing was loaded: the text composes fresh
        assert.same({ 'y' }, inter:get_text())
      end)

      it('never overwrites the block typed on', function()
        mock.keystroke('down', press)
        controller:textinput('-')
        controller:textinput('-')
        mock.keystroke('return', press)
        --- the function survives, with the comment in it
        local all = string.unlines(
          buffer:get_text_content())
        assert.truthy(
          string.find(all, 'function one()', 1, true))
        assert.truthy(string.find(all, '--', 1, true))
      end)
    end)

    describe('block undo (1.1)', function()
      require("tests.helpers.codesnippets")
      local controller, press, buffer, savefile

      before_each(function()
        local f1 = mock_func_snippet('one')
        local f2 = mock_func_snippet('two')
        local text = f1 .. '\n\n' .. f2 .. '\n'
        controller, press = wire(TU.mock_view_cfg())
        local save
        save, savefile = TU.get_save_function(text)
        controller:open('bu.lua', text, save)
        love.system = {
          getClipboardText = function() return '' end,
          setClipboardText = function() end,
        }
        buffer = controller:get_active_buffer()
      end)

      it('undoes an acceptance, file steps back', function()
        local orig = string.unlines(
          buffer:get_text_content())
        mock.keystroke('return', press)
        controller.input:set_text(
          string.lines(mock_func_snippet('renamed')))
        mock.keystroke('return', press)
        assert.truthy(string.find(savefile(), 'renamed',
          1, true))

        mock.keystroke('C-z', press)
        --- back in the file, block not reopened
        assert.same('nav', controller:get_mode())
        assert.same(orig, string.unlines(
          buffer:get_text_content()))
        assert.same(orig, savefile())
        --- redo returns the accepted state
        mock.keystroke('C-y', press)
        assert.truthy(string.find(
          string.unlines(buffer:get_text_content()),
          'renamed', 1, true))
      end)

      it('undoes a block deletion', function()
        local orig = string.unlines(
          buffer:get_text_content())
        mock.keystroke('C-delete', press)
        assert.falsy(string.find(
          string.unlines(buffer:get_text_content()),
          'function one()', 1, true))
        mock.keystroke('C-z', press)
        assert.same(orig, string.unlines(
          buffer:get_text_content()))
      end)

      it('undoes a reorder block move', function()
        local orig = string.unlines(
          buffer:get_text_content())
        mock.keystroke('C-m', press)
        mock.keystroke('down', press)
        mock.keystroke('return', press)
        assert.is_not.same(orig, string.unlines(
          buffer:get_text_content()))
        mock.keystroke('C-z', press)
        assert.same(orig, string.unlines(
          buffer:get_text_content()))
      end)

      it('discard asks, and undo brings the draft back',
        function()
          local orig = string.unlines(
            buffer:get_text_content())
          mock.keystroke('return', press)
          controller.input:set_text(
            string.lines(mock_func_snippet('draft')))

          --- first press asks, still editing
          mock.keystroke('S-escape', press)
          assert.same('edit', controller:get_mode())
          assert.is_true(controller.input:has_error())

          --- Enter confirms; the file untouched
          mock.keystroke('return', press)
          assert.same('nav', controller:get_mode())
          assert.same(orig, string.unlines(
            buffer:get_text_content()))

          --- one undo: the parseable draft lands in
          --- the file; another: gone again (the pair)
          mock.keystroke('C-z', press)
          assert.truthy(string.find(
            string.unlines(buffer:get_text_content()),
            'draft', 1, true))
          mock.keystroke('C-z', press)
          assert.same(orig, string.unlines(
            buffer:get_text_content()))
        end)

      it('any other key cancels the discard ask',
        function()
          mock.keystroke('return', press)
          controller.input:set_text({ 'x = 1' })
          mock.keystroke('S-escape', press)
          mock.keystroke('down', press)
          --- still editing, the ask is gone
          assert.same('edit', controller:get_mode())
          assert.is_nil(controller.pending_confirm)
        end)

      it('a broken draft discards without the pair',
        function()
          local orig = string.unlines(
            buffer:get_text_content())
          local n0 = #buffer.history
          mock.keystroke('return', press)
          controller.input:set_text(
            { 'function broken(' })
          mock.keystroke('S-escape', press)
          --- Enter confirms (repeat-proof dialogs)
          mock.keystroke('return', press)
          assert.same('nav', controller:get_mode())
          --- nothing recoverable was recorded
          assert.same(n0, #buffer.history)
          assert.same(orig, string.unlines(
            buffer:get_text_content()))
        end)

      it('bare Delete drops the block, undoably',
        function()
          local orig = string.unlines(
            buffer:get_text_content())
          local n0 = buffer:get_content_length()
          mock.keystroke('delete', press)
          assert.same(n0 - 1,
            buffer:get_content_length())
          mock.keystroke('C-z', press)
          assert.same(orig, string.unlines(
            buffer:get_text_content()))
        end)

      it('checkpoint restore clears the history',
        function()
          mock.keystroke('C-m', press)
          mock.keystroke('down', press)
          mock.keystroke('return', press)
          assert.is_true(#buffer.history > 0)
          --- a restore rebuilds the buffer: reload
          controller:reload_active(string.unlines(
            buffer:get_text_content()))
          local fresh = controller:get_active_buffer()
          assert.same(0, #fresh.history)
        end)

      it('knocks on empty history', function()
        local n0 = #mock.played_sounds()
        mock.keystroke('C-z', press)
        assert.is_true(#mock.played_sounds() > n0)
      end)

      it('a new write kills the redo tail', function()
        mock.keystroke('C-m', press)
        mock.keystroke('down', press)
        mock.keystroke('return', press)
        mock.keystroke('C-z', press)
        mock.keystroke('C-m', press)
        mock.keystroke('down', press)
        mock.keystroke('return', press)
        local n0 = #mock.played_sounds()
        mock.keystroke('C-z', press)
        assert.same(n0, #mock.played_sounds())
        mock.keystroke('C-y', press)
        mock.keystroke('C-y', press)
        --- the second redo has nothing: the tail died
        assert.is_true(#mock.played_sounds() > n0)
      end)
    end)

    it('Ctrl+Z undoes typing word by word', function()
      require("tests.helpers.codesnippets")
      local controller, press = wire(TU.mock_view_cfg())
      local src = 'x = 1'
      local save = TU.get_save_function(src)
      controller:open('undo.lua', src .. '\n', save)
      local inter = controller.input

      mock.keystroke('return', press)
      local base = table.clone(inter:get_text():items())
      for ch in string.gmatch('ab cd', '.') do
        controller:textinput(ch)
      end
      local typed = table.clone(inter:get_text():items())
      assert.same('ab cd' .. base[1], typed[1])

      --- first undo eats the last word (with the space
      --- that started it), not one letter
      mock.keystroke('C-z', press)
      assert.same('ab' .. base[1],
        inter:get_text():items()[1])
      --- and again, back to the baseline
      mock.keystroke('C-z', press)
      assert.same(base, inter:get_text():items())
      --- empty history knocks
      local n0 = #mock.played_sounds()
      mock.keystroke('C-z', press)
      assert.is_true(#mock.played_sounds() > n0)

      --- redo returns everything
      mock.keystroke('C-y', press)
      mock.keystroke('C-y', press)
      assert.same(typed, inter:get_text():items())

      --- still in edit: the keys never left the block
      assert.same('edit', controller:get_mode())
    end)

    it('Delete leaves the clipboard alone, Ctrl+X cuts',
      function()
        require("tests.helpers.codesnippets")
        local controller, press = wire(TU.mock_view_cfg())
        local f1 = mock_func_snippet('one')
        local f2 = mock_func_snippet('two')
        local text = f1 .. '\n\n' .. f2 .. '\n'
        local save = TU.get_save_function(text)
        controller:open('clip.lua', text, save)
        local clip = 'precious'
        love.system = {
          getClipboardText = function() return clip end,
          setClipboardText = function(t) clip = t end,
        }
        local buffer = controller:get_active_buffer()
        local n0 = buffer:get_content_length()

        mock.keystroke('delete', press)
        assert.same(n0 - 1, buffer:get_content_length())
        --- the copied text survived the deletion
        assert.same('precious', clip)

        mock.keystroke('C-x', press)
        assert.same(n0 - 2, buffer:get_content_length())
        assert.is_not.same('precious', clip)
      end)

    it('returning from a require restores the view',
      function()
        require("tests.helpers.codesnippets")
        local controller, press = wire(TU.mock_view_cfg())
        local blocks = {}
        for i = 1, 30 do
          blocks[#blocks + 1] = mock_func_snippet('f' .. i)
        end
        blocks[16] = "local m = require('other')"
        local text = table.concat(blocks, '\n\n')
        local save = TU.get_save_function(text)
        controller.console = {
          edit = function() end,
        }
        controller:open('main.lua', text .. '\n', save)

        --- to the middle of the file, into the require
        mock.keystroke('home', press)
        for _ = 1, 15 do
          mock.keystroke('C-down', press)
        end
        local line0 = controller:get_active_buffer()
          :get_active_line()
        controller:open('other.lua', 'x = 1\n',
          TU.get_save_function('x = 1\n'))

        --- and back: the stored line is visible again
        --- (open() alone parks the view at the end)
        controller:close_buffer()
        assert.same(line0, controller:get_active_buffer()
          :get_active_line())
        local bv = controller.view:get_current_buffer()
        local r = bv.content:get_range()
        local wl = bv.content.wrap_forward[line0]
        assert.is_true(wl[1] >= r.start
          and wl[#wl] <= r.fin)
      end)

    it('dialogs confirm on Enter or Space only', function()
      require("tests.helpers.codesnippets")
      local controller, press = wire(TU.mock_view_cfg())
      local f1 = mock_func_snippet('one')
      local save, savefile =
        TU.get_save_function(f1 .. '\n')
      controller:open('dlg.lua', f1 .. '\n', save)
      local inter = controller.input

      --- a held Shift+Esc: every repeat lands on the
      --- idempotent cancel, nothing is lost
      mock.keystroke('return', press)
      inter:set_text({ 'x = 9' })
      mock.keystroke('S-escape', press)
      assert.is_true(inter:has_error())
      --- repeat cancels; the next press asks again —
      --- held, it oscillates and never discards
      mock.keystroke('S-escape', press)
      assert.is_false(inter:has_error())
      mock.keystroke('S-escape', press)
      assert.is_true(inter:has_error())
      assert.same('edit', controller:get_mode())
      assert.same({ 'x = 9' }, inter:get_text():items())

      --- Space confirms, via textinput as the device
      --- delivers it, and the glyph is swallowed
      controller:textinput(' ')
      controller:keypressed('space')
      assert.same('nav', controller:get_mode())

      --- a printable cancels without typing
      mock.keystroke('return', press)
      inter:set_text({ 'y = 1' })
      mock.keystroke('S-escape', press)
      controller:textinput('q')
      assert.same('edit', controller:get_mode())
      assert.same({ 'y = 1' }, inter:get_text():items())
      mock.keystroke('S-escape', press)
      mock.keystroke('return', press)
      assert.same('nav', controller:get_mode())
    end)

    it('an error message closes on Enter or Esc', function()
      require("tests.helpers.codesnippets")
      local controller, press = wire(TU.mock_view_cfg())
      local f1 = mock_func_snippet('one')
      local save = TU.get_save_function(f1 .. '\n')
      controller:open('err.lua', f1 .. '\n', save)
      local inter = controller.input

      mock.keystroke('return', press)
      inter:set_text({ 'function broken(' })
      mock.keystroke('return', press)
      assert.is_true(inter:has_error())
      --- Enter closes the message without re-submitting
      mock.keystroke('return', press)
      assert.is_false(inter:has_error())
      assert.same('edit', controller:get_mode())

      mock.keystroke('return', press)
      assert.is_true(inter:has_error())
      --- Esc closes it too, staying in the block
      mock.keystroke('escape', press)
      assert.is_false(inter:has_error())
      assert.same('edit', controller:get_mode())
    end)

    it('the console widget keeps plain keys', function()
      --- a console-style input: no editing flag
      local model = UserInputModel(
        TU.mock_view_cfg(), LuaEval(), false, 'console')
      local con = UserInputController(model)
      --- keypressed refreshes the view first; a stub
      --- is enough, the spec is about the keys
      con.view = { refresh = function() end }
      con.update_view = function() end
      local press = function(k) con:keypressed(k) end

      model:add_text('one two')
      mock.keystroke('C-backspace', press)
      --- plain backspace, one character, not a word
      assert.same({ 'one tw' }, model:get_text():items())

      mock.keystroke('C-w', press)
      assert.same({ 'one tw' }, model:get_text():items())

      mock.keystroke('C-y', press)
      --- delete-line is still the console's Ctrl+Y
      assert.same({ '' }, model:get_text():items())
    end)

    it('Ctrl+W and Ctrl+Backspace eat a word', function()
      require("tests.helpers.codesnippets")
      local controller, press = wire(TU.mock_view_cfg())
      local src = 'x = 1'
      local save = TU.get_save_function(src)
      controller:open('w.lua', src .. '\n', save)
      local inter = controller.input

      mock.keystroke('return', press)
      inter:set_text({ 'local one two three' })
      inter.model:move_cursor(1, 20)

      mock.keystroke('C-w', press)
      assert.same({ 'local one two ' }, inter:get_text())
      --- still editing: the key must not leave the block
      assert.same('edit', controller:get_mode())

      mock.keystroke('C-backspace', press)
      assert.same({ 'local one ' }, inter:get_text())

      --- trailing spaces go with the word
      mock.keystroke('C-w', press)
      assert.same({ 'local ' }, inter:get_text())
    end)

    it('Ctrl+Delete drops a block only in nav', function()
      require("tests.helpers.codesnippets")
      local controller, press = wire(TU.mock_view_cfg())
      local f1 = mock_func_snippet('one')
      local f2 = mock_func_snippet('two')
      local save = TU.get_save_function(
        f1 .. '\n\n' .. f2 .. '\n')
      controller:open('del.lua',
        f1 .. '\n\n' .. f2 .. '\n', save)
      --- dropping a block copies it to the clipboard
      love.system = {
        getClipboardText = function() return '' end,
        setClipboardText = function() end,
      }
      local buffer = controller:get_active_buffer()
      local n0 = buffer:get_content_length()

      --- editing: the block survives, the key is the
      --- widget's delete-next-word
      mock.keystroke('return', press)
      mock.keystroke('C-delete', press)
      assert.same(n0, buffer:get_content_length())
      --- the word deletion made the draft dirty
      mock.keystroke('S-escape', press)
      --- Enter confirms (repeat-proof dialogs)
      mock.keystroke('return', press)

      --- navigation: it drops the block
      mock.keystroke('C-delete', press)
      assert.same(n0 - 1, buffer:get_content_length())
    end)

    it('knocks on every refused action', function()
      require("tests.helpers.codesnippets")
      local controller, press = wire(TU.mock_view_cfg())
      local f1 = mock_func_snippet('one')
      local f2 = mock_func_snippet('two')
      local text = f1 .. '\n\n' .. f2 .. '\n'
      local save = TU.get_save_function(text)
      controller.console = { edit = function() end }
      controller:open('knock.lua', text, save)
      local buffer = controller:get_active_buffer()

      local function knocked(fn)
        local before = #mock.played_sounds()
        fn()
        local played = mock.played_sounds()
        if #played == before then return false end
        return played[#played] == 'assets/sounds/knock.ogg'
      end

      --- walk down until the file ends: the last real
      --- block, then the phantom line past it, both
      --- legitimate moves
      mock.keystroke('end', press)
      assert.is_false(knocked(function()
        mock.keystroke('down', press)
      end), 'stepping onto the phantom line is a move')

      --- now there is nowhere further
      assert.is_true(knocked(function()
        mock.keystroke('down', press)
      end), 'bare arrow at the end')

      --- Ctrl+arrow past the end
      assert.is_true(knocked(function()
        mock.keystroke('C-down', press)
      end), 'block jump at the end')

      --- PageDown at the end
      assert.is_true(knocked(function()
        mock.keystroke('pagedown', press)
      end), 'page move at the end')

      --- reorder move past the edge
      mock.keystroke('home', press)
      mock.keystroke('C-m', press)
      assert.is_true(knocked(function()
        mock.keystroke('up', press)
      end), 'block move at the edge')
      mock.keystroke('escape', press)

      --- Ctrl+J with no require in the block
      assert.is_true(knocked(function()
        mock.keystroke('C-j', press)
      end), 'nothing to follow')

      --- and it stays quiet when the move works
      assert.is_false(knocked(function()
        mock.keystroke('down', press)
      end), 'a working move is silent')
      assert.same(2, buffer:get_active_line())
    end)

    it('knocks when the search finds nothing', function()
      local controller, press = wire(TU.mock_view_cfg())
      local src = "local function findme() end"
      local save = TU.get_save_function(src)
      controller:open('search.lua', src .. '\n', save)
      --- entering search saves the clipboard state
      love.system = {
        getClipboardText = function() return '' end,
        setClipboardText = function() end,
      }

      mock.keystroke('C-f', press)
      assert.same('search', controller:get_mode())
      local before = #mock.played_sounds()
      --- a match: quiet
      controller:textinput('f')
      assert.same(before, #mock.played_sounds())
      --- no match: knock
      controller:textinput('zzz')
      local played = mock.played_sounds()
      assert.is_true(#played > before)
      assert.same('assets/sounds/knock.ogg', played[#played])
    end)

    it('follows the require on Ctrl+J', function()
      require("tests.helpers.codesnippets")
      local controller, press = wire(TU.mock_view_cfg())
      local src = "local m = require('other')"
      local save = TU.get_save_function(src)
      local edited = {}
      controller.console = {
        edit = function(_, name)
          table.insert(edited, name)
        end,
      }
      controller:open('main.lua', src, save)

      --- Ctrl+O is free now, it must do nothing
      mock.keystroke('C-o', press)
      assert.same({}, edited)

      mock.keystroke('C-j', press)
      assert.same({ 'other.lua' }, edited)
    end)

    describe('mouse (2.9)', function()
      require("tests.helpers.codesnippets")
      local controller, press, buffer, inter
      local f1, f2

      before_each(function()
        f1 = mock_func_snippet('one')
        f2 = mock_func_snippet('two')
        local text = f1 .. '\n\n' .. f2 .. '\n'
        controller, press = wire(TU.mock_view_cfg())
        local save = TU.get_save_function(text)
        controller:open('mouse.lua', text, save)
        buffer = controller:get_active_buffer()
        inter = controller.input
      end)

      it('maps lines to their blocks', function()
        assert.same(1, buffer:block_at_line(2))
        assert.same(2, buffer:block_at_line(4))
        assert.same(3, buffer:block_at_line(6))
        assert.is_nil(buffer:block_at_line(99))
      end)

      it('a double click opens the block', function()
        controller:mousepressed(0, 0, 1, false, 2)
        assert.same('edit', controller:get_mode())
        assert.same(1, buffer:get_selection())
        assert.same(buffer:get_selected_text(),
          inter:get_text():items())
      end)

      it('a single click does not open', function()
        controller:mousepressed(0, 0, 1, false, 1)
        assert.same('nav', controller:get_mode())
      end)

      it('a click in nav selects block and line', function()
        controller:mouse_select(6)
        assert.same('nav', controller:get_mode())
        assert.same(3, buffer:get_selection())
        assert.same(6, buffer:get_active_line())
      end)

      it('a click inside the open block sets the cursor',
        function()
          mock.keystroke('return', press)
          controller:mouse_select(2)
          assert.same('edit', controller:get_mode())
          assert.same(1, buffer:get_selection())
          assert.same(2,
            inter.model:get_cursor_info().cursor.l)
        end)

      it('a clean click outside flows out', function()
        mock.keystroke('return', press)
        controller:mouse_select(6)
        assert.same('nav', controller:get_mode())
        assert.same(3, buffer:get_selection())
        assert.same(6, buffer:get_active_line())
        assert.same({ '' }, inter:get_text())
      end)

      it('a changed click outside is accepted', function()
        mock.keystroke('return', press)
        inter:set_text({ 'function renamed()', 'end' })
        controller:mouse_select(6)
        --- 2.4.2 via 2.9: written through, then the
        --- clicked block takes the selection
        assert.same('nav', controller:get_mode())
        assert.same(3, buffer:get_selection())
        assert.same(6, buffer:get_active_line())
        assert.truthy(string.find(
          string.unlines(buffer:get_text_content()),
          'renamed', 1, true))
      end)

      it('an invalid click outside refuses', function()
        mock.keystroke('return', press)
        inter:set_text({ 'function broken(' })
        controller:mouse_select(6)
        --- 2.4.3: the block keeps the editor
        assert.same('edit', controller:get_mode())
        assert.same(1, buffer:get_selection())
        assert.is_true(inter:has_error())
      end)
    end)

    describe('leave gate (2.4)', function()
      require("tests.helpers.codesnippets")
      local controller, press, buffer, inter, savefile
      local f1, f2, text

      before_each(function()
        f1 = mock_func_snippet('one')
        f2 = mock_func_snippet('two')
        text = f1 .. '\n\n' .. f2 .. '\n'
        local save
        controller, press = wire(TU.mock_view_cfg())
        save, savefile = TU.get_save_function(text)
        controller:open('gate.lua', text, save)
        buffer = controller:get_active_buffer()
        inter = controller.input
      end)

      it('untouched block flows out freely', function()
        mock.keystroke('return', press)
        local span = buffer:get_selection_lines()
        for _ = 1, span:len() do
          mock.keystroke('down', press)
        end
        --- crossed the edge: neighbor open, no write
        assert.same(2, buffer:get_selection())
        assert.same('edit', controller:get_mode())
        local saved = savefile()
        assert.same(text, saved)
        --- and upward lands on the previous last line
        mock.keystroke('up', press)
        assert.same(1, buffer:get_selection())
        local sp = buffer:get_selection_lines()
        assert.same(sp.fin, buffer:get_active_line())
      end)

      it('acceptance in place stays on the block', function()
        mock.keystroke('return', press)
        local changed = mock_func_snippet('changed')
        inter:set_text(string.lines(changed))
        mock.keystroke('return', press)
        --- 2.4.4: in place, so the block keeps the
        --- selection and the editor returns to nav
        assert.same('nav', controller:get_mode())
        assert.same(1, buffer:get_selection())
        assert.truthy(
          string.find(savefile(), 'changed', 1, true))
      end)

      it('changed block is accepted on the way out', function()
        mock.keystroke('return', press)
        local changed = mock_func_snippet('changed')
        inter:set_text(string.lines(changed))
        mock.keystroke('C-down', press)
        --- written through, editing flows on
        assert.same('edit', controller:get_mode())
        --- NB savefile() reads destructively
        local saved = savefile()
        assert.truthy(
          string.find(saved, 'changed', 1, true))
        assert.is_nil(
          string.find(saved, 'one', 1, true))
      end)

      it('invalid block refuses to leave', function()
        mock.keystroke('return', press)
        inter:set_text({
          'function broken()', '  x = = 2', 'end'
        })
        mock.keystroke('C-down', press)
        assert.same('edit', controller:get_mode())
        assert.same(1, buffer:get_selection())
        assert.is_true(inter:has_error())
        --- and the cursor sits on the error's line
        assert.same(2,
          inter.model:get_cursor_info().cursor.l)
        --- Shift+Esc still gets out, writing nothing:
        --- one press closes the message, the next asks,
        --- Enter confirms
        mock.keystroke('S-escape', press)
        assert.is_false(inter:has_error())
        mock.keystroke('S-escape', press)
        mock.keystroke('return', press)
        assert.same('nav', controller:get_mode())
        assert.same(text, savefile())
      end)
    end)

    it('changing single line', function()
      local controller, press = wire(TU.mock_view_cfg())
      local save, savefile = TU.get_save_function(sierpinski)

      controller:open('sierpinski.lua', sierpinski, save)

      local input = controller.input
      local buffer = controller:get_active_buffer()
      local cont = buffer:get_content()


      assert.same('lua', buffer.content_type)
      assert.same('block', cont:type())
      assert.same(4, buffer:get_content_length())
      local modified = table.clone(sierpinski)
      local new_print = 'print(sierpinski(3))'
      mock.keystroke('C-down', press)
      mock.keystroke('C-down', press)
      assert.same(3, buffer:get_selection())
      assert.same({ print_result }, buffer:get_selected_text())
      mock.keystroke('return', press)
      input:clear()
      input:add_text(new_print)
      mock.keystroke('return', press)
      --- acceptance in place stays on the block (2.4.4)
      assert.same(3, buffer:get_selection())
      local after = savefile()
      modified[#modified] = new_print
      modified[#modified + 1] = ''
      assert.same(string.unlines(modified), after)
    end)

    describe('with blocks:', function()
      require("tests.helpers.codesnippets")
      require("tests.helpers.editor_session")
      local src = snippets_to_code
      local fmt = string.format

      local controller, press, save, savefile, session

      before_each(function()
        controller, press = wire(TU.mock_view_cfg())
        save, savefile = TU.get_save_function({})
        session = EditorSession(controller, press, save, mock)
      end)

      describe("replacement with", function()
        it('single normal block', function()
          local f_orig = mock_func_snippet("orig")
          local f_modified = mock_func_snippet("modified")
          local f_untouched = mock_func_snippet("untouched")

          local src_orig = src(f_orig, '', f_untouched)
          local src_exp = src(f_modified, '', f_untouched, '')

          local input, buffer = session:open(src_orig, 3)
          session:select_and_open_block(1, f_orig)
          session:submit(f_modified)

          assert.is_true(input:is_empty(), "input cleared")
          --- acceptance in place stays (2.4.4)
          assert.same(1, buffer.selection, "selection stays")

          assert.same(string.lines(f_modified),
                      buffer:get_selected_text(),
                      "selection replaced with modified block")
          assert.same(string.lines(src_exp),
                      buffer:get_text_content(),
                      "buffer contains expected altered content")
          assert.same(src_exp, savefile(),
                      "saved content has altered block")
        end)

        it('multiple normal blocks', function()
          local f_orig = mock_func_snippet("orig")
          local f1 = mock_func_snippet("f1")
          local f2 = mock_func_snippet("f2")
          local new_code = src(f1, f2)

          local input, buffer = session:open(f_orig, 1)
          session:select_and_open_block(1, f_orig)
          session:submit(new_code)

          assert.is_true(input:is_empty(), "input cleared")
          --- acceptance in place stays (2.4.4)
          assert.same(1, buffer.selection, "selection stays")

          session:select_block(1)
          assert.same( string.lines(f1),
                       buffer:get_selected_text(),
                       "first block injected first")
          session:select_block(2)
          assert.same({}, buffer:get_selected_text(),
                      "empty line injected after first")
          session:select_block(3)
          assert.same( string.lines(f2),
                       buffer:get_selected_text(),
                       "second block injected second")
          assert.same(src(f1,'',f2,''), savefile(),
                      "old block replaced in saved content")

        end)

        it('oversized block is rejected', function()
          local f_simple = mock_func_snippet("simple")
          local f_oversized = mock_func_snippet("oversized",17)
          local input, buffer = session:open(f_simple, 1)
          session:select_and_open_block(1, f_simple)
          session:submit(f_oversized)

          assert.same(1, buffer.selection, "selection not moved")
          assert.same(string.lines(f_simple),
                      buffer:get_selected_text(),
                      "selection content not changed")
          assert.same(string.lines(f_oversized),
                      input:get_text(),
                      "input content stays altered")
          assert.same(f_simple,
                      savefile(),
                      "saved content not changed")
          session:assert_cursor_at(session:input_line_of(f_oversized))
        end)

        it("normal block rewrites oversized", function()
          local f_simple = mock_func_snippet("simple")
          local f_oversized = mock_func_snippet("oversized",17)

          local input, buffer = session:open(f_oversized, 1)
          session:select_and_open_block(1, f_oversized)
          session:submit(f_simple)

          --- acceptance in place stays (2.4.4)
          assert.same(1, buffer.selection, "selection stays")
          assert.is_true(input:is_empty(), "input cleared")
          assert.same(string.lines(f_simple),
                      buffer:get_selected_text(),
                      "previous block content replaced")
          assert.same(f_simple..'\n', savefile(),
                      "updated content is saved")
        end)

        it("refactored blocks with oversized tail rejected", function()
          local f_simple = mock_func_snippet("simple")
          local f_over_orig = mock_func_snippet("oversized",20)
          local f_over_new = mock_func_snippet("oversized2",17)
          local code_refactored = src(f_simple, f_over_new)

          local input, buffer = session:open(f_over_orig, 1)
          session:select_and_open_block(1, f_over_orig)
          session:submit(code_refactored)

          assert.same(1, buffer.selection,
                       "selection not moved")
          assert.same( string.lines(f_over_orig),
                       buffer:get_selected_text(),
                       "selection text stays untouched" )
          assert.same( string.lines(code_refactored),
                       input:get_text(),
                       "input keeps full submission")
          assert.same(f_over_orig,
                      savefile(),
                      "saved content not changed")
          session:assert_cursor_at(session:input_line_of(f_over_new))
        end)

        -- see issue #114
        it ("extra emptyline+comment before single LOC", function()
          local emptyline = ''
          local comment = '-- comment'
          local single_loc = 'print("original line of code")'


          local orig = src(single_loc, emptyline)
          local edited = src(emptyline, comment, single_loc)

          local input, buffer = session:open(orig)
          session:select_and_open_block(1, single_loc)

          session:submit( edited )

          local expected  = src(emptyline,
                                comment,
                                emptyline,
                                single_loc,
                                emptyline)

          assert.same( expected, savefile() )
        end)

        it ("extra emptyline+comment before block", function()
          local emptyline = ''
          local comment = '-- comment'
          local block = mock_func_snippet("orig_block")


          local orig = src(block, emptyline)
          local edited = src(emptyline, comment, block)

          local input, buffer = session:open(orig)
          session:select_and_open_block(1, single_loc)

          session:submit( edited )

          local expected  = src(emptyline,
                                comment,
                                emptyline,
                                block,
                                emptyline)

          assert.same( expected, savefile() )
        end)

        it ("extra emptyline before comment", function()
          local emptyline = ''
          local comment = '-- comment'

          local orig = src(comment)
          local edited = src(emptyline, comment)

          local input, buffer = session:open(orig)
          session:select_and_open_block(1, comment)

          session:submit( edited )
          assert.same( edited.."\n", savefile() )
        end)

      end)

      describe("insertion of", function()
        setup(function()
          some_func = mock_func_snippet('some')
          other_func = mock_func_snippet('other')
          base_blocks = {
            some_func,
            '',
            '--some comment',
            '',
            other_func,
            ''
          }
          existing_src = src(unpack(base_blocks))
          n_blocks = #base_blocks
          input = nil
          buffer = nil
        end)

        before_each(function()
          input, buffer = session:open(existing_src, n_blocks)
          --- files open at the top; these insert at the end
          session:select_block(n_blocks)
        end)

        it("single normal block", function()
          local new_func = mock_func_snippet("new_func")
          session:submit(new_func, true)

          assert.is_true(input:is_empty(), "input cleared")
          assert.same(n_blocks+1, buffer:get_content_length(),
                      "buffer size increased by 1 block")
          assert.same(n_blocks+1, buffer.selection,
                      "selection moved down by 1")

          session:select_block(n_blocks)
          assert.same( string.lines(new_func),
                       buffer:get_selected_text(),
                       "content added as new block")
          assert.same( existing_src..new_func..'\n',
                       savefile(),
                       "saved file contains updates")
        end)

        it("multiple normal blocks", function()
          local f1 = mock_func_snippet("f1")
          local f2 = mock_func_snippet("f2")
          local new_code = src(f1, f2)
          session:submit(new_code, true)

          assert.is_true(input:is_empty(), "input cleared")
          assert.same(n_blocks+3, buffer:get_content_length(),
                      "buffer size increased by 3 blocks")
          assert.same(n_blocks+3, buffer.selection,
                      "selection moved down by 3")
          assert.same( {},
                       buffer:get_selected_text(),
                       "trailing empty line is selected")

          session:select_block(n_blocks)
          assert.same( string.lines(f1),
                       buffer:get_selected_text(),
                       "first block injected first")
          session:select_block(n_blocks+1)
          assert.same({}, buffer:get_selected_text(),
                      "empty line injected after first")
          session:select_block(n_blocks+2)
          assert.same( string.lines(f2),
                       buffer:get_selected_text(),
                       "second block injected second")
          assert.same( src(existing_src..f1,'',f2,''),
                       savefile(),
                       "saved file contains updates")
        end)

        it('fourteen lines pass, fifteen are refused', function()
          local ok14 = mock_func_snippet('ok14', 14)
          session:submit(ok14, true)
          assert.is_true(input:is_empty(), '14 lines accepted')
          assert.same(n_blocks + 1, buffer:get_content_length())

          local over15 = mock_func_snippet('over15', 15)
          session:submit(over15, true)
          assert.is_false(input:is_empty(), '15 lines refused')
          --- with a visible message naming the excess (9.6)
          assert.is_true(controller.input:has_error())
          local err = controller.input.model.error
          assert.truthy(
            string.find(err[1], 'Remove 1', 1, true))
          mock.keystroke('S-escape', press)
        end)

        it('opening auto-formats a sloppy block', function()
          local sloppy = 'function fmt()   print( "x" )    end'
          local _, b2 = session:open(sloppy, 1)
          mock.keystroke('return', press)
          --- the formatter reshaped the input on open (9.4)
          local t = controller.input:get_text()
          assert.is_true(#t > 1)
          assert.same('function fmt()', t[1])
          --- the file is untouched until acceptance
          assert.same(sloppy, table.concat(
            b2:get_text_content(), '\n'):gsub('\n+$', ''))
          mock.keystroke('S-escape', press)
        end)

        it('single oversized block is rejected', function()
          local f_oversized = mock_func_snippet("oversized",20)
          session:submit(f_oversized, true)

          assert.is_false(input:is_empty(), "input not cleared")
          assert.same( string.lines(f_oversized),
                       input:get_text(),
                       "text remains in the input")
          assert.same(n_blocks, buffer.selection,
                       "selection not moved")
          assert.same(n_blocks, buffer:get_content_length(),
                       "buffer length not changed")
          assert.same( existing_src,
                       savefile(),
                       "saved file unchanged")
          session:assert_cursor_at(session:input_line_of(f_oversized))
        end)

        it("normal+oversized mix rejected", function()
          local f_normal = mock_func_snippet("normal")
          local f1 = mock_func_snippet("f1")
          local f2 = mock_func_snippet("f2")
          local f_oversized = mock_func_snippet("oversized",20)

          local good = { f_normal, f1, f2 }
          local bad =  { f_oversized }
          local mix = table.flatten({good, bad})
          local mixed_content = src(unpack(mix))

          local old_sel = buffer.selection
          local old_len = buffer:get_content_length()
          local old_selected_block = buffer:get_selected_text()

          session:submit(mixed_content, true)

          assert.same(old_len, buffer:get_content_length(),
                      "buffer length unchanged")
          assert.same(old_sel, buffer.selection,
                      "selection not moved")
          assert.same(old_selected_block,
                      buffer:get_selected_text(),
                      "original block unchanged")
          assert.same(string.lines(mixed_content),
                      input:get_text(),
                      "input keeps full submission")
          assert.same(existing_src,
                      savefile(),
                      "saved file unchanged")
          session:assert_cursor_at(session:input_line_of(f_oversized))
        end)
      end)

    end)

  end)
end)
