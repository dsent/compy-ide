local P = require('harmony.probe')
local D = require('harmony.drive')

--- Checks of behaviour found wrong, kept apart so that the
--- rest of the run has passed by the time one fails: the file
--- runs last, by its name.

-- Ctrl+Backspace, Alt+Backspace and Ctrl+W remove exactly
-- what Ctrl+Left moves over (IS3.8, the ruling on word
-- deletion): the characters before the cursor that are no
-- word characters, then the word. At the start of a line they
-- remove the line break alone and join the lines.
scenario('word-delete', function(wait)
  wait(.1)
  D.key(wait, 'escape')
  local cases = {
    { 'q = 9', 'q = ' },
    { 'f(x)', 'f(' },
    { 'a.b', 'a.' },
  }
  for _, k in ipairs({ 'C-backspace', 'A-backspace', 'C-w' }) do
    for _, c in ipairs(cases) do
      D.type(wait, c[1])
      D.key(wait, k)
      D.shot(wait, k .. '-' .. c[1]:gsub('%W', '_'))
      D.eq(P.console_draft(), c[2], k .. ' after ' .. c[1])
      D.key(wait, 'escape')
    end
    D.type(wait, 'ab')
    D.key(wait, 'S-return')
    D.type(wait, 'cd')
    D.key(wait, 'home')
    D.key(wait, k)
    D.eq(P.console_draft(), 'abcd', k .. ' at a line\'s start')
    D.key(wait, 'escape')
  end
  hm_done()
end)
