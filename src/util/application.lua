local OS = require("util.os")

local application_exit_requested = false

local function request_exit()
  love.event.quit()
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
  return_home_before_exit = return_home_before_exit,
}
