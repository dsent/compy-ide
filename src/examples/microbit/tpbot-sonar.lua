-- A TPBot measures how far away a wall is with its sonar, the
-- two eyes on its front. One eye clicks, too high for us to
-- hear, and the other hears the click come back. Press A: the
-- robot listens 20 times and prints how long the click took,
-- in microseconds, and how far the wall is, in centimetres.
-- The display shows the distance, or ? if nothing came back.
--
-- To test it, lay a tape measure on the floor at a right angle
-- to a flat, hard wall, with nothing on the tape or within
-- half a metre either side of it. Set air below to the
-- room's temperature. Stand the robot on the tape facing the
-- wall, the front of its eyes at a mark, press A, step back
-- behind the robot and wait for the number. Then move it to
-- the next mark. To find how far the sonar reaches, go on in
-- steps of 50 cm until the display shows ? or a number nearer
-- than the wall. To see how precise it is, press A ten times
-- without moving the robot.
--
-- This is what one TPBot did in a room at 19 degrees. It stood
-- on a box at 6, 7, 8, 200 and 400 cm, and on the floor at the
-- other marks.
--
--   tape cm    3    5    6    7    8   10   15   20
--   sonar cm  4.8  5.7  6.4  7.7  8.6 10.1 14.9 19.4
--
--   tape cm   30   50  100   200   300   350   400
--   sonar cm 29.5 48.6 98.7 203.4 299.0 349.6 400.1
--
-- From 5 cm to 4 m the sonar was within 1.5 cm of the tape,
-- except for 3.4 cm at 2 m. At 3 cm it was off by 1.8 cm. At
-- 4 m not one click was lost. Further than about 4.2 m the
-- display shows ? whatever the sonar hears: the firmware waits
-- for an echo 25 ms at most, the time sound takes to go there
-- and back. Ten measurements at 3 m without moving the robot
-- differed by 4 mm.
--
-- At some marks the sonar heard a cabinet and other things in
-- the room before the wall, with a steady but wrong distance.

require("microbit.display")
require("tpbot")

-- The air's temperature in degrees, from a room thermometer.
-- In that room the board's microbit.thermometer said 24. Five
-- degrees off is almost 1 cm off in a metre.
air = 19

-- How far apart the eyes are, centre to centre, in cm
eyes = 4

-- How fast sound goes in air, in metres a second: 20.0469
-- times the square root of the temperature in kelvin, which
-- is degrees plus 273.15
function soundSpeed(celsius)
  return 20.0469 * math.sqrt(celsius + 273.15)
end

-- The click goes from one eye to the wall and back to the
-- other eye, the two long sides of a triangle with the eyes at
-- its base. Speed in metres a second times time in
-- microseconds is the way in micrometres; each side is half
-- of it, and / 20000 gives that in centimetres. The distance
-- is the triangle's height, by Pythagoras.
function distance(time, speed)
  local side = speed * time / 20000
  return math.sqrt(side * side - (eyes / 2) ^ 2)
end

function measure()
  local time = tpbot.echo(20)
  if time then
    local cm = distance(time, soundSpeed(air))
    print(string.format("%.0f microseconds, %.1f cm", time, cm))
    microbit.display.printAsync(tostring(math.floor(cm + 0.5)))
  else
    microbit.display.printAsync("?")
  end
end

microbit.handler[microbit.DEVICE_ID_BUTTON_A] = function(value)
  if value == microbit.DEVICE_BUTTON_EVT_CLICK then
    measure()
  end
end
