-- IS1 Opening, navigating between, and leaving files
-- (editor principles, ratified). Keys only, through
-- tests/helpers/editor_keys.lua.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it, spec_gap = marks.spec_it, marks.spec_gap

local tall = K.block

describe("IS1 files #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  describe("IS1.1", function()
    before_each(function()
      K.reset({
        ["main.lua"] = "x = 1\ny = 2\n",
        ["empty.lua"] = "",
        ["bad.lua"] = "s = '\255'\n"
      })
    end)

    spec_it(
        "IS1.1 Open a Lua file: edit() in the console opens "
        .. "it to browse, the field empty", function()
      K.open()
      assert.same("editor", K.app_state())
      assert.same("main.lua", K.file_name())
      assert.same("browsing", K.state())
      assert.same("", K.draft())
    end)

    spec_it("IS1.1 Open a Lua file: the browsing position " ..
        "starts at the end", function()
      K.open()
      assert.same("end", K.position())
    end)

    spec_it(
        "IS1.1 Open a Lua file: an empty file opens at its " ..
        "end, with no block", function()
      K.open("empty.lua")
      assert.same(0, K.blocks())
      assert.same("end", K.position())
    end)

    spec_it("IS1.1 Open a Lua file: a refused file leaves the "
        .. "console, its field empty", function()
      K.open("bad.lua")
      assert.same("ready", K.app_state())
      assert.same("", K.console_draft())
    end)
  end)

  describe("IS1.2", function()
    before_each(function()
      K.reset({
        ["main.lua"] = "x = 1",
        ["a.txt"] = "one\n",
        ["b.md"] = "# two\n",
        todo_md = "three = 3\n",
        notes_lua = "four = 4\n",
        ["bad8.lua"] = "s = '\255'\n"
      })
    end)

    spec_it("IS1.2 Admit or refuse a file: .lua, .txt and .md "
        .. "fix the type", function()
      K.open("main.lua")
      assert.same("lua", K.file_type())
      K.restart()
      K.open("a.txt")
      assert.same("plain", K.file_type())
      K.restart()
      K.open("b.md")
      assert.same("markdown", K.file_type())
    end)

    spec_it("IS1.2 Admit or refuse a file: any other name " ..
        "opens as plain text", function()
      K.open("todo_md")
      local first = K.file_type()
      K.restart()
      K.open("notes_lua")
      local second = K.file_type()
      assert.same({
        "plain",
        "plain"
      }, {
        first,
        second
      })
    end)

    spec_it("IS1.2 Admit or refuse a file: invalid UTF-8 is "
        .. "refused with a notice naming the file", function()
      K.open("bad8.lua")
      assert.same("ready", K.app_state())
      -- the notice names the file and the reason
      local notice = K.console_text()
      assert.truthy(notice:find("bad8.lua", 1, true))
      assert.truthy(notice:find("UTF-8", 1, true))
      assert.same("", K.console_draft())
    end)

    spec_it("IS1.2 Admit or refuse a file: a file that cannot "
        .. "be read is refused with a notice, and is not opened "
        .. "empty", function()
      -- the device's read gives no text and no reason
      K.fail_reads()
      K.open("main.lua")
      assert.same("ready", K.app_state())
      assert.same("", K.console_draft())
      local notice = K.console_text()
      assert.truthy(notice:find("main.lua", 1, true))
      assert.truthy(notice:find("could not be read", 1, true))
      assert.same("x = 1", K.file("main.lua"))
    end)

    -- A .lua file whose text does not parse is admitted, so
    -- that it can be repaired. The spec names no blocks for
    -- such text; as in Luditor, its reference implementation,
    -- each line is a block until the file parses again. Edit
    -- opens a line as it opens any block, and cutting a line
    -- loads it too.
    describe("a file that does not parse", function()
      local BROKEN = "x = 1\n?\n\n  function f(\ny = 2\n"

      before_each(function()
        K.reset({ ["broken.lua"] = BROKEN })
        K.open("broken.lua")
      end)

      spec_it("IS1.2 Admit or refuse a file: a Lua file that "
          .. "does not parse opens, every line shown", function()
        assert.same("editor", K.app_state())
        assert.same("broken.lua", K.file_name())
        assert.same("lua", K.file_type())
        assert.same("browsing", K.state())
        assert.same("end", K.position())
        assert.same(5, K.blocks())
        assert.same({
          "x = 1",
          "?",
          "",
          "  function f(",
          "y = 2"
        }, K.view_rows())
      end)

      spec_it("IS1.2 Admit or refuse a file: an insertion " ..
          "elsewhere keeps the lines that do not parse as "
          .. "they are", function()
        K.type("z = 3")
        K.keys("return")
        assert.same(BROKEN .. "z = 3\n", K.file("broken.lua"))
        K.browse_to(1)
        K.type("w = 4")
        K.keys("return")
        assert.same("w = 4\n" .. BROKEN .. "z = 3\n",
          K.file("broken.lua"))
      end)

      -- the maintainer's ruling of November 14, 2026 overrides
      -- IS1.3's refusal of Edit
      spec_it("IS1.2 Admit or refuse a file: Edit opens a line of "
          .. "a file that does not parse, as it stands", function()
        K.browse_to(2)
        K.keys("f2")
        assert.same("replacing", K.state())
        assert.same(2, K.target())
        assert.same("?", K.draft())
        assert.is_nil(K.message())
        assert.same(BROKEN, K.file("broken.lua"))
      end)

      spec_it("IS1.2 Admit or refuse a file: formatting a " ..
          "file that does not parse changes nothing and says "
          .. "why", function()
        K.keys("lalt", "f")
        assert.same(BROKEN, K.file("broken.lua"))
        assert.same({ }, K.writes())
        assert.same(5, K.blocks())
        assert.truthy(
          (K.message() or ""):find("cannot split this file", 1,
            true)
        )
      end)

      spec_it("IS1.2 Admit or refuse a file: moving a line of "
          .. "a file that does not parse keeps every line, and "
          .. "undo puts it back", function()
        K.browse_to(2)
        K.keys("lalt", "down")
        assert.same("x = 1\n\n?\n  function f(\ny = 2\n",
          K.file("broken.lua"))
        K.keys("lctrl", "z")
        assert.same(BROKEN, K.file("broken.lua"))
      end)

      spec_it("IS1.2 Admit or refuse a file: undo and redo " ..
          "cross the repair of a file that did not parse",
          function()
        K.browse_to(2)
        K.keys("lctrl", "delete")
        K.keys("escape")
        K.browse_to(3)
        K.keys("lctrl", "delete")
        K.keys("escape")
        local repaired = "x = 1\n\ny = 2\n"
        assert.same(repaired, K.file("broken.lua"))
        for _ = 1, 4 do
          K.keys("lctrl", "z")
        end
        assert.same(BROKEN, K.file("broken.lua"))
        assert.same(5, K.blocks())
        for _ = 1, 4 do
          K.keys("lctrl", "y")
        end
        assert.same(repaired, K.file("broken.lua"))
        assert.same(3, K.blocks())
      end)

      spec_it("IS1.2 Admit or refuse a file: a failed write " ..
          "in a file that does not parse keeps its lines and "
          .. "the draft", function()
        K.fail_writes("the card is full")
        K.type("z = 3")
        K.keys("return")
        assert.same(BROKEN, K.file("broken.lua"))
        assert.same("z = 3", K.draft())
        assert.same(5, K.blocks())
        assert.truthy(
          (K.message() or ""):find("the card is full", 1, true)
        )
      end)

      spec_it("IS1.2 Admit or refuse a file: cutting the lines "
          .. "that do not parse loads each for repair, and the "
          .. "repaired file has its blocks again", function()
        K.browse_to(2)
        K.keys("lctrl", "delete")
        assert.same("?", K.draft())
        assert.same("x = 1\n\n  function f(\ny = 2\n",
          K.file("broken.lua"))
        K.keys("escape")
        K.browse_to(3)
        K.keys("lctrl", "delete")
        assert.same("  function f(", K.draft())
        assert.same("x = 1\n\ny = 2\n", K.file("broken.lua"))
        K.keys("escape")
        -- the file parses again: Edit opens a block
        K.browse_to(1)
        K.keys("f2")
        assert.same("replacing", K.state())
        assert.same("x = 1", K.draft())
      end)
    end)

    -- A file with CRLF line ends is read as its lines, without
    -- the carriage return, and written with LF (the ruling "A
    -- file is written with LF line ends"), as Luditor does.
    describe("a file with CRLF line ends", function()
      before_each(function()
        K.reset({
          ["crlf.lua"] = "x = 1\r\ny = 2\r\n",
          ["crlf.txt"] = "one\r\ntwo\r\n"
        })
      end)

      spec_it("IS1.2 Admit or refuse a file: a Lua file with "
          .. "CRLF line ends opens, and Edit then Enter is " ..
          "accepted", function()
        K.open("crlf.lua")
        assert.same(2, K.blocks())
        assert.same({ "x = 1", "y = 2" }, K.view_rows())
        K.browse_to(1)
        K.keys("f2")
        assert.same("x = 1", K.draft())
        K.keys("end")
        K.type("0")
        K.keys("return")
        assert.same("browsing", K.state())
        assert.same("x = 10\ny = 2\n", K.file("crlf.lua"))
      end)

      spec_it("IS1.2 Admit or refuse a file: an insertion in "
          .. "a CRLF Lua file writes LF on every line", function()
        K.open("crlf.lua")
        K.browse_to(2)
        K.type("w = 4")
        K.keys("return")
        assert.same("x = 1\nw = 4\ny = 2\n", K.file("crlf.lua"))
      end)

      spec_it("IS1.2 Admit or refuse a file: a text file with "
          .. "CRLF line ends is written with LF, with no " ..
          "carriage return in its text", function()
        K.open("crlf.txt")
        assert.same(2, K.blocks())
        K.browse_to(2)
        K.keys("f2")
        assert.same("two", K.draft())
        K.keys("end")
        K.type("0")
        K.keys("return")
        assert.same("one\ntwo0\n", K.file("crlf.txt"))
        K.browse_to_end()
        K.type("three")
        K.keys("return")
        assert.same("one\ntwo0\nthree\n", K.file("crlf.txt"))
      end)
    end)

    spec_it("IS1.2 Admit or refuse a file: a name with another "
        .. "ending opens as plain text", function()
      K.open("notes.log")
      assert.same("editor", K.app_state())
      assert.same("plain", K.file_type())
    end)

    spec_it("IS1.2 Admit or refuse a file: a refused submission "
        .. "does not create a missing file", function()
      K.open("new.lua")
      K.type("a = = 1")
      K.keys("return")
      assert.is_nil(K.file("new.lua"))
      assert.same("a = = 1", K.draft())
    end)

    spec_it(
        "IS1.2 Admit or refuse a file: a missing file opens "
        .. "empty and its first submission creates it",
        function()
      K.open("new.lua")
      assert.same("browsing", K.state())
      assert.is_nil(K.file("new.lua"))
      K.browse_to_end()
      K.type("a = 1")
      K.keys("return")
      assert.is_not_nil(K.file("new.lua"))
    end)

    spec_it(
        "IS1.2 Admit or refuse a file: a created file holds "
        .. "only what was submitted", function()
      K.open("new.lua")
      K.browse_to_end()
      K.type("a = 1")
      K.keys("return")
      assert.same("a = 1\n", K.file("new.lua"))
    end)

    spec_it("IS1.2 Admit or refuse a file: a missing last line "
        .. "break is added by the first submission", function()
      K.open()
      K.browse_to_end()
      K.type("y = 2")
      K.keys("return")
      assert.same("x = 1\ny = 2\n", K.file())
    end)
  end)

  describe("IS1.3", function()
    before_each(function()
      K.reset({
        ["main.lua"] = tall(16) .. "y = 2\n",
        ["small.lua"] = "x = 1\n"
      })
    end)

    spec_it(
        "IS1.3 Handle size limits: a file with an oversized "
        .. "block is admitted for browsing", function()
      K.open()
      assert.same("editor", K.app_state())
      assert.same(2, K.blocks())
      assert.same("browsing", K.state())
    end)

    -- the maintainer's ruling of November 14, 2026 overrides
    -- IS1.3's refusal of Edit
    spec_it("IS1.3 Handle size limits: Edit opens an oversized "
        .. "block, and Enter refuses it with a notice naming the "
        .. "limit", function()
      K.open()
      K.browse_to(1)
      K.keys("f2")
      assert.same("replacing", K.state())
      assert.same(1, K.target())
      assert.is_nil(K.message())
      K.keys("return")
      assert.same("replacing", K.state())
      assert.truthy((K.message() or ""):find("14", 1, true))
      assert.same(tall(16) .. "y = 2\n", K.file())
    end)

    spec_it("IS1.3 Handle size limits: cutting an oversized "
        .. "block loads it into the field", function()
      K.open()
      K.browse_to(1)
      K.keys("lctrl", "delete")
      assert.same("inserting", K.state())
      assert.same(tall(16):gsub("\n$", ""), K.draft())
    end)

    spec_it(
        "IS1.3 Handle size limits: a submission over a limit "
        .. "is refused", function()
      K.open("small.lua")
      K.browse_to_end()
      local lines = { }
      for l in tall(15):gmatch("[^\n]+") do
        lines[#lines + 1] = l
      end
      K.type_lines(lines)
      K.keys("return")
      assert.same("x = 1\n", K.file("small.lua"))
      assert.are_not.same("", K.draft())
      -- the notice names the limit
      assert.truthy((K.message() or ""):find("14", 1, true))
      assert.same("inserting", K.state())
      assert.same("end", K.position())
    end)

    spec_it("IS1.3 Handle size limits: insertion elsewhere in "
        .. "the file works as usual", function()
      K.open()
      K.browse_to(2)
      K.type("w = 4")
      K.keys("return")
      assert.same(tall(16) .. "w = 4\ny = 2\n", K.file())
      assert.same(3, K.blocks())
    end)
  end)

  describe("IS1.4", function()
    before_each(function()
      K.reset({ ["main.lua"] = "x = 1\ny = 2\nz = 3\n" })
      K.open()
    end)

    spec_it("IS1.4 Resume after running a project: Ctrl+T and "
        .. "back restores the browsing position", function()
      K.browse_to(2)
      K.keys("lctrl", "t")
      K.keys("lctrl", "t")
      assert.same("editor", K.app_state())
      assert.same("main.lua", K.file_name())
      assert.same(2, K.position())
    end)

    spec_it("IS1.4 Resume after running a project: the " ..
        "document view is restored", function()
      local t = { }
      for i = 1, 60 do
        t[i] = "v" .. i .. " = " .. i
      end
      K.reset({ ["main.lua"] = table.concat(t, "\n") .. "\n" })
      K.open()
      local opened = K.view_rows()
      K.browse_to(20)
      local rows = K.view_rows()
      assert.are_not.same(opened, rows)
      K.keys("lctrl", "t")
      K.keys("lctrl", "t")
      assert.same(20, K.position())
      assert.same(rows, K.view_rows())
    end)

    spec_it("IS1.4 Resume after running a project: the end "
        .. "position is restored too", function()
      K.browse_to_end()
      K.keys("lctrl", "t")
      K.keys("lctrl", "t")
      assert.same("end", K.position())
    end)
  end)

  describe("IS1.5", function()
    before_each(function()
      K.reset({
        ["main.lua"] = "local m = require(\"mod\")\n" ..
            "dofile(\"script.lua\")\nx = 1\n",
        ["mod.lua"] = "y = 2\n",
        ["script.lua"] = "z = 3\n",
        ["refs.lua"] = "x = 1\nrequire(\"bad8\")\n",
        ["bad8.lua"] = "s = '\255'\n"
      })
    end)

    spec_it("IS1.5 Follow a file reference: Ctrl+J opens a " ..
        "required file to browse it", function()
      K.open()
      K.browse_to(1)
      K.keys("lctrl", "j")
      assert.same("mod.lua", K.file_name())
      assert.same("browsing", K.state())
    end)

    spec_it("IS1.5 Follow a file reference: Ctrl+J follows "
        .. "dofile", function()
      K.open()
      K.browse_to(2)
      K.keys("lctrl", "j")
      assert.same("script.lua", K.file_name())
    end)

    spec_it("IS1.5 Follow a file reference: during an edit "
        .. "Ctrl+J is refused with a notice", function()
      K.open()
      K.browse_to(1)
      K.type("w = 4")
      K.keys("lctrl", "j")
      assert.same("main.lua", K.file_name())
      assert.same("w = 4", K.draft())
      assert.is_not_nil(K.message())
    end)

    spec_it("IS1.5 Follow a file reference: with a draft of "
        .. "spaces alone Ctrl+J is refused, the draft kept",
        function()
      K.open()
      K.browse_to(1)
      K.type("  ")
      K.keys("lctrl", "j")
      assert.same("main.lua", K.file_name())
      assert.same("  ", K.draft())
      assert.is_not_nil(K.message())
    end)

    spec_it("IS1.5 Follow a file reference: with a replacement "
        .. "target Ctrl+J is refused with a notice", function()
      K.open()
      K.browse_to(3)
      K.keys("f2")
      K.browse_to(1)
      K.keys("lctrl", "j")
      assert.same("main.lua", K.file_name())
      assert.same(3, K.target())
      assert.same("x = 1", K.draft())
      assert.same(1, K.position())
      assert.is_not_nil(K.message())
    end)

    spec_it("IS1.5 Follow a file reference: on a block naming "
        .. "no file Ctrl+J is refused with a notice", function()
      K.open()
      K.browse_to(3)
      K.keys("lctrl", "j")
      assert.same("main.lua", K.file_name())
      assert.same(3, K.position())
      assert.truthy((K.message() or ""):find("require", 1, true))
    end)

    -- Leaving the editor during an edit: the spec names no
    -- rule, so the editor does as Luditor, its reference
    -- implementation, does on Ctrl+Q (the lead's call, pending
    -- the maintainer's confirmation): the exit is refused with
    -- a notice and the state kept, as Ctrl+J is above.
    -- Ctrl+Shift+R and Ctrl+Shift+S left this list on
    -- 2026-11-14, when the keys were dropped, and Ctrl+R on
    -- 2026-11-16, when it came to restart a live program only:
    -- in the editor it does nothing.
    for _, exit in ipairs({
      { "Ctrl+T", { "lctrl", "t" } },
      { "Ctrl+Q", { "lctrl", "q" } },
    }) do
      spec_it("IS3.11 Preserve state on refusal: " .. exit[1] ..
          " during an insertion is refused with a notice",
          function()
        K.open()
        K.browse_to(2)
        K.type("w = 4")
        K.keys(unpack(exit[2]))
        assert.same("editor", K.app_state())
        assert.same("main.lua", K.file_name())
        assert.same("inserting", K.state())
        assert.same("w = 4", K.draft())
        assert.same(2, K.position())
        assert.truthy((K.message() or ""):find("Enter", 1, true))
      end)

      spec_it("IS3.11 Preserve state on refusal: " .. exit[1] ..
          " with a replacement target is refused with a notice",
          function()
        K.open()
        K.browse_to(3)
        K.keys("f2")
        K.keys(unpack(exit[2]))
        assert.same("editor", K.app_state())
        assert.same(3, K.target())
        assert.same("x = 1", K.draft())
        assert.truthy((K.message() or ""):find("Enter", 1, true))
      end)
    end

    spec_it("IS3.11 Preserve state on refusal: a draft kept " ..
        "by a failed write refuses an exit the same way",
        function()
      K.open()
      K.fail_writes("the card is full")
      K.type("w = 4")
      K.keys("return")
      K.keys("lctrl", "t")
      assert.same("editor", K.app_state())
      assert.same("w = 4", K.draft())
      assert.truthy((K.message() or ""):find("Enter", 1, true))
    end)

    spec_it("IS3.11 Preserve state on refusal: once the edit " ..
        "is aborted, Ctrl+Q leaves the editor", function()
      K.open()
      K.type("w = 4")
      K.keys("lctrl", "q")
      assert.same("editor", K.app_state())
      -- one Escape: the notice goes and the edit with it
      K.keys("escape")
      assert.same("browsing", K.state())
      assert.same("editor", K.app_state())
      K.keys("lctrl", "q")
      assert.same("ready", K.app_state())
    end)

    spec_it("IS3.11 Preserve state on refusal: Ctrl+Shift+S, "
        .. "dropped on 2026-11-14, does nothing", function()
      K.open()
      K.keys("lctrl", "lshift", "s")
      assert.same("editor", K.app_state())
      K.type("w = 4")
      K.keys("lctrl", "lshift", "s")
      assert.same("editor", K.app_state())
      assert.same("w = 4", K.draft())
      assert.is_nil(K.message())
    end)

    -- Ctrl+Q in the file editor (the reserved map of
    -- 2026-11-14; this reading of it for the editor is the
    -- lead's, pending the maintainer's confirmation): from the
    -- browsing state it returns to the console, every file on
    -- the editor's stack closed, and the project stays open.
    spec_it("IS1.6 Step back from a file with Escape: Ctrl+Q "
        .. "from the browsing state leaves the editor for the "
        .. "console, the project still open", function()
      K.open()
      K.browse_to(2)
      K.keys("lctrl", "q")
      assert.same("ready", K.app_state())
      assert.is_nil(K.cc.editor:get_active_buffer())
      assert.same("", K.console_draft())
      assert.same(K.PROJECT, K.cc.model.projects.current.name)
    end)

    spec_it("IS1.6 Step back from a file with Escape: Ctrl+Q "
        .. "with two files on the stack leaves both for the " ..
        "console", function()
      K.open()
      K.browse_to(1)
      K.keys("lctrl", "j")
      assert.same("mod.lua", K.file_name())
      assert.same(2, K.cc.editor.model.buffers:length())
      K.keys("lctrl", "q")
      assert.same("ready", K.app_state())
      assert.is_nil(K.cc.editor:get_active_buffer())
      assert.same(0, K.cc.editor.model.buffers:length())
      assert.same(K.PROJECT, K.cc.model.projects.current.name)
    end)

    spec_it("IS1.6 Step back from a file with Escape: Ctrl+Q "
        .. "in the console with no program running does " ..
        "nothing", function()
      K.type("x = 1")
      K.keys("lctrl", "q")
      assert.same("ready", K.app_state())
      assert.same("x = 1", K.console_draft())
      assert.same(K.PROJECT, K.cc.model.projects.current.name)
    end)

    -- What the console's key card says of Ctrl+Q while F1 is
    -- held: "exit program", under "Keys now" while a program
    -- is not stopped, under "Other keys" with none. The card is
    -- read in its reading order, column by column.
    local function card_ctrl_q()
      K.hold("f1")
      local lines = K.key_card() or { }
      K.release("f1")
      local section
      for col = 0, 1 do
        for _, l in ipairs(lines) do
          local cell = l:sub(col * 32 + 1, col * 32 + 32)
          if cell:find("Keys now", 1, true) then
            section = "now"
          elseif cell:find("Other keys", 1, true) then
            section = "other"
          elseif cell:find("^ Ctrl%+Q ") then
            return section, cell:match("^ Ctrl%+Q +(.-)%s*$")
          end
        end
      end
    end

    -- A paused program is live behind the console, not
    -- stopped; Ctrl+Q stops it.
    spec_it("IS3.16 Show the key card: the console's " ..
        "card lists Ctrl+Q as exit program, among the keys now " ..
        "while a program is not stopped and after them with " ..
        "none, and the key does nothing while the card shows",
        function()
      K.reset({ ["main.lua"] = "x = 1\npause('here')\n" })
      assert.same({ "other", "exit program" },
        { card_ctrl_q() })
      -- run the project from the editor: its first lines pause it,
      -- and the console is in front of it (a program that can do
      -- nothing more ends at its last line: stage 4)
      K.open()
      K.keys("lctrl", "t")
      assert.same("inspect", K.app_state())
      assert.is_true(K.cc.run_live)
      assert.same({ "now", "exit program" }, { card_ctrl_q() })
      K.hold("f1")
      K.keys("lctrl", "q")
      assert.is_true(K.cc.run_live)
      K.release("f1")
      K.keys("lctrl", "q")
      assert.is_false(K.cc.run_live)
      assert.same("ready", K.app_state())
      assert.same(K.PROJECT, K.cc.model.projects.current.name)
      assert.same({ "other", "exit program" },
        { card_ctrl_q() })
    end)

    -- A program paused by an error hands the console over; its
    -- card shows there, and Ctrl+Q exits the program.
    spec_it("IS3.16 Show the key card: while a program " ..
        "is paused, the console's card lists Ctrl+Q among the " ..
        "keys now, and the key does nothing while the card shows",
        function()
      K.reset({
        ["main.lua"] = "function love.update() error('x') end\n"
      })
      K.open()
      K.keys("lctrl", "t")
      -- the error pauses the run, in the frame it raises in
      K.frame()
      assert.same("inspect", K.app_state())
      assert.same({ "now", "exit program" }, { card_ctrl_q() })
      K.hold("f1")
      K.keys("lctrl", "q")
      assert.same("inspect", K.app_state())
      K.release("f1")
      K.keys("lctrl", "q")
      assert.same("ready", K.app_state())
      assert.is_false(K.cc.run_live)
    end)

    -- keys the map reserves no longer, and Ctrl+F, whose
    -- search the editor no longer has: in the editor they do
    -- nothing, with or without an edit in progress
    for _, key in ipairs({
      { "Ctrl+S", { "lctrl", "s" } },
      { "Ctrl+Shift+R", { "lctrl", "lshift", "r" } },
      { "Ctrl+F", { "lctrl", "f" } },
    }) do
      spec_it("IS3.11 Preserve state on refusal: " .. key[1] ..
          " does nothing in the editor", function()
        K.open()
        K.browse_to(2)
        K.keys(unpack(key[2]))
        assert.same("editor", K.app_state())
        assert.same("main.lua", K.file_name())
        assert.same("browsing", K.state())
        assert.same(2, K.position())
        K.type("w = 4")
        K.keys(unpack(key[2]))
        assert.same("editor", K.app_state())
        assert.same("inserting", K.state())
        assert.same("w = 4", K.draft())
        assert.is_nil(K.message())
        assert.same(K.PROJECT, K.cc.model.projects.current.name)
      end)
    end

    spec_it(
        "IS1.5 Follow a file reference: a file that cannot " ..
        "be opened leaves the caller as it was", function()
      K.open("refs.lua")
      K.browse_to(2)
      local ok = pcall(K.keys, "lctrl", "j")
      assert.is_true(ok)
      assert.same("refs.lua", K.file_name())
      assert.same(2, K.position())
    end)
  end)

  describe("IS1.6", function()
    before_each(function()
      K.reset({
        ["main.lua"] = "local m = require(\"mod\")\nx = 1\n",
        ["mod.lua"] = "y = 2\n"
      })
    end)

    spec_it(
        "IS1.6 Step back from a file with Escape: the last " ..
        "file closes to the console, its field empty", function()
      K.open()
      K.keys("escape")
      assert.same("ready", K.app_state())
      assert.same("", K.console_draft())
    end)

    spec_it(
        "IS1.6 Step back from a file with Escape: a caller " ..
        "comes back at its browsing position", function()
      K.open()
      K.browse_to(1)
      K.keys("lctrl", "j")
      K.keys("escape")
      assert.same("main.lua", K.file_name())
      assert.same(1, K.position())
    end)

    spec_it("IS1.6 Step back from a file with Escape: the " ..
        "caller's document view comes back too", function()
      -- the reference stands far from the end, so the view
      -- there is not the one a file opens with
      local t = { }
      for i = 1, 60 do
        t[i] = "v" .. i .. " = " .. i
      end
      t[5] = "local m = require(\"mod\")"
      K.reset({
        ["main.lua"] = table.concat(t, "\n") .. "\n",
        ["mod.lua"] = "y = 2\n"
      })
      K.open()
      local opened = K.view_rows()
      K.browse_to(5)
      local rows = K.view_rows()
      assert.are_not.same(opened, rows)
      K.keys("lctrl", "j")
      K.keys("escape")
      assert.same("main.lua", K.file_name())
      assert.same(5, K.position())
      assert.same(rows, K.view_rows())
    end)

    spec_it("IS1.6 Step back from a file with Escape: in the "
        .. "console Escape clears a draft without running it",
        function()
      -- run, it would open the editor
      K.type("edit(\"main.lua\")")
      K.keys("escape")
      assert.same("", K.console_draft())
      assert.same("ready", K.app_state())
    end)

    spec_it("IS1.6 Step back from a file with Escape: on an "
        .. "empty console field Escape keeps the project open",
        function()
      K.keys("escape")
      assert.same("ready", K.app_state())
      assert.same(K.PROJECT, K.cc.model.projects.current.name)
    end)
  end)

  describe("IS1.7", function()
    before_each(function()
      K.reset({ ["main.lua"] = "x = 1\n" })
      K.open()
      K.fail_writes("the card is full")
    end)

    spec_it(
        "IS1.7 Report a persistence failure: a failed insert "
        .. "is not accepted and says so", function()
      K.browse_to_end()
      K.type("y = 2")
      K.keys("return")
      assert.same("x = 1\n", K.file())
      assert.same("y = 2", K.draft())
      assert.same("inserting", K.state())
      assert.same(1, K.blocks())
      -- the notice names the failure: the file and the reason
      local notice = K.message() or ""
      assert.truthy(notice:find("main.lua", 1, true))
      assert.truthy(notice:find("the card is full", 1, true))
      assert.same("end", K.position())
    end)

    spec_it("IS1.7 Report a persistence failure: the draft "
        .. "stays as typed", function()
      K.browse_to_end()
      K.type("y=2")
      K.keys("return")
      assert.same("y=2", K.draft())
    end)

    spec_it(
        "IS1.7 Report a persistence failure: after a failed "
        .. "replacement the view shows what is stored",
        function()
      K.browse_to(1)
      K.keys("f2")
      K.keys("end")
      K.type("9")
      K.keys("return")
      assert.same("x = 19", K.draft())
      assert.same("replacing", K.state())
      assert.same({ "x = 1" }, K.view_rows())
    end)
  end)
end)
