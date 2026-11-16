--- The IDE draws its own things in its own graphics state,
--- whatever state a program left, running, paused or stopped
--- (scissor, wireframe, colour, shader, blending, stencil,
--- transform): the state is saved, reset for the drawing, and
--- given back, so the program's own is untouched. Every place
--- the IDE draws, to the screen or into a canvas of its own,
--- goes through here: View.draw (the console, its output and
--- the program's canvas over it, the status line, the band, the
--- field, the key card, the editor), a program's input field
--- (controller.lua), a field's cached render, which also runs
--- from an API call or a key, outside any draw
--- (UserInputView:render), and the frame-rate overlay
--- (View.drawFPS).
--- @param font love.Font? --- the IDE's font, set for `f`
--- @param f function
--- @param ... any
--- The push is counted while it is under way
--- (util.program_end's ide_pushes): a stop made inside it pops
--- none of it.
local End = require('util.program_end')

return function(font, f, ...)
  local gfx = love.graphics
  gfx.push('all')
  End.ide_pushes = End.ide_pushes + 1
  gfx.reset()
  if font then gfx.setFont(font) end
  local ok, err = pcall(f, ...)
  End.ide_pushes = End.ide_pushes - 1
  gfx.pop()
  if not ok then error(err, 0) end
end
