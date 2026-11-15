require("util.table")

local unpack  = unpack or table.unpack

local shift_k = { "lshift", "rshift" }
local ctrl_k  = { "lctrl", "rctrl" }
local alt_k   = { "lalt", "ralt" }

-- Single source of truth for left/right modifier folding. Each
-- row is { left-key, right-key, generic-name }; combo_string
-- folds e.g. lctrl|rctrl -> "ctrl" (precedence order: ctrl,
-- alt, shift). The set is closed
-- (doc/development/decisions/input.md, D-THREE-MODS): a key
-- outside it is an ordinary trigger. This is the single source
-- shared by combo registration and dispatch.
local mod_triples = {
  { ctrl_k[1],  ctrl_k[2],  "ctrl" },
  { alt_k[1],   alt_k[2],   "alt" },
  { shift_k[1], shift_k[2], "shift" },
}

-- Generic modifier names in combo-string precedence order
-- (doc/development/decisions/input.md, D-COMBO-TABLES: ctrl <
-- alt < shift), and the l/r fold that maps held key-names onto
-- them ('lctrl' -> 'ctrl').
local mod_rank = {
  ctrl = 1, alt = 2, shift = 3,
}
local mod_order = { 'ctrl', 'alt', 'shift' }
local fold_mod = { }
for _, row in ipairs(mod_triples) do
  fold_mod[row[1]] = row[3]
  fold_mod[row[2]] = row[3]
end

--- Split a combo string into a generic-modifier set, the
--- trigger token, and how many triggers were seen. Tokens fold
--- l/r to generic names; anything that is not a modifier is a
--- trigger. The count is what lets registration refuse a combo
--- naming two of them — dispatch itself only ever splits its
--- own output.
--- @param combo string
--- @return table mods
--- @return string? trigger
--- @return integer triggers
local function split_combo(combo)
  local mods, trigger, n = { }, nil, 0
  for tok in combo:lower():gmatch('[^+]+') do
    local g = fold_mod[tok] or tok
    if mod_rank[g] then
      mods[g] = true
    else
      trigger, n = g, n + 1
    end
  end
  return mods, trigger, n
end

--- Canonicalise a combo string
--- (doc/development/decisions/input.md, D-COMBO-TABLES):
--- lower-cased, l/r folded, modifiers in fixed precedence,
--- trigger last, '+'-joined. 'Ctrl+S' -> 'ctrl+s'; bare 'S' ->
--- 's'. Matches what combo_string() (controller.lua) emits at
--- dispatch.
--- @param combo string
--- @return string
local function normalize_combo(combo)
  local mods, trigger = split_combo(combo)
  local parts = { }
  for _, name in ipairs(mod_order) do
    if mods[name] then parts[#parts + 1] = name end
  end
  if trigger then parts[#parts + 1] = trigger end
  return table.concat(parts, '+')
end

--- A combo names modifiers plus exactly ONE trigger
--- (doc/development/decisions/input.md, D-COMBO-SHAPE). Refused
--- at registration rather than silently canonicalised, because
--- the canonical form used to keep the LAST trigger and drop
--- the rest: 'ctrl+a+b' became 'ctrl+b', and 'a+b+*' became a
--- bare '*' — the widest binding there is, from a string
--- written to mean the narrowest.
---
--- A bare '*' is refused for a different reason: it satisfies
--- the one-trigger rule but is the class of "no modifiers
--- held", i.e. every unmodified key. That is what hooks[event]
--- already is, by a spelling that reads like a narrow binding.
--- @param combo string
local function check_combo(combo)
  local mods, trigger, n = split_combo(combo)
  if n == 1 then
    if trigger ~= '*' or next(mods) then return end
    error("bad combo '*': a class needs modifiers to be a"
      .. ' class of (e.g. alt+*); for every key, use'
      .. ' compy.input.hooks', 4)
  end
  local why = (n == 0) and 'names no trigger'
      or 'names more than one trigger'
  error("bad combo '" .. tostring(combo) .. "': " .. why
    .. ' (modifiers plus one trigger, e.g. ctrl+alt+s'
    .. ' or ctrl+alt+*)', 4)
end

--- A project handlers sub-table
--- (doc/development/decisions/input.md, D-COMBO-TABLES):
--- assigned combo keys normalise on registration, so
--- handlers.keypressed['Ctrl+S'] is stored (and
--- dispatch-matched) as 'ctrl+s'. The matcher uses exact
--- canonical lookup (O(1)), plus one class lookup on a miss
--- (D-COMBO-SHAPE).
--- @return table
local function new_handler_table()
  return setmetatable({ }, {
    __newindex = function(t, k, v)
      check_combo(k)
      rawset(t, normalize_combo(k), v)
    end,
  })
end

--- @param k string
--- @return boolean
local function is_enter(k)
  return k == "return" or k == 'kpenter'
end

--- Is any of the named keys held? The project-facing way to ask
--- the keyboard about a key `Key` has no accessor for — a key
--- that is not a modifier — so project code has one surface for
--- held state instead of reaching for love.keyboard beside it.
--- Multi-argument is OR, exactly like the device call it wraps.
--- Named `any_pressed` because of that OR: a future richer
--- predicate over a whole chord is a different question and
--- takes a different name.
--- @param ... string
--- @return boolean
local function any_pressed(...)
  if select('#', ...) == 0 then
    error('Key.any_pressed needs at least one key name', 2)
  end
  return love.keyboard.isDown(...)
end

--- Whether a key name is any modifier, l/r alike. A combo class
--- (D-COMBO-SHAPE) must not match its own modifier: holding Alt
--- alone dispatches 'alt+lalt', the modifier prepended to
--- itself as the trigger, which 'alt+*' would otherwise catch.
--- @param k string
--- @return boolean
local function is_mod(k)
  return fold_mod[k] ~= nil
end

--- A lock or a system key, which types nothing
local LOCKS = {
  capslock = true, numlock = true, scrolllock = true,
  lgui = true, rgui = true,
}

--- Whether a key does nothing pressed on its own: a modifier,
--- a lock or a system key. It leaves a message showing
--- (IS3.14).
--- @param k string
--- @return boolean
local function is_lone(k)
  return is_mod(k) or LOCKS[k] == true
end

--- @return boolean
local function is_shift(k)
  return table.is_member(shift_k, k)
end
--- @return boolean
local function shift()
  ---@diagnostic disable-next-line: param-type-mismatch
  return love.keyboard.isDown(unpack(shift_k))
end

--- @return boolean
local function is_ctrl(k)
  return table.is_member(ctrl_k, k)
end

--- @return boolean
local function is_alt(k)
  return table.is_member(alt_k, k)
end

--- @return string?
local function os_name()
  local sys = love.system
  return sys and sys.getOS and sys.getOS()
end

--- AltGr, the key that types a layout's third-level
--- characters, is the right Alt key on a computer, where people
--- bring their own layouts. Linux reports it as `ralt` alone;
--- Windows as left Ctrl plus right Alt. With the left Alt or
--- the right Ctrl down as well, the keys are a chord of their
--- own. A Compy (Android) has no AltGr: its right Alt key is an
--- Alt like the left one.
--- @return boolean
local function altgr()
  local name = os_name()
  if name == 'Android' then return false end
  local down = love.keyboard.isDown
  if not down('ralt') or down('lalt') or down('rctrl') then
    return false
  end
  return not down('lctrl') or name == 'Windows'
end

--- Ctrl held, either side. AltGr is no Ctrl: on Windows its
--- left Ctrl is the system's, not a key the person pressed.
--- @return boolean
local function ctrl()
  ---@diagnostic disable-next-line: param-type-mismatch
  return love.keyboard.isDown(unpack(ctrl_k)) and not altgr()
end

--- Alt held, either side. AltGr is no Alt: a key pressed
--- under it types, and makes no chord.
--- @return boolean
local function alt()
  ---@diagnostic disable-next-line: param-type-mismatch
  return love.keyboard.isDown(unpack(alt_k)) and not altgr()
end

--- Whether text that arrives now is a modifier chord's own
--- glyph and no typed text. With Ctrl or Alt held, a key makes
--- a chord; on the device its glyph is sent as text all the
--- same, before or after the key press (the Compy input
--- quirks 1 and 3). Shift alone composes text. On a computer
--- a chord sends no text, so what arrives under AltGr is what
--- the layout composes, whatever the character.
---
--- This is the one statement of the rule; the event gate
--- asks it for every text event (controller.lua,
--- handlers.textinput), so no text field has to.
--- @param _ string --- the text, which does not enter the rule
--- @return boolean
local function chord_text(_)
  return ctrl() or alt()
end

--- A key event's chord, by its canonical name: the held
--- modifiers in precedence order (ctrl, alt, shift), folded
--- to their generic names, then the key, lower-cased: 'up',
--- 'ctrl+up', 'alt+shift+f4' (doc/development/decisions/
--- input.md, D-COMBO-TABLES). A modifier asked about on its
--- own press names itself too: 'shift+lshift'.
--- @param k string --- the raw LÖVE key name
--- @return string
local function combo(k)
  local s = ''
  if ctrl() then s = 'ctrl+' end
  if alt() then s = s .. 'alt+' end
  if shift() then s = s .. 'shift+' end
  return s .. k:lower()
end

Key = {
  combo       = combo,
  mod_triples = mod_triples,
  chord_text  = chord_text,
  normalize_combo = normalize_combo,
  new_handler_table = new_handler_table,
  is_enter    = is_enter,
  any_pressed = any_pressed,
  is_mod      = is_mod,
  is_lone     = is_lone,
  shift       = shift,
  is_shift    = is_shift,
  ctrl        = ctrl,
  is_ctrl     = is_ctrl,
  alt         = alt,
  is_alt      = is_alt,
}
