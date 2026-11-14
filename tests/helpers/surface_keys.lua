-- What a surface (the file editor, the console) binds, read
-- from the key tables a key is looked up in: the surface's
-- own, the text field's, and the gate's reserved chords. For
-- the tests of exact chords and of the key card's inventory.

local FieldKeys = require("model.input.fieldKeys")
local Reserved = require("model.input.reservedKeys")

local S = { }

local MOD_KEYS = { ctrl = "lctrl", alt = "lalt", shift = "lshift" }
local ORDER = { "ctrl", "alt", "shift" }

--- The keys no card lists, each with its reason: an alias of
--- a key the card lists, a debug build's key, or a reserved
--- chord that acts only while a program runs in front or in a
--- profiling build.
S.EXEMPT = {
  kpenter = "alias of Enter",
  ["shift+kpenter"] = "alias of Shift+Enter",
  ["alt+kpenter"] = "alias of Alt+Enter",
  ["shift+backspace"] = "alias of Backspace",
  ["alt+backspace"] = "alias of Ctrl+Backspace",
  ["shift+delete"] = "alias of Ctrl+Delete",
  f5 = "debug build",
  ["ctrl+f5"] = "debug build",
  ["ctrl+alt+t"] = "debug build",
  ["ctrl+pause"] = "only while a program runs in front",
  ["ctrl+alt+p"] = "profiling build",
  ["ctrl+alt+shift+p"] = "profiling build",
  f10 = "profiling build",
}

--- Every chord the surface takes in `state`, with the
--- definition that binds it: chord -> def
--- @param keys table --- the surface's keymap
--- @param state string
--- @return table<string, table>
function S.bound(keys, state)
  local out = { }
  for _, d in ipairs(FieldKeys.defs) do
    if not d.only or keys.allows[d.only] then
      for _, c in ipairs(d.chords) do out[c] = d end
    end
  end
  for _, d in ipairs(keys.defs) do
    if d[state] then
      for _, c in ipairs(d.chords) do out[c] = d end
    end
  end
  for _, r in ipairs(Reserved) do
    out[r.chord] = r
  end
  return out
end

--- Every bound chord with one more modifier that nothing
--- binds: { name, keys for K.keys }, the help key apart
--- @param bound table<string, table>
--- @return table[]
function S.unbound_neighbours(bound)
  local out, seen = { }, { }
  for chord in pairs(bound) do
    local mods, trigger = { }, nil
    for part in chord:gmatch("[^+]+") do
      if MOD_KEYS[part] then mods[part] = true else trigger = part end
    end
    for _, m in ipairs(ORDER) do
      if not mods[m] and trigger ~= "f1" then
        local names, keys = { }, { }
        for _, o in ipairs(ORDER) do
          if mods[o] or o == m then
            names[#names + 1] = o
            keys[#keys + 1] = MOD_KEYS[o]
          end
        end
        names[#names + 1] = trigger
        keys[#keys + 1] = trigger
        local name = table.concat(names, "+")
        if not bound[name] and not seen[name] then
          seen[name] = true
          out[#out + 1] = { name, keys }
        end
      end
    end
  end
  table.sort(out, function(a, b) return a[1] < b[1] end)
  return out
end

--- The card labels the surface's keys need in `state`: each
--- bound chord's, unless EXEMPT. A chord whose definition has
--- no label is returned in `missing`.
--- @return table<string, true> labels
--- @return string[] missing
function S.inventory(keys, state)
  local labels, missing = { }, { }
  for chord, d in pairs(S.bound(keys, state)) do
    if not S.EXEMPT[chord] then
      if d.card then
        labels[d.card] = true
      else
        missing[#missing + 1] = chord
      end
    end
  end
  table.sort(missing)
  return labels, missing
end

--- The labels a card's text lines show, read from the screen
--- text: each cell of a 32-column grid that opens with a key
--- @param lines string[]
--- @param labels table<string, true> --- the labels to find
--- @return table<string, true>
function S.shown(lines, labels)
  local text = "\n" .. table.concat(lines, "\n")
  local out = { }
  for label in pairs(labels) do
    if text:find("[\n ]" .. label:gsub("%p", "%%%0") .. " ") then
      out[label] = true
    end
  end
  return out
end

return S
