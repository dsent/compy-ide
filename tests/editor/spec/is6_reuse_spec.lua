-- IS6 Reusing, removing, and reordering blocks (editor
-- principles, ratified), and the two journeys of copying one
-- block into another. Keys only, through
-- tests/helpers/editor_keys.lua. Edit is F2; copy is
-- Ctrl+Ins; cut is Ctrl+Delete; move is Alt+Up and Alt+Down.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it, spec_gap = marks.spec_it, marks.spec_gap

local FILE = "x = 1\ny = 2\nz = 3\n"

local function open_file(text)
  K.reset({ ["main.lua"] = text or FILE })
  K.open()
end

describe("IS6 reuse #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  describe("IS6.1", function()
    before_each(function()
      open_file()
    end)

    spec_gap(
        "IS6.1 Copy a block: in browsing, Ctrl+Ins begins an "
        .. "insertion with the block's text", function(gap)
      K.browse_to(2)
      K.keys("lctrl", "insert")
      gap(function()
        assert.same("inserting", K.state())
        assert.same("y = 2", K.draft())
        assert.same({
          1,
          6
        }, { K.cursor() })
        assert.is_nil(K.target())
        assert.same(FILE, K.file())
      end)
    end)

    spec_gap(
        "IS6.1 Copy a block: into a draft, on lines of its " ..
        "own, the cursor after it", function(gap)
      K.browse_to_end()
      K.type("a = 1")
      K.keys("lctrl", "home")
      local browsed = pcall(K.browse_to, 1)
      K.keys("lctrl", "insert")
      gap(function()
        assert.is_true(browsed)
        assert.same("x = 1\na = 1", K.draft())
        assert.same({
          1,
          6
        }, { K.cursor() })
        assert.same(FILE, K.file())
      end)
    end)

    spec_gap(
        "IS6.1 Copy a block: into a replacement, the target "
        .. "stays", function(gap)
      K.browse_to(1)
      K.keys("f2")
      local browsed = pcall(K.browse_to, 3)
      K.keys("lctrl", "insert")
      gap(function()
        assert.is_true(browsed)
        assert.same(1, K.target())
        assert.same("x = 1\nz = 3", K.draft())
        assert.same(FILE, K.file())
      end)
    end)
  end)

  describe("IS6.2 and IS6.3", function()
    spec_gap("IS6.2 Cut a block: the block leaves, its text in "
        .. "the field, the position on the next", function(gap)
      open_file()
      K.browse_to(2)
      K.keys("lctrl", "delete")
      gap(function()
        assert.same("x = 1\nz = 3\n", K.file())
        assert.same("inserting", K.state())
        assert.same("y = 2", K.draft())
        assert.same({
          1,
          6
        }, { K.cursor() })
        assert.same(2, K.position())
      end)
    end)

    spec_it("IS6.2 Cut a block: an empty line leaves the field "
        .. "empty, browsing", function()
      open_file("x = 1\n\ny = 2\n")
      K.browse_to(2)
      K.keys("lctrl", "delete")
      assert.same("x = 1\ny = 2\n", K.file())
      assert.same("browsing", K.state())
      assert.same("", K.draft())
      assert.same(2, K.position())
    end)

    spec_gap("IS6.2 Cut a block: cutting the only block leaves "
        .. "an empty file, at its end", function(gap)
      open_file("x = 1\n")
      K.browse_to(1)
      K.keys("lctrl", "delete")
      gap(function()
        assert.same("", K.file())
        assert.same("end", K.position())
        assert.same(0, K.blocks())
      end)
    end)

    spec_gap(
        "IS6.2 Cut a block: refused in a replacement, with " ..
        "a notice", function(gap)
      open_file()
      K.browse_to(2)
      K.keys("f2")
      K.keys("lctrl", "delete")
      gap(function()
        assert.same("replacing", K.state())
        assert.same("y = 2", K.draft())
        assert.same(FILE, K.file())
        assert.is_not_nil(K.message())
      end)
    end)

    spec_it("IS6.3 Restore a cut block: Ctrl+Z puts it back in "
        .. "place, the field empty", function()
      open_file()
      K.browse_to(2)
      K.keys("lctrl", "delete")
      K.keys("lctrl", "z")
      assert.same(FILE, K.file())
      assert.same("browsing", K.state())
      assert.same("", K.draft())
    end)

    spec_gap(
        "IS6.3 Restore a cut block: typing after the cut is "
        .. "taken back first", function(gap)
      open_file()
      K.browse_to(2)
      K.keys("lctrl", "delete")
      K.type("x")
      K.keys("lctrl", "z")
      local first = {
        K.draft(),
        K.file()
      }
      K.keys("lctrl", "z")
      gap(function()
        assert.same({
          "y = 2",
          "x = 1\nz = 3\n"
        }, first)
        assert.same(FILE, K.file())
      end)
    end)
  end)

  describe("IS6.4 and IS6.5", function()
    before_each(function()
      open_file()
    end)

    spec_gap("IS6.4 Submit and retain the field: Shift+Ins " ..
        "submits and keeps the draft", function(gap)
      K.browse_to_end()
      K.type("a = 1")
      K.keys("lshift", "insert")
      gap(function()
        assert.same(FILE .. "a = 1\n", K.file())
        assert.same("a = 1", K.draft())
        assert.same("inserting", K.state())
        assert.same({
          1,
          6
        }, { K.cursor() })
      end)
    end)

    spec_gap("IS6.5 Move a block: Alt+Up and Alt+Down move it, "
        .. "the highlight with it", function(gap)
      K.browse_to(2)
      K.keys("lalt", "up")
      local up = {
        K.file(),
        K.position()
      }
      K.keys("lalt", "down")
      gap(function()
        assert.same({
          "y = 2\nx = 1\nz = 3\n",
          1
        }, up)
        assert.same(FILE, K.file())
        assert.same(2, K.position())
      end)
    end)

    spec_gap("IS6.5 Move a block: at the end position, refused "
        .. "with a notice", function(gap)
      K.browse_to_end()
      K.keys("lalt", "up")
      local up = {
        K.file(),
        K.message()
      }
      K.keys("lalt", "down")
      gap(function()
        assert.same(FILE, up[1])
        assert.is_not_nil(up[2])
        assert.same(FILE, K.file())
        assert.is_not_nil(K.message())
      end)
    end)

    spec_it("IS6.5 Move a block: toward the edge, the first "
        .. "block stays", function()
      K.browse_to(1)
      K.keys("lalt", "up")
      assert.same(FILE, K.file())
      assert.same(1, K.position())
      assert.is_nil(K.message())
      K.browse_to(3)
      K.keys("lalt", "down")
      assert.same(FILE, K.file())
      assert.same(3, K.position())
    end)

    spec_gap(
        "IS6.5 Move a block: during an insertion, the draft "
        .. "and its cursor stay", function(gap)
      K.browse_to_end()
      K.type("a = 1")
      local browsed = pcall(K.browse_to, 2)
      K.keys("lalt", "up")
      gap(function()
        assert.is_true(browsed)
        assert.same("y = 2\nx = 1\nz = 3\n", K.file())
        assert.same("a = 1", K.draft())
        assert.same({
          1,
          6
        }, { K.cursor() })
      end)
    end)

    spec_gap(
        "IS6.5 Move a block: refused in a replacement, with "
        .. "a notice", function(gap)
      K.browse_to(2)
      K.keys("f2")
      K.keys("lalt", "up")
      gap(function()
        assert.same("replacing", K.state())
        assert.same(FILE, K.file())
        assert.is_not_nil(K.message())
      end)
    end)
  end)

  describe("IS6.6", function()
    before_each(function()
      open_file()
    end)

    spec_it(
        "IS6.6 Undo and redo: undoing an acceptance does not "
        .. "reach into its typing", function()
      K.browse_to_end()
      K.type("a = 1")
      K.keys("return")
      K.keys("lctrl", "z")
      K.keys("lctrl", "z")
      assert.same(FILE, K.file())
      assert.same("", K.draft())
      assert.same("browsing", K.state())
    end)

    spec_it("IS6.6 Undo and redo: a refused submission leaves "
        .. "the draft's typing undoable", function()
      K.browse_to_end()
      local lines = K.block_lines(15)
      lines[2] = "  v1=1"
      K.type_lines(lines)
      local typed = K.draft()
      K.keys("return")
      -- refused for size: shown formatted (IS3.2)
      local refused = K.draft()
      assert.truthy(refused:find("\n  v1 = 1\n", 1, true))
      K.keys("lctrl", "z")
      assert.same(typed, K.draft())
      K.keys("lctrl", "y")
      assert.same(refused, K.draft())
      assert.same(FILE, K.file())
    end)

    spec_it("IS6.6 Undo and redo: a draft refused for line " ..
        "length leaves its typing undoable", function()
      K.browse_to_end()
      K.type(string.rep("x", 65) .. "=1")
      local typed = K.draft()
      K.keys("return")
      -- refused for the line: shown formatted, spaces added
      local refused = K.draft()
      assert.are_not.same(typed, refused)
      K.keys("lctrl", "z")
      assert.same(typed, K.draft())
      K.keys("lctrl", "y")
      assert.same(refused, K.draft())
      assert.same(FILE, K.file())
    end)

    spec_gap(
        "IS6.6 Undo and redo: from a draft, Ctrl+Z reaches " ..
        "the file once the draft is undone", function(gap)
      K.browse_to_end()
      K.type("a = 1")
      K.keys("return")
      K.type("b")
      K.keys("lctrl", "z")
      K.keys("lctrl", "z")
      gap(function()
        assert.same(FILE, K.file())
        assert.same("", K.draft())
      end)
    end)

    spec_it("IS6.6 Undo and redo: Ctrl+Y redoes, leaving the "
        .. "editor as the action did", function()
      K.browse_to_end()
      K.type("a = 1")
      K.keys("return")
      K.keys("lctrl", "z")
      K.keys("lctrl", "y")
      assert.same(FILE .. "a = 1\n", K.file())
      assert.same("browsing", K.state())
    end)

    spec_gap("IS6.6 Undo and redo: undo and redo put the " ..
        "position where the action left it", function(gap)
      K.browse_to_end()
      K.type("a = 1")
      K.keys("return")
      K.keys("lctrl", "z")
      -- where the removed block stood: the end
      local undone = K.position()
      K.keys("lctrl", "y")
      gap(function()
        assert.same("end", undone)
        assert.same("end", K.position())
      end)
    end)

    spec_gap("IS6.6 Undo and redo: a held Ctrl+Z stops at the "
        .. "cut, and one more press restores it", function(gap)
      K.browse_to(2)
      K.keys("lctrl", "delete")
      K.type("x")
      K.keys("backspace")
      K.hold("lctrl")
      K.hold("z")
      for _ = 1, 5 do
        K.repeat_key("z")
      end
      K.release("z")
      local held = {
        K.draft(),
        K.file()
      }
      K.keys("lctrl", "z")
      K.release("lctrl")
      gap(function()
        assert.same({
          "y = 2",
          "x = 1\nz = 3\n"
        }, held)
        assert.same(FILE, K.file())
        assert.same("", K.draft())
      end)
    end)

    spec_gap("IS6.6 Undo and redo: the timeline goes when the "
        .. "file is left", function(gap)
      K.browse_to_end()
      K.type("a = 1")
      K.keys("return")
      K.keys("escape")
      local left = K.app_state()
      K.open()
      K.keys("lctrl", "z")
      gap(function()
        assert.same("ready", left)
        assert.same(FILE .. "a = 1\n", K.file())
      end)
    end)

    -- "from outside": between two runs of the editor
    spec_it("IS6.6 Undo and redo: a file changed from outside "
        .. "between runs is left as it was", function()
      K.browse_to_end()
      K.type("a = 1")
      K.keys("return")
      K.restart()
      K.write_outside("main.lua", "q = 9\n")
      K.open()
      K.keys("lctrl", "z")
      assert.same("q = 9\n", K.file())
    end)
  end)

  describe("copying one block into another", function()
    before_each(function()
      open_file("a = 1\nb = 2\n")
    end)

    spec_gap(
        "FR1.8 Reuse a block in the draft: B copied into A " ..
        "is saved in A, and B stays", function(gap)
      K.browse_to(1)
      K.keys("f2")
      local browsed = pcall(K.browse_to, 2)
      K.keys("lctrl", "insert")
      K.keys("return")
      gap(function()
        assert.is_true(browsed)
        assert.same("a = 1\nb = 2\nb = 2\n", K.file())
      end)
    end)

    spec_gap(
        "FR1.8 Reuse a block in the draft: B copied into A, "
        .. "then B cut, leaves A holding both", function(gap)
      K.browse_to(1)
      K.keys("f2")
      local browsed = pcall(K.browse_to, 2)
      K.keys("lctrl", "insert")
      K.keys("return")
      local cut = pcall(K.browse_to, 3)
      K.keys("lctrl", "delete")
      K.keys("escape")
      gap(function()
        assert.is_true(browsed and cut)
        assert.same("a = 1\nb = 2\n", K.file())
        assert.same("browsing", K.state())
      end)
    end)
  end)
end)
