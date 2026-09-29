local OS = require("util.os")

local application_exit_requested = false
--- The next quit event was asked for by the IDE itself, not
--- by Android closing it
local exit_asked = false

local function request_exit()
  exit_asked = true
  love.event.quit()
end

--- Whether the quit event being handled was asked for by the
--- IDE; the answer is given once
--- @return boolean
local function consume_exit_asked()
  local asked = exit_asked
  exit_asked = false
  return asked
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
  return_home_before_exit = return_home_before_exit,
}
