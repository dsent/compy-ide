--- Backend with no hardware behind it. Tests drive it with
--- attach/detach/rx; sent data lands in .sent

--- @class FakeBackend
--- @field new function
--- @field start function
--- @field poll function
--- @field send function
--- @field drop function
--- @field reset function
--- @field stop function
FakeBackend = {}
FakeBackend.__index = FakeBackend

--- @return FakeBackend
function FakeBackend.new()
  local self = setmetatable({}, FakeBackend)
  self.sink = nil
  self.sent = {}
  self.drops = 0
  self.resets = 0
  self.started = false
  return self
end

function FakeBackend:start(sink)
  self.sink = sink
  self.started = true
end

--- @return string? fault
function FakeBackend:poll()
  local f = self.fault
  self.fault = nil
  return f
end

--- @param data string
--- @return boolean? ok
--- @return string? err
function FakeBackend:send(data)
  if not self.started then
    return nil, 'backend not started'
  end
  self.sent[#self.sent + 1] = data
  return true
end

--- send hands data to .sent at once, so nothing waits here;
--- the drop is counted
function FakeBackend:drop()
  self.drops = self.drops + 1
end

--- Counted; a test sets .refuse to have it refused
--- @return boolean? ok
--- @return string? err
function FakeBackend:reset()
  if not self.started then
    return nil, 'backend not started'
  end
  if self.refuse then
    return nil, self.refuse
  end
  self.resets = self.resets + 1
  return true
end

function FakeBackend:stop()
  self.started = false
  self.sink = nil
end

--- @param info table?
function FakeBackend:attach(info)
  self.sink.attach(info or { name = 'fake micro:bit' })
end

function FakeBackend:detach()
  self.sink.detach()
end

--- @param bytes string
function FakeBackend:rx(bytes)
  self.sink.bytes(bytes)
end

--- The link to the board's chip: a test sets .link, or
--- .dapRefuse to have it refused
--- @return table? link
--- @return string? err
function FakeBackend:dap()
  if self.dapRefuse then return nil, self.dapRefuse end
  if not self.link then return nil, 'no link' end
  return self.link
end

--- What a test put in .why
--- @return string?
function FakeBackend:absence()
  return self.why
end

--- What a test put in .id
--- @return string?
function FakeBackend:boardId()
  return self.id
end

--- What a test put in .info
--- @return table?
function FakeBackend:board()
  return self.info
end

--- Report a fault on the next poll
--- @param text string
function FakeBackend:breaks(text)
  self.fault = text
end
