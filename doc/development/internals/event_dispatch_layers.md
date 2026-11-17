---
description: The two-layer love.handlers.* vs love.<event> wiring, and what becomes of a project-defined love.*
status: active
audience: developer
authored: llm
reviewed: none
---

# Event Dispatch Layers — `love.handlers.*` vs `love.<event>`

Compy mirrors stock LÖVE's own two-layer event dispatch, and the mirroring is deliberate, not
incidental. Stock LÖVE's `love.run` pumps OS events into a dispatch table `love.handlers[name]`;
the default entry LÖVE itself installs there simply forwards to the user-facing callback
`love[name]` (`love.handlers.keypressed` calls `love.keypressed`). Compy reproduces that same
split on purpose — see the comment at `src/controller/controller.lua:974-982`.

This doc exists because the two layers are easy to conflate from the code alone — both are
LÖVE's own "handlers", one the pump table and one its per-event occupant, and `controller.lua`
uses the word for both within a few hundred lines. Read this before trying to reverse-engineer
the wiring cold. For the *why* of the routing this wiring carries (route-centric dispatch, the
default/restore route, etc.), see [`../decisions/input.md`](../decisions/input.md), in particular
its ["Vocabulary — hook, callback, handler"](../decisions/input.md#vocabulary--hook-callback-handler)
section; this doc's closing section covers what becomes of a project's own `love.*`.

---

## Layer 1 — `love.handlers.*`, the raw event-pump table

Installed once by `Controller.setup_callback_handlers(CC)` (`src/controller/controller.lua:864`).
The function body grabs the table LÖVE itself exposes — `local handlers = love.handlers`
(`controller.lua:873`) — and assigns each event onto it, e.g.
`handlers.keypressed = function(k, sc, isr) ... end` (`controller.lua:876`).

Each raw handler does exactly two jobs, in order:

1. **Route-independent framework concerns** that must run no matter which route is currently
   active: the global power hotkeys — Ctrl+T quickswitch (`controller.lua:879-900`), Ctrl+R
   restart (`:928-932`), Ctrl+Alt+P / F10 profiler toggle (`:933-955`), Ctrl+Esc quit (on the
   *release* side, `handlers.keyreleased`, `:997-998`), and on that side the end of a press the
   console or the file editor recorded, which ends the key card (`CC:key_released`). The raw
   handler keeps only these: it
   holds no state of its own, and whatever needs to know which modifiers are down asks the
   keyboard (`../decisions/input.md`, D-ASK-THE-DEVICE).
2. **Forward to the active route.** Once the framework-level concerns have run, the raw handler
   defers unconditionally to whatever route currently owns the corresponding `love.<event>`:
   `if love.keypressed then return love.keypressed(k, sc, isr) end` (`controller.lua:983-985`).

`setup_callback_handlers` is called **exactly once, at boot** (`src/main.lua:389`) and never
re-invoked or swapped afterward — the fixed, permanent event pump for the process's lifetime.
Tests reproduce this startup wiring directly: `tests/helpers/input_session.lua`.

---

## Layer 2 — `love.<event>`, the active route's handler

This is the layer that actually changes as the app moves between console, editor, and a running
project. Each `Controller.set_love_<event>(CC[, CV])` installer assigns the corresponding
`love.<event>` directly — e.g. `Controller.set_love_keypressed(CC)` (`controller.lua:448`) ends
with `love.keypressed = keypressed` (`controller.lua:491`), where the local `keypressed` closure
is the console/editor route's default handler for that event.

`Controller.set_default_handlers(CC, CV)` (`controller.lua:809`) is the bulk operation that makes
the console the owner of every `love.<event>` at once — "restore to the default route," in the
vocabulary of [`../decisions/input.md`](../decisions/input.md), D-ROUTE-OWNS. It does three things,
in order:

1. Calls `Controller.project_input:deactivate()` (`controller.lua:817`) — drops the project route
   first, so the reinstall below is never racing an already-live project occupant.
2. Calls the ten per-event `set_love_*` installers (`controller.lua:822-834`) — keypressed,
   keyreleased, textinput, mousemoved, mousepressed, mousereleased, wheelmoved, touchpressed,
   touchreleased, touchmoved — each one repointing its `love.<event>` at the console.
3. Resets the user-handler presence flags (`user_update`/`user_draw`/`user_pointer = false`,
   `controller.lua:854`, `:856-857`) and installs the console's own `update`/`draw`/`quit`
   (`:855`, `:858-860`), recording the console's own handlers into `Controller._defaults`
   (`:859`, and per-installer at e.g. `:490`).

`set_default_handlers` is called at boot right after Layer 1 is installed —
`src/main.lua:389-390`, `setup_callback_handlers` then `set_default_handlers` back to back — and
again on every project teardown: `src/controller/consoleController.lua:1033` and the
`stop_project_run` call at `:1130`.

During a project **run**, the project route takes `love.keypressed` (and the other event handlers)
away from the console instead, via `occupy_input` (`controller.lua`).
`set_default_handlers` is what takes it back on stop — it is the console's own restore operation,
not a general-purpose "reset everything" call. The comment on `love.handlers.keypressed`
(`controller.lua`) states this explicitly at the Layer-1 forwarding site: *"`love.keypressed` below
holds the active route's handler — console via `set_love_keypressed`, project via
`occupy_input`."*

---

## The difference in one line

`setup_callback_handlers` builds the **fixed pump** — Layer 1, `love.handlers.*` — which always
runs the global shortcuts first, then forwards; it is set once at boot and never swapped again.
`set_default_handlers` (re)installs **Layer 2**, `love.<event>` — the layer routes actually swap
between console, editor, and a running project — and its specific job each time it runs is "reset
every `love.<event>` back to the console." These are not two ways of doing the same thing: one is
permanent plumbing, the other is a route-switch operation invoked repeatedly over the app's
lifetime.

---
## What becomes of a project-defined `love.*`

`setup_callback_handlers`'s "callback" / "handlers" wording is **LÖVE's own**: the function
literally sets up `love.handlers`, which is what LÖVE calls that table. There is no second,
Compy-specific sense of *handler* to collide with it — the input API's vocabulary
([`../decisions/input.md`](../decisions/input.md#vocabulary--hook-callback-handler)) names
*other* things — **hook**, **callback** and **shortcut** — and leaves "handler" to LÖVE.

What does need saying is what happens to a project's own `love.*` functions, because a project
author writing them believes they are installing handlers:

**Every channel is treated the same way, and that is the whole answer.** Keyboard and text
(`keypressed`, `keyreleased`, `textinput`), pointer (`mousepressed`, `mousemoved`, …) and the
derived clicks (`singleclick`, `doubleclick`) are all captured from the project's sandboxed `love`
table and **seeded as `compy.input.hooks[event]`** (D-HOOKS-SEEDED), once, at activation, off one
channel list (`_bindable`). They run in hook position inside the route's walk, with hook semantics:
a truthy return consumes. None of them is installed as `love.<event>`; the route owns that. Writing
`compy.input.hooks.textinput = f` directly is the same thing said plainly, and is the encouraged
form.

So a project author's `love.mousepressed` is demoted to a hook exactly as their `love.keypressed`
is, and "handler" keeps its literal meaning for neither.

**Two pointer questions are still open, and neither is an install asymmetry:** whether a shown
widget should consume clicks **within its bounds** automatically — nothing does bounds checks, so
the chain gives a project the means to decide rather than deciding for it — and whether a pointer
*combo* vocabulary is wanted, a modifier plus a button, pointer having no shortcuts tier and
entering the walk at the hook tier. Both are recorded as deliberately open under
[`../technical_debt/input.md`](../technical_debt/input.md), *"Pointer delivery is an unstructured
broadcast, not a chain"* — an entry whose heading reads RESOLVED because the broadcast itself was
resolved: pointer joined the one chain (`../decisions/input.md`, D-ONE-LIFETIME).

---
## What becomes of an event nobody consumed

**It goes nowhere, unless the program can no longer act** (the maintainer's ruling of 2026-11-17:
"all input is the program's while it runs"). `occupy_input` binds every channel to the project
route, and the route's walk reports whether anybody consumed (`projectInputController.lua`,
`dispatch`: a shortcut or hook returning truthy, or a shown widget). Before the walk, the route
asks `can_act` (`controller.lua`): an update or a draw, a hook or a non-empty shortcut table on any
channel, a shown field, or a serial handler. While the program can act, every event is its own and
what its walk leaves goes nowhere, with one exception: a key press that is one of the output's
scrolling keys, or a wheel event, scrolls the console's output (`ConsoleController:output_key`,
`output_wheel`; ruling 1.1, "the scrollback area is visible so it takes keys and mouse events that
normally belong to it, if the program doesn't take these keys and events"). Once the program can
act no more it has ended at its last line: that event releases the route
(`release_keyboard_route`) and goes to the console's own handler, `Controller._defaults[event]`;
the two derived clicks (`singleclick`, `doubleclick`) have no console default by design and go
nowhere, without raising. The predicate is asked as the event comes, before the walk, since hooks
and shortcuts come and go; the hook table is the one record, a program's own handlers being seeded
there.

**Is this base parity?** No longer. At the PR base binding was per channel: a project that defined
no handler for a channel left it with the console. Since 2026-11-17 a program that can act on any
channel, or that updates or draws, owns them all.

The regression this pays, with the base comparison and the per-example measurement, is
[`../technical_debt/input.md`](../technical_debt/input.md), `T-ROUTE-EATS-UNCONSUMED`.
