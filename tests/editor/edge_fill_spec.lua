-- The document view's rows have the console's pitch, which
-- does not divide the area above the status line: under the
-- last row a strip of a few pixels may be left, and it is
-- that row's. A highlighted block at the view's edge runs on
-- to the edge, and under the status line; no strip of the
-- view's background shows between it and the status line, or
-- the view's top (the maintainer's ruling on the browsed
-- block cut at the bottom edge).

local K = require("tests.helpers.editor_keys")

local EPS = 1e-6

local function colour_of(name)
  return K.cc.view.cfg.view.colors.editor[name]
end

local function same(a, b)
  for i = 1, 3 do
    if math.abs((a[i] or 0) - (b[i] or 0)) > 0.001 then
      return false
    end
  end
  return true
end

--- The screen's fills in a highlight's colour.
local function fills(s, name)
  local out = { }
  for _, f in ipairs(s.fills) do
    if same(f.colour, colour_of(name)) then
      out[#out + 1] = f
    end
  end
  return out
end

--- The pixel rows whose middles lie from `from` to `to` that
--- no fill in the highlight's colour covers: a pixel row is
--- covered when its middle lies in a fill.
local function bare_rows(s, name, from, to)
  local bare = { }
  for y = math.floor(from), math.floor(to - 0.5) do
    local mid, hit = y + 0.5, false
    for _, f in ipairs(fills(s, name)) do
      hit = hit or (f.y <= mid and mid < f.y + f.h)
    end
    if not hit then
      bare[#bare + 1] = y
    end
  end
  return bare
end

--- The top and the bottom of the highlight's fills.
local function extent(s, name)
  local top, bottom
  for _, f in ipairs(fills(s, name)) do
    top = math.min(top or f.y, f.y)
    bottom = math.max(bottom or f.y + f.h, f.y + f.h)
  end
  return top, bottom
end

--- Where the status line's band starts: the field's top,
--- from its rows, as the field lays itself out.
local function band_top(s)
  local v = K.cc.view.cfg.view
  local h = love.graphics.getHeight()
  return h - (s.field_rows + 1) * v.fh - v.statusline_border / 2
end

local function block_cut(b)
  local rows, shown = K.rows_shown(b)
  local range = K.ed.view:get_current_buffer().content.range
  return shown < rows, range
end

describe("the highlight at the view's edges #editor", function()
  setup(K.setup)
  teardown(K.teardown)
  after_each(K.cleanup)

  before_each(function()
    K.reset({
      ["main.lua"] = "x = 1\n\nif a then\n  b = 1\nend\n",
      ["tall.lua"] = "a = 1\n" .. K.block(24) .. "b = 2\n",
      ["target.lua"] = "a = 1\n" .. K.block(14)
          .. "b = 2\nc = 3\nd = 4\n"
    })
  end)

  it("a tall browsed block cut at the bottom reaches the "
      .. "status line", function()
    K.open("tall.lua")
    K.browse_to(1)
    K.keys("lctrl", "down")
    assert.same(2, K.position())
    local s = K.screen()
    local band = band_top(s)
    -- the field and its status line where they always are
    assert.same(1, s.field_rows)
    assert.is_true(math.abs(band - s.field_y) < EPS)
    local cut = block_cut(2)
    assert.is_true(cut)
    local top, bottom = extent(s, "highlight")
    assert.is_true(bottom >= band - EPS)
    assert.same({ }, bare_rows(s, "highlight", top, band))
  end)

  it("a tall browsed block cut at the top starts at the "
      .. "view's top", function()
    K.open("tall.lua")
    K.browse_to(3)
    K.keys("lctrl", "up")
    assert.same(2, K.position())
    local s = K.screen()
    local cut, range = block_cut(2)
    assert.is_true(cut)
    assert.is_true(1 < range.start)
    local top, bottom = extent(s, "highlight")
    assert.same(0, top)
    -- its last row is the view's last: it reaches the status
    -- line too
    local band = band_top(s)
    assert.is_true(bottom >= band - EPS)
    assert.same({ }, bare_rows(s, "highlight", 0, band))
  end)

  it("a tall browsed block cut at both edges fills the view "
      .. "from its top to the status line", function()
    K.open("tall.lua")
    K.browse_to(1)
    for _ = 1, 4 do
      K.keys("lctrl", "down")
    end
    assert.same(2, K.position())
    local s = K.screen()
    local _, range = block_cut(2)
    assert.is_true(2 < range.start)
    local rows = K.rows_shown(2)
    assert.is_true(range.fin < 1 + rows)
    local band = band_top(s)
    assert.same({ }, bare_rows(s, "highlight", 0, band))
    local _, bottom = extent(s, "highlight")
    assert.is_true(bottom >= band - EPS)
  end)

  it("a tall target cut at the bottom reaches the status line "
      .. "above a taller field", function()
    K.open("target.lua")
    K.browse_to(2)
    K.keys("f2")
    K.browse_to(1)
    assert.same("replacing", K.state())
    assert.same(2, K.target())
    local s = K.screen()
    -- the target's draft takes the field's eight rows
    assert.same(8, s.field_rows)
    local band = band_top(s)
    assert.is_true(math.abs(band - s.field_y) < EPS)
    assert.is_true(block_cut(2))
    local top, bottom = extent(s, "highlight_loaded")
    assert.is_true(top > 0)
    assert.is_true(bottom >= band - EPS)
    assert.same({ }, bare_rows(s, "highlight_loaded", top,
      band))
    -- the browsing position, block 1, keeps its one row
    assert.same(1, #fills(s, "highlight"))
  end)

  it("a tall block that is both reaches the status line in "
      .. "both colours", function()
    K.open("target.lua")
    K.browse_to(2)
    K.keys("f2")
    assert.same(2, K.target())
    assert.same(2, K.position())
    local s = K.screen()
    local band = band_top(s)
    assert.is_true(block_cut(2))
    for _, name in ipairs({ "highlight", "highlight_loaded" }) do
      local top, bottom = extent(s, name)
      assert.is_true(bottom >= band - EPS)
      assert.same({ }, bare_rows(s, name, top, band))
    end
  end)

  it("a short block in the middle of the view keeps its rows",
      function()
    K.open()
    K.browse_to(3)
    local s = K.screen()
    local pitch = K.ed.view:get_current_buffer():row_height()
    local white = fills(s, "highlight")
    assert.same(3, #white)
    for _, f in ipairs(white) do
      assert.is_true(math.abs(f.h - pitch) < EPS)
    end
    local _, bottom = extent(s, "highlight")
    assert.is_true(bottom < band_top(s) - pitch)
  end)
end)
