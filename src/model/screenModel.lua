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
--- @field switched boolean --- this run has shown its picture, or
--- chosen its mode
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

--- Show `m`
--- @param m ScreenMode
function ScreenModel:set(m)
  assert(valid[m], 'no such screen mode: ' .. tostring(m))
  self.mode = m
end

--- The next mode, in MODES' order and round again: the key that
--- steps through them
function ScreenModel:step()
  local at = 1
  for i, m in ipairs(ScreenModel.MODES) do
    if m == self.mode then at = i end
  end
  self:set(ScreenModel.MODES[at % #ScreenModel.MODES + 1])
end

--- From the full picture back to the console's text, whatever
--- showed before it: any key or button there (the lead's ruling
--- of November 17, 2026, after the maintainer's "if any key gets
--- us back into console, this is good enough"); F12 reaches the
--- picture through combined, and the plain console is then one
--- key away
function ScreenModel:back()
  if self.mode ~= 'picture' then return end
  self.mode = 'text'
end

--- A program or a typed line chose `m` (compy.screen.show): it
--- holds against the run's first drawing
--- @param m ScreenMode
function ScreenModel:choose(m)
  self:set(m)
  self.switched = true
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
  --- while paused the console stays, and continue() shows the
  --- picture (round c2's third finding: a serial handler draws)
  if self.paused then
    self.paused = 'picture'
    return
  end
  self:set('picture')
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
