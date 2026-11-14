local P = require('harmony.probe')
local D = require('harmony.drive')

--- The system clipboard is gone from the text field (the
--- ruling of November 14): Ctrl+V, Ctrl+C and Ctrl+X change
--- neither the field nor the clipboard, in the file editor and
--- in the console. The clipboard holds text first, so that a
--- paste would show.

local PROJECT = 'h-clip'
local HELD = 'from the clipboard'

--- Ctrl+V, then a selection cut and copied; `draft` reads the
--- field
--- @param wait function
--- @param draft function
--- @param want string
--- @param where string
local function keys(wait, draft, want, where)
  D.key(wait, 'C-v')
  D.eq(draft(), want, 'Ctrl+V pastes nothing in ' .. where)
  -- Shift+Left selects, as far as the field selects at all
  D.key(wait, 'S-left')
  D.key(wait, 'S-left')
  D.key(wait, 'C-x')
  D.eq(draft(), want, 'Ctrl+X cuts nothing in ' .. where)
  D.key(wait, 'C-c')
  D.eq(love.system.getClipboardText(), HELD,
    'Ctrl+C copies nothing in ' .. where)
  D.eq(draft(), want, 'Ctrl+C leaves the field in ' .. where)
end

scenario('editor', function(wait)
  local f = 'clip.lua'
  wait(.1)
  love.system.setClipboardText(HELD)
  D.eq(love.system.getClipboardText(), HELD,
    'the clipboard holds the text')
  D.open(wait, PROJECT, f, { [f] = 'a = 1\n' })
  D.type(wait, 'b = 2')
  keys(wait, P.draft, 'b = 2', 'the editor')
  D.shot(wait, 'field')
  D.eq(P.stored(PROJECT, f), 'a = 1\n', 'nothing was written')
  D.leave(wait)
  hm_done()
end)

scenario('console', function(wait)
  wait(.1)
  love.system.setClipboardText(HELD)
  D.type(wait, 'x = 1')
  keys(wait, P.console_draft, 'x = 1', 'the console')
  D.shot(wait, 'field')
  D.key(wait, 'escape')
  hm_done()
end)
