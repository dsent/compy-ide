local gfx = love.graphics
local own = require('view.ownState')

local FPSfont = gfx.newFont("assets/fonts/fraps.otf", 24)

View = {
  --- @type love.Image?
  snapshot = nil,
  prev_draw = nil,
  main_draw = nil,
  end_draw = nil,
  --- The console, its output and the program's canvas over
  --- it, the status line, the band, the field, the key card
  --- and the editor, in the IDE's own graphics state
  --- (view/ownState.lua)
  --- @param C ConsoleController
  --- @param CV ConsoleView
  draw = function(C, CV)
    own(C.cfg.view.font, CV.draw, CV, C:get_terminal(),
      C:get_canvas(), View.snapshot)
  end,

  clear_snapshot = function()
    if View.snapshot then View.snapshot:release() end
    View.snapshot = nil
  end,

  drawFPS = function()
    own(nil, View._drawFPS)
  end,

  _drawFPS = function()
    local pr = love.PROFILE
    if type(pr) ~= 'table' then return end
    if love.PROFILE.fpsc == 'off' then return end

    local fps = tostring(love.timer.getFPS())
    local mode = love.PROFILE.fpsc
    local w = FPSfont:getWidth(fps)
    local fh = FPSfont:getHeight()
    local y = 10
    local x
    if mode == 'T_L'
        or mode == 'T_L_B'
    then
      x = 10
    elseif mode == 'T_R'
        or mode == 'T_R_B'
    then
      x = gfx.getWidth() - 10 - w
    end
    gfx.push('all')
    local prevCanvas = gfx.getCanvas()
    gfx.setCanvas()
    if mode == 'T_L_B' or mode == 'T_R_B' then
      gfx.setColor(Color[Color.black])
      gfx.rectangle("fill",
      x, y, w, fh - 5)
    end
    gfx.setColor(Color[Color.yellow])
    gfx.setFont(FPSfont)
    gfx.print(fps, x, y)
    gfx.setCanvas(prevCanvas)
    gfx.pop()
  end
}

--- @class ViewBase
--- @field cfg ViewConfig
--- @field draw function
