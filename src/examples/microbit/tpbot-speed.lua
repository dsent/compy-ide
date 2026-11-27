-- A TPBot finds the powers of its motors that drive it straight
-- at a given speed, forward and backward. It drives there and
-- back across a page of black stripes, and its two line sensors
-- tell it how fast it goes and whether it turns.
--
-- Print tpbot-stripes-a4.pdf or tpbot-stripes-letter.pdf on a
-- laser printer at 100%: the bar on its edge has to be 100 mm.
-- Tape the page to a table, and put the robot in the middle of
-- it, on the white before the first stripe, its nose along the
-- page. Press A. It shows F while it drives forward and B while
-- it drives back, and at the end P, and prints the powers to
-- give its motors.
--
-- This is what one TPBot did.
--
-- A line sensor sees a stripe about 3 mm narrower than it is
-- printed. It saw every stripe 6 mm wide, missed one of 5 mm
-- and saw none of 4 mm. The black of an inkjet printer, an
-- Epson, and of a felt pen was white to it.
--
-- With fresh batteries and both wheels at one power it went:
--
--   power            40   45   50   60
--   forward mm/s    252  281  307  354
--   backward mm/s   164  190  216  261
--
-- At each end of the page, stopping and starting, it turned by
-- a few degrees. Before it learnt to steer back, that grew to
-- 20 degrees in four rounds: it went more than 12 mm from
-- stripe to stripe, so it measured itself slower than it went
-- and gave its motors too much power. Steering back, it stayed
-- within 5 degrees, moved 3 to 5 cm sideways in four rounds,
-- and found:
--
--   forward: tpbot.set_motors_speed(33, 34)
--   backward: tpbot.set_motors_speed(-49, -51)

require("microbit.display")
require("tpbot")

-- The speed to find the powers for, in mm a second
speed = 200

-- A stripe comes every 12 mm: 6 mm of black, 6 mm of white.
-- The line sensors are 15 mm apart.
pitch = 12
sensors = 15

-- How many times to drive there and back
rounds = 4

-- What the robot learns, forward (1) and backward (-1): the
-- power of both wheels, and how much more of it the right one
-- gets and the left one less. A wheel's power is a whole
-- number.
power, turn = { }, { }
turn[1], turn[-1] = 0, 0

-- The way the robot drives now, 1 forward or -1 backward
way = 1

-- The time from stripe to stripe, in milliseconds: the last
-- one measured, and before that the one at the speed to find
period = 1000 * pitch / speed

-- Both wheels get level, the right one steer more and the
-- left one steer less
function drive(level, steer)
  tpbot.set_motors_speed(
    way * (level - steer),
    way * (level + steer)
  )
end

-- A line sensor came onto a stripe: its time, in microseconds,
-- goes on the sensor's list, lefts or rights. A second black
-- sooner than half a period after the last is the same
-- stripe's flicker. Once both sensors are on a stripe, the
-- robot knows where it is.
-- heard is when the last stripe came, in milliseconds.
function entered(list, time)
  local last = list[#list]
  local fresh = not last or last + 500 * period < time
  if fresh then
    list[#list + 1] = time
    heard = microbit.systemTime()
    if #lefts == #rights then
      stripe(#lefts)
    end
  end
end

-- The state holds the line sensors, the left one and the right
-- one, each 1 over black, and left_on and right_on hold them
-- from before. A sensor that was on white and now is on black
-- came onto a stripe.
function tpbot.onLineChange(state, time)
  local left, right = state % 2, math.floor(state / 2)
  if left_on < left then
    entered(lefts, time)
  end
  if right_on < right then
    entered(rights, time)
  end
  left_on, right_on = left, right
end

-- How fast the robot went from the stripe before, in mm a
-- second: 12 mm in the microseconds the two sensors took
function measured(k)
  local left = lefts[k] - lefts[k - 1]
  local right = rights[k] - rights[k - 1]
  local took = (left + right) / 2
  return 1000000 * pitch / took
end

-- How far the robot is turned from straight across the
-- stripes at stripe k, in radians while it is small: the right
-- sensor comes onto it later than the left by the way the robot
-- went meanwhile, at now mm a second, over the 15 mm between
-- them
function angle(k, now)
  local late = (rights[k] - lefts[k]) / 1000000
  return late * now / sensors
end

-- At the first stripe the robot is moving, and goes on at the
-- power it learnt, or at push, the one that moved it. At each
-- next one the power changes by half of how far the speed is
-- off: one more power is about 5 mm a second more.
-- The robot also steers back to straight across the stripes:
-- 30 times the angle turns it back within a second. Each
-- stripe, 3 times the angle stays in turn, until the robot
-- goes straight with no steering back.
function stripe(k)
  power[way] = power[way] or push
  local steer = turn[way]
  if 1 < k then
    local now = measured(k)
    local tilt = angle(k, now)
    power[way] = power[way] + (speed - now) / 10
    period = 1000 * pitch / now
    turn[way] = turn[way] + 3 * tilt
    steer = turn[way] + 30 * tilt
  end
  drive(power[way], steer)
end

-- Whether the robot is past the page: no stripe for 1.5 s
-- before the second, or for one and a half stripes after it
function past()
  local waited = microbit.systemTime() - heard
  if math.min(#lefts, #rights) < 2 then
    return 1500 < waited
  end
  return 1.5 * period < waited
end

-- One drive across the page. Before it moves, the power grows
-- from 30, too little to move, by 20 a second until the robot
-- reaches the first stripe. Past the page, the robot stops and
-- stands for a second.
function cross()
  lefts, rights, left_on, right_on = { }, { }, 0, 0
  push, heard = 30, microbit.systemTime()
  repeat
    if #lefts == 0 then
      push = push + 0.4
      drive(push, turn[way])
    end
    microbit.sleep(20)
  until past()
  tpbot.set_motors_speed(0, 0)
  microbit.sleep(1000)
end

-- The powers learnt one way, rounded to whole numbers, as the
-- line to put into a script
function report(name, direction)
  local left = power[direction] - turn[direction]
  local right = power[direction] + turn[direction]
  print(string.format(
    "%s: tpbot.set_motors_speed(%d, %d)",
    name,
    direction * math.floor(left + 0.5),
    direction * math.floor(right + 0.5)
  ))
end

-- A drive one way, with the letter to show meanwhile
function along(direction, letter)
  way = direction
  microbit.display.printAsync(letter)
  cross()
end

function calibrate()
  tpbot.watchLine(true)
  for i = 1, rounds do
    along(1, "F")
    along(-1, "B")
  end
  tpbot.watchLine(false)
  report("forward", 1)
  report("backward", -1)
  microbit.display.printAsync("P")
end

-- The script waits for A itself, sleeping: a button's handler
-- that drove would hold every other event, the line sensors'
-- too, until it ended.
go = false
microbit.handler[microbit.DEVICE_ID_BUTTON_A] = function(value)
  if value == microbit.DEVICE_BUTTON_EVT_CLICK then
    go = true
  end
end

microbit.display.printAsync("A")
repeat
  microbit.sleep(20)
until go
calibrate()
