# Console Mode — Implementation Overview

<!-- authored By LLM; human-approved NOT YET -->

Console mode is the default application state — active when no project is running and the editor is not open. It presents the user with a REPL-like interface: type Lua, press Enter, see results. It is also the lifecycle manager for projects: opening, running, suspending, stopping, and closing them.

---

## App State Machine

`love.state.app_state` drives what the application does on each frame:

| State | Meaning |
|---|---|
| `ready` | Console REPL active; the open project is not running, or its code has finished and it only answers events |
| `running` | Project's main.lua is executing (handlers set) |
| `snapshot` | Transition: screenshot requested, about to suspend |
| `inspect` | Project suspended (paused); console REPL active over frozen project state |
| `editor` | Editor is open |
| `shutdown` | Quitting |

Key transitions not obvious from the state table:

| Transition | Trigger |
|---|---|
| `running → editor` | Ctrl+T (quickswitch) while running |
| `editor → running` | Ctrl+T while in editor (normal mode) |
| `editor → inspect` | `finish_edit()` when project was running before edit was opened |
| `inspect → editor` | `edit()` called while in inspect |

The full machine is diagrammed in `doc/mermaid/fsm.md` and `doc/mermaid/fsm_f.md`.

The `snapshot` state is a one-frame transition: on the next `update()` tick, LÖVE2D captures a screenshot, stores it as `View.snapshot`, and then calls `ConsoleController:suspend()` which switches to `inspect`. The snapshot is drawn as a background behind the console UI during inspect, giving the user a "freeze frame" view of where the project stopped.

---

## Three Environments

This is the most non-obvious architectural decision in the console. There are three Lua environments (tables used as `fenv`):

**`main_env`** — the live console environment. Code typed into the REPL runs here. Contains the project management commands, file I/O, `compy`, `gfx`, etc. Mutated by user REPL commands.

**`compy` is not the same table in both environments, and the difference is one member.** The console's `compy` has **no `input`** — the input surface is built for the project environment only (`get_compy_namespace(terminal, with_input)`, `consoleController.lua`). A console-side surface resolved whichever widget was current, so a command typed at the prompt could reconfigure a running project's widget, while its own hooks were dispatched by nobody; the release removes the member rather than making it work, *"because input API is not yet ready to run out of project sandbox"* (owner, 2026-09-08). **Assignment still raises in both**: `compy.input = {}` at the prompt fails loudly instead of handing the caller a plain table it would believe is the API. What a console-side input surface would have to be is designed and not scheduled — see `doc/development/technical_debt/input.md`, `T-CONSOLE-SURFACE-INTERFERES`, and the BACKLOG entry it points at.

**`base_env`** — a frozen snapshot of `project_env` at project-open time. Protected with `table.protect()` (writes are blocked). Serves as the clean baseline that `project_env` is reset to when a project is stopped without closing.

**`project_env`** — the mutable environment in which a project's code runs. Started as a clone of `base_env`, then the project's own `require`/`dofile` calls and global assignments accumulate here. Reset to `base_env` on `_reset_executor_env()`.

The reason for `base_env` vs `project_env`: restarting a project (`Ctrl+Alt+R`) should give it a clean global table, but reopening the project should not — the distinction allows "reset project state" without "close and reopen".

Sources: `prepare_env` and `prepare_project_env` (consoleController.lua:341 and 482), `_set_base_env`, `_reset_executor_env`.

---

## Console Input Evaluation

When Enter is pressed in the REPL (`ConsoleController:keypressed`, line 1009):

1. `evaluate_input()` is called
2. The input text is validated via the `Evaluator` (LuaEval — parse via metalua)
3. If parse succeeds: `codeload(code, run_env)` compiles the string into a chunk with the appropriate `fenv` (console env normally; project env during `inspect`)
4. `run_user_code(f, self)` executes the chunk inside `use_canvas` — so any `gfx.*` calls go to the virtual canvas
5. Output from `print()` goes to the terminal via the `redirect_to` mechanism (set up in `src/main.lua`)
6. On success: input is cleared. On error: error is set on the input model and displayed in the status line.

During `inspect` state, the REPL runs code in `project_env`, allowing the user to inspect and mutate the paused project's state.

---

## Project Lifecycle

### Opening a project

`open_project(name)` (consoleController.lua:782):
- Closes any currently open project first
- Calls `ProjectService:opreate(name)` which opens an existing project or creates a new one with example code
- Registers a custom `package.loader` that loads modules from the project directory (prepended to `package.loaders` so it takes priority)

The custom loader is stored in `self.loaders[name]` so it can be removed on close.

### Running a project

`run_project(name)` (line 230):
- Calls `ProjectService:run()` which loads `main.lua` via the project's filesystem mount
- Sets state to `running`
- Calls `run_user_code(f, cc, path)` which: executes the chunk in `use_canvas`, then calls `set_user_handlers(env['love'], cc)` to detect and register any `love.*` event handlers the project defined
- If the project defines no blocking handlers (`love.draw`, `love.update`), state immediately returns to `ready`; with no input widget shown and no pointer handler either, the program has ended and `flush_program_state` puts the mouse back

### Stopping vs suspending vs quitting

**`stop_project_run()`**: Clears user handlers, calls `evacuate_required()` to remove project modules from `package.loaded`, restores default draw, resets widget input, and puts the mouse back as the console needs it (`flush_program_state`, which `run_project` also calls before a run starts and on a top-level raise). State → `ready`. The project's global state persists in `project_env` (can be inspected at the REPL).

**`suspend_run(msg)`**: Requests a snapshot. State → `snapshot` → `inspect` on next tick. Handlers saved; default handlers restored temporarily. The console gets its mouse back and the program's is saved. User can inspect and continue.

**`continue()`**: Restores project handlers and the program's mouse from the saved copies. State → `running`.

**`quit_project()`**: Calls `stop_project_run()` + `close_project()` + resets terminal and input. The environment is wiped.

### Module isolation

`evacuate_required()` (line 844) removes all project `.lua` filenames from `package.loaded` when stopping. This ensures that `require('helpers')` in the project will reload fresh on the next run, rather than returning the cached module from the previous run. Without this, mutated module state would leak between runs.

---

## The `user_input` Widget

Projects can request live text input mid-run via `compy.input.*`
**(supported since 1.0.0-rc20260712)**
(`show`/`hide`/`configure`/`clear`/`set_text`, callback fields
`on_text_entered`/`after_submit`/etc. — the full surface is in
[`user_input.md`](user_input.md), and the project-author usage guide
is [`../../input_api.md`](../../input_api.md)). This creates a second
`UserInputModel`, painted over the console frame by the draw wrapper
`Controller.set_love_draw` installs. Calling `show`
creates/reuses the singleton `UserInputController`/`UserInputView`
and stores the triplet in `love.state.user_input`, which is the
**drawing** contract: the draw path paints for exactly as long as it is
set. Events do not read it — the gateway routes on the active route,
and the widget is reached inside that route's own chain
([`user_input.md`](user_input.md), "Dispatch chain"). `show` on an
already-active widget warns and no-ops unless `force = true`.

Source: `prepare_project_env` (`consoleController.lua`),
`love.state.user_input` handling in `controller.lua` handlers.

The five legacy globals this replaced (`user_input()`,
`input_text()`, `input_code()`, `validated_input()`,
`write_to_input()` — a bare poll-a-reftable idiom, one call
returning a callable `reftable` the project polled with
`r:is_empty()`/`r()` each frame) are **(deprecated, removed in
1.0.0-rc20260712)**; calling any of them now is an ordinary `nil`
call, no shim.

---

## The `compy` Namespace

Projects receive a `compy` table with:

| Field | Contents |
|---|---|
| `compy.audio` | Sound effects (`sfx.beep()`, `sfx.gameover()`, etc.) — `src/util/audio.lua` |
| `compy.terminal` | VT-100 terminal control (`gotoxy`, `clear`, `show_cursor`, `hide_cursor`) |
| `compy.graphics` | Extended graphics (`shape2d`) — `src/util/graphics/shape2d.lua` |
| `compy.fonts` | Font path constants (`mono`, `sans`, `serif`, etc.) — `src/util/namespace/fonts.lua` |
| `compy.input` | Text input widget surface (`show`/`hide`/`configure`/`clear`/`set_text`) — see [`user_input.md`](user_input.md) |

`compy.terminal` wraps the VT-100 terminal instance directly (the same terminal that renders the console output). Projects can use it for text-mode output within their run context.

---

## Key Files

| File | Role |
|---|---|
| `src/controller/consoleController.lua` | Everything: env setup, project lifecycle, REPL eval, widget input API |
| `src/model/consoleModel.lua` | Model aggregate (input, editor, output canvas, project service) |
| `src/model/project/project.lua` | `ProjectService` and `Project` — open/run/close, file I/O, filesystem mount |
| `src/model/io/redirect.lua` | Redirects `print()` output to the terminal |
| `src/view/consoleView.lua` | Top-level view compositor |
| `src/util/audio.lua` | `compy.audio` sound effect library |
| `src/util/namespace/fonts.lua` | `compy.fonts` font path constants |
