-- Editor principles, ratified: cases a mutation run over the
-- editor's code found unguarded (a small break of the code
-- that no test noticed), each under the item whose words it
-- checks. Keys only, through tests/helpers/editor_keys.lua.
-- Edit is F2; cut is Ctrl+Delete; move is Alt+Up and Alt+Down;
-- submit and retain is Shift+Ins.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it, spec_gap = marks.spec_it, marks.spec_gap

local FILE = "x = 1\ny = 2\nz = 3\n"

local function open_file(text)
  K.reset({ ["main.lua"] = text or FILE })
  K.open()
end

--- What a failed action must leave alone.
local function held_state()
  return {
    draft = K.draft(),
    cursor = { K.cursor() },
    position = K.position(),
    target = K.target() or "none",
    file = K.file(),
    blocks = K.blocks()
  }
end

describe("mutation survivors #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  describe("the size limit, at the limit", function()
    spec_it("IS5.1 Begin a replacement: Edit loads a block " ..
        "of exactly 14 lines", function()
      open_file(K.block(14) .. "y = 2\n")
      K.browse_to(1)
      K.keys("f2")
      assert.same("replacing", K.state())
      assert.same(1, K.target())
      assert.same(
        table.concat(K.block_lines(14), "\n"),
        K.draft()
      )
    end)

    -- the maintainer's ruling of November 14, 2026 overrides
    -- IS1.3's refusal of Edit
    spec_it("IS1.3 Handle size limits: Edit opens a block of " ..
        "15 lines, and Enter refuses it with a notice naming " ..
        "the limit", function()
      local text = K.block(15) .. "y = 2\n"
      open_file(text)
      K.browse_to(1)
      K.keys("f2")
      assert.same("replacing", K.state())
      assert.same(1, K.target())
      K.keys("return")
      assert.same("replacing", K.state())
      assert.same(1, K.target())
      assert.same(table.concat(K.block_lines(15), "\n"), K.draft())
      assert.truthy((K.message() or ""):find("14", 1, true))
      assert.same(text, K.file())
    end)
  end)

  describe("a write that fails", function()
    before_each(function()
      open_file()
    end)

    spec_it("IS3.11 Preserve state on refusal: a cut whose " ..
        "write fails leaves the block and the empty field",
        function()
      K.browse_to(2)
      local before = held_state()
      K.fail_writes("the card is full")
      K.keys("lctrl", "delete")
      assert.same(before, held_state())
      assert.same("browsing", K.state())
      assert.is_not_nil(K.message())
    end)

    spec_it("IS3.11 Preserve state on refusal: a move whose "
        .. "write fails leaves the blocks in their order",
        function()
      K.browse_to(2)
      local before = held_state()
      local view = K.view_rows()
      K.fail_writes("the card is full")
      K.keys("lalt", "up")
      assert.same(before, held_state())
      assert.same(view, K.view_rows())
      assert.is_not_nil(K.message())
    end)

    spec_it("IS3.11 Preserve state on refusal: an undo whose "
        .. "write fails leaves the text as the file holds it",
        function()
      K.type("a = 1")
      K.keys("return")
      local before = held_state()
      local view = K.view_rows()
      K.fail_writes("the card is full")
      K.keys("lctrl", "z")
      assert.same(FILE .. "a = 1\n", before.file)
      assert.same(before, held_state())
      assert.same(view, K.view_rows())
    end)
  end)

  describe("the timeline", function()
    before_each(function()
      open_file()
    end)

    spec_it("IS6.6 Undo and redo: opening a replacement " ..
        "drops what could be redone", function()
      K.type("a = 1")
      K.keys("return")
      K.keys("lctrl", "z")
      K.browse_to(1)
      K.keys("f2")
      K.keys("lctrl", "y")
      assert.same(FILE, K.file())
      assert.same("replacing", K.state())
      assert.same(1, K.target())
      assert.same("x = 1", K.draft())
    end)

    spec_it("IS6.6 Undo and redo: an abort drops what " ..
        "could be redone", function()
      K.type("a = 1")
      K.keys("return")
      K.keys("lctrl", "z")
      K.browse_to(1)
      K.keys("f2")
      K.keys("escape")
      K.keys("lctrl", "y")
      assert.same(FILE, K.file())
      assert.same("browsing", K.state())
      assert.same("", K.draft())
    end)

    spec_it("IS6.6 Undo and redo: undoing a replacement " ..
        "accepted after a switch does not reach the switch",
        function()
      K.browse_to(1)
      K.keys("f2")
      K.keys("lctrl", "down")
      K.keys("lctrl", "down")
      K.keys("f2")
      K.type("0")
      K.keys("return")
      local accepted = K.file()
      K.keys("lctrl", "z")
      local undone = K.file()
      K.keys("lctrl", "z")
      assert.same("x = 1\ny = 2\nz = 30\n", accepted)
      assert.same(FILE, undone)
      assert.same(FILE, K.file())
      assert.same("browsing", K.state())
      assert.is_nil(K.target())
      assert.same("", K.draft())
    end)

    spec_it("IS6.6 Undo and redo: redoing a Shift+Ins " ..
        "submission brings back the draft it kept", function()
      K.type("a = 1")
      K.keys("lshift", "insert")
      K.keys("lctrl", "z")
      local undone = {
        K.file(),
        K.draft()
      }
      K.keys("lctrl", "y")
      assert.same({
        FILE,
        ""
      }, undone)
      assert.same(FILE .. "a = 1\n", K.file())
      assert.same("a = 1", K.draft())
      assert.same("inserting", K.state())
    end)
  end)

  describe("leaving and joining", function()
    spec_it("IS1.5 Follow a file reference: with a target " ..
        "and the draft cleared, Ctrl+J is still refused",
        function()
      K.reset({
        ["main.lua"] = "local m = require(\"mod\")\nx = 1\n",
        ["mod.lua"] = "y = 2\n"
      })
      K.open()
      K.browse_to(1)
      K.keys("f2")
      K.keys("lctrl", "home")
      K.keys("lctrl", "k")
      local cleared = K.draft()
      K.keys("lctrl", "j")
      assert.same("", cleared)
      assert.same("main.lua", K.file_name())
      assert.same(1, K.target())
      assert.is_not_nil(K.message())
    end)

    spec_it("FR3.1 Preserve file structure: a draft that " ..
        "would join the block before it does not merge them",
        function()
      -- "x = y" and "(f or g)(1)" read together as one call
      open_file("x = y\n")
      K.type("(f or g)(1)")
      K.keys("return")
      local kept = K.file() == "x = y\n"
      local apart = K.blocks() == 2
      assert.is_true(kept or apart)
      assert.same("x = y", K.file():match("^[^\n]*"))
    end)
  end)

  describe("the timeline, with no draft change between",
      function()
    before_each(function()
      open_file()
    end)

    spec_it("IS6.6 Undo and redo: a move after an undo " ..
        "drops what could be redone", function()
      K.type("a = 1")
      K.keys("return")
      K.keys("lctrl", "z")
      K.browse_to(2)
      K.keys("lalt", "up")
      local moved = K.file()
      K.keys("lctrl", "y")
      assert.same("y = 2\nx = 1\nz = 3\n", moved)
      assert.same(moved, K.file())
    end)

    spec_it("IS6.6 Undo and redo: an empty-line insertion " ..
        "after an undo drops what could be redone", function()
      K.type("a = 1")
      K.keys("return")
      K.keys("lctrl", "z")
      K.browse_to(2)
      K.keys("return")
      local inserted = K.file()
      K.keys("lctrl", "y")
      assert.same("x = 1\n\ny = 2\nz = 3\n", inserted)
      assert.same(inserted, K.file())
    end)
  end)

  describe("the gate and the field's keys", function()
    before_each(function()
      open_file()
    end)

    spec_it("IS3.3 Check Lua submission: a line of 65 " ..
        "characters is refused with a notice naming the limit",
        function()
      -- no formatting shortens a name of 65 characters
      local name = string.rep("x", 65)
      K.type(name .. " = 1")
      K.keys("return")
      assert.same(FILE, K.file())
      assert.same("inserting", K.state())
      assert.truthy(K.draft():find(name, 1, true))
      assert.truthy((K.message() or ""):find("64", 1, true))
    end)

    spec_it("IS3.4 Locate a syntax failure: a draft that " ..
        "fails at its first character gets the cursor there",
        function()
      K.type("'s'")
      K.keys("return")
      assert.same("'s'", K.draft())
      assert.same({
        1,
        1
      }, { K.cursor() })
      assert.same(FILE, K.file())
    end)

    spec_it("IS3.5 Continue input on a new line: a draft " ..
        "unfinished before a closing comment goes on too",
        function()
      K.type("if x then -- why")
      K.keys("return")
      assert.same("if x then -- why\n", K.draft())
      assert.same({
        2,
        1
      }, { K.cursor() })
      assert.same(FILE, K.file())
    end)

    spec_it("IS3.12 Keep deletion keys in the draft: Ctrl+K "
        .. "before the last character removes it", function()
      K.type("abc")
      K.keys("left")
      K.keys("lctrl", "k")
      assert.same("ab", K.draft())
      assert.same({
        1,
        3
      }, { K.cursor() })
      assert.same(FILE, K.file())
    end)
  end)

  describe("an outside change, and comments in a draft",
      function()
    before_each(function()
      open_file()
    end)

    spec_it("IS6.6 Undo and redo: after a change from " ..
        "outside, the old actions stay gone", function()
      K.type("a = 1")
      K.keys("return")
      local accepted = K.file()
      K.write_outside("main.lua", "q = 9\n")
      K.keys("lctrl", "z")
      -- the text comes back as the action left it: the action
      -- went with the change, and stays gone
      K.write_outside("main.lua", accepted)
      K.keys("lctrl", "z")
      assert.same(FILE .. "a = 1\n", accepted)
      assert.same(accepted, K.file())
      assert.same(4, K.blocks())
    end)

    spec_it("IS3.4 Locate a syntax failure: past a comment " ..
        "that ends a line, the cursor goes to the failure",
        function()
      K.type_lines({
        "w = 1 + -- note",
        "= 2"
      })
      K.keys("return")
      assert.same("w = 1 + -- note\n= 2", K.draft())
      assert.same({
        2,
        1
      }, { K.cursor() })
      assert.same(FILE, K.file())
    end)

    spec_it("IS3.4 Locate a syntax failure: past comment " ..
        "lines, the cursor goes to the failure", function()
      K.type_lines({
        "w = -- why",
        "-- more",
        "= 3"
      })
      K.keys("return")
      assert.same({
        3,
        1
      }, { K.cursor() })
      assert.same(FILE, K.file())
    end)

    spec_it("IS3.4 Locate a syntax failure: after a comment "
        .. "that opens the draft, the cursor is at the failure"
        , function()
      K.type("--[[ c ]] = 1")
      K.keys("return")
      assert.same("--[[ c ]] = 1", K.draft())
      assert.same({
        1,
        11
      }, { K.cursor() })
      assert.same(FILE, K.file())
    end)

    spec_it("IS3.4 Locate a syntax failure: after a comment "
        .. "inside a line, the cursor is at the failure",
        function()
      K.type("w = 1 --[[ c ]] = 2")
      K.keys("return")
      assert.same({
        1,
        17
      }, { K.cursor() })
      assert.same(FILE, K.file())
    end)

    spec_it("IS3.4 Locate a syntax failure: a failure on " ..
        "the line after a comment is located, not continued",
        function()
      K.type_lines({
        "w = 1 -- c",
        "2"
      })
      K.keys("return")
      assert.same("w = 1 -- c\n2", K.draft())
      assert.same({
        2,
        1
      }, { K.cursor() })
      assert.same(FILE, K.file())
    end)

    spec_it("IS3.4 Locate a syntax failure: a failure right "
        .. "after a comment in the line is located there",
        function()
      K.type("w = 1 --[[ c ]] 2")
      K.keys("return")
      assert.same("w = 1 --[[ c ]] 2", K.draft())
      assert.same({
        1,
        17
      }, { K.cursor() })
      assert.same(FILE, K.file())
    end)

    spec_it("IS3.5 Continue input on a new line: a draft " ..
        "unfinished before a comment line goes on too",
        function()
      K.type_lines({
        "if w then",
        "-- why"
      })
      K.keys("return")
      assert.same("if w then\n-- why\n", K.draft())
      assert.same({
        3,
        1
      }, { K.cursor() })
      assert.same(FILE, K.file())
    end)
  end)
end)
