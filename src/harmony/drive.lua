--- How a scenario types into the IDE: keys, chords, text and
--- screenshots, each with the wait that lets it land.
local h = love.harmony.utils or error()
local P = require('harmony.probe')

local D = {}

--- `keys`, a key or a chord such as `C-z`, with its modifiers
--- let go once it has landed: a modifier stays held until it
--- is let go, and a key or text sent while it is held is a
--- chord. An event sent now is handled at the next frame,
--- before the wait can end.
--- @param wait function
--- @param keys string
function D.key(wait, keys)
  h.love_key(keys)
  wait(.02)
  h.release_mods()
  wait(.01)
end

--- `key`, `n` times
--- @param wait function
--- @param key string
--- @param n integer
function D.press(wait, key, n)
  for _ = 1, n do D.key(wait, key) end
end

--- @param wait function
--- @param text string
function D.type(wait, text)
  h.love_text(text)
  wait(.03)
end

--- type a line and submit it with Enter
--- @param wait function
--- @param text string
function D.enter(wait, text)
  D.type(wait, text)
  D.key(wait, 'return')
  wait(.05)
end

--- a screenshot of the screen as it is now: it is taken a
--- frame later, so the next key waits for it
--- @param wait function
--- @param tag string
function D.shot(wait, tag)
  h.screenshot(tag)
  wait(.1)
end

--- @param want string --- love.state.app_state
function D.in_state(want)
  local st = love.state.app_state
  assert(st == want,
    string.format('expected %s, the IDE is %s', want, st))
end

--- `got` equals `want`, or the scenario fails saying `what`
--- @param got any
--- @param want any
--- @param what string
function D.eq(got, want, what)
  if got ~= want then
    error(string.format('%s: expected %q, got %q', what,
      tostring(want), tostring(got)), 2)
  end
end

--- hold F1 while `f` runs, then let it go
--- @param wait function
--- @param f function
function D.with_card(wait, f)
  h.hold('f1')
  wait(.1)
  f()
  h.let_go('f1')
  wait(.1)
end

--- hold `key` down for its press and `repeats` repeats, then
--- let it go
--- @param wait function
--- @param key string
--- @param repeats integer
function D.held(wait, key, repeats)
  h.hold(key)
  wait(.02)
  for _ = 1, repeats do
    h.key_repeat(key)
    wait(.02)
  end
  h.let_go(key)
  wait(.02)
end

--- a click of the left button at `x`, `y`
--- @param wait function
--- @param x number
--- @param y number
function D.click(wait, x, y)
  h.love_event('mousepressed', x, y, 1, false, 1)
  wait(.02)
  h.love_event('mousereleased', x, y, 1, false, 1)
  wait(.05)
end

--- open `project`, creating it, write `files` to it as
--- fixtures, and open `file` in the editor
--- @param wait function
--- @param project string
--- @param file string
--- @param files table<string, string>?
function D.open(wait, project, file, files)
  D.enter(wait, string.format('project(%q)', project))
  for name, text in pairs(files or {}) do
    P.put(project, name, text)
  end
  D.enter(wait, string.format('edit(%q)', file))
  D.in_state('editor')
  D.eq(P.file(), file, 'the open file')
end

--- Escape until the console is back: each press drops an
--- edit or steps back from a file
--- @param wait function
function D.leave(wait)
  for _ = 1, 6 do
    if love.state.app_state ~= 'editor' then break end
    D.key(wait, 'escape')
  end
  D.in_state('ready')
end

return D
