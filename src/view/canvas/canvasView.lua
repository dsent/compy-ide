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

--- The screen by its mode (model/screenModel.lua):
--- - text: the console's output on its ground, no picture;
--- - combined: the program's picture on its ground, then the
---   output over it on a translucent ground of its own, its
---   text unshaded, with the two opacities of the theme's
---   `screen.combined` (the lead's decision 5 of November 17,
---   2026, open to the maintainer's choice);
--- - picture: the picture on the ground the program chose, on
---   the whole screen, alone.
--- @param terminal table
--- @param canvas love.Canvas --- the program's
--- @param term_canvas love.Canvas
--- @param drawable_height number
--- @param mode ScreenMode
--- @param output CanvasModel? --- whose view of its rows is
--- drawn: scrolled, or the screen at rest; and whose picture's
--- ground
function CanvasView:draw(
    terminal, canvas, term_canvas, drawable_height, mode,
    output
)
  local cfg = self.cfg
  local test = cfg.drawtest

  --- in the IDE's own state already (View.draw)
  gfx.push('all')
  gfx.setBlendMode('alpha', 'alphamultiply') -- default

  if not test then
    local pictured = mode == 'combined' or mode == 'picture'
    if pictured and ViewUtils.conditional_draw('show_canvas') then
      --- the ground opaque, as a screen shows a translucent
      --- clear colour, so it counts once wherever it was set
      --- (round c4)
      local ground = output and output:get_background()
          or { 0, 0, 0, 1 }
      gfx.setColor(ground[1], ground[2], ground[3], 1)
      gfx.rectangle('fill', 0, 0, cfg.w, cfg.h)
      gfx.setColor(1, 1, 1, 1)
      --- what was drawn on the canvas carries its alpha in its
      --- colour already (c1's fourth finding)
      gfx.setBlendMode('alpha', 'premultiplied')
      gfx.draw(canvas)
      gfx.setBlendMode('alpha', 'alphamultiply')
    end
    if mode ~= 'picture'
        and ViewUtils.conditional_draw('show_terminal') then
      local top = Layout(cfg).top
      --- the text's own ground: whole in text, translucent over
      --- the picture
      local shade
      if mode == 'combined' then
        local c = cfg.colors.screen.combined
        shade = c.text
        gfx.setColor(Color.with_alpha(cfg.colors.terminal.bg,
          c.ground))
        --- as high as the grid's rows, which the output's grid
        --- may grow by the field's while no field is drawn
        gfx.rectangle('fill', 0, 0, cfg.w,
          top + terminal.height * terminal.char_height)
        gfx.setColor(1, 1, 1, 1)
      else
        if ViewUtils.conditional_draw('show_snapshot') then
          self.bg:draw(drawable_height)
        end
        --- a strip reserved at the screen's top takes the
        --- output's ground
        if 0 < top then
          gfx.setColor(cfg.colors.terminal.bg)
          gfx.rectangle('fill', 0, 0, cfg.w, top)
          gfx.setColor(1, 1, 1, 1)
        end
      end
      local window, above, below
      if output then window, above, below = output:window() end
      TerminalView.draw(terminal, term_canvas, shade, top, window)
      if window then
        self:draw_cues(terminal, window, top, above, below)
      end
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
            TerminalView.draw(terminal, term_canvas)
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
