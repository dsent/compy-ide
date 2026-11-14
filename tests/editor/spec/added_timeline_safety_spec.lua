-- The paths that keep a person's text and its undo timeline:
-- storage that cannot be read just now forgets nothing, a
-- file the user did not leave keeps its draft's changes, the
-- retained draft is the accepted text, each line keeps its
-- own ending, and a file the editor cannot split into blocks
-- can be repaired. Keys only, through
-- tests/helpers/editor_keys.lua.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it = marks.spec_it

local UNREAD = "Could not read"
local BOM = "\239\187\191"

describe("timeline safety #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  describe("storage that cannot be read just now", function()
    for _, ext in ipairs({ "lua", "txt", "md" }) do
      spec_it("IS6.6 Undo and redo: in a ." .. ext .. " file, "
          .. "Ctrl+Z while the file cannot be read says so and "
          .. "forgets nothing", function()
        local name = "notes." .. ext
        K.reset({ [name] = "a = 1\n" })
        K.open(name)
        K.type("precious = 123")
        K.keys("escape")
        K.fail_reads()
        K.keys("lctrl", "z")
        assert.same("", K.draft())
        assert.truthy((K.message() or ""):find(UNREAD, 1, true))
        K.mend_reads()
        K.keys("lctrl", "z")
        assert.same("precious = 123", K.draft())
        assert.same("a = 1\n", K.file(name))
      end)
    end

    spec_it("IS6.6 Undo and redo: an accepted change and its "
        .. "redo outlast a failed read", function()
      K.reset({ ["main.lua"] = "a = 1\n" })
      K.open()
      K.type("b = 2")
      K.keys("return")
      K.fail_reads()
      K.keys("lctrl", "z")
      assert.same("a = 1\nb = 2\n", K.file())
      K.mend_reads()
      K.keys("lctrl", "z")
      assert.same("a = 1\n", K.file())
      K.fail_reads()
      K.keys("lctrl", "y")
      assert.same("a = 1\n", K.file())
      assert.truthy((K.message() or ""):find(UNREAD, 1, true))
      K.mend_reads()
      K.keys("lctrl", "y")
      assert.same("a = 1\nb = 2\n", K.file())
    end)

    spec_it("IS6.6 Undo and redo: with the SD card out, nothing "
        .. "is cut and nothing forgotten; back in, the cut and "
        .. "its undo work", function()
      K.reset({ ["main.lua"] = "x = 1\ny = 2\n" })
      K.open()
      K.browse_to(1)
      K.keys("lctrl", "delete")
      K.keys("escape")
      K.remove_card()
      K.keys("lctrl", "z")
      assert.truthy((K.message() or ""):find(UNREAD, 1, true))
      K.keys("lctrl", "delete")
      assert.truthy((K.message() or ""):find(
        "nothing is cut", 1, true))
      K.insert_card()
      K.keys("lctrl", "z")
      assert.same("x = 1", K.draft())
      K.keys("lctrl", "z")
      assert.same("x = 1\ny = 2\n", K.file())
    end)

    spec_it("IS1.4 Resume after running a project: a return "
        .. "while the file cannot be read comes back to it, and "
        .. "its timeline waits for the read", function()
      K.reset({ ["main.lua"] = "a = 1\n" })
      K.open()
      K.type("precious = 123")
      K.keys("escape")
      K.keys("lctrl", "t")
      K.fail_reads()
      K.keys("lctrl", "t")
      assert.same("editor", K.app_state())
      assert.same("main.lua", K.file_name())
      K.keys("lctrl", "z")
      assert.same("", K.draft())
      assert.truthy((K.message() or ""):find(UNREAD, 1, true))
      K.mend_reads()
      K.keys("lctrl", "z")
      assert.same("precious = 123", K.draft())
    end)

    spec_it("IS6.6 Undo and redo: a run that rewrote the file "
        .. "ends its timeline, and Ctrl+Z then writes nothing",
      function()
        K.reset({ ["main.lua"] = "x = 1\ny = 2\n" })
        K.open()
        K.type("z = 3")
        K.keys("return")
        local rewritten = "p = 1\nq = 2\nr = 3\ns = 4\n"
        K.keys("lctrl", "t")
        K.write_outside("main.lua", rewritten)
        K.keys("lctrl", "t")
        assert.same("main.lua", K.file_name())
        K.keys("lctrl", "z")
        assert.same(rewritten, K.file())
      end)
  end)

  describe("a file the user did not leave", function()
    spec_it("IS1.5 Follow a file reference: the caller's draft "
        .. "changes stay undoable and redoable after the "
        .. "followed file", function()
      K.reset({
        ["main.lua"] = "dofile(\"notes.txt\")\n",
        ["notes.txt"] = "n\n",
      })
      K.open()
      K.browse_to(1)
      K.type("q")
      K.keys("backspace")
      K.keys("lctrl", "j")
      assert.same("notes.txt", K.file_name())
      K.keys("escape")
      assert.same("main.lua", K.file_name())
      K.keys("lctrl", "z")
      assert.same("q", K.draft())
      K.keys("lctrl", "y")
      assert.same("", K.draft())
      K.keys("lctrl", "z")
      K.keys("lctrl", "z")
      assert.same("", K.draft())
    end)

    spec_it("IS1.4 Resume after running a project: a caller's "
        .. "draft changes outlast a run from the followed file",
      function()
        K.reset({
          ["main.lua"] = "dofile(\"notes.txt\")\n",
          ["notes.txt"] = "n\n",
        })
        K.open()
        K.browse_to(1)
        K.type("q")
        K.keys("backspace")
        K.keys("lctrl", "j")
        K.keys("lctrl", "t")
        K.keys("lctrl", "t")
        assert.same("notes.txt", K.file_name())
        K.keys("escape")
        assert.same("main.lua", K.file_name())
        K.keys("lctrl", "z")
        assert.same("q", K.draft())
      end)

    spec_it("IS1.4 Resume after running a project: the draft's "
        .. "changes stay undoable after a run with Ctrl+T",
      function()
        K.reset({ ["main.lua"] = "x = 1\n" })
        K.open()
        K.type("q")
        K.keys("backspace")
        K.keys("lctrl", "t")
        K.keys("lctrl", "t")
        assert.same("main.lua", K.file_name())
        K.keys("lctrl", "z")
        assert.same("q", K.draft())
      end)

    spec_it("IS1.4 Resume after running a project: a run with "
        .. "Ctrl+Alt+R keeps the timeline for Ctrl+T's return",
      function()
        K.reset({ ["main.lua"] = "x = 1\ny = 2\n" })
        K.open()
        K.browse_to(1)
        K.keys("lctrl", "delete")
        K.keys("escape")
        K.keys("lctrl", "lalt", "r")
        assert.are_not.same("editor", K.app_state())
        K.keys("lctrl", "t")
        assert.same("main.lua", K.file_name())
        K.keys("lctrl", "z")
        assert.same("x = 1", K.draft())
        K.keys("lctrl", "z")
        assert.same("x = 1\ny = 2\n", K.file())
      end)
  end)

  describe("the retained draft", function()
    spec_it("IS6.4 Submit and retain the field: the draft kept "
        .. "is the accepted text, empty lines included, through "
        .. "undo and redo", function()
      K.reset({ ["main.lua"] = "" })
      K.open()
      K.type_lines({ "a=1", "", "", "b=2" })
      K.keys("lshift", "insert")
      assert.same("a = 1\n\n\nb = 2\n", K.file())
      assert.same("a = 1\n\n\nb = 2", K.draft())
      K.keys("lctrl", "z")
      K.keys("lctrl", "y")
      assert.same("a = 1\n\n\nb = 2", K.draft())
    end)
  end)

  describe("line endings", function()
    local MIXED = "a = 1\r\nb = 2\nc = 3\r\n"
    for _, ext in ipairs({ "lua", "txt", "md" }) do
      local name = "notes." .. ext

      spec_it("FR3.1 Preserve file structure: in a ." .. ext
          .. " file, a cut line comes back by undo with its own "
          .. "ending", function()
        K.reset({ [name] = MIXED })
        K.open(name)
        K.browse_to(2)
        K.keys("lctrl", "delete")
        assert.same("a = 1\r\nc = 3\r\n", K.file(name))
        K.keys("lctrl", "z")
        K.keys("lctrl", "z")
        assert.same(MIXED, K.file(name))
        K.keys("lctrl", "y")
        K.keys("lctrl", "y")
        assert.same("a = 1\r\nc = 3\r\n", K.file(name))
      end)

      spec_it("FR3.1 Preserve file structure: in a ." .. ext
          .. " file, a moved line keeps its ending, and so does "
          .. "the move's undo", function()
        K.reset({ [name] = MIXED })
        K.open(name)
        K.browse_to(2)
        K.keys("lalt", "up")
        assert.same("b = 2\na = 1\r\nc = 3\r\n", K.file(name))
        K.keys("lctrl", "z")
        assert.same(MIXED, K.file(name))
      end)

      spec_it("FR3.1 Preserve file structure: in a ." .. ext
          .. " file, a new line takes the ending most lines "
          .. "have, the first in the file of two as frequent",
        function()
          local even = "a = 1\r\nb = 2\nc = 3\nd = 4\r\n"
          K.reset({ [name] = even })
          K.open(name)
          K.type("e = 5")
          K.keys("return")
          assert.same(even .. "e = 5\r\n", K.file(name))
        end)
    end

    spec_it("FR3.1 Preserve file structure: identical lines "
        .. "keep their own endings through a cut and its undo",
      function()
        local same = "a\r\na\na\r\n"
        K.reset({ ["notes.txt"] = same })
        K.open("notes.txt")
        K.browse_to(1)
        K.keys("lctrl", "delete")
        assert.same("a\na\r\n", K.file("notes.txt"))
        K.keys("lctrl", "z")
        K.keys("lctrl", "z")
        assert.same(same, K.file("notes.txt"))
      end)
  end)

  describe("a file the editor cannot split into blocks", function()
    local FILE = BOM .. "x = 1\nfunction f()\n  return 1\nend\n"
        .. "y = 2\n"

    spec_it("IS1.2 Admit or refuse a file: Edit's notice does not "
        .. "call a file that runs invalid", function()
      K.reset({ ["main.lua"] = FILE })
      K.open()
      K.browse_to(1)
      K.keys("f2")
      local msg = K.message() or ""
      assert.falsy(msg:find("valid", 1, true))
      assert.truthy(msg:find("Ctrl+Delete", 1, true))
    end)

    spec_it("IS6.2 Cut a block: the line to repair is cut, with "
        .. "no notice of a merge that is not one", function()
      K.reset({ ["main.lua"] = FILE })
      K.open()
      K.browse_to(1)
      K.keys("lctrl", "delete")
      assert.same(BOM .. "x = 1", K.draft())
      assert.same("function f()\n  return 1\nend\ny = 2\n",
        K.file())
      assert.falsy((K.message() or ""):find("merge", 1, true))
    end)

    spec_it("IS4.2 Append after the last block: a draft of "
        .. "several lines lands in such a file", function()
      K.reset({ ["main.lua"] = "x = 1\ngoto done\n::done::\n" })
      K.open()
      K.type_lines({ "if x then", "  y = 2", "end" })
      K.keys("return")
      assert.same("x = 1\ngoto done\n::done::\n"
        .. "if x then\n  y = 2\nend\n", K.file())
      assert.falsy((K.message() or ""):find("merge", 1, true))
    end)
  end)

  describe("a line that starts with #", function()
    spec_it("IS3.4 Locate a syntax failure: a draft whose first "
        .. "line starts with # is refused, and nothing is lost",
      function()
        K.reset({ ["main.lua"] = "x = 1\n" })
        K.open()
        K.type_lines({ "# note", "y = 1" })
        K.keys("return")
        assert.same("x = 1\n", K.file())
        assert.same("# note\ny = 1", K.draft())
        assert.same("error", K.message_kind())
      end)

    spec_it("IS3.4 Locate a syntax failure: a #! draft is no "
        .. "file's first line, and is refused", function()
      K.reset({ ["main.lua"] = "x = 1\n" })
      K.open()
      K.type("#!/usr/bin/lua")
      K.keys("return")
      assert.same("x = 1\n", K.file())
      assert.same("#!/usr/bin/lua", K.draft())
      assert.same("error", K.message_kind())
    end)

    spec_it("IS3.4 Locate a syntax failure: a refused #! draft "
        .. "is red from the failing character, the cursor before "
        .. "it", function()
      K.reset({ ["main.lua"] = "x = 1\n" })
      K.open()
      K.type("#!/usr/bin/lua")
      local _, red = K.field_highlight()
      K.keys("return")
      assert.same({ 1, 2 }, red)
      assert.same({ 1, 2 }, { K.cursor() })
      assert.truthy(K.message():find("`!'", 1, true))
    end)

    spec_it("IS1.2 Admit or refuse a file: a file of a #! line "
        .. "alone is read as blocks", function()
      K.reset({ ["main.lua"] = "#!/usr/bin/lua\n" })
      K.open()
      K.browse_to(1)
      K.keys("f2")
      assert.same("replacing", K.state())
    end)

    spec_it("FR3.1 Preserve file structure: formatting the "
        .. "whole file keeps a #! first line as it is", function()
      K.reset({ ["main.lua"] = "#!/usr/bin/lua\nx=1\n" })
      K.open()
      K.keys("lctrl", "lshift", "f")
      assert.same("#!/usr/bin/lua\nx = 1\n", K.file())
    end)

    spec_it("FR3.1 Preserve file structure: a draft does not go "
        .. "above a #! first line, and the notice gives no reason "
        .. "that is not the cause", function()
      local text = "#!/usr/bin/lua\nx = 1\n"
      K.reset({ ["main.lua"] = text })
      K.open()
      K.browse_to(1)
      K.type("y = 2")
      K.keys("return")
      assert.same(text, K.file())
      assert.same("y = 2", K.draft())
      local msg = K.message() or ""
      assert.truthy(msg:find("could not run the file", 1, true))
      assert.falsy(msg:find("return or break", 1, true))
    end)
  end)

  describe("the draft's own changes", function()
    spec_it("IS6.6 Undo and redo: Ctrl+Shift+Y and Ctrl+Alt+Y "
        .. "delete no draft text", function()
      K.reset({ ["main.lua"] = "x = 1\n" })
      K.open()
      K.type("a = 1")
      K.keys("lctrl", "lshift", "y")
      K.keys("lctrl", "lalt", "y")
      assert.same("a = 1", K.draft())
    end)

    spec_it("IS6.6 Undo and redo: a draft of over a thousand "
        .. "changes undoes to its start", function()
      K.reset({ ["notes.txt"] = "" })
      K.open("notes.txt")
      K.type("keep")
      for _ = 1, 501 do
        K.type("x")
        K.keys("backspace")
      end
      for _ = 1, 1003 do K.keys("lctrl", "z") end
      assert.same("", K.draft())
    end)

    spec_it("IS6.2 Cut a block: a Lua line of spaces goes into "
        .. "the field as it is", function()
      K.reset({ ["main.lua"] = "a = 1\n  \nb = 2\n" })
      K.open()
      K.browse_to(2)
      K.keys("lctrl", "delete")
      assert.same("a = 1\nb = 2\n", K.file())
      assert.same("  ", K.draft())
    end)
  end)
end)
