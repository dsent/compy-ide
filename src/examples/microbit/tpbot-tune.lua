-- A TPBot finds its own gains for robot.pid, the way Ziegler
-- and Nichols found them for machines in 1942. Put it on the
-- floor away from metal and magnets, built as it will be
-- driven, and run this.
--
-- The robot turns a quarter turn and holds the new heading,
-- with only the first gain, kp. A small kp turns it gently and
-- it stops near the heading. Each next turn has a larger kp,
-- until the robot swings past the heading and back again, and
-- the swings no longer die away. That kp and the time of one
-- swing are all the method needs: it prints the line with the
-- three gains to put into a script for this robot.
--
-- The display shows C while the compass calibrates, T while
-- the robot tries kp after kp, P when the gains are printed,
-- and X if the compass loses its circle.

require("microbit.accelerometer")
require("microbit.audio")
require("microbit.compass")
require("microbit.display")
require("tpbot")
require("robot")

-- The mean wheel speed to find the gains for: 0 turns in place
speed = 0

-- How far the compass may be off, 0.15 rad or 9 degrees. Swings
-- smaller than this cannot be told apart from the compass's
-- own jitter.
noise = 0.15

-- The first kp, and how much larger each next one is
kp = 20
grow = 1.25

-- Each kp is tried for 5 seconds and judged by 4 swings
try_ms = 5000
swings = 4

-- Which way the robot faces: its angle from magnetic north
-- towards east. north() says how the field lies in the board;
-- the nose is the board's -z, and how far it points east comes
-- from east = up x north.
function facing()
  local n_x, n_y, n_z = microbit.compass.north()
  if n_x then
    return math.atan2(up_y * n_x - up_x * n_y, -n_z)
  end
end

-- How far the robot still has to turn, clockwise positive.
-- The % keeps it within half a turn either way: 350 degrees to
-- go is the same as 10 degrees back.
function offset(angle)
  return ((target - angle) + math.pi) % (2 * math.pi) - math.pi
end

-- When the robot crosses the heading, by more than the noise,
-- one half swing ends: how far it went and when it came back
-- are written down, and the next half swing goes the other way.
function swing(off)
  if off * way < -noise then
    way = -way
    reaches[#reaches + 1] = reach
    crossed[#crossed + 1] = microbit.systemTime()
    reach = 0
  end
  reach = math.max(reach, math.abs(off))
end

function robot.drive(left, right)
  tpbot.set_motors_speed(left, right)
  local angle = facing()
  if angle then
    swing(offset(angle))
  end
end

-- One try: a quarter turn clockwise with this kp alone
function try()
  print("kp", kp)
  robot.pid(kp, 0, 0)
  target = target + math.pi / 2
  way, reach, reaches, crossed = 1, 0, { }, { }
  local north, east = math.cos(target), math.sin(target)
  robot.hold(0, 0, -1, north, east, speed, try_ms)
end

-- The first half swing is the turn itself. The swings after
-- it have not died away if there were enough of them and the
-- later half went as far as the earlier half, on average, give
-- or take the noise.
function sustained()
  local count = #reaches - 1
  if count < swings then
    return false
  end
  local half = math.floor(count / 2)
  local early, late = 0, 0
  for i = 1, half do
    early = early + reaches[1 + i]
    late = late + reaches[#reaches + 1 - i]
  end
  return early / half - noise <= late / half
end

-- The time of one swing, there and back, in seconds: the time
-- from the first crossing after the turn to the last, shared
-- out over the half swings between them, times two
function period()
  local halves = #crossed - 2
  return (2 * (crossed[#crossed] - crossed[2]) / halves) / 1000
end

-- Ziegler and Nichols: ku is the kp that kept the robot
-- swinging and tu the time of one swing. The gains are then
--   kp = 0.6 * ku
--   ki = 2 * kp / tu
--   kd = kp * tu / 8
function report()
  local ku, tu = kp, period()
  local gain = 0.6 * ku
  print(string.format(
    "robot.pid(%.1f, %.1f, %.2f)",
    gain,
    2 * gain / tu,
    gain * tu / 8
  ))
  microbit.display.printAsync("P")
end

function robot.done(lost)
  if lost then
    microbit.display.printAsync("X")
  elseif sustained() then
    report()
  else
    kp = kp * grow
    try()
  end
end

-- The compass says found again after a short loss; the tries
-- start only the first time, from where the robot faces
function microbit.compass.found()
  if not target then
    target = facing()
    microbit.display.printAsync("T")
    try()
  end
end

-- The board stands upright in a TPBot, so a robot on its
-- wheels has up mostly along the board's -y
function upright()
  return math.abs(up_x) < -up_y and math.abs(up_z) < -up_y
end

-- Stand for a second, so that the compass knows the heading
-- the turn is to end on, then turn in place, so that it sees
-- the field go round and finds its circle
function calibrate()
  microbit.compass.track(up_x, up_y, up_z, noise)
  microbit.display.printAsync("C")
  microbit.sleep(1000)
  tpbot.set_motors_speed(50, -50)
end

-- Wait until the robot stands still, to know which way is up
repeat
  up_x, up_y, up_z = microbit.accelerometer.vertical()
until up_x

if upright() then
  calibrate()
else
  microbit.audio.express("sad")
end
