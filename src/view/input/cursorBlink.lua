--- The text cursor's blink (H-NFR4.4). The cursor is shown
--- for `duty` of each `period` and hidden for the rest. A key
--- press, a typed character, a click or a program's move of
--- the cursor (the input API) restarts the cycle and keeps the
--- cursor shown for one whole period, so that it never goes
--- while a person types or moves. One clock for
--- every input field: the frame time the app's update passes
--- (`pass_time`); the blink has no timer of its own.
local Blink = {
  --- seconds of frames so far
  time = 0,
  --- when the cycle last restarted
  since = 0,
}

--- @param dt number --- a frame's time, in seconds
function Blink.pass_time(dt)
  Blink.time = Blink.time + dt
end

--- The person pressed a key, typed or clicked, or a program
--- moved the cursor.
function Blink.restart()
  Blink.since = Blink.time
end

--- Whether the cursor shows now. Without a blink setting, or
--- with blinking off, it always does.
--- @param cfg BlinkConfig?
--- @return boolean
function Blink.shown(cfg)
  if not cfg or not cfg.enable then return true end
  local period = cfg.period
  local t = Blink.time - Blink.since
  if t < period then return true end
  return t % period < cfg.duty * period
end

return Blink
