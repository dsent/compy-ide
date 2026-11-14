-- Luditor parity: the reference editor's own editor-behavior tests
-- (desktopeditor, tests/editor_spec_tests.rs), ported key sequence by
-- key sequence and driven through tests/helpers/editor_keys.lua. Each
-- test name opens with the Luditor test's name. A case the IDE fails
-- is left pending with its reason; the classification is in the
-- task's luditor-parity notes.

local K = require("tests.helpers.editor_keys")

describe("Luditor parity #editor", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  describe("an_unmodified_draft_holds_no_change_that_ctrl_z_would_take_back", function()
    local function z()
      K.keys("lctrl", "z")
    end
    pending("an_unmodified_draft_holds_no_change_that_ctrl_z_would_take_back / reload, switch and opening undo in turn: spec silent: after a reload the IDE switches the target to B where Luditor refuses with a notice", function()
      K.reset({ ["main.lua"] = "a = 1\nb = 2\n" })
      K.open()
      K.keys("lctrl", "up")
      K.keys("lctrl", "up")
      assert.same(1, K.position())
      K.keys("f2")
      K.type("0")
      K.keys("f2") -- the reload is a change
      assert.same("a = 1", K.draft())
      K.keys("lctrl", "down") -- onto B
      K.keys("f2")
      assert.truthy((K.message() or ""):find("Already editing", 1, true))
      z() -- the reload
      assert.same("a = 10", K.draft())
      z() -- the typing: nothing left to undo
      K.keys("f2") -- now a switch
      assert.same(2, K.target())
      K.keys("home")
      K.keys("f2")
      assert.same({ 1, 6 }, { K.cursor() })
      z() -- the switch
      assert.same(1, K.target())
      z() -- the opening of the replacement
      assert.same("browsing", K.state())
    end)
  end)

  describe("fr2_8_an_accepted_change_and_an_abort_are_taken_back_and_redone", function()
    local function z()
      K.keys("lctrl", "z")
    end
    local function y()
      K.keys("lctrl", "y")
    end
    it("fr2_8_an_accepted_change_and_an_abort_are_taken_back_and_redone / accepted change, insertion, abort, held undo", function()
      K.reset({ ["main.lua"] = "a = 1\nb = 2\nc = 3\n" })
      K.open()
      K.keys("lctrl", "up")
      K.keys("lctrl", "up")
      K.keys("f2")
      K.type(" + 1")
      K.keys("return")
      assert.same("a = 1\nb = 2 + 1\nc = 3\n", K.file())
      z()
      assert.same("a = 1\nb = 2\nc = 3\n", K.file())
      assert.same("", K.draft())
      assert.same("browsing", K.state())
      assert.same(2, K.position())
      y()
      assert.same(3, K.position())
      assert.same("a = 1\nb = 2 + 1\nc = 3\n", K.file())
      K.type("x = 1")
      K.keys("return")
      assert.same(4, K.blocks())
      z()
      assert.same(3, K.blocks())
      assert.same(3, K.position())
      assert.same("a = 1\nb = 2 + 1\nc = 3\n", K.file())
      K.keys("f2")
      K.type("y")
      K.keys("escape")
      assert.same("browsing", K.state())
      z()
      assert.same("c = 3y", K.draft())
      assert.same(3, K.target())
      -- a held Ctrl+Z: `y` goes and the hold stops there
      K.hold("lctrl")
      K.hold("z")
      K.repeat_key("z")
      K.repeat_key("z")
      K.release("z")
      K.release("lctrl")
      assert.same("c = 3", K.draft())
      assert.same("replacing", K.state())
      z() -- the opening: a press of its own
      assert.same("browsing", K.state())
      -- a fresh editor on the file has nothing to undo
      K.restart()
      K.open()
      z()
      assert.same(3, K.blocks())
      assert.same("a = 1\nb = 2 + 1\nc = 3\n", K.file())
    end)
  end)

  describe("opening_a_replacement_or_cutting_keeps_the_earlier_draft_history", function()
    local function z()
      K.keys("lctrl", "z")
    end
    it("opening_a_replacement_or_cutting_keeps_the_earlier_draft_history / across an opening and a cut", function()
      K.reset({ ["main.lua"] = "b = 2\nc = 3\n" })
      K.open()
      K.type("a")
      K.keys("backspace")
      K.keys("up")
      K.keys("f2")
      z()
      assert.same("browsing", K.state())
      z()
      assert.same("a", K.draft())
      assert.same("inserting", K.state())
      K.keys("backspace")
      K.keys("lctrl", "delete")
      z()
      assert.same(2, K.blocks())
      assert.same("", K.draft())
      z()
      assert.same("a", K.draft())
    end)
  end)

  describe("redoing_a_move_brings_back_the_field_the_move_left", function()
    it("redoing_a_move_brings_back_the_field_the_move_left / redo restores the cut draft", function()
      K.reset({ ["main.lua"] = "a = 1\nb = 2\nc = 3\n" })
      K.open()
      K.keys("pageup")
      K.keys("lctrl", "delete") -- `a = 1` into the field
      K.keys("lalt", "down") -- `b` below `c`
      assert.same("c = 3\nb = 2\n", K.file())
      K.keys("lctrl", "z")
      assert.same("b = 2\nc = 3\n", K.file())
      assert.same("", K.draft())
      K.keys("lctrl", "y")
      assert.same("c = 3\nb = 2\n", K.file())
      assert.same("a = 1", K.draft())
      assert.same("inserting", K.state())
    end)
  end)

  describe("a_moves_redo_never_revives_or_replays_undone_typing", function()
    local function z()
      K.keys("lctrl", "z")
    end
    local function y()
      K.keys("lctrl", "y")
    end
    pending("a_moves_redo_never_revives_or_replays_undone_typing / typing then a move, undone and redone twice: spec silent: the first Ctrl+Y redoes the move with `abc` back in the field, Luditor leaves it empty", function()
      K.reset({ ["main.lua"] = "a = 1\nb = 2\n" })
      K.open()
      K.keys("up") -- onto `b = 2`
      K.type("abc")
      K.keys("lalt", "up")
      for _ = 1, 2 do
        for _ = 1, 4 do
          z()
        end
        assert.same({ "a = 1\nb = 2\n", "" }, { K.file(), K.draft() })
        for _, want in ipairs({ "", "a", "ab", "abc" }) do
          y()
          assert.same({ "b = 2\na = 1\n", want }, { K.file(), K.draft() })
        end
      end
      K.keys("escape")
    end)
    it("a_moves_redo_never_revives_or_replays_undone_typing / cut, typing, move: redo gives the cut text, the typing still to redo", function()
      K.reset({ ["main.lua"] = "a = 1\nb = 2\nc = 3\n" })
      K.open()
      K.keys("pageup")
      K.keys("lctrl", "delete")
      K.type("x")
      K.keys("lalt", "down")
      z()
      z()
      assert.same("b = 2\nc = 3\n", K.file())
      y()
      assert.same("c = 3\nb = 2\n", K.file())
      assert.same("a = 1", K.draft())
      z()
      assert.same("b = 2\nc = 3\n", K.file())
      y()
      y() -- the typing, still to redo
      assert.same("a = 1x", K.draft())
    end)
  end)

  describe("consecutive_moves_redo_with_the_field_the_first_move_left", function()
    local function z()
      K.keys("lctrl", "z")
    end
    local function y()
      K.keys("lctrl", "y")
    end
    it("consecutive_moves_redo_with_the_field_the_first_move_left / two moves after a cut: IDE wrong by the spec (IS6.6): redoing the first move leaves the field empty, not `a = 1`", function()
      K.reset({ ["main.lua"] = "a = 1\nb = 2\nc = 3\n" })
      K.open()
      K.keys("pageup")
      K.keys("lctrl", "delete")
      K.keys("lalt", "down")
      K.keys("lalt", "up")
      z()
      assert.same("c = 3\nb = 2\n", K.file())
      assert.same("", K.draft())
      z()
      assert.same("b = 2\nc = 3\n", K.file())
      y()
      assert.same("c = 3\nb = 2\n", K.file())
      assert.same("a = 1", K.draft())
      assert.same({ 1, 6 }, { K.cursor() })
      assert.same("inserting", K.state())
      y()
      assert.same("b = 2\nc = 3\n", K.file())
      assert.same("a = 1", K.draft())
    end)
    it("consecutive_moves_redo_with_the_field_the_first_move_left / a move then a cut", function()
      K.reset({ ["main.lua"] = "a = 1\nb = 2\nc = 3\n" })
      K.open()
      K.keys("pageup")
      K.keys("lalt", "down") -- b, a, c
      K.keys("down") -- onto `c = 3`
      K.keys("lctrl", "delete")
      z() -- the cut
      z() -- the move
      assert.same("a = 1\nb = 2\nc = 3\n", K.file())
      y() -- the move: the field as the move left it, empty
      assert.same("b = 2\na = 1\nc = 3\n", K.file())
      assert.same("", K.draft())
      y() -- the cut
      assert.same("c = 3", K.draft())
    end)
  end)

  describe("undo_and_redo_run_one_timeline_per_file", function()
    local MAIN = "require(\"helper\")\nb = 2\nc = 3\n"
    local FIVE = MAIN .. "p = 1\nq = 2\n"
    local function z()
      K.keys("lctrl", "z")
    end
    local function y()
      K.keys("lctrl", "y")
    end
    local function block(i)
      local n = 0
      for l in K.file():gmatch("([^\n]*)\n") do
        n = n + 1
        if n == i then
          return l
        end
      end
    end
    local function open(text)
      K.reset({ ["main.lua"] = text, ["helper.lua"] = "h = 1\n" })
      K.open()
    end
    it("undo_and_redo_run_one_timeline_per_file / a split submission undoes and redoes in one step", function()
      open(MAIN)
      K.type("p = 1")
      K.keys("lshift", "return")
      K.type("q = 2")
      K.keys("return")
      assert.same(5, K.blocks())
      z()
      assert.same(3, K.blocks())
      assert.same("end", K.position())
      y()
      assert.same(5, K.blocks())
    end)
    pending("undo_and_redo_run_one_timeline_per_file / draft changes redo until a new change; Ctrl+R unbound: spec silent: one Ctrl+Z takes back all of `abc`, Luditor one character", function()
      open(FIVE)
      K.type("abc")
      z()
      z()
      assert.same("a", K.draft())
      K.keys("lctrl", "r")
      assert.same("a", K.draft())
      y()
      assert.same("ab", K.draft())
      K.type("x")
      y()
      assert.same("abx", K.draft())
      K.keys("escape")
      z() -- the abort
      assert.same("abx", K.draft())
      for _ = 1, 3 do
        z()
      end
      assert.same("", K.draft())
    end)
    it("undo_and_redo_run_one_timeline_per_file / a held Ctrl+Y stops before each step", function()
      open(FIVE)
      K.type("r = 1")
      K.keys("return") -- 6 blocks
      K.keys("lctrl", "up") -- onto `r = 1`
      K.keys("f2")
      K.type("0")
      for _ = 1, 3 do
        z() -- the typing, the opening, the insertion
      end
      assert.same(5, K.blocks())
      assert.same("browsing", K.state())
      K.hold("lctrl")
      K.hold("y") -- the insertion
      K.repeat_key("y")
      K.release("y")
      K.release("lctrl")
      assert.same(6, K.blocks())
      assert.same("browsing", K.state())
      K.hold("lctrl")
      K.hold("y") -- the opening
      K.repeat_key("y") -- the typing
      K.release("y")
      K.release("lctrl")
      assert.same("r = 10", K.draft())
      assert.same(6, K.target())
      K.keys("escape")
      z() -- the abort
      z() -- the typing
      z() -- the opening
      z() -- the insertion
      assert.same(5, K.blocks())
    end)
    it("undo_and_redo_run_one_timeline_per_file / a cut and a move undo and redo with the browsing position", function()
      open(FIVE)
      K.keys("pageup")
      K.keys("down") -- onto `b = 2`
      K.keys("lctrl", "delete")
      assert.same("b = 2", K.draft())
      z()
      assert.same("b = 2", block(2))
      assert.same(3, K.position())
      assert.same("", K.draft())
      y()
      assert.same("b = 2", K.draft())
      assert.same(2, K.position())
      z()
      K.keys("up") -- onto `b = 2`
      K.keys("lalt", "down")
      assert.same("b = 2", block(3))
      z()
      assert.same("b = 2", block(2))
      assert.same(2, K.position())
      y()
      assert.same("b = 2", block(3))
      assert.same(3, K.position())
    end)
    it("undo_and_redo_run_one_timeline_per_file / Ctrl+J keeps the caller's timeline; leaving the referenced file ends its own", function()
      open(MAIN)
      local before = K.file()
      K.type("m = 1")
      K.keys("return")
      K.keys("pageup") -- onto require("helper")
      K.keys("lctrl", "j")
      assert.same("helper.lua", K.file_name())
      K.type("h = 2")
      K.keys("return")
      K.keys("escape") -- back to main.lua
      z()
      assert.same(before, K.file())
      K.keys("pageup")
      K.keys("lctrl", "j")
      z()
      assert.same("h = 1\nh = 2\n", K.file("helper.lua"))
      K.keys("escape")
    end)
  end)

  describe("spec_keys_undo_order_target_switching_and_limits", function()
    it("spec_keys_undo_order_target_switching_and_limits / undo order, target switching and limits", function()
      K.reset({ ["main.lua"] = "" })
      K.open()
      for _, s in ipairs({ "x = 1", "y = 2", "z = 3" }) do
        K.type(s)
        K.keys("return")
      end
      assert.same(3, K.blocks())

      -- IS3.12: Backspace and Delete in the browsing state change nothing
      K.keys("up") -- onto `z = 3`
      K.keys("backspace")
      K.keys("delete")
      assert.same(3, K.blocks())
      assert.same("browsing", K.state())

      -- IS6.1: Ctrl+Ins inserts the browsed block on lines of its own
      K.type("a = 0")
      K.keys("lctrl", "insert")
      assert.same("a = 0\nz = 3", K.draft())
      assert.same({ 2, 6 }, { K.cursor() })
      -- IS6.6: the copy is one draft change
      K.keys("lctrl", "z")
      assert.same("a = 0", K.draft())
      K.keys("escape")

      -- IS6.4: Shift+Ins submits and keeps the draft
      K.type("b = 4")
      K.keys("lshift", "insert")
      assert.same(4, K.blocks())
      assert.same("x = 1\ny = 2\nb = 4\nz = 3\n", K.file())
      assert.same(4, K.position())
      assert.same("inserting", K.state())
      assert.same("b = 4", K.draft())
      K.keys("escape")

      -- IS6.2, IS6.6: cut `z = 3`, type, undo latest first; a held
      -- key stops at the draft
      K.keys("lctrl", "delete")
      assert.same(3, K.blocks())
      assert.same("z = 3", K.draft())
      K.type("x")
      K.keys("backspace")
      assert.same("z = 3", K.draft())
      K.hold("lctrl")
      K.hold("z")
      assert.same("z = 3x", K.draft())
      K.repeat_key("z")
      assert.same("z = 3", K.draft())
      K.repeat_key("z") -- held: nothing beyond the draft
      assert.same(3, K.blocks())
      assert.same("inserting", K.state())
      K.release("z")
      K.release("lctrl")
      K.keys("lctrl", "z") -- a press of its own restores the block
      assert.same(4, K.blocks())
      assert.same("x = 1\ny = 2\nb = 4\nz = 3\n", K.file())
      assert.same("browsing", K.state())
      -- IS6.3, IS4.1: the position follows the restored block (the end)
      assert.same("end", K.position())

      -- IS2.3, IS5.6
      K.keys("lctrl", "up") -- onto `z = 3`
      K.keys("lctrl", "up") -- onto `b = 4`
      K.keys("f2")
      assert.same(3, K.target())
      K.keys("lctrl", "up") -- onto `y = 2`: the target stays
      assert.same(3, K.target())
      assert.same("b = 4", K.draft())
      K.keys("f2") -- switches to `y = 2`
      assert.same(2, K.target())
      assert.same("y = 2", K.draft())
      K.type("0")
      K.keys("lctrl", "up") -- onto `x = 1`: the target stays
      assert.same(1, K.position())
      assert.same(2, K.target())
      K.keys("f2")
      assert.is_not_nil(K.message())
      assert.same(2, K.target())
      -- IS6.6: the typing, the switch, then the opening
      K.keys("lctrl", "z")
      assert.same("y = 2", K.draft())
      K.keys("lctrl", "z")
      assert.same(3, K.target())
      assert.same("b = 4", K.draft())
      assert.same(1, K.position())
      K.keys("lctrl", "z")
      assert.same("browsing", K.state())
      assert.same(4, K.blocks())

      -- IS4.3: Enter on an emptied replacement draft leaves an empty line
      K.keys("down") -- onto `y = 2`
      K.keys("f2")
      for _ = 1, 5 do
        K.keys("backspace")
      end
      assert.same("", K.draft())
      K.keys("return")
      assert.same(4, K.blocks())
      assert.same("x = 1\n\nb = 4\nz = 3\n", K.file())
      assert.same("browsing", K.state())

      -- IS3.8: word movement, Ctrl+Home and Ctrl+End; IS3.12: Ctrl+K
      K.type("gfx.circle(10, 20, 5)")
      assert.same("gfx.circle(10, 20, 5)", K.draft())
      for _, col in ipairs({ 20, 16, 12, 5, 1 }) do
        K.keys("lctrl", "left")
        assert.same({ 1, col }, { K.cursor() })
      end
      K.keys("lctrl", "right")
      assert.same({ 1, 4 }, { K.cursor() })
      K.keys("lctrl", "right")
      assert.same({ 1, 11 }, { K.cursor() })
      K.keys("end")
      K.keys("lshift", "return")
      K.type("x = 1")
      assert.same("gfx.circle(10, 20, 5)\nx = 1", K.draft())
      K.keys("home")
      K.keys("lctrl", "left") -- crosses the line break
      assert.same({ 1, 20 }, { K.cursor() })
      K.keys("lctrl", "end")
      assert.same({ 2, 6 }, { K.cursor() })
      K.keys("lctrl", "home")
      assert.same({ 1, 1 }, { K.cursor() })
      for _ = 1, 3 do
        K.keys("right")
      end
      K.keys("lctrl", "k")
      assert.same("gfx", (K.draft():match("^[^\n]*")))
      K.keys("escape")

      -- IS3.3, IS3.14: a line over 64 characters is refused, naming the limit
      K.type("x = " .. string.rep("a", 70))
      K.keys("return")
      assert.same(4, K.blocks())
      assert.truthy((K.message() or ""):find("64", 1, true))
      assert.same("inserting", K.state())
      K.keys("escape")

      -- IS6.5, IS3.14: moving at the end position is refused
      K.keys("pagedown")
      assert.same("end", K.position())
      K.keys("lalt", "up")
      assert.is_not_nil(K.message())
      assert.same(4, K.blocks())
    end)
  end)

  describe("browsing_keeps_the_target_and_edit_switches_it_while_unmodified", function()
    pending("browsing_keeps_the_target_and_edit_switches_it_while_unmodified / the empty-line refusal names an empty line: the IDE says \"There is no block to edit here.\"", function()
      K.reset({ ["main.lua"] = "a = 1\n\nb = 2\nc = 3\n" })
      K.open()
      for _ = 1, 4 do
        K.keys("lctrl", "up")
      end
      K.keys("f2")
      K.keys("lctrl", "down")
      K.keys("f2")
      assert.truthy((K.message() or ""):find("empty line", 1, true))
      assert.same(1, K.target())
      assert.same("a = 1", K.draft())
    end)

    pending("browsing_keeps_the_target_and_edit_switches_it_while_unmodified / Edit at the end position names the end of file: the IDE says \"There is no block to edit here.\"", function()
      K.reset({ ["main.lua"] = "a = 1\n\nb = 2\nc = 3\n" })
      K.open()
      for _ = 1, 4 do
        K.keys("lctrl", "up")
      end
      K.keys("f2")
      K.keys("pagedown")
      K.keys("f2")
      assert.truthy((K.message() or ""):find("End of file", 1, true))
      assert.same(1, K.target())
    end)

    it("browsing_keeps_the_target_and_edit_switches_it_while_unmodified / target, switch, refusals and submission", function()
      K.reset({ ["main.lua"] = "a = 1\n\nb = 2\nc = 3\n" })
      K.open()
      assert.same(4, K.blocks())
      for _ = 1, 4 do
        K.keys("lctrl", "up")
      end
      K.keys("f2") -- A
      assert.same(1, K.target())
      assert.same({ 1, 6 }, { K.cursor() })

      -- IS5.6: Edit on an empty line during a replacement is refused
      -- (its notice wording is checked in the pending case below)
      K.keys("lctrl", "down")
      K.keys("f2")
      assert.is_not_nil(K.message())
      assert.same(1, K.target())
      assert.same("a = 1", K.draft())

      -- FR1.3, IS2.3
      K.keys("lctrl", "down") -- onto B
      assert.same(3, K.position())
      assert.same(1, K.target())
      assert.same("a = 1", K.draft())
      assert.same({ 1, 6 }, { K.cursor() })

      -- IS5.6, FR1.5: Edit on B switches
      K.keys("f2")
      assert.same(3, K.target())
      assert.same("b = 2", K.draft())
      assert.same({ 1, 6 }, { K.cursor() })

      -- IS6.6: Ctrl+Z switches back to A; position stays on B
      K.keys("lctrl", "z")
      assert.same(1, K.target())
      assert.same("a = 1", K.draft())
      assert.same(3, K.position())
      assert.same("replacing", K.state())

      -- IS5.6: Edit at the end position is refused
      K.keys("pagedown")
      K.keys("f2")
      assert.is_not_nil(K.message()) -- wording: pending case below
      assert.same(1, K.target())

      -- IS6.1: a copy into the unmodified replacement draft
      K.keys("lctrl", "up") -- onto C
      K.keys("lctrl", "insert")
      assert.same("a = 1\nc = 3", K.draft())
      assert.same(1, K.target())
      K.keys("lctrl", "z")
      assert.same("a = 1", K.draft())
      assert.same(1, K.target())

      -- Edit on B, modify, browse to C, Edit: refused
      K.keys("lctrl", "up") -- onto B
      K.keys("f2")
      assert.same(3, K.target())
      K.type("0")
      K.keys("lctrl", "down") -- onto C
      K.keys("f2")
      assert.truthy((K.message() or ""):find("Already editing", 1, true))
      assert.same(3, K.target())
      assert.same("b = 20", K.draft())

      K.keys("return")
      assert.same("browsing", K.state())
      assert.same("a = 1\n\nb = 20\nc = 3\n", K.file())
    end)
  end)

  describe("editor_journeys_insert_replace_copy_cut_move_undo_and_escape", function()
    it("editor_journeys_insert_replace_copy_cut_move_undo_and_escape / insert, replace, move, cut and undo", function()
      local function lines()
        return select(2, K.draft():gsub("\n", "")) + 1
      end
      K.reset({ ["main.lua"] = "" })
      K.open()
      assert.same("browsing", K.state())
      assert.same(0, K.blocks())

      -- 1. typewriter entry
      K.type("x=1")
      assert.same("inserting", K.state())
      assert.is_nil(K.target())
      K.keys("return")
      assert.same("browsing", K.state())
      assert.same(1, K.blocks())
      assert.same("x = 1\n", K.file())
      assert.same("end", K.position())

      -- 2. an empty-draft Enter inserts an empty line
      K.keys("return")
      assert.same(2, K.blocks())
      assert.same("x = 1\n\n", K.file())
      assert.same("end", K.position())

      -- 3. IS3.5: an incomplete statement continues on Enter
      K.type("if x == 1 then")
      K.keys("return")
      assert.same("inserting", K.state())
      assert.same(2, lines())
      K.type("y = 2")
      K.keys("return")
      assert.same(3, lines())
      K.type("end")
      K.keys("return")
      assert.same("browsing", K.state())
      assert.same(3, K.blocks())
      assert.same("x = 1\n\nif x == 1 then\n  y = 2\nend\n", K.file())

      -- 4. typing on a block does not open a replacement; Escape aborts
      K.keys("up")
      K.keys("up")
      K.keys("up")
      assert.same(1, K.position())
      K.type("z = 0")
      assert.same("inserting", K.state())
      assert.is_nil(K.target())
      K.keys("escape")
      assert.same("browsing", K.state())
      assert.same("", K.draft())

      -- 5. F2 on `x = 1`
      K.keys("f2")
      assert.same("replacing", K.state())
      assert.same(1, K.target())
      assert.same("x = 1", K.draft())
      assert.same({ 1, 6 }, { K.cursor() })
      K.keys("lctrl", "down")
      assert.same(2, K.position())
      assert.same(1, K.target())
      K.keys("backspace")
      K.type("10")
      K.keys("lshift", "return")
      K.type("w = 20")
      K.keys("return")
      assert.same("browsing", K.state())
      assert.is_nil(K.target())
      assert.same(4, K.blocks())
      assert.same("x = 10\nw = 20\n\nif x == 1 then\n  y = 2\nend\n",
        K.file())
      assert.same(3, K.position())

      -- 6. IS6.5: Alt+Up moves a block
      K.keys("up")
      assert.same(2, K.position())
      K.keys("lalt", "up")
      assert.same(1, K.position())
      assert.same("w = 20\nx = 10\n\nif x == 1 then\n  y = 2\nend\n",
        K.file())

      -- 7. IS6.2, IS6.3: cut, then Ctrl+Z restores
      K.keys("lctrl", "delete")
      assert.same(3, K.blocks())
      assert.same("inserting", K.state())
      assert.same("w = 20", K.draft())
      K.keys("lctrl", "z")
      assert.same("browsing", K.state())
      assert.same(4, K.blocks())
      assert.same("w = 20\nx = 10\n\nif x == 1 then\n  y = 2\nend\n",
        K.file())
    end)
  end)

  describe("a_cut_that_would_merge_its_neighbours_is_refused", function()
    it("a_cut_that_would_merge_its_neighbours_is_refused / refused, then cutting the merging block: the IDE cuts `do end` and leaves 2 blocks, no refusal", function()
      K.reset({ ["main.lua"] = "a = f\ndo end\n(g)()\nx = 1\n" })
      K.open()
      assert.same(4, K.blocks())
      K.keys("up")
      K.keys("up")
      K.keys("up") -- onto `do end`
      K.keys("lctrl", "delete")
      assert.same(4, K.blocks())
      assert.truthy((K.message() or ""):find("Cutting", 1, true))
      assert.same("browsing", K.state())
      K.keys("down") -- onto `(g)()`
      K.keys("lctrl", "delete")
      assert.same(3, K.blocks())
      assert.same("(g)()", K.draft())
    end)
  end)

  describe("escape_dismisses_a_notice_first_and_ctrl_q_keeps_a_draft", function()
    -- Luditor's Escape only dismisses the notice and keeps
    -- the draft; by the maintainer's ruling the IDE's Escape
    -- is not special: it dismisses and aborts in one press.
    it("escape_dismisses_a_notice_first_and_ctrl_q_keeps_a_draft / a syntax error on Enter shows a notice; one Escape dismisses it and drops the draft", function()
      K.reset({ ["main.lua"] = "" })
      K.open()
      K.type("x = = 2")
      K.keys("return")
      assert.is_not_nil(K.message())
      assert.same("x = = 2", K.draft())
      K.keys("escape")
      assert.is_nil(K.message())
      assert.same("", K.draft())
      assert.same("browsing", K.state())
      assert.same("editor", K.app_state())
    end)

    it("escape_dismisses_a_notice_first_and_ctrl_q_keeps_a_draft / Ctrl+Q refused with a draft, Escape dismisses then drops", function()
      K.reset({ ["main.lua"] = "" })
      K.open()
      K.type("x = = 2")
      K.keys("return")
      K.keys("lctrl", "q")
      assert.same("editor", K.app_state())
      assert.is_not_nil(K.message())
      assert.same("x = = 2", K.draft())
      K.keys("escape")
      assert.is_nil(K.message())
      assert.same("browsing", K.state())
      assert.same("editor", K.app_state())
    end)

    it("escape_dismisses_a_notice_first_and_ctrl_q_keeps_a_draft / an empty-line Enter ends the stale draft history", function()
      K.reset({ ["main.lua"] = "" })
      K.open()
      K.type("zz")
      K.keys("backspace")
      K.keys("backspace")
      K.keys("return")
      assert.same(1, K.blocks())
      K.keys("lctrl", "z")
      assert.same("", K.draft())
      assert.same(0, K.blocks())
    end)

    -- Luditor lands three empty-line blocks; the maintainer's
    -- ruling of November 14, 2026 lets the formatter decide:
    -- one empty line
    it("escape_dismisses_a_notice_first_and_ctrl_q_keeps_a_draft / three blank lines submit as one empty line, then Ctrl+Q quits", function()
      K.reset({ ["main.lua"] = "" })
      K.open()
      K.keys("lalt", "return")
      K.keys("lalt", "return")
      local n = select(2, K.draft():gsub("\n", "")) + 1
      assert.same(3, n)
      K.keys("return")
      assert.same(1, K.blocks())
      K.keys("lctrl", "q")
      assert.are_not.same("editor", K.app_state())
    end)
  end)

  describe("over_limit_lua_block_is_browsable_and_cuttable_but_not_editable", function()
    -- Luditor refuses Edit here; the maintainer's ruling of
    -- November 14, 2026 opens the block, and Enter refuses it
    it("over_limit_lua_block_is_browsable_and_cuttable_but_not_editable / Edit opens it, cut loads it", function()
      local body = "function f()\n"
      for i = 0, 13 do
        body = body .. "  print(" .. i .. ")\n"
      end
      body = body .. "end\n"
      K.reset({ ["main.lua"] = body })
      K.open()
      assert.same(1, K.blocks())
      K.keys("up")
      assert.same(1, K.position())
      K.keys("f2")
      assert.same("replacing", K.state())
      K.keys("return")
      assert.truthy((K.message() or ""):find("14", 1, true))
      assert.same(body, K.file())
      K.keys("escape")
      assert.same("browsing", K.state())
      K.keys("lctrl", "delete")
      assert.same(0, K.blocks())
      local n = select(2, K.draft():gsub("\n", "")) + 1
      assert.same(16, n)
      assert.same("", K.file())
    end)
  end)

  describe("review_regressions_live_formatting_reload_undo_and_interleaved_moves", function()
    local N = "review_regressions_live_formatting_reload_undo_and_interleaved_moves"
    -- Skipped: the --live-format part (a Luditor-only flag).
    local function start()
      K.reset({ ["main.lua"] = "" })
      K.open()
    end

    it(N .. " / the draft keeps the user's spelling until acceptance", function()
      start()
      K.type("x=1")
      assert.same("x=1", K.draft())
    end)

    local function abc()
      start()
      for _, s in ipairs({ "a = 1", "b = 2", "c = 3" }) do
        K.type(s)
        K.keys("return")
      end
    end

    it(N .. " / an F2 reload is one draft change; browsing keeps the target", function()
      abc()
      K.keys("up")
      K.keys("up")
      K.keys("up")
      assert.same(1, K.position())
      K.keys("f2")
      K.type("0")
      K.keys("f2")
      assert.same("a = 1", K.draft())
      K.keys("lctrl", "down")
      assert.same(1, K.target())
      K.keys("lctrl", "z")
      assert.same("a = 10", K.draft())
    end)

    it(N .. " / cut, type, move undo in reverse order", function()
      abc()
      K.keys("up")
      K.keys("up")
      K.keys("up")
      K.keys("lctrl", "delete")
      assert.same("a = 1", K.draft())
      K.type("0")
      K.keys("lalt", "down")
      assert.same("c = 3\nb = 2\n", K.file())
      K.keys("lctrl", "z")
      assert.same("c = 3\nb = 2\n", K.file())
      assert.same("a = 1", K.draft())
      K.keys("lctrl", "z")
      assert.same("b = 2\nc = 3\n", K.file())
      assert.same("", K.draft())
      K.keys("lctrl", "z")
      assert.same(3, K.blocks())
      assert.same("a = 1\nb = 2\nc = 3\n", K.file())
      assert.same(2, K.position())
      assert.same("browsing", K.state())
    end)
  end)

  describe("final_round_regressions_undo_timeline_f2_cursor_blank_lines_and_wrapping", function()
    local N = "final_round_regressions_undo_timeline_f2_cursor_blank_lines_and_wrapping"
    -- Skipped: the refused 70-character draft (depends on Luditor's 64-column
    -- formatter width), the notice/repeat-guard part, grapheme wrapping
    -- (rendering).
    local function start()
      K.reset({ ["main.lua"] = "a = 1\nb = 2\n" })
      K.open()
    end

    it(N .. " / a typed character after a move is undone first, then the move", function()
      start()
      K.browse_to(2)
      K.keys("lalt", "up")
      assert.same("b = 2\na = 1\n", K.file())
      K.type("b")
      K.keys("lctrl", "z")
      assert.same("b = 2\na = 1\n", K.file())
      assert.is_nil(K.draft():match("b$"))
      for _ = 1, 20 do
        if K.draft() == "" then break end
        K.keys("lctrl", "z")
      end
      K.keys("lctrl", "z")
      assert.same("a = 1\nb = 2\n", K.file())
    end)

    it(N .. " / F2 on an untouched target puts the cursor at the end", function()
      start()
      K.browse_to(1)
      K.keys("f2")
      K.keys("home")
      K.keys("f2")
      assert.same({ 1, 6 }, { K.cursor() })
      K.keys("lctrl", "z")
      assert.same("browsing", K.state())
    end)

    it(N .. " / a retained blank-only draft keeps its cursor line: "
        .. "Shift+Ins empties the field instead of retaining the blank draft", function()
      start()
      K.browse_to_end()
      K.keys("lalt", "return")
      K.keys("lalt", "return")
      assert.same({ 3, 1 }, { K.cursor() })
      K.keys("lshift", "insert")
      assert.same("\n\n", K.draft())
      assert.same({ 3, 1 }, { K.cursor() })
    end)
  end)

  describe("regressions_multiline_calls_long_strings_comments_and_copy_undo", function()
    local N = "regressions_multiline_calls_long_strings_comments_and_copy_undo"
    -- Skipped: parts 1-4 call the formatter and validator directly
    -- (formatter internals).
    it(N .. " / Ctrl+Z after a copy undoes the copy in the draft, not the block", function()
      K.reset({ ["main.lua"] = "" })
      K.open()
      K.type("x = 1")
      K.keys("return")
      assert.same(1, K.blocks())
      K.keys("up")
      K.keys("lctrl", "insert")
      assert.same("inserting", K.state())
      assert.same("x = 1", K.draft())
      K.keys("lctrl", "z")
      assert.same("browsing", K.state())
      assert.same(1, K.blocks())
      assert.same("x = 1\n", K.file())
    end)
  end)

  describe("paste_is_one_change_return_guard_open_file_and_read_only_file", function()
    local N = "paste_is_one_change_return_guard_open_file_and_read_only_file"
    -- Skipped: the paste part (the IDE has no paste). The read-only file
    -- maps to K.fail_writes (file permissions themselves are Luditor-only).
    local function start(text)
      K.reset({ ["main.lua"] = text or "" })
      K.open()
    end

    it(N .. " / the draft retained after Shift+Ins starts afresh", function()
      start()
      K.type("x=1")
      K.keys("lshift", "insert")
      assert.same("x = 1", K.draft())
      K.keys("lctrl", "z")
      assert.same("", K.draft())
      assert.same(0, K.blocks())
      K.keys("lctrl", "y")
      assert.same(1, K.blocks())
      assert.same("x = 1", K.draft())
    end)

    it(N .. " / nothing may follow a return: insertion and move refused", function()
      start("x = 1\n")
      K.type("return 1")
      K.keys("return")
      assert.same(2, K.blocks())
      K.type("y = 2")
      K.keys("return")
      assert.same(2, K.blocks())
      assert.truthy((K.message() or ""):find("return"))
      assert.same("inserting", K.state())
      K.keys("escape")
      K.keys("up")
      K.keys("lalt", "up")
      assert.same("x = 1\nreturn 1\n", K.file())
      assert.is_not_nil(K.message())
    end)

    it(N .. " / Ctrl+J onto a file that is already open is refused", function()
      K.reset({ ["self.lua"] = "dofile(\"self.lua\")\n" })
      K.open("self.lua")
      K.keys("up")
      K.keys("lctrl", "j")
      assert.same("self.lua", K.file_name())
      assert.truthy((K.message() or ""):find("already open"))
    end)

    it(N .. " / a file that cannot be written is left alone, the refusal explained", function()
      start("x = 1\n")
      K.fail_writes("read-only")
      K.type("y = 2")
      K.keys("return")
      assert.same("x = 1\n", K.file())
      assert.same("y = 2", K.draft())
      assert.is_not_nil(K.message())
      assert.same(1, K.blocks())
    end)
  end)

  describe("repaired_invalid_lua_file_is_rechunked", function()
    local N = "repaired_invalid_lua_file_is_rechunked"
    it(N .. " / cutting the invalid line lets the file rechunk", function()
      K.reset({ ["main.lua"] = "x = 1\n?\n" })
      K.open()
      assert.same(2, K.blocks())
      K.keys("up")
      -- Luditor refuses Edit here; the maintainer's ruling of
      -- November 14, 2026 opens the line
      K.keys("f2")
      assert.same("?", K.draft())
      K.keys("escape")
      K.keys("lctrl", "delete")
      K.keys("escape")
      K.keys("up")
      K.keys("f2")
      assert.same("replacing", K.state())
      assert.same("x = 1", K.draft())
    end)
  end)

  describe("round_three_minors_card_release_redo_notice_opening_and_lone_cursor_mark", function()
    local N = "round_three_minors_card_release_redo_notice_opening_and_lone_cursor_mark"
    -- Skipped: the one-cell field's lone cursor mark (rendering on a 1x3
    -- terminal). File permissions map to K.fail_writes.
    local function start()
      K.reset({ ["main.lua"] = "a = 1\nb = 2\nc = 3\n" })
      K.open()
    end

    pending(N .. " / a fresh F1 press while the card shows means a missed release: "
        .. "a second F1 press without a release leaves the card shown", function()
      start()
      K.hold("f1")
      K.hold("f1")
      assert.falsy(K.key_card())
    end)

    it(N .. " / redoing an opening leaves the highlight on the target: "
        .. "the redo restores the target but leaves the browsing position at 3", function()
      start()
      K.browse_to(1)
      K.keys("f2")
      K.keys("lctrl", "z")
      K.keys("lctrl", "down")
      K.keys("lctrl", "down")
      K.keys("lctrl", "y")
      assert.same(1, K.target())
      assert.same(1, K.position())
    end)

    it(N .. " / a redo that cannot write says so as a redo: "
        .. "the notice is the generic 'Could not save the file'", function()
      start()
      K.type("x = 1")
      K.keys("return")
      K.keys("lctrl", "z")
      K.fail_writes("read-only")
      K.keys("lctrl", "y")
      assert.truthy((K.message() or ""):find("Nothing redone.", 1, true))
    end)
  end)

  describe("closing_round_regressions_tabs_in_text_new_root_file_merges_and_empty_paste", function()
    local N = "closing_round_regressions_tabs_in_text_new_root_file_merges_and_empty_paste"
    -- Skipped: the tab placeholder (rendering) and the pastes themselves
    -- (the IDE has no paste); the cut-then-Ctrl+Z it guards is kept.
    it(N .. " / Ctrl+J back to a root file that did not exist is refused", function()
      K.reset({ })
      K.open("fresh.lua")
      K.type("dofile(\"fresh.lua\")")
      K.keys("return")
      K.keys("up")
      K.keys("lctrl", "j")
      assert.same("fresh.lua", K.file_name())
      assert.truthy((K.message() or ""):find("already open"))
    end)

    local function merged()
      K.reset({ ["main.lua"] = "" })
      K.open()
      K.type("a = f")
      K.keys("return")
      K.type("(g)()")
      K.keys("return")
    end

    pending(N .. " / two blocks that would read as one statement are refused: "
        .. "refused, but the notice blames a return or break", function()
      merged()
      assert.same(1, K.blocks())
      assert.truthy((K.message() or ""):find("merge"))
    end)

    it(N .. " / a cut stays one Ctrl+Z away", function()
      merged()
      -- one Escape: the notice goes and the edit with it
      K.keys("escape")
      K.keys("up")
      K.keys("lctrl", "delete")
      assert.same("a = f", K.draft())
      K.keys("lctrl", "z")
      assert.same(1, K.blocks())
      assert.same("browsing", K.state())
    end)
  end)

  describe("with_text_in_the_field_the_arrows_only_move_the_cursor", function()
    local DRAFT = "gfx.circle(10, 20, 5)\nx = 1"
    local function check(line, col, browsing)
      local l, c = K.cursor()
      assert.same({ DRAFT, line, col, browsing, 2 },
        { K.draft(), l, c, K.position(), K.target() })
    end
    local function cur()
      local l, c = K.cursor()
      return { l, c }
    end

    it("with_text_in_the_field_the_arrows_only_move_the_cursor / "
        .. "Up, Down and Ctrl+Up/Down with text in the field", function()
      K.reset({ ["arrows.lua"] = "a = 1\ngfx.circle(10, 20, 5)\nb = 2\n" })
      K.open("arrows.lua")
      K.keys("up")
      K.keys("up")
      K.keys("f2")
      assert.same({ 1, 22 }, cur())
      K.keys("end")
      K.keys("lshift", "return")
      K.type("x = 1")
      -- IS3.8: Home, then Up, stands before gfx; Up again stays.
      K.keys("home")
      K.keys("up")
      check(1, 1, 2)
      K.keys("up")
      check(1, 1, 2)
      -- IS2.1: Ctrl+Up and Ctrl+Down browse; draft and cursor stay.
      K.keys("lctrl", "up")
      check(1, 1, 1)
      K.keys("lctrl", "down")
      check(1, 1, 2)
      K.keys("down")
      check(2, 1, 2)
      K.keys("down")
      check(2, 6, 2)
      K.keys("down")
      check(2, 6, 2)
      -- with the field empty, the bare keys browse
      K.keys("escape")
      K.keys("down")
      assert.same(3, K.position())
      -- an insertion draft of one line: Down to its end, Up to its start
      K.type("y = 3")
      K.keys("left")
      K.keys("down")
      assert.same({ 1, 6 }, cur())
      K.keys("up")
      assert.same({ 1, 1 }, cur())
      assert.same(3, K.position())
      K.keys("escape")
      -- a replacement draft cleared to empty browses; the target stays
      K.keys("f2")
      K.keys("home")
      K.keys("lctrl", "k")
      assert.same("", K.draft())
      K.keys("up")
      assert.same(2, K.position())
      assert.same(3, K.target())
      assert.same("replacing", K.state())
    end)
  end)

  describe("ctrl_j_follows_require_and_escape_stops_at_root_file_until_ctrl_q",
      function()
    it("ctrl_j_follows_require_and_escape_stops_at_root_file_until_ctrl_q / "
        .. "follow, abort, pop", function()
      K.reset({
        ["main.lua"] = "require(\"helper\")\n",
        ["helper.lua"] = "local h = 42\n"
      })
      K.open("main.lua")
      assert.same("main.lua", K.file_name())
      -- opening starts at the end position (FR3.3, IS1.1)
      assert.same("end", K.position())
      K.keys("up")
      assert.same(1, K.position())
      -- IS1.5: Ctrl+J follows the require
      K.keys("lctrl", "j")
      assert.same("helper.lua", K.file_name())
      -- IS5.7: Escape aborts the draft and stays in helper.lua
      K.type("local temp = 1")
      assert.same("inserting", K.state())
      K.keys("escape")
      assert.same("helper.lua", K.file_name())
      assert.same("browsing", K.state())
      -- IS1.6: Escape while browsing pops back to main.lua
      K.keys("escape")
      assert.same("main.lua", K.file_name())
    end)

    pending("ctrl_j_follows_require_and_escape_stops_at_root_file_until_ctrl_q"
        .. " / Escape at the root file stays, Ctrl+Q quits: IS1.6 has the "
        .. "bottom-most Escape close the editor", function()
      K.reset({
        ["main.lua"] = "require(\"helper\")\n",
        ["helper.lua"] = "local h = 42\n"
      })
      K.open("main.lua")
      K.keys("up")
      K.keys("lctrl", "j")
      K.keys("escape")
      assert.same("main.lua", K.file_name())
      -- Escape at the root file does not quit
      K.keys("escape")
      assert.same("main.lua", K.file_name())
      -- Ctrl+Q quits
      K.keys("lctrl", "q")
      assert.is_nil(K.file_name())
    end)
  end)

  describe("browse_keys_scroll_a_tall_block_row_by_row_before_moving_on",
      function()
    -- Luditor's function has 12 prints for a 9-row view; the
    -- Compy's view is taller, so each function has 30.
    local N = 30
    local function tall(name)
      local t = { "function " .. name .. "()" }
      for i = 1, N do
        t[#t + 1] = "  print(" .. i .. ")"
      end
      t[#t + 1] = "end"
      return table.concat(t, "\n") .. "\n"
    end
    local function starts(row, prefix)
      return row ~= nil and row:sub(1, #prefix) == prefix
    end
    local function top()
      return K.view_rows()[1]
    end
    local function bottom()
      local v = K.view_rows()
      return v[#v]
    end
    local function cur()
      local l, c = K.cursor()
      return { l, c }
    end

    it("browse_keys_scroll_a_tall_block_row_by_row_before_moving_on / "
        .. "Ctrl+Up/Down with a full field scroll, then move on", function()
      K.reset({ ["tall.lua"] = "x = 1\n" .. tall("f") .. tall("g")
          .. "y = 2\n" })
      K.open("tall.lua")
      assert.same(4, K.blocks())
      -- a 14-line draft brings the field to its limit of 8 rows
      local lines = { }
      for i = 1, 14 do
        lines[i] = "a" .. i .. " = " .. i
      end
      K.type_lines(lines)
      local draft, cursor = K.draft(), cur()
      K.browse_to(1)
      -- IS2.2: from above, the tall block shows from its first row
      K.keys("lctrl", "down")
      assert.same(2, K.position())
      assert.is_true(starts(top(), "function f()"), top())
      local rows, shown = K.rows_shown(2)
      local steps = rows - shown
      assert.is_true(0 < steps)
      for step = 1, steps do
        K.keys("lctrl", "down")
        assert.same(2, K.position())
        assert.is_true(starts(top(), "  print(" .. step .. ")"), top())
      end
      assert.is_true(starts(bottom(), "end"), bottom())
      -- the next press moves on; g shows from its first row
      K.keys("lctrl", "down")
      assert.same(3, K.position())
      assert.is_true(starts(top(), "function g()"), top())
      -- from below, f shows from its last row at the bottom
      K.keys("lctrl", "up")
      assert.same(2, K.position())
      assert.is_true(starts(bottom(), "end"), bottom())
      assert.is_true(starts(top(), "  print(" .. steps .. ")"), top())
      for step = steps, 1, -1 do
        K.keys("lctrl", "up")
        assert.same(2, K.position())
        local want = step == 1 and "function f()"
            or "  print(" .. (step - 1) .. ")"
        assert.is_true(starts(top(), want), top())
      end
      K.keys("lctrl", "up")
      assert.same(1, K.position())
      -- FR3.4: draft and cursor unchanged throughout
      assert.same(draft, K.draft())
      assert.same(cursor, cur())
      -- with the field empty the bare keys scroll the same way
      K.keys("escape")
      K.keys("down")
      K.keys("down")
      assert.same(2, K.position())
      assert.is_true(starts(top(), "  print(1)"), top())
    end)
  end)

  describe("at_the_end_position_a_tall_last_block_shows_its_last_rows",
      function()
    -- Luditor: 12 prints in a 10-row view; here 30, taller than
    -- the Compy's view.
    local N = 30
    local function starts(row, prefix)
      return row ~= nil and row:sub(1, #prefix) == prefix
    end

    it("at_the_end_position_a_tall_last_block_shows_its_last_rows / "
        .. "end at the bottom, Up stays then scrolls", function()
      local t = { "x = 1", "function f()" }
      for i = 1, N do
        t[#t + 1] = "  print(" .. i .. ")"
      end
      t[#t + 1] = "end"
      K.reset({ ["last.lua"] = table.concat(t, "\n") .. "\n" })
      K.open("last.lua")
      assert.same("end", K.position())
      local v = K.view_rows()
      assert.is_true(starts(v[#v], "end"), v[#v])
      local first = v[1]
      local k = tonumber(first:match("^  print%((%d+)%)"))
      assert.is_truthy(k, first)
      -- from below, the view stays; Up then scrolls one row
      K.keys("up")
      assert.is_true(starts(K.view_rows()[1], first), K.view_rows()[1])
      K.keys("up")
      assert.same(2, K.position())
      assert.is_true(starts(K.view_rows()[1], "  print(" .. (k - 1) .. ")"),
        K.view_rows()[1])
    end)
  end)

  describe("text_files_have_no_line_limit_and_only_md_is_markdown",
      function()
    it("text_files_have_no_line_limit_and_only_md_is_markdown / "
        .. "a 149-character line is one block", function()
      K.reset({ ["notes.txt"] = "" })
      K.open("notes.txt")
      local long = ("word "):rep(30):gsub(" $", "")
      K.type(long)
      K.keys("return")
      assert.same(1, K.blocks())
      assert.same(long .. "\n", K.file("notes.txt"))
      assert.same(149, #long)
      assert.same("browsing", K.state())
    end)

    for _, c in ipairs({
      { "a.markdown", "plain" },
      { "a.md", "markdown" },
      { "a.lua", "lua" },
      { "Makefile", "plain" }
    }) do
      it("text_files_have_no_line_limit_and_only_md_is_markdown / "
          .. c[1] .. " is " .. c[2], function()
        K.reset({ [c[1]] = "" })
        K.open(c[1])
        assert.same(c[2], K.file_type())
      end)
    end
  end)

  describe("holding_f1_shows_the_key_card_and_suspends_every_other_key",
      function()
    it("holding_f1_shows_the_key_card_and_suspends_every_other_key / "
        .. "keys while F1 is held change nothing", function()
      K.reset({ ["card.lua"] = "a = 1\nb = 2\nc = 3\n" })
      K.open("card.lua")
      K.keys("up")
      K.keys("up")
      assert.same(2, K.position())
      -- FR4.9, IS3.16: F1 held shows the card
      K.hold("f1")
      assert.is_truthy(K.key_card())
      -- typing, Escape, Ctrl+Q and F1's repeats change nothing
      K.type("x")
      K.keys("escape")
      K.keys("lctrl", "q")
      K.repeat_key("f1")
      assert.is_truthy(K.key_card())
      assert.same("card.lua", K.file_name())
      assert.same("", K.draft())
      assert.same(2, K.position())
      K.release("f1")
      assert.is_nil(K.key_card())
      -- inserting: the card comes and goes, the draft stays
      K.type("x")
      K.hold("f1")
      assert.is_truthy(K.key_card())
      K.release("f1")
      assert.same("x", K.draft())
      -- replacing: target and draft unchanged
      K.keys("escape")
      K.keys("f2")
      K.hold("f1")
      assert.is_truthy(K.key_card())
      K.release("f1")
      assert.same(2, K.target())
      assert.same("b = 2", K.draft())
    end)
  end)

  describe("the_cursor_moves_by_displayed_row", function()
    -- Luditor runs this at 20 columns; the Compy's field is 64.
    -- Every width-bound length is scaled so that the same rows
    -- arise: `four` becomes a 48-letter word, so the first row
    -- is 63 characters plus the padding, as Luditor's is 19
    -- plus the padding.
    local W = 64
    local FOUR = ("f"):rep(W - 16)
    local TEXT = "one two three " .. FOUR .. " five six seven"
    local R2 = W -- the second row's first column
    local function cur()
      local l, c = K.cursor()
      return { l, c }
    end

    pending("the_cursor_moves_by_displayed_row / Up, Down, Home and End "
        .. "by rows of a wrapped line: Luditor's field breaks between words "
        .. "after a padding cell, IS3.13 wraps from the left edge", function()
      K.reset({ ["walk.txt"] = "" })
      K.open("walk.txt")
      K.type(TEXT)
      local last = #TEXT + 1
      assert.same({ 1, last }, cur())
      -- IS3.8: Up keeps the offset from the row's first position
      K.keys("up")
      assert.same({ 1, 15 }, cur())
      -- End stands after the row's last word, before its space
      K.keys("end")
      assert.same({ 1, W - 1 }, cur())
      -- Down onto a shorter row stands at its last position
      K.keys("down")
      assert.same({ 1, last }, cur())
      K.keys("home")
      assert.same({ 1, R2 }, cur())
      -- within the line's rows at the same offset, both ways
      K.keys("lctrl", "home")
      for _ = 1, 4 do
        K.keys("right")
      end
      K.keys("down")
      assert.same({ 1, R2 + 4 }, cur())
      K.keys("up")
      assert.same({ 1, 5 }, cur())
      -- first row: Up to the draft's start; last row: Down to its end
      K.keys("up")
      assert.same({ 1, 1 }, cur())
      K.keys("down")
      assert.same({ 1, R2 }, cur())
      K.keys("down")
      assert.same({ 1, last }, cur())
      -- IS3.12: Ctrl+K from the first row removes the rest of the line
      K.keys("lctrl", "home")
      for _ = 1, 4 do
        K.keys("right")
      end
      K.keys("lctrl", "k")
      assert.same("one ", K.draft())
      K.keys("lctrl", "z")
      assert.same(TEXT, K.draft())
      -- across lines by rows: up to the second row of the line above
      K.keys("lctrl", "end")
      K.keys("lshift", "return")
      K.type("ab")
      K.keys("up")
      assert.same({ 1, R2 + 2 }, cur())
      K.keys("up")
      assert.same({ 1, 3 }, cur())
      K.keys("down")
      K.keys("down")
      assert.same({ 2, 3 }, cur())
    end)

    it("the_cursor_moves_by_displayed_row / a line that fills its "
        .. "row does not wrap", function()
      K.reset({ ["walk.txt"] = "" })
      K.open("walk.txt")
      K.type(("abcdefghijklmnopqrstuvwxyz"):rep(3):sub(1, W))
      assert.same({ 1, W + 1 }, cur())
      K.keys("home")
      assert.same({ 1, 1 }, cur())
      K.keys("end")
      assert.same({ 1, W + 1 }, cur())
      K.keys("up")
      assert.same({ 1, 1 }, cur())
      K.keys("lctrl", "end")
      K.keys("lshift", "return")
      K.type("xyz")
      K.keys("up")
      assert.same({ 1, 4 }, cur())
      K.keys("end")
      assert.same({ 1, W + 1 }, cur())
      K.keys("down")
      assert.same({ 2, 4 }, cur())
    end)

    it("the_cursor_moves_by_displayed_row / a line wrapped at the "
        .. "edge", function()
      K.reset({ ["walk.txt"] = "" })
      K.open("walk.txt")
      -- rows of W and, after the padding, W - 1
      K.type(("x"):rep(2 * W - 1))
      K.keys("lctrl", "home")
      K.keys("down")
      assert.same({ 1, W + 1 }, cur())
      K.keys("end")
      assert.same({ 1, 2 * W }, cur())
      K.keys("home")
      assert.same({ 1, W + 1 }, cur())
    end)
  end)
end)
