--- @alias SerialEnv 'console' | 'program'
--- @alias SerialEvent 'connect' | 'disconnect' | 'bytes' | 'line'
---   | 'tick'

--- Delivery by assignment, the love way: each environment
--- owns a compy.serial table and assigns its handlers to
--- fields. Nothing registers by call; at delivery time the
--- current value of the field is read, and called if it is
--- a function.

--- @class Dispatcher
--- @field new function
--- @field table_for function
--- @field suspend_env function
--- @field resume_env function
--- @field clear_env function
--- @field has_handler function
--- @field push function
--- @field pump function
Dispatcher = {}
Dispatcher.__index = Dispatcher

local End = require('util.program_end')

local FIELDS = {
  connect = 'onConnect',
  disconnect = 'onDisconnect',
  bytes = 'onBytes',
  line = 'onLine',
  tick = 'onTick',
}

local ENVS = { console = true, program = true }

--- The order each event goes round in: the console first, so
--- a program's handler that turns the console's on hands it
--- the next event, never this one again
local ORDER = { 'console', 'program' }

--- @param env SerialEnv
local function check_env(env)
  if not ENVS[env] then
    error('no such environment: ' .. tostring(env))
  end
end

--- @return Dispatcher
function Dispatcher.new()
  local self = setmetatable({}, Dispatcher)
  self.tables = { console = {}, program = {} }
  self.queue = {}
  self.suspended = {}
  return self
end

--- The environment's compy.serial table; handlers are
--- assigned to its fields by the code running there
--- @param env SerialEnv
--- @return table
function Dispatcher:table_for(env)
  check_env(env)
  return self.tables[env]
end

--- Keep the table, stop reading its fields
--- @param env SerialEnv
function Dispatcher:suspend_env(env)
  check_env(env)
  self.suspended[env] = true
end

--- Read the fields again, from now on. No replay of the gap.
--- @param env SerialEnv
function Dispatcher:resume_env(env)
  check_env(env)
  self.suspended[env] = nil
end

--- @param env SerialEnv
function Dispatcher:clear_env(env)
  check_env(env)
  local t = self.tables[env]
  for _, field in pairs(FIELDS) do
    t[field] = nil
  end
end

--- @param event SerialEvent
--- @param arg any?
function Dispatcher:push(event, arg)
  if not FIELDS[event] then
    error('no such event: ' .. tostring(event))
  end
  self.queue[#self.queue + 1] = { event = event, arg = arg }
end

--- A tick comes every update, so a tick handler that fails
--- would fail every update: it is taken off after its first
--- error, and the error says so. One that put another handler
--- in its place before failing leaves that one there.
--- @param t table
--- @param field string
--- @param fn function --- the handler that failed
--- @param e any
--- @return any
local function failed(t, field, fn, e)
  local still = field == FIELDS.tick and t[field] == fn
  if not still then return e end
  t[field] = nil
  return tostring(e) .. ' (onTick is taken off)'
end

--- The handler that would receive field in env right now, or
--- nil when env is suspended or holds no function there
--- @param self Dispatcher
--- @param env SerialEnv
--- @param field string
--- @return function?
local function live(self, env, field)
  if self.suspended[env] then return nil end
  local fn = self.tables[env][field]
  if type(fn) == 'function' then return fn end
  return nil
end

--- Whether any active environment has a live handler for event
--- @param event SerialEvent
--- @return boolean
function Dispatcher:has_handler(event)
  local field = FIELDS[event]
  if not field then
    error('no such event: ' .. tostring(event))
  end
  for _, env in ipairs(ORDER) do
    if live(self, env, field) then return true end
  end
  return false
end

--- Run queued events through the current field values, in
--- order. Anything pushed from a handler waits for the next
--- pump.
--- @return table[] errors
function Dispatcher:pump()
  local batch = self.queue
  self.queue = {}
  local errors = {}
  for _, ev in ipairs(batch) do
    local field = FIELDS[ev.event]
    for _, env in ipairs(ORDER) do
      local fn = live(self, env, field)
      if fn then
        --- a stop the handler asks for ends it, no fault, and
        --- is made once the frame's update returns
        local ok, e = End.call(fn, ev.arg)
        if not ok then
          errors[#errors + 1] = {
            env = env,
            err = failed(self.tables[env], field, fn, e),
          }
        end
      end
    end
  end
  return errors
end
