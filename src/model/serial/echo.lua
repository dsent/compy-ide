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
end

--- What is held back goes, shown or not: the board has
--- restarted and what comes next begins a line of its own
function Echo:clear()
  self.held = ""
  self.settle = 0
end

function Echo:off()
  self.held = ""
  self.showing = false
end

--- @return boolean
function Echo:isOn()
  return self.showing
end

--- @param chunk string
function Echo:bytes(chunk)
  self.held = self.held .. as_text(as_lines(chunk))
  while true do
    local line, rest = self.held:match("^([^\n]*)\n(.*)$")
    if not line then break end
    self.say(line)
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
  self.write(self.held)
  self.held = ""
end
