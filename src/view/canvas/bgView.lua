local class = require("util.class")
local Layout = require("view.layout")

--- @class BGView : ViewBase
BGView = class.create(function(cfg)
  return { cfg = cfg }
end)

function BGView:draw(drawable_height)
  local cfg = self.cfg
  local w = cfg.w
  local from = Layout(cfg).top + drawable_height

  gfx.push('all')

  -- background in case input is not visible
  gfx.rectangle("fill", 0, from, w, cfg.h - from)
  gfx.pop()
end
