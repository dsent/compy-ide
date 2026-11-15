local gfx = love.graphics

--- @class TerminalView
TerminalView = {}

local utf8 = require("utf8")

--- One cell: its background, unless drawn over a program's
--- picture, then its character
--- @param state { color: number[], backcolor: number[],
---   reversed: boolean? }
local function draw_cell(char, state, left, top, cw, ch, overlay)
  local back, fore
  if state.reversed then
    back, fore = state.color, state.backcolor
  else
    back, fore = state.backcolor, state.color
  end
  if overlay then
    back = Color.with_alpha(back, 0.25)
    fore = Color.with_alpha(fore, 0.75)
  else
    gfx.setColor(unpack(back))
    gfx.rectangle("fill", left, top, cw, ch)
  end
  local bm, am = gfx.getBlendMode()
  gfx.setBlendMode('alpha', "alphamultiply")
  gfx.setColor(unpack(fore))
  gfx.print(char, left, top)
  gfx.setBlendMode(bm, am)
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

--- Grid row `y` drawn at the canvas's row `at`
local function draw_grid_row(terminal, y, at, overlay)
  local cw, ch = terminal.char_width, terminal.char_height
  local states = terminal.state_buffer[y]
  for x, char in ipairs(terminal.buffer[y]) do
    local state = states[x]
    draw_cell(char, state, (x - 1) * cw, (at - 1) * ch, cw, ch,
      overlay)
    state.dirty = false
  end
end

--- A kept row drawn at the canvas's row `at`
local function draw_kept_row(terminal, row, at, overlay)
  local cw, ch = terminal.char_width, terminal.char_height
  each_kept_cell(row, function(x, char, style)
    draw_cell(char, style, (x - 1) * cw, (at - 1) * ch, cw, ch,
      overlay)
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
    if window then
      for at, r in ipairs(window) do
        if r.kept then
          draw_kept_row(terminal, r.kept, at, overlay)
        elseif r.y then
          draw_grid_row(terminal, r.y, at, overlay)
        end
      end
    else
      for y = 1, #terminal.buffer do
        draw_grid_row(terminal, y, y, overlay)
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
