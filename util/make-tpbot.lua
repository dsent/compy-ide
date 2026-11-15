-- Makes the microbit project's tpbot.lua and tpbot-radio.lua again from
-- the bundled firmware, src/examples/microbit/MICROBIT.hex: its start-up
-- script, with the robot lessons' words added before the script's own
-- setup, and its version in each file's first lines. The words are the
-- block in the current tpbot.lua that starts with "-- The robot lessons'
-- words" and ends before "-- Script-level setup"; to change them, edit
-- that block in tpbot.lua and run this. Run it whenever MICROBIT.hex
-- changes, from the repository root, with Lua 5.1 or LuaJIT:
--
--   luajit util/make-tpbot.lua

local DIR = "src/examples/microbit/"
package.path = DIR .. "?.lua;" .. package.path
local hex = require("hex")

local function read(name)
  local f = assert(io.open(DIR .. name, "rb"))
  local text = assert(f:read("*a"))
  f:close()
  return text
end

-- Through a new file renamed over the old one, so that a failed write
-- leaves the old file whole
local function write(name, text)
  local path = DIR .. name
  local f = assert(io.open(path .. ".new", "wb"))
  local ok, err = f:write(text)
  if ok then
    ok, err = f:close()
  else
    f:close()
  end
  if not ok then
    os.remove(path .. ".new")
    error(name .. ": " .. tostring(err), 0)
  end
  assert(os.rename(path .. ".new", path))
end

-- Where each plain match of part in text ends, in order
local function ends(text, part)
  local found, from = { }, 1
  while true do
    local i, j = text:find(part, from, true)
    if not i then return found end
    found[#found + 1] = j
    from = i + 1
  end
end

-- Where the one plain match of part in text ends. Any other count stops
-- the tool: a marker that moved or doubled needs a person to look.
local function only(text, part, what)
  local found = ends(text, part)
  if #found ~= 1 then
    error(what .. ": " .. #found .. " found, where there must be one", 0)
  end
  return found[1]
end

local blocks = hex.parse(read("MICROBIT.hex"))
local script = hex.script(blocks)
local version = hex.version(blocks)
assert(script and version, "MICROBIT.hex has no script or no version")

local WORDS = "\n-- The robot lessons' words"
local SETUP = "\n-- Script-level setup"
local PROMPT = "\nserial_session.prompt()\n"

-- The script: one setup heading, and after it the one top-level line that
-- starts with serial_session.prompt, which is exactly the prompt's call.
-- The script up to each compiles on its own, so neither is inside a
-- string, a comment or a block.
local setup = only(script, SETUP, "setup headings in the script")
only(script, "\nserial_session.prompt", "top-level prompts in the script")
local prompt = only(script, PROMPT, "prompt lines in the script")
assert(prompt > setup, "the script's prompt comes before its setup")
assert(#ends(script, WORDS) == 0, "the script has a words heading itself")
local at = setup - #SETUP + 2
assert(loadstring(script:sub(1, at - 1)),
       "the script's setup heading is not between top-level statements")
assert(loadstring(script:sub(1, prompt)),
       "the script's prompt line is not a top-level statement")

-- The words: from their heading in tpbot.lua to the blank line before the
-- last setup heading there, which is the script's own, after the words
local tpbot = read("tpbot.lua")
local first = only(tpbot, WORDS, "words headings in tpbot.lua")
    - #WORDS + 2
local setups = ends(tpbot, SETUP)
local last = setups[#setups]
assert(last and last > first, "tpbot.lua has no setup heading after the words")
local words = tpbot:sub(first, last - #SETUP)
assert(loadstring(words), "the words block in tpbot.lua does not compile")

-- The words go after the newline before the setup, a blank line after them
local with_words = script:sub(1, at - 1) .. words .. "\n" .. script:sub(at)

local CABLE = [[
-- tpbot.lua: the micro:bit firmware for the Compy's robot lessons. It is
-- the start-up script of the firmware the Compy ships (%s), prompt
-- and radio link included, with the lessons' words added near its end:
-- robot_info(), robot_move(left, right, seconds), turn(hours) and
-- straight(steps). upload("tpbot.lua") puts it on the board, which then
-- runs it at every start. It belongs to that firmware: when the Compy
-- ships another, this file is made again from that firmware's script.

]]
local RADIO = [[
-- tpbot-radio.lua: the micro:bit firmware for a robot the Compy's robot
-- lessons drive by radio. It is tpbot.lua, the start-up script of the
-- firmware the Compy ships (%s) with the lessons' words, and at
-- every start it waits for a call: listen() without a name, so a board
-- that calls it with connect("<this board's name>") gets it again after
-- the robot lost power. upload("tpbot-radio.lua") puts it on the board;
-- upload("tpbot.lua") gives it the prompt on the cable back. It belongs
-- to that firmware: when the Compy ships another, this file is made again.

]]
local LISTEN = [[

-- The script's loading garbage goes first: a program at boot that starts
-- without a full collection can run out of memory within seconds
collectgarbage("collect")
listen()
]]

-- The radio robot listens right after the prompt
local p = only(with_words, PROMPT, "prompt lines in the script with words")
local cable = CABLE:format(version) .. with_words
local radio = RADIO:format(version) .. with_words:sub(1, p) .. LISTEN
    .. with_words:sub(p + 1)
assert(loadstring(cable) and loadstring(radio), "a made file does not compile")

write("tpbot.lua", cable)
write("tpbot-radio.lua", radio)
print("tpbot.lua and tpbot-radio.lua made for firmware " .. version)
