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
--- function of whether the draft is empty, nil where the key
--- is trivial then) is what the card says while the state is
--- in front. `trivial`: a key anyone
--- finds without being told (moving the cursor, paging), bound
--- and working but left off the card. A state with no entry
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

--- Whether any state binds one of `def`'s chords
--- @param def table
--- @return boolean
function Keymap:binds(def)
  for _, t in pairs(self.tables) do
    for _, chord in ipairs(def.chords) do
      if t[chord] then return true end
    end
  end
  return false
end

--- @param e table?
--- @param empty boolean?
--- @return string?
local function words_of(e, empty)
  local w = e and e.words
  if type(w) == 'function' then return w(empty) end
  return w
end

--- Whether the key acts in `state` with a meaning of its own
--- that has no words: a function of the draft gave none, or
--- the state leaves the chords to another table (`falls_to`)
--- that binds them.
--- @param d table
--- @param state string
--- @param empty boolean?
--- @param falls_to (fun(chord: string): boolean)?
--- @return boolean
local function wordless_here(d, state, empty, falls_to)
  local e = d[state]
  if e then
    return type(e.words) == 'function' and e.words(empty) == nil
  end
  if not falls_to then return false end
  for _, chord in ipairs(d.chords) do
    if falls_to(chord) then return true end
  end
  return false
end

--- The card's rows in the list's order: { label, words, now }.
--- A label is now when the state's entry has words. Else it
--- is listed with the words another state gives it, the first
--- in `states` order, after the state's own, unless the key
--- acts in this state with a meaning that has no words: then
--- it has no row, so that the card never gives a key that acts
--- here another state's meaning. `keep`, when given, says
--- which definitions the card may list; `falls_to`, which
--- chords the state leaves to another table that binds them.
--- @param state string
--- @param empty boolean?
--- @param keep (fun(def: table): boolean)?
--- @param falls_to (fun(chord: string): boolean)?
--- @return table[]
function Keymap:card_rows(state, empty, keep, falls_to)
  local rows, seen = { }, { }
  for _, d in ipairs(self.defs) do
    local label = d.card
    if label and not seen[label] and (not keep or keep(d)) then
      local w = words_of(d[state], empty)
      local now = w ~= nil
      if not now and not wordless_here(d, state, empty, falls_to)
      then
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
