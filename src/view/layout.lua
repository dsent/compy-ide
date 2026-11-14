--- The screen's rows, every one `cfg.fh` high on one grid
--- from the top: `cfg.lines` above the status line, the status
--- line's, the field's. What they leave of the height goes
--- where conf/display.lua's `spare` says.
local display = require("conf.display")

--- @class ScreenLayout
--- @field top number --- the strip reserved at the top
--- @field bottom number --- the strip reserved at the bottom
--- @field status_h number --- the status line's height

--- @param cfg ViewConfig
--- @return ScreenLayout
return function(cfg)
  local spare = math.max(0, cfg.h - (cfg.lines + 2) * cfg.fh)
  local where = display.spare
  return {
    top = where == 'top' and spare or 0,
    bottom = where == 'bottom' and spare or 0,
    status_h = cfg.fh + (where == 'status' and spare or 0),
  }
end
