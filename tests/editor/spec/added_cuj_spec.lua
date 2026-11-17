-- The core user journeys of file editing, CUJ1-CUJ7 (editor
-- principles, ratified): the paths the tests of
-- cuj_journeys_spec.lua leave out. Keys only, through
-- tests/helpers/editor_keys.lua. Edit is F2; copy is
-- Ctrl+Ins; cut is Ctrl+Delete; move is Alt+Up and Alt+Down;
-- submit and retain is Shift+Ins.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it, spec_gap = marks.spec_it, marks.spec_gap

local FILE = "x = 1\ny = 2\nz = 3\n"

local function open_file(files)
  K.reset(files or { ["main.lua"] = FILE })
  K.open()
end

-- Browse to the end position with Ctrl+Down, which browses
-- while the field holds text too (IS2.1).
local function ctrl_to_end()
  for _ = 1, 200 do
    if K.position() == "end" then
      return
    end
    K.keys("lctrl", "down")
  end
  error("the end position was not reached")
end

describe("CUJ journeys, added #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  spec_it("CUJ1 Begin Working on a File: a refused file " ..
      "leaves the console, and the next opens", function()
    K.reset({
      ["main.lua"] = FILE,
      ["bad8.lua"] = "s = '\255'\n"
    })
    K.open("bad8.lua")
    local refused = K.app_state()
    K.open()
    assert.same("ready", refused)
    assert.same("editor", K.app_state())
    assert.same("main.lua", K.file_name())
    assert.same("end", K.position())
    assert.same("s = '\255'\n", K.file("bad8.lua"))
  end)

  spec_it("CUJ1 Begin Working on a File: a file with an " ..
      "oversized block opens ready to append", function()
    open_file({ ["main.lua"] = K.block(16) .. "y = 2\n" })
    local opened = {
      K.state(),
      K.position(),
      K.blocks()
    }
    K.type("z = 3")
    K.keys("return")
    assert.same({
      "browsing",
      "end",
      2
    }, opened)
    assert.same(K.block(16) .. "y = 2\nz = 3\n", K.file())
  end)

  spec_it("CUJ1 Begin Working on a File: a failed write " ..
      "keeps the draft, and the next submission lands",
      function()
    open_file()
    K.type("w = 4")
    K.fail_writes("the card is full")
    K.keys("return")
    local failed = {
      K.draft(),
      K.file(),
      K.position(),
      K.message() ~= nil
    }
    K.fail_writes(nil)
    K.keys("return")
    assert.same({
      "w = 4",
      FILE,
      "end",
      true
    }, failed)
    assert.same(FILE .. "w = 4\n", K.file())
    assert.same("browsing", K.state())
  end)

  spec_it("CUJ2 Add Text Where It Belongs: at the beginning "
      .. "of the file, in typing order", function()
    open_file()
    K.browse_to(1)
    K.type("a = 1")
    K.keys("return")
    K.type("b = 2")
    K.keys("return")
    assert.same("a = 1\nb = 2\n" .. FILE, K.file())
    assert.same("browsing", K.state())
    assert.same("", K.draft())
    assert.same(3, K.position())
  end)

  spec_it("CUJ2 Add Text Where It Belongs: a draft " ..
      "incomplete at its end continues on new lines", function()
    open_file()
    K.type("if x then")
    K.keys("return")
    local continued = {
      K.draft(),
      { K.cursor() },
      K.file(),
      K.state()
    }
    K.type("y = 1")
    K.keys("return")
    K.type("end")
    K.keys("return")
    assert.same({
      "if x then\n",
      {
        2,
        1
      },
      FILE,
      "inserting"
    }, continued)
    assert.same(FILE .. "if x then\n  y = 1\nend\n", K.file())
    assert.same("browsing", K.state())
    assert.same("end", K.position())
  end)

  spec_it("CUJ3 Revise a Block: Edit on another block " ..
      "before any change switches, and that one is revised",
      function()
    open_file()
    K.browse_to(1)
    K.keys("f2")
    K.keys("lctrl", "down")
    K.keys("lctrl", "down")
    K.keys("f2")
    local switched = {
      K.target(),
      K.draft()
    }
    K.keys("backspace")
    K.type("4")
    K.keys("return")
    assert.same({
      3,
      "z = 3"
    }, switched)
    assert.same("x = 1\ny = 2\nz = 4\n", K.file())
    assert.same("browsing", K.state())
    assert.same("end", K.position())
  end)

  spec_it("CUJ4 Consult Other Text During an Edit: Edit " ..
      "elsewhere is refused once modified, typing resumes",
      function()
    open_file()
    K.browse_to(1)
    K.keys("f2")
    K.type("0")
    K.keys("lctrl", "down")
    K.keys("lctrl", "down")
    K.keys("f2")
    local refused = {
      K.target(),
      K.draft(),
      K.position(),
      K.message() ~= nil
    }
    K.type("0")
    local resumed = K.draft()
    K.keys("return")
    assert.same({
      1,
      "x = 10",
      3,
      true
    }, refused)
    assert.same("x = 100", resumed)
    assert.same("x = 100\ny = 2\nz = 3\n", K.file())
    assert.same(2, K.position())
  end)

  spec_it("CUJ5 Recover the Original Text: Escape drops an " ..
      "unwanted insertion from any browsing position", function(
    
  )
    open_file()
    K.type("a = = 1")
    K.keys("lctrl", "up")
    K.keys("lctrl", "up")
    K.keys("escape")
    assert.same("browsing", K.state())
    assert.same("", K.draft())
    assert.same(2, K.position())
    assert.same("editor", K.app_state())
    assert.same(FILE, K.file())
  end)

  spec_it("CUJ5 Recover the Original Text: Ctrl+Z puts back "
      .. "the text a mistaken submission replaced", function()
    open_file()
    K.browse_to(2)
    K.keys("f2")
    K.type("0")
    K.keys("return")
    local mistaken = K.file()
    K.keys("lctrl", "z")
    local back = K.file()
    K.keys("lctrl", "y")
    assert.same("x = 1\ny = 20\nz = 3\n", mistaken)
    assert.same(FILE, back)
    assert.same(mistaken, K.file())
  end)

  spec_it("CUJ6 Reuse Text Elsewhere: copy into a modified " ..
      "replacement, a move refused, the target replaced",
      function()
    open_file()
    K.browse_to(1)
    K.keys("f2")
    K.type("0")
    K.keys("lctrl", "down")
    K.keys("lctrl", "down")
    K.keys("lctrl", "insert")
    local copied = {
      K.draft(),
      K.target()
    }
    K.keys("lalt", "up")
    local refused = {
      K.file(),
      K.target(),
      K.message() ~= nil
    }
    K.keys("return")
    assert.same({
      "x = 10\nz = 3",
      1
    }, copied)
    assert.same({
      FILE,
      1,
      true
    }, refused)
    assert.same("x = 10\nz = 3\ny = 2\nz = 3\n", K.file())
    assert.same("browsing", K.state())
    assert.same(3, K.position())
  end)

  spec_it("CUJ6 Reuse Text Elsewhere: several copies with " ..
      "typing around them, the sources in place", function()
    open_file()
    K.browse_to(1)
    K.keys("lctrl", "insert")
    K.type(" + 1")
    K.keys("lctrl", "down")
    K.keys("lctrl", "insert")
    K.type("0")
    local draft = K.draft()
    ctrl_to_end()
    K.keys("return")
    assert.same("x = 1 + 1\ny = 20", draft)
    assert.same(FILE .. "x = 1 + 1\ny = 20\n", K.file())
    assert.same("browsing", K.state())
    assert.same("", K.draft())
  end)

  spec_it("CUJ6 Reuse Text Elsewhere: Shift+Ins submits the "
      .. "copy and keeps it for the next use", function()
    open_file()
    K.browse_to(1)
    K.keys("lctrl", "insert")
    ctrl_to_end()
    K.keys("lshift", "insert")
    local once = {
      K.file(),
      K.draft(),
      K.state()
    }
    K.keys("lshift", "insert")
    assert.same({
      FILE .. "x = 1\n",
      "x = 1",
      "inserting"
    }, once)
    assert.same(FILE .. "x = 1\nx = 1\n", K.file())
    assert.same("x = 1", K.draft())
    assert.same({
      1,
      6
    }, { K.cursor() })
  end)

  spec_it("CUJ7 Relocate, Reorder, or Remove a Block: a " ..
      "block is reordered during an insertion", function()
    open_file()
    K.type("a = 1")
    K.keys("lctrl", "up")
    K.keys("lctrl", "up")
    K.keys("lalt", "down")
    local moved = {
      K.file(),
      K.draft(),
      K.position()
    }
    K.keys("return")
    assert.same({
      "x = 1\nz = 3\ny = 2\n",
      "a = 1",
      3
    }, moved)
    assert.same("x = 1\nz = 3\na = 1\ny = 2\n", K.file())
  end)

  spec_it("CUJ7 Relocate, Reorder, or Remove a Block: Ctrl+Y "
      .. "redoes an undone relocation", function()
    open_file()
    K.browse_to(1)
    K.keys("lctrl", "delete")
    ctrl_to_end()
    K.keys("return")
    local relocated = K.file()
    K.keys("lctrl", "z")
    local undone = K.file()
    K.keys("lctrl", "y")
    assert.same("y = 2\nz = 3\nx = 1\n", relocated)
    assert.same("y = 2\nz = 3\n", undone)
    assert.same(relocated, K.file())
  end)

  spec_it("CUJ7 Relocate, Reorder, or Remove a Block: Ctrl+Y "
      .. "redoes an undone reorder", function()
    open_file()
    K.browse_to(3)
    K.keys("lalt", "up")
    K.keys("lctrl", "z")
    local undone = K.file()
    K.keys("lctrl", "y")
    assert.same(FILE, undone)
    assert.same("x = 1\nz = 3\ny = 2\n", K.file())
    assert.same(2, K.position())
  end)
end)
