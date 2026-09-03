if _VERSION ~= "Lua 5.1" then
  io.stderr:write(
    "Compy IDE tests require Lua 5.1 or LuaJIT, found ",
    _VERSION,
    ".\n"
  )
  os.exit(1)
end

require("busted.runner")({ standalone = false })
