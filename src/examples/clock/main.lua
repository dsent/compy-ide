width, height = gfx.getDimensions()
midx = width / 2
midy = height / 2

local M = 60
local H = M * M
local D = 24

local h, m, s, t
function stencilCircle()
  love.graphics.stencil(function()
    love.graphics.setColor(Color[Color.white + Color.bright])
    local time = love.timer.getTime() * 3
    love.graphics.circle(
      "fill",
      115 * 0.5 + math.cos(time) * 20,
      50 * 0.5 + math.sin(time) * 20,
      10 + math.sin(time) * 2
    )
  end, "replace", 1)
end

function readClock()
  local time = os.date("*t")
  h = time.hour
  m = time.min
  s = time.sec
  t = s + M * m + H * h
end

function setTime()
  stencilCircle()
  readClock()
end

setTime()

math.randomseed(os.time())
color = math.random(7)
bg_color = math.random(7)
local font = gfx.newFont(compy.fonts.sans, 172)

local function pad(i)
  return string.format("%02d", i)
end

function getTimestamp()
  local hours = pad(math.fmod((t / H), D))
  local minutes = pad(math.fmod((t / M), M))
  local seconds = pad(math.fmod(t, M))
  return string.format("%s:%s:%s", hours, minutes, seconds)
end

function love.draw()
  gfx.setColor(Color[bg_color])
  gfx.rectangle("fill", 0, 0, width, height)
  gfx.setColor(Color[color + Color.bright])
  gfx.setFont(font)
  local text = getTimestamp()
  local off_x = font:getWidth(text) / 2
  local off_y = font:getHeight() / 2
  gfx.print(text, midx - off_x, midy - off_y)
end

function love.update(dt)
  t = t + dt
end

function cycle(c)
  if 7 < c then
    return 1
  end
  return c + 1
end

-- These stay in the hook rather than becoming shortcuts, though
-- 'space' / 'shift+space' / 'shift+r' name themselves like
-- combos. A shortcut matches its modifier set EXACTLY, so a
-- 'space' binding would stop firing while any unrelated
-- modifier is held, where the hook fires whatever else is down.
-- Nobody asked for that narrowing, and it is not visible in the
-- diff that would introduce it (doc/input_api.md, "Event hooks
-- and shortcuts").
local function color_cycle(k)
  if k == "space" then
    if Key.shift() then
      bg_color = cycle(bg_color)
    else
      color = cycle(color)
    end
  end
end
function love.keyreleased(k)
  color_cycle(k)
  local reset = k == "r" and Key.shift()
  if reset then
    setTime()
  end
  if k == "p" then
    pause("STOP THE CLOCKS!")
  end
end
