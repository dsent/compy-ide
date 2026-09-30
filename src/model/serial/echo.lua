--- Showing what the board says, in the console.
---
--- A board answers a character at a time, so a chunk that
--- arrives is rarely a whole line. Printing each chunk as it
--- lands spells the answer out letter by letter; whole lines
--- printed at once read the way an answer should.
---
--- What is left over — a prompt, the head of a long answer
--- has no terminator to wait for, and a stream carries no
--- sign that it has ended. So it goes out once the board has
--- been quiet for a moment, through io.write, which leaves
--- the line open for the rest of it.
---
--- A board also greets a fresh connection with a few stray
--- bytes. The terminal takes UTF-8 only and raises on
--- anything else (technical_debt, io.write is not defended),
--- so what is not text is dropped here.

local utf8 = require("utf8")

--- A file the micro:bit example's exec sent that runs on past
--- exec's wait ends while echo shows the board. exec gives
--- echo the frame the board is to say its end in (expect), a
--- line of its own with a mark new to that exec, and echo says
--- how the file ended in its place. The line break the board
--- puts before the frame is dropped when it leaves an empty
--- line, and a tail that may yet be the frame is held until
--- the line shows it is not.
local ENDED = {
  ok = "The program on the micro:bit has ended.",
  error = "The program on the micro:bit stopped on the"
      .. " mistake above.",
}

--- How long the board must be quiet before an unterminated
--- tail is shown anyway
local SETTLE_S = 0.2

--- @class Echo
--- @field new function
--- @field on function
--- @field off function
--- @field isOn function
--- @field clear function
--- @field bytes function
--- @field tick function
Echo = {}
Echo.__index = Echo

--- @param write function takes a string, ends no line
--- @param say function takes a string, ends the line
--- @return Echo
function Echo.new(write, say)
  local self = setmetatable({}, Echo)
  self.write = write
  self.say = say
  self.held = ""
  self.settle = 0
  self.showing = false
  return self
end

--- The board ends a line with CR, and an echoed one with
--- CR CR LF. Whatever the mix, it means one new line.
--- @param chunk string
--- @return string
local function as_lines(chunk)
  return (chunk:gsub("\r+\n", "\n"):gsub("\r", "\n"))
end

--- Drop what is not UTF-8, the way the input model sanitises
--- what it is handed
--- @param chunk string
--- @return string
local function as_text(chunk)
  local text = chunk
  local ok, bad = utf8.len(text)
  while not ok do
    text = text:sub(1, bad - 1) .. text:sub(bad + 1)
    ok, bad = utf8.len(text)
  end
  return text
end

function Echo:on()
  self.held = ""
  self.settle = 0
  self.showing = true
  self.frame = nil
  self.blank = false
  self.open = false
  self.cr = false
end

--- The frame the board is to say a file's end in, once
--- @param frame string
function Echo:expect(frame)
  self.frame = frame
end

--- What is held back goes, shown or not: the board has
--- restarted and what comes next begins a line of its own
function Echo:clear()
  self.held = ""
  self.settle = 0
  self.frame = nil
  self.blank = false
  self.open = false
  self.cr = false
end

function Echo:off()
  self.held = ""
  self.showing = false
  self.frame = nil
  self.blank = false
  self.open = false
  self.cr = false
end

--- Whether what is held may yet be the line the file's end is
--- said in: the frame, then ok or error, however little of it
--- has come
--- @param held string
--- @return boolean
function Echo:mayBeEnd(held)
  local frame = self.frame
  if not frame then return false end
  for status in pairs(ENDED) do
    local whole = frame .. status
    if whole:sub(1, #held) == held then return true end
  end
  return false
end

--- How a whole line says the file ended, when it is the frame
--- @param line string
--- @return string? words
function Echo:ended(line)
  local frame = self.frame
  if not frame or line:sub(1, #frame) ~= frame then return nil end
  return ENDED[line:sub(#frame + 1)]
end

--- One whole line from the board
--- @param line string
function Echo:line(line)
  -- a line the tail left open ends here, the frame's own
  -- line break or not
  local open = self.open
  self.open = false
  local ended = self:ended(line)
  if ended then
    self.frame, self.blank = nil, false
    self.say(ended)
    return
  end
  if self.blank then
    self.blank = false
    self.say("")
  end
  if line == "" and self.frame and not open then
    self.blank = true
    return
  end
  self.say(line)
end

--- @return boolean
function Echo:isOn()
  return self.showing
end

--- @param chunk string
function Echo:bytes(chunk)
  -- a CR LF cut between two chunks ends one line: the CR
  -- ended it already
  if self.cr and chunk:sub(1, 1) == "\n" then
    chunk = chunk:sub(2)
  end
  self.cr = chunk:sub(-1) == "\r"
  self.held = self.held .. as_text(as_lines(chunk))
  while true do
    local line, rest = self.held:match("^([^\n]*)\n(.*)$")
    if not line then break end
    self:line(line)
    self.held = rest
  end
  self.settle = SETTLE_S
end

--- Call once per frame
--- @param dt number
function Echo:tick(dt)
  if self.held == "" then return end
  self.settle = self.settle - dt
  if self.settle > 0 then return end
  if self:mayBeEnd(self.held) then return end
  if self.blank then
    self.blank = false
    self.say("")
  end
  self.write(self.held)
  self.held = ""
  self.open = true
end
