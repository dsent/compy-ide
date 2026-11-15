-- A wrapped line's mark (the maintainer's rulings of November
-- 15, 2026), read from the real draw (K.screen): every row
-- that continues a line has a small fillet at its top left,
-- drawn as runs of pixels in the theme's colour, under the
-- text; a line's first row has none. In the document view and
-- in the draft field: the editor's, the console's, a
-- program's.

local K = require("tests.helpers.editor_keys")
local F = require("tests.helpers.input_fixture")
local WrapMark = require("view.wrapMark")

local function view_cfg()
  return K.cc.view.cfg.view
end

local function theme()
  return view_cfg().colors.editor.wrap_mark
end

local function is_mark(f)
  local c = theme().color
  for i = 1, 3 do
    if math.abs((f.colour[i] or 0) - c[i]) >= 0.001 then
      return false
    end
  end
  return (f.colour[4] or 1) == 1 and f.h == 1
      and f.x + f.w <= theme().size
end

--- The marks among `fills`: their runs, grouped by the y of
--- the row each starts on, as { y = { x, dy, w }... }
local function marks(fills)
  local runs = WrapMark.runs(theme().size, theme().round)
  local out, tops = { }, { }
  for _, f in ipairs(fills) do
    if f.fill ~= false and is_mark(f) then
      out[#out + 1] = f
    end
  end
  --- a mark is the shape's runs, one after another
  local i = 1
  while i <= #out do
    local top = out[i].y - runs[1][2]
    for k, run in ipairs(runs) do
      local f = out[i + k - 1]
      assert(f, "a mark cut short at " .. top)
      assert.same({ run[1], top + run[2], run[3] }, { f.x, f.y, f.w })
    end
    tops[#tops + 1] = top
    i = i + #runs
  end
  return tops
end

local function view_marks(s)
  return marks(s.fills)
end

local function field_marks(s)
  local fills = { }
  for _, e in ipairs(s.field_log) do
    if e.fill then fills[#fills + 1] = e end
  end
  return marks(fills)
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

--- the tops of rows 2 on of the lines `ls`, as drawn
local function continuation_tops(ls)
  local out = { }
  for _, l in ipairs(ls) do
    local rows = rows_of(l)
    for i = 2, #rows do out[#out + 1] = row_y(rows[i]) end
  end
  return out
end

local W = 64

describe("a wrapped line's mark #editor", function()
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

  it("is a fillet in the corner the font leaves free", function()
    local runs = WrapMark.runs(6, 0)
    -- the corner's pixels outside the circle round (6, 6)
    assert.same({ { 0, 0, 4 }, { 0, 1, 2 }, { 0, 2, 1 },
      { 0, 3, 1 } }, runs)
    -- rounding the outer corner takes its corner pixel
    assert.same({ 1, 0, 3 }, WrapMark.runs(6, 2)[1])
    -- a size is one number
    assert.is_true(#WrapMark.runs(8, 0) > #runs)
  end)

  describe("in the document view", function()
    it("marks rows 2 on of lines of 2, 3 and 5 rows, and no "
        .. "line's first row", function()
      K.open("rows.txt")
      K.browse_to(1)
      assert.same({ 2, 3, 5 }, { #rows_of(2), #rows_of(3),
        #rows_of(4) })
      assert.same(continuation_tops({ 2, 3, 4 }),
        view_marks(K.screen()))
    end)

    it("marks nothing in a file whose lines take a row each",
        function()
      K.open()
      assert.same({ }, view_marks(K.screen()))
    end)

    it("marks a continuation row at the view's top edge, and "
        .. "none on rows of the line below the view", function()
      K.open("long.txt")
      K.browse_to(2)
      local rows = rows_of(2)
      -- up to the line's first row, then four rows on
      for _ = 1, 30 do
        if bv().content.range.start <= rows[1] then break end
        K.keys("lctrl", "up")
      end
      for _ = 1, 4 do
        K.keys("lctrl", "down")
      end
      assert.same(2, K.position())
      local r = bv().content.range
      assert.is_true(rows[1] < r.start and r.fin < rows[#rows])
      local want = { }
      for v = r.start, r.fin do want[#want + 1] = row_y(v) end
      assert.same(want, view_marks(K.screen()))
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
        if is_mark(f) then
          n = n + 1
          assert.is_true(f.seq < first_text)
        end
      end
      assert.is_true(0 < n)
    end)
  end)

  describe("in the field", function()
    local function first()
      return require("view.layout")(view_cfg()).status_h
    end

    it("marks the editor's draft", function()
      K.open("rows.txt")
      K.browse_to(3)
      K.keys("f2")
      local fh = view_cfg().fh
      -- line 3 takes 3 rows of the field
      assert.same({ first() + fh, first() + 2 * fh },
        field_marks(K.screen()))
    end)

    it("marks the console's field, and nothing for a line of "
        .. "one row", function()
      K.type("x = 1")
      assert.same({ }, field_marks(K.screen()))
      K.type(string.rep("y", W))
      assert.same({ first() + view_cfg().fh },
        field_marks(K.screen()))
    end)

    it("marks a program's input field", function()
      local widget = F.show_widget({ text = string.rep("p", 70) })
      local view = UserInputView(view_cfg(), widget)
      widget:init_view(view)
      local s = K.screen(function()
        widget:update_view()
        view:draw()
      end)
      local got = field_marks(s)
      assert.same(first() + view_cfg().fh, got[#got])
    end)
  end)
end)
