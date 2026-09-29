local OS = require("util.os")

local application_exit_requested = false
--- Quit events asked for by the IDE or a project, not by
--- Android closing the IDE: one mark each, holding the update
--- it was made in. A quit event is polled before the update
--- after the one it was pushed in, whatever a frame takes, so
--- a mark more than one update old belongs to an event that
--- never came (Android drops queued events as it closes the
--- IDE) and does not count.
--- @type integer[]
local asked = {}
local updates = 0

--- An update begins (Controller's love.update)
local function update_began()
  updates = updates + 1
end

--- The quit event about to come is asked for by the IDE or a
--- project in it
local function mark_exit_asked()
  asked[#asked + 1] = updates
end

--- A quit asked for, counted once: love.event.quit marks it
--- itself once the IDE has wrapped it (Controller)
local function request_exit()
  local before = #asked
  love.event.quit()
  if #asked == before then mark_exit_asked() end
end

--- Whether the quit event being handled was asked for by the
--- IDE or a project; each mark answers one event
--- @return boolean
local function consume_exit_asked()
  while #asked > 0 do
    local at = table.remove(asked, 1)
    if updates - at <= 1 then return true end
  end
  return false
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
  update_began = update_began,
  return_home_before_exit = return_home_before_exit,
}
