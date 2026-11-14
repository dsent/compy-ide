local class = require('util.class')
require("util.key")

-- The project route: owner of the input handlers while a
-- project run owns the screen — a sibling to ConsoleController
-- / EditorController. The route is DUMB: it navigates every
-- event, keyboard and pointer alike, through THREE consumers in
-- order, stopping at the first that returns truthy
-- (doc/development/decisions/input.md, D-CHAIN-OF-3):  1.
-- compy.input.shortcuts[event][combo]  project shortcut combos
-- (doc/development/decisions/input.md, D-COMBO-TABLES:
-- per-event sub-tables, normalising) 2.
-- compy.input.hooks[event]             one hook per event
-- (doc/development/decisions/input.md, D-HOOKS-SEEDED): the
-- single source of truth, seeded once at activate() with the
-- project's captured love.* handler where unset; a nil clears
-- with no resurrection 3. the widget
-- terminal; consumes whenever it is shown (its own internal
-- flag), skipped when hidden. Enter/Escape/submit/cancel are
-- the WIDGET's own business (userInputController), signalled
-- via callbacks — never a routing concern.  Truthy at a
-- consumer stops the walk; falsey falls through. The widget's
-- participation derives from its shownness, not a return
-- value (doc/development/decisions/input.md, D-CHAIN-OF-3;
-- outcomes travel by callback, D-EDIT-CALLBACKS). Routing
-- contract: doc/development/internals/user_input.md

-- Every channel the chain dispatches on, in ONE list. The
-- derived clicks belong in it: where an event comes from (LÖVE,
-- or the framework's click timer) is not how a project binds
-- it, and the seeder has to see the same channels the
-- dispatcher installs.
local EVENTS = {
  'keypressed', 'keyreleased', 'textinput',
  'mousepressed', 'mousereleased', 'mousemoved', 'wheelmoved',
  'touchpressed', 'touchreleased', 'touchmoved',
  'singleclick', 'doubleclick',
}

-- What a channel names as its combo trigger, read off LÖVE's
-- own arguments. Keyboard and text name their first; the two
-- button channels name their third, serialised as 'mouseN' so a
-- combo reads the same way whatever the trigger is — 'ctrl+s'
-- and 'ctrl+mouse2' are one vocabulary, not two. A channel
-- absent here has no discrete trigger to name and matches on
-- held modifiers alone ('ctrl+*').
local TRIGGER = {
  keypressed    = function(k) return k end,
  keyreleased   = function(k) return k end,
  textinput     = function(t) return t end,
  mousepressed  = function(_, _, b) return 'mouse' .. b end,
  mousereleased = function(_, _, b) return 'mouse' .. b end,
}

--- A project's own `love.keypressed` was written under LÖVE's
--- convention, where assigning a channel means owning it and
--- there is nothing to propagate to — so its return value
--- says nothing about consumption and must not decide it.
--- Seeded handlers therefore consume unconditionally; a hook
--- the project wrote into `compy.input.hooks` keeps the
--- chain's truthy convention, its author being presumed to
--- know it (doc/development/decisions/input.md,
--- D-HOOKS-SEEDED, "A seeded handler consumes" — the named
--- exception to D-CHAIN-OF-3). Nil in, nil out: an unset
--- channel stays unset, which is information a project reads
--- (D-NO-LOG-NOISE).
--- @param handler function?
--- @return function?
local function consuming(handler)
  if not handler then return nil end
  return function(...)
    handler(...)
    return true
  end
end

--- Seed the project's hooks table
--- (doc/development/decisions/input.md, D-HOOKS-SEEDED): each
--- event with no explicit project hook gets the project's own
--- love.* handler, once, at activation. After this the hooks
--- table is the single source of truth — a nil'd hook clears,
--- with no resurrection. Runs after the project's top-level
--- code, so an explicit hooks[event] set there is already
--- present and correctly preserved.
--- @param hooks table  compy_input.hooks
--- @param handlers table  { event -> fn? }
local function seed_hooks(hooks, handlers)
  for _, event in ipairs(EVENTS) do
    if hooks[event] == nil then
      hooks[event] = consuming(handlers[event])
    end
  end
end

local function new()
  return { compy_input = nil }
end

--- @class ProjectInputController
--- @field compy_input table?
ProjectInputController = class.create(new)

-- Published: the console provisions one shortcut table per
-- channel and teardown wipes them, so both need the list this
-- file dispatches on rather than a copy of it.
ProjectInputController.EVENTS = EVENTS

--- Exact combo first, then the modifier class
--- (doc/development/decisions/input.md, D-COMBO-SHAPE): 'alt+*'
--- is every Alt chord. The class key needs no parsing — it is
--- the same serialisation with '*' as the trigger. A modifier's
--- own press names no shortcut at all: no combo with a modifier
--- as its trigger is registrable (check_combo folds every
--- token, finds no trigger and raises), so the guard comes
--- first and neither lookup is built.
---
--- A channel with no trigger to name (mousemoved, wheel, touch,
--- the derived clicks) can only have the class key: 'ctrl+*' is
--- a ctrl-drag. With no modifier held there is nothing to name
--- and the event belongs to the hook — which is why the
--- held-modifier test comes first, so an unmodified mousemoved
--- never allocates a combo string.
--- @param tbl table   one channel's combo table
--- @param trigger string?
--- @return function?
local function find_shortcut(tbl, trigger)
  if not tbl then return end
  if not trigger then
    if not Controller.any_mod() then return end
    return tbl[Controller.combo_string('*')]
  end
  if Key.is_mod(trigger) then return end
  local sc = tbl[Controller.combo_string(trigger)]
  if sc then return sc end
  return tbl[Controller.combo_string('*')]
end

--- The three-consumer walk: shortcuts[event][combo] →
--- hooks[event] → widget, stopping at the first that consumes.
--- A shortcut or hook consumes by returning truthy; the widget
--- consumes whenever it is shown (its own internal flag), and
--- is skipped when hidden — so the walk reports consumed iff a
--- consumer fired or the widget was shown. A free function over
--- plain tables + a widget reference, so any adopter (not only
--- the project widget) can reuse it over its own instance. The
--- nil guards are deliberate (D-NO-LOG-NOISE): whether a hook
--- is set is information a project reads, so an unset one stays
--- nil rather than defaulting to a callable noop. Nothing is
--- logged when an event is consumed by nobody either — that
--- would be a line per ordinary keystroke at this tier.
--- @param shortcuts table   per-event combo tables
--- @param hooks table       per-event hook fns
--- @param widget table      responds to widget[event](...)
---                          + is_shown()
--- @param event string
--- @param trigger string
--- @return boolean consumed
local function dispatch(shortcuts, hooks, widget, event, trigger, ...)
  local sc = find_shortcut(shortcuts[event], trigger)
  if sc and sc(...) then return true end
  local hk = hooks[event]
  if hk and hk(...) then return true end
  if widget and widget:is_shown() then
    widget[event](widget, ...)
    return true
  end
  return false
end

--- Whether the walk has a consumer for an event now: a
--- shortcut for its combo, a hook, or the shown widget. One
--- that is there is offered the event before the console,
--- whatever it answers (Controller.key_owner).
--- @param event string
--- @param trigger string?
--- @return boolean
function ProjectInputController:takes(event, trigger)
  local input = self.compy_input
  if not input then return false end
  local widget = love.state.user_input_controller
  return find_shortcut(input.shortcuts[event], trigger) ~= nil
      or input.hooks[event] ~= nil
      or widget ~= nil and widget:is_shown()
end

--- Run the chain for one event. `trigger` is the combo token
--- (the key, or the text); the varargs are the channel payload.
--- @param event string
--- @param trigger string
--- @return boolean consumed
function ProjectInputController:_dispatch(event, trigger, ...)
  return dispatch(
    self.compy_input.shortcuts, self.compy_input.hooks,
    love.state.user_input_controller, event, trigger, ...)
end

--- A modifier chord's own glyph (Key.chord_text) is offered to
--- the tiers above the text field and to nothing below them.
--- The project's shortcuts and hook are promised every text
--- event with its modifiers (`shortcuts.textinput['ctrl+j']`,
--- `'alt+*'`), so they still get it; the widget is a text
--- field, and a chord's glyph is no text.
--- @param t string
--- @return boolean consumed
function ProjectInputController:chord_text(t)
  if not self.compy_input then return false end
  return dispatch(self.compy_input.shortcuts,
    self.compy_input.hooks, nil, 'textinput', t, t)
end

--- Take the keyboard route for a project run. `handlers` holds
--- the project's own error-wrapped love.* keyboard handlers
--- (from the caller); they seed the hooks table once here
--- (seed_hooks; doc/development/decisions/input.md,
--- D-HOOKS-SEEDED) — only where the project set no explicit
--- hook. After seeding, hooks is read directly on each event;
--- there is no separate handlers store.
--- @param handlers table?
--- @param compy_input table
function ProjectInputController:activate(handlers, compy_input)
  self.compy_input = compy_input
  seed_hooks(compy_input.hooks, handlers or {})
end

--- Forget the project's handlers
--- (doc/development/decisions/input.md, D-ROUTE-LIFETIME).
--- Nulling compy_input does not itself disconnect anything: the
--- caller (controller.lua release_keyboard_route /
--- set_default_handlers) re-points the love.* handlers at the
--- console, after which _dispatch is unreachable. Dropping the
--- reference here lets the stopped project's handlers be
--- collected and guarantees the next activate() starts from a
--- clean state instead of a stale project's callbacks.
function ProjectInputController:deactivate()
  self.compy_input = nil
end

-- One installer for every channel. All that varies is how the
-- combo trigger is read off the arguments — and for the
-- channels with none, that there is nothing to read.
--- @param event string
local function channel(event)
  local trigger_of = TRIGGER[event]
  ProjectInputController[event] = function(self, ...)
    local trigger = trigger_of and trigger_of(...) or nil
    return self:_dispatch(event, trigger, ...)
  end
end

for _, event in ipairs(EVENTS) do channel(event) end
