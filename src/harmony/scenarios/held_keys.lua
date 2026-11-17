local P = require('harmony.probe')
local D = require('harmony.drive')

--- Held keys (the maintainer's ruling of November 16, 2026):
--- a key held down is its press followed by repeat events, as
--- LÖVE sends them (the key, its scancode, isrepeat true). A
--- held key repeats to its natural stop; the editor's Escape,
--- the console's Enter and a program field's Enter act once per
--- press. In the editor, the console and a program's input
--- field.

local PROJECT = 'h-held'
local ABC = 'a = 1\nb = 2\nc = 3\n'

--- a program whose input field counts its submissions; the
--- text stays in the field, so that a second submission would
--- carry it too
local COUNTS = [[
submitted = 0
compy.input.show{
  prompt = 'say:',
  clear_on_submit = false,
  on_text_entered = function(text)
    submitted = submitted + 1
    last = text
  end,
}
]]

--- @param name string
--- @return string?
local function stored(name)
  return P.stored(PROJECT, name)
end

scenario('editor', function(wait)
  local f = 'held.lua'
  wait(.1)
  D.open(wait, PROJECT, f, { [f] = ABC })
  -- a held Enter submits the draft, and each repeat adds an
  -- empty line after it, as Luditor's
  D.type(wait, 'd = 4')
  D.held(wait, 'return', 2)
  D.shot(wait, 'enter')
  local held_text = ABC .. 'd = 4\n\n\n'
  D.eq(stored(f), held_text, 'a held Enter submits, then adds lines')
  -- with no draft, a held Enter adds an empty line per event
  D.held(wait, 'return', 1)
  held_text = held_text .. '\n\n'
  D.eq(stored(f), held_text, 'an empty line per event')

  -- a held Escape drops the edit and stays in the file
  D.type(wait, 'x = 0')
  D.held(wait, 'escape', 4)
  D.in_state('editor')
  D.eq(P.file(), f, 'a held Escape stays in the file')
  D.eq(P.draft(), '', 'and drops the draft')

  -- a held Down browses on; from the first block, three
  -- steps
  D.press(wait, 'pageup', 1)
  D.eq(P.position(), 1, 'on the first block')
  D.held(wait, 'down', 2)
  D.eq(P.position(), 4, 'a held Down browses on')

  -- a held Backspace stops at the start of the draft
  D.type(wait, 'abc')
  D.held(wait, 'backspace', 6)
  D.eq(P.draft(), '', 'the draft is emptied')
  D.eq(P.state(), 'browsing', 'browsing with no draft')
  D.eq(P.position(), 4, 'the position stays')
  D.eq(P.file(), f, 'the file stays open')
  D.eq(stored(f), held_text, 'nothing was written')
  D.leave(wait)
  hm_done()
end)

scenario('console', function(wait)
  wait(.1)
  local function count()
    local _, n = string.gsub(P.console_text(), 'held once', '')
    return n
  end
  local before = count()
  D.type(wait, 'print("held " .. "once")')
  D.held(wait, 'return', 4)
  D.eq(count(), before + 1, 'a held Enter runs the line once')
  D.eq(P.console_draft(), '', 'the field is empty')
  -- an unfinished line takes one line break, not one a repeat
  D.type(wait, 'if true then')
  D.held(wait, 'return', 4)
  D.eq(P.console_draft(), 'if true then\n',
    'a held Enter breaks an unfinished line once')
  D.key(wait, 'escape')
  hm_done()
end)

scenario('program', function(wait)
  wait(.1)
  D.enter(wait, string.format('project(%q)', PROJECT))
  P.put(PROJECT, 'main.lua', COUNTS)
  D.enter(wait, 'run_project()')
  wait(.2)
  local env = P.cc():get_project_env()
  D.eq(env.submitted, 0, 'the program is waiting for input')
  D.type(wait, 'hello')
  D.held(wait, 'return', 4)
  D.shot(wait, 'submitted')
  D.eq(env.last, 'hello', 'the program got the text')
  D.eq(env.submitted, 1, 'a held Enter submits the field once')
  D.key(wait, 'C-q')
  D.in_state('ready')
  hm_done()
end)
