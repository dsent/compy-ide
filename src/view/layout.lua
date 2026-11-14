--- The screen's rows, every one `cfg.fh` high on one grid
--- from the top: `cfg.lines` above the status line, the status
--- line's, the field's. What they leave of the height goes to
--- the status line and to a strip at the bottom, as
--- conf/display.lua says; the rest lies at the top.
local display = require("conf.display")

--- @class ScreenLayout
--- @field top number --- the strip reserved at the top
--- @field bottom number --- the strip reserved at the bottom
--- @field status_h number --- the status line's height

--- @param cfg ViewConfig
--- @return ScreenLayout
return function(cfg)
  local spare = math.max(0, cfg.h - (cfg.lines + 2) * cfg.fh)
  local extra = math.min(display.status_extra, spare)
  local bottom = math.min(display.bottom_strip, spare - extra)
  return {
    top = spare - extra - bottom,
    bottom = bottom,
    status_h = cfg.fh + extra,
  }
end
