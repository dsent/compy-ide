-- A wrapped line's marks (the maintainer's rulings of November
-- 15 and 16, 2026), read from the real draw (K.screen): a
-- line that takes more than one row has a small fillet in the
-- theme's colour at the top right of every row that goes on
-- below, at the last text column, and the same fillet mirrored
-- at the bottom left of every row that continues it. They are
-- drawn under the text: the glyphs, a selection and the cursor
-- paint over them. An edge row that carries a continuation cue
-- takes no mark in its last column, where the cue stands. In
-- the document view and in the draft field: the editor's, the
-- console's, a program's.

local K = require("tests.helpers.editor_keys")
local F = require("tests.helpers.input_fixture")
local WrapMark = require("view.wrapMark")

local function view_cfg()
  return K.cc.view.cfg.view
end

local function theme()
  return view_cfg().colors.editor.wrap_mark
end

local function right()
  return view_cfg().drawableChars * view_cfg().fw
end

local function is_mark(f)
  local c = theme().color
  for i = 1, 3 do
    if math.abs((f.colour[i] or 0) - c[i]) >= 0.001 then
      return false
    end
  end
  return (f.colour[4] or 1) == 1 and f.h == 1
end

--- The marks among `fills`, each checked run for run against
--- the shape: { 'end' | 'start', the top of its row }, in the
--- order drawn.
local function marks(fills)
  local runs = WrapMark.runs(theme().size, theme().round)
  local fh = view_cfg().fh
  local out, got = { }, { }
  for _, f in ipairs(fills) do
    if f.fill ~= false and is_mark(f) then out[#out + 1] = f end
  end
  local i = 1
  while i <= #out do
    local first = out[i]
    local at = first.x == 0 and 'start' or 'end'
    local top = at == 'end' and first.y - runs[1][2]
        or first.y - (fh - 1 - runs[1][2])
    for k, run in ipairs(runs) do
      local f = out[i + k - 1]
      assert(f, "a mark cut short at " .. top)
      if at == 'end' then
        assert.same({ right() - run[1] - run[3], top + run[2], run[3] },
          { f.x, f.y, f.w })
      else
        assert.same({ run[1], top + fh - 1 - run[2], run[3] },
          { f.x, f.y, f.w })
      end
    end
    got[#got + 1] = { at, top }
    i = i + #runs
  end
  return got
end

local function view_marks(s)
  return marks(s.fills)
end

local function field_fills(s)
  local fills = { }
  for _, e in ipairs(s.field_log) do
    if e.fill then fills[#fills + 1] = e end
  end
  return fills
end

local function field_marks(s)
  return marks(field_fills(s))
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

--- the marks lines `ls` take, row by row, in the order drawn
local function want_of(ls, from, to)
  local out = { }
  local rows = { }
  for _, l in ipairs(ls) do
    local rs = rows_of(l)
    for i, r in ipairs(rs) do
      rows[#rows + 1] = { r, i < #rs, 1 < i }
    end
  end
  for _, x in ipairs(rows) do
    local r = x[1]
    if (not from or from <= r) and (not to or r <= to) then
      if x[2] then out[#out + 1] = { 'end', row_y(r) } end
      if x[3] then out[#out + 1] = { 'start', row_y(r) } end
    end
  end
  return out
end

local W = 64

describe("a wrapped line's marks #editor", function()
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
      ["under.txt"] = "x\n" .. string.rep("_", W + 8) .. "\ny\n",
    })
  end)

  it("are fillets of the theme's size, in its orange", function()
    assert.same({ { 0, 0, 5 }, { 0, 1, 3 }, { 0, 2, 2 }, { 0, 3, 1 },
      { 0, 4, 1 } }, WrapMark.runs(8, 0))
    assert.same(8, theme().size)
    assert.same(view_cfg().colors.statusline.editor.warning,
      theme().color)
    -- a size is one number
    assert.are_not.same(WrapMark.runs(8, 0), WrapMark.runs(7, 0))
  end)

  describe("in the document view", function()
    it("mark the end of every row that goes on and the start "
        .. "of every row that continues, for 2, 3 and 5 rows",
      function()
        K.open("rows.txt")
        K.browse_to(1)
        assert.same({ 2, 3, 5 }, { #rows_of(2), #rows_of(3),
          #rows_of(4) })
        assert.same(want_of({ 2, 3, 4 }), view_marks(K.screen()))
      end)

    it("mark nothing in a file whose lines take a row each",
      function()
        K.open()
        assert.same({ }, view_marks(K.screen()))
      end)

    it("leave out the end mark on an edge row with a "
        .. "continuation cue, and keep it without one", function()
      K.open("long.txt")
      K.browse_to(2)
      local rows = rows_of(2)
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
      -- the browsed line goes on beyond both edges: cues there
      local want = { }
      for v = r.start, r.fin do
        if v ~= r.start and v ~= r.fin then
          want[#want + 1] = { 'end', row_y(v) }
        end
        want[#want + 1] = { 'start', row_y(v) }
      end
      assert.same(want, view_marks(K.screen()))
    end)

    it("are drawn under the text", function()
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

    it("mark the editor's draft", function()
      K.open("rows.txt")
      K.browse_to(3)
      K.keys("f2")
      local fh = view_cfg().fh
      -- line 3 takes 3 rows of the field
      local a, b, c = first(), first() + fh, first() + 2 * fh
      assert.same({ { 'end', a }, { 'end', b }, { 'start', b },
        { 'start', c } }, field_marks(K.screen()))
    end)

    it("mark the console's field, and nothing for a line of "
        .. "one row", function()
      K.type("x = 1")
      assert.same({ }, field_marks(K.screen()))
      K.type(string.rep("y", W))
      local fh = view_cfg().fh
      assert.same({ { 'end', first() }, { 'start', first() + fh } },
        field_marks(K.screen()))
    end)

    it("mark a program's input field", function()
      local widget = F.show_widget({ text = string.rep("p", 70) })
      local view = UserInputView(view_cfg(), widget)
      widget:init_view(view)
      local s = K.screen(function()
        widget:update_view()
        view:draw()
      end)
      local got = field_marks(s)
      assert.same({ 'start', first() + view_cfg().fh }, got[#got])
    end)

    -- nothing selects today; the draw still paints a selection,
    -- and a selected cell covers the mark under it
    it("lie under a selected cell, which is painted after them "
        .. "and covers them", function()
        K.type(string.rep("y", W + 4))
        local model = K.cc.input.model
        model:start_selection(1, W - 2)
        model:end_selection(1, W + 4)
        local log = K.screen().field_log
        local fw, fh = view_cfg().fw, view_cfg().fh
        local x, y = (W - 1) * fw, first()
        local cover
        for i, e in ipairs(log) do
          if e.text == "█" and e.x == x and e.y == y then
            cover = i
          end
        end
        assert.is_number(cover, "the selected last cell of row 1")
        local seen = 0
        for i, e in ipairs(log) do
          if e.fill and is_mark(e) and e.y < y + fh then
            seen = seen + 1
            assert.is_true(i < cover, "a mark after the selection")
            assert.is_true(x <= e.x and e.x + e.w <= x + fw)
            assert.is_true(y <= e.y and e.y < y + fh)
          end
        end
        assert.is_true(0 < seen)
      end)

    it("are drawn before the draft's text and the cursor",
      function()
        K.type(string.rep("y", W + 4))
        local log = K.screen().field_log
        local last_mark, first_after
        for i, e in ipairs(log) do
          if e.fill and is_mark(e) then last_mark = i end
        end
        for i, e in ipairs(log) do
          if i > 1 and e.text and not first_after then
            first_after = i
          end
        end
        assert.is_number(last_mark)
        -- the cursor's block, in its colour, comes after them
        local cursor = view_cfg().colors.input.cursor
        local cursor_at
        for i, e in ipairs(log) do
          if e.fill and e.w == view_cfg().fw and e.h == view_cfg().fh
              and e.colour[1] == cursor[1] and e.colour[2] == cursor[2]
          then cursor_at = i end
        end
        assert.is_number(cursor_at)
        assert.is_true(last_mark < cursor_at)
        -- every text of the draft comes after the last mark
        for i, e in ipairs(log) do
          if e.text and e.y >= first() then
            assert.is_true(last_mark < i, e.text)
          end
        end
      end)
  end)
end)
