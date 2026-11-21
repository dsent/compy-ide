local class = require('util.class')

--- @class CustomStatus table
--- @field name string
--- @field line integer --- file line of the browsing position or draft cursor
--- @field total integer --- the file's line count
--- @field end_position boolean? --- the position is the end
--- position, past the last line
--- @field state EditorStateName? --- the file editor's state
--- @field arrow string? --- while replacing, '↑' or '↓' toward the target out of view
--- @field project string? --- the open project's name
CustomStatus = class.create(
  function(name, line, total)
    return {
      name = name,
      line = line,
      total = total,
    }
  end)

function CustomStatus:__tostring()
  return 'L' .. self.line .. '/' .. self.total
end
