-- IS4 Inserting Lua text, IS5 Replacing and restoring a Lua
-- block (editor principles, ratified): the clauses the tests
-- of is4_is5_spec.lua leave out. Keys only, through
-- tests/helpers/editor_keys.lua. Edit is F2.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it, spec_gap = marks.spec_it, marks.spec_gap

local FILE = "x = 1\ny = 2\nz = 3\n"
local FOUR = "x = 1\ny = 2\nz = 3\nw = 4\n"
local GAPPED = "x = 1\n\ny = 2\n"

local function open_file(text)
  K.reset({ ["main.lua"] = text or FILE })
  K.open()
end

--- Edit (F2) on block `b`.
local function edit(b)
  K.browse_to(b)
  K.keys("f2")
end

describe("IS4 and IS5, added #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  describe("IS4", function()
    before_each(function()
      open_file()
    end)

    spec_it(
        "IS4.1 Insert before a block: a draft of two blocks "
        .. "goes before it, the position still on it", function(
      
    )
      K.browse_to(2)
      K.type("a = 1; b = 2")
      K.keys("return")
      assert.same(
        "x = 1\na = 1\nb = 2\ny = 2\nz = 3\n",
        K.file()
      )
      assert.same("browsing", K.state())
      assert.same("", K.draft())
      assert.same(4, K.position())
    end)

    spec_it(
        "IS4.3 Submit an empty draft: a replacement cleared "
        .. "to empty finishes, the position after it", function(
      
    )
      edit(2)
      K.keys("lctrl", "home")
      K.keys("lctrl", "k")
      K.keys("return")
      assert.same("x = 1\n\nz = 3\n", K.file())
      assert.is_nil(K.target())
      assert.same(3, K.position())
    end)
  end)

  describe("IS5.1 and IS5.3", function()
    spec_it("IS5.1 Begin a replacement: a refused Edit keeps "
        .. "the position and the empty field", function()
      open_file(GAPPED)
      edit(2)
      local on_empty = {
        K.position(),
        K.draft(),
        K.message() ~= nil,
        K.target()
      }
      K.browse_to_end()
      K.keys("f2")
      assert.same({
        2,
        "",
        true
      }, on_empty)
      assert.is_not_nil(K.message())
      assert.same("end", K.position())
      assert.same("", K.draft())
      assert.is_nil(K.target())
      assert.same(GAPPED, K.file())
    end)

    spec_it("IS5.1 Begin a replacement: the yellow highlight "
        .. "stays on the target through browsing", function()
      open_file()
      edit(1)
      K.keys("lctrl", "down")
      K.keys("lctrl", "down")
      local away = K.highlights()
      K.keys("lctrl", "down")
      local at_end = K.highlights()
      assert.same({ 1 }, away.yellow)
      assert.same({ 3 }, away.white)
      assert.same("end", K.position())
      assert.same({ 1 }, at_end.yellow)
      assert.same({ }, at_end.white)
      assert.same(1, K.target())
    end)

    spec_it("IS5.3 Accept a replacement: an incorrect draft is "
        .. "rejected, browsed away, the target kept", function()
      open_file()
      edit(1)
      K.type(" = 2")
      local browsed = pcall(K.browse_to, 3)
      K.keys("return")
      assert.is_true(browsed)
      assert.same(FILE, K.file())
      assert.same("replacing", K.state())
      assert.same(1, K.target())
      assert.same("x = 1 = 2", K.draft())
    end)
  end)

  describe("IS5.4", function()
    before_each(function()
      open_file(FOUR)
    end)

    spec_it("IS5.4 Finish a replacement: browsed further down, "
        .. "the position moves to the block after it", function(
      
    )
      edit(2)
      K.type("0")
      local browsed = pcall(K.browse_to, 4)
      K.keys("return")
      assert.is_true(browsed)
      assert.same("x = 1\ny = 20\nz = 3\nw = 4\n", K.file())
      assert.same("browsing", K.state())
      assert.is_nil(K.target())
      assert.same("", K.draft())
      assert.same(3, K.position())
    end)

    spec_it("IS5.4 Finish a replacement: browsed further up, "
        .. "the position moves to the block after it", function(
      
    )
      edit(3)
      K.type("0")
      local browsed = pcall(K.browse_to, 1)
      K.keys("return")
      assert.is_true(browsed)
      assert.same("x = 1\ny = 2\nz = 30\nw = 4\n", K.file())
      assert.same(4, K.position())
    end)

    spec_it("IS5.4 Finish a replacement: of the last block, "
        .. "browsed away, the position moves to the end",
        function()
      edit(4)
      K.type("0")
      local browsed = pcall(K.browse_to, 1)
      K.keys("return")
      assert.is_true(browsed)
      assert.same("x = 1\ny = 2\nz = 3\nw = 40\n", K.file())
      assert.same("end", K.position())
    end)
  end)

  describe("IS5.5 and IS5.6", function()
    spec_it("IS5.5 Restore the original draft: the reload puts "
        .. "the cursor at the draft's end", function()
      open_file()
      edit(2)
      K.type("0")
      K.keys("home")
      K.keys("f2")
      assert.same("y = 2", K.draft())
      assert.same({
        1,
        6
      }, { K.cursor() })
      assert.same(2, K.target())
      assert.same(FILE, K.file())
    end)

    spec_it(
        "IS5.6 Switch the replacement target: the cursor is "
        .. "at the end of the loaded draft", function()
      open_file("x = 1\nyy = 22\n")
      edit(1)
      local browsed = pcall(K.browse_to, 2)
      K.keys("f2")
      assert.is_true(browsed)
      assert.same(2, K.target())
      assert.same("yy = 22", K.draft())
      assert.same({
        1,
        8
      }, { K.cursor() })
      assert.same("x = 1\nyy = 22\n", K.file())
    end)

    spec_it("IS5.6 Switch the replacement target: Edit on an "
        .. "empty line is refused, the target kept", function()
      open_file(GAPPED)
      edit(1)
      local browsed = pcall(K.browse_to, 2)
      K.keys("f2")
      assert.is_true(browsed)
      assert.same(1, K.target())
      assert.same("x = 1", K.draft())
      assert.same(2, K.position())
      assert.is_not_nil(K.message())
      assert.same(GAPPED, K.file())
    end)

    spec_it("IS5.6 Switch the replacement target: Edit at the "
        .. "end position is refused, the target kept", function(
      
    )
      open_file(GAPPED)
      edit(1)
      -- Ctrl+Down browses while the field holds the draft
      K.keys("lctrl", "down")
      K.keys("lctrl", "down")
      K.keys("lctrl", "down")
      K.keys("f2")
      assert.same(1, K.target())
      assert.same("x = 1", K.draft())
      assert.same("end", K.position())
      assert.is_not_nil(K.message())
      assert.same(GAPPED, K.file())
    end)
  end)

  describe("IS5.7", function()
    before_each(function()
      open_file()
    end)

    spec_it("IS5.7 Cancel an edit with Escape: an unmodified "
        .. "replacement is dropped at once", function()
      edit(2)
      K.keys("escape")
      assert.same("browsing", K.state())
      assert.is_nil(K.target())
      assert.same("", K.draft())
      assert.same(2, K.position())
      assert.same("editor", K.app_state())
      assert.same(FILE, K.file())
    end)

    spec_it("IS5.7 Cancel an edit with Escape: a replacement "
        .. "with invalid syntax is dropped at once", function()
      edit(2)
      K.type(" = = (")
      K.keys("escape")
      assert.same("browsing", K.state())
      assert.is_nil(K.target())
      assert.same("", K.draft())
      assert.same("editor", K.app_state())
      assert.same(FILE, K.file())
    end)

    spec_it("IS5.7 Cancel an edit with Escape: while a notice "
        .. "shows, Escape dismisses it and keeps the edit",
        function()
      edit(1)
      K.type("0")
      local browsed = pcall(K.browse_to, 3)
      K.keys("f2")
      local refused = K.message()
      K.keys("escape")
      assert.is_true(browsed)
      assert.is_not_nil(refused)
      assert.is_nil(K.message())
      assert.same("replacing", K.state())
      assert.same(1, K.target())
      assert.same("x = 10", K.draft())
      assert.same(FILE, K.file())
    end)

    spec_it(
        "IS5.7 Cancel an edit with Escape: after the notice "
        .. "is dismissed, the next Escape aborts", function()
      edit(1)
      K.type("0")
      local browsed = pcall(K.browse_to, 3)
      K.keys("f2")
      K.keys("escape")
      local kept = K.state()
      K.keys("escape")
      assert.is_true(browsed)
      assert.same("replacing", kept)
      assert.same("browsing", K.state())
      assert.is_nil(K.target())
      assert.same("", K.draft())
      assert.same("editor", K.app_state())
      assert.same(FILE, K.file())
    end)

    spec_it("IS5.7 Cancel an edit with Escape: after a size "
        .. "refusal, Escape dismisses its notice first",
        function()
      K.browse_to_end()
      K.type_lines(K.block_lines(15))
      K.keys("return")
      local refused = K.message()
      local kept = K.draft()
      K.keys("escape")
      local dismissed = {
        K.state(),
        K.draft(),
        K.message() or "none"
      }
      K.keys("escape")
      assert.is_not_nil(refused)
      assert.same({
        "inserting",
        kept,
        "none"
      }, dismissed)
      assert.same("browsing", K.state())
      assert.same("", K.draft())
      assert.same("editor", K.app_state())
      assert.same(FILE, K.file())
    end)

    spec_it("IS5.7 Cancel an edit with Escape: after a syntax "
        .. "failure, which shows no notice, one Escape aborts",
        function()
      K.browse_to_end()
      K.type("a = = 1")
      K.keys("return")
      local refused = {
        K.state(),
        K.draft(),
        K.message() or "none"
      }
      K.keys("escape")
      assert.same({
        "inserting",
        "a = = 1",
        "none"
      }, refused)
      assert.same("browsing", K.state())
      assert.same("", K.draft())
      assert.is_nil(K.target())
      assert.same("end", K.position())
      assert.same("editor", K.app_state())
      assert.same(FILE, K.file())
    end)

    spec_it("IS5.7 Cancel an edit with Escape: once browsing, "
        .. "the next Escape steps out of the file", function()
      edit(2)
      K.type("0")
      K.keys("escape")
      local aborted = K.app_state()
      K.keys("escape")
      assert.same("editor", aborted)
      assert.same("ready", K.app_state())
      assert.same(FILE, K.file())
    end)
  end)
end)
