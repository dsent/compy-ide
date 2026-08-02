-- Every color Compy can draw. Each cell is filled with the
-- color it names and labelled with its number; the cell to
-- its right is the same color plus Color.bright.
-- Press Space for a picture painted only with named colors.
gfx = love.graphics

WIDTH, HEIGHT = gfx.getDimensions()
SCREEN = 0
SCREENS = 2

NAMES = {
  "black",
  "blue",
  "red",
  "magenta",
  "green",
  "cyan",
  "yellow",
  "white",
  "orange",
  "brown",
  "tan",
  "yellowgreen",
  "skyblue",
  "purple",
  "pink",
  "gray",
  "coral",
  "gold",
  "limegreen",
  "springgreen",
  "turquoise",
  "azure",
  "slateblue",
  "crimson",
  "khaki",
  "salmon",
  "mint",
  "powderblue",
  "lavender",
  "orchid",
  "royalblue",
  "slategray",
}

-- list geometry: 11 rows of 3 names. Cell height follows the
-- font rather than a guess, so rows cannot overlap.
CELL_H = gfx.getFont():getHeight() + 6
TEXT_DY = 3
TOP = CELL_H + 2
ROWS = 11
ROW_STEP = (HEIGHT - TOP - 4) / ROWS
NAME_W = 244
CHIP_W = 48
BLOCK_STEP = 330
BLOCK_X0 = 16

-- picture geometry
HORIZON = 350
FLOWERS = {
  { 150, 470, Color.pink + Color.bright },
  { 205, 505, Color.orchid + Color.bright },
  { 262, 462, Color.lavender + Color.bright },
  { 330, 520, Color.salmon + Color.bright },
  { 700, 470, Color.crimson + Color.bright },
  { 762, 512, Color.lavender + Color.bright },
  { 830, 466, Color.pink + Color.bright },
  { 900, 528, Color.orchid + Color.bright },
}

gfx.setBackgroundColor(Color[Color.black])

function indexOf(row)
  local tier = math.floor(row / 8)
  return tier * 16 + row % 8
end

function labelFor(i)
  local c = Color[i]
  local lum = 0.299 * c[1] + 0.587 * c[2] + 0.114 * c[3]
  if lum > 0.55 then
    return Color[Color.black]
  end
  return Color[Color.white + Color.bright]
end

function drawNameCell(i, text, x, y)
  gfx.setColor(Color[i])
  gfx.rectangle("fill", x, y, NAME_W, CELL_H)
  gfx.setColor(labelFor(i))
  gfx.print(text, x + 7, y + TEXT_DY)
end

function drawChip(i, x, y)
  gfx.setColor(Color[i])
  gfx.rectangle("fill", x, y, CHIP_W, CELL_H)
  gfx.setColor(labelFor(i))
  gfx.print(tostring(i), x + 7, y + TEXT_DY)
end

function drawBlock(hue, col, row)
  local i = indexOf(hue)
  local x = BLOCK_X0 + col * BLOCK_STEP
  local y = TOP + row * ROW_STEP
  drawNameCell(i, i .. " " .. NAMES[hue + 1], x, y)
  drawChip(i + 8, x + NAME_W + 6, y)
end

function drawList()
  local hint = "space: picture"
  local hint_w = gfx.getFont():getWidth(hint)
  gfx.setColor(Color[Color.white + Color.bright])
  gfx.print(hint, WIDTH - hint_w - BLOCK_X0, 2)
  for hue = 0, 31 do
    drawBlock(hue, hue % 3, math.floor(hue / 3))
  end
end

function drawSky()
  gfx.setColor(Color[Color.skyblue + Color.bright])
  gfx.rectangle("fill", 0, 0, WIDTH, HORIZON)
  gfx.setColor(Color[Color.powderblue + Color.bright])
  gfx.rectangle("fill", 0, HORIZON - 60, WIDTH, 60)
end

function drawSun()
  gfx.setColor(Color[Color.gold])
  gfx.circle("fill", 858, 92, 62)
  gfx.setColor(Color[Color.gold + Color.bright])
  gfx.circle("fill", 858, 92, 46)
  gfx.setColor(Color[Color.khaki + Color.bright])
  gfx.circle("fill", 858, 92, 30)
end

function drawCloud(x, y, w)
  gfx.setColor(Color[Color.white + Color.bright])
  gfx.ellipse("fill", x, y, w, w * 0.44)
  gfx.ellipse("fill", x - w * 0.6, y + 6, w * 0.6, w * 0.3)
  gfx.ellipse("fill", x + w * 0.62, y + 5, w * 0.55, w * 0.3)
end

function drawMountains()
  gfx.setColor(Color[Color.slategray])
  gfx.polygon("fill", 60, HORIZON, 250, 120, 440, HORIZON)
  gfx.setColor(Color[Color.slategray + Color.bright])
  gfx.polygon("fill", 330, HORIZON, 520, 170, 710, HORIZON)
  gfx.setColor(Color[Color.white + Color.bright])
  gfx.polygon("fill", 208, 178, 250, 120, 292, 178)
  gfx.polygon("fill", 486, 222, 520, 170, 554, 222)
end

function drawGround()
  gfx.setColor(Color[Color.limegreen])
  gfx.rectangle("fill", 0, HORIZON, WIDTH, HEIGHT - HORIZON)
  gfx.setColor(Color[Color.yellowgreen])
  gfx.ellipse("fill", 200, HORIZON + 30, 340, 70)
  gfx.ellipse("fill", 820, HORIZON + 24, 300, 60)
  gfx.setColor(Color[Color.limegreen + Color.bright])
  gfx.rectangle("fill", 0, 500, WIDTH, HEIGHT - 500)
end

function drawPond()
  gfx.setColor(Color[Color.azure])
  gfx.ellipse("fill", 512, 452, 132, 40)
  gfx.setColor(Color[Color.turquoise + Color.bright])
  gfx.ellipse("fill", 500, 445, 92, 22)
  gfx.setColor(Color[Color.powderblue + Color.bright])
  gfx.ellipse("fill", 470, 440, 34, 8)
end

function drawTree(x, y)
  gfx.setColor(Color[Color.brown])
  gfx.rectangle("fill", x - 12, y - 78, 24, 84)
  gfx.setColor(Color[Color.springgreen])
  gfx.circle("fill", x, y - 116, 52)
  gfx.setColor(Color[Color.limegreen + Color.bright])
  gfx.circle("fill", x - 34, y - 96, 38)
  gfx.circle("fill", x + 34, y - 98, 36)
  gfx.setColor(Color[Color.springgreen + Color.bright])
  gfx.circle("fill", x + 6, y - 140, 28)
end

function drawHouse()
  gfx.setColor(Color[Color.tan + Color.bright])
  gfx.rectangle("fill", 640, 300, 190, 120)
  gfx.setColor(Color[Color.crimson])
  gfx.polygon("fill", 620, 302, 735, 226, 850, 302)
  gfx.setColor(Color[Color.brown + Color.bright])
  gfx.rectangle("fill", 706, 350, 46, 70)
  gfx.setColor(Color[Color.gold + Color.bright])
  gfx.rectangle("fill", 660, 328, 38, 34)
  gfx.rectangle("fill", 772, 328, 38, 34)
  gfx.setColor(Color[Color.coral + Color.bright])
  gfx.rectangle("fill", 620, 296, 230, 8)
end

function drawFlowers()
  for n = 1, #FLOWERS do
    local f = FLOWERS[n]
    gfx.setColor(Color[f[3]])
    gfx.circle("fill", f[1], f[2], 9)
    gfx.setColor(Color[Color.gold + Color.bright])
    gfx.circle("fill", f[1], f[2], 4)
  end
end

function drawButterfly(x, y)
  gfx.setColor(Color[Color.purple + Color.bright])
  gfx.ellipse("fill", x - 11, y - 6, 11, 15)
  gfx.ellipse("fill", x + 11, y - 6, 11, 15)
  gfx.setColor(Color[Color.orchid + Color.bright])
  gfx.ellipse("fill", x - 9, y + 9, 8, 10)
  gfx.ellipse("fill", x + 9, y + 9, 8, 10)
  gfx.setColor(Color[Color.brown])
  gfx.ellipse("fill", x, y, 3, 17)
end

function drawPicture()
  drawSky()
  drawSun()
  drawCloud(180, 96, 62)
  drawCloud(430, 66, 46)
  drawMountains()
  drawGround()
  drawHouse()
  drawPond()
  drawTree(228, HORIZON + 96)
  drawTree(946, HORIZON + 74)
  drawFlowers()
  drawButterfly(566, 300)
  gfx.setColor(Color[Color.white + Color.bright])
  gfx.print("space: color list", 830, 2)
end

function love.draw()
  if SCREEN == 0 then
    drawList()
    return
  end
  drawPicture()
end

function love.keypressed(k)
  if k == "space" then
    SCREEN = (SCREEN + 1) % SCREENS
  end
end
