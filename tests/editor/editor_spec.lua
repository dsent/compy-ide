--- @diagnostic disable: invisible
require("model.editor.editorModel")
require("controller.editorController")
require("view.editor.editorView")
require("view.editor.visibleContent")

local FS = require("util.filesystem")
local textfile = require("util.textfile")

local mock, TU

describe('Editor #editor', function()
  --- these tests start at the first block (pre-IS1.1)
  local open_as_before
  teardown(function() open_as_before() end)
  setup(function()
    open_as_before =
        require('tests.helpers.open_at_first').install()
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

      assert.same(turtle_doc, buffer:get_text_content():items())
      assert.same(#turtle_doc, buffer:get_content_length())

      local sel = buffer:get_selection()
      local sel_t = buffer:get_selected_text()
      --- files open at the first line
      assert.same(1, sel)
      --- the first line is empty: no text to select
        assert.same({}, sel_t)
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
        assert.same(turtle_doc, buffer:get_text_content():items())
        assert.same(#turtle_doc, buffer:get_content_length())

        local sel = buffer:get_selection()
        local sel_t = buffer:get_selected_text()
        --- files open at the first line
        assert.same(1, sel)
        --- the first line is empty: no text to select
        assert.same({}, sel_t)
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
            mock.keystroke('M-pageup', press)
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
            mock.keystroke('M-pagedown', press)
            mock.keystroke('M-pagedown', press)
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

    end)
  end)
  --- end plaintext

  describe('structured (lua) works', function()
    it('the console widget has the field\'s keys', function()
      --- a console-style input: no editing flag
      local model = UserInputModel(
        TU.mock_view_cfg(), LuaEval(), 'console')
      --- MERGE MECHANICS, not this spec's subject: since
      --- this branch, a widget only takes keys while it is
      --- shown, and the console's is a permanent surface.
      --- Without this the presses below no-op silently.
      local con = UserInputController(model):always_shown()
      --- keypressed refreshes the view first; a stub
      --- is enough, the spec is about the keys
      con.view = { refresh = function() end }
      con.update_view = function() end
      local press = function(k) con:keypressed(k) end

      model:add_text('one two')
      --- the word deletions are every field's (the ruling of
      --- November 14, 2026: one text field everywhere)
      mock.keystroke('C-backspace', press)
      assert.same({ 'one ' }, model:get_text():items())

      --- Ctrl+Z undoes and Ctrl+Y redoes, and no longer
      --- deletes the line (D-UNDO-KEYS)
      mock.keystroke('C-z', press)
      assert.same({ 'one two' }, model:get_text():items())
      mock.keystroke('C-y', press)
      assert.same({ 'one ' }, model:get_text():items())
      mock.keystroke('C-z', press)
      mock.keystroke('C-z', press)
      assert.same({ '' }, model:get_text():items())
      mock.keystroke('C-y', press)
      assert.same({ 'one two' }, model:get_text():items())
    end)

    it('Ctrl+W and Ctrl+Backspace eat a word', function()
      require("tests.helpers.codesnippets")
      local controller, press = wire(TU.mock_view_cfg())
      local src = 'x = 1'
      local save = TU.get_save_function(src)
      controller:open('w.lua', src .. '\n', save)
      local inter = controller.input

      controller:get_active_buffer():set_selection(1)
      mock.keystroke('f2', press)
      inter:set_text({ 'local one two three' })
      inter.model:move_cursor(1, 20)

      mock.keystroke('C-w', press)
      assert.same({ 'local one two ' }, inter:get_text())
      --- still replacing: the key must not end the edit
      assert.same('replacing', controller:state_name())

      mock.keystroke('C-backspace', press)
      assert.same({ 'local one ' }, inter:get_text())

      --- trailing spaces go with the word
      mock.keystroke('C-w', press)
      assert.same({ 'local ' }, inter:get_text())
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

    --- the REPL's tidy(name): the editor's formatting, at a
    --- Compy's width, on a project file
    describe('blocks by line', function()
      require("tests.helpers.codesnippets")
      local controller, buffer
      local f1, f2

      before_each(function()
        f1 = mock_func_snippet('one')
        f2 = mock_func_snippet('two')
        local text = f1 .. '\n\n' .. f2 .. '\n'
        controller = wire(TU.mock_view_cfg())
        local save = TU.get_save_function(text)
        controller:open('mouse.lua', text, save)
        buffer = controller:get_active_buffer()
      end)

      it('maps lines to their blocks', function()
        assert.same(1, buffer:block_at_line(2))
        assert.same(2, buffer:block_at_line(4))
        assert.same(3, buffer:block_at_line(6))
        assert.is_nil(buffer:block_at_line(99))
      end)

    end)

    describe('tidy() in the REPL', function()
      require("controller.consoleController")
      local path, console, printed

      before_each(function()
        path = os.tmpname()
        local project = {
          get_path = function() return path end,
          readfile = function() return FS.read(path) end,
          writefile = function(_, _, text)
            return FS.write(path, text)
          end,
        }
        console = setmetatable({
          model = { projects = { current = project } },
        }, ConsoleController)
        printed = {}
        stub(_G, 'print', function(s) table.insert(printed, s) end)
      end)

      after_each(function()
        _G.print:revert()
        os.remove(path)
      end)

      it('formats the file, blank runs and all', function()
        assert.is_true(FS.write(path,
          'a  =  1\n\n\n\nfunction f()   return 1 end\n'))
        assert.is_true(console:tidy('main.lua'))
        local _, text = FS.read(path)
        assert.same('a = 1\n\nfunction f()\n  return 1\nend\n', text)
      end)

      it('leaves a file with an error, saying on which line',
        function()
          local broken = 'a = 1\nfunction f(\n'
          assert.is_true(FS.write(path, broken))
          assert.is_false(console:tidy('main.lua'))
          local _, text = FS.read(path)
          assert.same(broken, text)
          assert.truthy(string.find(printed[1], 'line', 1, true))
        end)

      --- its syntax formats it, by the file's name: a Markdown
      --- file has nothing to format
      it('leaves a Markdown file, saying it has nothing to format',
        function()
          local text = '#  a  title\n'
          assert.is_true(FS.write(path, text))
          assert.is_false(console:tidy('notes.md'))
          local _, after = FS.read(path)
          assert.same(text, after)
          assert.same('notes.md has nothing to format', printed[1])
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
      assert.same(3, buffer:get_content_length())
      local modified = table.clone(sierpinski)
      local new_print = 'print(sierpinski(3))'
      mock.keystroke('C-down', press)
      mock.keystroke('C-down', press)
      assert.same(3, buffer:get_selection())
      assert.same({ print_result }, buffer:get_selected_text())
      mock.keystroke('f2', press)
      input:clear()
      input:add_text(new_print)
      mock.keystroke('return', press)
      --- the position moves past the replacement, here to
      --- the end position (IS5.4)
      assert.same(4, buffer:get_selection())
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
          --- the position moves past the replacement (IS5.4)
          assert.same(2, buffer.selection, "selection moves on")
          session:select_block(1)

          assert.same(string.lines(f_modified),
                      buffer:get_selected_text(),
                      "selection replaced with modified block")
          assert.same(textfile.lines(src_exp),
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
          --- the position moves past the replacement, here
          --- to the end position (IS5.4)
          assert.same(3, buffer.selection, "selection moves on")

          session:select_block(1)
          assert.same( string.lines(f1),
                       buffer:get_selected_text(),
                       "first block injected first")
          session:select_block(2)
          assert.same( string.lines(f2),
                       buffer:get_selected_text(),
                       "second block follows, no empty line added")
          assert.same(src(f1, f2, ''), savefile(),
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
          session:assert_cursor_kept()
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

      describe("a comment trailing code", function()
        local first = 'robot_move(40, 40, 1)'
        local code = 'robot_move(40, -40, 1)'
        local comment = '-- and back again'
        local commented = code .. '  ' .. comment

        --- formatting gives the comment a line of its own below
        --- the code; accepting writes it back as two blocks, no
        --- blank line between them
        local opened = src(code, comment)
        local accepted = src(first, code, comment, '')

        it("is shown on its own line and accepted so",
          function()
            local input = session:open(src(first, commented), 2)

            session:select_block(2, commented)
            session:select_and_open_block(2)
            --- Edit loads the block formatted as a submission
            --- formats it (ruling: F2 opens a block that
            --- breaks a limit)
            assert.same(string.lines(opened), input:get_text(),
                        "the block loads formatted")

            session:submit(opened)
            assert.same(accepted, savefile(), "one copy of the comment")
          end)

        it("stays put when the block is accepted again", function()
          session:open(src(first, commented), 2)
          session:select_and_open_block(2)
          session:submit(opened)
          assert.same(accepted, savefile())

          --- reopen the file and accept the same code again
          session:open(accepted)
          session:select_and_open_block(2, code)
          session:submit(code)

          assert.same(accepted, savefile(),
                      "second accept leaves the file alone")
        end)
      end)

      --- The editor adds no blank line; blank lines typed
      --- between statements stay, each of them (IS3.7); a run
      --- inside a block becomes one; blank lines outside the
      --- draft are never changed
      describe("blank lines on acceptance", function()
        --- open the block, accept it as the input shows it
        local function accept_as_is(n)
          session:select_and_open_block(n)
          mock.keystroke('return', press)
        end

        it("are not added between typed statements", function()
          session:open('a = 1\n', 1)
          session:select_and_open_block(1, 'a = 1')
          session:submit('a = 1\nb = 2')
          assert.same('a = 1\nb = 2\n', savefile())
        end)

        --- the formatter leaves one empty line of a run (the
        --- ruling "The formatter decides a draft's empty lines",
        --- over IS3.7)
        it("typed at top level stay, one of a run",
          function()
            session:open('x = 0\ny = 0\n', 2)
            session:select_and_open_block(1, 'x = 0')
            session:submit('\n\n\nx = 1\n\n\n\na = 1\nb = 1\n\n')
            assert.same(
              '\nx = 1\n\na = 1\nb = 1\n\ny = 0\n',
              savefile())
          end)

        it("typed inside a function body stay, one per run",
          function()
            session:open('a = 1\n', 1)
            session:select_and_open_block(1, 'a = 1')
            session:submit(string.unlines({
              'function f()',
              '  local x = 1',
              '',
              '',
              '  -- note',
              '',
              '  return x',
              'end',
            }))
            assert.same(string.unlines({
              'function f()',
              '  local x = 1',
              '',
              '  -- note',
              '',
              '  return x',
              'end',
              '',
            }), savefile())
          end)

        it("outside the block are left alone", function()
          local file = 'a = 1\n\n\n\nb = 2\n\nc = 3\n'
          session:open(file, 7)
          session:select_and_open_block(7, 'c = 3')
          session:submit('c = 4')
          assert.same('a = 1\n\n\n\nb = 2\n\nc = 4\n', savefile(),
                      "the run of three is still three")
        end)

        it("before a comment leave the blocks after it in place",
          function()
            local file = 'a = 1\n\n\n\n-- note\nb = 2\n'
            session:open(file, 6)
            session:select_block(5, '-- note')
            session:select_and_open_block(6, 'b = 2')
            session:submit('b = 3')
            assert.same('a = 1\n\n\n\n-- note\nb = 3\n',
                        savefile())
          end)

        it("of a file holding nothing else stay when code is added",
          function()
            session:open('\n\n\n', 3)
            session:select_block(1)
            for ch in ('a = 1'):gmatch('.') do
              controller:textinput(ch)
            end
            mock.keystroke('return', press)
            --- the draft goes before the browsed line (IS4.1)
            assert.same('a = 1\n\n\n\n', savefile(),
                        "the empty lines are all still there")
          end)

        it("do not grow an empty function body", function()
          local placeholder = 'function g()\n  \nend\n'
          session:open('function g() end\n', 1)
          session:select_and_open_block(1)
          session:submit('function g() end')
          assert.same(placeholder, savefile(), "indented slot")

          accept_as_is(1)
          assert.same(placeholder, savefile(), "accepted again")

          session:select_and_open_block(1)
          session:submit('function g()\n\n\nend')
          assert.same(placeholder, savefile(), "emptied slot")

          --- code typed below the slot leaves the slot behind;
          --- it is no blank line of the user's
          session:select_and_open_block(1)
          session:submit('function g()\n  \n  x()\nend')
          assert.same('function g()\n  x()\nend\n', savefile(),
                      "slot left behind")
        end)

        it("leave the file byte-identical on a second accept",
          function()
            session:open('local a = 1\n', 1)
            session:select_and_open_block(1)
            session:submit(string.unlines({
              'local a = 1',
              '',
              '',
              '-- note',
              '',
              'function f()',
              '  local x = 1',
              '',
              '',
              '  return x',
              'end',
              'function g() end',
            }))
            local once = savefile()
            --- every run is one empty line, inside the function
            --- and between statements
            assert.same(string.unlines({
              'local a = 1',
              '',
              '-- note',
              '',
              'function f()',
              '  local x = 1',
              '',
              '  return x',
              'end',
              'function g()',
              '  ',
              'end',
              '',
            }), once)

            local buffer = session.buffer
            for n = 1, buffer:get_content_length() do
              if not buffer:get_content()[n]:is_empty() then
                accept_as_is(n)
                assert.same(once, savefile(),
                            fmt("block #%d accepted again", n))
              end
            end
          end)
      end)

      describe("formatting the whole file", function()
        it("collapses every blank run, keeping the statement",
          function()
            local _, buffer = session:open(string.unlines({
              'a = 1', '', '', '',
              'function f()   return 1 end', '', '',
              'b = 2', '',
            }), 8)
            session:select_block(8, 'b = 2')
            mock.keystroke('C-S-f', press)
            assert.same(string.unlines({
              'a = 1', '',
              'function f()', '  return 1', 'end', '',
              'b = 2', '',
            }), savefile())
            assert.same({ 'b = 2' }, buffer:get_selected_text(),
                        "the selection stays on its statement")
          end)

        --- compyfmt formats at a Compy's width, and the test
        --- editor's window is a Compy's
        describe("gives compyfmt's result on", function()
          local compyfmt = require("util.compyfmt")
          local ls = assert(io.popen(
            "find src/examples -name '*.lua' | sort"))
          for path in ls:lines() do
            it(path, function()
              local f = assert(io.open(path))
              local text = f:read('*a')
              f:close()
              session:open(text)
              mock.keystroke('C-S-f', press)
              local lines = textfile.lines(text)
              local want = compyfmt.inspect(lines)
              assert.same(textfile.text(want), savefile())
            end)
          end
          ls:close()
        end)

        it("leaves the screen as the file when the save fails",
          function()
            local disk = 'a  =  1\n'
            local failing = true
            controller:open('test.lua', disk, function(content)
              if failing then return false, 'no space left' end
              disk = string.unlines(content)
              return true
            end)
            local buffer = controller:get_active_buffer()

            mock.keystroke('C-S-f', press)
            assert.same('a  =  1\n', disk)
            assert.same({ 'a  =  1' },
              buffer:get_text_content())
            assert.is_true(controller.input:has_error())

            --- storage back: trying again formats and saves;
            --- the chord's key dismisses the notice and acts
            failing = false
            mock.keystroke('C-S-f', press)
            assert.is_false(controller.input:has_error())
            assert.same('a = 1\n', disk)
          end)

        it("is undone and redone like any write", function()
          local _, buffer = session:open(string.unlines({
            'a  =  1', '', '', '', 'b = 2', 'c = 3', 'd = 4',
            'e = 5', '',
          }), 8)
          session:select_block(5, 'b = 2')
          mock.keystroke('C-S-f', press)
          assert.same({ 'b = 2' }, buffer:get_selected_text())
          mock.keystroke('C-z', press)
          --- the text is back, the position on the first
          --- restored block (IS6.6)
          assert.same('a  =  1', buffer:get_text_content()[1])
          assert.same({ 'a  =  1' }, buffer:get_selected_text())
          mock.keystroke('C-y', press)
          assert.same('a = 1', buffer:get_text_content()[1])
          assert.same({ 'b = 2' }, buffer:get_selected_text(),
                      "redo lands where the format did")
        end)

        it("leaves a file it cannot format safely as it is",
          function()
            local file = string.unlines({
              'local colors = {',
              '  black = 0, -- #000000',
              '  white = 1,',
              '}',
              '',
            })
            session:open(file, 1)
            mock.keystroke('C-S-f', press)
            assert.same(file, savefile())
            assert.is_true(controller.input:has_error())
          end)
      end)

      --- the newline ending a file's last line belongs to that
      --- line: no block stands for it
      describe("a file's final newline", function()
        it("is no block, and a save writes it back", function()
          for _, case in ipairs({
            { 'x = 1\n', 1, 'x = 1\n' },
            { 'x = 1', 1, 'x = 1\n' },
            { 'x = 1\n\n', 2, 'x = 1\n\n' },
          }) do
            local text, blocks = case[1], case[2]
            local saved = case[3]
            local _, buffer = session:open(text, blocks)
            --- past the last block, the append row
            session:select_block(blocks + 1)
            assert.same({}, buffer:get_selected_text())
            assert.is_true(buffer:save())
            assert.same(saved, savefile(), text)
          end
        end)

        it("is written the same by an accept, Ctrl+Shift+F,"
          .. " tidy and compyfmt --fix", function()
          require("controller.consoleController")
          local compyfmt = require("util.compyfmt")
          stub(_G, 'print')
          for _, case in ipairs({
            { 'x  =  1', 'x = 1\n' },
            { 'x  =  1\n', 'x = 1\n' },
            { 'x  =  1\n\n', 'x = 1\n\n' },
          }) do
            local text, want = case[1], case[2]
            session:open(text, #textfile.lines(text))
            session:select_and_open_block(1)
            session:submit('x  =  1')
            assert.same(want, savefile(), 'accept: ' .. text)

            session:open(text)
            mock.keystroke('C-S-f', press)
            assert.same(want, savefile(),
              'Ctrl+Shift+F: ' .. text)

            local path = os.tmpname()
            assert.is_true(FS.write(path, text))
            local console = setmetatable({
              model = { projects = { current = {
                get_path = function() return path end,
                readfile = function() return FS.read(path) end,
                writefile = function(_, _, t)
                  return FS.write(path, t)
                end,
              } } },
            }, ConsoleController)
            assert.is_true(console:tidy('main.lua'))
            assert.same(want, select(2, FS.read(path)),
              'tidy: ' .. text)

            assert.is_true(FS.write(path, text))
            compyfmt.main({ '--fix', path })
            assert.same(want, select(2, FS.read(path)),
              'compyfmt --fix: ' .. text)
            os.remove(path)
          end
          _G.print:revert()
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
          --- the last '' is the file's final newline, no block
          n_blocks = #base_blocks - 1
          input = nil
          buffer = nil
        end)

        before_each(function()
          input, buffer = session:open(existing_src, n_blocks)
          --- files open at the top; these insert at the end,
          --- on the append row past the last block
          session:select_block(n_blocks + 1)
        end)

        it("single normal block", function()
          local new_func = mock_func_snippet("new_func")
          session:submit(new_func, true)

          assert.is_true(input:is_empty(), "input cleared")
          assert.same(n_blocks+1, buffer:get_content_length(),
                      "buffer size increased by 1 block")
          assert.same(n_blocks+2, buffer.selection,
                      "selection moved down by 1")

          session:select_block(n_blocks+1)
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
          assert.same(n_blocks+2, buffer:get_content_length(),
                      "buffer size increased by 2 blocks")
          assert.same(n_blocks+3, buffer.selection,
                      "selection moved down by 2")
          assert.same( {},
                       buffer:get_selected_text(),
                       "the append row is selected")

          session:select_block(n_blocks+1)
          assert.same( string.lines(f1),
                       buffer:get_selected_text(),
                       "first block injected first")
          session:select_block(n_blocks+2)
          assert.same( string.lines(f2),
                       buffer:get_selected_text(),
                       "second block follows, no empty line added")
          assert.same( src(existing_src..f1, f2, ''),
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
          --- with a visible notice naming the limit (IS3.3)
          assert.is_true(controller.input:has_error())
          local err = controller.input.model.error
          assert.truthy(string.find(err[1], '14', 1, true))
          mock.keystroke('S-escape', press)
        end)

        it('single oversized block is rejected', function()
          local f_oversized = mock_func_snippet("oversized",20)
          session:submit(f_oversized, true)

          assert.is_false(input:is_empty(), "input not cleared")
          assert.same( string.lines(f_oversized),
                       input:get_text(),
                       "text remains in the input")
          assert.same(n_blocks+1, buffer.selection,
                       "selection not moved")
          assert.same(n_blocks, buffer:get_content_length(),
                       "buffer length not changed")
          assert.same( existing_src,
                       savefile(),
                       "saved file unchanged")
          session:assert_cursor_kept()
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
          session:assert_cursor_kept()
        end)
      end)

    end)

  end)
end)
