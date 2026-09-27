math.randomseed(os.time())
cw, ch = gfx.getDimensions()
midx = cw / 2

require("mathlib")
examples = require("examples")

size = 28
spacing = 3
offset = size + 4

local colors = {
  bg = Color[Color.black],
  pos = Color[Color.white + Color.bright],
  neg = Color[Color.red + Color.bright],
  text = Color[Color.white],
  help = Color.with_alpha(Color[Color.white], 0.5)
}

body = ""
legend = ""
help = "Hint:\n" .. "left click for next example\n" ..
    "shift + left click to go back\n" ..
    "right click for a random one"
show_help = true
count = 16
ex_idx = 1
local time = 0

function load_example(ex)
  if type(ex) == "table" then
    body = ex.code
    setupTixy()
    legend = ex.legend
    compy.input.set_text(body)
  end
end

function advance()
  local e = examples[ex_idx]
  load_example(e)
  if ex_idx < #examples then
    ex_idx = ex_idx + 1
  end
end

function retreat()
  if 1 < ex_idx then
    local e = examples[ex_idx]
    load_example(e)
    ex_idx = ex_idx - 1
  end
end

function pick_random(t)
  if type(t) == "table" then
    local n = #t
    local r = math.random(n)
    return t[r], r
  end
end

function randomize()
  local e, i = pick_random(examples)
  load_example(e)
  ex_idx = i + 1
end

function b2n(b)
  if b then
    return 1
  else
    return 0
  end
end

function n2b(n)
  if n ~= 0 then
    return true
  else
    return false
  end
end

function tixy(t, i, x, y)
  return 0.1
end

function setupTixy()
  local code = "return function(t, i, x, y)\n" .. "  " .. body
      .. "  return r\n" .. "end"
  local f = loadstring(code)
  if f then
    setfenv(f, _G)
    time = 0
    tixy = f()
  end
end

function drawBackground()
  gfx.setColor(colors.bg)
  gfx.rectangle("fill", 0, 0, cw, ch)
end

function dotCircle(mode, radius, x, y)
  gfx.circle(
    mode,
    x * (size + spacing) + offset,
    y * (size + spacing) + offset,
    radius
  )
end

function drawCircle(color, radius, x, y)
  gfx.setColor(color)
  dotCircle("fill", radius, x, y)
  dotCircle("line", radius, x, y)
end

function clamp(value)
  local color = colors.pos
  local radius = (value * size) / 2
  if radius < 0 then
    radius = -radius
    color = colors.neg
  end
  if size / 2 < radius then
    radius = size / 2
  end
  return color, radius
end

function drawOutput()
  local index = 0
  local ts = time
  for y = 0, count - 1 do
    for x = 0, count - 1 do
      local value = tonumber(tixy(ts, index, x, y)) or -0.1
      local color, radius = clamp(value)
      drawCircle(color, radius, x, y)
      index = index + 1
    end
  end
end

function drawText()
  gfx.setColor(colors.text)
  local sof = (size / 2) + offset
  local hof = sof / 2
  gfx.printf(legend, midx + hof, sof, midx - sof)
  if show_help then
    gfx.setColor(colors.help)
    gfx.setFont(font)
    gfx.printf(help, midx + hof, ch - (5 * sof), midx - sof)
  end
end

function love.draw()
  drawBackground()
  drawOutput()
  drawText()
end

-- Continuous-session idiom (doc/input_api.md, "Submit
-- lifecycle"): consume the submitted code in on_text_entered.
-- The widget stays shown by default, and this project turns the
-- submit clear OFF (configured below, before the first show):
-- editing the running body in place is the whole demo, so the
-- just-submitted code must still be sitting there afterwards.
-- With that, after_submit has nothing left to do and is gone.
local function submit_body(text)
  body = text
  setupTixy()
  legend = ""
end

-- Escape destroys nothing by default, so this callback is not a
-- repair any more — it is what Escape MEANS here: revert the
-- strip to the last body that actually ran. The widget is still
-- standing when it runs, so the reverted text is on screen.
function compy.input.callbacks.after_cancel()
  compy.input.set_text(string.lines(body))
end

function love.update(dt)
  time = time + dt
end

-- A hook rather than love.mousepressed, because this project
-- shows the widget below it: a handler captured from love.*
-- consumes its channel outright, and a hook decides per event
-- (doc/input_api.md, "Event hooks and shortcuts — when to use
-- which"). The two buttons this game uses are claimed; any
-- other goes on to the widget.
function compy.input.hooks.mousepressed(_, _, button)
  if button == 1 then
    if Key.shift() then
      retreat()
    else
      advance()
    end
    return true
  end
  if button == 2 then
    randomize()
    return true
  end
end

advance()

-- Set this program's lifecycle once, before the first show
-- (doc/input_api.md, "Submit lifecycle"): the submitted body
-- stays in the strip so it can be edited and re-run.
compy.input.configure({ clear_on_submit = false })

compy.input.show({
  prompt = "function tixy(t, i, x, y)",
  text = string.lines(body),
  highlighter = LuaHighlighter,
  validator = LuaSyntaxValidator,
  on_text_entered = submit_body
})
