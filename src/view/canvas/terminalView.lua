local gfx = love.graphics

--- @class TerminalView
TerminalView = {}

local utf8 = require("utf8")

--- A cell's two colors: its background's, then its character's
--- @param state { color: number[], backcolor: number[],
---   reversed: boolean? }
local function cell_colors(state)
  if state.reversed then
    return state.color, state.backcolor
  end
  return state.backcolor, state.color
end

--- How far each character's picture goes past its cell, for
--- each font
--- @type table<love.Font, table<string, integer>>
local reaches = setmetatable({ }, { __mode = 'k' })

--- How far the picture of `char` goes, read from the glyph the
--- font draws: how many cells to the right of its own it paints
--- into. A terminal that does not name its font's rasterizers
--- gets every cell after a character drawn as drawing cell by
--- cell did.
--- @param terminal table
--- @param char string
--- @return integer
function TerminalView.measure(terminal, char)
  local rasterizers = terminal.rasterizers
  if not rasterizers then return math.huge end
  --- the font's own glyph, else the first fallback's that has
  --- one, as the font chooses
  local from = rasterizers[1]
  for _, r in ipairs(rasterizers) do
    if r:hasGlyphs(char) then
      from = r
      break
    end
  end
  local glyph = from:getGlyphData(char)
  local w, h = glyph:getDimensions()
  --- a pixel's last byte is its opacity
  local size = glyph:getFormat() == 'la8' and 2 or 4
  local bytes = glyph:getString()
  local last = -1
  for y = 0, h - 1 do
    for x = w - 1, last + 1, -1 do
      if 0 < bytes:byte((y * w + x) * size + size) then
        last = x
        break
      end
    end
  end
  if last < 0 then return 0 end
  --- A picture counts as one column wider than it is: the
  --- font's texture is sampled between its pixels, so the
  --- column next to a painted one can take a trace of it, and
  --- whether it does changes as the texture fills.
  local right = glyph:getBearing() + last + 2
  local cell = terminal.char_width * terminal.font:getDPIScale()
  return math.max(0, math.ceil(right / cell) - 1)
end

--- How many cells to its right `char` paints into when a cell
--- draws it: none for most characters, one or more for one
--- as wide as its cell or wider. Measured once for a character.
--- @param terminal table
--- @param char string
--- @return integer
local function reach(terminal, char)
  local known = reaches[terminal.font]
  if not known then
    known = { }
    reaches[terminal.font] = known
  end
  local r = known[char]
  if r == nil then
    r = TerminalView.measure(terminal, char)
    known[char] = r
  end
  return r
end

--- The cells of a kept row in order: each(x, char, style)
--- @param row KeptRow
--- @param each fun(x: integer, char: string, style: KeptStyle)
local function each_kept_cell(row, each)
  local runs = row.runs
  local r, left, x = 1, runs[1] and runs[1].n or 0, 0
  for _, code in utf8.codes(row.text) do
    while left == 0 and runs[r + 1] do
      r = r + 1
      left = runs[r].n
    end
    x = x + 1
    each(x, utf8.char(code), runs[r].style)
    left = left - 1
  end
end

--- The cells of grid row `y` in order: each(x, char, style)
local function each_grid_cell(terminal, y, each)
  local states = terminal.state_buffer[y]
  for x, char in ipairs(terminal.buffer[y]) do
    local state = states[x]
    each(x, char, state)
    state.dirty = false
  end
end

--- A row at the canvas's row `at`: its backgrounds, then its
--- characters, so that calls of one kind follow each other and
--- reach the GPU together. The picture is the one that drawing
--- cell by cell, background then character, makes: there a
--- cell's background covers what an earlier character painted
--- past its own cell, so here the background of a cell that an
--- earlier character reaches is drawn again before the cell's
--- own character. Over a program's picture (`overlay`) the
--- backgrounds stay out.
--- @param terminal table
--- @param cells fun(each: fun(x: integer, char: string,
---   style: table)) --- the row's cells in order
--- @param at integer
--- @param overlay boolean?
--- @param bm string --- the blend mode the backgrounds take
--- @param am string
local function draw_row(terminal, cells, at, overlay, bm, am)
  local cw, ch = terminal.char_width, terminal.char_height
  local top = (at - 1) * ch
  if not overlay then
    gfx.setBlendMode(bm, am)
    cells(function(x, _, style)
      local back = cell_colors(style)
      gfx.setColor(unpack(back))
      gfx.rectangle("fill", (x - 1) * cw, top, cw, ch)
    end)
  end
  gfx.setBlendMode('alpha', "alphamultiply")
  --- how many cells from here on an earlier character reaches
  local reached = 0
  cells(function(x, char, style)
    local back, fore = cell_colors(style)
    local left = (x - 1) * cw
    if 0 < reached then
      reached = reached - 1
      if not overlay then
        gfx.setBlendMode(bm, am)
        gfx.setColor(unpack(back))
        gfx.rectangle("fill", left, top, cw, ch)
        gfx.setBlendMode('alpha', "alphamultiply")
      end
    end
    reached = math.max(reached, reach(terminal, char))
    if overlay then
      fore = Color.with_alpha(fore, 0.75)
    end
    gfx.setColor(unpack(fore))
    gfx.print(char, left, top)
  end)
end

--- @param terminal table
--- @param overlay boolean?
--- @param window ViewRow[]? --- a scrolled view's rows; the
--- grid as it is when nil
local function terminal_draw(terminal, canvas, overlay, window)
  local char_width, char_height =
      terminal.char_width, terminal.char_height

  if terminal.dirty or overlay then
    gfx.push('all')
    gfx.setCanvas(canvas)
    gfx.setFont(terminal.font)
    gfx.clear(terminal.clear_color_alpha)
    local bm, am = gfx.getBlendMode()
    local function grid(y, at)
      draw_row(terminal, function(each)
        each_grid_cell(terminal, y, each)
      end, at, overlay, bm, am)
    end
    if window then
      for at, r in ipairs(window) do
        if r.kept then
          draw_row(terminal, function(each)
            each_kept_cell(r.kept, each)
          end, at, overlay, bm, am)
        elseif r.y then
          grid(r.y, at)
        end
      end
    else
      for y = 1, #terminal.buffer do
        grid(y, y)
      end
    end
    terminal.dirty = false
    gfx.pop()
  end

  if terminal.cursor_visible then
    gfx.setFont(terminal.font)
    if love.timer.getTime() % 1 > 0.5 then
      gfx.print("_",
        (terminal.cursor_x - 1) * char_width,
        (terminal.cursor_y - 1) * char_height)
    end
  end
end

--- @param terminal table
--- @param y number? --- where its first row starts: under the
--- strip the screen may reserve at its top
--- @param window ViewRow[]? --- a scrolled view's rows
function TerminalView.draw(terminal, canvas, snapshot, y, window)
  gfx.setCanvas()
  gfx.push('all')

  terminal_draw(terminal, canvas, snapshot and true or nil, window)
  gfx.draw(canvas, 0, y or 0)
  gfx.setBlendMode('alpha') -- default
  gfx.pop()
end

--- The background of a view row, piece by piece, as the
--- continuation cue fades it (view/continuationCue.lua)
--- @param terminal table
--- @param r ViewRow
--- @return { x: number, w: number, color: number[] }[]
function TerminalView.row_paint(terminal, r)
  local cw = terminal.char_width
  local paint = { }
  local function add(x, _, style)
    local c = style.reversed and style.color or style.backcolor
    local p = paint[#paint]
    local same = p and p.color[1] == c[1] and p.color[2] == c[2]
        and p.color[3] == c[3]
    if same then
      p.w = p.w + cw
    else
      paint[#paint + 1] = { x = (x - 1) * cw, w = cw, color = c }
    end
  end
  if r.kept then
    each_kept_cell(r.kept, add)
  elseif r.y then
    for x, state in ipairs(terminal.state_buffer[r.y]) do
      add(x, nil, state)
    end
  end
  return paint
end
