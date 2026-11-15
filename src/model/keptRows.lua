--- The console's kept rows: the rows that scroll off the top of
--- its output, each as it looked when it left, the newest
--- `limit` of them (the maintainer's ruling "Console
--- scrollback, first version"). A kept row is its text, a
--- character per cell, with a style for each run of cells that
--- share one: color, back color, reversal.
---
--- Rows are numbered from the first kept since the last
--- forgetting, so that a number names the same row while newer
--- rows arrive and the oldest are dropped: `first` is the
--- oldest kept, `last` the newest, and none is kept while
--- `last < first`.
local class = require('util.class')

local DEFAULT_LIMIT = 1000

--- @class KeptStyle
--- @field color number[]
--- @field backcolor number[]
--- @field reversed boolean

--- @class KeptRow
--- @field text string --- its cells' characters, joined
--- @field runs { n: integer, style: KeptStyle }[] --- in order

--- @class KeptRows
--- @field limit integer
--- @field first integer
--- @field last integer
--- @field rows table<integer, KeptRow>
--- @field styles table<string, KeptStyle> --- each style once
KeptRows = class.create()

--- @param limit integer? --- the rows kept at most
function KeptRows.new(limit)
  return setmetatable({
    limit = limit or DEFAULT_LIMIT,
    first = 1,
    last = 0,
    rows = { },
    styles = { },
  }, KeptRows)
end

--- @param c number[]
--- @return string
local function color_key(c)
  return string.format('%g,%g,%g,%g', c[1], c[2], c[3], c[4] or 1)
end

--- One table for each style, however many cells use it
--- @param state table --- a grid cell's state
--- @return KeptStyle
function KeptRows:style(state)
  local rev = state.reversed == true
  local key = color_key(state.color) .. '/'
      .. color_key(state.backcolor) .. (rev and '/r' or '')
  local s = self.styles[key]
  if not s then
    local c, b = state.color, state.backcolor
    s = {
      color = { c[1], c[2], c[3], c[4] or 1 },
      backcolor = { b[1], b[2], b[3], b[4] or 1 },
      reversed = rev,
    }
    self.styles[key] = s
  end
  return s
end

--- Keep a row of the grid as it is now: its characters and
--- its cells' states, which the caller may change afterwards.
--- @param chars string[]
--- @param states table[]
function KeptRows:keep(chars, states)
  local runs = { }
  local run
  for x = 1, #chars do
    local s = self:style(states[x])
    if run and run.style == s then
      run.n = run.n + 1
    else
      run = { n = 1, style = s }
      runs[#runs + 1] = run
    end
  end
  self.last = self.last + 1
  self.rows[self.last] = { text = table.concat(chars), runs = runs }
  while self.last - self.first + 1 > self.limit do
    self.rows[self.first] = nil
    self.first = self.first + 1
  end
end

--- @return integer
function KeptRows:count()
  return self.last - self.first + 1
end

--- @param i integer --- a row's number
--- @return KeptRow?
function KeptRows:get(i)
  return self.rows[i]
end

--- Forget every row; numbering goes on from where it was
function KeptRows:forget()
  for i = self.first, self.last do self.rows[i] = nil end
  self.first = self.last + 1
end
