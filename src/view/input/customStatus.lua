local class = require('util.class')

--- @class CustomStatus table
--- @field name string
--- @field spans_lines boolean? --- the file's blocks may span
--- lines (its syntax's `spans_lines`): the block is named
--- @field buflen integer
--- @field selection integer
--- @field range Range?
--- @field state EditorStateName? --- the file editor's state
--- @field arrow string? --- while replacing, '↑' or '↓' toward the target out of view
--- @field project string? --- the open project's name
CustomStatus = class.create(
  function(name, spans, len, sel, range)
    return {
      name = name,
      spans_lines = spans,
      buflen = len,
      selection = sel,
      range = range,
    }
  end)

function CustomStatus:__tostring()
  if self.range then
    return 'B' .. self.range
  else
    return 'L' .. self.selection
  end
end
