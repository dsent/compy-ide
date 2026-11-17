local class = require('util.class')

--- What the screen shows of the console's text and the
--- program's canvas, two records kept apart: one of three
--- modes (the proposal "The Program's Canvas and the Viewing
--- Modes", built as if accepted, the maintainer's ruling of
--- November 17, 2026).
---
--- - `text`: the console's output, the status line and the
---   field; no picture.
--- - `combined`: the output drawn over the picture, the mode
---   for drawing from the console.
--- - `picture`: the canvas on the whole screen, read-only.
---
--- Every change of mode goes through here, one call for each
--- thing that happens: a run starts, it draws, a typed line
--- draws, a pause and its continue(), the end of a run.
--- @class ScreenModel
--- @field mode ScreenMode
--- @field paused ScreenMode? --- the mode a pause replaced
--- @field switched boolean --- this run has shown its picture
ScreenModel = class.create(function()
  return {
    mode = 'text',
    paused = nil,
    switched = false,
  }
end)

--- @alias ScreenMode 'text'|'combined'|'picture'

--- The modes, in the order a key steps through them
ScreenModel.MODES = { 'text', 'combined', 'picture' }

local valid = { }
for _, m in ipairs(ScreenModel.MODES) do valid[m] = true end

--- @param m any
--- @return boolean
function ScreenModel.is_mode(m)
  return valid[m] == true
end

--- @return ScreenMode
function ScreenModel:get()
  return self.mode
end

--- @param m ScreenMode
function ScreenModel:set(m)
  assert(valid[m], 'no such screen mode: ' .. tostring(m))
  self.mode = m
end

--- A run starts: its text shows, and its first drawing will
--- bring up its picture
function ScreenModel:run_starts()
  self.mode = 'text'
  self.paused = nil
  self.switched = false
end

--- A running program drew: the first time in its run, its
--- picture comes up ("When a program starts to draw, switching
--- to the canvas, as it happens now, seems appropriate").
function ScreenModel:program_drew()
  if self.switched then return end
  self.switched = true
  self.mode = 'picture'
end

--- A typed line drew: the console's text over the picture, so
--- that what was drawn is seen while typing goes on
function ScreenModel:typed_drew()
  if self.mode == 'text' then self.mode = 'combined' end
end

--- A pause shows the console; continue() brings back the mode
--- it replaced
function ScreenModel:pause()
  if self.paused == nil then self.paused = self.mode end
  self.mode = 'text'
end

function ScreenModel:resume()
  if self.paused then self.mode = self.paused end
  self.paused = nil
end

--- A run ended, by a stop, an error in its first lines or
--- reset(): the console shows, and the picture is kept on the
--- canvas for a mode that shows it
function ScreenModel:ended()
  self.mode = 'text'
  self.paused = nil
end
