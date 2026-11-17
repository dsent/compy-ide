-- FR4.8 Mark what continues off the edge, with IS2.2 and
-- IS3.13, as Appendix B checks it: the continuation cue the
-- maintainer chose on November 15, 2026 (rulings, "The
-- continuation cue is chosen"): the edge row's fade and the
-- mark `^` or `v` in its last column. Read from the real draw
-- (K.screen).

local K = require("tests.helpers.editor_keys")
local C = require("tests.helpers.screen_cues")
local marks = require("tests.helpers.spec_marks")
local spec_it, spec_deviation = marks.spec_it, marks.spec_deviation

local RULING = "rulings, The continuation cue is chosen (2026-11-15)"

--- the edges carrying a cue in the document view
local function view_edges_marked()
  local c = C.view_cues(K.screen())
  return { top = c.top ~= nil, bottom = c.bottom ~= nil }
end

local function field_edges_marked()
  local c = C.field_cues(K.screen())
  return { top = c.top ~= nil, bottom = c.bottom ~= nil }
end

local NONE = { top = false, bottom = false }

describe("FR4.8 the continuation cue #editor #spec", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  before_each(function()
    K.reset({
      ["main.lua"] = "x = 1\n",
      ["tall.lua"] = "a = 1\n" .. K.block(20) .. "b = 2\n",
      ["block.lua"] = "a = 1\n" .. K.block(14) .. "b = 2\n",
    })
  end)

  spec_it("FR4.8 Mark what continues off the edge: a block taller "
      .. "than the view is marked at the bottom while its last rows "
      .. "are hidden, at the top once the view reaches its last "
      .. "row, and not once it fits", function()
    K.open("tall.lua")
    K.browse_to(1)
    K.keys("lctrl", "down")
    assert.same(2, K.position())
    assert.same({ top = false, bottom = true }, view_edges_marked())
    local bv = K.ed.view:get_current_buffer()
    local rows = bv:_block_rows(2)
    for _ = 1, 30 do
      if rows[#rows] <= bv.content.range.fin then break end
      K.keys("lctrl", "down")
    end
    assert.same(2, K.position())
    assert.same({ top = true, bottom = false }, view_edges_marked())
    K.keys("lctrl", "down")
    assert.same(3, K.position())
    assert.same(NONE, view_edges_marked())
  end)

  spec_it("FR4.8 Mark what continues off the edge: after Edit, "
      .. "the replacement target cut by the shorter view is marked, "
      .. "and a block that fits is not", function()
    K.open("block.lua")
    K.browse_to(2)
    K.keys("f2")
    assert.same("replacing", K.state())
    -- the draw fits the view to the field the draft takes
    local m = view_edges_marked()
    local rows, shown = K.rows_shown(2)
    assert.is_true(shown < rows)
    assert.is_true(m.top or m.bottom)
    K.keys("escape")
    K.browse_to(1)
    K.keys("f2")
    assert.same(NONE, view_edges_marked())
  end)

  spec_it("IS3.13 Wrap long lines: a draft taller than the field's "
      .. "display limit is marked at the top while rows lie above, "
      .. "at the bottom after Ctrl+Home, and not once it fits",
    function()
      K.open("block.lua")
      K.browse_to(2)
      K.keys("f2")
      K.keys("lctrl", "end")
      assert.same({ top = true, bottom = false },
        field_edges_marked())
      K.keys("lctrl", "home")
      assert.same({ top = false, bottom = true },
        field_edges_marked())
      K.keys("escape")
      K.browse_to(1)
      K.keys("f2")
      assert.same(NONE, field_edges_marked())
    end)

  spec_it("FR4.8 Mark what continues off the edge: the edge row "
      .. "stays readable and full-width, every character of it "
      .. "drawn", function()
    K.open("tall.lua")
    K.browse_to(1)
    K.keys("lctrl", "down")
    local s = K.screen()
    local c = C.view_cues(s)
    assert.is_table(c.bottom)
    local drawn = { }
    for _, t in ipairs(s.texts) do
      if t.y == c.bottom.y and (t.colour[4] or 1) == 1 then
        drawn[#drawn + 1] = t.text
      end
    end
    local bv = K.ed.view:get_current_buffer()
    local row = bv.content.text[bv.content.range.fin]
    assert.same(row, table.concat(drawn))
  end)

  spec_deviation("FR4.8 Mark what continues off the edge: the mark "
      .. "stands in the edge row's last column, over its character, "
      .. "translucent, where the spec's cue takes no text column",
    RULING, function()
      local v = C.view_cfg()
      K.open("tall.lua")
      K.browse_to(1)
      K.keys("lctrl", "down")
      local c = C.view_cues(K.screen())
      assert.same((v.drawableChars - 1) * v.fw, c.bottom.x)
      assert.same(.5, C.theme().cue.mark_alpha)
      assert.same(.25, C.theme().cue.box_alpha)
    end)
end)
