local gfx = love.graphics

--- @class TerminalView
TerminalView = {}

--- @param terminal table
--- @param overlay boolean?
local function terminal_draw(terminal, canvas, overlay)
  local char_width, char_height =
      terminal.char_width, terminal.char_height

  if terminal.dirty or overlay then
  gfx.push('all')

  gfx.setCanvas(canvas)
  gfx.setFont(terminal.font)
  gfx.clear(terminal.clear_color_alpha)

  for y, row in ipairs(terminal.buffer) do
    for x, char in ipairs(row) do
      local state = terminal.state_buffer[y][x]
      -- if state.dirty then
      local left, top =
          (x - 1) * char_width,
          (y - 1) * char_height
      local bg, fg = (function()
        local back, fore
        if state.reversed then
          back, fore = state.color, state.backcolor
        else
          back, fore = state.backcolor, state.color
        end

        if overlay then
          back = Color.with_alpha(back, 0.25)
          fore = Color.with_alpha(fore, 0.75)
        end
        return back, fore
      end)()

      -- Character background
      if not overlay then
        gfx.setColor(unpack(bg))
        gfx.rectangle("fill", left, top, char_width, char_height)
      end

      local bm, am = gfx.getBlendMode()
      gfx.setBlendMode('alpha', "alphamultiply")
      -- Character
      gfx.setColor(unpack(fg))
      gfx.print(char, left, top)

      gfx.setBlendMode(bm, am)

      state.dirty = false
      -- end
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
function TerminalView.draw(terminal, canvas, snapshot, y)
  gfx.setCanvas()
  gfx.push('all')

  if snapshot then
    terminal_draw(terminal, canvas, true)
  else
    terminal_draw(terminal, canvas)
  end
  gfx.draw(canvas, 0, y or 0)
  gfx.setBlendMode('alpha') -- default
  gfx.pop()
end
