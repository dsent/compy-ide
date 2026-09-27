actions = require("action")
require("drawing")

width, height = gfx.getDimensions()
midx = width / 2
midy = height / 2
incr = 10

tx, ty = midx, midy
debug = false

function eval(input)
  local f = actions[input]
  if f then
    f()
  end
end

local font = gfx.newFont(compy.fonts.mono, 32)
local debug_font = gfx.newFont(compy.fonts.serif, 20)

function love.draw()
  gfx.setFont(font)
  drawBackground()
  drawHelp()
  drawTurtle(tx, ty)
  if debug then
    gfx.setFont(debug_font)
    drawDebuginfo()
  end
end

-- Hooks run above the widget on purpose (doc/input_api.md,
-- "Why the widget sits at tier 3"), so a project that must not
-- act on keys being typed into the widget says so itself. The
-- guard is blanket, so `pause` goes quiet with `space` and
-- `shift+r`: the framework reserves `ctrl+pause` for the same
-- suspend, and a reservation no guard can reach.
--
-- Why this is a hook and not `love.keypressed`: a handler the
-- framework picks up from `love.*` CONSUMES its channel, the
-- way it does under plain LÖVE (doc/input_api.md, "How events
-- reach your project"). A project that shows the widget has to
-- register here instead, where falling through on falsey is
-- the contract and the guard above can work.
function actOnKey(key)
  if Key.shift() then
    if key == "r" then
      tx, ty = midx, midy
    end
  end
  if key == "space" then
    debug = not debug
  end
  if key == "pause" then
    pause()
  end
end

function compy.input.hooks.keypressed(key)
  if compy.input.is_shown() then
    return
  end
  actOnKey(key)
end

-- The `i` that shows the widget must not also be typed into
-- it (doc/input_api.md, "Worked example: the trigger key
-- echoes into the widget it showed"):
-- LÖVE delivers a keypressed and a textinput for one physical
-- key in no guaranteed order. This one-time guard eats that
-- echo whichever side of the open it lands on, then unregisters
-- so `i` is ordinary content afterwards.
local function arm_echo_guard()
  function compy.input.shortcuts.textinput.i()
    compy.input.shortcuts.textinput.i = nil
    return true
  end
end
arm_echo_guard()

-- One widget per command: it stays shown after submit by
-- default, so this project asks for the other behaviour once,
-- before its first show (doc/input_api.md, "Asking one
-- question"). It is a mode rather than a one-off — every submit
-- hides the widget until something passes
-- `hide_on_submit = false`, which is exactly what turtle wants
-- and why it is configured once rather than re-armed per show.
-- The widget is shown empty next time because the project
-- widget clears on submit by default.
compy.input.configure({ hide_on_submit = true })

--
-- What is left for after_submit is the echo guard, which runs
-- before the close: the next open needs a fresh one.
compy.input.callbacks.after_submit = arm_echo_guard

-- Both keyboard channels are registered here rather than as
-- love.keyreleased: this project shows the widget, so a handler
-- picked up from love.* would consume the channel above it
-- (doc/input_api.md, "How events reach your project") and the
-- widget would never see a key. Turtle used to demonstrate the
-- legacy path for its own sake; the widget is the reason it
-- stopped.
function showTurtleInput()
  compy.input.show({
    prompt = "TURTLE",
    on_text_entered = function(text)
      eval(text)
    end
  })
end

function compy.input.hooks.keyreleased(key)
  -- Open only when it is closed, and consume `i` only then: the
  -- hook runs BEFORE the widget, so without the guard every `i`
  -- typed into the widget would re-trigger show (which warns
  -- and no-ops).
  local open = key == "i" and not compy.input.is_shown()
  if open then
    showTurtleInput()
    return true
  end
end

function love.update()
  if midy < ty then
    debug_color = Color.red
  end
end
