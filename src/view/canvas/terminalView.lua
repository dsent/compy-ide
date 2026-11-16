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

--- @param a number[]
--- @param b number[]
local function same_color(a, b)
  return a == b or a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
      and (a[4] or 1) == (b[4] or 1)
end

--- Which characters stand alone, for each font and each width
--- of a cell
--- @type table<love.Font, table<number, table<string, boolean>>>
local alone = setmetatable({ }, { __mode = 'k' })

--- Whether `char` is drawn on its own at its cell and not in a
--- run of text: one that does not advance by a cell's width, as
--- a fallback font's glyph or a tab, and so would move the
--- characters after it in a run off their cells.
--- @param terminal table
--- @param char string
--- @return boolean
local function stands_alone(terminal, char)
  local font, cw = terminal.font, terminal.char_width
  local widths = alone[font]
  if not widths then
    widths = { }
    alone[font] = widths
  end
  local known = widths[cw]
  if not known then
    known = { }
    widths[cw] = known
  end
  local a = known[char]
  if a == nil then
    a = font:getWidth(char) ~= cw
    known[char] = a
  end
  return a
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

--- A kept row's cells as the grid holds its own rows: the
--- characters and their styles
--- @param row KeptRow
--- @return string[] chars, KeptStyle[] styles
local function kept_cells(row)
  local chars, styles = { }, { }
  each_kept_cell(row, function(x, char, style)
    chars[x], styles[x] = char, style
  end)
  return chars, styles
end

--- A row's backgrounds at the canvas's row `at`: a rectangle for
--- each run of cells of one background
--- @param terminal table
--- @param styles table[]
--- @param at integer
local function draw_backs(terminal, styles, at)
  local cw, ch = terminal.char_width, terminal.char_height
  local top = (at - 1) * ch
  local from, color = 1, nil
  for x = 1, #styles + 1 do
    local back = styles[x] and cell_colors(styles[x])
    if color and not (back and same_color(color, back)) then
      gfx.setColor(unpack(color))
      gfx.rectangle("fill", (from - 1) * cw, top,
        (x - from) * cw, ch)
      from = x
    end
    color = back
  end
end

--- A row's characters at the canvas's row `at`: a print for each
--- run of characters of one color. A space takes any color, so
--- it stays in the run it is in; a character that stands alone
--- is printed at its own cell. Every cell's character is in a
--- print, a space too: the font fills its texture in the order
--- characters are first printed, and text drawn from a texture
--- filled in another order differs by a shade.
--- @param terminal table
--- @param chars string[]
--- @param styles table[]
--- @param at integer
--- @param overlay boolean?
local function draw_text(terminal, chars, styles, at, overlay)
  local cw = terminal.char_width
  local top = (at - 1) * terminal.char_height
  --- the run in progress: its first cell, and its color once a
  --- character that is no space has given it one
  local from, color
  local function flush(to)
    if not from then return end
    if color then
      if overlay then
        color = Color.with_alpha(color, 0.75)
      end
      gfx.setColor(unpack(color))
    end
    gfx.print(table.concat(chars, '', from, to),
      (from - 1) * cw, top)
    from, color = nil, nil
  end
  for x = 1, #chars do
    local char = chars[x]
    if char == ' ' then
      from = from or x
    else
      local _, fore = cell_colors(styles[x])
      if stands_alone(terminal, char) then
        flush(x - 1)
        from, color = x, fore
        flush(x)
      elseif not from then
        from, color = x, fore
      elseif not color then
        color = fore
      elseif not same_color(color, fore) then
        flush(x - 1)
        from, color = x, fore
      end
    end
  end
  flush(#chars)
end

--- The canvases last drawn over a program's picture: faint
--- characters and no backgrounds
--- @type table<love.Canvas, boolean>
local overlaid = setmetatable({ }, { __mode = 'k' })

--- @param terminal table
--- @param overlay boolean?
--- @param window ViewRow[]? --- a scrolled view's rows; the
--- grid as it is when nil
local function terminal_draw(terminal, canvas, overlay, window)
  local char_width, char_height =
      terminal.char_width, terminal.char_height

  -- A canvas drawn over a program's picture is drawn again once
  -- the picture is gone, though the output did not change: it
  -- would show its faint characters on no ground until the next
  -- output.
  if terminal.dirty or overlay or overlaid[canvas] then
    overlaid[canvas] = overlay or nil
    gfx.push('all')
    gfx.setCanvas(canvas)
    gfx.setFont(terminal.font)
    gfx.clear(terminal.clear_color_alpha)
    --- the rows to draw: their characters, styles and place
    local rows = { }
    local function grid(y, at)
      local states = terminal.state_buffer[y]
      rows[#rows + 1] = { terminal.buffer[y], states, at }
      for x = 1, #states do states[x].dirty = false end
    end
    if window then
      for at, r in ipairs(window) do
        if r.kept then
          local chars, styles = kept_cells(r.kept)
          rows[#rows + 1] = { chars, styles, at }
        elseif r.y then
          grid(r.y, at)
        end
      end
    else
      for y = 1, #terminal.buffer do
        grid(y, y)
      end
    end
    -- All the backgrounds are down before any character, so a
    -- character's ink is never cut where it reaches past its
    -- cell: a block or a box line by a pixel at each side, an
    -- arrow or a CJK character by a few. Whoever wants such ink
    -- cut at the next cell draws that cell's background again
    -- after the character, in draw_text. Over a program's
    -- picture (`overlay`) the backgrounds stay out.
    if not overlay then
      for _, r in ipairs(rows) do
        draw_backs(terminal, r[2], r[3])
      end
    end
    gfx.setBlendMode('alpha', "alphamultiply")
    for _, r in ipairs(rows) do
      draw_text(terminal, r[1], r[2], r[3], overlay)
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
