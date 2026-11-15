--- A wrapped line's mark: every row that continues a line,
--- one that takes more than one row, has a small inward
--- rounded corner at its top left, a fillet (the maintainer's
--- rulings of November 15, 2026). The line's first row has
--- none. It is drawn under the text, which does not move, and
--- in the corner the font leaves free: no glyph's ink reaches
--- it. Its colour, size and the rounding of its outer corner
--- are the theme's (`colors.editor.wrap_mark`).
local WrapMark = { }

--- @class WrapMarkTheme
--- @field color RGB
--- @field size integer --- the fillet's radius, in pixels
--- @field round number --- its outer corner's radius; 0: square

local cache = { }

--- The mark as runs of pixels, { x, y, w } from the row's top
--- left: the pixels of the size-by-size corner outside the
--- circle of radius `size` round its far corner, less those
--- outside the rounding of its outer corner.
--- @param size integer
--- @param round number
--- @return integer[][]
function WrapMark.runs(size, round)
  local key = size .. '/' .. round
  if cache[key] then return cache[key] end
  local runs = { }
  for j = 0, size - 1 do
    local from, to
    for i = 0, size - 1 do
      local x, y = i + .5, j + .5
      local on = (x - size) ^ 2 + (y - size) ^ 2 > size * size
      if on and x < round and y < round then
        on = (x - round) ^ 2 + (y - round) ^ 2 <= round * round
      end
      if on then
        from = from or i
        to = i
      end
    end
    if from then runs[#runs + 1] = { from, j, to - from + 1 } end
  end
  cache[key] = runs
  return runs
end

--- The rows `first` to `last` of a wrapped text that continue
--- a line.
--- @param rev table<integer, integer> --- a row's line
--- @param first integer
--- @param last integer
--- @return integer[]
function WrapMark.rows(rev, first, last)
  local out = { }
  for r = math.max(first, 2), last do
    if rev[r] and rev[r] == rev[r - 1] then out[#out + 1] = r end
  end
  return out
end

--- Draw the mark on each of `rows`.
--- @param rows integer[]
--- @param row_y fun(r: integer): number --- where row `r` starts
--- @param theme WrapMarkTheme
function WrapMark.draw(rows, row_y, theme)
  if #rows == 0 then return end
  local gfx = love.graphics
  local runs = WrapMark.runs(theme.size, theme.round)
  gfx.push('all')
  gfx.setColor(theme.color)
  for _, r in ipairs(rows) do
    local y = row_y(r)
    for _, run in ipairs(runs) do
      gfx.rectangle('fill', run[1], y + run[2], run[3], 1)
    end
  end
  gfx.pop()
end

return WrapMark
