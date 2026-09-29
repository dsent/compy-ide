--- The backend for platforms without USB serial access: the
--- desktop build, and any future one until it gets its own.
--- Keeps compy.serial present everywhere: never connects,
--- sending fails with a readable error, polling never
--- faults.

--- @class NullBackend
NullBackend = {}
NullBackend.__index = NullBackend

--- @return NullBackend
function NullBackend.new()
  return setmetatable({}, NullBackend)
end

function NullBackend:start()
end

--- @return nil
function NullBackend:poll()
  return nil
end

--- @return nil
--- @return string
function NullBackend:send()
  return nil, 'no serial on this platform'
end

function NullBackend:drop()
end

function NullBackend:reset()
  return nil, 'no serial on this platform'
end

function NullBackend:dap()
  return nil, 'no serial on this platform'
end

function NullBackend:board()
  return nil
end

function NullBackend:boardId()
  return nil
end

function NullBackend:stop()
end
