--- A wrapped line's marks (the maintainer's rulings of
--- November 15 and 16, 2026): a line that takes more than one
--- row carries a small rounded corner, a fillet, at the top
--- right of every row that goes on below, at the last text
--- column, and the same corner mirrored at the bottom left of
--- every row that continues it. They are drawn under the text:
--- the glyphs, a selection and the cursor all paint over them.
--- Their colour, size and the rounding of the outer corner are
--- the theme's (`colors.editor.wrap_mark`).
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

--- Where the marks go on rows `first` to `last` of a wrapped
--- text: { row, at } with `at` 'end', the top right of a row
--- that goes on below, or 'start', the bottom left of a row
--- that continues the one above. `bare` lists rows that take
--- no 'end' mark (a continuation cue's edge row). Rows past
--- `total`, such as the row a field keeps for the cursor
--- after its text, are no rows of a line.
--- @param rev table<integer, integer> --- a row's line
--- @param first integer
--- @param last integer
--- @param total integer --- the text's rows
--- @param bare table<integer, boolean>?
--- @return { row: integer, at: 'end'|'start' }[]
function WrapMark.places(rev, first, last, total, bare)
  local out = { }
  for r = first, math.min(last, total) do
    local l = rev[r]
    local goes_on = r < total and l == rev[r + 1]
    if l and goes_on and not (bare and bare[r]) then
      out[#out + 1] = { row = r, at = 'end' }
    end
    if l and 1 < r and l == rev[r - 1] then
      out[#out + 1] = { row = r, at = 'start' }
    end
  end
  return out
end

--- Draw the marks of `places`.
--- @param places { row: integer, at: 'end'|'start' }[]
--- @param row_y fun(r: integer): number --- where row `r` starts
--- @param right number --- the last text column's right edge
--- @param fh number --- a row's height
--- @param theme WrapMarkTheme
function WrapMark.draw(places, row_y, right, fh, theme)
  if #places == 0 then return end
  local gfx = love.graphics
  local runs = WrapMark.runs(theme.size, theme.round)
  gfx.push('all')
  gfx.setColor(theme.color)
  for _, p in ipairs(places) do
    local y = row_y(p.row)
    for _, run in ipairs(runs) do
      if p.at == 'end' then
        gfx.rectangle('fill', right - run[1] - run[3], y + run[2],
          run[3], 1)
      else
        gfx.rectangle('fill', run[1], y + fh - 1 - run[2], run[3], 1)
      end
    end
  end
  gfx.pop()
end

return WrapMark
