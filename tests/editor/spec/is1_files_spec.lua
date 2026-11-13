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

    spec_gap("IS1.1 Open a Lua file: the browsing position " ..
        "starts at the end", function(gap)
      K.open()
      gap(function()
        assert.same("end", K.position())
      end)
    end)

    spec_gap(
        "IS1.1 Open a Lua file: an empty file opens at its " ..
        "end, with no block", function(gap)
      K.open("empty.lua")
      gap(function()
        assert.same(0, K.blocks())
        assert.same("end", K.position())
      end)
    end)

    spec_gap("IS1.1 Open a Lua file: a refused file leaves the "
        .. "console, its field empty", function(gap)
      K.open("bad.lua")
      gap(function()
        assert.same("ready", K.app_state())
        assert.same("", K.console_draft())
      end)
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

    spec_gap("IS1.2 Admit or refuse a file: any other name " ..
        "opens as plain text", function(gap)
      K.open("todo_md")
      local first = K.file_type()
      K.restart()
      K.open("notes_lua")
      local second = K.file_type()
      gap(function()
        assert.same({
          "plain",
          "plain"
        }, {
          first,
          second
        })
      end)
    end)

    spec_gap("IS1.2 Admit or refuse a file: invalid UTF-8 is "
        .. "refused with a notice naming the file", function(
      gap
    )
      K.open("bad8.lua")
      gap(function()
        assert.same("ready", K.app_state())
        assert.truthy(
          K.console_text():find("bad8.lua", 1, true)
        )
      end)
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

    spec_gap(
        "IS1.2 Admit or refuse a file: a created file holds "
        .. "only what was submitted", function(gap)
      K.open("new.lua")
      K.browse_to_end()
      K.type("a = 1")
      K.keys("return")
      gap(function()
        assert.same("a = 1\n", K.file("new.lua"))
      end)
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

    spec_gap("IS1.3 Handle size limits: Edit on an oversized "
        .. "block is refused with a notice naming the limit",
        function(gap)
      K.open()
      K.browse_to(1)
      K.keys("f2")
      gap(function()
        assert.same("browsing", K.state())
        assert.truthy((K.message() or ""):find("14", 1, true))
      end)
    end)

    spec_gap("IS1.3 Handle size limits: cutting an oversized "
        .. "block loads it into the field", function(gap)
      K.open()
      K.browse_to(1)
      K.keys("lctrl", "delete")
      gap(function()
        assert.same("inserting", K.state())
        assert.same(tall(16):gsub("\n$", ""), K.draft())
      end)
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
      assert.is_not_nil(K.message())
    end)
  end)

  describe("IS1.4", function()
    before_each(function()
      K.reset({ ["main.lua"] = "x = 1\ny = 2\nz = 3\n" })
      K.open()
    end)

    spec_gap("IS1.4 Resume after running a project: Ctrl+T and "
        .. "back restores the browsing position", function(gap)
      K.browse_to(2)
      K.keys("lctrl", "t")
      K.keys("lctrl", "t")
      gap(function()
        assert.same("editor", K.app_state())
        assert.same("main.lua", K.file_name())
        assert.same(2, K.position())
      end)
    end)

    spec_gap("IS1.4 Resume after running a project: the end "
        .. "position is restored too", function(gap)
      K.browse_to_end()
      K.keys("lctrl", "t")
      K.keys("lctrl", "t")
      gap(function()
        assert.same("end", K.position())
      end)
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

    spec_gap("IS1.5 Follow a file reference: Ctrl+J follows "
        .. "dofile", function(gap)
      K.open()
      K.browse_to(2)
      K.keys("lctrl", "j")
      gap(function()
        assert.same("script.lua", K.file_name())
      end)
    end)

    spec_gap("IS1.5 Follow a file reference: during an edit "
        .. "Ctrl+J is refused with a notice", function(gap)
      K.open()
      K.browse_to(1)
      K.type("w = 4")
      K.keys("lctrl", "j")
      gap(function()
        assert.same("main.lua", K.file_name())
        assert.same("w = 4", K.draft())
        assert.is_not_nil(K.message())
      end)
    end)

    spec_gap(
        "IS1.5 Follow a file reference: a file that cannot " ..
        "be opened leaves the caller as it was", function(gap)
      K.open("refs.lua")
      K.browse_to(2)
      local ok = pcall(K.keys, "lctrl", "j")
      gap(function()
        assert.is_true(ok)
        assert.same("refs.lua", K.file_name())
        assert.same(2, K.position())
      end)
    end)
  end)

  describe("IS1.6", function()
    before_each(function()
      K.reset({
        ["main.lua"] = "local m = require(\"mod\")\nx = 1\n",
        ["mod.lua"] = "y = 2\n"
      })
    end)

    spec_gap(
        "IS1.6 Step back from a file with Escape: the last " ..
        "file closes to the console, its field empty", function(
      gap
    )
      K.open()
      K.keys("escape")
      gap(function()
        assert.same("ready", K.app_state())
        assert.same("", K.console_draft())
      end)
    end)

    spec_gap(
        "IS1.6 Step back from a file with Escape: a caller " ..
        "comes back at its browsing position", function(gap)
      K.open()
      K.browse_to(1)
      K.keys("lctrl", "j")
      K.keys("escape")
      gap(function()
        assert.same("main.lua", K.file_name())
        assert.same(1, K.position())
      end)
    end)

    spec_gap("IS1.6 Step back from a file with Escape: the " ..
        "caller's document view comes back too", function(gap)
      local t = { }
      for i = 1, 30 do
        t[i] = "v" .. i .. " = " .. i
      end
      t[31] = "local m = require(\"mod\")"
      K.reset({
        ["main.lua"] = table.concat(t, "\n") .. "\n",
        ["mod.lua"] = "y = 2\n"
      })
      K.open()
      K.browse_to(31)
      local rows = K.view_rows()
      K.keys("lctrl", "j")
      K.keys("escape")
      gap(function()
        assert.same("main.lua", K.file_name())
        assert.same(rows, K.view_rows())
      end)
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
      assert.truthy((K.message() or ""):lower():find("save"))
    end)

    spec_it("IS1.7 Report a persistence failure: the draft "
        .. "stays as typed", function()
      K.browse_to_end()
      K.type("y=2")
      K.keys("return")
      assert.same("y=2", K.draft())
    end)

    spec_gap(
        "IS1.7 Report a persistence failure: after a failed "
        .. "replacement the view shows what is stored",
        function(gap)
      K.browse_to(1)
      K.keys("f2")
      K.keys("end")
      K.type("9")
      K.keys("return")
      gap(function()
        assert.same("x = 19", K.draft())
        assert.same("replacing", K.state())
        assert.same({ "x = 1" }, K.view_rows())
      end)
    end)
  end)
end)
