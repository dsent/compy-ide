-- The paths that keep a person's text and its undo timeline:
-- no write goes over storage the editor did not write, a
-- file the user did not leave keeps its draft's changes, the
-- retained draft is the accepted text, a file is written with
-- LF line ends, and a file the editor cannot split into
-- blocks can be repaired. Keys only, through
-- tests/helpers/editor_keys.lua.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it = marks.spec_it
local spec_deviation = marks.spec_deviation

local UNREAD = "Could not read"
local BOM = "\239\187\191"

describe("timeline safety #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  -- the ruling "A lost SD card is the IDE's failure to
  -- handle": one guard before a write, and a file that changed
  -- while the editor was hidden read anew
  describe("storage the editor did not write", function()
    spec_it("IS3.11 Preserve state on refusal: a write over a "
        .. "file changed outside the editor is refused, and the "
        .. "draft stays", function()
      K.reset({ ["main.lua"] = "a = 1\n" })
      K.open()
      K.type("b = 2")
      K.write_outside("main.lua", "z = 9\n")
      K.keys("return")
      assert.same("z = 9\n", K.file())
      assert.same("b = 2", K.draft())
      assert.truthy((K.message() or ""):find(
        "changed outside the editor", 1, true))
    end)

    spec_it("IS3.11 Preserve state on refusal: a write to a file "
        .. "that cannot be read is refused, and the draft stays",
      function()
        K.reset({ ["main.lua"] = "a = 1\n" })
        K.open()
        K.type("b = 2")
        K.fail_reads()
        K.keys("return")
        K.mend_reads()
        assert.same("a = 1\n", K.file())
        assert.same("b = 2", K.draft())
        assert.truthy((K.message() or ""):find(UNREAD, 1, true))
      end)

    spec_it("IS1.4 Resume after running a project: a file "
        .. "changed while the editor was hidden comes back as "
        .. "storage holds it, its timeline afresh", function()
      K.reset({ ["main.lua"] = "x = 1\ny = 2\n" })
      K.open()
      K.type("z = 3")
      K.keys("return")
      local rewritten = "p = 1\nq = 2\nr = 3\n"
      K.keys("lctrl", "t")
      K.write_outside("main.lua", rewritten)
      K.keys("lctrl", "t")
      assert.same("main.lua", K.file_name())
      assert.same({ "p = 1", "q = 2", "r = 3" }, K.view_rows())
      K.keys("lctrl", "z")
      assert.same(rewritten, K.file())
      K.type("s = 4")
      K.keys("return")
      assert.same(rewritten .. "s = 4\n", K.file())
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

    spec_it("IS1.4 Resume after running a project: a run "
        .. "restarted with Ctrl+R keeps the timeline for Ctrl+T's "
        .. "return", function()
        K.reset({ ["main.lua"] = "x = 1\ny = 2\n" })
        K.open()
        K.browse_to(1)
        K.keys("lctrl", "delete")
        K.keys("escape")
        K.keys("lctrl", "t")
        K.keys("lctrl", "r")
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
    spec_deviation("IS6.4 Submit and retain the field: the draft "
        .. "kept is the accepted text, the run of empty lines the "
        .. "formatter leaves one, through undo and redo",
        "rulings.md: The formatter decides a draft's empty lines", function()
      K.reset({ ["main.lua"] = "" })
      K.open()
      K.type_lines({ "a=1", "", "", "b=2" })
      K.keys("lshift", "insert")
      assert.same("a = 1\n\nb = 2\n", K.file())
      assert.same("a = 1\n\nb = 2", K.draft())
      K.keys("lctrl", "z")
      K.keys("lctrl", "y")
      assert.same("a = 1\n\nb = 2", K.draft())
    end)
  end)

  -- the ruling "A file is written with LF line ends": LF,
  -- CRLF and a lone CR each end a line on opening, opening
  -- writes nothing, and the first save writes LF throughout
  describe("line endings", function()
    local FILES = {
      { "CRLF", "a = 1\r\nb = 2\r\nc = 3\r\n" },
      { "CR", "a = 1\rb = 2\rc = 3\r" },
      { "mixed", "a = 1\r\nb = 2\nc = 3\r" },
    }
    for _, ext in ipairs({ "lua", "txt", "md" }) do
      local name = "notes." .. ext
      for _, f in ipairs(FILES) do
        spec_it("FR3.1 Preserve file structure: a ." .. ext
            .. " file with " .. f[1] .. " line ends opens as its "
            .. "lines and stays as it is until a submission, "
            .. "which writes it with LF; undo gives the lines "
            .. "back", function()
          K.reset({ [name] = f[2] })
          K.open(name)
          assert.same(3, K.blocks())
          K.browse_to(2)
          K.keys("f2")
          assert.same("b = 2", K.draft())
          K.keys("escape")
          assert.same(f[2], K.file(name))
          assert.same({ }, K.writes())
          K.browse_to_end()
          K.type("d = 4")
          K.keys("return")
          assert.same("a = 1\nb = 2\nc = 3\nd = 4\n", K.file(name))
          K.keys("lctrl", "z")
          assert.same("a = 1\nb = 2\nc = 3\n", K.file(name))
        end)
      end
    end
  end)

  describe("a file the editor cannot split into blocks", function()
    local FILE = BOM .. "x = 1\nfunction f()\n  return 1\nend\n"
        .. "y = 2\n"

    -- Edit opens its lines (the maintainer's ruling of
    -- November 14, 2026); formatting is refused
    spec_it("IS1.2 Admit or refuse a file: the notice of a file "
        .. "the editor cannot split does not call a file that "
        .. "runs invalid", function()
      K.reset({ ["main.lua"] = FILE })
      K.open()
      K.keys("lalt", "f")
      local msg = K.message() or ""
      assert.falsy(msg:find("valid", 1, true))
      assert.truthy(msg:find("cannot split", 1, true))
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

    -- a guard: the file read so before
    spec_it("IS1.2 Admit or refuse a file: a file of a #! line "
        .. "alone is read as a block, and text goes after it",
      function()
        K.reset({ ["main.lua"] = "#!/usr/bin/lua\n" })
        K.open()
        assert.same(1, K.blocks())
        assert.falsy(K.buffer().invalid)
        K.type("x = 1")
        K.keys("return")
        assert.same("#!/usr/bin/lua\nx = 1\n", K.file())
      end)

    spec_it("FR3.1 Preserve file structure: formatting the "
        .. "whole file keeps a #! first line as it is", function()
      K.reset({ ["main.lua"] = "#!/usr/bin/lua\nx=1\n" })
      K.open()
      K.keys("lalt", "f")
      assert.same("#!/usr/bin/lua\nx = 1\n", K.file())
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
