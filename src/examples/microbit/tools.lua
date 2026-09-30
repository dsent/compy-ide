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
--- The way back when the board runs a program of its own from
--- upload: restart_microbit only starts that program again
local UPLOADED = "If a program of yours is on it from upload,"
    .. " upload() puts the Compy's firmware back."
local STOPPED = "the board stopped answering. Type" ..
    " restart_microbit(), then try again. " .. UPLOADED

--- The file exec is sending, while it sends
local sending = nil

--- The end of a long bracket around a script, long enough
--- that nothing in the script ends it first. It is never
--- [[ ]]: the board's Lua refuses a [[ inside one of those.
--- @param script string
--- @return string
local function closing(script)
  local level = "="
  while script:find("]" .. level .. "]", 1, true) do
    level = level .. "="
  end
  return "]" .. level .. "]"
end

--- How the chunk exec sends ends: it runs the file, says a
--- mistake in the board's own words, then says how the file
--- ended on a line of its own, its frame: a character no
--- program prints by chance, and a mark new to each exec. A
--- line break goes before it, so it starts a line even after
--- output with no end. The console's echo is given the frame
--- too, and says how a file that ran on past exec's wait
--- ended in its place.
local FRAME = "\30exec "
local RAN = table.concat({
  "local ok = file ~= nil if ok then ok, err = P(file) end",
  " if not ok then say((file and 'Runtime' or 'Compile')",
  " .. ' error: ' .. T(err)) end",
  " say('\\r\\n\\30exec %s ' .. (ok and 'ok' or 'error')) end"
})

--- How many frames exec has made
local frames = 0

--- A frame of its own for the exec about to start
--- @return string
local function newFrame()
  frames = frames + 1
  local mark = ("%x%04x"):format(os.time(), frames % 65536)
  return FRAME .. mark .. " "
end

--- The first line exec sends begins so: what the chunk uses
--- is taken from the board's globals as they are before the
--- file runs, so what the file puts there changes nothing; the
--- frame goes straight to the port, when the board has one,
--- past whatever print is. With no pcall left from an earlier
--- file, the file runs unprotected. With no rawget, loadstring
--- or tostring the board's own prompt fails before the file
--- runs, and exec says the board did not say whether it ran.
local OPENING = "do local R, G = rawget, _G local file, err ="
    .. " R(G, 'loadstring')("

--- What the closing line adds after the file's name: the rest
--- the chunk uses, taken still before the file runs
local TAKE = table.concat({
  " local m, P, T, W = R(G, 'microbit'), R(G, 'pcall'),",
  " R(G, 'tostring'), R(G, 'print')"
})

--- The line after it: how the chunk says a line
local SAY = table.concat({
  "local s = m and m.serial and m.serial.send",
  " local function say(t)",
  " if s then s(t .. '\\r\\n') else W(t) end end",
  " P = P or function(f) return true, f() end"
})

--- The line after the file: the end of its bracket, its
--- name, and the rest the chunk takes
--- @param filename string
--- @param close string
--- @return string
local function closingLine(filename, close)
  local name = string.format("%q", "@" .. filename)
  return close .. ", " .. name .. ")" .. TAKE
end

--- The last line exec sends: the run and the frame
--- @param frame string
--- @return string
local function runLine(frame)
  return RAN:format(frame:match("^\30exec (%x+) $"))
end

--- How many lines exec sends besides the file's
local WRAPPING = 4

--- The lines exec sends: the file in a chunk of its own, so
--- what the code declares stays in it, named for the file in
--- the board's words for a mistake; and the frame its end is
--- said in, as lines.frame
--- @param filename string
--- @return string[]
local function chunkLines(filename)
  local text = fileForBoard(filename)
  local close = closing(text)
  local open = (close:gsub("%]", "["))
  local lines = { OPENING .. open }
  lines.frame = newFrame()
  for line in text:gmatch("([^\r]*)\r") do
    lines[#lines + 1] = line
  end
  lines[#lines + 1] = closingLine(filename, close)
  lines[#lines + 1] = SAY
  lines[#lines + 1] = runLine(lines.frame)
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
  local total = #(sending.lines) - WRAPPING
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
--- @param frame string? the frame echo is to take in place
---   of the board's line, for a file still running
local function finish(outcome, frame)
  putBack()
  sending = nil
  echo(nil, frame)
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
  sending.since = 0
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

--- Say how far exec has got, every PROGRESS_S, once for each
--- line it gets to: a line said again reads as stuck
--- @param dt number
local function tell(dt)
  sending.told = sending.told + dt
  local at = where()
  local due = PROGRESS_S <= sending.told
  local moved = at ~= sending.toldAt
  local say = due and moved
  if say then
    sending.told = 0
    sending.toldAt = at
    print("exec: " .. at)
  end
end

--- No prompt QUIET_S after the last line: once the board has
--- taken it, the file is still running, as a program that
--- loops is, and echo shows the rest as it comes
--- @param after string?
local function quietLast(after)
  if after then
    show(after)
    local running = " is on the board and still running"
    finish(sending.name .. running, sending.lines.frame)
  else
    stopAt(STOPPED)
  end
end

--- What the board said, less this exec's frame at its end and
--- the line break that went before it; and how the frame says
--- the file ended. A frame anywhere else, or of another exec,
--- is the program's own output.
--- @param said string
--- @return string text
--- @return string? status
local function framed(said)
  local frame = sending.lines.frame
  local at = said:find(frame, 1, true)
  while at do
    local status = said:sub(at + #frame):match("^(%a+)\r?\n?$")
    if status then
      local text = said:sub(1, at - 1)
      return (text:gsub("\r?\n$", "")), status
    end
    at = said:find(frame, at + 1, true)
  end
  return said
end

--- What exec says once the board has run the file, from its
--- frame alone
--- @param status string?
--- @return string
local function verdict(status)
  if status == "ok" then
    return sending.name .. " is on the board"
  end
  if status == "error" then
    return sending.name .. " was run, and stopped on the" ..
        " mistake above"
  end
  return "the board did not say whether " .. sending.name ..
      " ran. Type restart_microbit(), then try again."
end

--- This exec's frame with its status and line break, found in
--- what the board said: the file has ended. What came before
--- it, less the line break that went before the frame, and
--- the status.
--- @param after string
--- @return string? text
--- @return string? status
local function frameIn(after)
  local frame = sending.lines.frame
  local at = after:find(frame, 1, true)
  while at do
    local status = after:sub(at + #frame):match("^(%a+)\r\n")
    if status then
      return (after:sub(1, at - 1):gsub("\r?\n$", "")), status
    end
    at = after:find(frame, at + 1, true)
  end
end

--- How a frame says the file ended
local ENDS = {
  "ok",
  "error"
}

--- Whether what the board said ends in the start of this
--- exec's end line, the rest of which is on its way
--- @param after string
--- @return boolean
local function endComing(after)
  for _, status in ipairs(ENDS) do
    local whole = sending.lines.frame .. status .. "\r\n"
    for n = #whole - 1, 1, -1 do
      if after:sub(-n) == whole:sub(1, n) then
        return true
      end
    end
  end
  return false
end

--- The file ran past QUIET_S: ended after all, when its frame
--- has come; still on its way, while the end of what came may
--- be its start; else still running, and echo shows the rest
--- @param after string?
local function longLast(after)
  local text, status = frameIn(after or "")
  if status then
    show(text)
    finish(verdict(status))
  elseif not (after and endComing(after)) then
    quietLast(after)
  end
end

--- The last line runs the file: a prompt the board has been
--- quiet after means the file has run, as far as the board's
--- bytes can tell; a program that writes "> " and pauses looks
--- the same. No prompt QUIET_S after the line went, however
--- much the file prints, and the file is still running.
local function lastLine()
  local after = afterEcho()
  local said = after and after:match("^(.*)> $")
  local done = said and SETTLE_S <= sending.quiet
  if done then
    local text, status = framed(said)
    show(text)
    finish(verdict(status))
  elseif QUIET_S < sending.quiet then
    quietLast(after)
  elseif QUIET_S < sending.since then
    longLast(after)
  end
end

--- A line the board has not taken QUIET_S after it went, or
--- has said nothing for as long: a board that runs a program
--- of its own may send all the while, and never echo it
--- @return boolean
local function unanswered()
  local unechoed = QUIET_S < sending.since and not afterEcho()
  return QUIET_S < sending.quiet or unechoed
end

--- Time passing while exec waits on the board
--- @param dt number
local function waiting(dt)
  tell(dt)
  sending.quiet = sending.quiet + dt
  sending.since = sending.since + dt
  if sending.at == #(sending.lines) then
    lastLine()
  elseif unanswered() then
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

--- Whether exec is still sending a file, said when it is
--- @return boolean
local function busy()
  if not isSending() then
    return false
  end
  print("exec is still sending " .. sending.name .. ". Wait")
  print("until it says how it went, or type")
  print("restart_microbit() to stop it.")
  return true
end

--- Whether the board can take a file now; a stop, in words,
--- when it is not there, and false, said, while it takes new
--- firmware or exec is still sending a file
--- @return boolean
local function readyToSend()
  assert(serial.isConnected(), "no micro:bit connected")
  return not flashing() and not busy()
end

--- exec's handlers take the board over while it sends
local function takeOver()
  for field, handler in pairs(sending.mine) do
    serial[field] = handler
  end
  compy.before_exit = stopped
end

--- Run a project file on the board as one chunk, loaded from
--- a long string and run in a protected call, sent a line at
--- a time. The board's echo of the file is not shown; what it
--- answers is.
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
  print("socket. If a program of yours is on it from")
  print("upload, upload() puts the Compy's firmware back.")
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

--- The largest Lua file upload puts on the board, in bytes.
--- The file becomes the board's whole program. The board
--- reads it in place, from its flash, with about 90 KB of
--- memory free, and the parsed code grows with how much the
--- file does per character: a long table of distinct strings
--- costs about three times what a program of the same length
--- usually does. A board that runs out of memory reading its
--- program does not start: it shows 020 on every start until
--- upload() puts the Compy's firmware back. Measured with the
--- board's Lua and a CODAL-like allocator on a computer, 6000
--- keeps the densest code tried within the memory that a
--- 7916-character program of the usual kind took, beside the
--- Compy's own script, on a board where it started; the
--- densest code at 6000 is yet to be tried on one.
local MAX_SCRIPT = 6000

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
  local limit = "takes a program of up to %d characters;"
  print(limit:format(MAX_SCRIPT))
  print("letters with accents and signs beyond a plain")
  print("keyboard count as two or more. Make it shorter, then")
  print("upload it again.")
end

--- Say what the mistake in a Lua file is, and where
--- @param filename string
--- @param err string LuaJIT's words, "name:line: what"
local function mistake(filename, err)
  local line, what = err:match(":(%d+): (.*)$")
  local where = line and " on line " .. line or ""
  print(filename .. " has a mistake" .. where .. ":")
  print(what or err)
  print("The micro:bit would stop on it every time it starts.")
  print(("Put it right with edit(%q), then"):format(filename))
  print("upload it again.")
end

--- The invisible mark some computers' editors put first in a
--- file, a byte order mark
local BOM = string.char(239, 187, 191)

--- Say that a Lua file begins with the invisible mark some
--- computers' editors put first (a byte order mark)
--- @param filename string
local function marked(filename)
  print(filename .. " begins with an invisible mark a")
  print("computer's editor put there, which the micro:bit")
  print("cannot read. To take it off, type")
  local off = "writefile(%q, readfile(%q):sub(4))"
  print(off:format(filename, filename))
  print("then upload it again.")
end

--- Say that a Lua file's first line starts with #
--- @param filename string
local function hashed(filename)
  print(filename .. " begins with a line that starts with #,")
  print("which the micro:bit cannot read. Take that line out")
  local edit = "with edit(%q), then upload it again."
  print(edit:format(filename))
end

--- Whether a Lua file begins with something LuaJIT skips and
--- the board's Lua 5.1 cannot read, said when it does
--- @param filename string
--- @param script string
--- @return boolean
local function markedStart(filename, script)
  local bom = script:sub(1, 3) == BOM
  local hash = script:sub(1, 1) == "#"
  if bom then
    marked(filename)
  elseif hash then
    hashed(filename)
  end
  return bom or hash
end

--- A Lua file's text, when the board can read it; nil, said,
--- when it has a mistake that stops it from being read. The
--- Compy reads it with LuaJIT, which takes a few things the
--- board's Lua 5.1 does not: goto and labels, \x and \z in
--- strings, and a [[ inside a [[ ]] string. A file with one
--- of those passes here, and the board says "Compile error"
--- at every start.
--- @param filename string
--- @param script string
--- @return string?
local function readable(filename, script)
  if markedStart(filename, script) then
    return nil
  end
  local fn, err = loadstring(script, "=" .. filename)
  if fn then
    return script
  end
  mistake(filename, err)
  return nil
end

--- A Lua file's text, its line endings the board's own; nil,
--- said, when it holds no program, is too long for the board,
--- or has a mistake that stops it from being read
--- @param filename string
--- @return string?
local function scriptOf(filename)
  local script = (read(filename):gsub("\r\n?", "\n"))
  if not script:find("%S") then
    empty(filename)
    return nil
  end
  if MAX_SCRIPT < #script then
    tooLong(filename)
    return nil
  end
  return readable(filename, script)
end

--- MICROBIT.hex with a Lua file as its program in place of
--- the Compy's own; nil, said, when the file cannot be one
--- @param filename string
--- @return string?
local function build(filename)
  local script = scriptOf(filename)
  if not script then
    return nil
  end
  local blocks = blocksOf(HEX)
  hex.embed(blocks, script)
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
    print("robots' firmware. Put it in a firmware file of")
    print("another name, then send that:")
    print(("embed(\"mine.hex\", %q)"):format(filename))
    print("upload(\"mine.hex\")")
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
  print("sent to the micro:bit. The lines above say why.")
  print("When the Compy is full, delete files you no longer")
  print("need, then upload it again.")
  return false
end

--- The hex file upload sends, and what it holds: the file
--- itself, or for a Lua file, a hex file of its name with the
--- file as its program; nil, said, when that would overwrite
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

--- Whether upload may begin: exec is not sending, and no file
--- is on its way already; false, said, when either is
--- @return boolean
local function mayUpload()
  return not busy() and not flashing()
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
--- into a hex file of its name first, as the board's whole
--- program in place of the Compy's own
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
