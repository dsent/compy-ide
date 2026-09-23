--- The Compy's own screen, as the editor lays it out. The
--- editor follows the window it runs in; tools that format or
--- check code away from a Compy use these numbers, so a file
--- comes out the same everywhere.

--- the window conf.lua opens on a Compy, in pixels
local width = 1024

--- one character of the editor font at its default size
--- (util/fonts.lua: 32.4 pixels), as LÖVE measures it
local char_width = 16

return {
  --- characters on a line of the editor
  columns = width / char_width,
  --- lines the input shows: the most one block may have
  input_lines = 14,
}
