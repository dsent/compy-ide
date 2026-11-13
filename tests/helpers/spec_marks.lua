-- Tests that check the editor against its spec. Each name
-- opens with the spec item's id and name, as the item reads:
-- "IS5.7 Cancel an edit with Escape: ...", so a script can
-- count the tests per item (util/spec_count.lua).
--
-- spec_it        the editor complies; an ordinary test
-- spec_gap       the editor does not comply yet. `fn` gets
--                `gap` and calls it once with the spec's
--                check: the check must fail by an assertion,
--                and the test fails once it passes, so a fixed
--                gap cannot go unseen. Everything else in `fn`
--                is an ordinary test step
-- spec_deviation the editor departs from the spec on purpose,
--                under a recorded ruling; asserts what is
--                built, counted apart from the gaps
--
-- A mark is called from the spec file itself, as a statement:
-- it finds busted's `it` in its caller's environment.

local M = { }

-- An item id: letters (a hyphen allowed), then n or n.n:
-- CUJ1, IS5.7, H-NFR4.4.
local ID = "^(%u[%u%-]*%d+%.?%d*) "

-- names defined in this spec file: busted loads this module
-- afresh for each file
local seen = { }

-- the spec file's frame, seen from a helper a mark calls:
-- the helper, the mark, the spec file
local FILE = 3

-- one frame deeper: called from such a helper, or `depth`
-- frames deeper still
local function fail_at(msg, depth)
  error(msg, FILE + 1 + (depth or 0))
end

local function where()
  local info = debug.getinfo(FILE, "Sl")
  return info.short_src .. ":" .. info.currentline
end

local function id_of(name)
  local id = type(name) == "string" and name:match(ID)
  if not id then
    fail_at(
      "a spec test's name opens with its item id: " .. tostring(
        name
      ),
      1
    )
  end
  return id
end

local function check(name, fn)
  local id = id_of(name)
  if type(fn) ~= "function" then
    fail_at("a spec test has a body: " .. name)
  end
  if seen[name] then
    fail_at("a second test named " .. name)
  end
  seen[name] = true
  return id
end

local function busted_it()
  local it = getfenv(FILE).it
  if not it then
    fail_at("call a mark from the spec file, as a statement")
  end
  return it
end

-- busted raises a failed assertion as a table typed
-- 'failure'; anything else is an error in the test itself.
local function is_failure(e)
  local mt = type(e) == "table" and getmetatable(e)
  return mt and mt.__type == "failure"
end

-- SPEC_GAP_WHY=1 prints why each gap's check failed, to
-- audit that it fails for its item's reason
local function tell_why(ctx, e)
  if not os.getenv("SPEC_GAP_WHY") then
    return
  end
  local why = tostring(e.message or e):gsub("\n", "\n  ")
  print("GAP " .. ctx.name .. "\n  " .. why)
end

local function expect_failure(ctx, spec_check)
  ctx.calls = ctx.calls + 1
  local ok, e = pcall(spec_check)
  local complies = ctx.at .. ": " .. ctx.id ..
      " now complies: remove the mark"
  if ok then
    error(complies, 0)
  end
  if not is_failure(e) then
    error(e, 0)
  end
  tell_why(ctx, e)
end

local function gap_body(ctx, fn)
  return function()
    ctx.calls = 0
    fn(function(c)
      expect_failure(ctx, c)
    end)
    if ctx.calls ~= 1 then
      error(ctx.at .. ": " .. ctx.id ..
          " calls gap(check) once, not " .. ctx.calls, 0)
    end
  end
end

--- @param name string  "<id> <item name>: <case>"
--- @param fn function
function M.spec_it(name, fn)
  check(name, fn)
  busted_it()(name, fn)
end

--- @param name string  "<id> <item name>: <case>"
--- @param fn fun(gap: fun(check: function))
function M.spec_gap(name, fn)
  local ctx = {
    id = check(name, fn),
    at = where(),
    name = name
  }
  busted_it()(name .. " #spec_gap", gap_body(ctx, fn))
end

--- @param name string  "<id> <item name>: <case>"
--- @param ruling string  where the deviation was ruled
--- @param fn function  asserts what is built
function M.spec_deviation(name, ruling, fn)
  check(name, fn)
  local ruled = type(ruling) == "string" and ruling ~= ""
  if not ruled then
    error("a deviation names its ruling: " .. name, 2)
  end
  busted_it()(name .. " #spec_deviation", fn)
end

return M
