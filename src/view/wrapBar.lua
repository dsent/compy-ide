--- A wrapped line's bar: a line that takes more than one row
--- carries a bar at the left edge, one solid stroke from the
--- middle of its first row to the middle of its last, so that
--- two wrapped lines one after the other show as two strokes
--- (the maintainer's ruling of November 15, 2026). It is drawn
--- under the text, which does not move. Where the line's first
--- or last row lies beyond the rows shown, the stroke runs to
--- that edge.
local display = require("conf.display")

local WrapBar = { }

--- The bar's strokes on the rows `first` to `last` of a
--- wrapped text: one { y, h } for each line of more than one
--- row with a row among them.
--- @param fwd table<integer, integer[]> --- a line's rows
--- @param rev table<integer, integer> --- a row's line
--- @param first integer --- the first row shown
--- @param last integer --- the last row shown
--- @param row_y fun(r: integer): number --- where row `r` starts
--- @param fh number --- a row's height
--- @return { y: number, h: number }[]
function WrapBar.strokes(fwd, rev, first, last, row_y, fh)
  local out, seen = { }, { }
  local mid = math.floor(fh / 2)
  for r = first, last do
    local l = rev[r]
    local rows = l and not seen[l] and fwd[l]
    if l then seen[l] = true end
    if rows and #rows > 1 then
      local a, b = rows[1], rows[#rows]
      local y0 = first <= a and row_y(a) + mid or row_y(first)
      local y1 = b <= last and row_y(b) + mid or row_y(last) + fh
      if y0 < y1 then
        out[#out + 1] = { y = y0, h = y1 - y0 }
      end
    end
  end
  return out
end

--- Draw the strokes at the left edge in `color`.
--- @param strokes { y: number, h: number }[]
--- @param color RGB
function WrapBar.draw(strokes, color)
  if #strokes == 0 then return end
  local gfx = love.graphics
  gfx.push('all')
  gfx.setColor(color)
  for _, s in ipairs(strokes) do
    gfx.rectangle('fill', 0, s.y, display.wrap_bar, s.h)
  end
  gfx.pop()
end

return WrapBar
