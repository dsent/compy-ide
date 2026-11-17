-- The text cursor as the field draws it (H-NFR4.4, IS3.10): a
-- block on the cursor's cell, the character under it in the
-- text's colour; past the last column of a full row, where
-- there is no cell, a bar at the field's right edge. Read
-- from the real draw (K.screen): the field is the console's
-- and a project's too.

local K = require("tests.helpers.editor_keys")
local F = require("tests.helpers.input_fixture")

local function cfg()
  return K.cc.view.cfg.view
end

--- Where the field's first row starts in its canvas: under
--- the status line.
local function first_row_y()
  return require("view.layout")(cfg()).status_h
end

local function same_colour(a, b)
  for i = 1, 3 do
    if 0.001 <= math.abs((a[i] or 0) - (b[i] or 0)) then
      return false
    end
  end
  return true
end

--- What the field drew for the cursor: its block, as the
--- cell's column and row from 1 (row 1 is the draft's first
--- shown), with the character drawn on the block after it;
--- and the bars drawn in the cursor's colour. `also` draws a
--- field the screen's own draw leaves out, after the screen's
--- own: the cursor read is then that field's, the last drawn.
local function cursor(also)
  local c = cfg()
  local colour = c.colors.input.cursor
  local out = { bars = { } }
  for _, e in ipairs(K.screen(also).field_log) do
    local own = same_colour(e.colour, colour)
    if e.fill and own and e.w == c.fw and e.h == c.fh then
      assert(also or not out.col, "one block")
      out.under, out.under_colour = nil, nil
      out.col = e.x / c.fw + 1
      out.row = (e.y - first_row_y()) / c.fh + 1
      out.x, out.y = e.x, e.y
    elseif e.text == "|" and own then
      out.bars[#out.bars + 1] = e
    elseif out.col and e.x == out.x and e.y == out.y
        and e.text then
      out.under = e.text
      out.under_colour = e.colour
    end
  end
  return out
end

--- The block stands on `col`, `row`, with `under` on it (nil:
--- an empty cell), and no bar is drawn.
local function is_block(col, row, under, also)
  local c = cursor(also)
  assert.same({
    col,
    row
  }, {
    c.col,
    c.row
  })
  assert.same(under, c.under)
  assert.same(0, #c.bars)
  if under then
    -- readable: the text's colour on the cursor's
    local colors = cfg().colors.input
    assert.is_true(same_colour(colors.console.fg,
      c.under_colour))
    assert.is_false(same_colour(colors.cursor, c.under_colour))
  end
end

describe("the text cursor drawn #editor", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  before_each(function()
    K.reset({
      ["main.lua"] = "x = 1\n",
      ["a.txt"] = "one\n"
    })
  end)

  describe("in the file editor", function()
    it("is a block on the first cell of an empty draft",
        function()
      K.open()
      assert.same("", K.draft())
      is_block(1, 1, nil)
    end)

    it("stands on the empty cell after a line's end",
        function()
      K.open()
      K.browse_to_end()
      K.type("abc")
      is_block(4, 1, nil)
    end)

    it("inside text, has the character under it on the block",
        function()
      K.open()
      K.browse_to_end()
      K.type("abc")
      K.keys("left")
      K.keys("left")
      assert.same({
        1,
        2
      }, { K.cursor() })
      is_block(2, 1, "b")
    end)

    it("at a line's start, is one block on the first cell",
        function()
      K.open()
      K.browse_to_end()
      K.type("abc")
      K.keys("home")
      is_block(1, 1, "a")
    end)

    it("at the start of a wrapped line's second row, is a "
        .. "block on that row's first cell", function()
      K.open("a.txt")
      K.browse_to_end()
      K.type(string.rep("x", 64) .. "yz")
      K.keys("home")
      assert.same({
        1,
        65
      }, { K.cursor() })
      is_block(1, 2, "y")
    end)

    it("on a second line, stands on that line's row",
        function()
      K.open("a.txt")
      K.browse_to_end()
      K.type_lines({
        "first",
        "second"
      })
      K.keys("left")
      is_block(6, 2, "d")
    end)

    it("past the last column of a full row, is a bar at the "
        .. "right edge", function()
      K.open("a.txt")
      K.browse_to_end()
      K.type(string.rep("x", 64))
      assert.same({
        1,
        65
      }, { K.cursor() })
      local c, v = cursor(), cfg()
      assert.is_nil(c.col)
      assert.same(2, #c.bars)
      -- on the row itself, half off the edge and just inside
      local edge = v.drawableChars * v.fw
      assert.same(first_row_y(), c.bars[1].y)
      assert.same(first_row_y(), c.bars[2].y)
      assert.same(edge - v.fw / 2, c.bars[1].x)
      assert.is_true(c.bars[2].x < c.bars[1].x)
      assert.is_true(edge - v.fw < c.bars[2].x)
    end)
  end)

  describe("in a project's input field", function()
    it("is the same block, the character under it on it",
        function()
      -- the fixture's widget has no view of its own: give it
      -- the field's, as a run does
      local widget = F.show_widget({ text = "hey" })
      local view = UserInputView(cfg(), widget)
      widget:init_view(view)
      local function draw()
        -- a shown widget renders when its text changes
        widget:update_view()
        view:draw()
      end
      local _, col = widget.model:get_cursor_pos()
      is_block(col, 1, ("hey "):sub(col, col):match("%S"),
        draw)
      assert.is_true(col == 1 or col == 4)
    end)
  end)

  describe("in the console", function()
    it("is a block on the first cell of an empty line",
        function()
      is_block(1, 1, nil)
    end)

    it("inside text, has the character under it on the block",
        function()
      K.type("print(1)")
      K.keys("left")
      is_block(8, 1, ")")
      K.keys("home")
      is_block(1, 1, "p")
    end)
  end)
end)
