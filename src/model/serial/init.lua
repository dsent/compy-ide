require('model.serial.line_reader')
require('model.serial.dispatcher')
require('model.serial.echo')

--- Backend contract:
---   backend:start(sink)  sink.attach(info), sink.detach(),
---                        sink.bytes(chunk)
---   backend:poll() -> nil | fault, one step per update
---   backend:send(data) -> true | nil, err
---   backend:drop()       what send queued and has not
---                        written yet goes
---   backend:reset() -> true | nil, err  the board restarts
---   backend:stop()

--- @class Serial
--- @field new function
--- @field fault function
--- @field table_for function
--- @field send function
--- @field drop function
--- @field reset function
--- @field isConnected function
--- @field programStarted function
--- @field programIdle function
--- @field programPaused function
--- @field programContinued function
--- @field programEnded function
--- @field echo Echo
--- @field update function
--- @field stop function
Serial = {}
Serial.__index = Serial

--- @param backend table
--- @param max_line integer?
--- @return Serial
function Serial.new(backend, max_line)
  local self = setmetatable({}, Serial)
  self.backend = backend
  self.reader = LineReader.new(max_line)
  self.dispatcher = Dispatcher.new()
  self.faults = {}
  self.connected = false
  self.echo = Echo.new(io.write, print)
  for _, env in ipairs({ 'console', 'program' }) do
    local t = self.dispatcher:table_for(env)
    t.send = function(line)
      return self:send(line)
    end
    t.reset = function()
      return self:reset()
    end
    t.isConnected = function()
      return self:isConnected()
    end
  end
  backend:start(self:sink())
  return self
end

--- @return table
function Serial:sink()
  return {
    attach = function(info)
      self.connected = true
      self.reader:reset()
      self.dispatcher:push('connect', info)
    end,
    detach = function()
      self.connected = false
      self.reader:reset()
      self.dispatcher:push('disconnect')
    end,
    bytes = function(chunk)
      self:receive(chunk)
    end,
  }
end

--- Record something that failed outside a handler
--- @param err string?
function Serial:fault(err)
  if not err then return end
  self.faults[#self.faults + 1] = { env = 'serial', err = err }
end

--- Raw chunk first, then the lines it completed
--- @param chunk string
function Serial:receive(chunk)
  self.dispatcher:push('bytes', chunk)
  local lines, err = self.reader:feed(chunk)
  for _, l in ipairs(lines) do
    self.dispatcher:push('line', l)
  end
  self:fault(err)
end

--- The environment's compy.serial table. Handlers are its
--- fields, assigned by the code running there: onConnect,
--- onDisconnect, onBytes, onLine, and onTick, called every
--- update with the seconds since the last, after that
--- update's bytes, so a wait on the board can end when it
--- stops answering. send, reset and isConnected live in
--- the same table. Delivery reads the current field value;
--- a field left nil means nothing is delivered.
--- @param env SerialEnv
--- @return table
function Serial:table_for(env)
  return self.dispatcher:table_for(env)
end

--- Sent as given: the terminator, if the other end wants
--- one, belongs to the caller
--- @param line string
--- @return boolean? ok
--- @return string? err
function Serial:send(line)
  if not self.connected then
    return nil, 'no device connected'
  end
  return self.backend:send(line)
end

--- What was sent and has not left yet goes: the program that
--- sent it has ended, or the board is about to take new
--- firmware. Either way it would reach the board where it no
--- longer makes sense, as lines typed into a fresh REPL.
function Serial:drop()
  self.backend:drop()
end

--- The board restarts, as its reset button makes it: the way
--- back from a board that no longer reads what it is sent.
--- What waits to be sent goes first, and so does the line it
--- was in the middle of, or both would run into its greeting.
--- @return boolean? ok
--- @return string? err
function Serial:reset()
  self:drop()
  self.reader:reset()
  return self.backend:reset()
end

--- @return boolean
function Serial:isConnected()
  return self.connected
end

--- A running program speaks for the board, so the console
--- stops listening while it does — otherwise both print what
--- arrives and every answer is shown twice.
function Serial:programStarted()
  self.dispatcher:suspend_env('console')
  self.echo:off()
end

--- The program's top-level code has finished without taking
--- the frame: nothing speaks for the board any more, so the
--- console listens again. Handlers the program set stay —
--- it has not stopped, it is only idle.
function Serial:programIdle()
  self.dispatcher:resume_env('console')
end

--- Stopped, but continue() may follow
function Serial:programPaused()
  self.dispatcher:suspend_env('program')
end

function Serial:programContinued()
  self.dispatcher:resume_env('program')
end

--- Stopped for good
function Serial:programEnded()
  self.dispatcher:resume_env('program')
  self.dispatcher:clear_env('program')
  self.dispatcher:resume_env('console')
end

--- Call once per update loop
--- @return table[] errors
--- @param dt number
function Serial:update(dt)
  self:fault(self.backend:poll())
  self.echo:tick(dt)
  self.dispatcher:push('tick', dt)
  local errors = self.dispatcher:pump()
  for _, f in ipairs(self.faults) do
    errors[#errors + 1] = f
  end
  self.faults = {}
  return errors
end

function Serial:stop()
  self.backend:stop()
  self.connected = false
end
