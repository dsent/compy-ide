bg_color = Color.black
body_color = Color.green
limb_color = body_color + Color.bright
debug_color = Color.yellow

function drawBackground(color)
  local c = bg_color
  local not_green = color ~= body_color
       and color ~= limb_color
  local color_valid = Color.valid(color) and not_green
  if color_valid then
    c = color
  end
  gfx.setColor(Color[c])
  gfx.rectangle("fill", 0, 0, width, height)
end

function drawFrontLegs(x_r, y_r, leg_xr, leg_yr)
  gfx.setColor(Color[limb_color])
  gfx.push("all")
  gfx.translate(-x_r, -y_r / 2 - leg_xr)
  gfx.rotate(-math.pi / 4)
  gfx.ellipse("fill", 0, 0, leg_xr, leg_yr, 100)
  gfx.pop()
  gfx.push("all")
  gfx.translate(x_r, -y_r / 2 - leg_xr)
  gfx.rotate(math.pi / 4)
  gfx.ellipse("fill", 0, 0, leg_xr, leg_yr, 100)
  gfx.pop()
end

function drawHindLegs(x_r, y_r, leg_r, leg_yr)
  gfx.setColor(Color[limb_color])
  gfx.push("all")
  gfx.translate(-x_r, y_r / 2 + leg_r)
  gfx.rotate(math.pi / 4)
  gfx.ellipse("fill", 0, 0, leg_r, leg_yr, 100)
  gfx.pop()
  gfx.push("all")
  gfx.translate(x_r, y_r / 2 + leg_r)
  gfx.rotate(-math.pi / 4)
  gfx.ellipse("fill", 0, 0, leg_r, leg_yr, 100)
  gfx.pop()
end

function drawHead(y_r, head_r)
  local neck = 5
  gfx.circle(
    "fill",
    0,
    ((0 - y_r) - head_r) + neck,
    head_r,
    100
  )
end

function drawBody(x_r, y_r, head_r)
  --- body
  gfx.setColor(Color[body_color])
  gfx.ellipse("fill", 0, 0, x_r, y_r, 100)
  --- head
  drawHead(y_r, head_r)
  --- end
end

function drawTurtle(x, y)
  local head_r = 8
  local leg_xr = 5
  local leg_yr = 10
  local x_r = 15
  local y_r = 20
  gfx.push("all")
  gfx.translate(x, y)
  drawFrontLegs(x_r, y_r, leg_xr, leg_yr)
  drawHindLegs(x_r, y_r, leg_xr, leg_yr)
  drawBody(x_r, y_r, head_r)
  gfx.pop()
end

function drawHelp()
  local x = 15
  gfx.setColor(Color[Color.white])
  gfx.print("Press [I] to open console", x, 20)
  local help = "Enter 'forward', 'back', 'left', or 'right' "
      .. "to move the turtle!"
  gfx.print(help, x, 50)
end

function drawDebuginfo()
  gfx.setColor(Color[debug_color])
  local dt = string.format("Turtle position: (%d, %d)", tx, ty)
  gfx.print(dt, width - 500, 80)
end
