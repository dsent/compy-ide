local class = require('util.class')

--- @class CustomStatus table
--- @field name string
--- @field content_type ContentType
--- @field buflen integer
--- @field selection integer
--- @field range Range?
--- @field state EditorStateName? --- the file editor's state
--- @field project string? --- the open project's name
CustomStatus = class.create(
  function(name, ct, len, sel, range)
    return {
      name = name,
      content_type = ct,
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
