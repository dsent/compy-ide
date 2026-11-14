--- A surface's keys: one table per state, each chord with its
--- action, whether it repeats while held, and the words the
--- key card shows for it (PR #28, D-KEY-TABLES). A chord is
--- looked up by its full name (Key.combo): a key with other
--- modifiers is another chord, and a chord that no table of
--- the state binds does nothing.
---
--- A keymap is written as an ordered list of definitions:
---
---   { chords = { 'up', 'down' }, card = 'Up/Down',
---     repeats = true,
---     browsing = { act = 'vertical', words = 'browse' },
---     inserting = { act = 'vertical' } }
---
--- `act` names the surface's action; `words` (a string, or a
--- function of whether the draft is empty) is what the card
--- says while the state is in front. A state with no entry
--- leaves the chords unbound there. The card follows the
--- list's order: one cell per `card` label.
local Keymap = { }
Keymap.__index = Keymap

--- @param defs table[]
--- @param states string[]
--- @return table keymap
function Keymap.new(defs, states)
  local tables = { }
  for _, st in ipairs(states) do
    local t = { }
    for _, d in ipairs(defs) do
      local e = d[st]
      if e then
        for _, chord in ipairs(d.chords) do
          assert(not t[chord], st .. ': ' .. chord .. ' twice')
          t[chord] = {
            act = e.act,
            words = e.words,
            repeats = d.repeats == true,
            card = d.card,
          }
        end
      end
    end
    tables[st] = t
  end
  return setmetatable({
    defs = defs,
    states = states,
    tables = tables,
  }, Keymap)
end

--- @param state string
--- @param chord string --- Key.combo's name
--- @return table? entry --- { act, words, repeats, card }
function Keymap:lookup(state, chord)
  return self.tables[state][chord]
end

--- @param e table?
--- @param empty boolean?
--- @return string?
local function words_of(e, empty)
  local w = e and e.words
  if type(w) == 'function' then return w(empty) end
  return w
end

--- The card's rows in the list's order: { label, words, now }.
--- A label is now when the state's entry has words; else it
--- is listed with the words another state gives it, the first
--- in `states` order, after the state's own.
--- @param state string
--- @param empty boolean?
--- @return table[]
function Keymap:card_rows(state, empty)
  local rows, seen = { }, { }
  for _, d in ipairs(self.defs) do
    local label = d.card
    if label and not seen[label] then
      local w = words_of(d[state], empty)
      local now = w ~= nil
      if not now then
        for _, st in ipairs(self.states) do
          w = w or words_of(d[st], empty)
        end
      end
      if w then
        seen[label] = true
        rows[#rows + 1] = { label, w, now }
      end
    end
  end
  return rows
end

return Keymap
