local OS = require("util.os")

local application_exit_requested = false
--- A quit the IDE or a project asks for carries a tag as the
--- quit event's value, so love.quit can tell it from the quit
--- Android sends as it closes the IDE, which carries none. The
--- tag holds the exit status the quit was asked with (a
--- number, or 'restart'); an event Android drops takes its
--- tag with it.
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

--- LÖVE 11.5's own love.run, with one change: love.quit is
--- given the quit event's value, and the status the run ends
--- with is the one the quit was asked with
--- @return function loop
local function run()
  if love.load then
    love.load(love.arg.parseGameArguments(arg), arg)
  end
  -- the first frame's dt leaves out the time love.load took
  if love.timer then love.timer.step() end
  local dt = 0
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
    if love.graphics and love.graphics.isActive() then
      love.graphics.origin()
      love.graphics.clear(love.graphics.getBackgroundColor())
      if love.draw then love.draw() end
      love.graphics.present()
    end
    if love.timer then love.timer.sleep(0.001) end
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
  run = run,
  return_home_before_exit = return_home_before_exit,
}
