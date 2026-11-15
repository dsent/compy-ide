require("view.canvas.bgView")
require("view.canvas.terminalView")

local class = require("util.class")
local Layout = require("view.layout")
local Cue = require("view.continuationCue")
require("util.view")

local gfx = love.graphics

--- @class CanvasView : ViewBase
--- @field bg BGView
CanvasView = class.create(function(cfg)
  return {
    cfg = cfg,
    bg = BGView(cfg)
  }
end)

--- A scrolled view's continuation cue: at the top edge while
--- older kept rows lie above it, at the bottom while newer rows
--- lie below (view/continuationCue.lua, the editor's)
--- @param terminal table
--- @param window ViewRow[]
--- @param top number --- where the output's first row starts
--- @param above boolean
--- @param below boolean
function CanvasView:draw_cues(terminal, window, top, above, below)
  local ch = terminal.char_height
  local edges = { }
  if above then edges[#edges + 1] = { 'top', 1 } end
  if below then edges[#edges + 1] = { 'bottom', #window } end
  for _, e in ipairs(edges) do
    Cue.draw({
      edge = e[1],
      y = top + (e[2] - 1) * ch,
      h = ch,
      width = terminal.width * terminal.char_width,
      fw = terminal.char_width,
      font = terminal.font,
      theme = self.cfg.colors.editor.cue,
      paint = TerminalView.row_paint(terminal, window[e[2]]),
    })
  end
end

--- @param terminal table
--- @param canvas love.Canvas
--- @param term_canvas love.Canvas
--- @param drawable_height number
--- @param snapshot love.Image?
--- @param output CanvasModel? --- whose view of its rows is
--- drawn: scrolled, or the screen at rest
function CanvasView:draw(
    terminal, canvas, term_canvas, drawable_height, snapshot,
    output
)
  local cfg = self.cfg
  local test = cfg.drawtest

  gfx.reset()
  gfx.push('all')
  gfx.setBlendMode('alpha', 'alphamultiply') -- default
  if ViewUtils.conditional_draw('show_snapshot') then
    if snapshot then
      gfx.draw(snapshot)
    end
    self.bg:draw(drawable_height)
  end

  if not test then
    if ViewUtils.conditional_draw('show_terminal') then
      --- a strip reserved at the screen's top takes the
      --- output's ground
      local top = Layout(cfg).top
      if 0 < top and not snapshot then
        gfx.setColor(cfg.colors.terminal.bg)
        gfx.rectangle('fill', 0, 0, cfg.w, top)
        gfx.setColor(1, 1, 1, 1)
      end
      -- gfx.setBlendMode('multiply', "premultiplied")
      local window, above, below
      if output then window, above, below = output:window() end
      TerminalView.draw(terminal, term_canvas, snapshot, top,
        window)
      if window then
        self:draw_cues(terminal, window, top, above, below)
      end
    end
    if ViewUtils.conditional_draw('show_canvas') then
      gfx.draw(canvas)
    end
    gfx.setBlendMode('alpha', 'alphamultiply') -- default
  else
    gfx.setBlendMode('alpha', 'alphamultiply') -- default
    for i = 0, love.test_grid_y - 1 do
      for j = 0, love.test_grid_x - 1 do
        local off_x = cfg.debugwidth * cfg.fw
        local off_y = cfg.debugheight * cfg.fh
        local dx = j * off_x
        local dy = i * off_y
        gfx.reset()
        gfx.translate(dx, dy)

        local index = (i * love.test_grid_x) + j + 1

        local b = ViewUtils.blendModes[index]
        if b then
          -- gfx.setBlendMode('alpha') -- default
          if ViewUtils.conditional_draw('show_terminal') then
            b.blend()
            TerminalView.draw(terminal, term_canvas, snapshot)
          end
          gfx.setBlendMode('alpha') -- default
          if ViewUtils.conditional_draw('show_canvas') then
            gfx.draw(canvas)
          end

          gfx.setBlendMode('alpha') -- default
          gfx.setColor(1, 1, 1, 1)
          gfx.setFont(cfg.labelfont)

          -- gfx.print(index .. ' ' .. b.name)
          gfx.print(b.name)
        end
      end
    end
  end

  gfx.pop()
end
