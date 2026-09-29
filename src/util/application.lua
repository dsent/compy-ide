local OS = require("util.os")

local application_exit_requested = false
--- Quit events asked for by the IDE or a project, not by
--- Android closing the IDE, and when the last was asked. A
--- quit event is handled in the frame it is pushed or the
--- next, so a mark older than ASKED_S belongs to an event
--- that never came (Android drops queued events as it closes
--- the IDE) and does not count.
local exit_asked = 0
local exit_asked_at = nil
local ASKED_S = 0.5

--- @return number? seconds
local function now()
  local timer = love and love.timer
  return timer and timer.getTime and timer.getTime() or nil
end

--- The quit event about to come is asked for by the IDE or a
--- project in it
local function mark_exit_asked()
  exit_asked = exit_asked + 1
  exit_asked_at = now()
end

--- A quit asked for, counted once: love.event.quit marks it
--- itself once the IDE has wrapped it (Controller)
local function request_exit()
  local before = exit_asked
  love.event.quit()
  if exit_asked == before then mark_exit_asked() end
end

--- Whether the quit event being handled was asked for by the
--- IDE or a project; each mark answers one event
--- @return boolean
local function consume_exit_asked()
  if exit_asked == 0 then return false end
  local t = now()
  if t and exit_asked_at and t - exit_asked_at > ASKED_S then
    exit_asked = 0
    return false
  end
  exit_asked = exit_asked - 1
  return true
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
  consume_exit_asked = consume_exit_asked,
  mark_exit_asked = mark_exit_asked,
  return_home_before_exit = return_home_before_exit,
}
