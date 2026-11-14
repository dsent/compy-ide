-- Reading the continuation cue (FR4.8; the maintainer's
-- ruling of November 15, 2026) from a recorded draw
-- (editor_keys.lua, K.screen): the mark, its box and the
-- fade's bands at each edge of the document view and of the
-- field, and a check of one edge.

local K = require("tests.helpers.editor_keys")
local assert = require("luassert")

local C = { }

local function view_cfg()
  return K.cc.view.cfg.view
end

local function theme()
  return view_cfg().colors.editor
end

--- `c` is `rgb` at opacity `a`
local function is(c, rgb, a)
  for i = 1, 3 do
    if math.abs((c[i] or 0) - rgb[i]) >= 0.001 then
      return false
    end
  end
  return math.abs((c[4] or 1) - a) < 0.001
end

--- The cues among a draw's texts and fills: for each edge, the
--- mark's glyph and where it stands, the box, and the colours
--- of the fade's bands. `texts` and `fills` are the view's
--- (s.texts, s.fills) or the field's (s.field and the fills of
--- s.field_log).
local function cues(texts, fills)
  local t = theme().cue
  local out = { }
  local function at(y)
    for _, c in pairs(out) do
      if c.y == y then return c end
    end
  end
  for _, x in ipairs(texts) do
    if is(x.colour, t.mark, t.mark_alpha) then
      local edge = x.text == "^" and "top" or "bottom"
      out[edge] = { glyph = x.text, x = x.x, y = x.y, fades = { } }
    end
  end
  for _, f in ipairs(fills) do
    local c = at(f.y)
    if is(f.colour, t.box, t.box_alpha) then
      assert(c, "a box without a mark at " .. f.y)
      c.box = f
    end
  end
  for _, f in ipairs(fills) do
    --- a band: translucent and a sliver of a row (the view's
    --- own tint under its rows is translucent too, and tall)
    local a = f.colour[4] or 1
    local band = f.h and f.h < view_cfg().fh / 4
    if a < 1 and band and not is(f.colour, t.box, t.box_alpha) then
      for _, c in pairs(out) do
        if c.y <= f.y and f.y < c.y + view_cfg().fh then
          c.fades[#c.fades + 1] = f
        end
      end
    end
  end
  return out
end

local function field_fills(s)
  local out = { }
  for _, e in ipairs(s.field_log) do
    if e.fill then out[#out + 1] = e end
  end
  return out
end

local function view_cues(s)
  return cues(s.texts, s.fills)
end

local function field_cues(s)
  return cues(s.field, field_fills(s))
end

--- Where the document view's first and last rows start
local function view_edges()
  local bv = K.ed.view:get_current_buffer()
  local r, off, fh = bv.content.range, bv.content.offset, view_cfg().fh
  local function y(v) return bv:top() + (v - off - 1) * fh end
  return y(r.start), y(r.fin)
end

--- the colours a fade's bands are in
local function fade_colours(c)
  local seen, out = { }, { }
  for _, f in ipairs(c.fades) do
    local k = string.format("%.3f,%.3f,%.3f", f.colour[1],
      f.colour[2], f.colour[3])
    if not seen[k] then
      seen[k] = true
      out[#out + 1] = { f.colour[1], f.colour[2], f.colour[3] }
    end
  end
  return out
end

local function same_rgb(a, b)
  for i = 1, 3 do
    if math.abs(a[i] - b[i]) >= 0.001 then return false end
  end
  return true
end

--- The mark stands in the last column of the row at `y`, on
--- a box that is that cell, and the row fades in `colours`.
local function check(c, glyph, y, colours)
  local v = view_cfg()
  assert.is_table(c)
  assert.same(glyph, c.glyph)
  assert.same(y, c.y)
  local x = (v.drawableChars - 1) * v.fw
  assert.same(x, c.x)
  assert.same({ x, y, v.fw, v.fh },
    { c.box.x, c.box.y, c.box.w, c.box.h })
  assert.is_true(#c.fades >= 16)
  local got = fade_colours(c)
  assert.same(#colours, #got)
  for i, want in ipairs(colours) do
    local hit = false
    for _, g in ipairs(got) do hit = hit or same_rgb(g, want) end
    assert.is_true(hit, "the fade's colour " .. i)
  end
end


C.is = is
C.view_cues = view_cues
C.field_cues = field_cues
C.view_edges = view_edges
C.check = check
C.theme = theme
C.view_cfg = view_cfg

return C
