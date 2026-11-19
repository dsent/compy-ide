--- The continuation cue (FR4.8, IS2.2, IS3.13): what marks an
--- edge of the document view beyond which rows of the browsed
--- block or of the replacement target lie, and an edge of the
--- field beyond which rows of the draft lie. The edge row
--- fades toward the edge into its own background, and its last
--- column carries the mark, `^` at a top edge and `v` at a
--- bottom one, translucent on a translucent box, so that the
--- character under it stays readable (the maintainer's ruling
--- of November 15, 2026). The colours and opacities are the
--- theme's (`colors.editor.cue`). A row that is both edges,
--- the one row of a field with rows above and below it,
--- carries both marks, `^` in the column before the last and
--- `v` in the last, and no fade, so that the row the user
--- types in stays as readable as any other.
local Cue = { }

--- the bands the fade is drawn in
local STEPS = 16

--- @class CueOpts
--- @field edge 'top'|'bottom'|'both'
--- @field y number --- the top of the edge row
--- @field h number --- the edge row's height
--- @field width number --- the area's width
--- @field fw number --- a character cell's width
--- @field font love.Font
--- @field theme CueColors
--- @field paint { x: number, w: number, color: RGB }[] --- the
--- edge row's background, piece by piece

--- @param o CueOpts
function Cue.draw(o)
  local gfx = love.graphics
  local t = o.theme
  gfx.push('all')
  local sh = o.h / STEPS
  for i = 0, o.edge == 'both' and -1 or STEPS - 1 do
    local alpha = t.fade * (1 - (i + .5) / STEPS)
    local top = o.y + i * sh
    if o.edge == 'bottom' then
      top = o.y + o.h - (i + 1) * sh
    end
    for _, p in ipairs(o.paint) do
      local c = p.color
      gfx.setColor(c[1], c[2], c[3], alpha)
      gfx.rectangle('fill', p.x, top, p.w, sh)
    end
  end
  local last = (math.floor(o.width / o.fw) - 1) * o.fw
  local marks = { { o.edge == 'top' and '^' or 'v', last } }
  if o.edge == 'both' then
    marks = { { '^', last - o.fw }, { 'v', last } }
  end
  gfx.setFont(o.font)
  for _, mark in ipairs(marks) do
    local glyph, x = mark[1], mark[2]
    local b = t.box
    gfx.setColor(b[1], b[2], b[3], t.box_alpha)
    gfx.rectangle('fill', x, o.y, o.fw, o.h)
    local gw = o.font:getWidth(glyph)
    local m = t.mark
    gfx.setColor(m[1], m[2], m[3], t.mark_alpha)
    gfx.print(glyph, x + math.floor((o.fw - gw) / 2), o.y)
  end
  gfx.pop()
end

return Cue
