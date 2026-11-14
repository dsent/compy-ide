local class = require('util.class')
require('util.dequeue')
require('util.string.string')
require('util.debug')

local DEFAULT_LIMIT = 1000

--- The classic shell's history: each entry is a line that
--- ran, and walking through the entries never changes one.
--- During a walk the line being typed waits below the
--- newest entry (`line_typed`), and an edit to a shown entry
--- waits beside it (`edits`); a line run or a field cleared
--- ends the walk and forgets both.
--- @class History: Dequeue<string[]>
--- @field index integer? the entry shown; nil on the line typed
--- @field line_typed string[]? the line typed, while an entry shows
--- @field edits table<integer, string[]> entries edited in a walk
--- @field limit integer entry cap, 0 for unlimited
History = class.create()

--- @param limit integer? entry cap; 0 means unlimited
function History.new(limit)
  local self = Dequeue.typed('string[]')
  self.limit = limit or DEFAULT_LIMIT
  self.edits = {}

  setmetatable(self, {
    __index = function(t, k)
      local value = History[k] or Dequeue[k]
      return value
    end
  })
  return self
end

--- A plain copy of a field's lines, which the field goes on
--- editing in place
--- @param lines string[]?
--- @return string[]
local function copy(lines)
  local t = {}
  for i, l in ipairs(lines or { '' }) do t[i] = l end
  return t
end

--- Store a line that ran, which ends the walk; an empty one
--- is not stored
--- @param input string[]?
--- @return boolean
function History:remember(input)
  self:reset_index()
  if string.is_non_empty_string_array(input) then
    self:append(copy(input))
    self:_trim()
    return true
  end
  return false
end

--- Evict oldest entries past the limit
--- @private
function History:_trim()
  if self.limit == 0 then return end
  while #self > self.limit do
    self:pop_front()
  end
end

--- End the walk: back on the line typed, every edit forgotten
function History:reset_index()
  self.index = nil
  self.line_typed = nil
  self.edits = {}
end

--- Keep the text shown where the walk is, before it moves
--- @private
--- @param current string[]? nil: no text to keep
function History:_keep(current)
  if not current then return end
  if self.index then
    self.edits[self.index] = copy(current)
  else
    self.line_typed = copy(current)
  end
end

--- @private
--- @param i integer
--- @return string[]
function History:_shown(i)
  return copy(self.edits[i] or self[i])
end

--- One entry back: the text to show, or false at the oldest
--- @param current string[]? the field's text now
--- @return boolean
--- @return string[]?
function History:history_back(current)
  local at = self.index or #self + 1
  if at <= 1 then return false end
  self:_keep(current)
  self.index = at - 1
  return true, self:_shown(self.index)
end

--- One entry forward, past the newest to the line typed: the
--- text to show, or false on the line typed
--- @param current string[]? the field's text now
--- @return boolean
--- @return string[]?
function History:history_fwd(current)
  if not self.index then return false end
  self:_keep(current)
  local at = self.index + 1
  if self[at] then
    self.index = at
    return true, self:_shown(at)
  end
  self.index = nil
  return true, copy(self.line_typed)
end

--- @protected
--- @return integer
function History:_get_length()
  return #(self)
end

--- @protected
--- @param i integer
function History:_get_entry(i)
  return self[i]
end

--- @protected
--- @return string[][]
function History:_get_entries()
  return self:items()
end

--- For debug purposes, log content
--- @private
--- @param f function
function History:_dbgprint(f)
  local log = f or Log.debug
  local h = self:items()
  local t = table.map(h, function(t)
    return table.concat(t, '⏎')
  end)
  local i = self.index or '-'
  local l = ' [' .. self:length() .. '] '
  log(i .. l .. Debug.text_table(t, false, nil, 64))
end
