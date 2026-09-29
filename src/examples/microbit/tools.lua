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

--- Whether this Compy sends files down the cable: an older
--- one lacks isFlashing, and copies them to the drive
--- @return boolean
local function cableFlash()
  return serial.isFlashing ~= nil
end

--- Whether a file is on its way to the board now
--- @return boolean
local function onItsWay()
  return cableFlash() and serial.isFlashing()
end

--- Whether a file is on its way to the board, said when it
--- is: the board is halted, and sending to it or restarting
--- it would break the file off
--- @return boolean
local function flashing()
  if onItsWay() then
    print("A file is on its way to the micro:bit. Wait until")
    print("the Compy says how it went.")
    return true
  end
  return false
end

--- Send a project file to the board, line by line, as if
--- typed
--- @param filename string
function send(filename)
  if flashing() then
    return
  end
  assert(serial.send(fileForBoard(filename)))
end

-- The board takes a line, then answers it with a prompt: "> "
-- when it is ready for a new statement, ">> " while a chunk is
-- still open. It drops what arrives faster than it reads, so
-- exec sends a line and waits for the prompt before the next.

--- How long the board may say nothing before exec stops
--- waiting on it
local QUIET_S = 5
--- How long the board must be quiet after the last line's
--- prompt before it counts: what the program prints may end
--- in "> " too
local SETTLE_S = 0.2
--- How often exec says how far it has got
local PROGRESS_S = 3
local STOPPED = "the board stopped answering. Type" ..
    " restart_microbit(), then try again."

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

--- What the board has said since it echoed the line in flight
--- and started a new line on taking it. What came before the
--- echo, such as the greeting of a board just reset, is not
--- the line's.
--- @return string?
local function afterEcho()
  local line = sending.lines[sending.at]
  local _, at = sending.heard:find(line .. "\r\r\n", 1, true)
  if at then
    return sending.heard:sub(at + 1)
  end
end

--- The board's answer once its prompt has come, and whether
--- that prompt says the chunk is still open
--- @param after string
--- @return string? said
--- @return boolean? open
local function reply(after)
  local open = after:match("^(.*)>> $")
  local said = open or after:match("^(.*)> $")
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

--- The board's answer, a line at a time, blank lines left out
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

--- Put back what exec set aside, where its own handlers still
--- are: something that took one over keeps it
local function putBack()
  for field, mine in pairs(sending.mine) do
    if serial[field] == mine then
      serial[field] = sending.kept[field]
    end
  end
  if compy.before_exit == sending.stop then
    compy.before_exit = sending.exit
  end
end

--- Say what happened, and hand the board back. Echo comes back
--- on: what the board says from here on is shown.
--- @param outcome string
local function finish(outcome)
  putBack()
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
    finish(sending.name .. " is on the board")
  elseif not serial.send(line .. "\r") then
    stopAt("the board is not connected")
  end
end

--- A line's prompt lets the next line go. A prompt for a new
--- statement before the last line means the board ran the file
--- before its end, and the rest would reach it as statements
--- of their own.
--- @param said string
--- @param open boolean
local function answered(said, open)
  show(said)
  if open then
    sendNext()
  else
    stopAt("the board ran the file before its end")
  end
end

--- The board's bytes while exec sends. The last line's prompt
--- is left to waiting, which lets the board settle first.
--- @param chunk string
local function hear(chunk)
  sending.heard = sending.heard .. chunk
  sending.quiet = 0
  if sending.at == #(sending.lines) then
    return
  end
  local said, open = reply(afterEcho() or "")
  if said then
    answered(said, open)
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

--- No prompt QUIET_S after the last line: once the board has
--- taken it, the file is still running, as a program that
--- loops is, and echo shows the rest as it comes
--- @param after string?
local function quietLast(after)
  if after then
    show(after)
    finish(sending.name .. " is on the board and still running")
  else
    stopAt(STOPPED)
  end
end

--- The last line runs the file: a prompt the board has been
--- quiet after means the file has run, as far as the board's
--- bytes can tell; a program that writes "> " and pauses looks
--- the same
local function lastLine()
  local after = afterEcho()
  local said = after and after:match("^(.*)> $")
  local done = said and SETTLE_S <= sending.quiet
  if done then
    show(said)
    finish(sending.name .. " is on the board")
  elseif QUIET_S < sending.quiet then
    quietLast(after)
  end
end

--- Time passing while exec waits on the board
--- @param dt number
local function waiting(dt)
  tell(dt)
  sending.quiet = sending.quiet + dt
  if sending.at == #(sending.lines) then
    lastLine()
  elseif QUIET_S < sending.quiet then
    stopAt(STOPPED)
  end
end

local function unplugged()
  stopAt("the board was unplugged")
end

--- stop(), or the project closing, while exec sends
local function stopped()
  local exit = sending.exit
  stopAt("it was stopped")
  if exit then
    exit()
  end
end

--- The handlers exec sets while it sends
--- @return table
local function handlers()
  return {
    onBytes = hear,
    onTick = waiting,
    onDisconnect = unplugged
  }
end

--- The handlers found where exec is about to set its own
--- @param mine table
--- @return table
local function setAside(mine)
  local kept = { }
  for field in pairs(mine) do
    kept[field] = serial[field]
  end
  return kept
end

--- What exec keeps while it sends a file
--- @param filename string
--- @return table
local function newSending(filename)
  local mine = handlers()
  return {
    name = filename,
    lines = chunkLines(filename),
    mine = mine,
    kept = setAside(mine),
    stop = stopped,
    exit = compy.before_exit,
    at = 0,
    quiet = 0,
    told = 0
  }
end

--- Whether an exec is still sending: a stop or a project run
--- that cleared its handlers has ended it without a word
--- @return boolean
local function isSending()
  return sending ~= nil and serial.onTick == waiting
end

--- Whether the board can take a file now; a stop, in words,
--- when it is not there or exec is still sending one, and
--- false, said, while it takes new firmware
--- @return boolean
local function readyToSend()
  assert(serial.isConnected(), "no micro:bit connected")
  if flashing() then
    return false
  end
  assert(not isSending(), "exec is still sending a file")
  return true
end

--- exec's handlers take the board over while it sends
local function takeOver()
  for field, handler in pairs(sending.mine) do
    serial[field] = handler
  end
  compy.before_exit = stopped
end

--- Run a project file on the board as one chunk, wrapped in
--- assert(loadstring [[ ... ]])(), sent a line at a time. The
--- board's echo of the file is not shown; what it answers is.
--- @param filename string
function exec(filename)
  if not readyToSend() then
    return
  end
  if sending then
    putBack()
  end
  sending = newSending(filename)
  echo(false)
  takeOver()
  sendNext()
end

-- restart ----------------------------------------------------

--- What to do when the board did not take the restart
local NO_RESTART = "the micro:bit did not restart. Press its"
    .. " reset button, on the back next to the USB socket."

--- What to do when no greeting comes after a restart
local function greetingNote()
  print("The micro:bit restarts, and greets you when it")
  print("is ready. If it does not within a minute, press")
  print("its reset button, on the back next to the USB")
  print("socket.")
end

--- Restart the board, as its reset button does, without
--- touching it: the way back from a board that no longer
--- reads what it is sent, stuck in a loop or in listen(). An
--- exec still sending stops first, and echo comes back on,
--- so the greeting shows. While a file goes to the board, the
--- restart waits. The message says what to do when no
--- greeting comes.
function restart_microbit()
  assert(serial.isConnected(), "no micro:bit connected")
  if flashing() then
    return
  end
  local restarted = serial.reset()
  if isSending() then
    stopAt(restarted and "the board was restarted"
         or "the board did not restart")
  end
  echo()
  assert(restarted, NO_RESTART)
  greetingNote()
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
end

--- Whether a name is the robots' firmware's, in any case: the
--- card does not tell microbit.hex from MICROBIT.hex
--- @param name string
--- @return boolean
local function isFirmware(name)
  return name:upper() == HEX:upper()
end

--- Put a Lua script into a hex file. MICROBIT.hex is always
--- the firmware read from, and never the one written to: it
--- is the one copy that has to stay as it came.
--- @param hex_name string
--- @param lua_name string?
function embed(hex_name, lua_name)
  assert(hex_name, "name the hex file to write")
  local firmware = isFirmware(hex_name)
  assert(not firmware, HEX .. " cannot be overwritten")
  local blocks = blocksOf(HEX)
  hex.embed(blocks, read(lua_name or LUA))
  writefile(hex_name, hex.write(blocks))
end

--- The hex file's name for a Lua file, its ending in the
--- case it was typed in: robot.lua gives robot.hex, ROBOT.LUA
--- gives ROBOT.HEX; nil for any other file
--- @param filename string
--- @return string?
local function hexNameOf(filename)
  local base, ending = filename:match("^(.*)%.([Ll][Uu][Aa])$")
  if not base then
    return nil
  end
  local upper = ending == "LUA"
  return base .. (upper and ".HEX" or ".hex")
end

--- The end of a long bracket around a script, long enough
--- that nothing in the script ends it first
--- @param script string
--- @return string
local function closing(script)
  local level = ""
  while script:find("]" .. level .. "]", 1, true) do
    level = level .. "="
  end
  return "]" .. level .. "]"
end

--- A script as a long string: a line break before its end
--- only when the script's last character would join it
--- @param script string
--- @return string
local function quoted(script)
  local close = closing(script)
  local open = (close:gsub("%]", "["))
  local joins = script:find("[%]=]$") ~= nil
  local tail = joins and "\n" or ""
  return open .. "\n" .. script .. tail .. close
end

--- Where the firmware's script arms the port and shows its
--- prompt, found last: the last thing it does, after which
--- the REPL and the event handlers run
local ARMING = ".*()\nserial_session%.prompt%(%)"

--- The Lua file, run where the firmware's script is about to
--- arm the port. Nothing else runs Lua meanwhile: on_event,
--- through which the firmware calls in, is set aside, and an
--- on_event the file defines is held until the file returns.
--- A mistake stops only the file, and is printed and its
--- start scrolled; the prompt comes after it all the same.
local RUN_START = table.concat({
  "",
  "do",
  "local firmware, env = on_event, { }",
  "on_event = nil",
  "local function set(t, k, v)",
  "  if k == 'on_event' then rawset(t, k, v)",
  "  else _G[k] = v end",
  "end",
  "setmetatable(env, { __index = _G, __newindex = set })",
  "local file, err = loadstring(%s, %s)"
}, "\n")

--- The end of the Lua file's run, after it is read
local RUN_END = table.concat({
  "local ran = file ~= nil",
  "if ran then ran, err = pcall(setfenv(file, env)) end",
  "local function say()",
  "  local text = tostring(err)",
  "  print(text)",
  "  microbit.display.scroll(text:sub(1, 60))",
  "end",
  "if not ran then pcall(say) end",
  "on_event = rawget(env, 'on_event') or firmware",
  "end"
}, "\n")

--- The largest Lua file upload puts on the board. The board
--- holds the file as text and as parsed code while it reads
--- it, in about 100 KB of memory shared with the firmware's
--- own script. The figure is an estimate, not yet measured on
--- a board.
local MAX_SCRIPT = 8000

--- Say that MICROBIT.hex has no place for a Lua file, and
--- how to send the file alone
--- @param filename string
local function noPlace(filename)
  local hex_name = hexNameOf(filename)
  print(HEX .. " here is not the firmware the Compy came")
  print("with, and has no place for your program. To send it")
  print("alone, without the board's prompt, type")
  print(("embed(%q, %q)"):format(hex_name, filename))
  print(("then upload(%q)."):format(hex_name))
end

--- The firmware's own script with a Lua file run in it; nil,
--- said, when the firmware's script has no place for one
--- @param runtime string
--- @param script string
--- @param filename string
--- @return string?
local function withRuntime(runtime, script, filename)
  local at = runtime:match(ARMING)
  if not at then
    noPlace(filename)
    return nil
  end
  local name = string.format("%q", "@" .. filename)
  local start = RUN_START:format(quoted(script), name)
  local run = start .. "\n" .. RUN_END
  return runtime:sub(1, at - 1) .. run .. runtime:sub(at)
end

--- Say that a Lua file is empty
--- @param filename string
local function empty(filename)
  local edit = "edit(%q), then upload it again."
  print(filename .. " is empty. Write your program with")
  print(edit:format(filename))
end

--- Say that a Lua file is too long for the board
--- @param filename string
local function tooLong(filename)
  print(filename .. " is too long for the micro:bit, which")
  local limit = "takes a program of up to %d characters."
  print(limit:format(MAX_SCRIPT))
  print("Make it shorter, then upload it again.")
end

--- A Lua file's text; nil, said, when it holds no program or
--- is too long for the board
--- @param filename string
--- @return string?
local function scriptOf(filename)
  local script = read(filename)
  if not script:find("%S") then
    empty(filename)
    return nil
  end
  if MAX_SCRIPT < #script then
    tooLong(filename)
    return nil
  end
  return script
end

--- MICROBIT.hex with a Lua file run in its own script, so
--- the board keeps its REPL and robot commands; nil, said,
--- when the file is empty or too long
--- @param filename string
--- @return string?
local function build(filename)
  local script = scriptOf(filename)
  if not script then
    return nil
  end
  local blocks = blocksOf(HEX)
  local runtime = hex.script(blocks)
  local whole = withRuntime(runtime, script, filename)
  if not whole then
    return nil
  end
  hex.embed(blocks, whole)
  return hex.write(blocks)
end

--- Whether a Lua file's hex would overwrite the robots'
--- firmware, said when it would
--- @param filename string
--- @param hex_name string
--- @return boolean
local function overwrites(filename, hex_name)
  if isFirmware(hex_name) then
    print(filename .. " would overwrite " .. HEX .. ", the")
    print("robots' firmware. Give your script another name:")
    local copy = "writefile(\"robot.lua\", readfile(%q))"
    print(copy:format(filename))
    print("then upload(\"robot.lua\").")
    return true
  end
  return false
end

--- Whether a hex file built for upload is on the card as
--- built: the console's writefile says how it went, but
--- does not tell. Said when it is not, since what the card
--- holds under that name may be an older build.
--- @param hex_name string
--- @param data string
--- @return boolean
local function saved(hex_name, data)
  writefile(hex_name, data)
  if readfile(hex_name) == data then
    return true
  end
  print(hex_name .. " could not be saved, so nothing was")
  print("sent to the micro:bit.")
  return false
end

--- The hex file upload sends, and what it holds: the file
--- itself, or for a Lua file, a hex file of its name that
--- runs the script too; nil, said, when that would overwrite
--- the robots' firmware, cannot be built or is not saved
--- @param filename string
--- @return string? name
--- @return string? data
local function hexFor(filename)
  local hex_name = hexNameOf(filename)
  if not hex_name then
    return filename, read(filename)
  end
  if overwrites(filename, hex_name) then
    return nil
  end
  local data = build(filename)
  local kept = data and saved(hex_name, data)
  if kept then
    return hex_name, data
  end
end

--- Say which firmware a hex file holds, when it says
--- @param name string
--- @param version string?
local function holds(name, version)
  if version then
    print(name .. " holds firmware " .. version)
  end
end

--- What the Compy tells the upload: the file it read, and
--- the sending beginning
--- @param name string
--- @return table
local function uploadHooks(name)
  return {
    read = function(image)
      holds(name, hex.version(image))
    end,
    sending = function()
      compy.audio.hyperjump()
    end
  }
end

--- Put a hex file on the board over the USB cable, as a
--- Compy does: the Compy reads the file a share at a time,
--- says which firmware it holds, then says every few seconds
--- how far it has got, and at the end whether the board took
--- it; the board restarts with it. A sound says the sending
--- has begun.
--- @param name string
--- @param data string
local function uploadOverCable(name, data)
  local ok, err = flash_microbit(data, uploadHooks(name))
  if not ok then
    print(err)
  end
end

--- Put a hex file on the board's drive, on a computer. The
--- board is looked for each time, since it usually goes in
--- after Compy has started. Copying takes a few seconds and
--- the screen does not move until it is done, so a sound says
--- the copying has begun. The board then writes the file into
--- its memory by itself and restarts; the Compy cannot see
--- whether it took it.
--- @param name string
--- @param data string
local function uploadToDrive(name, data)
  local version = hex.version(hex.parse(data))
  compy.audio.hyperjump()
  local ok, err = flash_microbit(data)
  assert(ok, err)
  print(name .. " is sent. The micro:bit's light blinks")
  print("while it writes it, then it restarts with it.")
  holds(name, version)
end

--- Whether the file goes down the cable: on a Compy that
--- sends files that way; a computer, or an older Compy,
--- copies it to the drive, as before
--- @return boolean
local function overCable()
  return love.system.getOS() == "Android" and cableFlash()
end

--- Whether upload may begin: exec is not sending, stopped
--- with words when it is, and no file is on its way already,
--- false, said, when one is
--- @return boolean
local function mayUpload()
  assert(not isSending(), "exec is still sending a file")
  return not flashing()
end

--- The hex file to send and what it holds, nil when there is
--- none; on the drive the board is looked for first, so
--- without one no file is written
--- @param filename string
--- @param cable boolean
--- @return string? name
--- @return string? data
local function fileToSend(filename, cable)
  if not cable then
    assert(detect_microbit(), "no micro:bit plugged in")
  end
  return hexFor(filename)
end

--- Put a hex file on the board, or a Lua file: that goes
--- into a hex file of its name first, after the firmware's
--- own script, which it keeps
--- @param filename string?
function upload(filename)
  if not mayUpload() then
    return
  end
  local cable = overCable()
  local name, data = fileToSend(filename or HEX, cable)
  if not name then
    return
  end
  local send = cable and uploadOverCable or uploadToDrive
  send(name, data)
end

-- help --------------------------------------------------------

--- The commands for the board itself, then those for its
--- firmware
local COMMANDS = {
  "help()                  this list",
  "echo(on)                board output in the console;",
  "                        echo(false) stops it, echo()",
  "                        resumes",
  "send(filename)          file to the board, as typed",
  "exec(filename)          file to the board a line at a",
  "                        time, run as one chunk",
  "restart_microbit()      the board starts again, as its",
  "                        reset button makes it"
}

local FIRMWARE = {
  "hexmap(hex)             what a hex file holds",
  "extract(hex, lua)       its script out to a file",
  "embed(hex, lua)         a script into a new hex, in",
  "                        place of the firmware's own",
  "upload(file)            a hex file onto the board, or a",
  "                        lua file, put in a hex first"
}

function help()
  print("micro:bit tools")
  for _, line in ipairs(COMMANDS) do
    print("  " .. line)
  end
  for _, line in ipairs(FIRMWARE) do
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
