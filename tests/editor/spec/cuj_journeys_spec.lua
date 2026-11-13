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

describe("CUJ journeys #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  local REFS = {
    ["main.lua"] = "local m = require(\"mod\")\nx = 1\n",
    ["mod.lua"] = "y = 2\n"
  }

  spec_gap("CUJ1 Begin Working on a File: a fresh open is " ..
      "browsing at the end with an empty field", function(gap)
    open_file(REFS)
    gap(function()
      assert.same("browsing", K.state())
      assert.same("end", K.position())
      assert.same("", K.draft())
    end)
  end)

  spec_it("CUJ1 Begin Working on a File: Ctrl+J follows a " ..
      "reference into its file", function()
    open_file(REFS)
    K.browse_to(1)
    K.keys("lctrl", "j")
    assert.same("mod.lua", K.file_name())
  end)

  spec_gap("CUJ1 Begin Working on a File: Escape steps back "
      .. "to the caller and out", function(gap)
    open_file(REFS)
    K.browse_to(1)
    K.keys("lctrl", "j")
    K.keys("escape")
    local back = {
      K.file_name(),
      K.position()
    }
    K.keys("escape")
    gap(function()
      assert.same({
        "main.lua",
        1
      }, back)
      assert.same("ready", K.app_state())
    end)
  end)

  spec_gap("CUJ1 Begin Working on a File: returning from a " ..
      "test run restores the file and position", function(gap)
    open_file()
    K.browse_to(2)
    local before = {
      K.file_name(),
      K.position()
    }
    K.keys("lctrl", "t")
    K.keys("lctrl", "t")
    gap(function()
      assert.same(before, {
        K.file_name(),
        K.position()
      })
    end)
  end)

  spec_gap("CUJ2 Add Text Where It Belongs: before a block, "
      .. "past a syntax failure, in typing order", function(gap)
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
    gap(function()
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
  end)

  spec_gap("CUJ3 Revise a Block: Edit, Backspace at the end, "
      .. "submit, the position past it", function(gap)
    open_file()
    K.browse_to(2)
    K.keys("f2")
    K.keys("backspace")
    K.type("5")
    K.keys("return")
    gap(function()
      assert.same("x = 1\ny = 5\nz = 3\n", K.file())
      assert.same("browsing", K.state())
      assert.same("", K.draft())
      assert.same(3, K.position())
    end)
  end)

  spec_gap("CUJ4 Consult Other Text During an Edit: browse " ..
      "away and back, the draft and target kept", function(gap)
    open_file()
    K.browse_to(1)
    K.keys("f2")
    K.type("0")
    local browsed = pcall(K.browse_to, 3)
    local back = pcall(K.browse_to, 1)
    K.type("0")
    gap(function()
      assert.is_true(browsed)
      assert.is_true(back)
      assert.same("replacing", K.state())
      assert.same(1, K.target())
      assert.same("x = 100", K.draft())
      assert.same(FILE, K.file())
    end)
  end)

  spec_gap("CUJ5 Recover the Original Text: Escape, and Ctrl+Z "
      .. "brings the edit back", function(gap)
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
    gap(function()
      assert.same({
        "browsing",
        FILE,
        ""
      }, aborted)
      assert.same("replacing", K.state())
      assert.same("y = 2 +", K.draft())
      assert.same(2, K.target())
    end)
  end)

  spec_gap("CUJ5 Recover the Original Text: Edit on the " ..
      "target reloads the original at its end", function(gap)
    open_file()
    K.browse_to(2)
    K.keys("f2")
    K.type(" +")
    local back = pcall(K.browse_to, 2)
    K.keys("f2")
    gap(function()
      assert.is_true(back)
      assert.same("replacing", K.state())
      assert.same("y = 2", K.draft())
      assert.same({
        1,
        6
      }, { K.cursor() })
    end)
  end)

  spec_gap("CUJ5 Recover the Original Text: Ctrl+Y redoes " ..
      "what Ctrl+Z brought back", function(gap)
    open_file()
    K.browse_to(2)
    K.keys("f2")
    K.type(" +")
    K.keys("escape")
    K.keys("lctrl", "z")
    K.keys("lctrl", "y")
    gap(function()
      assert.same("browsing", K.state())
      assert.same("", K.draft())
      assert.same(FILE, K.file())
    end)
  end)

  spec_gap("CUJ6 Reuse Text Elsewhere: copy a block into a " ..
      "draft and append it, the source in place", function(gap)
    open_file()
    K.browse_to(1)
    K.keys("lctrl", "insert")
    local copied = K.draft()
    K.browse_to_end()
    K.keys("return")
    gap(function()
      assert.same("x = 1", copied)
      assert.same(FILE .. "x = 1\n", K.file())
      assert.same("", K.draft())
    end)
  end)

  spec_gap("CUJ7 Relocate, Reorder, or Remove a Block: cut, "
      .. "relocate, take it back", function(gap)
    open_file()
    K.browse_to(1)
    K.keys("lctrl", "delete")
    local cut = {
      K.state(),
      K.draft()
    }
    local browsed = pcall(K.browse_to_end)
    K.keys("return")
    local moved = K.file()
    K.keys("lctrl", "z")
    gap(function()
      assert.same({
        "inserting",
        "x = 1"
      }, cut)
      assert.is_true(browsed)
      assert.same("y = 2\nz = 3\nx = 1\n", moved)
      assert.same("y = 2\nz = 3\n", K.file())
    end)
  end)

  spec_gap("CUJ7 Relocate, Reorder, or Remove a Block: Alt+Up "
      .. "moves the block, the highlight stays on it, Ctrl+Z "
      .. "puts it back", function(gap)
    open_file()
    K.browse_to(2)
    K.keys("lalt", "up")
    local moved = {
      K.file(),
      K.position()
    }
    K.keys("lctrl", "z")
    gap(function()
      assert.same({
        "y = 2\nx = 1\nz = 3\n",
        1
      }, moved)
      assert.same(FILE, K.file())
    end)
  end)
end)
