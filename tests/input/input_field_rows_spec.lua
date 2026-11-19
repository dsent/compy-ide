-- The rows a program's field shows (doc/input_api.md, "The
-- rows the field shows"; the maintainer's ruling of November
-- 19, 2026: a program builds a field like the editor's, of 1
-- to 14 rows, its text longer than it and scrolled, with the
-- editor's continuation cue). A new spec file because
-- `max_rows` is a key of the compy.input contract, the seam
-- every program's typing goes through, and the field it
-- shapes is the one the editor and the console share: a
-- mistake here breaks every field. The keys and the mouse in
-- a field of one and of three rows are also run by
-- input_one_field_spec and input_selection_spec, which take
-- those fields as owners of their own.

local F = require("tests.helpers.input_fixture")
local K = require("tests.helpers.editor_keys")
local C = require("tests.helpers.screen_cues")
local Layout = require("view.layout")

local function cfg()
  return K.cc.view.cfg.view
end

--- A program run and its field shown with `opts`; returns
--- the project's compy.input and the field, which has the
--- view a run gives it.
--- @param opts table?
local function program(opts)
  F.activate_project()
  local input = F.compy_input()
  input.show(opts or { })
  local w = love.state.user_input_controller
  w:init_view(UserInputView(cfg(), w))
  return input, w
end

--- `n` lines: "line 1" to "line n"
local function lines(n)
  local out = { }
  for i = 1, n do out[i] = "line " .. i end
  return out
end

--- The rows the field takes under its status line.
local function rows(w)
  return w.view:get_rows(w:get_input())
end

--- The draft's wrapped rows the field shows, first and last.
local function shown(w)
  local r = w.model.visible:get_range()
  return { r.start, r.fin }
end

--- The draw of the screen with the field `w` drawn over it,
--- as love.draw draws a program's field.
local function screen(w)
  return K.screen(function()
    w:update_view()
    w.view:draw()
  end)
end

--- The row of the field the cursor's block is drawn on, 1
--- the first; nil when none is drawn.
local function cursor_row(s)
  local c = cfg()
  local colour = c.colors.input.cursor
  local top = Layout(c).status_h
  local row
  for _, e in ipairs(s.field_log) do
    local own = e.colour and C.is(e.colour, colour, 1)
    if e.fill and own and e.w == c.fw and e.h == c.fh then
      row = (e.y - top) / c.fh + 1
    end
  end
  return row
end

--- The cursor is drawn on a row the field shows.
local function cursor_in_view(w, what)
  local s = screen(w)
  local r = cursor_row(s)
  assert.is_number(r, "no cursor drawn: " .. what)
  assert.is_true(1 <= r and r <= rows(w),
    "the cursor drawn off the field's rows: " .. what)
end

--- The cues' glyphs drawn in the field, and where.
local function marks(s)
  local t = C.theme().cue
  local out = { }
  for _, e in ipairs(s.field_log) do
    if e.text and C.is(e.colour, t.mark, t.mark_alpha) then
      out[#out + 1] = { e.text, e.x, e.y }
    end
  end
  return out
end

--- The fade's bands drawn in the field.
local function bands(s)
  local t = C.theme().cue
  local n = 0
  for _, e in ipairs(s.field_log) do
    local a = e.colour and e.colour[4] or 1
    if e.fill and a < 1 and e.h < cfg().fh / 4
        and not C.is(e.colour, t.box, t.box_alpha) then
      n = n + 1
    end
  end
  return n
end

describe("the rows a program's field shows #input", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)
  before_each(function() K.reset() end)

  describe("without max_rows", function()
    -- what the brief asked to establish: past 14 lines a
    -- program's field goes on taking text, shows 14 rows and
    -- scrolls; nothing is refused or lost
    it("takes a 20th line, shows 14 rows, the last 14, and "
        .. "marks the rows above", function()
      local _, w = program()
      K.type_lines(lines(20))
      assert.same(lines(20), w:get_text())
      assert.same({ 20, 8 }, { w:get_cursor_pos() })
      assert.same(14, rows(w))
      assert.same({ 7, 20 }, shown(w))
      local s = screen(w)
      local c = C.field_cues(s)
      assert.is_table(c.top)
      assert.is_nil(c.bottom)
      K.keys("lctrl", "home")
      assert.same({ 1, 14 }, shown(w))
      c = C.field_cues(screen(w))
      assert.is_nil(c.top)
      assert.is_table(c.bottom)
    end)

    it("is the console's 14 rows, where the editor's field "
        .. "takes 8", function()
      K.type_lines(lines(20))
      assert.same(14, K.cc.input.model.visible.size_max)
      K.reset({ ["notes.txt"] = "" })
      K.open("notes.txt")
      K.type_lines(lines(20))
      assert.same(20, #K.ed.input:get_text())
      assert.same(8, rows(K.ed.input))
    end)
  end)

  describe("max_rows", function()
    it("caps the field: it grows with its text up to the "
        .. "rows, then keeps its height and scrolls", function()
      local _, w = program({ max_rows = 3 })
      assert.same(1, rows(w))
      K.type_lines(lines(2))
      assert.same(2, rows(w))
      K.keys("lshift", "return")
      K.type("line 3")
      K.keys("lshift", "return")
      K.type("line 4")
      assert.same(3, rows(w))
      assert.same({ 2, 4 }, shown(w))
      assert.same(lines(4), w:get_text())
    end)

    it("keeps the cursor's row in view under every key that "
        .. "moves it over hidden lines", function()
      local keys = {
        { "up" }, { "up" }, { "up" }, { "lctrl", "home" },
        { "down" }, { "down" }, { "lctrl", "end" },
        { "pageup" }, { "pagedown" }, { "home" },
        { "left" }, { "right" }, { "lctrl", "left" },
        { "lalt", "lshift", "up" },
      }
      for _, n in ipairs({ 1, 3 }) do
        local _, w = program({ max_rows = n })
        K.type_lines(lines(8))
        for _, k in ipairs(keys) do
          K.keys(unpack(k))
          cursor_in_view(w, n .. " rows, " .. table.concat(k, "+"))
          assert.same(math.min(n, 8), rows(w))
        end
        K.reset()
      end
    end)

    it("edits a hidden line when the cursor reaches it: "
        .. "typing, Backspace across a line break, Ctrl+K",
      function()
        local _, w = program({ max_rows = 1,
          text = lines(4) })
        K.keys("lctrl", "home")
        K.keys("end")
        K.type("!")
        K.keys("down")
        K.keys("home")
        K.keys("backspace")
        assert.same({ "line 1!line 2", "line 3", "line 4" },
          w:get_text())
        assert.same({ 1, 1 }, shown(w))
        K.keys("lctrl", "end")
        K.keys("up")
        K.keys("home")
        K.keys("lctrl", "k")
        assert.same({ "line 1!line 2", "", "line 4" },
          w:get_text())
        cursor_in_view(w, "after Ctrl+K")
      end)

    it("selects across hidden lines with Shift and the "
        .. "arrows, and typing replaces all of it", function()
      local _, w = program({ max_rows = 1, text = lines(3) })
      K.keys("lctrl", "home")
      K.keys("lshift", "down")
      K.keys("lshift", "down")
      K.keys("lshift", "end")
      assert.same({ 3, 3 }, shown(w))
      assert.same("line 1\nline 2\nline 3",
        table.concat(w.model:get_selection().text, "\n"))
      K.type("x")
      assert.same({ "x" }, w:get_text())
      assert.same(1, rows(w))
    end)

    describe("and the mouse in a field of one row", function()
      local function at_row(col)
        local v = cfg()
        local bottom = love.graphics.getHeight()
            - Layout(v).bottom
        return v.fw * (col - 1 + 0.2), bottom - v.fh * 0.5
      end
      local function click(col, presses)
        local x, y = at_row(col)
        F.session.mousepressed(x, y, 1, false, presses or 1)
        F.session.mousereleased(x, y, 1, false, presses or 1)
        K.frame()
      end

      it("a click lands on the line the row shows, a "
          .. "Shift+click selects from a hidden line to it, and "
          .. "a double click selects its word", function()
        local _, w = program({ max_rows = 1,
          text = { "one two", "three four" } })
        assert.same({ 2, 2 }, shown(w))
        click(3)
        assert.same({ 2, 3 }, { w:get_cursor_pos() })
        K.keys("up")
        assert.same({ 1, 1 }, shown(w))
        K.keys("home")
        K.keys("lshift", "down")
        assert.same({ 2, 2 }, shown(w))
        F.session.press("lshift")
        click(9)
        F.session.release("lshift")
        assert.same({ 2, 9 }, { w:get_cursor_pos() })
        assert.same("one two\nthree fo",
          table.concat(w.model:get_selection().text, "\n"))
        local x, y = at_row(8)
        F.session.mousepressed(x, y, 1, false, 2)
        F.session.mousereleased(x, y, 1, false, 2)
        K.frame()
        assert.same("four",
          table.concat(w.model:get_selection().text, "\n"))
      end)

      it("the wheel scrolls nothing: the field takes no wheel",
        function()
          local _, w = program({ max_rows = 1, text = lines(3) })
          local before = shown(w)
          w:wheelmoved(0, 1)
          w:wheelmoved(0, -1)
          assert.same(before, shown(w))
        end)
    end)

    it("is kept by set_text, by hide and show, and by "
        .. "clear", function()
      local input, w = program({ max_rows = 2 })
      input.set_text(lines(6))
      assert.same(2, rows(w))
      assert.same({ 5, 6 }, shown(w))
      input.hide()
      input.show()
      assert.same(2, rows(w))
      input.clear()
      input.set_text(lines(4))
      assert.same(2, rows(w))
    end)

    it("leaves a validator's message its rows, more than "
        .. "the field's one", function()
      local _, w = program({ max_rows = 1, text = "x",
        validator = function()
          return false, { Error("a"), Error("b"), Error("c") }
        end })
      K.keys("return")
      assert.is_true(w:has_error())
      local message = w:get_wrapped_error()
      assert.is_true(3 <= #message)
      assert.same(#message, rows(w))
    end)

    it("is the run's: the next run's field has 14 rows",
      function()
        program({ max_rows = 2 })
        local _, w = program()
        w:set_text(lines(20))
        assert.same(14, rows(w))
      end)
  end)

  describe("the continuation cue", function()
    it("in a field of three rows is the editor's: the top "
        .. "row marked and faded while lines lie above, the "
        .. "bottom row while lines lie below", function()
      local v = cfg()
      local _, w = program({ max_rows = 3, text = lines(6) })
      local top = Layout(v).status_h
      local c = C.field_cues(screen(w))
      C.check(c.top, "^", top, { v.colors.input.user.bg })
      assert.is_nil(c.bottom)
      K.keys("up")
      K.keys("up")
      K.keys("up")
      c = C.field_cues(screen(w))
      C.check(c.top, "^", top, { v.colors.input.user.bg })
      C.check(c.bottom, "v", top + 2 * v.fh,
        { v.colors.input.user.bg })
      K.keys("lctrl", "home")
      c = C.field_cues(screen(w))
      assert.is_nil(c.top)
      C.check(c.bottom, "v", top + 2 * v.fh,
        { v.colors.input.user.bg })
    end)

    it("in a field of one row shows each direction there is "
        .. "text in, both on its one row, `^` in the column "
        .. "before the last and `v` in the last", function()
      local v = cfg()
      local top = Layout(v).status_h
      local last = (v.drawableChars - 1) * v.fw
      local _, w = program({ max_rows = 1, text = lines(3) })
      local s = screen(w)
      assert.same({ { "^", last, top } }, marks(s))
      K.keys("up")
      s = screen(w)
      assert.same({ { "^", last - v.fw, top }, { "v", last, top } },
        marks(s))
      K.keys("up")
      s = screen(w)
      assert.same({ { "v", last, top } }, marks(s))
    end)

    it("in a field of one row with text on both sides takes "
        .. "nothing from the row: no fade, every character "
        .. "drawn, the cursor drawn", function()
      local v = cfg()
      local top = Layout(v).status_h
      local _, w = program({ max_rows = 1, text = lines(3) })
      K.keys("up")
      local s = screen(w)
      assert.same(0, bands(s))
      local drawn = { }
      for _, e in ipairs(s.field_log) do
        if e.text and e.y == top and #e.text == 1
            and C.is(e.colour, v.colors.input.user.fg, 1) then
          drawn[#drawn + 1] = e.text
        end
      end
      assert.same("line 2", table.concat(drawn))
      assert.same(1, cursor_row(s))
    end)
  end)

  describe("configure while the field is in use", function()
    it("shrinking keeps the cursor in view, growing shows "
        .. "more, and the status line says the same", function()
      local input, w = program({ prompt = "cmd", text = lines(10),
        cursor = { 2, 3 } })
      K.keys("lctrl", "home")
      K.keys("down")
      assert.same({ 1, 10 }, shown(w))
      local status = w:get_status()
      local label = w.model:get_label()
      input.configure({ max_rows = 1 })
      assert.same(1, rows(w))
      assert.same({ 2, 2 }, shown(w))
      cursor_in_view(w, "shrunk to 1")
      K.keys("lctrl", "end")
      input.configure({ max_rows = 4 })
      assert.same(4, rows(w))
      assert.same({ 7, 10 }, shown(w))
      cursor_in_view(w, "grown to 4")
      input.configure({ max_rows = false })
      assert.same(10, rows(w))
      assert.same({ 1, 10 }, shown(w))
      K.keys("lctrl", "home")
      K.keys("down")
      assert.same(status, w:get_status())
      assert.same(label, w.model:get_label())
    end)

    it("growing past the text shows the whole of it",
      function()
        local input, w = program({ max_rows = 2,
          text = lines(3) })
        assert.same({ 2, 3 }, shown(w))
        input.configure({ max_rows = 5 })
        assert.same(3, rows(w))
        assert.same({ 1, 3 }, shown(w))
      end)

    it("is taken while the field is hidden and applies at "
        .. "the next show", function()
      local input, w = program({ text = lines(5) })
      input.hide()
      input.configure({ max_rows = 2 })
      input.show()
      assert.same(2, rows(w))
      cursor_in_view(w, "after show")
    end)
  end)

  describe("a bad value", function()
    local BAD = { 0, 15, -1, 2.5, 0 / 0, 1 / 0, "3", true, { } }

    it("raises from show and configure, naming the key and "
        .. "the range, and changes nothing", function()
      local input, w = program({ max_rows = 3, text = lines(5) })
      for _, bad in ipairs(BAD) do
        for _, name in ipairs({ "show", "configure" }) do
          local ok, err = pcall(input[name], { max_rows = bad })
          assert.is_false(ok, name .. " " .. tostring(bad))
          assert.matches("compy.input." .. name
            .. ": max_rows must be a whole number from 1 to 14",
            err, 1, true)
          assert.same(3, rows(w))
        end
      end
    end)

    it("1 and 14 are taken; nil leaves the rows as they are",
      function()
        local input, w = program({ max_rows = 1,
          text = lines(20) })
        assert.same(1, rows(w))
        input.configure({ max_rows = 14 })
        assert.same(14, rows(w))
        input.configure({ prompt = "x" })
        assert.same(14, rows(w))
        input.configure({ max_rows = 1 })
        input.configure({ })
        assert.same(1, rows(w))
      end)
  end)
end)
