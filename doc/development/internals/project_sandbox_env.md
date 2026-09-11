---
description: How a running project's Lua environment is sandboxed — the deep-cloned env, the shared-leaf-function consequence, and the three tiers of state
status: active
audience: developer
authored: llm
reviewed: none
---

# Project sandbox environment

A project does **not** run in the raw global environment. The console controller builds a per-project
env and `setfenv`'s the project's chunks into it. Understanding *what is and isn't isolated* by that env
is load-bearing for any feature touching project lifecycle, global state, or teardown.

## How the env is built

- `ConsoleController.new` captures the file env: `local env = getfenv()` (`consoleController.lua:40`),
  and clones it: `pre_env = table.clone(env)` (`:41`).
- The project env descends from that clone (`get_pre_env_c` → `prepare_project_env`, `:514–520`); the
  project's files are loaded via `project_dofile` which does `setfenv(chunk, env)` (`:297`).
- `table.clone` (`util/table.lua:48`) is **recursive** (deep) and copies metatables, with a `seen` set
  for cycles.

**The crucial consequence.** A deep clone gives the env a `love` table with a **fresh identity**, but
its **leaf values are shared by reference** — `table.clone` returns non-tables as-is (`table.lua:50`).
So every *engine function* the clone starts with — `love.graphics.print`, `love.mouse.setVisible`,
`love.keyboard.setKeyRepeat`, `love.audio.play`, … — is the **same C function** the global `love`
holds. The *table* is sandboxed; the *functions and their side effects* are not.

This is about the functions a project **calls**, not the callbacks it **defines**. Those are the
opposite case: when a project assigns `love.draw`, `love.keypressed`, `love.textinput` and friends, it
writes into its own cloned `love`, and the framework harvests them from there
(`save_user_handlers(runner_env['love'])`, `consoleController.lua:824`) rather than letting them reach
the real global — see T1 below, and `event_dispatch_layers.md` for where a harvested callback is
re-installed. Input callbacks in particular are re-installed as *hooks* on the project route, never as
global LÖVE handlers ([`user_input.md`](user_input.md), "Dispatch chain"). Nothing in this section
weakens that: a captured callback is safe precisely *because* it never touches the shared leaf, and
a shared leaf is dangerous precisely *because* nothing captures a call to it.

## Three tiers of project state

**Leak** here means one thing: state a project changed that is **still changed after the project
stops**, so the console — or the next project — inherits it. A tier "does not leak" when the framework
either keeps the state inside the project's own env or restores it at stop; it "leaks" when the state
lives in a global subsystem nobody snapshots.

| Tier | What | Isolated / restored? |
|---|---|---|
| **T1 — handlers** (LÖVE calls these "callbacks"; here the word is the widget's — see `../decisions/input.md`, *"Vocabulary — hook, callback, handler"*) | `love.draw`, `love.update`, `love.keypressed`, `love.textinput`, `love.mouse*`… defined by the project | **Yes — framework-managed.** Set on the project's cloned `love`; harvested by `save_user_handlers(runner_env['love'])` (`consoleController.lua:824`) and wired into the real dispatch; reset to defaults on stop (`set_default_handlers` / `restore_user_handlers`, `controller.lua:826`). No leak. |
| **T2 — `compy.*`** | `compy.terminal`, `compy.audio`, `compy.graphics`, `compy.input` **(supported since 1.0.0-rc20260712)**… injected into the env (`get_compy_namespace`, `consoleController.lua:360`) | **Yes — framework wrappers.** The project calls a controlled surface; the framework owns the underlying object. No leak. |
| **T3 — raw `love.*` imperative calls** | `love.keyboard.setKeyRepeat`/`setTextInput`, `love.mouse.setRelativeMode`/`setVisible`, raw `love.audio.newSource`/`play`, cursor… called (not defined) by the project | **No.** These invoke the shared C functions → mutate **real global SDL/LÖVE subsystem state**. Nothing snapshots or restores them across run boundaries. **They leak into the IDE/console after the project exits.** |

### Font at project startup

`ConsoleController:run_project` selects the configured Compy font, including
its icon and CJK fallbacks, immediately before executing project code. Every
run starts with that font, including restarts and runs after another project
selected a custom font. A project can select its own font during execution.

## Why this matters

- **T1 isolation is what makes the IDE survive a project** — a project that defines `love.draw` doesn't
  permanently hijack the console, because the framework swaps handlers in/out. Any input feature that
  reroutes callbacks (e.g. the `ProjectInputController` added in 1.0.0-rc20260712) lives in this T1
  machinery.
- **T3 is the real leak surface.** A project that sets relative-mouse mode, hides the cursor, disables
  key-repeat, or leaves a sound playing leaves that state changed after exit.
  Example: `src/examples/keyboard/input.lua` *wants* to disable key-repeat for clean input but
  deliberately doesn't, **because it cannot restore it on exit** — and hand-rolls edge-tracking instead.
- **The robust fix for T3 is framework snapshot/restore across run boundaries** — extend the T1
  save/restore discipline to imperative subsystem state. This is sandbox-safe (doesn't trust the
  project to clean up), survives a crash, and is strictly better than relying on a project teardown
  hook — which is why `compy.before_exit` (below) is scoped to project-internal teardown and not
  offered as the answer to T3.

### `compy.before_exit` — the project teardown hook

It exists and is wired **since 1.0.0-rc20260712**; it is **not** a proposal. `compy.before_exit` is a slot on the injected
`compy` namespace, defaulting to a no-op (`default_before_exit`, `consoleController.lua`), assignable
by the project through the namespace metatable (`build_project_env`'s `before_exit_slot`) — assign a
function to it and the framework calls it **once, first thing, when the project stops**
(`ConsoleController:stop_project_run` → `framework_before_exit`), before any handler teardown. The
slot is then reset to the default in the same function, so the next project starts clean and cannot
inherit the previous one's teardown.

Every stop path that runs a project reaches `stop_project_run`, so the hook fires on all of them:
`Ctrl+Q`, `Ctrl+S` and `Ctrl+T` into the editor (the gate's `RESERVED` table, `controller.lua`), and
the `Ctrl+Esc` / `love.quit` path (`Controller.set_love_quit`, which stops the project instead of
quitting whenever one is running or the console is still interactive). The only exit that runs no project code
is quitting with **no** project running, where there is nothing to tear down.

What it is for: **project-internal** teardown — save a score, flush a memo, stop a timer. It is not a
restore mechanism for T3 global state, which the project cannot restore reliably in any case
(a crash never reaches the hook). Covered by `tests/input/input_route_lifecycle_spec.lua`
("`compy.before_exit`").

**What it cannot guarantee.** The hook is a notification, not a veto and not a transaction. The
framework calls it from inside a teardown function of its own, in a `pcall`, and reads nothing it
returns (D-STOP-IS-FW) — so an absent hook is skipped, a raising one is logged and the stop
continues, and a project cannot refuse to stop, defer the stop, or break it by failing. The consequence a project author has to
plan around is the one this cannot fix: **a project that raises before reaching a clean state never
gets to run its teardown at all**, because the raise, not the stop, is what ends the run. That gap is
the failure mode the "proposed robust fix" above is a counter-measure for — identified and
registered, not implemented. The register entry is
`doc/development/technical_debt/input.md`, "A project that raises leaves global device state dirty;
no force-reset exists", which names the same crash path from the other side:
`run_project`'s failed-run branch drops to `project_open` without ever calling `stop_project_run`,
so the hook is uninstalled but never fired. See `doc/development/decisions/input.md`, D-STOP-IS-FW,
for the hook's contract (framework-owned teardown, called from inside it, return value unread) and
D-ROUTE-LIFETIME for the teardown invariant itself.

## Pointers

Each says what you get by following it, so the list can be scanned rather than sampled.

- **How a project's own `love.*` handlers actually reach it** — T1 above, from the dispatch side:
  [`event_dispatch_layers.md`](event_dispatch_layers.md).
- **The input widget's namespace, lifetime and routing contract**:
  [`user_input.md`](user_input.md).
- **What a project author is told about any of this** — the public guide:
  [`../../input_api.md`](../../input_api.md).
- **The `before_exit` contract** — teardown is the framework's, the hook is called from inside it,
  and its return value is unread: [`../decisions/input.md`](../decisions/input.md), D-STOP-IS-FW.
- **Why the input route outlives the run** — every channel is held from activation until the
  project *stops*, so a non-blocking project sitting in `project_open` keeps them all:
  [`../decisions/input.md`](../decisions/input.md), D-ROUTE-LIFETIME.
- **The T3 leak, registered rather than fixed**:
  [`../technical_debt/input.md`](../technical_debt/input.md), *"A project that raises leaves
  global device state dirty; no force-reset exists"*.
