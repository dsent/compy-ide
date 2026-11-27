-- A TPBot tells how warm the air is by its sonar. A reflector
-- built on the robot stands still in front of its eyes, so the
-- way the click goes stays the same, and only the speed of
-- sound changes: sound is faster in warmer air.
--
-- Press B once to measure where the reflector is, with air set
-- to the temperature a room thermometer shows: the robot
-- prints and shows how far it is, in centimetres. Then press
-- A: it prints and shows how warm the air is, in degrees. The
-- display shows ? if no echo came back.
--
-- The reflector: on each side of the robot a long beam is
-- pinned into the holes by two pins and made longer by a
-- second beam, so that both reach about 16 cm in front of the
-- eyes. Across their ends stands a wall of beams laid one on
-- another, upright, facing the eyes at their height.
--
-- To test it, put a room thermometer next to the reflector, at
-- the same height, away from doors, windows and heaters, and
-- wait until it stops changing. Set air to what it shows, send
-- this to the board, press B, then press A ten times. Change
-- the room's temperature without moving the robot, by opening
-- a window for a while, and press A again.
--
-- This is what one TPBot did, next to a cheap room
-- thermometer:
--
-- B found the reflector at 16.19, 16.21 and 16.22 cm, and at
-- 16.56 by a balcony door, in its draught. The ruler said
-- 15.5: with that the robot would be some 25 degrees off, so
-- the reflector has to be measured by B.
--
-- Ten measurements in a row, in still air, mostly stayed
-- within 0.4 to 0.9 degrees of each other; now and then one
-- was a degree or two off.
--
-- Between 17 and 19 degrees the robot was within about 0.3
-- degrees of the thermometer.
--
-- Moving air makes the robot wrong by several degrees, up to
-- ten and more: the warm stream of a heater, wind outside, a
-- draught by a door.

require("microbit.display")
require("tpbot")

-- How far apart the eyes are, centre to centre, in cm
eyes = 4

-- How many clicks to listen to for one measurement, 60 ms each
echoes = 50

-- The air's temperature in degrees when B is pressed
air = 20

-- How far the reflector is from the eyes, in cm: measured with
-- a ruler, until B measures it by the sonar. A millimetre off
-- at 16 cm is almost 4 degrees off.
reflector = 16

-- In air sound goes 20.0469 metres a second times the square
-- root of the temperature in kelvin, which is degrees plus
-- 273.15
sound = 20.0469
kelvin = 273.15

function soundSpeed(celsius)
  return sound * math.sqrt(celsius + kelvin)
end

function airTemperature(speed)
  return (speed / sound) ^ 2 - kelvin
end

-- The click goes from one eye to the reflector and back to the
-- other eye, the two long sides of a triangle with the eyes at
-- its base. Speed in metres a second times time in
-- microseconds is the way in micrometres; each side is half
-- of it, and / 20000 gives that in centimetres. The distance
-- is the triangle's height, by Pythagoras.
function distance(time, speed)
  local side = speed * time / 20000
  return math.sqrt(side * side - (eyes / 2) ^ 2)
end

-- The same triangle the other way round, for a reflector cm
-- centimetres away: the way is known, so the time tells the
-- speed, and the speed the temperature. Centimetres over
-- microseconds times 10000 is metres a second.
function temperature(time, cm)
  local way = math.sqrt(eyes ^ 2 + 4 * cm ^ 2)
  return airTemperature(way * 10000 / time)
end

-- Prints a number with its unit and shows it on the display
function show(number, unit)
  print(string.format("%.2f %s", number, unit))
  microbit.display.printAsync(string.format("%.1f", number))
end

function measure()
  local time = tpbot.echo(echoes)
  if time then
    show(temperature(time, reflector), "degrees")
  else
    microbit.display.printAsync("?")
  end
end

function calibrate()
  local time = tpbot.echo(echoes)
  if time then
    reflector = distance(time, soundSpeed(air))
    show(reflector, "cm")
  else
    microbit.display.printAsync("?")
  end
end

microbit.handler[microbit.DEVICE_ID_BUTTON_A] = function(value)
  if value == microbit.DEVICE_BUTTON_EVT_CLICK then
    measure()
  end
end

microbit.handler[microbit.DEVICE_ID_BUTTON_B] = function(value)
  if value == microbit.DEVICE_BUTTON_EVT_CLICK then
    calibrate()
  end
end
