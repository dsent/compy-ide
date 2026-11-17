--- A lifecycle call made from code ends that code at once, and
--- the IDE carries out what it asked for when the code has
--- returned to it (the maintainer's ruling of November 16,
--- 2026, design B: "ends the calling code at once — this makes
--- the most sense").
---
--- stop(), reset(), run(), project() and the other calls that
--- end or replace a run record one request here and raise
--- ENDED, which unwinds the code that made the call. Every
--- place the IDE calls into a program or a typed line counts
--- the call (`call`, or `enter` and `leave` around an xpcall of
--- its own) and takes ENDED as no error. Every place the IDE
--- enters from LÖVE, or from which it starts a run, is `held`:
--- the request is carried out when the outermost of them ends,
--- once, with no program code on the stack. The first request
--- wins: the code after it never ran, and only the program's
--- own pcall or coroutine.resume, which swallow ENDED, can reach
--- a second. A
--- request made while a stop is under way (in compy.before_exit)
--- ends that code and is dropped: the stop goes on.
---
--- A call made with no program code on the stack (the IDE's
--- own, a test's) is carried out at once.

local M = {
  --- program code calls on the stack
  user = 0,
  --- places the IDE is in that carry out a request at their end
  hold = 0,
  --- the request to carry out
  --- @type function?
  pending = nil,
  --- a stop is under way: a request is dropped
  ending = false,
  --- a request is being carried out
  carrying = false,
  --- the IDE's own graphics pushes under way (view.ownState, the
  --- draw wrapper): a stop pops none of them
  ide_pushes = 0,
}

--- The private error that ends the calling code
M.ENDED = setmetatable({ }, {
  __tostring = function() return 'the program ended' end,
})

--- @param err any
--- @return boolean
function M.is(err)
  return rawequal(err, M.ENDED)
end

local function pack(...)
  return { n = select('#', ...), ... }
end

--- Carry out the request, when nothing holds it back: no IDE
--- place still on the stack, no program code, no request under
--- way (that one's loop takes it)
function M.carry_out()
  if M.hold > 0 or M.user > 0 or M.carrying then return end
  M.carrying = true
  while M.pending do
    local work = M.pending
    M.pending = nil
    local ok, err = pcall(work)
    if not ok then
      M.carrying = false
      M.pending = nil
      error(err, 0)
    end
  end
  M.carrying = false
end

--- Program code begins: a lifecycle call in it now ends it
function M.enter()
  M.user = M.user + 1
end

--- Program code returned
function M.leave()
  M.user = M.user - 1
end

--- Call program code `f`: as pcall, where an end is no error
--- (true and nothing else)
--- @param f function
--- @return boolean ok
--- @return any ...
function M.call(f, ...)
  M.enter()
  local r = pack(pcall(f, ...))
  M.leave()
  if not r[1] and M.is(r[2]) then return true end
  return unpack(r, 1, r.n)
end

--- Call program code `f` from inside the IDE's own work, which
--- goes on: as a plain call, where an end is no error and gives
--- nothing back, and any other error goes on up
--- @param f function
--- @return any ...
function M.counted(f, ...)
  M.enter()
  local r = pack(pcall(f, ...))
  M.leave()
  if r[1] then return unpack(r, 2, r.n) end
  if M.is(r[2]) then return end
  error(r[2], 0)
end

--- Run the IDE's `f`, which may call program code, and carry
--- out at its end a request that code made. An error goes on
--- up, the counts put back.
--- @param f function
--- @return any ...
function M.held(f, ...)
  M.hold = M.hold + 1
  local r = pack(pcall(f, ...))
  M.hold = M.hold - 1
  if not r[1] then
    if M.hold == 0 and M.user == 0 then M.pending = nil end
    error(r[2], 0)
  end
  M.carry_out()
  return unpack(r, 2, r.n)
end

--- A lifecycle call: `work` does what it asks. From program
--- code it is recorded (unless one is already, or a stop is
--- under way) and the code ends; from the IDE's own code it is
--- done at once.
--- @param work function
--- @return any ... what work returns, when done at once
function M.request(work)
  if M.user == 0 then return work() end
  if not M.pending and not M.ending then M.pending = work end
  error(M.ENDED, 0)
end

--- The IDE's own request, made where program code may be on the
--- stack: recorded as a lifecycle call's is, and carried out
--- once the place that holds it ends, with nothing raised, so
--- the IDE's code there goes on (a program's natural end, found
--- as an event comes)
--- @param work function
function M.defer(work)
  if M.user == 0 and M.hold == 0 then return work() end
  if not M.pending and not M.ending then M.pending = work end
end

--- Everything back as at the start, for a test's fixture
function M.reset()
  M.user, M.hold = 0, 0
  M.pending, M.ending, M.carrying = nil, false, false
  M.ide_pushes = 0
end

return M
