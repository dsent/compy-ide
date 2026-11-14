-- IS6 Reusing, removing, and reordering blocks (editor
-- principles, ratified): the clauses the tests of
-- is6_reuse_spec.lua leave out. Keys only, through
-- tests/helpers/editor_keys.lua. Edit is F2; copy is
-- Ctrl+Ins; cut is Ctrl+Delete; move is Alt+Up and Alt+Down.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it, spec_gap = marks.spec_it, marks.spec_gap
local spec_deviation = marks.spec_deviation

local FILE = "x = 1\ny = 2\nz = 3\n"
local GAPPED = "x = 1\n\ny = 2\n"
local CUT = "x = 1\nz = 3\n"

local function open_file(text)
  K.reset({ ["main.lua"] = text or FILE })
  K.open()
end

--- Hold Ctrl and `k`, with `n` repeats of `k`, then let both
--- go.
local function hold_ctrl(k, n)
  K.hold("lctrl")
  K.hold(k)
  for _ = 1, n do
    K.repeat_key(k)
  end
  K.release(k)
  K.release("lctrl")
end

describe("IS6 reuse, added #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  describe("IS6.1", function()
    spec_it("IS6.1 Copy a block: on an empty line, refused " ..
        "with a notice", function()
      open_file(GAPPED)
      K.browse_to(2)
      K.keys("lctrl", "insert")
      assert.same("browsing", K.state())
      assert.same("", K.draft())
      assert.same(2, K.position())
      assert.is_not_nil(K.message())
      assert.same(GAPPED, K.file())
    end)

    spec_it("IS6.1 Copy a block: at the end position, refused "
        .. "with a notice, the draft kept", function()
      open_file()
      K.browse_to_end()
      K.type("a = 1")
      K.keys("lctrl", "insert")
      assert.same("a = 1", K.draft())
      assert.same({
        1,
        6
      }, { K.cursor() })
      assert.same("end", K.position())
      assert.is_not_nil(K.message())
      assert.same(FILE, K.file())
    end)

    spec_it("IS6.1 Copy a block: inside a line, a line break "
        .. "goes before the block and after it", function()
      open_file()
      K.browse_to_end()
      K.type("a = 1")
      K.keys("home")
      K.keys("right")
      local browsed = pcall(K.browse_to, 1)
      K.keys("lctrl", "insert")
      assert.is_true(browsed)
      assert.same("a\nx = 1\n = 1", K.draft())
      assert.same({
        2,
        6
      }, { K.cursor() })
      assert.same(FILE, K.file())
    end)

    spec_it(
        "IS6.1 Copy a block: into a replacement, the cursor "
        .. "ends after the copied text", function()
      open_file()
      K.browse_to(1)
      K.keys("f2")
      local browsed = pcall(K.browse_to, 3)
      K.keys("lctrl", "insert")
      assert.is_true(browsed)
      assert.same("x = 1\nz = 3", K.draft())
      assert.same({
        2,
        6
      }, { K.cursor() })
      assert.same("replacing", K.state())
      --- copying leaves an existing replacement target in place
      assert.same(1, K.target())
    end)
  end)

  describe("IS6.2 and IS6.3", function()
    spec_it("IS6.2 Cut a block: refused during an insertion, "
        .. "with a notice", function()
      open_file()
      K.browse_to(2)
      K.type("a = 1")
      K.keys("lctrl", "delete")
      assert.same("inserting", K.state())
      assert.same("a = 1", K.draft())
      assert.same(2, K.position())
      assert.is_not_nil(K.message())
      assert.same(FILE, K.file())
    end)

    spec_it("IS6.2 Cut a block: at the end position, refused "
        .. "with a notice", function()
      open_file()
      K.browse_to_end()
      K.keys("lctrl", "delete")
      assert.same("browsing", K.state())
      assert.same("", K.draft())
      assert.same("end", K.position())
      assert.is_not_nil(K.message())
      assert.same(FILE, K.file())
    end)

    -- the spec's note has a held Ctrl+Delete cut on through
    -- the empty lines; a key that writes acts once per press
    spec_deviation("IS6.2 Cut a block: held, it cuts one block, "
        .. "however many repeats follow",
        "rulings.md: Which keys repeat while held",
        function()
          open_file("x = 1\n\n\ny = 2\nz = 3\n")
          K.browse_to(2)
          assert.same(5, K.blocks())
          hold_ctrl("delete", 6)
          assert.same("x = 1\n\ny = 2\nz = 3\n", K.file())
          assert.same("", K.draft())
          assert.same("browsing", K.state())
          assert.same(2, K.position())
        end)

    spec_it("IS6.3 Restore a cut block: the position stays on "
        .. "the block after the restored one", function()
      open_file()
      K.browse_to(2)
      K.keys("lctrl", "delete")
      K.keys("lctrl", "z")
      assert.same(FILE, K.file())
      assert.same("browsing", K.state())
      assert.same(3, K.position())
    end)

    spec_it("IS6.3 Restore a cut block: Enter right after the "
        .. "cut puts the block back in its place", function()
      open_file()
      K.browse_to(2)
      K.keys("lctrl", "delete")
      local cut = K.file()
      K.keys("return")
      assert.same(CUT, cut)
      assert.same(FILE, K.file())
      assert.same("browsing", K.state())
      assert.same(3, K.position())
    end)
  end)

  describe("IS6.5", function()
    before_each(function()
      open_file()
    end)

    spec_it("IS6.5 Move a block: during an insertion, the " ..
        "position follows the moved block", function()
      K.browse_to_end()
      K.type("a = 1")
      local browsed = pcall(K.browse_to, 2)
      K.keys("lalt", "down")
      assert.is_true(browsed)
      assert.same("x = 1\nz = 3\ny = 2\n", K.file())
      assert.same(3, K.position())
      assert.same("a = 1", K.draft())
    end)

    spec_it("IS6.5 Move a block: toward the edge, the last " ..
        "block stays", function()
      K.browse_to(3)
      K.keys("lalt", "down")
      assert.same(FILE, K.file())
      assert.same(3, K.position())
    end)

    spec_it("IS6.5 Move a block: Ctrl+Z reverts the move",
        function()
      K.browse_to(2)
      K.keys("lalt", "up")
      local moved = K.file()
      K.keys("lctrl", "z")
      assert.same("y = 2\nx = 1\nz = 3\n", moved)
      assert.same(FILE, K.file())
      assert.same("browsing", K.state())
    end)

  end)

  describe("IS6.6", function()
    before_each(function()
      open_file()
    end)

    spec_it("IS6.6 Undo and redo: Ctrl+Z takes a copy back as "
        .. "one change to the draft", function()
      K.browse_to_end()
      K.type("a = 1")
      local browsed = pcall(K.browse_to, 1)
      K.keys("lctrl", "insert")
      local copied = K.draft()
      K.keys("lctrl", "z")
      assert.is_true(browsed)
      assert.same("a = 1\nx = 1", copied)
      assert.same("a = 1", K.draft())
      assert.same("inserting", K.state())
      assert.same(FILE, K.file())
    end)

    spec_it("IS6.6 Undo and redo: undoing the opening of a " ..
        "replacement leaves the edit as Escape does", function()
      K.browse_to(2)
      K.keys("f2")
      K.keys("lctrl", "z")
      assert.same("browsing", K.state())
      assert.is_nil(K.target())
      assert.same("", K.draft())
      assert.same(2, K.position())
      assert.same("editor", K.app_state())
      assert.same(FILE, K.file())
    end)

    spec_it("IS6.6 Undo and redo: the opening of a replacement "
        .. "is reached once the draft is undone", function()
      K.browse_to(2)
      K.keys("f2")
      K.type("0")
      K.keys("lctrl", "z")
      local first = {
        K.state(),
        K.draft(),
        K.target()
      }
      K.keys("lctrl", "z")
      assert.same({
        "replacing",
        "y = 2",
        2
      }, first)
      assert.same("browsing", K.state())
      assert.is_nil(K.target())
      assert.same("", K.draft())
    end)

    spec_it("IS6.6 Undo and redo: undoing an abort brings a "
        .. "replacement back, draft, cursor and target",
        function()
      K.browse_to(2)
      K.keys("f2")
      K.type("0")
      K.keys("home")
      K.keys("escape")
      local aborted = K.state()
      K.keys("lctrl", "z")
      assert.same("browsing", aborted)
      assert.same("replacing", K.state())
      assert.same(2, K.target())
      assert.same("y = 20", K.draft())
      assert.same({
        1,
        1
      }, { K.cursor() })
      assert.same(FILE, K.file())
    end)

    spec_it("IS6.6 Undo and redo: Ctrl+Y redoes an abort",
        function()
      K.browse_to(2)
      K.keys("f2")
      K.type("0")
      K.keys("escape")
      K.keys("lctrl", "z")
      local back = K.state()
      K.keys("lctrl", "y")
      assert.same("replacing", back)
      assert.same("browsing", K.state())
      assert.is_nil(K.target())
      assert.same("", K.draft())
      assert.same(FILE, K.file())
    end)

    spec_it("IS6.6 Undo and redo: Ctrl+Y redoes a cut",
        function()
      K.browse_to(2)
      K.keys("lctrl", "delete")
      K.keys("lctrl", "z")
      local restored = K.file()
      K.keys("lctrl", "y")
      assert.same(FILE, restored)
      assert.same(CUT, K.file())
      assert.same("inserting", K.state())
      assert.same("y = 2", K.draft())
      assert.same(2, K.position())
    end)

    spec_it("IS6.6 Undo and redo: Ctrl+Y redoes a move",
        function()
      K.browse_to(2)
      K.keys("lalt", "up")
      K.keys("lctrl", "z")
      local reverted = K.file()
      K.keys("lctrl", "y")
      assert.same(FILE, reverted)
      assert.same("y = 2\nx = 1\nz = 3\n", K.file())
      assert.same(1, K.position())
      assert.same("browsing", K.state())
    end)

    spec_it("IS6.6 Undo and redo: a submission of two blocks "
        .. "is undone in one step and redone in one", function()
      K.browse_to(2)
      K.type("a = 1; b = 2")
      K.keys("return")
      local accepted = K.file()
      K.keys("lctrl", "z")
      local undone = K.file()
      K.keys("lctrl", "y")
      assert.same(
        "x = 1\na = 1\nb = 2\ny = 2\nz = 3\n",
        accepted
      )
      assert.same(FILE, undone)
      assert.same(accepted, K.file())
    end)

    spec_it("IS6.6 Undo and redo: a new action drops what " ..
        "could be redone", function()
      K.browse_to_end()
      K.type("a = 1")
      K.keys("return")
      K.keys("lctrl", "z")
      K.type("b")
      K.keys("lctrl", "y")
      assert.same(FILE, K.file())
      assert.same("b", K.draft())
    end)

    spec_it("IS6.6 Undo and redo: undoing an insertion leaves "
        .. "the position where its blocks stood", function()
      K.browse_to(2)
      K.type("a = 1; b = 2")
      K.keys("return")
      K.keys("lctrl", "z")
      assert.same(FILE, K.file())
      assert.same("browsing", K.state())
      assert.same("", K.draft())
      assert.same(2, K.position())
    end)

    spec_it("IS6.6 Undo and redo: undoing an append leaves " ..
        "the position at the end", function()
      K.browse_to_end()
      K.type("a = 1")
      K.keys("return")
      K.keys("lctrl", "z")
      assert.same(FILE, K.file())
      assert.same("browsing", K.state())
      assert.same("end", K.position())
    end)

    spec_it("IS6.6 Undo and redo: undoing an empty-line " ..
        "insertion takes the line out again", function()
      K.browse_to(2)
      K.keys("return")
      local inserted = K.file()
      K.keys("lctrl", "z")
      assert.same("x = 1\n\ny = 2\nz = 3\n", inserted)
      assert.same(FILE, K.file())
      assert.same("browsing", K.state())
      assert.same(2, K.position())
    end)

    spec_it("IS6.6 Undo and redo: undoing a replacement puts "
        .. "the position on the restored block", function()
      K.browse_to(1)
      K.keys("f2")
      K.type("0; w = 4")
      K.keys("return")
      local accepted = K.file()
      K.keys("lctrl", "z")
      assert.same("x = 10\nw = 4\ny = 2\nz = 3\n", accepted)
      assert.same(FILE, K.file())
      assert.same("browsing", K.state())
      assert.same("", K.draft())
      assert.is_nil(K.target())
      assert.same(1, K.position())
    end)

    spec_it("IS6.6 Undo and redo: a held Ctrl+Y stops after "
        .. "the draft, and one more press redoes the abort",
        function()
      K.browse_to_end()
      K.type("a")
      K.keys("escape")
      K.keys("lctrl", "z")
      local back = K.draft()
      K.keys("lctrl", "z")
      local undone = K.draft()
      hold_ctrl("y", 5)
      local held = K.draft()
      K.keys("lctrl", "y")
      assert.same("a", back)
      assert.same("", undone)
      assert.same("a", held)
      assert.same("", K.draft())
      assert.same("browsing", K.state())
      assert.same(FILE, K.file())
    end)
  end)

  describe("IS6.4, and the position through undo", function()
    before_each(function()
      open_file()
    end)

    spec_it("IS6.4 Submit and retain the field: an append " ..
        "leaves the position at the end", function()
      K.browse_to_end()
      K.type("a = 1")
      K.keys("lshift", "insert")
      assert.same(FILE .. "a = 1\n", K.file())
      assert.same("a = 1", K.draft())
      assert.same("inserting", K.state())
      assert.same("end", K.position())
    end)

    spec_it("IS6.4 Submit and retain the field: a replacement "
        .. "is completed, the draft kept for an insertion",
        function()
      K.browse_to(2)
      K.keys("f2")
      K.type("0")
      K.keys("lshift", "insert")
      assert.same("x = 1\ny = 20\nz = 3\n", K.file())
      assert.is_nil(K.target())
      assert.same("inserting", K.state())
      assert.same("y = 20", K.draft())
      assert.same({
        1,
        7
      }, { K.cursor() })
      assert.same(3, K.position())
    end)

    spec_it("IS6.4 Submit and retain the field: a draft with "
        .. "a syntax failure is rejected as Enter rejects it",
        function()
      K.browse_to_end()
      K.type("a = = 1")
      K.keys("lshift", "insert")
      assert.same(FILE, K.file())
      assert.same("a = = 1", K.draft())
      assert.same("inserting", K.state())
      assert.same({
        1,
        5
      }, { K.cursor() })
    end)

    spec_it("IS6.6 Undo and redo: after Shift+Ins, Ctrl+Z " ..
        "undoes the acceptance at once", function()
      K.browse_to_end()
      K.type("a = 1")
      K.keys("lshift", "insert")
      local accepted = K.file()
      K.keys("lctrl", "z")
      assert.same(FILE .. "a = 1\n", accepted)
      assert.same(FILE, K.file())
      assert.same("browsing", K.state())
      assert.same("", K.draft())
    end)

    spec_it("IS6.6 Undo and redo: the position follows an " ..
        "insertion through undo and redo", function()
      K.browse_to(2)
      K.type("a = 1")
      K.keys("return")
      local accepted = K.position()
      K.keys("lctrl", "z")
      local undone = K.position()
      K.keys("lctrl", "y")
      assert.same(3, accepted)
      assert.same(2, undone)
      assert.same(3, K.position())
      assert.same("x = 1\na = 1\ny = 2\nz = 3\n", K.file())
    end)

  end)
end)
