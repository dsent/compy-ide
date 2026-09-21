-- micro:bit tools. Load them into the console with
-- require("tools"); every function below becomes a command.
--
-- The board is a micro:bit with the Lua REPL firmware, on
-- USB. Everything it prints arrives through compy.serial and
-- is shown by echo(), which the console has of its own;
-- everything sent to it leaves the same way. The REPL is a
-- terminal: it ends its lines with CR, and it echoes every
-- character it receives.
--
-- Typing to the board is the "terminal" project; these are
-- the commands around it — feed it a file, run one.

local serial = compy.serial
local hex = require("hex")

local HEX = "MICROBIT.hex"
local LUA = "MICROBIT.lua"
-- How much of the script hexmap shows, as hextract's
-- structure does: enough to tell which script it is, and
-- that the metadata points at one at all
local PEEK = 256

local EXEC_PREFIX = "assert(loadstring [[\r"
local EXEC_SUFFIX = "]])()\r"
local EXEC_MARKER = "]])()"

-- send, exec --------------------------------------------------

--- A project file, ready for the REPL: CR line endings and a
--- CR at the end, so the last line is entered too
--- @param filename string
--- @return string
local function fileForBoard(filename)
  local text = assert(readfile(filename), "no " .. filename)
  local cr = text:gsub("\r\n", "\n"):gsub("\n", "\r")
  if cr:sub(-1) ~= "\r" then cr = cr .. "\r" end
  return cr
end

--- Send a project file to the board, line by line, as if
--- typed
--- @param filename string
function send(filename)
  assert(serial.send(fileForBoard(filename)))
end

--- Whether echo was showing when exec started
local showing = false

--- Stay silent until the board has echoed the marker, then
--- hand what followed, and all that comes after, back to echo
--- @param marker string
--- @return function
local function silentUntil(marker)
  local heard = ""
  return function(chunk)
    heard = heard .. chunk
    local _, at = heard:find(marker, 1, true)
    if not at then return end
    if not showing then return echo(false) end
    echo()
    serial.onBytes(heard:sub(at + 1))
  end
end

--- Run a project file on the board as one chunk, wrapped in
--- assert(loadstring [[ ... ]])(). The board echoes every byte
--- it receives; that echo is held back while the file is in
--- flight, the program's own output comes through.
--- @param filename string
function exec(filename)
  local body = fileForBoard(filename)
  local code = EXEC_PREFIX .. body .. EXEC_SUFFIX
  showing = serial.onBytes ~= nil
  serial.onBytes = silentUntil(EXEC_MARKER)
  assert(serial.send(code))
end

-- firmware ---------------------------------------------------

--- The blocks of a hex file in the project
--- @param filename string
--- @return table[]
local function blocksOf(filename)
  return hex.parse(assert(readfile(filename),
    "no " .. filename))
end

--- The start of a script, up to PEEK bytes, in whole lines
--- @param script string
--- @return string
local function head(script)
  local cut = script:sub(1, PEEK)
  local whole = cut:match("^(.*)\n") or cut
  return (whole:gsub("\n+$", ""))
end

--- Where a hex file's data sits
--- @param blocks table[]
local function regions(blocks)
  for _, b in ipairs(blocks) do
    print(string.format("%08X - %08X  %d bytes",
      b.addr, b.addr + #b.data - 1, #b.data))
  end
end

--- What a hex file is made of: where its data sits, where
--- the firmware keeps its Lua script, and how that script
--- begins.
--- @param filename string?
function hexmap(filename)
  local blocks = blocksOf(filename or HEX)
  regions(blocks)
  local addr, meta = hex.meta(blocks)
  if not addr then
    print("no Lua script inside")
    return
  end
  print(string.format("script %08X - %08X  %d of %d",
    meta.start, meta.stop, meta.size, meta.space))
  print(head(hex.script(blocks)))
end

--- Take the Lua script out of a hex file and keep it
--- @param hex_name string?
--- @param lua_name string?
function extract(hex_name, lua_name)
  local name = lua_name or LUA
  writefile(name, hex.script(blocksOf(hex_name or HEX)))
  print("wrote " .. name)
end

--- Put a Lua script into a hex file. MICROBIT.hex is always
--- the firmware read from, and never the one written to: it
--- is the one copy that has to stay as it came.
--- @param hex_name string
--- @param lua_name string?
function embed(hex_name, lua_name)
  assert(hex_name, "name the hex file to write")
  assert(hex_name ~= HEX, HEX .. " cannot be overwritten")
  local name = lua_name or LUA
  local blocks = blocksOf(HEX)
  hex.embed(blocks, assert(readfile(name), "no " .. name))
  writefile(hex_name, hex.write(blocks))
  print("wrote " .. hex_name)
end

--- What a file has to say: its lines, less the blank ones
--- and the comments. A directive is a comment too, and is
--- left in for the caller to recognise.
--- @param filename string
--- @return string[]
local function linesOf(filename)
  local kept = {}
  local text = assert(readfile(filename), "no " .. filename)
  for line in text:gmatch("[^\r\n]*") do
    local code = line:find("%S") and not line:find("^%s*%-%-")
    if code or line:find("^%s*%-%->>?%s+%S+%s*$") then
      kept[#kept + 1] = line
    end
  end
  return kept
end

--- The file a directive names, or nothing
--- @param line string
--- @return string? name
--- @return boolean? wrapped
local function included(line)
  local plain = line:match("^%s*%-%->>%s+(%S+)%s*$")
  if plain then return plain, false end
  local wrapped = line:match("^%s*%-%->%s+(%S+)%s*$")
  if wrapped then return wrapped, true end
end

--- An included file, as it stands. Its own directives are
--- comments here: a reference is not followed further.
--- @param out string[]
--- @param filename string
local function bring(out, filename)
  for _, line in ipairs(linesOf(filename)) do
    if not included(line) then out[#out + 1] = line end
  end
end

--- One line of the source: itself, or the file it names
--- @param out string[]
--- @param line string
local function expand(out, line)
  local name, wrapped = included(line)
  if not name then
    out[#out + 1] = line
  elseif wrapped then
    out[#out + 1] = "assert(loadstring[["
    bring(out, name)
    out[#out + 1] = "]])()"
  else
    bring(out, name)
  end
end

--- Build one Lua file out of several and put it in the
--- firmware. A line "--> name" brings that file in wrapped
--- in a chunk of its own, so what it declares stays there;
--- "-->> name" brings it in as it stands.
--- @param lua_name string
--- @param hex_name string?
function compile(lua_name, hex_name)
  assert(lua_name, "name the lua file to compile")
  assert(lua_name ~= LUA, LUA .. " is the one it builds")
  local out = {}
  for _, line in ipairs(linesOf(lua_name)) do
    expand(out, line)
  end
  writefile(LUA, table.concat(out, "\n") .. "\n")
  embed(hex_name or (lua_name:gsub("%.lua$", "") .. ".hex"))
end

-- help --------------------------------------------------------

local COMMANDS = {
  "help()                  this list",
  "echo(on)                board output in the console;",
  "                        echo(false) stops it, echo()",
  "                        resumes",
  "send(filename)          file to the board, as typed",
  "exec(filename)          file to the board, run as one",
  "                        chunk",
  "hexmap(hex)             what a hex file holds",
  "extract(hex, lua)       its script out to a file",
  "embed(hex, lua)         a script into a new hex",
  "compile(lua, hex)       files into one, then into a hex",
}

function help()
  print("micro:bit tools")
  for _, line in ipairs(COMMANDS) do print("  " .. line) end
  print("")
  print("Write the files with edit(filename), type to the")
  print("board in the \"terminal\" project.")
end

echo()
help()
