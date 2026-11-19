local class = require('util.class')
local Layout = require("view.layout")
local KeyCard = require('model.editor.keyCard')

--- The key card (IS3.16): drawn over the document view and
--- the editor field alike while the help key is held, with
--- the status line on the last row.
--- @class KeyCardView : ViewBase
KeyCardView = class.create(function(cfg)
  return { cfg = cfg }
end)

--- The card's area: every row but the status line's.
--- @return integer rows
--- @return integer width --- in characters
function KeyCardView:size()
  local cf = self.cfg
  return cf.lines + 1, cf.drawableChars
end

--- @param state EditorStateName
--- @param empty boolean --- the draft is empty
--- @return string[]
function KeyCardView:lines(state, empty)
  local rows, width = self:size()
  return KeyCard.lines(state, empty, rows, width)
end

--- The console's card.
--- @param live boolean? --- a program is not stopped
--- @param empty boolean? --- the field holds no text
--- @return string[]
function KeyCardView:console_lines(live, empty)
  local rows, width = self:size()
  return KeyCard.lines_of(
    KeyCard.console_cells(live, empty), rows, width)
end

--- @param state EditorStateName
--- @param empty boolean
--- @param statusline Statusline
--- @param status Status
function KeyCardView:draw(state, empty, statusline, status)
  local colors = self.cfg.colors.statusline.editor
  local cells = KeyCard.cells(state, empty)
  self:draw_cells(cells, colors, statusline, status)
end

--- @param statusline Statusline
--- @param status Status
--- @param live boolean? --- a program is not stopped
--- @param empty boolean? --- the field holds no text
function KeyCardView:draw_console(statusline, status, live, empty)
  local colors = self.cfg.colors.statusline.console
  local cells = KeyCard.console_cells(live, empty)
  self:draw_cells(cells, colors, statusline, status)
end

--- @param cells table[]
--- @param colors table --- a status line's
--- @param statusline Statusline
--- @param status Status
function KeyCardView:draw_cells(cells, colors, statusline,
                               status)
  local gfx = love.graphics
  local cf = self.cfg
  local fh, fw = cf.fh, cf.fw
  local rows, width = self:size()
  local grid, col_w, key_w, cols =
      KeyCard.layout(cells, rows, width)
  --- the card's rows on the screen's grid, the status line
  --- on the field's row; a strip reserved at an edge takes
  --- the card's ground
  local l = Layout(cf)
  local status_y = cf.h - l.bottom - l.status_h

  gfx.push('all')
  gfx.setFont(cf.font)
  gfx.setColor(colors.bg)
  gfx.rectangle('fill', 0, 0, cf.w, cf.h)
  for r, row in ipairs(grid) do
    local y = l.top + (r - 1) * fh
    for c = 1, cols do
      local cell = row[c]
      local x = ((c - 1) * col_w + 1) * fw
      if cell and cell.heading then
        gfx.setColor(colors.fg2 or colors.fg)
        gfx.print(cell.heading, x, y)
      elseif cell then
        gfx.setColor(colors.indicator)
        gfx.print(cell.key, x, y)
        gfx.setColor(colors.fg)
        gfx.print(cell.what, x + (key_w + 1) * fw, y)
      end
    end
  end
  gfx.pop()

  --- the line under the card names no screen mode: its label
  --- offers F12, which the card holds back (review r1); the
  --- label is back once F1 is released
  local under = { }
  for k, v in pairs(status) do under[k] = v end
  under.mode = nil
  gfx.push('all')
  statusline:draw(under, status_y)
  gfx.pop()
end
