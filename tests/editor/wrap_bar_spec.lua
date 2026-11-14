-- A wrapped line's bar (the maintainer's ruling of November
-- 15, 2026), read from the real draw (K.screen): a line that
-- takes more than one row carries a bar at the left edge, 3
-- pixels wide, gray, one stroke from the middle of its first
-- row to the middle of its last, under the text. Where a row
-- of the line lies beyond the rows shown, the stroke runs to
-- that edge. In the document view and in the draft field:
-- the editor's, the console's, a program's.

local K = require("tests.helpers.editor_keys")
local F = require("tests.helpers.input_fixture")

local function view_cfg()
  return K.cc.view.cfg.view
end

local function is_bar(f)
  local c = view_cfg().colors.editor.wrap_bar
  for i = 1, 3 do
    if math.abs((f.colour[i] or 0) - c[i]) >= 0.001 then
      return false
    end
  end
  return (f.colour[4] or 1) == 1 and f.x == 0
      and f.w == require("conf.display").wrap_bar
end

--- The bar's strokes as { top, bottom } pixel rows, in the
--- order drawn, among `fills`
local function strokes(fills)
  local out = { }
  for _, f in ipairs(fills) do
    if f.fill ~= false and is_bar(f) then
      out[#out + 1] = { f.y, f.y + f.h }
    end
  end
  return out
end

local function view_strokes(s)
  return strokes(s.fills)
end

local function field_strokes(s)
  local fills = { }
  for _, e in ipairs(s.field_log) do
    if e.fill then fills[#fills + 1] = e end
  end
  return strokes(fills)
end

local function bv()
  return K.ed.view:get_current_buffer()
end

--- where the document view's wrapped row `v` starts
local function row_y(v)
  local c = bv().content
  return bv():top() + (v - c.offset - 1) * view_cfg().fh
end

--- the document view's rows of source line `l`
local function rows_of(l)
  return bv().content.wrap_forward[l]
end

local W = 64

describe("a wrapped line's bar #editor", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  local lines = {
    "short",
    string.rep("a", W + 10),
    string.rep("b", 2 * W + 10),
    string.rep("c", 4 * W + 10),
    "end",
  }

  before_each(function()
    K.reset({
      ["main.lua"] = "x = 1\n",
      ["rows.txt"] = table.concat(lines, "\n") .. "\n",
      ["long.txt"] = "a\n" .. string.rep("z", 24 * W) .. "\nb\n",
    })
  end)

  describe("in the document view", function()
    it("runs from the middle of a line's first row to the "
        .. "middle of its last, for 2, 3 and 5 rows", function()
      K.open("rows.txt")
      K.browse_to(1)
      local half = math.floor(view_cfg().fh / 2)
      local want = { }
      for l = 2, 4 do
        local rows = rows_of(l)
        want[#want + 1] = { row_y(rows[1]) + half,
          row_y(rows[#rows]) + half }
      end
      assert.same({ 2, 3, 5 }, { #rows_of(2), #rows_of(3),
        #rows_of(4) })
      assert.same(want, view_strokes(K.screen()))
    end)

    it("is none beside a line of one row", function()
      K.open("rows.txt")
      K.browse_to(1)
      local y1 = row_y(rows_of(1)[1])
      local y5 = row_y(rows_of(5)[1])
      for _, s in ipairs(view_strokes(K.screen())) do
        assert.is_true(s[2] <= y1 or y1 + view_cfg().fh <= s[1])
        assert.is_true(s[2] <= y5 or y5 + view_cfg().fh <= s[1])
      end
    end)

    it("shows two wrapped lines in a row as two strokes",
        function()
      K.open("rows.txt")
      local s = view_strokes(K.screen())
      assert.same(3, #s)
      assert.same(view_cfg().fh, s[2][1] - s[1][2])
      assert.same(view_cfg().fh, s[3][1] - s[2][2])
    end)

    it("runs to the view's edge where the line goes on beyond "
        .. "it", function()
      K.open("long.txt")
      K.browse_to(2)
      local rows = rows_of(2)
      local fh = view_cfg().fh
      local half = math.floor(fh / 2)
      -- scrolled up to its first row: its last below the view
      for _ = 1, 30 do
        if bv().content.range.start <= rows[1] then break end
        K.keys("lctrl", "up")
      end
      assert.same(2, K.position())
      local r = bv().content.range
      assert.is_true(r.start <= rows[1] and r.fin < rows[#rows])
      assert.same({ { row_y(rows[1]) + half, row_y(r.fin) + fh } },
        view_strokes(K.screen()))
      -- scrolled on: its first row above the view as well
      for _ = 1, 4 do
        K.keys("lctrl", "down")
      end
      r = bv().content.range
      assert.is_true(rows[1] < r.start and r.fin < rows[#rows])
      assert.same({ { row_y(r.start), row_y(r.fin) + fh } },
        view_strokes(K.screen()))
      -- on to its end: its last row in view, its first above
      for _ = 1, 30 do
        if rows[#rows] <= bv().content.range.fin then break end
        K.keys("lctrl", "down")
      end
      assert.same(2, K.position())
      r = bv().content.range
      assert.is_true(rows[1] < r.start and rows[#rows] <= r.fin)
      local s = view_strokes(K.screen())
      assert.same({ row_y(r.start), row_y(rows[#rows]) + half },
        s[1])
    end)

    it("is drawn under the text", function()
      K.open("rows.txt")
      local s = K.screen()
      local first_text
      for _, t in ipairs(s.texts) do
        first_text = math.min(first_text or t.seq, t.seq)
      end
      local n = 0
      for _, f in ipairs(s.fills) do
        if is_bar(f) then
          n = n + 1
          assert.is_true(f.seq < first_text)
        end
      end
      assert.same(3, n)
    end)
  end)

  describe("in the field", function()
    it("marks the editor's draft", function()
      K.open("rows.txt")
      K.browse_to(3)
      K.keys("f2")
      local s = K.screen()
      local got = field_strokes(s)
      local fh = view_cfg().fh
      local first = require("view.layout")(view_cfg()).status_h
      local half = math.floor(fh / 2)
      -- line 3 takes 3 rows of the field, its rows 1 to 3
      assert.same({ { first + half, first + 2 * fh + half } }, got)
    end)

    it("marks the console's field, and none for a line of one "
        .. "row", function()
      K.type("x = 1")
      assert.same({ }, field_strokes(K.screen()))
      K.type(string.rep("y", W))
      local fh = view_cfg().fh
      local first = require("view.layout")(view_cfg()).status_h
      local half = math.floor(fh / 2)
      assert.same({ { first + half, first + fh + half } },
        field_strokes(K.screen()))
    end)

    it("marks a program's input field", function()
      local widget = F.show_widget({ text = string.rep("p", 70) })
      local view = UserInputView(view_cfg(), widget)
      widget:init_view(view)
      local s = K.screen(function()
        widget:update_view()
        view:draw()
      end)
      local fh = view_cfg().fh
      local first = require("view.layout")(view_cfg()).status_h
      local half = math.floor(fh / 2)
      local got = field_strokes(s)
      assert.same({ first + half, first + fh + half },
        got[#got])
    end)
  end)
end)
