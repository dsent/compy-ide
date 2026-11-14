-- A TPBot drives a square by the compass. Put it on the
-- floor away from metal and magnets and run this. It turns in
-- place until the compass has found its circle, then turns on
-- the spot to each side of the square and drives it for two
-- seconds. The display shows C while the compass calibrates,
-- then the side the robot is on, and X if the compass loses
-- its circle. A robot that is not on its wheels makes a sad
-- sound and stays still.

require("microbit.accelerometer")
require("microbit.audio")
require("microbit.compass")
require("microbit.display")
require("tpbot")
require("robot")

-- The heading: how much of it points north and how much east,
-- the cosine and sine of its angle from magnetic north; the
-- first side goes north
north, east = 1, 0
side = 0
turning = false

-- Gains tried on a TPBot
robot.pid(100, 30, 5)

function robot.drive(left, right)
  tpbot.set_motors_speed(left, right)
end

-- Each side starts with a turn on the spot to its heading:
-- speed 0 for 700 ms. The TPBot's nose is -z in the board's
-- axes.
function nextSide()
  if side < 4 then
    side = side + 1
    microbit.display.printAsync(tostring(side))
    turning = true
    robot.hold(0, 0, -1, north, east, 0, 700)
  else
    microbit.display.clear()
  end
end

-- Then the side is driven at speed 40 for 2000 ms. The next
-- side's heading is a quarter turn clockwise.
function driveSide()
  turning = false
  robot.hold(0, 0, -1, north, east, 40, 2000)
  north, east = -east, north
end

function robot.done(lost)
  if lost then
    microbit.display.printAsync("X")
  elseif turning then
    driveSide()
  else
    nextSide()
  end
end

-- The compass says found again after a short loss; the
-- square starts only the first time
function microbit.compass.found()
  if side == 0 then
    nextSide()
  end
end

-- The board stands upright in a TPBot, so a robot on its
-- wheels has up mostly along the board's -y
function upright(up_x, up_y, up_z)
  return math.abs(up_x) < -up_y and math.abs(up_z) < -up_y
end

-- Turn in place, so that the compass sees the field go round
-- and finds its circle; heading noise 0.15 rad, 9 degrees
function calibrate(up_x, up_y, up_z)
  microbit.compass.track(up_x, up_y, up_z, 0.15)
  microbit.display.printAsync("C")
  tpbot.set_motors_speed(50, -50)
end

-- Wait until the robot stands still, to know which way is up
repeat
  up_x, up_y, up_z = microbit.accelerometer.vertical()
until up_x

if upright(up_x, up_y, up_z) then
  calibrate(up_x, up_y, up_z)
else
  microbit.audio.express("sad")
end
