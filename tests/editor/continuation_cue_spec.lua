-- The continuation cue (FR4.8, IS2.2, IS3.13; the maintainer's
-- ruling of November 15, 2026), read from the real draw
-- (K.screen): at an edge of the document view beyond which
-- rows of the browsed block or of the replacement target lie,
-- and at an edge of the field beyond which rows of the draft
-- lie, the edge row fades into its own background, and its
-- last column carries `^` (top) or `v` (bottom), the glyph
-- half opaque on a box a quarter opaque. A block the view
-- merely cuts has none, and a notice covers the one at the
-- view's bottom edge until the next key.

local K = require("tests.helpers.editor_keys")

local C = require("tests.helpers.screen_cues")
local view_cfg, theme, is = C.view_cfg, C.theme, C.is
local view_cues, field_cues = C.view_cues, C.field_cues
local view_edges, check = C.view_edges, C.check

describe("the continuation cue #editor", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  before_each(function()
    K.reset({
      ["main.lua"] = "x = 1\n\nif a then\n  b = 1\nend\n",
      ["tall.lua"] = "a = 1\n" .. K.block(24) .. "b = 2\n",
      ["target.lua"] = "a = 1\n" .. K.block(14)
          .. "b = 2\nc = 3\nd = 4\n",
      ["empty.lua"] = "",
    })
  end)

  describe("in the document view", function()
    it("marks the bottom edge while the browsed block goes on "
        .. "below it, and no other", function()
      K.open("tall.lua")
      K.browse_to(1)
      K.keys("lctrl", "down")
      assert.same(2, K.position())
      local c = view_cues(K.screen())
      local _, bottom = view_edges()
      assert.is_nil(c.top)
      check(c.bottom, "v", bottom, { theme().highlight })
    end)

    it("marks the top edge while the browsed block goes on "
        .. "above it, and no other", function()
      K.open("tall.lua")
      K.browse_to(3)
      K.keys("lctrl", "up")
      assert.same(2, K.position())
      local c = view_cues(K.screen())
      local top = view_edges()
      assert.is_nil(c.bottom)
      check(c.top, "^", top, { theme().highlight })
    end)

    it("marks both edges of a block cut at both", function()
      K.open("tall.lua")
      K.browse_to(1)
      for _ = 1, 4 do
        K.keys("lctrl", "down")
      end
      local c = view_cues(K.screen())
      local top, bottom = view_edges()
      check(c.top, "^", top, { theme().highlight })
      check(c.bottom, "v", bottom, { theme().highlight })
    end)

    it("marks the edge beyond which the yellow target goes on",
        function()
      K.open("target.lua")
      K.browse_to(2)
      K.keys("f2")
      K.browse_to(1)
      assert.same(2, K.target())
      local c = view_cues(K.screen())
      local _, bottom = view_edges()
      assert.is_nil(c.top)
      check(c.bottom, "v", bottom, { theme().highlight_loaded })
    end)

    it("fades a block that is both in its yellow and its white "
        .. "strips", function()
      K.open("target.lua")
      K.browse_to(2)
      K.keys("f2")
      assert.same(2, K.position())
      local c = view_cues(K.screen())
      local edge = c.top or c.bottom
      local top, bottom = view_edges()
      check(edge, edge.glyph, c.top and top or bottom,
        { theme().highlight, theme().highlight_loaded })
    end)

    it("leaves a block the view merely cuts unmarked", function()
      K.open("tall.lua")
      K.browse_to(1)
      local rows, shown = K.rows_shown(2)
      assert.is_true(shown < rows)
      assert.same({ }, view_cues(K.screen()))
    end)

    it("has none in a file that fits, nor in an empty one",
        function()
      K.open()
      for b = 1, K.blocks() do
        K.browse_to(b)
        assert.same({ }, view_cues(K.screen()))
      end
      K.restart()
      K.open("empty.lua")
      assert.same({ }, view_cues(K.screen()))
    end)

    it("goes once the whole block is in view", function()
      K.open("target.lua")
      K.browse_to(2)
      assert.is_true(K.in_view(2))
      assert.same({ }, view_cues(K.screen()))
    end)

    it("is covered by a notice at the bottom edge until the "
        .. "next key", function()
      K.open("tall.lua")
      K.browse_to(1)
      K.keys("lctrl", "down")
      K.ed:notice("A notice.")
      local s = K.screen()
      local c = view_cues(s)
      assert.is_table(c.bottom)
      local bg = view_cfg().colors.input.error_bg
      local covered = false
      local after = false
      for _, f in ipairs(s.fills) do
        if f == c.bottom.box then after = true end
        if after and is(f.colour, bg, 1)
            and f.y <= c.bottom.y
            and c.bottom.y + view_cfg().fh <= f.y + f.h then
          covered = true
        end
      end
      assert.is_true(covered)
      K.keys("lctrl", "down")
      s = K.screen()
      for _, f in ipairs(s.fills) do
        assert.is_false(is(f.colour, bg, 1))
      end
      assert.is_table(view_cues(s).bottom)
    end)
  end)

  describe("in the field", function()
    it("marks the field's top edge while draft rows lie above "
        .. "it, and its bottom edge after Ctrl+Home", function()
      K.open("target.lua")
      K.browse_to(2)
      K.keys("f2")
      K.keys("lctrl", "end")
      local s = K.screen()
      local c = field_cues(s)
      local bg = view_cfg().colors.input.console.bg
      local first = require("view.layout")(view_cfg()).status_h
      assert.is_nil(c.bottom)
      check(c.top, "^", first, { bg })
      K.keys("lctrl", "home")
      s = K.screen()
      c = field_cues(s)
      assert.is_nil(c.top)
      check(c.bottom, "v", first + (s.field_rows - 1)
        * view_cfg().fh, { bg })
    end)

    it("has none while the draft fits", function()
      K.open("target.lua")
      K.browse_to(1)
      K.keys("f2")
      assert.same({ }, field_cues(K.screen()))
    end)
  end)
end)
