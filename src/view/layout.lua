--- The screen's rows, every one `cfg.fh` high on one grid
--- from the top: `cfg.lines` above the status line, the status
--- line's, the field's. What they leave of the height goes to
--- the status line and to a strip at the bottom, as
--- conf/display.lua says; the rest lies at the top. The status
--- line's text keeps a row's place in its own row, and the
--- pixels the line gains split evenly above and below it (an
--- odd one goes below).
local display = require("conf.display")

--- @class ScreenLayout
--- @field top number --- the strip reserved at the top
--- @field bottom number --- the strip reserved at the bottom
--- @field status_h number --- the status line's height
--- @field status_pad number --- pixels above its text

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
    status_pad = math.floor(extra / 2),
  }
end
