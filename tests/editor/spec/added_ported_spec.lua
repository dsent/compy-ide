-- Cases the editor's pre-spec tests pinned and no spec test
-- covered, ported to the spec's keys (editor principles,
-- ratified). Keys only, through tests/helpers/editor_keys.lua.
-- Edit is F2; Ctrl+Up and Ctrl+Down browse.

local K = require("tests.helpers.editor_keys")
local marks = require("tests.helpers.spec_marks")
local spec_it, spec_gap = marks.spec_it, marks.spec_gap

local FILE = "x = 1\ny = 2\nz = 3\n"

local function open_file(text)
  K.reset({ ["main.lua"] = text or FILE })
  K.open()
end

describe("ported pre-spec cases #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  describe("IS3.8", function()
    spec_it("IS3.8 Position the text cursor: with the field "
        .. "empty, Ctrl+Home and Ctrl+End do not browse",
        function()
      open_file()
      K.browse_to(2)
      K.keys("lctrl", "end")
      local after_end = {
        K.position(),
        K.state(),
        K.draft()
      }
      K.keys("lctrl", "home")
      assert.same({
        2,
        "browsing",
        ""
      }, after_end)
      assert.same(2, K.position())
      assert.same("browsing", K.state())
      assert.same("", K.draft())
      assert.same(FILE, K.file())
    end)
  end)

  describe("IS2.3", function()
    spec_it("IS2.3 Browse during a replacement: an invalid "
        .. "changed draft browses away, kept and unsubmitted",
        function()
      open_file()
      K.browse_to(1)
      K.keys("f2")
      K.type(" = 2")
      K.keys("lctrl", "down")
      assert.same(2, K.position())
      assert.same("replacing", K.state())
      assert.same(1, K.target())
      assert.same("x = 1 = 2", K.draft())
      assert.same({
        1,
        10
      }, { K.cursor() })
      assert.same(FILE, K.file())
    end)
  end)

  describe("IS4.1", function()
    spec_it("IS4.1 Insert before a block: typed on an empty "
        .. "line between two blocks, the draft goes before it "
        .. "and the empty line stays", function()
      open_file("a = 1\n\nb = 2\n")
      K.browse_to(2)
      K.type("x = 0")
      K.keys("return")
      assert.same("a = 1\nx = 0\n\nb = 2\n", K.file())
      assert.same(4, K.blocks())
      assert.same(3, K.position())
      assert.same("browsing", K.state())
      assert.same("", K.draft())
    end)

    spec_it("IS4.1 Insert before a block: typed on a file's "
        .. "last line, an empty one, the draft goes before it "
        .. "and the empty line stays", function()
      open_file("a = 1\n\n")
      K.browse_to(2)
      K.type("b = 2")
      K.keys("return")
      assert.same("a = 1\nb = 2\n\n", K.file())
      assert.same(3, K.blocks())
      assert.same(3, K.position())
      assert.same("browsing", K.state())
    end)
  end)

  describe("IS2.2", function()
    spec_it("IS2.2 Keep the viewed block visible: a last block "
        .. "taller than the view, reached from the end, ends "
        .. "at the bottom", function()
      K.reset({ ["main.lua"] = "a = 1\n" .. K.block(32) })
      K.open()
      assert.same("end", K.position())
      K.keys("lctrl", "up")
      local rows = K.view_rows()
      local n, shown = K.rows_shown(2)
      assert.same(2, K.position())
      assert.same("end", rows[#rows])
      assert.is_true(shown < n)
    end)
  end)
end)
