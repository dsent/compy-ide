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
--- @field push function
--- @field pump function
Dispatcher = {}
Dispatcher.__index = Dispatcher

local FIELDS = {
  connect = 'onConnect',
  disconnect = 'onDisconnect',
  bytes = 'onBytes',
  line = 'onLine',
  tick = 'onTick',
}

local ENVS = { console = true, program = true }

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
    for env, t in pairs(self.tables) do
      if not self.suspended[env] then
        local fn = t[field]
        if type(fn) == 'function' then
          local ok, e = pcall(fn, ev.arg)
          if not ok then
            errors[#errors + 1] = { env = env, err = e }
          end
        end
      end
    end
  end
  return errors
end
