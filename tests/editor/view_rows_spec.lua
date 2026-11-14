-- The document view draws whole rows only, from the screen's
-- top at the console's pitch: a row hidden beyond either
-- edge leaves no part of itself on the screen, the last row
-- shown reaches under the status line's border at most, as
-- the console's last row does, and a text file's rows sit on
-- the same rows as a Lua file's.

local K = require("tests.helpers.editor_keys")

--- the line height main.lua gives the font on a Compy
local LINE_HEIGHT = 1.0468

local function view_cfg()
  return K.cc.view.cfg.view
end

local function pitch()
  return K.ed.view:get_current_buffer():row_height()
end

--- What the view's draw leaves wrong of its texts in screen
--- `s`: each text off the rows counted from the screen's top,
--- above the screen, more than one row, or in a row that
--- reaches under the status line beyond its border.
local function off_rows(s)
  local fh, band = pitch(), s.field_y
  local border = view_cfg().statusline_border / 2
  local wrong = { }
  for _, t in ipairs(s.texts) do
    local k = t.y / fh
    local on_row = math.abs(k - math.floor(k + 0.5)) < 1e-6
    local inside = 0 <= t.y and t.y + fh <= band + border
    if not (on_row and inside) or t.text:find("\n") then
      wrong[#wrong + 1] = string.format("%q at %.3f", t.text, t.y)
    end
  end
  return wrong
end

local function lines(n, w)
  local out = { "one" }
  local word = { }
  for i = 1, n * w / 8 do
    word[#word + 1] = string.format("word%03d", i)
  end
  out[#out + 1] = table.concat(word, " ")
  out[#out + 1] = "last"
  return table.concat(out, "\n") .. "\n"
end

describe("the document view's rows #editor", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  before_each(function()
    K.reset({
      ["main.lua"] = "x = 1\n",
      ["tall.lua"] = "a = 1\n" .. K.block(20) .. "b = 2\n",
      ["notes.txt"] = lines(20, 64),
      ["notes.md"] = lines(20, 64),
    })
    view_cfg().lh = LINE_HEIGHT
  end)

  it("have the console's pitch, and 16 of them fill the space "
      .. "above the status line", function()
    K.open("tall.lua")
    local s = K.screen()
    local cfg = view_cfg()
    assert.same(cfg.fh * cfg.lh, pitch())
    local band = s.field_y
    local rows = K.ed.view:get_current_buffer():get_height()
    assert.same(16, rows)
    assert.is_true(math.abs(rows * pitch() - band)
      <= cfg.statusline_border / 2)
  end)

  it("a target taller than the view above a taller field "
      .. "leaves no part of a row under the field", function()
    K.open("tall.lua")
    K.browse_to(2)
    K.keys("f2")
    assert.same("replacing", K.state())
    local s = K.screen()
    assert.is_true(1 < s.field_rows)
    local range = K.ed.view:get_current_buffer().content.range
    assert.is_true(range.fin < 1 + #K.block_lines(20))
    assert.same({ }, off_rows(s))
  end)

  it("a browsed block cut at both edges draws no row beyond "
      .. "either", function()
    K.open("tall.lua")
    K.browse_to(1)
    for _ = 1, 4 do
      K.keys("lctrl", "down")
    end
    assert.same(2, K.position())
    local range = K.ed.view:get_current_buffer().content.range
    assert.is_true(2 < range.start)
    local s = K.screen()
    assert.same(1, s.field_rows)
    assert.same({ }, off_rows(s))
  end)

  it("map a pixel row to the line drawn on it", function()
    K.open("tall.lua")
    K.browse_to(3)
    local bv = K.ed.view:get_current_buffer()
    local fh = pitch()
    local y
    for _, t in ipairs(K.screen().texts) do
      if t.text == "b" then y = t.y end
    end
    -- the last pixel row of b = 2, line 22, and the last of
    -- the row above it, line 21
    assert.same(22, bv:line_at(y + fh - 1))
    assert.same(21, bv:line_at(y - 1))
  end)

  for _, name in ipairs({ "notes.txt", "notes.md" }) do
    it("in " .. name .. " a long line cut at the edge draws "
        .. "each row on its own row", function()
      K.open(name)
      K.browse_to(2)
      local range = K.ed.view:get_current_buffer().content.range
      assert.is_true(1 < range.start)
      assert.same({ }, off_rows(K.screen()))
    end)
  end
end)
