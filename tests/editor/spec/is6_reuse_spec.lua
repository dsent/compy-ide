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

    spec_it(
        "IS6.1 Copy a block: in browsing, Ctrl+Ins begins an "
        .. "insertion with the block's text", function()
      K.browse_to(2)
      K.keys("lctrl", "insert")
      assert.same("inserting", K.state())
      assert.same("y = 2", K.draft())
      assert.same({
        1,
        6
      }, { K.cursor() })
      assert.is_nil(K.target())
      assert.same(FILE, K.file())
    end)

    spec_it(
        "IS6.1 Copy a block: into a draft, on lines of its " ..
        "own, the cursor after it", function()
      K.browse_to_end()
      K.type("a = 1")
      K.keys("lctrl", "home")
      local browsed = pcall(K.browse_to, 1)
      K.keys("lctrl", "insert")
      assert.is_true(browsed)
      assert.same("x = 1\na = 1", K.draft())
      assert.same({
        1,
        6
      }, { K.cursor() })
      assert.same(FILE, K.file())
    end)

    spec_it(
        "IS6.1 Copy a block: into a replacement, the target "
        .. "stays", function()
      K.browse_to(1)
      K.keys("f2")
      local browsed = pcall(K.browse_to, 3)
      K.keys("lctrl", "insert")
      assert.is_true(browsed)
      assert.same(1, K.target())
      assert.same("x = 1\nz = 3", K.draft())
      assert.same(FILE, K.file())
    end)
  end)

  describe("IS6.1 at the cursor", function()
    spec_it("IS6.1 Copy a block: inside a line, a line break "
        .. "goes before and after, and Ctrl+Z takes it back",
        function()
      open_file()
      K.browse_to_end()
      K.type("ab")
      K.keys("left")
      K.keys("lctrl", "up")
      K.keys("lctrl", "insert")
      local copied = {
        K.draft(),
        K.cursor()
      }
      K.keys("lctrl", "z")
      assert.same({
        "a\nz = 3\nb",
        2,
        6
      }, copied)
      assert.same("ab", K.draft())
      assert.same({
        1,
        2
      }, { K.cursor() })
      assert.same(FILE, K.file())
    end)
  end)

  describe("IS6.1 with no block to copy", function()
    spec_it("IS6.1 Copy a block: on an empty line, nothing is "
        .. "copied and a notice says so", function()
      open_file("x = 1\n\ny = 2\n")
      K.browse_to(2)
      K.keys("lctrl", "insert")
      assert.same("", K.draft())
      assert.same("browsing", K.state())
      assert.same(2, K.position())
      assert.same("x = 1\n\ny = 2\n", K.file())
      assert.is_not_nil(K.message())
    end)

    spec_it("IS6.1 Copy a block: at the end position, nothing "
        .. "is copied and a notice says so", function()
      open_file()
      K.browse_to_end()
      K.keys("lctrl", "insert")
      assert.same("", K.draft())
      assert.same("browsing", K.state())
      assert.same("end", K.position())
      assert.same(FILE, K.file())
      assert.is_not_nil(K.message())
    end)

    spec_it("IS6.1 Copy a block: with no block to copy, a draft "
        .. "and its cursor stay as they are", function()
      open_file()
      K.browse_to_end()
      K.type("ab")
      K.keys("left")
      K.keys("lctrl", "insert")
      assert.same("ab", K.draft())
      assert.same({
        1,
        2
      }, { K.cursor() })
      assert.same(FILE, K.file())
      assert.is_not_nil(K.message())
    end)
  end)

  describe("IS6.2 and IS6.3", function()
    spec_it("IS6.2 Cut a block: the block leaves, its text in "
        .. "the field, the position on the next", function()
      open_file()
      K.browse_to(2)
      K.keys("lctrl", "delete")
      assert.same("x = 1\nz = 3\n", K.file())
      assert.same("inserting", K.state())
      assert.same("y = 2", K.draft())
      assert.same({
        1,
        6
      }, { K.cursor() })
      assert.same(2, K.position())
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

    spec_it("IS6.2 Cut a block: cutting the only block leaves "
        .. "an empty file, at its end", function()
      open_file("x = 1\n")
      K.browse_to(1)
      K.keys("lctrl", "delete")
      assert.same("", K.file())
      assert.same("end", K.position())
      assert.same(0, K.blocks())
    end)

    spec_it(
        "IS6.2 Cut a block: refused in a replacement, with " ..
        "a notice", function()
      open_file()
      K.browse_to(2)
      K.keys("f2")
      K.keys("lctrl", "delete")
      assert.same("replacing", K.state())
      assert.same("y = 2", K.draft())
      assert.same(FILE, K.file())
      assert.is_not_nil(K.message())
    end)

    spec_it("IS6.2 Cut a block: refused during an insertion "
        .. "of spaces alone, the draft kept", function()
      open_file()
      K.browse_to(2)
      K.type("   ")
      K.keys("lctrl", "delete")
      local ctrl = {
        K.file(),
        K.draft(),
        K.message() ~= nil
      }
      --- Shift+Delete cuts while browsing only; here it is
      --- the field's Delete, at the draft's end
      K.keys("lshift", "delete")
      assert.same({
        FILE,
        "   ",
        true
      }, ctrl)
      assert.same(FILE, K.file())
      assert.same("   ", K.draft())
      assert.same("inserting", K.state())
    end)

    spec_it("IS6.2 Cut a block: refused during an insertion "
        .. "of empty lines alone, the draft kept", function()
      open_file()
      K.browse_to(2)
      K.keys("lshift", "return")
      K.keys("lctrl", "delete")
      assert.same(FILE, K.file())
      assert.same("\n", K.draft())
      assert.same("inserting", K.state())
      assert.is_not_nil(K.message())
    end)

    spec_it("IS6.2 Cut a block: a held key removes the empty "
        .. "lines, cuts the first block with text, and stops",
        function()
      open_file("x = 1\n\n\ny = 2\nz = 3\n")
      K.browse_to(2)
      K.hold("lctrl")
      K.hold("delete")
      for _ = 1, 5 do
        K.repeat_key("delete")
      end
      K.release("delete")
      K.release("lctrl")
      assert.same("x = 1\nz = 3\n", K.file())
      assert.same("y = 2", K.draft())
      assert.same(2, K.position())
      assert.is_nil(K.message())
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
      -- as an insertion before a block leaves it (IS4.1)
      assert.same(3, K.position())
    end)

    spec_it("IS6.3 Restore a cut block: only once the draft "
        .. "holds no change, however many it held", function()
      open_file()
      K.browse_to(2)
      K.keys("lctrl", "delete")
      for _ = 1, 20 do
        K.type("x")
        K.keys("backspace")
      end
      for _ = 1, 40 do
        K.keys("lctrl", "z")
      end
      local undone = {
        K.draft(),
        K.file()
      }
      K.keys("lctrl", "z")
      assert.same({
        "y = 2",
        "x = 1\nz = 3\n"
      }, undone)
      assert.same(FILE, K.file())
      assert.same("", K.draft())
    end)

    spec_it(
        "IS6.3 Restore a cut block: typing after the cut is "
        .. "taken back first", function()
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
      assert.same({
        "y = 2",
        "x = 1\nz = 3\n"
      }, first)
      assert.same(FILE, K.file())
    end)
  end)

  describe("IS6.4 and IS6.5", function()
    before_each(function()
      open_file()
    end)

    spec_it("IS6.4 Submit and retain the field: Shift+Ins " ..
        "submits and keeps the draft", function()
      K.browse_to_end()
      K.type("a = 1")
      K.keys("lshift", "insert")
      assert.same(FILE .. "a = 1\n", K.file())
      assert.same("a = 1", K.draft())
      assert.same("inserting", K.state())
      assert.same({
        1,
        6
      }, { K.cursor() })
    end)

    spec_it("IS6.4 Submit and retain the field: a draft of "
        .. "empty lines is kept, its cursor too", function()
      K.browse_to_end()
      K.keys("lshift", "return")
      K.keys("lshift", "return")
      K.keys("lshift", "insert")
      assert.same("\n\n", K.draft())
      assert.same({
        3,
        1
      }, { K.cursor() })
    end)

    spec_it("IS6.4 Submit and retain the field: the browsing "
        .. "position ends as after Enter, before a block",
        function()
      K.browse_to(2)
      K.type("a = 1")
      K.keys("lshift", "insert")
      assert.same("x = 1\na = 1\ny = 2\nz = 3\n", K.file())
      assert.same(3, K.position())
      assert.same("a = 1", K.draft())
      assert.is_nil(K.target())
    end)

    spec_it("IS6.4 Submit and retain the field: the browsing "
        .. "position ends as after Enter, at the end", function()
      K.browse_to_end()
      K.type("a = 1")
      K.keys("lshift", "insert")
      assert.same("end", K.position())
      K.keys("lshift", "insert")
      assert.same(FILE .. "a = 1\na = 1\n", K.file())
      assert.same("end", K.position())
    end)

    spec_it("IS6.4 Submit and retain the field: a replacement "
        .. "is completed, the position after the block",
        function()
      K.browse_to(2)
      K.keys("f2")
      K.type(" + 1")
      K.keys("lshift", "insert")
      assert.same("x = 1\ny = 2 + 1\nz = 3\n", K.file())
      assert.is_nil(K.target())
      assert.same("inserting", K.state())
      assert.same(3, K.position())
    end)

    spec_it("IS6.4 Submit and retain the field: the retained "
        .. "draft starts afresh, so Ctrl+Z takes the "
        .. "acceptance back, not its typing", function()
      K.browse_to_end()
      K.type("a = 1")
      K.keys("lshift", "insert")
      K.keys("lctrl", "z")
      local first = {
        K.file(),
        K.draft(),
        K.state()
      }
      K.keys("lctrl", "z")
      assert.same({
        FILE,
        "",
        "browsing"
      }, first)
      assert.same(FILE, K.file())
      assert.same("", K.draft())
    end)

    spec_it("IS6.4 Submit and retain the field: a change to "
        .. "the retained draft is undone first, back to the "
        .. "retained text", function()
      K.browse_to_end()
      K.type("a = 1")
      K.keys("lshift", "insert")
      K.type("0")
      K.keys("lctrl", "z")
      local first = {
        K.file(),
        K.draft()
      }
      K.keys("lctrl", "z")
      assert.same({
        FILE .. "a = 1\n",
        "a = 1"
      }, first)
      assert.same(FILE, K.file())
      assert.same("", K.draft())
    end)

    spec_it("IS6.5 Move a block: Alt+Up and Alt+Down move it, "
        .. "the highlight with it", function()
      K.browse_to(2)
      K.keys("lalt", "up")
      local up = {
        K.file(),
        K.position()
      }
      K.keys("lalt", "down")
      assert.same({
        "y = 2\nx = 1\nz = 3\n",
        1
      }, up)
      assert.same(FILE, K.file())
      assert.same(2, K.position())
    end)

    spec_it("IS6.5 Move a block: at the end position, refused "
        .. "with a notice", function()
      K.browse_to_end()
      K.keys("lalt", "up")
      local up = {
        K.file(),
        K.message()
      }
      K.keys("lalt", "down")
      assert.same(FILE, up[1])
      assert.is_not_nil(up[2])
      assert.same(FILE, K.file())
      assert.is_not_nil(K.message())
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

    spec_it(
        "IS6.5 Move a block: during an insertion, the draft "
        .. "and its cursor stay", function()
      K.browse_to_end()
      K.type("a = 1")
      local browsed = pcall(K.browse_to, 2)
      K.keys("lalt", "up")
      assert.is_true(browsed)
      assert.same("y = 2\nx = 1\nz = 3\n", K.file())
      assert.same("a = 1", K.draft())
      assert.same({
        1,
        6
      }, { K.cursor() })
    end)

    spec_it(
        "IS6.5 Move a block: refused in a replacement, with "
        .. "a notice", function()
      K.browse_to(2)
      K.keys("f2")
      K.keys("lalt", "up")
      assert.same("replacing", K.state())
      assert.same(FILE, K.file())
      assert.is_not_nil(K.message())
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

    spec_it(
        "IS6.6 Undo and redo: from a draft, Ctrl+Z reaches " ..
        "the file once the draft is undone", function()
      K.browse_to_end()
      K.type("a = 1")
      K.keys("return")
      K.type("b")
      K.keys("lctrl", "z")
      K.keys("lctrl", "z")
      assert.same(FILE, K.file())
      assert.same("", K.draft())
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

    spec_it("IS6.6 Undo and redo: undo and redo put the " ..
        "position where the action left it", function()
      K.browse_to_end()
      K.type("a = 1")
      K.keys("return")
      K.keys("lctrl", "z")
      -- where the removed block stood: the end
      local undone = K.position()
      K.keys("lctrl", "y")
      assert.same("end", undone)
      assert.same("end", K.position())
    end)

    spec_it("IS6.6 Undo and redo: a held Ctrl+Z stops at the "
        .. "cut, and one more press restores it", function()
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
      -- Ctrl stays down: one more press of Z alone
      K.hold("z")
      K.release("z")
      K.release("lctrl")
      assert.same({
        "y = 2",
        "x = 1\nz = 3\n"
      }, held)
      assert.same(FILE, K.file())
      assert.same("", K.draft())
    end)

    spec_it("IS6.6 Undo and redo: the timeline goes when the "
        .. "file is left", function()
      K.browse_to_end()
      K.type("a = 1")
      K.keys("return")
      K.keys("escape")
      local left = K.app_state()
      K.open()
      K.keys("lctrl", "z")
      assert.same("ready", left)
      assert.same(FILE .. "a = 1\n", K.file())
    end)

    spec_it("IS6.6 Undo and redo: undoing an accepted "
        .. "replacement does not reach into its edit", function()
      K.browse_to_end()
      K.type("a = 1")
      K.keys("return")
      K.browse_to(2)
      K.keys("f2")
      K.type(" + 1")
      K.keys("return")
      local replaced = K.file()
      K.keys("lctrl", "z")
      local first = {
        K.file(),
        K.state()
      }
      K.keys("lctrl", "z")
      assert.same("x = 1\ny = 2 + 1\nz = 3\na = 1\n", replaced)
      assert.same({
        FILE .. "a = 1\n",
        "browsing"
      }, first)
      assert.same(FILE, K.file())
      assert.same("browsing", K.state())
    end)

    spec_it("IS6.6 Undo and redo: latest first, a cut is "
        .. "undone before the typing that came before it",
        function()
      K.browse_to(2)
      K.type("q")
      K.keys("backspace")
      K.keys("lctrl", "delete")
      K.keys("lctrl", "z")
      local first = {
        K.file(),
        K.draft()
      }
      K.keys("lctrl", "z")
      assert.same({
        FILE,
        ""
      }, first)
      assert.same("q", K.draft())
      assert.same(FILE, K.file())
    end)

    spec_it("IS6.6 Undo and redo: a file changed from outside "
        .. "ends an abort's undo too", function()
      K.browse_to(3)
      K.keys("f2")
      K.type("y")
      K.keys("escape")
      K.write_outside("main.lua", "q = 9\n")
      K.keys("lctrl", "z")
      assert.same("browsing", K.state())
      assert.same("", K.draft())
      assert.is_nil(K.target())
      assert.same("q = 9\n", K.file())
    end)

    spec_it("IS6.6 Undo and redo: a file changed from outside "
        .. "ends the undo of typing made before", function()
      K.browse_to_end()
      K.type("old")
      K.write_outside("main.lua", "q = 9\n")
      K.keys("lctrl", "z")
      assert.same("old", K.draft())
      assert.same("q = 9\n", K.file())
    end)

    spec_it("IS6.6 Undo and redo: the first of two moves is "
        .. "redone with the field it left", function()
      K.browse_to(1)
      K.keys("lctrl", "delete")
      K.keys("lalt", "down")
      K.keys("lalt", "up")
      K.keys("lctrl", "z")
      K.keys("lctrl", "z")
      K.keys("lctrl", "y")
      assert.same("x = 1", K.draft())
      assert.same("z = 3\ny = 2\n", K.file())
    end)

    spec_it("IS6.6 Undo and redo: an unchanged replacement "
        .. "kept with Shift+Ins leaves older actions as they "
        .. "were", function()
      K.browse_to_end()
      K.type("abc")
      K.keys("escape")
      K.browse_to(1)
      K.keys("f2")
      K.keys("lshift", "insert")
      local kept = K.draft()
      K.keys("lctrl", "z")
      assert.same("x = 1", kept)
      assert.same("abc", K.draft())
      assert.same(FILE, K.file())
    end)

    spec_it("IS6.6 Undo and redo: an undone empty line leaves "
        .. "the position where it stood", function()
      open_file("x = 1\n\ny = 2\n")
      K.browse_to(2)
      K.keys("return")
      local added = K.file()
      K.keys("lctrl", "z")
      assert.same("x = 1\n\n\ny = 2\n", added)
      assert.same("x = 1\n\ny = 2\n", K.file())
      assert.same(2, K.position())
    end)

    spec_it("IS6.6 Undo and redo: an undone replacement that "
        .. "began with the old text leaves the position on "
        .. "the restored block", function()
      K.browse_to(2)
      K.keys("f2")
      K.type_lines({
        "",
        "w = 0"
      })
      K.keys("return")
      local replaced = K.file()
      K.keys("lctrl", "z")
      assert.same("x = 1\ny = 2\nw = 0\nz = 3\n", replaced)
      assert.same(FILE, K.file())
      assert.same(2, K.position())
    end)

    spec_it("IS6.6 Undo and redo: following a reference and "
        .. "stepping back keeps what could be redone", function()
      K.reset({
        ["main.lua"] = "require(\"other\")\nx = 1\n",
        ["other.lua"] = "y = 2\n"
      })
      K.open()
      K.browse_to_end()
      K.type("a = 1")
      K.keys("return")
      local accepted = K.file()
      K.keys("lctrl", "z")
      local undone = K.file()
      K.browse_to(1)
      K.keys("lctrl", "j")
      local followed = K.file_name()
      K.keys("escape")
      local back = K.file_name()
      K.keys("lctrl", "y")
      assert.same({
        "other.lua",
        "main.lua"
      }, {
        followed,
        back
      })
      assert.same("require(\"other\")\nx = 1\n", undone)
      assert.same(accepted, K.file())
      assert.same("require(\"other\")\nx = 1\na = 1\n", accepted)
    end)

    spec_it("IS6.6 Undo and redo: after a change from outside "
        .. "no later key writes over it", function()
      K.browse_to(3)
      K.keys("f2")
      K.type("y")
      K.keys("escape")
      K.write_outside("main.lua", "q = 9\n")
      K.keys("lctrl", "z")
      local undone = K.file()
      K.keys("return")
      local entered = K.file()
      K.keys("lctrl", "delete")
      local cut = K.file()
      K.browse_to(1)
      K.keys("lalt", "down")
      assert.same({
        "q = 9\n",
        "q = 9\n",
        "q = 9\n"
      }, {
        undone,
        entered,
        cut
      })
      assert.same("q = 9\n", K.file())
    end)

    spec_it("IS6.6 Undo and redo: redoing a cut leaves the "
        .. "editor as the cut did", function()
      K.browse_to(2)
      K.keys("lctrl", "delete")
      K.keys("lctrl", "z")
      K.keys("lctrl", "y")
      assert.same("x = 1\nz = 3\n", K.file())
      assert.same("inserting", K.state())
      assert.same("y = 2", K.draft())
      assert.same({
        1,
        6
      }, { K.cursor() })
      assert.same(2, K.position())
    end)

    spec_it("IS6.6 Undo and redo: a held Ctrl+Y repeats only "
        .. "through changes to the draft", function()
      K.browse_to(2)
      K.keys("lctrl", "delete")
      K.type("x")
      K.keys("lctrl", "z")
      K.keys("lctrl", "z")
      K.hold("lctrl")
      K.hold("y")
      local pressed = {
        K.draft(),
        K.file()
      }
      for _ = 1, 5 do
        K.repeat_key("y")
      end
      K.release("y")
      K.release("lctrl")
      assert.same({
        "y = 2",
        "x = 1\nz = 3\n"
      }, pressed)
      assert.same("y = 2x", K.draft())
    end)

    spec_it("IS6.6 Undo and redo: a new action drops what "
        .. "could be redone", function()
      K.browse_to_end()
      K.type("a = 1")
      K.keys("return")
      local accepted = K.file()
      K.keys("lctrl", "z")
      local undone = K.file()
      K.type("b")
      K.keys("lctrl", "y")
      assert.same({
        FILE .. "a = 1\n",
        FILE
      }, {
        accepted,
        undone
      })
      assert.same(FILE, K.file())
      assert.same("b", K.draft())
    end)

    spec_it("IS6.6 Undo and redo: a move during an insertion "
        .. "is undone once the draft is, and both redone",
        function()
      K.browse_to_end()
      K.type("a")
      K.browse_to(2)
      K.keys("lalt", "up")
      K.keys("lctrl", "z")
      local first = {
        K.draft(),
        K.file()
      }
      K.keys("lctrl", "z")
      local second = {
        K.state(),
        K.file()
      }
      K.keys("lctrl", "y")
      K.keys("lctrl", "y")
      assert.same({
        "",
        "y = 2\nx = 1\nz = 3\n"
      }, first)
      assert.same({
        "browsing",
        FILE
      }, second)
      assert.same("y = 2\nx = 1\nz = 3\n", K.file())
      assert.same("a", K.draft())
    end)

    spec_it("IS6.6 Undo and redo: a retained draft's acceptance "
        .. "is undone and redone as one action", function()
      K.browse_to(2)
      K.keys("f2")
      K.type(" + 1")
      K.keys("lshift", "insert")
      local kept = {
        K.file(),
        K.draft(),
        K.state()
      }
      K.keys("lctrl", "z")
      local undone = {
        K.file(),
        K.draft(),
        K.state()
      }
      K.keys("lctrl", "y")
      assert.same({
        "x = 1\ny = 2 + 1\nz = 3\n",
        "y = 2 + 1",
        "inserting"
      }, kept)
      assert.same({
        FILE,
        "",
        "browsing"
      }, undone)
      assert.same(kept, {
        K.file(),
        K.draft(),
        K.state()
      })
    end)

    spec_it("IS6.6 Undo and redo: a file changed from outside "
        .. "while open is left as it was", function()
      K.browse_to_end()
      K.type("a = 1")
      K.keys("return")
      K.write_outside("main.lua", "q = 9\n")
      K.keys("lctrl", "z")
      K.keys("lctrl", "y")
      assert.same("q = 9\n", K.file())
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

    spec_it(
        "FR1.8 Reuse a block in the draft: B copied into A " ..
        "is saved in A, and B stays", function()
      K.browse_to(1)
      K.keys("f2")
      local browsed = pcall(K.browse_to, 2)
      K.keys("lctrl", "insert")
      K.keys("return")
      assert.is_true(browsed)
      assert.same("a = 1\nb = 2\nb = 2\n", K.file())
    end)

    spec_it(
        "FR1.8 Reuse a block in the draft: B copied into A, "
        .. "then B cut, leaves A holding both", function()
      K.browse_to(1)
      K.keys("f2")
      local browsed = pcall(K.browse_to, 2)
      K.keys("lctrl", "insert")
      K.keys("return")
      local cut = pcall(K.browse_to, 3)
      K.keys("lctrl", "delete")
      K.keys("escape")
      assert.is_true(browsed and cut)
      assert.same("a = 1\nb = 2\n", K.file())
      assert.same("browsing", K.state())
    end)
  end)
end)
