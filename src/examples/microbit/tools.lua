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

--- How wide the tools' own lines are, inside the console's
--- 64 columns: a longer line would break mid-word
local LINE = 56

--- Words for the person, broken between words at LINE, never
--- inside one
--- @param text string
local function say(text)
  local line
  for word in text:gmatch("%S+") do
    if not line then
      line = word
    elseif #line + 1 + #word <= LINE then
      line = line .. " " .. word
    else
      print(line)
      line = word
    end
  end
  print(line or "")
end

--- A command stopped for a reason a person can put right is
--- raised with its words under this key: they say what to do,
--- in place of an error with a line number
local REFUSAL = { }

--- Stop the command, saying why, a line at a time
--- @param ... string
local function refuse(...)
  error({ [REFUSAL] = { ... } }, 0)
end

--- Say a refusal in its words; any other error goes on as it
--- came
--- @param err any
local function said(err)
  local words = type(err) == "table" and err[REFUSAL]
  if not words then
    error(err, 0)
  end
  say(table.concat(words, " "))
end

--- A command that says a refusal in words
--- @param command function
--- @return function
local function plainly(command)
  return function(...)
    local ok, err = pcall(command, ...)
    if not ok then
      said(err)
    end
  end
end

--- Stop a command that needs the board, which the Compy
--- cannot see
--- @param command string what to run again
local function noBoard(command)
  refuse(
    "No micro:bit is plugged in that the Compy can see.",
    "Plug it in with a data cable, or unplug it and plug it",
    "in again, then run " .. command .. " again."
  )
end

--- Stop a command that needs the board, when the Compy cannot
--- see one
--- @param command string what to run again
local function seen(command)
  if not serial.isConnected() then
    noBoard(command)
  end
end

-- How much of the script hexmap shows, as hextract's
-- structure does: enough to tell which script it is, and
-- that the metadata points at one at all
local PEEK = 256

--- Stop a command given no file name, or something else in
--- its place, in words
--- @param name any
local function named(name)
  if type(name) ~= "string" then
    refuse("Name the file in quotes, such as \"blink.lua\".")
  end
end

--- The firmware the tools build every firmware file from, when
--- the project lacks it: the name was right
local NO_FIRMWARE = {
  "This project has no " .. HEX .. ", which upload and",
  "embed build every firmware file from. Copy the",
  "microbit project, which has it, with",
  "clone(\"microbit\", \"myboard\"), and keep your files there."
}

--- Stop a command whose file the project does not have
--- @param filename string
local function missing(filename)
  if filename == HEX then
    refuse(unpack(NO_FIRMWARE))
  end
  refuse(
    "This project has no file called " .. filename .. ".",
    "Check the name, then try again."
  )
end

--- A project file, or a stop saying there is none, in these
--- words alone: the console is asked to say nothing of it
--- @param filename string
--- @return string
local function read(filename)
  named(filename)
  local text = readfile(filename, true)
  if not text then
    missing(filename)
  end
  return text
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

-- The board takes a line, then answers it with a prompt: "> "
-- when it is ready for a new statement, ">> " while a chunk is
-- still open. What arrives while it runs a line waits in 254
-- characters, and the rest is lost, so exec and send both send
-- a line and wait for the prompt before the next.

--- How long the board may say nothing before exec stops
--- waiting on it
local QUIET_S = 5
--- How long the board must be quiet after the last line's
--- prompt before it counts: what the program prints may end
--- in "> " too
local SETTLE_S = 0.2
--- How often exec says how far it has got
local PROGRESS_S = 3
--- How long exec waits for the board to take a line, from when
--- it went or its echo last moved on: a board whose prompt
--- waits behind a program of its own, busy with something
--- else, takes it late
local TAKE_S = 60
--- The way back when the board runs a program of its own from
--- upload: restart_microbit only starts that program again
local UPLOADED = "If a program of yours is on it from upload,"
    .. " upload() puts the Compy's firmware back."
local STOPPED = "the board stopped answering. Type" ..
    " restart_microbit(), then try again. " .. UPLOADED
local NOT_TAKEN = "the board did not take it. Type" ..
    " restart_microbit(), then try again. " .. UPLOADED
local CHANGED = table.concat({
  "the board got that line changed, and the file would not",
  " run as written. Type restart_microbit(), then try again."
})
local STILL_RUNNING = "that line was still running after a" ..
    " minute, and the rest was not sent. Type" ..
    " restart_microbit(), then try again."

--- The file exec or send is sending, while it sends: send's
--- is plain, its lines as they are, their echo and what the
--- board answers shown as they come
local sending = nil

--- The command sending the file, for its words
--- @return string
local function verb()
  return sending.plain and "send" or "exec"
end

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

--- How the chunk exec sends ends, once the file has run: it
--- says a mistake in the board's own words, then how the file
--- ended on a line of its own, its frame: a character no
--- program prints by chance, and a mark new to each exec. A
--- line break goes before it, so it starts a line even after
--- output with no end. The console's echo is given the frame
--- too, and says how a file that ran on past exec's wait
--- ended in its place. What exec adds goes down the cable
--- with every file, and the board reads and echoes each
--- character, so it is written as short as Lua reads it:
--- one-letter names, and no space the parser does not need.
local FRAME = "\30exec "
local RAN = table.concat({
  "local z='\\r\\n\\30exec %s '..(o and'ok'or f and'error'",
  "or'compile')if not o then z=(f and'Runtime'or'Compile')",
  "..' error: '..T(e)..z end if s then s(z..'\\r\\n')else W(z)",
  "end end"
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
--- file, the file runs unprotected. With no rawget or
--- loadstring the chunk stops before the file runs, and exec
--- says the board did not say whether it ran: the board's
--- prompt keeps a loadstring of its own, and reads every line;
--- with no tostring the file runs, and a mistake in it comes
--- with no frame.
local OPENING =
    "do local R,G=rawget,_G local f,e=R(G,'loadstring')("

--- What the closing line adds after the file's name: the rest
--- the chunk uses, taken still before the file runs
local TAKE = table.concat({
  "local m,P,T,W=R(G,'microbit'),R(G,'pcall'),",
  "R(G,'tostring'),R(G,'print')"
})

--- The line after it: where the chunk says how the file
--- ended, the port or else print; and the file's run, with
--- a pcall that runs it unprotected when there is none
local SAY = table.concat({
  "local s=m and m.serial s=s and s.send",
  " P=P or function(g)return true,g()end",
  " local o if f then o,e=P(f)end"
})

--- The line after the file: the end of its bracket, its
--- name, and the rest the chunk takes
--- @param filename string
--- @param close string
--- @return string
local function closingLine(filename, close)
  local name = string.format("%q", "@" .. filename)
  return close .. "," .. name .. ")" .. TAKE
end

--- The last line exec sends: the mistake and the frame
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

--- Where exec or send is in the file, counted in the file's
--- lines: exec's first line opens its chunk
--- @return string
local function where()
  local wrapping = sending.plain and 0 or WRAPPING
  local total = #(sending.lines) - wrapping
  local at = sending.at - math.min(wrapping, 1)
  local line = math.min(math.max(at, 1), total)
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

--- What the board said that exec has not shown goes to
--- echo, which reads it as it reads what comes next: an end
--- line cut in two is read whole. A console whose echo takes
--- none of it has it shown here.
--- @param frame string? the frame echo is to take in place
---   of the board's line, for a file still running
--- @param rest string?
local function pass(frame, rest)
  local taken = echo(nil, frame, rest)
  local unshown = rest and not taken
  if unshown then
    show(rest)
  end
end

--- Say what happened, and hand the board back. Echo comes back
--- on: it shows what the board says from here on, and first
--- before, what came before the outcome; after, what came
--- after the file's end, goes after the outcome.
--- send leaves echo on throughout, and says nothing at a
--- file's end.
--- @param outcome string?
--- @param frame string?
--- @param before string?
--- @param after string?
local function finish(outcome, frame, before, after)
  local plain = sending.plain
  putBack()
  sending = nil
  if not plain then
    pass(frame, before)
  end
  if outcome then
    say(outcome)
  end
  if after then
    pass(frame, after)
  end
end

--- @param why string
local function stopAt(why)
  finish(verb() .. " stopped at " .. where() .. ": " .. why)
end

--- A line just sent: nothing heard of it, no time waited
local function fresh()
  sending.heard = ""
  sending.quiet = 0
  sending.since = 0
  sending.waited = 0
  sending.echoed = 0
  sending.warned = false
  sending.shown = 0
  sending.long = false
  sending.got = nil
end

--- The next line on its way, or the end of the file
local function sendNext()
  sending.at = sending.at + 1
  fresh()
  local line = sending.lines[sending.at]
  if not line then
    local ran = not sending.plain
         and sending.name .. " is on the board"
    finish(ran or nil)
  elseif not serial.send(line .. "\r") then
    stopAt("the board is not connected")
  end
end

--- What exec says when the board ends its chunk early
local EARLY = "the board stopped reading the file before its"
    .. " end, and did not run it. Type restart_microbit(), then"
    .. " try again."

--- A line's prompt lets the next line go. A prompt for a new
--- statement before the last line means the board ended the
--- chunk early, before the file could run, and the rest would
--- reach it as statements of their own.
--- send's lines are each their own statement: echo has shown
--- what the board said, and any prompt lets the next go.
--- @param said string
--- @param open boolean
local function answered(said, open)
  if sending.plain then
    sendNext()
    return
  end
  show(said)
  if open then
    sendNext()
  else
    stopAt(EARLY)
  end
end

--- send's last line is done once the board has taken it: no
--- line waits on its prompt
local function heardLast()
  local done = sending.plain and afterEcho()
  if done then
    finish()
  end
end

--- The line the board entered in place of the line in flight,
--- once its prompt has come: the board ends a line it enters
--- with CR CR LF, and what came before that differs from the
--- line sent. nil while the line's own echo is there, or may
--- yet come.
--- @return string?
local function changed()
  local prompt = sending.heard:find(">>? $")
  local got = not afterEcho() and prompt and sending.got
  return got or nil
end

--- What send says after the line of the board's it got changed
local GOT_CHANGED = table.concat({
  " changed, so what it ran may differ from the file; the",
  " lines above show what it got."
})

--- The board entered the line changed: send says so and goes
--- on, echo having shown what the board got; exec stops, the
--- file changed on its way
local function mistook()
  if not sending.plain then
    stopAt(CHANGED)
    return
  end
  say("send: the board got " .. where() .. GOT_CHANGED)
  sendNext()
end

--- Whether the board entered the line in flight changed, done
--- with when it did: the first line it entered is kept, as
--- what it got, before a wait can show and drop it
--- @return boolean
local function heardChanged()
  local entered = sending.heard:match("([^\n]*)\r\r\n")
  sending.got = sending.got or entered
  local got = changed()
  if got then
    mistook()
  end
  return got ~= nil
end

--- What the board has said of the line in flight: the last
--- line's is send's alone, exec leaving its prompt to waiting
local function heardLine()
  if sending.at == #(sending.lines) then
    heardLast()
    return
  end
  local said, open = reply(afterEcho() or "")
  if said then
    answered(said, open)
  end
end

--- The board's bytes while exec or send sends: a line it
--- entered changed is seen first. exec leaves its last line's
--- prompt to waiting, which lets the board settle first.
--- @param chunk string
local function hear(chunk)
  sending.heard = sending.heard .. chunk
  sending.quiet = 0
  if not heardChanged() then
    heardLine()
  end
end

--- Say how far exec has got, every PROGRESS_S, once for each
--- line it gets to: a line said again reads as stuck
--- @param dt number
local function tell(dt)
  sending.told = (sending.told or 0) + dt
  local at = where()
  local due = PROGRESS_S <= sending.told
  local moved = at ~= sending.toldAt
  local say = due and moved
  if say then
    sending.told = 0
    sending.toldAt = at
    print(verb() .. ": " .. at)
  end
end

--- How a frame says the file ended, and what exec says of it
--- after the file's name: it ran; it ran, and stopped on a
--- mistake; the board could not compile it, so it never ran
local VERDICTS = {
  ok = " is on the board",
  error = " was run, and stopped on the mistake above",
  compile = " could not run, because of the mistake above"
}

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
    local word = said:sub(at + #frame):match("^(%a+)\r?\n?$")
    local status = VERDICTS[word or ""] and word
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
  local words = VERDICTS[status]
  if words then
    return sending.name .. words
  end
  return "the board has not said how " .. sending.name ..
      " went. It may still be running; if the board does not"
      .. " answer, type restart_microbit(), then try again."
end

--- Where this exec's end line begins in what the board said,
--- and how it says the file ended: the frame, one of the
--- statuses it sends, and a line break. A line that begins as
--- the frame and goes on otherwise is the program's own.
--- @param said string
--- @return integer? at
--- @return string? status
local function endLine(said)
  local frame = sending.lines.frame
  local at = said:find(frame, 1, true)
  while at do
    local word = said:sub(at + #frame):match("^(%a+)\r\n")
    local status = VERDICTS[word or ""] and word
    if status then
      return at, status
    end
    at = said:find(frame, at + 1, true)
  end
end

--- This exec's end line, found in what the board said: the
--- file has ended. What came before it, less the line break
--- that went before the frame; the status; and what came
--- after, less the prompt, such as what an on_event of the
--- file's prints.
--- @param after string
--- @return string? text
--- @return string? status
--- @return string? rest
local function frameIn(after)
  local at, status = endLine(after)
  if not at then
    return
  end
  local rest = after:sub(
    at + #(sending.lines.frame) + #status + 2
  )
  return (after:sub(1, at - 1):gsub("\r?\n$", "")), status,
    (rest:gsub("^> ", ""))
end

--- What the file prints shows as it comes, a whole line at a
--- time, up to its end line, which the verdict takes with
--- what follows: sending.shown counts what of it is shown
--- @param after string
local function showRunning(after)
  local whole = after:match("^.*\n") or ""
  local at = endLine(whole)
  local cut = at and at - 1 or #whole
  if sending.shown < cut then
    show(whole:sub(sending.shown + 1, cut))
    sending.shown = cut
  end
end

--- What of the text before the end line is not shown yet
--- @param text string
--- @return string
local function unshown(text)
  return text:sub(sending.shown + 1)
end

--- Whether what the board said ends in the start of this
--- exec's end line, the rest of which is on its way
--- @param after string
--- @return boolean
local function endComing(after)
  for status in pairs(VERDICTS) do
    local whole = sending.lines.frame .. status .. "\r\n"
    for n = #whole - 1, 1, -1 do
      if after:sub(-n) == whole:sub(1, n) then
        return true
      end
    end
  end
  return false
end

--- No prompt QUIET_S after the board took the last line: the
--- file is still running, as a program that loops is, and
--- echo shows the rest as it comes
--- @param after string
local function quietLast(after)
  local running = " is on the board and still running"
  finish(
    sending.name .. running,
    sending.lines.frame,
    unshown(after)
  )
end

--- The file ran past QUIET_S: ended after all, when its frame
--- has come; still on its way, while the end of what came may
--- be its start; else still running, and echo shows the rest
--- @param after string
local function longLast(after)
  local text, status, rest = frameIn(after)
  if status then
    show(unshown(text))
    finish(verdict(status), nil, nil, rest)
  elseif not endComing(after) then
    quietLast(after)
  end
end

--- The last line's prompt, and the board quiet after it:
--- what the board said, and how the frame says the file
--- ended. With no frame, the "> " may be a program's own, one
--- still running, and echo is given the frame to say its end.
--- @param said string
local function prompted(said)
  local text, status = framed(said)
  show(unshown(text))
  local unended = status == nil and sending.lines.frame or nil
  finish(verdict(status), unended)
end

--- The last line runs the file, once the board has taken it:
--- a prompt the board has been quiet after means the file has
--- run, as far as the board's bytes can tell; a program that
--- writes "> " and pauses looks the same. No prompt QUIET_S
--- after the board took the line, however much the file
--- prints, and the file is still running.
--- @param after string
local function lastLine(after)
  showRunning(after)
  local said = after:match("^(.*)> $")
  local done = said and SETTLE_S <= sending.quiet
  if done then
    prompted(said)
  elseif QUIET_S < sending.quiet then
    quietLast(after)
  elseif QUIET_S < sending.since then
    longLast(after)
  end
end

--- How much of the line in flight's echo has come, at the end
--- of what the board said
--- @return integer
local function echoed()
  local echo = sending.lines[sending.at] .. "\r\r\n"
  local heard = sending.heard
  for n = math.min(#heard, #echo), 1, -1 do
    if heard:sub(-n) == echo:sub(1, n) then
      return n
    end
  end
  return 0
end

--- What came before an echo that has not come is not kept: an
--- echo still to come begins in the last of it
local function forget()
  local keep = #(sending.lines[sending.at]) + 3
  if 2 * keep < #(sending.heard) then
    sending.heard = sending.heard:sub(-keep)
  end
end

--- What the board says while the line waits is a program's of
--- its own, or a greeting, and is shown, a whole line at a
--- time, to its line feed: all but what may be the start of the
--- line's echo. A line the board entered ends CR CR LF, and
--- stays whole until it is told from the line's own.
local function showHeard()
  local heard = sending.heard
  local head = heard:sub(1, #heard - echoed())
  local lines = head:match("^.*\n")
  if lines then
    show(lines)
    sending.heard = heard:sub(#lines + 1)
  end
end

--- The echo moving on is the board taking the line: the wait
--- for the rest starts again
local function moved()
  local came = echoed()
  if sending.echoed < came then
    sending.echoed = came
    sending.waited = 0
  end
end

--- Say, once, that the board has not taken the line yet
local function warn()
  sending.warned = true
  local who = verb()
  local still = " and " .. who .. " is still waiting;"
  say(who .. ": the board has not taken " .. where() .. " yet,"
      .. still .. " restart_microbit() stops it. " .. UPLOADED)
end

--- A line send has sent, which the board took and still runs
--- with no prompt: a loop, or a long move. send says so once,
--- QUIET_S on, and stops at TAKE_S, with the rest unsent.
local function running()
  local due = QUIET_S < sending.since and not sending.long
  if TAKE_S < sending.since then
    stopAt(STILL_RUNNING)
  elseif due then
    sending.long = true
    say("send: " .. where() .. " is still running; send waits"
        .. " for its end before the next line, and" ..
        " restart_microbit() stops it.")
  end
end

--- The board has not taken the line in flight: its prompt may
--- wait behind a program of the board's own, busy with
--- something else, or a program from upload may be on it, which
--- has no prompt. So exec says so once, QUIET_S on, and waits
--- up to TAKE_S from when the line went or its echo moved on.
--- The wait for the prompt starts once the board has taken it.
local function untaken()
  sending.since = 0
  moved()
  showHeard()
  forget()
  local due = QUIET_S < sending.waited
  local unsaid = due and not sending.warned
  if TAKE_S < sending.waited then
    stopAt(NOT_TAKEN)
  elseif unsaid then
    warn()
  end
end

--- The board has taken the line in flight: send waits for its
--- prompt, exec for the last line's end or a prompt, and stops
--- on a board that goes quiet before one
--- @param after string
local function taken(after)
  if sending.plain then
    running()
  elseif sending.at == #(sending.lines) then
    lastLine(after)
  elseif QUIET_S < sending.quiet then
    stopAt(STOPPED)
  end
end

--- Time passing while exec waits on the board: for it to take
--- the line in flight, then for its prompt
--- @param dt number
local function waiting(dt)
  tell(dt)
  sending.quiet = sending.quiet + dt
  sending.since = sending.since + dt
  sending.waited = sending.waited + dt
  local after = afterEcho()
  if not after then
    untaken()
  else
    taken(after)
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

--- A project file's lines, as they are
--- @param filename string
--- @return string[]
local function plainLines(filename)
  local lines = { }
  for line in fileForBoard(filename):gmatch("([^\r]*)\r") do
    lines[#lines + 1] = line
  end
  return lines
end

--- What exec, or send (plain), keeps while it sends a file
--- @param filename string
--- @param plain boolean?
--- @return table
local function newSending(filename, plain)
  local mine = handlers()
  return {
    name = filename,
    plain = plain,
    lines = plain and plainLines(filename)
         or chunkLines(filename),
    mine = mine,
    kept = setAside(mine),
    stop = stopped,
    exit = compy.before_exit,
    at = 0
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
  print(
    verb() .. " is still sending " .. sending.name .. ". Wait"
  )
  print("until it says how it went, or type")
  print("restart_microbit() to stop it.")
  return true
end

--- Whether the board can take a file now; a stop, in words,
--- when it is not there, and false, said, while it takes new
--- firmware or exec is still sending a file
--- @return boolean
--- @param command string exec or send
local function readyToSend(command)
  seen(command)
  return not flashing() and not busy()
end

--- exec's or send's handlers take the board over while it
--- sends
local function takeOver()
  for field, handler in pairs(sending.mine) do
    serial[field] = handler
  end
  compy.before_exit = stopped
end

--- Send a project file to the board, a line at a time, as if
--- typed: each line once the board has answered the one
--- before, its echo and the answers shown as they come
--- @param filename string
function send(filename)
  if not readyToSend("send") then
    return
  end
  if sending then
    putBack()
  end
  sending = newSending(filename, true)
  takeOver()
  sendNext()
end

--- Run a project file on the board as one chunk, loaded from
--- a long string and run in a protected call, sent a line at
--- a time. The board's echo of the file is not shown; what it
--- answers is.
--- @param filename string
function exec(filename)
  if not readyToSend("exec") then
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
local NO_RESTART = "The micro:bit did not restart. Press its"
    .. " reset button, on the back next to the USB socket."

--- What to do when no greeting comes after a restart
local function greetingNote()
  print("The micro:bit restarts, and greets you when it")
  print("is ready. If it does not within a minute, press")
  print("its reset button, on the back next to the USB")
  print("socket. If a program of yours is on it from")
  print("upload, upload() puts the Compy's firmware back.")
end

--- What to do once the board was asked to restart: wait for
--- its greeting, or press its button when it did not restart
--- @param restarted boolean?
local function afterRestart(restarted)
  if restarted then
    greetingNote()
  else
    say(NO_RESTART)
  end
end

--- Restart the board, as its reset button does, without
--- touching it: the way back from a board that no longer
--- reads what it is sent, stuck in a loop or in listen(). An
--- exec still sending stops first, and echo comes back on,
--- so the greeting shows. While a file goes to the board, the
--- restart waits. The message says what to do when no
--- greeting comes.
function restart_microbit()
  seen("restart_microbit()")
  if flashing() then
    return
  end
  local restarted = serial.reset()
  if isSending() then
    stopAt(restarted and "the board was restarted"
         or "the board did not restart")
  end
  echo()
  afterRestart(restarted)
end

-- firmware ---------------------------------------------------

--- The blocks of a hex file's text, or a stop saying it is
--- damaged
--- @param filename string
--- @param text string
--- @return table[]
local function parsed(filename, text)
  local ok, blocks = pcall(hex.parse, text)
  if not ok then
    refuse(
      filename .. " is damaged: part of it is missing or",
      "changed, so it is not a firmware file the micro:bit",
      "can take. Copy it onto the Compy again."
    )
  end
  return blocks
end

--- The blocks of a hex file in the project
--- @param filename string
--- @return table[]
local function blocksOf(filename)
  return parsed(filename, read(filename))
end

--- Where a hex file keeps its Lua script, or a stop saying it
--- keeps none
--- @param blocks table[]
--- @param filename string
--- @return integer addr
--- @return table meta
local function scriptPlace(blocks, filename)
  local addr, meta = hex.meta(blocks)
  if not addr then
    refuse(
      filename .. " has no place for a Lua program: it is",
      "not firmware the micro:bit tools work with."
    )
  end
  return addr, meta
end

--- Put a Lua file's script into MICROBIT.hex's blocks, or
--- stop, saying so, when the firmware has no place for one or
--- the script does not fit in it
--- @param blocks table[]
--- @param lua_name string
--- @param script string
local function embedInto(blocks, lua_name, script)
  local room = hex.room(scriptPlace(blocks, HEX))
  if room < #script then
    local most = "%s is %d bytes, and %s has room for %d."
    refuse(
      most:format(lua_name, #script, HEX, room),
      "Make it shorter, then try again."
    )
  end
  hex.embed(blocks, script)
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

--- Whether a name is the robots' firmware's, in any case: the
--- card does not tell microbit.hex from MICROBIT.hex
--- @param name string
--- @return boolean
local function isFirmware(name)
  return name:upper() == HEX:upper()
end

--- Stop a command when it has no file to write, or would
--- write over the robots' firmware
--- @param name any the file it writes
--- @param example string the command, written with another name
local function writable(name, example)
  if type(name) ~= "string" then
    refuse("Name the file to write, such as " .. example .. ".")
  end
  if isFirmware(name) then
    refuse(
      HEX .. " is the robots' firmware and is never written",
      "to. Name another file, such as " .. example .. "."
    )
  end
end

--- Take the Lua script out of a hex file and keep it
--- @param hex_name string?
--- @param lua_name string?
function extract(hex_name, lua_name)
  local name = lua_name or LUA
  writable(name, "extract(\"MICROBIT.hex\", \"mine.lua\")")
  local from = hex_name or HEX
  local blocks = blocksOf(from)
  scriptPlace(blocks, from)
  writefile(name, hex.script(blocks))
end

--- The hex file's name for a Lua file, its ending in the
--- case it was typed in: robot.lua gives robot.hex, ROBOT.LUA
--- gives ROBOT.HEX; nil for any other file
--- @param filename string
--- @return string?
local function hexNameOf(filename)
  named(filename)
  local base, ending = filename:match("^(.*)%.([Ll][Uu][Aa])$")
  if not base then
    return nil
  end
  local upper = ending == "LUA"
  return base .. (upper and ".HEX" or ".hex")
end

--- Say that a Lua file is empty
--- @param filename string
local function empty(filename)
  local edit = "edit(%q), then upload it again."
  print(filename .. " is empty. Write your program with")
  print(edit:format(filename))
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
--- said, when it holds no program, or has a mistake that stops
--- it from being read
--- @param filename string
--- @return string?
local function scriptOf(filename)
  local script = (read(filename):gsub("\r\n?", "\n"))
  if not script:find("%S") then
    empty(filename)
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
  embedInto(blocks, filename, script)
  return hex.write(blocks)
end

--- Put a Lua script into a hex file, with upload's checks.
--- MICROBIT.hex is always the firmware read from, and never
--- the one written to: it is the one copy that has to stay as
--- it came.
--- @param hex_name string
--- @param lua_name string?
function embed(hex_name, lua_name)
  writable(hex_name, "embed(\"mine.hex\")")
  local data = build(lua_name or LUA)
  if data then
    writefile(hex_name, data)
  end
end

--- A Lua file name the project does not use yet, nor its
--- firmware file's: mine.lua, or mine2.lua, and so on
--- @return string
local function freeName()
  local name, n = "mine.lua", 1
  local function taken()
    return readfile(name, true)
         or readfile(hexNameOf(name), true)
  end
  while taken() do
    n = n + 1
    name = "mine" .. n .. ".lua"
  end
  return name
end

--- The way to put a Lua file named for the firmware on the
--- board: as a Lua file of another name, one that takes the
--- place of none, with upload's checks
--- @param filename string
local function renameWay(filename)
  local free = freeName()
  print("robots' firmware. Give your script another name:")
  print(("writefile(%q, readfile(%q))"):format(free, filename))
  print(("upload(%q)"):format(free))
end

--- Whether a Lua file's hex would overwrite the robots'
--- firmware, said when it would
--- @param filename string
--- @param hex_name string
--- @return boolean
local function overwrites(filename, hex_name)
  if isFirmware(hex_name) then
    -- a file that is not there is said first, and alone
    read(filename)
    print(filename .. " would overwrite " .. HEX .. ", the")
    renameWay(filename)
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
  if readfile(hex_name, true) == data then
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

--- What running out of memory looks like, for a Lua file the
--- board takes as its whole program. The board reads it in
--- place, from its flash, with about 90 KB of memory free,
--- and the parsed code grows with how much the file does per
--- character: a long table of different strings costs about
--- three times what a program of the same length usually
--- does. A program that runs out, as it is read or as it runs,
--- stops the board with a sad face and 020, at every start,
--- until upload() puts the Compy's firmware back. The only
--- limit on the file is the firmware's room for a script.
--- Said once the board has taken the file.
--- @param filename string the file upload was given
local function memoryNote(filename)
  if not hexNameOf(filename) then
    return
  end
  print("A sad face and 020 on the micro:bit mean your")
  print("program ran out of the board's memory; upload()")
  print("puts the Compy's firmware back.")
end

--- What the Compy tells the upload: the file it read, the
--- sending beginning, and the board taking it
--- @param name string
--- @param source string the file upload was given
--- @return table
local function uploadHooks(name, source)
  return {
    read = function(image)
      holds(name, hex.version(image))
    end,
    sending = function()
      compy.audio.hyperjump()
    end,
    took = function()
      memoryNote(source)
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
--- @param source string the file upload was given
local function uploadOverCable(name, data, source)
  local ok, err = flash_microbit(
    data,
    uploadHooks(name, source)
  )
  if not ok then
    refuse(err or "The Compy could not send " .. name .. ".")
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
--- @param source string the file upload was given
local function uploadToDrive(name, data, source)
  local version = hex.version(parsed(name, data))
  compy.audio.hyperjump()
  local ok, err = flash_microbit(data)
  if not ok then
    refuse(err or "The Compy could not copy " .. name .. ".")
  end
  print(name .. " is sent. The micro:bit's light blinks")
  print("while it writes it, then it restarts with it.")
  holds(name, version)
  memoryNote(source)
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
  local unseen = not cable and not detect_microbit()
  if unseen then
    noBoard("upload")
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
  send(name, data, filename or HEX)
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

-- A command a person types says a refusal in words
send = plainly(send)
exec = plainly(exec)
restart_microbit = plainly(restart_microbit)
hexmap = plainly(hexmap)
extract = plainly(extract)
embed = plainly(embed)
upload = plainly(upload)

echo()
help()
