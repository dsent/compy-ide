-- Every row of the screen is one height, on one grid from the
-- top: the console's output rows, the document view's, the
-- status line's and the field's. The document view draws
-- whole rows only: a row hidden beyond either edge leaves no
-- part of itself on the screen, and a text file's rows sit on
-- the same rows as a Lua file's.

local K = require("tests.helpers.editor_keys")
local Layout = require("view.layout")

local function view_cfg()
  return K.cc.view.cfg.view
end

local function pitch()
  return K.ed.view:get_current_buffer():row_height()
end

--- What the view's draw leaves wrong of its texts in screen
--- `s`: each text off the grid, above the view or under the
--- status line, or more than one row.
local function off_rows(s)
  local fh, band = pitch(), s.field_y
  local top = Layout(view_cfg()).top
  local wrong = { }
  for _, t in ipairs(s.texts) do
    local k = (t.y - top) / fh
    local on_row = math.abs(k - math.floor(k + 0.5)) < 1e-6
    local inside = top <= t.y and t.y + fh <= band
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
  end)

  it("have the screen's one height: the console's output and "
      .. "the view take 16, the status line follows", function()
    local cfg = view_cfg()
    local l = Layout(cfg)
    -- the console
    local s = K.screen()
    assert.same(1, s.field_rows)
    assert.same(16 * cfg.fh, K.cc.view.drawable_height)
    assert.same(l.top + 16 * cfg.fh, s.field_y)
    -- the editor: no strip above the status line
    K.open("tall.lua")
    s = K.screen()
    assert.same(cfg.fh, pitch())
    local bv = K.ed.view:get_current_buffer()
    assert.same(16, bv:get_height())
    assert.same(l.top + 16 * cfg.fh, s.field_y)
    -- a taller field takes whole rows of the view
    K.browse_to(2)
    K.keys("f2")
    s = K.screen()
    assert.is_true(1 < s.field_rows)
    assert.same(l.top + bv:get_height() * cfg.fh, s.field_y)
    assert.same(cfg.h - l.bottom,
      s.field_y + l.status_h + s.field_rows * cfg.fh)
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
