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
  --- the height of every row of the screen, in pixels: the
  --- output's, the document view's, the status line's and the
  --- field's, on one grid from the top. 18 of them take 594
  --- of the screen's 600.
  row_height = 33,
  --- where the 6 pixels the rows leave go, as two numbers that
  --- add up to them: pixels added to the status line, its text
  --- centred in it, and pixels left at the screen's bottom,
  --- under the field, in its background; what the two leave
  --- lies at the top
  status_extra = 6,
  bottom_strip = 0,
}
