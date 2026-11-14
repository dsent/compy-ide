-- One text field, the same everywhere (the maintainer's
-- ruling of November 14, 2026): the console, the file
-- editor and a program's input field run the same keys over
-- the same draft to the same result, and a click places the
-- cursor in each. There is no selection: Shift with a move is
-- bound nowhere, and a drag selects nothing. Keys only,
-- through the K helper and the production gateway.

local F = require("tests.helpers.input_fixture")
local K = require("tests.helpers.editor_keys")

local LINES = { "one two", "three four" }

--- Each owner's field, its draft LINES, the cursor before
--- "four"; returns the field (a UserInputController).
local OWNERS = {
  console = function()
    K.reset()
    return K.cc.input
  end,
  editor = function()
    K.reset({ ["notes.txt"] = "" })
    K.cc.cfg.editor = { mouse_enabled = true }
    K.open("notes.txt")
    return K.ed.input
  end,
  program = function()
    K.reset()
    F.activate_project()
    return F.show_widget({ text = "" })
  end,
}
local ORDER = { "console", "editor", "program" }

--- @param owner string
--- @param lines string[]?
--- @param l integer?
--- @param c integer?
local function field_of(owner, lines, l, c)
  local f = OWNERS[owner]()
  f:set_text(lines or LINES)
  f:set_cursor_pos(l or 2, c or 7)
  return f
end

local function state(f)
  return {
    text = table.concat(f:get_text(), "\n"),
    cursor = { f:get_cursor_pos() },
    selected = f.model:has_selection(),
  }
end

describe("one text field everywhere #input", function()
  after_each(function()
    K.cc.cfg.editor = nil
    K.cleanup()
  end)

  -- the keys the field binds, with what each does to LINES
  -- from before "four"
  local BOUND = {
    { { "left" }, "one two\nthree four", { 2, 6 } },
    { { "right" }, "one two\nthree four", { 2, 8 } },
    { { "lctrl", "left" }, "one two\nthree four", { 2, 1 } },
    { { "lctrl", "right" }, "one two\nthree four", { 2, 11 } },
    { { "home" }, "one two\nthree four", { 2, 1 } },
    { { "end" }, "one two\nthree four", { 2, 11 } },
    { { "lctrl", "home" }, "one two\nthree four", { 1, 1 } },
    { { "lctrl", "end" }, "one two\nthree four", { 2, 11 } },
    { { "up" }, "one two\nthree four", { 1, 7 } },
    { { "lalt", "lshift", "up" }, "three four\none two", { 1, 7 } },
    { { "backspace" }, "one two\nthreefour", { 2, 6 } },
    { { "lshift", "backspace" }, "one two\nthreefour", { 2, 6 } },
    { { "delete" }, "one two\nthree our", { 2, 7 } },
    { { "lctrl", "backspace" }, "one two\nfour", { 2, 1 } },
    { { "lalt", "backspace" }, "one two\nfour", { 2, 1 } },
    { { "lctrl", "w" }, "one two\nfour", { 2, 1 } },
    { { "lctrl", "k" }, "one two\nthree ", { 2, 7 } },
    { { "lshift", "return" }, "one two\nthree \nfour", { 3, 1 } },
    { { "lalt", "return" }, "one two\nthree \nfour", { 3, 1 } },
  }
  for _, case in ipairs(BOUND) do
    local name = table.concat(case[1], "+")
    it(name .. " does the same in every field", function()
      for _, owner in ipairs(ORDER) do
        local f = field_of(owner)
        K.keys(unpack(case[1]))
        assert.same({
          text = case[2], cursor = case[3], selected = false
        }, state(f), owner)
      end
    end)
  end

  -- the keys no field binds: no selection, no Shift+Delete,
  -- and the block move is the file editor's own, not its
  -- field's
  local UNBOUND = {
    { "lshift", "left" }, { "lshift", "right" },
    { "lshift", "up" }, { "lshift", "down" },
    { "lshift", "home" }, { "lshift", "end" },
    { "lctrl", "lshift", "left" }, { "lctrl", "lshift", "end" },
    { "lshift", "delete" }, { "lctrl", "delete" },
    { "lalt", "left" }, { "lalt", "home" }, { "lalt", "end" },
  }
  for _, keys in ipairs(UNBOUND) do
    it(table.concat(keys, "+") .. " does nothing in any field",
      function()
        for _, owner in ipairs(ORDER) do
          local f = field_of(owner)
          local before = state(f)
          K.keys(unpack(keys))
          assert.same(before, state(f), owner)
        end
      end)
  end

  it("Alt+Up and Alt+Down do nothing in the console or a "
      .. "program's field", function()
    for _, owner in ipairs({ "console", "program" }) do
      local f = field_of(owner)
      local before = state(f)
      K.keys("lalt", "up")
      K.keys("lalt", "down")
      assert.same(before, state(f), owner)
    end
  end)

  it("Ctrl+K removes the rest of the line, every row of it, "
      .. "and keeps the line break", function()
    local long = string.rep("abcdefghij", 8)
    for _, owner in ipairs(ORDER) do
      local f = field_of(owner, { long, "next" }, 1, 11)
      K.keys("lctrl", "k")
      assert.same({ "abcdefghij", "next" }, f:get_text(), owner)
      assert.same({ 1, 11 }, { f:get_cursor_pos() }, owner)
    end
  end)

  it("Home and End go to the ends of the cursor's row in a "
      .. "wrapped line, Ctrl+Home and Ctrl+End to the draft's",
    function()
      local long = string.rep("abcdefghij", 8)
      for _, owner in ipairs(ORDER) do
        local f = field_of(owner, { long }, 1, 70)
        --- the second row's ends: where a row breaks is the
        --- field's own (the console's prompt takes a column)
        local first, last = f.model:get_row_span()
        assert.is_true(1 < first and last == 81, owner)
        K.keys("home")
        assert.same({ 1, first }, { f:get_cursor_pos() }, owner)
        K.keys("end")
        assert.same({ 1, last }, { f:get_cursor_pos() }, owner)
        K.keys("lctrl", "home")
        assert.same({ 1, 1 }, { f:get_cursor_pos() }, owner)
        K.keys("end")
        assert.is_true(select(2, f:get_cursor_pos()) < first,
          owner)
        K.keys("lctrl", "end")
        assert.same({ 1, 81 }, { f:get_cursor_pos() }, owner)
      end
    end)

  -- word deletion removes exactly what Ctrl+Left moves over
  -- (IS3.8: a word is a run of letters, digits and
  -- underscores), as one change
  describe("word deletion", function()
    local CASES = {
      { "q = 9", { "q = " }, { 1, 5 } },
      { "a.b", { "a." }, { 1, 3 } },
      { "f(x)", { "f(" }, { 1, 3 } },
      { "one    two", { "one    " }, { 1, 8 } },
      { "one    ", { "" }, { 1, 1 } },
      { "x = ёлка", { "x = " }, { 1, 5 } },
    }
    for _, keys in ipairs({ { "lctrl", "backspace" },
      { "lalt", "backspace" }, { "lctrl", "w" } }) do
      local name = table.concat(keys, "+")
      for _, case in ipairs(CASES) do
        it(name .. " on " .. case[1] .. " deletes what Ctrl+Left "
            .. "moves over, in every field", function()
          for _, owner in ipairs(ORDER) do
            local f = field_of(owner, { case[1] }, 1,
              string.ulen(case[1]) + 1)
            --- where Ctrl+Left lands is where the deletion ends
            K.keys("lctrl", "left")
            local left = { f:get_cursor_pos() }
            f:set_cursor_pos(1, string.ulen(case[1]) + 1)
            K.keys(unpack(keys))
            assert.same(case[2], f:get_text(), owner)
            assert.same(case[3], { f:get_cursor_pos() }, owner)
            assert.same(left, case[3], owner)
            K.keys("lctrl", "z")
            assert.same({ case[1] }, f:get_text(), owner)
          end
        end)
      end
    end

    it("at a line's start it joins the lines, the break alone "
        .. "removed; at the draft's start nothing", function()
      for _, owner in ipairs(ORDER) do
        local f = field_of(owner, { "ab cd", "ef" }, 2, 1)
        K.keys("lctrl", "backspace")
        assert.same({ "ab cdef" }, f:get_text(), owner)
        assert.same({ 1, 6 }, { f:get_cursor_pos() }, owner)
        f = field_of(owner, { "abc" }, 1, 1)
        K.keys("lctrl", "backspace")
        assert.same({ "abc" }, f:get_text(), owner)
        assert.same({ 1, 1 }, { f:get_cursor_pos() }, owner)
      end
    end)
  end)

  describe("the mouse", function()
    local Layout = require("view.layout")
    --- the point on the screen of column `col` of the field's
    --- shown row `row_from_bottom` (0, its last), the field's
    --- rows ending at the screen's bottom strip
    local function at(f, row_from_bottom, col)
      local v = f.model.cfg.view
      local bottom = love.graphics.getHeight() - Layout(v).bottom
      return v.fw * (col - 1 + 0.2),
          bottom - v.fh * (row_from_bottom + 0.5)
    end
    --- the rows the field shows
    local function shown_rows(f)
      local vis = f.model.visible
      return math.min(vis:get_content_length(),
        vis.size_max or f.model.cfg.view.input_max)
    end
    local function click(x, y)
      F.session.mousepressed(x, y, 1, false, 1)
      F.session.mousereleased(x, y, 1, false, 1)
      K.frame()
    end

    it("a click on a scrolled tall draft lands on the line its "
        .. "row shows: the first, a middle and the last row",
      function()
        local lines = { }
        for i = 1, 30 do lines[i] = "line " .. i end
        for _, owner in ipairs(ORDER) do
          local f = field_of(owner, lines, 30, 7)
          local rows = shown_rows(f)
          assert.is_true(rows < 30, owner)
          --- shown from its end, then from its start
          for _, keys in ipairs({ { "end" }, { "lctrl", "home" } })
          do
            K.keys(unpack(keys))
            local offset = f.model.visible.offset
            for _, r in ipairs({ 1, math.ceil(rows / 2), rows }) do
              click(at(f, rows - r, 2))
              assert.same({ offset + r, 2 },
                { f:get_cursor_pos() }, owner .. " row " .. r)
            end
            --- the cursor moved within the rows shown
            assert.same(offset, f.model.visible.offset, owner)
          end
        end
      end)

    it("a click lands on its own line's column below a wrapped "
        .. "line, and on a wrapped line's second row", function()
      local long = string.rep("a", 80)
      for _, owner in ipairs(ORDER) do
        local f = field_of(owner, { long, "hello" }, 1, 1)
        click(at(f, 0, 2))
        assert.same({ 2, 2 }, { f:get_cursor_pos() }, owner)
        local w = f.model.visible.wrap_w
        f = field_of(owner, { "x", long }, 1, 1)
        click(at(f, 0, 3))
        assert.same({ 2, w + 3 }, { f:get_cursor_pos() }, owner)
      end
    end)

    it("a click outside the field's rows moves no cursor: on "
        .. "the view above, on the status line", function()
      local lines = { }
      for i = 1, 30 do lines[i] = "line " .. i end
      for _, owner in ipairs(ORDER) do
        --- a draft taller than the field, its rows hidden above
        local f = field_of(owner, lines, 30, 3)
        local before = { f:get_cursor_pos() }
        local v = f.model.cfg.view
        local _, top = at(f, shown_rows(f) - 1, 1)
        click(v.fw * 2, v.fh * 2)
        click(v.fw * 2, top - v.fh)
        assert.same(before, { f:get_cursor_pos() }, owner)
      end
    end)

    it("a click in the draft places the cursor, in every "
        .. "field", function()
      for _, owner in ipairs(ORDER) do
        local f = field_of(owner)
        local x, y = at(f, 1, 3)
        F.session.mousepressed(x, y, 1, false, 1)
        F.session.mousereleased(x, y, 1, false, 1)
        K.frame()
        assert.same({ 1, 3 }, { f:get_cursor_pos() }, owner)
      end
    end)

    it("a drag selects nothing, in every field", function()
      for _, owner in ipairs(ORDER) do
        local f = field_of(owner)
        local x, y = at(f, 1, 2)
        local x2, y2 = at(f, 0, 8)
        F.set_mouse_down(true)
        F.session.mousepressed(x, y, 1, false, 1)
        F.session.mousemoved(x2, y2, x2 - x, y2 - y, false)
        F.session.mousereleased(x2, y2, 1, false, 1)
        F.set_mouse_down(false)
        K.frame()
        assert.is_false(f.model:has_selection(), owner)
        assert.same({ 1, 2 }, { f:get_cursor_pos() }, owner)
      end
    end)
  end)
end)
