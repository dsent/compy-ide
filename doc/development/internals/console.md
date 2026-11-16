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

## Two Environments

There are two Lua environments (tables used as `fenv`):

**`base_env`** — the clean baseline, built once by `prepare_project_env` from a copy of the IDE's own globals (`pre_env`) and the console's commands, file I/O, `compy` (with its `input` surface), `gfx`, etc. Nothing runs in it.

**`project_env`** — a deep copy of `base_env`, made anew when a project opens and before each run (`_reset_executor_env`). A project's code runs here, and so does every line typed in the console, paused or not (`get_effective_env` returns it): the console reads and changes what the last run left, until the next run makes it anew. `continue()` and `dofile()` run in it as it stands.

Sources: `prepare_project_env`, `_set_base_env`, `_reset_executor_env`, `get_effective_env`.

---

## Console Input Evaluation

When Enter is pressed in the REPL (`ConsoleController:keypressed`, line 1009):

1. `evaluate_input()` is called
2. The input text is validated via the `Evaluator` (LuaEval — parse via metalua)
3. If parse succeeds: `codeload(code, run_env)` compiles the whole line, every statement in it, into one chunk whose `fenv` is the project's environment
4. A line the parse refuses, or one Lua does not load, is not taken: its message shows in the notice band directly above the status line, as the file editor shows its messages, and the line stays in the field (`user_input.md`, "Error state"). A statement the parse continues takes Enter as its next line, and the band says so in orange (`UNFINISHED`, a notice).
5. The line is accepted: it enters the history, and `CanvasModel:echo` writes it to the output in `colors.terminal.echo` (blue), on a row of its own, before it runs.
6. `run_user_code(f, self)` executes the chunk inside `use_canvas` — so any `gfx.*` calls go to the virtual canvas. Output from `print()` goes to the terminal via the `redirect_to` mechanism (set up in `src/main.lua`)
7. The input is cleared (`clear_text`) whether the line ended well or in an error; it is in the history, and Up brings it back (the maintainer's ruling of November 16, 2026). On error, `CanvasModel:write_error` writes the error to the output after what the line printed. Any message shown before the line's Enter went with that key. Only a line that was not taken stays in the field: one that does not parse, does not load, or is unfinished.

The console has two channels (the maintainer's ruling of November 15, 2026). The notice band is the field's: it says why a line was not taken, and in orange a hint that is no error or a pause's text. What a command does is said in the output, each on a row of its own: `CanvasModel:write_error` writes a run's error in `colors.terminal.error` (red, for errors alone), `CanvasModel:write_refusal` a command's refusal in `colors.terminal.refusal` (a burnt orange), and an answer, such as "Project x opened", is printed in the output's own colour. Through `write_error` go a typed line's run error and a program's load and run errors (`run_project`, and `user_error_handler` in `controller.lua`, which pauses the program without a message); through `write_refusal` every console command's refusal (`messages` in `consoleController.lua`, and `ProjectService.messages` for a file or a project; `ProjectService:run` says which of its errors are refusals). A project is always open: `ConsoleController:open_project` refuses a name that cannot be a project's (`ProjectService.valid_name`) before it closes anything, puts back the project that was open when another cannot be opened or made on the card, and `close_project` lands in `scratchpad`. Only a card that cannot hold `scratchpad` leaves none open; every command that needs a project asks `ConsoleController:open_or_refuse`, which then says so as a refusal. Each run starts from a fresh environment (the maintainer's ruling "A run starts from a clean environment"). The run seam in `run_project` is one thing: end a run that is live exactly as a stop does (`stop_project_run`: handlers, input hooks and shortcuts, `before_exit`, serial handlers, the widget, then the modules, `evacuate_required`); with nothing live there is nothing to end, and only the modules go. Then a new environment, as opening the project makes it (`_reset_executor_env`), then the graphics state a program set goes (`reset_graphics`: `love.graphics.reset`; the bound canvas is bound again, and `run_project` sets the IDE's font after), then start. A run that ends for good resets the graphics state too, so the IDE draws on under its own (`_stop_project_run`, and the error of a program's first lines); a pause does not, so `continue()` resumes with the program's. The IDE draws its own things in its own graphics state, through one helper (`src/view/ownState.lua`: `push('all')`, `love.graphics.reset`, the IDE's font, the drawing, `pop()`). Every place the IDE draws goes through it: `View.draw` (the console's output and the program's canvas over it, the status line, the band, the field, the key card and the editor, the output's cached canvas among them), `draw_field` in `controller.lua` (a program's input field), `UserInputView:render` (a field's cached canvas, which also renders from a program's `show()` or `set_text()` or a key, outside any draw) and `View.drawFPS` (the frame-rate overlay). `CanvasModel:clear_canvas` clears the program's own canvas, and puts aside the scissor and colour mask itself. A program's scissor, wireframe, colour, shader, blending or transform reaches none of the IDE's pixels, running, paused or stopped, and the pop gives the program its state back, so a paused program resumes with it. This costs a reset and a font call a frame, and four calls more while a program's field shows. A run a program's `love.draw` ends or replaces has its state put back by the draw wrapper's `pop()`; the wrapper resets it once more, for a line typed next and for the run started there (`ConsoleController:reset_graphics`). Opening another project has done the stop and the reset already, and Ctrl+R stops before it calls the seam, so each happens once. Known limits: the rest of a typed line after `run()`, as in `run(); print(x)`, still sees the environment it started in, the one the run replaced; a transform a program pushed and never popped survives into the next run, since a run can start inside the IDE's own drawing or a program's push, and the seam leaves the stack to them; with nothing live, a shortcut or hook a typed line set on `compy.input` stays (Ctrl+R's stop clears it); and a program that stops its run from a handler other than `love.draw`, between its own `push('all')` and `pop()`, puts its graphics state back with that `pop()`: the IDE's own drawing does not take it, but a line typed next does; a program whose `love.draw` calls `stop(); run("target")` loses the scissor or colour the target sets in its first lines, which the draw wrapper's `pop()` and reset discard, where starting the target directly keeps them; and a program that calls `compy.input.show` or `set_text` inside its own `love.graphics.stencil(function() … end)` has that stencil write cancelled by the IDE's reset as the field renders, and the `pop()` does not resume it. The modules forgotten are the project's own and those a program loaded first (`program_loaded`, through its `require`); one the IDE had loaded itself stays shared. A run started by code that is running ends that code's run: its post-run steps and its handler install are skipped by the run's number (`run_id`), and an invocation installs its handlers only while its run is still live, so code that stopped its own run installs nothing. What the run leaves stays in the environment, for the console's lines to inspect, until the next run; `continue()` and `dofile()` run in it as it stands. A pause is the debugger's: `pause("text")`'s text and Ctrl+Pause's "BREAK into program" show in the band as an orange notice when the program pauses, and the program's screen is not touched (`ConsoleController:suspend`). `run("name")` opens and runs a project that exists and makes none: a name no project has is refused (`messages.no_such_project`), and `project("name")` makes one.

During `inspect` state too the REPL runs code in `project_env`, the paused project's, which `continue()` resumes as it stands.

---

## The Output and Its Kept Rows

The output is the terminal's grid (`src/lib/terminal.lua`), 64 by
16 cells, sized in `src/model/canvasModel.lua`. When a row scrolls
off its top, `terminal_roll_up` hands it, still whole, to
`terminal.on_row_leaving`; `CanvasModel` keeps it in a `KeptRows`
store (`src/model/keptRows.lua`): its text with a style (color, back
color, reversal) for each run of characters, the newest
`output_kept` rows (1,000, `src/main.lua`). Nothing else enters
the kept rows: `CanvasModel:reset` (a clear from code,
`compy.terminal.clear()`, and the play mode's quit) erases the 16
rows alone, and `CanvasModel:erase` (Ctrl+L) also drops what still
waits to be written and forgets the kept rows. Closing or opening
a project leaves both as they are.

The console's text is one sequence: the kept rows, numbered from
`kept.first` to `kept.last`, then the screen's rows down to the
last that holds text. At rest the screen is drawn as it is. A
scrolled view (`CanvasModel.view_top`, its first row's number) is
a window of 16 consecutive rows of the sequence, drawn by
`TerminalView` from the kept rows and the grid without changing
either; a number names the same row while new rows arrive, so new
output leaves the view where it is. `scroll_row`, `scroll_page`,
`to_oldest` and `to_rest` move it (the keys in
`src/model/input/consoleKeys.lua`). Every other key brings the
screen back first, except a modifier or a lock key on its own and
F1 (`ConsoleController:_back_to_screen`). A key or a text that a
running program takes brings it back too, except a lone modifier
or lock (`takes_screen` in `src/controller/controller.lua`), and
so does a running program's input field when it comes up
(`ConsoleController:pass_time`); a paused program's field leaves
the keys to the console.
`CanvasView:draw_cues` draws the editor's continuation cue
(`src/view/continuationCue.lua`) at a cut edge of a scrolled view.

A key reaches these only when it reaches the console: a program's
shown input field, its own `love.keypressed` or its own `love.draw`
keeps every key (`fall_through` in `src/controller/controller.lua`).

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
- If the project defines no blocking handlers (`love.draw`, `love.update`), state immediately returns to `ready`; with no input widget shown and no pointer handler either, nothing of the program answers the pointer while the console is on screen, so `flush_program_state` puts the mouse back, even if keys or serial handlers still reach the program

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
| `compy.terminal` | VT-100 terminal control (`gotoxy`, `clear`); a `gotoxy` position outside the screen is taken to the nearest edge |
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
| `src/model/canvasModel.lua` | The output: the terminal grid, its kept rows, the scrolled view, the echo |
| `src/model/keptRows.lua` | The rows scrolled off the output's top |
| `src/model/project/project.lua` | `ProjectService` and `Project` — open/run/close, file I/O, filesystem mount |
| `src/model/io/redirect.lua` | Redirects `print()` output to the terminal |
| `src/view/consoleView.lua` | Top-level view compositor |
| `src/util/audio.lua` | `compy.audio` sound effect library |
| `src/util/namespace/fonts.lua` | `compy.fonts` font path constants |
