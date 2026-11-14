local P = require('harmony.probe')
local D = require('harmony.drive')

--- What the editor does with a file's bytes: line endings
--- (the ruling that a file is written with LF) and a `#!`
--- first line (the ruling that it is the language layer's
--- matter).

local PROJECT = 'h-files'

--- @param name string
--- @return string?
local function stored(name)
  return P.stored(PROJECT, name)
end

-- CRLF and a lone CR each end a line on opening; opening and
-- browsing write nothing; the first submission writes the
-- whole file with LF
scenario('line-ends', function(wait)
  local f = 'crlf.lua'
  local text = 'a = 1\r\nb = 2\r\nc = 3\rd = 4\r\n'
  wait(.1)
  D.open(wait, PROJECT, f, { [f] = text })
  D.shot(wait, 'open')
  D.eq(P.blocks(), 4, 'CRLF and CR each end a line')
  D.press(wait, 'up', 3)
  D.key(wait, 'f2')
  D.eq(P.draft(), 'b = 2', 'the line holds no CR')
  D.key(wait, 'escape')
  D.press(wait, 'down', 3)
  D.eq(stored(f), text, 'opening and browsing write nothing')
  D.enter(wait, 'e = 5')
  D.eq(stored(f), 'a = 1\nb = 2\nc = 3\nd = 4\ne = 5\n',
    'the first submission writes LF throughout')
  D.leave(wait)
  hm_done()
end)

-- F2 opens a `#!` first line and Enter on it unchanged leaves
-- the file as it was; a `#!` line anywhere else is refused
-- and the draft stays; Alt+F keeps the header
scenario('header', function(wait)
  local f = 'script.lua'
  local text = '#!/usr/bin/env lua\na=1\n'
  wait(.1)
  D.open(wait, PROJECT, f, { [f] = text })
  D.press(wait, 'up', 2)
  D.eq(P.position(), 1, 'on the header')
  D.key(wait, 'f2')
  D.shot(wait, 'loaded')
  D.eq(P.state(), 'replacing', 'F2 opens the header')
  D.eq(P.draft(), '#!/usr/bin/env lua', 'the draft is the header')
  D.key(wait, 'return')
  D.eq(P.state(), 'browsing', 'Enter takes it')
  D.eq(stored(f), text, 'and the file is as it was')

  -- the position is on a=1 now: a header line before it
  D.eq(P.position(), 2, 'on a=1')
  D.type(wait, '#!/bin/sh')
  D.key(wait, 'return')
  D.shot(wait, 'refused')
  D.eq(P.draft(), '#!/bin/sh', 'the draft stays')
  assert(P.message(), 'the refusal says nothing')
  D.eq(stored(f), text, 'nothing was written')
  D.key(wait, 'escape')

  D.key(wait, 'A-f')
  D.shot(wait, 'tidied')
  D.eq(stored(f), '#!/usr/bin/env lua\na = 1\n',
    'Alt+F tidies and keeps the header')
  D.leave(wait)
  hm_done()
end)
