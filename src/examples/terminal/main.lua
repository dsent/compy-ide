-- terminal — a serial terminal for the micro:bit.
--
-- What the board says appears above, what you type below
-- goes to it. The board runs the Lua REPL firmware: it ends
-- its lines with CR and echoes every character it receives,
-- so what you see above is its echo followed by its answer.
--
-- Whatever is typed is sent as is; the field does not check
-- it, because what is valid is up to the board.

local serial = compy.serial
local input = compy.input

local PROMPT = "Lua> "
local SETTLE_S = 0.2
local RECALL = 100

-- The board ends a line with CR, and an echoed one with
-- CR CR LF. Whatever the mix, it means one new line.
--- @param chunk string
--- @return string
local function asLines(chunk)
  return (chunk:gsub("\r+\n", "\n"):gsub("\r", "\n"))
end

--- The board sends a few stray bytes on connect, and the
--- terminal takes UTF-8 only: utf8.codes raises on anything
--- else. Drop the offending byte and look again, the way the
--- input model sanitises what it is given.
--- @param chunk string
--- @return string
local function asText(chunk)
  local text = chunk
  local ok, bad = utf8.len(text)
  while not ok do
    text = text:sub(1, bad - 1) .. text:sub(bad + 1)
    ok, bad = utf8.len(text)
  end
  return text
end

-- A prompt arrives without a line ending and so does the
-- start of a long answer. Whole lines go out as they come;
-- what is left over waits a moment, in case the rest of the
-- line is still on its way, and then goes out too — through
-- io.write, which leaves the line open for it.
local tail = ""
local settle = 0

function serial.onBytes(chunk)
  tail = tail .. asText(asLines(chunk))
  while true do
    local line, rest = tail:match("^([^\n]*)\n(.*)$")
    if not line then
      break
    end
    print(line)
    tail = rest
  end
  settle = SETTLE_S
end

function love.update(dt)
  if tail == "" then
    return
  end
  settle = settle - dt
  if settle <= 0 then
    io.write(tail)
    tail = ""
  end
end

function serial.onConnect(info)
  print("[connected " .. tostring(info and info.name) .. "]")
end

function serial.onDisconnect()
  print("[disconnected]")
end

if serial.isConnected() then
  print("[board already connected]")
else
  print("[plug the micro:bit in]")
end
print("[Ctrl+R restarts the micro:bit]")

-- What to do when the board does not come back by itself
local BUTTON = "press its reset button, on the back next to" ..
    " the USB socket"

--- Whether a file is on its way to the board now; an older
--- Compy, without isFlashing, sends none down the cable
--- @return boolean
local function onItsWay()
  return serial.isFlashing ~= nil and serial.isFlashing()
end

-- The way back from a board that no longer reads what is
-- typed, stuck in a loop or in listen(): it restarts, as its
-- reset button makes it, and greets you again.
--- @return string what to tell
local function restartBoard()
  if not serial.isConnected() then
    return "[plug the micro:bit in]"
  end
  if onItsWay() then
    return "[a file is on its way to the micro:bit: wait until"
        .. " the Compy says how it went]"
  end
  if serial.reset() then
    return "[restarting the micro:bit: if it does not greet" ..
        " you within a minute, " .. BUTTON .. "]"
  end
  return "[the micro:bit did not restart: " .. BUTTON .. "]"
end

compy.input.shortcuts.keypressed["ctrl+r"] = function()
  tail = ""
  print(restartBoard())
  return true
end

-- On the Compy a Ctrl chord can also bring its letter as
-- text; this "r" is not meant for the board.
compy.input.shortcuts.textinput["ctrl+r"] = function()
  return true
end

-- What has been sent, newest last, the hundred most recent
-- of them. The widget keeps a history of its own but hands
-- it to nobody, so the walk through this one is ours: at is
-- where the walk has got to, and past the end is where it
-- rests, on the line being typed.
local sent = { }
local at = 1

--- @param text string
local function remember(text)
  local skip = text == "" or text == sent[#sent]
  if skip then
    return
  end
  sent[#sent + 1] = text
  if RECALL < #sent then
    table.remove(sent, 1)
  end
end

-- One step through what was sent; off the near end is the
-- oldest, off the far end is an empty line to type on.
--- @param step integer
local function recall(step)
  at = at + step
  if at < 1 then
    at = 1
  end
  if #sent + 1 < at then
    at = #sent + 1
  end
  input.set_text(sent[at] or "")
end

-- What was typed, the way the REPL reads it: CR ends a line.
-- The prompt above was written with the line left open and
-- the typed text has just landed on it, so close it: what
-- the board says next starts on a line of its own.
--- @param text string
local function sendLine(text)
  remember(text)
  at = #sent + 1
  io.write("\n")
  local cr = text:gsub("\n", "\r")
  local ok, err = serial.send(cr .. "\r")
  if not ok then
    print("[send failed: " .. tostring(err) .. "]")
  end
end

input.callbacks.after_submit = input.clear

-- The caret trying to leave the field is how the widget says
-- that an earlier line was asked for.
function input.callbacks.on_limit_reached(dir)
  if dir == "up" then
    recall(-1)
  end
  if dir == "down" then
    recall(1)
  end
end

input.show({
  prompt = PROMPT,
  highlighter = LuaHighlighter,
  on_text_entered = sendLine
})
