local OS = require("util.os")

local application_exit_requested = false
--- A quit the IDE or a project asks for carries a tag as the
--- quit event's value, so love.quit can tell it from the quit
--- Android sends as it closes the IDE, which carries none. The
--- tag holds the exit status the quit was asked with (a
--- number, or 'restart'); an event Android drops takes its
--- tag with it.
---
--- Known limits: a project's love.thread gets LÖVE's own quit
--- and push, so a thread's quit goes out untagged and reads as
--- Android's, which ends the IDE on Android. A project that
--- polls events itself and pushes them again tags Android's
--- quit as asked, and love.event.clear() or a full drain of
--- the queue swallows it.
local TAG = 'compy:quit'

--- The quit event's value for a quit asked with status
--- @param status any the value love.event.quit was given
--- @return string tag
local function quit_tag(status)
  if type(status) == 'string' and status:sub(1, #TAG) == TAG then
    return status
  end
  if type(status) == 'number' then
    return TAG .. ':n:' .. string.format('%.17g', status)
  end
  if type(status) == 'string' then
    return TAG .. ':s:' .. status
  end
  return TAG
end

--- Whether a quit event's value is a tag, and the exit status
--- it holds (the value itself when it is none)
--- @param value any
--- @return boolean asked
--- @return any status
local function untag(value)
  if type(value) ~= 'string' or value:sub(1, #TAG) ~= TAG then
    return false, value
  end
  local kind, rest = value:sub(#TAG + 1):match('^:(%a):(.*)$')
  if kind == 'n' then return true, tonumber(rest) end
  if kind == 's' then return true, rest end
  return true, nil
end

local function request_exit()
  love.event.quit(quit_tag())
end

--- The tagging functions put in place, so none is wrapped twice
local tagging = setmetatable({}, { __mode = 'k' })

--- love.event's quit and push, in the given table, send every
--- quit tagged. It must be done before anything copies them:
--- a project's environment is a copy of the IDE's, love.event
--- included (ConsoleController.new), and a function saved
--- before would send its quits untagged, which reads as
--- Android's own quit.
--- @param event table? love.event, or a copy of it
local function tag_quits(event)
  if type(event) ~= 'table' then return end
  local quit, push = event.quit, event.push
  if quit and not tagging[quit] then
    local tagged = function(status)
      return quit(quit_tag(status))
    end
    tagging[tagged] = true
    event.quit = tagged
  end
  if push and not tagging[push] then
    local tagged = function(name, a, ...)
      if name == 'quit' then
        return push(name, quit_tag(a), ...)
      end
      return push(name, a, ...)
    end
    tagging[tagged] = true
    event.push = tagged
  end
end

--- The share of the display's period a frame takes at least
--- when it counts as a whole period: the wake-up after a
--- present that waited for the display, and the timer's own
--- grain, take a little of it (14.6 ms of 16.7 at 60 Hz)
local WHOLE = 7 / 8

--- The display's period in seconds, a 60 Hz one's where the
--- window reports no refresh rate. Read once, as the loop
--- starts: love.window.getMode takes 416 to 430 µs a call on a
--- Compy (November 18, 2026), and called every frame it raised
--- the IDE's CPU share by 5.5 to 7.6 points in every awake
--- state. A window that changes display or mode later keeps the
--- first period's cutoff: a frame shorter than it still sleeps,
--- so the loop does not spin.
--- @return number
local function period()
  local hz = 0
  if love.window then
    local _, _, mode = love.window.getMode()
    hz = mode and mode.refreshrate or 0
  end
  return 1 / (hz > 0 and hz or 60)
end

--- LÖVE 11.5's own love.run, with two changes: love.quit is
--- given the quit event's value, and the status the run ends
--- with is the one the quit was asked with; and the loop's
--- millisecond of sleep is left out after a frame that
--- presented and took about the display's period or more
--- (WHOLE), measured from the end of the frame before (its
--- sleep included) to the end of its present, whatever made it
--- that long: a present that waited for the display, or the
--- frame's own work. On a frame longer than the period the
--- sleep was lost outright (1.1 ms of every frame in an
--- experiment on a Compy). A shorter frame sleeps, as does one
--- that presented nothing (the window inactive, as the Android
--- activity paused), so that a loop of short frames does not
--- spin, whatever the vsync flag says.
--- @return function loop
local function run()
  if love.load then
    love.load(love.arg.parseGameArguments(arg), arg)
  end
  -- the first frame's dt leaves out the time love.load took
  if love.timer then love.timer.step() end
  local dt = 0
  local whole = period() * WHOLE
  local began = love.timer and love.timer.getTime()
  return function()
    if love.event then
      love.event.pump()
      for name, a, b, c, d, e, f in love.event.poll() do
        if name == 'quit' then
          if not love.quit or not love.quit(a) then
            local _, status = untag(a)
            return status or 0
          end
        end
        love.handlers[name](a, b, c, d, e, f)
      end
    end
    if love.timer then dt = love.timer.step() end
    if love.update then love.update(dt) end
    local presented = false
    if love.graphics and love.graphics.isActive() then
      love.graphics.origin()
      love.graphics.clear(love.graphics.getBackgroundColor())
      if love.draw then love.draw() end
      love.graphics.present()
      presented = true
    end
    if love.timer then
      local took = love.timer.getTime() - began
      if not (presented and took >= whole) then
        love.timer.sleep(0.001)
      end
      began = love.timer.getTime()
    end
  end
end

local function request_application_exit()
  application_exit_requested = true
  request_exit()
end

local function consume_application_exit_request()
  local requested = application_exit_requested
  application_exit_requested = false
  return requested
end

local function return_home_before_exit()
  if OS.get_name() == 'Android' then
    love.window.minimize()
  end
end

return {
  request_exit = request_exit,
  request_application_exit = request_application_exit,
  consume_application_exit_request = consume_application_exit_request,
  quit_tag = quit_tag,
  untag = untag,
  tag_quits = tag_quits,
  run = run,
  return_home_before_exit = return_home_before_exit,
}
