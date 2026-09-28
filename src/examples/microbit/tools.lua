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
-- Typing to the board is the "terminal" project. These are
-- the commands around it: feeding it a file or running one,
-- and working with the firmware it is flashed with.

local serial = compy.serial
local hex = require("hex")

local HEX = "MICROBIT.hex"
local LUA = "MICROBIT.lua"
-- How much of the script hexmap shows, as hextract's
-- structure does: enough to tell which script it is, and
-- that the metadata points at one at all
local PEEK = 256

-- A chunk of its own, so what the code declares stays in it
local WRAP = "assert(loadstring[["
local UNWRAP = "]])()"

--- A project file, or a stop saying there is none
--- @param filename string
--- @return string
local function read(filename)
  return assert(readfile(filename), "no " .. filename)
end

-- send, exec --------------------------------------------------

--- A project file, ready for the REPL: CR line endings and a
--- CR at the end, so the last line is entered too
--- @param filename string
--- @return string
local function fileForBoard(filename)
  local text = read(filename)
  local cr = text:gsub("\r\n", "\n"):gsub("\n", "\r")
  if cr:sub(-1) ~= "\r" then
    cr = cr .. "\r"
  end
  return cr
end

--- Send a project file to the board, line by line, as if
--- typed
--- @param filename string
function send(filename)
  assert(serial.send(fileForBoard(filename)))
end

-- The board takes a line, then answers it with a prompt: "> "
-- when it is ready for a new statement, ">> " while a chunk is
-- still open. It drops what arrives faster than it reads, so
-- exec sends a line and waits for the prompt before the next.

--- How long the board may say nothing before exec stops
--- waiting on it
local QUIET_S = 5
--- How often exec says how far it has got
local PROGRESS_S = 3

--- The handlers exec sets while it sends, and puts back after
local HANDLERS = {
  "onBytes",
  "onTick",
  "onDisconnect"
}

--- The file exec is sending, while it sends
local sending = nil

--- The lines exec sends: the file in a chunk of its own
--- @param filename string
--- @return string[]
local function chunkLines(filename)
  local lines = { WRAP }
  for line in fileForBoard(filename):gmatch("([^\r]*)\r") do
    lines[#lines + 1] = line
  end
  lines[#lines + 1] = UNWRAP
  return lines
end

--- What the board said to the line in flight, once its prompt
--- has come after the line's echo, and whether that prompt
--- says the chunk is still open
--- @param heard string
--- @return string? said
--- @return boolean? open
local function reply(heard)
  local _, echoed = heard:find("\r\n", 1, true)
  if not echoed then
    return
  end
  local rest = heard:sub(echoed + 1)
  local open = rest:match("^(.*)>> $")
  local said = open or rest:match("^(.*)> $")
  local whole = said == "" or (said and said:find("[\r\n]$"))
  if whole then
    return said, open ~= nil
  end
end

--- Text the console can show: what is not UTF-8 goes
--- @param text string
--- @return string
local function asText(text)
  local ok, bad = utf8.len(text)
  while not ok do
    text = text:sub(1, bad - 1) .. text:sub(bad + 1)
    ok, bad = utf8.len(text)
  end
  return text
end

--- The board's answer, a line at a time
--- @param said string
local function show(said)
  local text = asText(said):gsub("\r\n?", "\n")
  for line in text:gmatch("[^\n]+") do
    print(line)
  end
end

--- Where exec is in the file, counted in the file's lines
--- @return string
local function where()
  local total = #(sending.lines) - 2
  local line = math.min(math.max(sending.at - 1, 1), total)
  return "line " .. line .. " of " .. total .. " of " .. sending
      .name
end

--- Put back what exec set aside, and say what happened. Echo
--- comes back on: what the board says from here on is shown.
--- @param outcome string
local function finish(outcome)
  for _, field in ipairs(HANDLERS) do
    serial[field] = sending.kept[field]
  end
  sending = nil
  echo()
  print(outcome)
end

--- @param why string
local function stopAt(why)
  finish("exec stopped at " .. where() .. ": " .. why)
end

--- The next line on its way, or the end of the file
local function sendNext()
  sending.at = sending.at + 1
  sending.heard = ""
  sending.quiet = 0
  local line = sending.lines[sending.at]
  if not line then
    finish(sending.name .. " is on the board and has run")
  elseif not serial.send(line .. "\r") then
    stopAt("the board is not connected")
  end
end

--- The board's bytes while exec sends: its prompt lets the
--- next line go. A prompt for a new statement before the
--- last line means the board ran the file before its end,
--- and the rest would reach it as statements of their own.
--- @param chunk string
local function hear(chunk)
  sending.heard = sending.heard .. chunk
  sending.quiet = 0
  local said, open = reply(sending.heard)
  local early = said and not open
       and sending.at < #(sending.lines)
  if early then
    show(said)
    stopAt("the board ran the file before its end")
  elseif said then
    show(said)
    sendNext()
  end
end

--- Say how far exec has got, every PROGRESS_S
--- @param dt number
local function tell(dt)
  sending.told = sending.told + dt
  if PROGRESS_S <= sending.told then
    sending.told = 0
    print("exec: " .. where())
  end
end

--- The whole file is in and the board is still running it,
--- as a program that loops does: what it has said so far is
--- shown, and echo shows the rest as it comes
local function handOver()
  local _, echoed = sending.heard:find("\r\n", 1, true)
  show(echoed and sending.heard:sub(echoed + 1) or "")
  finish(sending.name .. " is running on the board")
end

--- Time passing while exec waits on the board
--- @param dt number
local function waiting(dt)
  tell(dt)
  sending.quiet = sending.quiet + dt
  local last = sending.at == #(sending.lines)
  if sending.quiet <= QUIET_S then
    return
  elseif last then
    handOver()
  else
    stopAt("the board stopped answering. Press its reset" ..
        " button, then try again.")
  end
end

local function unplugged()
  stopAt("the board was unplugged")
end

--- The handlers exec is about to replace
--- @return table
local function setAside()
  local kept = { }
  for _, field in ipairs(HANDLERS) do
    kept[field] = serial[field]
  end
  return kept
end

--- What exec keeps while it sends a file
--- @param filename string
--- @return table
local function newSending(filename)
  return {
    name = filename,
    lines = chunkLines(filename),
    at = 0,
    kept = setAside(),
    quiet = 0,
    told = 0
  }
end

--- Run a project file on the board as one chunk, wrapped in
--- assert(loadstring [[ ... ]])(), sent a line at a time. The
--- board's echo of the file is not shown; what it answers is.
--- @param filename string
function exec(filename)
  assert(serial.isConnected(), "no micro:bit connected")
  local busy = sending and serial.onBytes == hear
  assert(not busy, "exec is still sending a file")
  sending = newSending(filename)
  echo(false)
  serial.onBytes, serial.onTick = hear, waiting
  serial.onDisconnect = unplugged
  sendNext()
end

-- firmware ---------------------------------------------------

--- The blocks of a hex file in the project
--- @param filename string
--- @return table[]
local function blocksOf(filename)
  return hex.parse(read(filename))
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
    print(string.format(
      "%08X - %08X  %d bytes",
      b.addr,
      b.addr + #(b.data) - 1,
      #(b.data)
    ))
  end
end

--- What a hex file is made of: where its data sits, where
--- the firmware keeps its Lua script, and how that script
--- begins.
--- @param filename string?
local function printMeta(meta)
  print(string.format(
    "script %08X - %08X  %d of %d",
    meta.start,
    meta.stop,
    meta.size,
    meta.space
  ))
end

function hexmap(filename)
  local blocks = blocksOf(filename or HEX)
  regions(blocks)
  local addr, meta = hex.meta(blocks)
  if not addr then
    print("no Lua script inside")
    return
  end
  printMeta(meta)
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
  local blocks = blocksOf(HEX)
  hex.embed(blocks, read(lua_name or LUA))
  writefile(hex_name, hex.write(blocks))
  print("wrote " .. hex_name)
end

--- What a file has to say: its lines, less the blank ones
--- and the comments. A directive is a comment too, and is
--- left in for the caller to recognise.
--- @param filename string
--- @return string[]
local function linesOf(filename)
  local kept = { }
  for line in read(filename):gmatch("[^\r\n]*") do
    local code = line:find("%S") and not line:find("^%s*%-%-")
    local keep = code or line:find("^%s*%-%->>?%s+%S+%s*$")
    if keep then
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
  if plain then
    return plain, false
  end
  local wrapped = line:match("^%s*%-%->%s+(%S+)%s*$")
  if wrapped then
    return wrapped, true
  end
end

--- An included file, as it stands. Its own directives are
--- comments here: a reference is not followed further.
--- @param out string[]
--- @param filename string
local function bring(out, filename)
  for _, line in ipairs(linesOf(filename)) do
    if not included(line) then
      out[#out + 1] = line
    end
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
    out[#out + 1] = WRAP
    bring(out, name)
    out[#out + 1] = UNWRAP
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
  local out = { }
  for _, line in ipairs(linesOf(lua_name)) do
    expand(out, line)
  end
  writefile(LUA, table.concat(out, "\n") .. "\n")
  embed(hex_name or (lua_name:gsub("%.lua$", "") .. ".hex"))
end

--- Put a hex file on the board. The board is looked for each
--- time, since it usually goes in after Compy has started.
--- Copying takes a few seconds and the screen does not move
--- until it is done, so a sound says the copying has begun.
--- The board then writes the file into its memory by itself
--- and restarts; the Compy cannot see whether it took it.
--- @param filename string?
function upload(filename)
  local name = filename or HEX
  local data = read(name)
  assert(detect_microbit(), "no micro:bit plugged in")
  compy.audio.hyperjump()
  local ok, err = flash_microbit(data)
  assert(ok, err)
  print(name .. " is sent. The micro:bit's light blinks")
  print("while it writes it, then it restarts with it.")
end

-- help --------------------------------------------------------

local COMMANDS = {
  "help()                  this list",
  "echo(on)                board output in the console;",
  "                        echo(false) stops it, echo()",
  "                        resumes",
  "send(filename)          file to the board, as typed",
  "exec(filename)          file to the board a line at a",
  "                        time, run as one chunk",
  "hexmap(hex)             what a hex file holds",
  "extract(hex, lua)       its script out to a file",
  "embed(hex, lua)         a script into a new hex",
  "compile(lua, hex)       files into one, then into a hex",
  "upload(hex)             a hex file onto the board"
}

function help()
  print("micro:bit tools")
  for _, line in ipairs(COMMANDS) do
    print("  " .. line)
  end
  print("")
  print("upload() with no file sends MICROBIT.hex, the")
  print("firmware for the TPBot robots.")
  print("Write the files with edit(filename), type to the")
  print("board in the \"terminal\" project.")
end

echo()
help()
