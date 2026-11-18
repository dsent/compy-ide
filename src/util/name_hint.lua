--- The near name (Beads compy-ide-console-suggests-the-near-name,
--- the maintainer's ruling of November 17, 2026, built while the
--- team has yet to decide whether to keep it): when code the
--- user ran fails because it called a global name that does not
--- exist, and exactly one name the code could have called there
--- differs from it in case and underscores alone, the error gains
--- a line naming it, as `listProjects()` typed where the name is
--- `list_projects`. Only after a failure; nothing that runs
--- changes. Called from CanvasModel:write_error, and before the
--- flush of a program's first lines that raised
--- (ConsoleController:run_project).
---
--- It never raises and never runs the user's code: it is
--- protected, it reads tables and metatables raw, and a value
--- counts as callable only when it is a function or its raw
--- metatable's raw __call is one. Where the environment falls
--- back to a function, or further than DEPTH tables, which names
--- exist cannot be known, and there is no hint.
---
--- Lua's "attempt to call field 'x'" names the field and not
--- its table, which only the source says: a field gets no hint.
local NameHint = { }

--- Lua 5.1's error for a call of a global that is nil
local GLOBAL = "attempt to call global '([%a_][%w_]*)' %(a nil value%)"

--- How deep the environment's __index chain is followed
local DEPTH = 4

local getmeta = debug.getmetatable

--- @param name string
--- @return string
local function folded(name)
  return (name:lower():gsub('_', ''))
end

--- @param v any
--- @return boolean
local function callable(v)
  if type(v) == 'function' then return true end
  local mt = getmeta(v)
  return type(mt) == 'table'
      and type(rawget(mt, '__call')) == 'function'
end

--- The one name in `env`, or in the tables it falls back to,
--- that `name` matches once case and underscores are ignored,
--- and that can be called; nil when there is none, more than
--- one, or the names cannot all be known. A name an earlier
--- table holds hides the same name further on.
--- @param name string
--- @param env table
--- @return string?
local function near(name, env)
  local want, seen, found = folded(name), { }, nil
  local t = env
  for _ = 1, DEPTH do
    for k, v in next, t do
      if type(k) == 'string' and not seen[k] then
        seen[k] = true
        if k ~= name and folded(k) == want and callable(v) then
          if found then return nil end
          found = k
        end
      end
    end
    local mt = getmeta(t)
    local index = type(mt) == 'table' and rawget(mt, '__index') or nil
    if index == nil then return found end
    --- a function, or anything but a table, answers names no
    --- walk can list
    if type(index) ~= 'table' then return nil end
    t = index
  end
  --- the chain goes on past DEPTH
  return nil
end

--- @param msg any
--- @param env any
--- @return string?
local function hint(msg, env)
  if type(msg) ~= 'string' or type(env) ~= 'table' then
    return nil
  end
  local name = msg:match(GLOBAL)
  if not name then return nil end
  local other = near(name, env)
  if not other then return nil end
  return string.format('There is no %s. Did you mean %s?', name,
    other)
end

--- The line the error `msg` gains, or nil; it never raises.
--- @param msg any --- the error, as Lua gives it or as shown
--- @param env table? --- the environment the failing code ran in
--- @return string?
function NameHint.of(msg, env)
  local ok, line = pcall(hint, msg, env)
  if ok then return line end
  return nil
end

return NameHint
