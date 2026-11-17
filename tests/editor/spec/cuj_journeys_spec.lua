-- The core user journeys of file editing, CUJ1-CUJ7 (editor
-- principles, ratified), each walked with the spec's keys
-- and checked against its outcome. Keys only, through
-- tests/helpers/editor_keys.lua. Edit is F2. A step today's
-- editor cannot take is caught and asserted in the check.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_gap = marks.spec_gap
local spec_it = marks.spec_it

local FILE = "x = 1\ny = 2\nz = 3\n"

local function open_file(files)
  K.reset(files or { ["main.lua"] = FILE })
  K.open()
end

-- Browse to the end position with Ctrl+Down, which browses
-- while the field holds text too; bare Down then moves the
-- text cursor (IS2.1).
local function ctrl_to_end()
  for _ = 1, 200 do
    if K.position() == "end" then
      return
    end
    K.keys("lctrl", "down")
  end
  error("the end position was not reached")
end

describe("CUJ journeys #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  local REFS = {
    ["main.lua"] = "local m = require(\"mod\")\nx = 1\n",
    ["mod.lua"] = "y = 2\n"
  }

  spec_it("CUJ1 Begin Working on a File: a fresh open is " ..
      "browsing at the end with an empty field", function()
    open_file(REFS)
    assert.same("browsing", K.state())
    assert.same("end", K.position())
    assert.same("", K.draft())
  end)

  spec_it("CUJ1 Begin Working on a File: Ctrl+J follows a " ..
      "reference into its file", function()
    open_file(REFS)
    K.browse_to(1)
    K.keys("lctrl", "j")
    assert.same("mod.lua", K.file_name())
  end)

  spec_it("CUJ1 Begin Working on a File: Escape steps back "
      .. "to the caller and out", function()
    open_file(REFS)
    K.browse_to(1)
    K.keys("lctrl", "j")
    K.keys("escape")
    local back = {
      K.file_name(),
      K.position()
    }
    K.keys("escape")
    assert.same({
      "main.lua",
      1
    }, back)
    assert.same("ready", K.app_state())
  end)

  spec_it("CUJ1 Begin Working on a File: returning from a " ..
      "test run restores the file and position", function()
    open_file()
    K.browse_to(2)
    local before = {
      K.file_name(),
      K.position()
    }
    K.keys("lctrl", "t")
    K.keys("lctrl", "t")
    assert.same(before, {
      K.file_name(),
      K.position()
    })
  end)

  spec_it("CUJ2 Add Text Where It Belongs: before a block, "
      .. "past a syntax failure, in typing order", function()
    open_file()
    K.browse_to(2)
    K.type("a = = 1")
    K.keys("return")
    local refused = { K.cursor() }
    K.keys("delete")
    K.keys("delete")
    K.keys("return")
    K.type("b = 2")
    K.keys("return")
    assert.same({
      1,
      5
    }, refused)
    assert.same(
      "x = 1\na = 1\nb = 2\ny = 2\nz = 3\n",
      K.file()
    )
    assert.same("", K.draft())
    assert.same(4, K.position())
  end)

  spec_it("CUJ3 Revise a Block: Edit, Backspace at the end, "
      .. "submit, the position past it", function()
    open_file()
    K.browse_to(2)
    K.keys("f2")
    K.keys("backspace")
    K.type("5")
    K.keys("return")
    assert.same("x = 1\ny = 5\nz = 3\n", K.file())
    assert.same("browsing", K.state())
    assert.same("", K.draft())
    assert.same(3, K.position())
  end)

  spec_it("CUJ4 Consult Other Text During an Edit: browse " ..
      "away and back, the draft and target kept", function()
    open_file()
    K.browse_to(1)
    K.keys("f2")
    K.type("0")
    local browsed = pcall(K.browse_to, 3)
    local back = pcall(K.browse_to, 1)
    K.type("0")
    assert.is_true(browsed)
    assert.is_true(back)
    assert.same("replacing", K.state())
    assert.same(1, K.target())
    assert.same("x = 100", K.draft())
    assert.same(FILE, K.file())
  end)

  spec_it("CUJ5 Recover the Original Text: Escape, and Ctrl+Z "
      .. "brings the edit back", function()
    open_file()
    K.browse_to(2)
    K.keys("f2")
    K.type(" +")
    K.keys("escape")
    local aborted = {
      K.state(),
      K.file(),
      K.draft()
    }
    K.keys("lctrl", "z")
    assert.same({
      "browsing",
      FILE,
      ""
    }, aborted)
    assert.same("replacing", K.state())
    assert.same("y = 2 +", K.draft())
    assert.same(2, K.target())
  end)

  spec_it("CUJ5 Recover the Original Text: Edit on the " ..
      "target reloads the original at its end", function()
    open_file()
    K.browse_to(2)
    K.keys("f2")
    K.type(" +")
    local back = pcall(K.browse_to, 2)
    K.keys("f2")
    assert.is_true(back)
    assert.same("replacing", K.state())
    assert.same("y = 2", K.draft())
    assert.same({
      1,
      6
    }, { K.cursor() })
  end)

  spec_it("CUJ5 Recover the Original Text: Ctrl+Y redoes " ..
      "what Ctrl+Z brought back", function()
    open_file()
    K.browse_to(2)
    K.keys("f2")
    K.type(" +")
    K.keys("escape")
    K.keys("lctrl", "z")
    K.keys("lctrl", "y")
    assert.same("browsing", K.state())
    assert.same("", K.draft())
    assert.same(FILE, K.file())
  end)

  spec_it("CUJ6 Reuse Text Elsewhere: copy a block into a " ..
      "draft and append it, the source in place", function()
    open_file()
    K.browse_to(1)
    K.keys("lctrl", "insert")
    local copied = K.draft()
    ctrl_to_end()
    K.keys("return")
    assert.same("x = 1", copied)
    assert.same(FILE .. "x = 1\n", K.file())
    assert.same("", K.draft())
  end)

  spec_it("CUJ7 Relocate, Reorder, or Remove a Block: cut, "
      .. "relocate, take it back", function()
    open_file()
    K.browse_to(1)
    K.keys("lctrl", "delete")
    local cut = {
      K.state(),
      K.draft()
    }
    local browsed = pcall(ctrl_to_end)
    K.keys("return")
    local moved = K.file()
    K.keys("lctrl", "z")
    assert.same({
      "inserting",
      "x = 1"
    }, cut)
    assert.is_true(browsed)
    assert.same("y = 2\nz = 3\nx = 1\n", moved)
    assert.same("y = 2\nz = 3\n", K.file())
  end)

  spec_it("CUJ7 Relocate, Reorder, or Remove a Block: Alt+Up "
      .. "moves the block, the highlight stays on it, Ctrl+Z "
      .. "puts it back", function()
    open_file()
    K.browse_to(2)
    K.keys("lalt", "up")
    local moved = {
      K.file(),
      K.position()
    }
    K.keys("lctrl", "z")
    assert.same({
      "y = 2\nx = 1\nz = 3\n",
      1
    }, moved)
    assert.same(FILE, K.file())
  end)
end)
