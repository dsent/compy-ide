-- IS4 Inserting Lua text, IS5 Replacing and restoring a Lua
-- block (editor principles, ratified). Keys only, through
-- tests/helpers/editor_keys.lua. Edit is F2.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it, spec_gap = marks.spec_it, marks.spec_gap

local FILE = "x = 1\ny = 2\nz = 3\n"

local function open_file(text)
  K.reset({ ["main.lua"] = text or FILE })
  K.open()
end

--- Edit (F2) on block `b`.
local function edit(b)
  K.browse_to(b)
  K.keys("f2")
end

describe("IS4 and IS5 #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  describe("IS4", function()
    before_each(function()
      open_file()
    end)

    spec_gap(
        "IS4.1 Insert before a block: the draft goes before "
        .. "it, and the position stays on it", function(gap)
      K.browse_to(2)
      K.type("a = 1")
      K.keys("return")
      gap(function()
        assert.same("x = 1\na = 1\ny = 2\nz = 3\n", K.file())
        assert.same("browsing", K.state())
        assert.same(3, K.position())
      end)
    end)

    spec_it("IS4.1 Insert before a block: Ctrl+Z takes the " ..
        "insertion back in one press", function()
      K.browse_to(2)
      K.type("a = 1")
      K.keys("return")
      K.keys("lctrl", "z")
      assert.same(FILE, K.file())
    end)

    spec_it("IS4.2 Append after the last block: the draft goes "
        .. "at the end, and the position stays there", function(
      
    )
      K.browse_to_end()
      K.type("a = 1")
      K.keys("return")
      assert.same(FILE .. "a = 1\n", K.file())
      assert.same("browsing", K.state())
      assert.same("", K.draft())
      assert.same("end", K.position())
    end)

    spec_it("IS4.2 Append after the last block: Ctrl+Z takes "
        .. "the append back in one press", function()
      K.browse_to_end()
      K.type("a = 1; b = 2")
      K.keys("return")
      K.keys("lctrl", "z")
      assert.same(FILE, K.file())
    end)

    spec_gap("IS4.3 Submit an empty draft: Enter on a block "
        .. "inserts an empty line before it", function(gap)
      K.browse_to(2)
      K.keys("return")
      gap(function()
        assert.same("x = 1\n\ny = 2\nz = 3\n", K.file())
        assert.same("browsing", K.state())
        assert.same(3, K.position())
      end)
    end)

    spec_gap("IS4.3 Submit an empty draft: at the end, Enter "
        .. "appends an empty line", function(gap)
      K.browse_to_end()
      K.keys("return")
      gap(function()
        assert.same(FILE .. "\n", K.file())
        assert.same("end", K.position())
      end)
    end)

    spec_gap(
        "IS4.3 Submit an empty draft: a replacement cleared "
        .. "to empty leaves an empty line", function(gap)
      edit(2)
      K.keys("lctrl", "home")
      K.keys("lctrl", "k")
      K.keys("return")
      gap(function()
        assert.same("x = 1\n\nz = 3\n", K.file())
        assert.same("browsing", K.state())
      end)
    end)
  end)

  describe("IS5.1", function()
    before_each(function()
      open_file("x = 1\n\ny = 2\n")
    end)

    spec_gap("IS5.1 Begin a replacement: Edit loads the block, "
        .. "cursor at its end", function(gap)
      edit(1)
      gap(function()
        assert.same("replacing", K.state())
        assert.same(1, K.target())
        assert.same("x = 1", K.draft())
        assert.same({
          1,
          6
        }, { K.cursor() })
        assert.same({ 1 }, K.highlights().yellow)
        assert.same("x = 1\n\ny = 2\n", K.file())
      end)
    end)

    spec_gap("IS5.1 Begin a replacement: Edit is refused on an "
        .. "empty line and at the end", function(gap)
      edit(2)
      local on_empty = {
        K.state(),
        K.message()
      }
      K.restart()
      K.open()
      K.browse_to_end()
      K.keys("f2")
      gap(function()
        assert.same("browsing", on_empty[1])
        assert.is_not_nil(on_empty[2])
        assert.same("browsing", K.state())
        assert.is_not_nil(K.message())
      end)
    end)

    spec_gap(
        "IS5.1 Begin a replacement: Edit is refused during " ..
        "an insertion", function(gap)
      K.browse_to_end()
      K.type("a = 1")
      local browsed = pcall(K.browse_to, 1)
      K.keys("f2")
      gap(function()
        assert.is_true(browsed)
        assert.same("inserting", K.state())
        assert.same("a = 1", K.draft())
        assert.is_not_nil(K.message())
      end)
    end)
  end)

  describe("IS5.2 to IS5.4", function()
    before_each(function()
      open_file()
    end)

    spec_gap(
        "IS5.2 Retain the original while drafting: the file "
        .. "keeps the block while the draft changes", function(
      gap
    )
      edit(2)
      K.type("0")
      local drafting = K.file()
      -- and an invalid submission changes nothing either; it
      -- fails before the draft's end (IS3.4, not IS3.5)
      K.type(" = 1")
      K.keys("return")
      gap(function()
        assert.same("y = 20 = 1", K.draft())
        assert.same(FILE, drafting)
        assert.same(FILE, K.file())
        assert.same("replacing", K.state())
      end)
    end)

    spec_gap(
        "IS5.3 Accept a replacement: Enter puts the draft in "
        .. "the target's place, even browsed away", function(
      gap
    )
      edit(1)
      K.type("0; w = 4")
      -- browsing during an edit is IS2.3's; it may fail here
      local browsed = pcall(K.browse_to, 3)
      K.keys("return")
      gap(function()
        assert.is_true(browsed)
        assert.same("x = 10\nw = 4\ny = 2\nz = 3\n", K.file())
      end)
    end)

    spec_gap(
        "IS5.4 Finish a replacement: the position moves past "
        .. "the replaced blocks", function(gap)
      edit(1)
      K.type("0; w = 4")
      K.keys("return")
      gap(function()
        assert.same("browsing", K.state())
        assert.is_nil(K.target())
        assert.same("", K.draft())
        assert.same(3, K.position())
      end)
    end)

    spec_gap("IS5.4 Finish a replacement: Ctrl+Z takes the " ..
        "accepted replacement back in one press", function(gap)
      edit(1)
      K.keys("end")
      K.type("0")
      K.keys("return")
      local accepted = K.file()
      K.keys("lctrl", "z")
      gap(function()
        assert.same("x = 10\ny = 2\nz = 3\n", accepted)
        assert.same(FILE, K.file())
        assert.same("browsing", K.state())
      end)
    end)
  end)

  describe("IS5.5 to IS5.7", function()
    before_each(function()
      open_file()
    end)

    spec_gap("IS5.5 Restore the original draft: Edit on the "
        .. "target reloads it, and Ctrl+Z takes that back",
        function(gap)
      edit(2)
      K.type("0")
      K.keys("f2")
      local reloaded = K.draft()
      K.keys("lctrl", "z")
      gap(function()
        assert.same("y = 2", reloaded)
        assert.same("y = 20", K.draft())
        assert.same("replacing", K.state())
      end)
    end)

    spec_gap(
        "IS5.6 Switch the replacement target: Edit elsewhere "
        .. "on an unchanged draft moves the target", function(
      gap
    )
      edit(1)
      local browsed = pcall(K.browse_to, 3)
      K.keys("f2")
      gap(function()
        assert.is_true(browsed)
        assert.same(3, K.target())
        assert.same("z = 3", K.draft())
      end)
    end)

    spec_gap(
        "IS5.6 Switch the replacement target: Ctrl+Z takes " ..
        "the switch back", function(gap)
      edit(1)
      local browsed = pcall(K.browse_to, 3)
      K.keys("f2")
      K.keys("lctrl", "z")
      gap(function()
        assert.is_true(browsed)
        assert.same(1, K.target())
        assert.same("x = 1", K.draft())
        assert.same(3, K.position())
      end)
    end)

    spec_gap(
        "IS5.6 Switch the replacement target: once the draft "
        .. "is changed, Edit elsewhere is refused", function(
      gap
    )
      edit(1)
      K.type("0")
      local browsed = pcall(K.browse_to, 3)
      K.keys("f2")
      gap(function()
        assert.is_true(browsed)
        assert.same(1, K.target())
        assert.same("x = 10", K.draft())
        assert.is_not_nil(K.message())
      end)
    end)

    spec_gap(
        "IS5.7 Cancel an edit with Escape: a replacement is "
        .. "dropped at once, the file as it was", function(gap)
      edit(2)
      K.type("0")
      K.keys("escape")
      gap(function()
        assert.same("browsing", K.state())
        assert.is_nil(K.target())
        assert.same("", K.draft())
        assert.same(FILE, K.file())
        assert.same("editor", K.app_state())
        -- the white highlight stays where it was
        assert.same(2, K.position())
      end)
    end)

    spec_gap(
        "IS5.7 Cancel an edit with Escape: an insertion too, "
        .. "and Ctrl+Z brings it back", function(gap)
      K.browse_to_end()
      K.type("a = = 1")
      K.keys("escape")
      local dropped = K.draft()
      K.keys("lctrl", "z")
      gap(function()
        assert.same("", dropped)
        assert.same("a = = 1", K.draft())
        assert.same(FILE, K.file())
      end)
    end)
  end)
end)
