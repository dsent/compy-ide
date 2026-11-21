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
| `snapshot` | Transition: a pause requested, made at the end of the frame's update |
| `inspect` | Project suspended (paused); console REPL active over frozen project state |
| `editor` | Editor is open |
| `shutdown` | Quitting |

Key transitions not obvious from the state table:

| Transition | Trigger |
|---|---|
| `running → editor` | Ctrl+T (quickswitch) while running |
| `editor → running` | Ctrl+T while in editor (browsing state) |
| `editor → ready` | `finish_edit()` (entering the editor stops any live run first) |
| `inspect → editor` | `edit()` called while in inspect |

The full machine is diagrammed in `doc/mermaid/fsm.md` and `doc/mermaid/fsm_f.md`.

The `snapshot` state is a transition within one frame: the frame's `update()` calls `ConsoleController:suspend()` at its end, which switches to `inspect`. The paused frame is the last one the program drew on its canvas, which a pause keeps; the screen shows the console (`ScreenModel:pause`), and `continue()` brings back the mode it replaced (`doc/development/drawing_system.md`).

### The status line's colours and words

The status line says what has the screen, by its colours and in words (the maintainer's rulings of November 17, 2026: its colour "clearly indicates the mode (but is never the single differentiating indicator)"; "keep the bar dark gray, just add 'running' in yellow as a status"; "the status line always starts with: project file mode", "'paused' in yellow as well", a darker red with white text; and of November 18, 2026, on its forms and its fit; `theme_of` and `Statusline:draw` in `src/view/input/statusline.lua`, the colours in `colors.statusline`). The IDE's own line starts with the project, the file and a state word in yellow. The console's own line names no file ("in console, there's no need to show the file"); a running or paused program's names its entry file, the one the run started from (`ConsoleController:entry_file`, `main.lua` unless a run started from another). The project keeps its place as a program starts, pauses and stops, and the file and the word keep theirs between running and paused:

| What has the screen | Theme | Ground | Left side | Right block |
|---|---|---|---|---|
| the console, a program that ended by itself included | `console` | dark gray, white text | the project and "console" (`state_source`) | the screen's mode, Caps Lock, `L-N`, the draft's cursor |
| a live program that can act and shows no field: the bare line (`ConsoleController:running_status`) | `console` | dark gray, white text | the project, the entry file and "running" | the screen's mode, `L-N` |
| a pause (`inspect`), an error's included | `inspect` | #A00000, white text | the project, the entry file (`name_source`) and "paused" | as the console's |
| the editor (`editor`) | `editor` | blue, white text | the project, the file (followed by `[broken]` in the mark tone, one space between and never cut, while the file does not load) and the editor's state; while replacing, an arrow after it toward the edit's target while no row of the target is in view, `replacing↑` above the view, `replacing↓` below (`arrow` in `EditorController:_generate_status`, from `BufferView:target_side`, which reads the rows the view draws the target's yellow highlight on, its wrapped rows included; it answers whether a row of the target lies within the view's rows, and a notice band or the held key card lying over those rows for a moment does not change it) | Caps Lock, the file line and the file's line count (`L1080/1200`, or `L1201/1200` in the indicator tone at the end position), and while inserting or replacing the cursor's column in yellow (`L1082/1200 :32`) |
| a program's own field (`compy.input.show`, `compy.ask`) | `console` | dark gray, white text | the program's prompt | Caps Lock, the draft's cursor |

The draft's cursor reads `line:column` in the console and in a program's field (`1:6`), in the state's yellow; in the editor the right end shows the file line and the file's line count (`L1080/1200`, or `L1201/1200` at the end position in `colors.indicator`) and, while inserting or replacing, the cursor's column (`:32`) one column to its right in yellow, with every number written in full. `L-N` says how far the output is scrolled back from rest, N rows, up to the kept rows' limit (`CanvasModel:scrolled_back`, the console's `scroll_source`, the bare line's `back`; "when we scroll, we can show L-4"); at rest, and on a program's own field, there is none. The state word's yellow is the theme's `state` (the editor's `fg2`). The console's own label is empty, so that its line starts with the project. While the Compy runs without an SD card (`love.state.has_removable` false, read at each draw), every line of the IDE's own, the console's, a running program's, a pause's and the editor's, has `[no sd]` in front, in the bright orange of the theme's `mark` (#FFA500), never cut (`NO_CARD` in `statusline.lua`; "[no sd card] stays in front", and on the editor's line too; "shorten [no sd card] to [no sd]"); a program's own field has none. On Android without a card the IDE keeps its projects in the Compy's internal storage (`setup_storage` in `main.lua`), and projects run and pause there, so the mark stands on every bar: it reads 9.0:1 on the console's gray, 6.1:1 on the editor's blue and 4.3:1 on the pause's red, where the warning orange that toned labels keep gives 5.2, 3.5 and 2.4:1. The pause's ground is outside the palette, as the console's is: on #A00000 white is 8.4:1, the yellow 7.8:1 and the cyan of Caps Lock 6.7:1, where the palette's red gives white 6.5:1, and a red darker still comes too close to the console's gray for a protanope. The words come from the status (the console's `state_source`, the bare line's `running_status`) and the colours from the IDE's state, and the bare line's kept render compares both (`Statusline:key`); a program's field that keeps its render is rendered again when the IDE's state changes, so that a line rendered during a pause does not keep its red (`Statusline:ide_key`, `UserInputView:draw`).

The line's text starts one cell from the left edge and ends one cell from the right ("Have just one space on each side"). The draft's rows out of view are shown by the field's own continuation cue, and the line has no more-rows mark ("Drop the ↕↕"). The right block is packed to the right edge: in the editor, the file line and line count (`L1080/1200`) with the cursor's column (`:32`, one column apart) while inserting or replacing, and Caps Lock two columns to the left; elsewhere, the draft's cursor at the edge, and left of it `L-N`, Caps Lock and the screen's mode, two columns apart. Each part stands next to the one on its right and moves left only as that grows; none is cut or dropped, and no room is kept for a longer one. In the console's and a program's cursor `line:column`, a number above 9999 is written in thousands, `10K` for 10000 to 10999; the editor writes its numbers in full. The left side takes what is left: the `[no sd]` mark, never cut, then a field's label (a program's prompt), the project, the file with `[broken]` one space after it while the open file does not load (also never cut), and the state word, two columns apart. Short of room the label is cut first, then the state word, then the project, the file the last ("the project name gets cut next, and the file name only if nothing more can"), each down to three columns, two characters and the ellipsis; an arrow after the state word is never cut, and the ellipsis comes before it, `repl…↑` ("nothing should be dropped fully, only cut"; `fit_left`). The left side is drawn inside a clip that ends two columns before the right block (`intersectScissor`; review e6), so that were even the floors not to fit, it would be cut off there and cover nothing of the right block. The debug build's marks, the state's name and `testing` at the line's middle, take no room in the fit. The fitting counts cells, a character to a cell; a character wider than its cell, as the CJK fallback draws, overruns until the fonts are fixed (Beads `compy-ide-fonts-characters-wider-than-a-cell`; the maintainer's ruling of November 18, 2026). What a program or a name supplies for the line is drawn on its one row: a control character, a line break, a carriage return or a tab among them, is a space before the fitting (`shown`; review e3: a line break printed a prompt's second line under the bar).

---

## Two Environments

There are two Lua environments (tables used as `fenv`):

**`base_env`** — the clean baseline, built once by `prepare_project_env` from a copy of the IDE's own globals (`pre_env`) and the console's commands, file I/O, `compy` (with its `input` surface), `gfx`, etc. Nothing runs in it.

**`project_env`** — a deep copy of `base_env`, made anew when a project opens
and before each run (`_reset_executor_env`). A project's code runs here, and so
does every line typed in the console, paused or not (`get_effective_env` returns
it): the console reads and changes what the last run left, until the next run
makes it anew. `continue()` and `dofile()` run in it as it stands.

`loadstring`, `load`, `eval`, and `print_eval` are wrapped in
`prepare_project_env` so code compiled from a string runs in the current
`project_env` (a program that calls `setfenv` itself, or passes a table as the
fourth argument of either loader, overrides that). `eval` and `print_eval` evaluate in
`project_env` and raise syntax or runtime errors through the IDE's usual error
path (`write_error` at the console or in a running program) instead of
swallowing them; `print_eval` prints via `project_env.print`. The IDE's own
`_G.loadstring`, `_G.load`, `codeload`, and `util.eval` remain untouched in
`_G`.

Sources: `prepare_project_env`, `_set_base_env`, `_reset_executor_env`, `get_effective_env`.

---

## Console Input Evaluation

When Enter is pressed in the REPL (`ConsoleController:keypressed`, line 1009):

1. `evaluate_input()` is called
2. The input text is validated via the `Evaluator` (LuaEval — parse via metalua)
3. If parse succeeds: `codeload(code, run_env)` compiles the whole line, every statement in it, into one chunk whose `fenv` is the project's environment
4. A line the parse refuses, or one Lua does not load, is not taken: its message shows in the notice band directly above the status line, as the file editor shows its messages, and the line stays in the field (`user_input.md`, "Error state"). A statement the parse continues takes Enter as its next line, and the band says so in orange (`UNFINISHED`, a notice).
5. The line is accepted: it enters the history, and while console echo is on
   (`compy.terminal.setEcho`, on by default), `CanvasModel:echo` writes it to
   the output in `colors.terminal.echo` (blue), on a row of its own, before it
   runs.
6. `run_user_code(f, self)` executes the chunk inside `use_canvas` — so any `gfx.*` calls go to the virtual canvas. Output from `print()` goes to the terminal via the `redirect_to` mechanism (set up in `src/main.lua`)
7. The input is cleared (`clear_text`) whether the line ended well or in an error; it is in the history, and Up brings it back (the maintainer's ruling of November 16, 2026). On error, `CanvasModel:write_error` writes the error to the output after what the line printed. Any message shown before the line's Enter went with that key. Only a line that was not taken stays in the field: one that does not parse, does not load, or is unfinished.

The console has two channels (the maintainer's ruling of November 15, 2026). The
notice band is the field's: it says why a line was not taken, and in orange a
hint that is no error. What a command or a pause does is said in the output,
each on a row of its own: `CanvasModel:write_error` writes a run's error in
`colors.terminal.error` (red, for errors alone), `CanvasModel:write_refusal` a
command's refusal or a pause's message in `colors.terminal.refusal` (a burnt
orange), and an answer, such as "Project x opened", is printed in the output's
own colour. A run error that calls a global name that does not exist ("attempt
to call global 'x' (a nil value)") gains a line, where exactly one name in the
environment the code ran in can be called and differs from it only in case and
underscores: "There is no listProjects. Did you mean list_projects?"
(`src/util/name_hint.lua`; Beads `compy-ide-console-suggests-the-near-name`, the
maintainer's ruling of November 17, 2026, kept or dropped after the team
discusses it). `write_error` looks for it in the environment `name_source`
gives; for a program's first lines that raised, `run_project` reads it before
the flush that ends the program's globals, so that its own names count, and
hands it to the write after the flush, the seam's order as it was. The hint
never raises and runs none of the user's code: `NameHint.of` is protected, reads
tables and metatables raw, counts a value as callable only when it is a function
or its raw metatable's raw `__call` is one, and gives none where the environment
falls back to a function or further than four tables. A field gets none: Lua's
message names the field and not its table, which only the source says. Known
limits: the suggestion is taken from the project's environment, so a chunk whose
environment was changed with `setfenv` or a local of the same name can make it
wrong; a program that raises an error in Lua's own wording gets the hint; the
IDE's own globals reachable from the environment can be suggested (`CanvasModel`
for `canvas_model()`) until the console has an environment of its own (Beads
`compy-ide-resident-programs-in-the-console-context`); and a name with letters
outside ASCII gets no hint, as Lua's message is matched for ASCII names alone.
Through `write_error` go a typed line's run error and a program's load and run
errors (`run_project`, and `user_error_handler` in `controller.lua`, which
pauses the program without a message of its own); through `write_refusal` every
console command's refusal (`messages` in `consoleController.lua`, and
`ProjectService.messages` for a file or a project; `ProjectService:run` says
which of its errors are refusals) and a pause's message
(`ConsoleController:suspend`). A project is always open:
`ConsoleController:open_project` refuses a name that cannot be a project's
(`ProjectService.valid_name`) before it closes anything, puts back the project
that was open when another cannot be opened or made on the card, and
`close_project` lands in `scratchpad`. Only a card that cannot hold `scratchpad`
leaves none open; every command that needs a project asks
`ConsoleController:open_or_refuse`, which then says so as a refusal. Each run
starts from a fresh environment (the maintainer's ruling "A run starts from a
clean environment"). The run seam in `run_project` is one thing: end a run that
is live exactly as a stop does (`stop_project_run`: handlers, input hooks and
shortcuts, `before_exit`, serial handlers, the widget, then the modules,
`evacuate_required`); with nothing live there is nothing to end, and only the
modules go. Then a new environment, as opening the project makes it
(`_reset_executor_env`), then the graphics state a program set goes
(`reset_graphics`: `love.graphics.reset`; the bound canvas is bound again, and
`run_project` sets the IDE's font after), then start. A run that ends for good
resets the graphics state too, so the IDE draws on under its own
(`_stop_project_run`, and the error of a program's first lines); a pause does
not, so `continue()` resumes with the program's. The IDE draws its own things in
its own graphics state, through one helper (`src/view/ownState.lua`:
`push('all')`, `love.graphics.reset`, the IDE's font, the drawing, `pop()`).
Every place the IDE draws goes through it: `View.draw` (the console's output and
the program's canvas over it, the status line, the band, the field, the key card
and the editor, the output's cached canvas among them), `draw_field` in
`controller.lua` (a program's input field), `UserInputView:render` (a field's
cached canvas, which also renders from a program's `show()` or `set_text()` or a
key, outside any draw) and `View.drawFPS` (the frame-rate overlay).
`CanvasModel:clear_canvas` clears the program's own canvas, and puts aside the
scissor and colour mask itself. A program's scissor, wireframe, colour, shader,
blending or transform reaches none of the IDE's pixels, running, paused or
stopped, and the pop gives the program its state back, so a paused program
resumes with it. This costs a reset and a font call a frame, and four calls more
while a program's field shows. A stop or a run a program asks for is made once
its code has returned (see "A lifecycle call ends the code that made it" below),
after the draw wrapper's `pop()`, with no push of the program's still to be
popped: the reset pops what the program pushed and never popped
(`gfx.getStackDepth`), and none of it while one of the IDE's own pushes is under
way (`view.ownState` and the draw wrapper count theirs in `End.ide_pushes`),
then resets. Opening another project has done the stop and the reset already,
and Ctrl+R stops before it calls the seam, so each happens once. With nothing
live, the seam also clears three slots every environment shares, which a new
environment does not: `compy.before_exit` (removed, not called), the hooks and
shortcuts of `compy.input`, and the program's serial handlers, as `reset()` does
(round 21); a question `compy.ask` armed belongs to its widget, so none asked
before reaches a later run's field (round 22). Known limit: the `compy` tables
are shared by the console's lines and every run, so what a typed line overwrites
in them (`compy.serial.send`, a field of its own in `compy.input.hooks`) stays
until the IDE restarts; the console's own environment, Beads
`compy-ide-resident-programs-in-the-console-context`, removes this. Known limit:
a program that calls `compy.input.show` or `set_text` inside its own
`love.graphics.stencil(function() … end)` has that stencil write cancelled by
the IDE's reset as the field renders, and the `pop()` does not resume it. The
modules forgotten are the project's own and those a program loaded first
(`program_loaded`, through its `require`); one the IDE had loaded itself stays
shared. A run that ends by itself leaves nothing in the environment: its end is
a stop. `continue()` and `dofile()` run in the environment as it stands, and
what a `dofile()` defines stays there.

| | natural end (a stop) | pause / handler error | `continue()` | stop, Ctrl+Q, close, first-lines error | run seam |
| --- | --- | --- | --- | --- | --- |
| Globals, `love` handlers | cleared | kept | kept | cleared (environment made anew) | made anew |
| Hooks, shortcuts, `before_exit`, serial handlers, input field | cleared (`before_exit` called first) | kept | kept | cleared (`before_exit` called first on a stop) | cleared if a run was live |
| Modules | cleared | kept | kept | cleared | cleared |
| Graphics state, key repeat and text input | reset | kept | kept | reset | graphics reset |
| Sounds playing | play to their end, a loop no longer repeats | kept | kept | play to their end, a loop no longer repeats (`reset()`: stopped) | as the stop |
| The program's picture | kept, shown whole when the program drew | kept | kept | kept, the console shown (`reset()`: cleared) | cleared |
| Output, kept rows, history, editor files | kept | kept | kept | kept | kept | A pause happened to the program, so `pause("text")`'s text and Ctrl+Pause's "BREAK into program" print on a row of their own in the output in `colors.terminal.refusal` (`CanvasModel:write_refusal`), while a bare `pause()` prints nothing unless the program drew; the band is untouched (`ConsoleController:suspend`, ruling of November 21, 2026). `run("name")` opens and runs a project that exists and makes none: a name no project has is refused (`messages.no_such_project`), and `project("name")` makes one.

During `inspect` state too the REPL runs code in `project_env`, the paused project's, which `continue()` resumes as it stands.

---

## The Output and Its Kept Rows

The output is the terminal's grid (`src/lib/terminal.lua`), 64
cells wide and 16 rows high over an input field, sized in
`src/model/canvasModel.lua`. While no input field is drawn the
field's own row is the grid's seventeenth (the maintainer's ruling
of November 17, 2026: "the freed lines should be available to the
program with no restriction"): the console's field is hidden
behind a program that owns the input and the program shows none of
its own (`ConsoleController:fieldless`, asked each frame in
`pass_time`, which tells `CanvasModel:field_drawn`). A program
prints and moves there as on any row, `gotoxy` reaches it, and a
scrolled view is 17 rows high. The status line is then the
screen's last row and names only the project, the file the run
started from and `running` (`ConsoleController:running_status`,
`UserInputView.bare_status`). That line is rendered into the
field's canvas when anything its draw reads changes, and kept
otherwise (`UserInputView:draw`, `bare_drawn`). The status line
gives the comparison itself (`Statusline:key`): the whole of the
status it is given, and the IDE's state, which picks its colours
and which its draw reads in one place (`ide_state`); the view
adds the window's size, by which it places the line. A field
that is drawn renders every frame, which costs a Compy about
1.5 ms of each.
When a field comes back, at a
pause, a stop, or when the program shows its own, the grid loses
that row: text or the cursor on it rolls the grid up, as a line
end on the last row does, and the top row goes to the kept rows;
an empty row just goes (`Terminal:set_height`). The grid's height
is set at each frame's step and again as the screen is drawn
(`ConsoleController:fit_output`), so that a field a program's
update shows or hides is over a grid of the right height in that
very frame. The change acts on the grid at once, ahead of what
still waits to be written; `CanvasModel:erase` (Ctrl+L, `reset()`)
makes its clear at once for that reason, so that nothing it
erased is on the grid for a roll to keep. The grid's canvas
is made 17 rows high and drawn as many rows as the grid has. No
call tells a program how many rows the grid has. When a row scrolls
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
a window of as many consecutive rows of the sequence as the grid
has, drawn by
`TerminalView` from the kept rows and the grid without changing
either; a number names the same row while new rows arrive, so new
output leaves the view where it is. `scroll_row`, `scroll_page`,
`to_oldest` and `to_rest` move it (the keys in
`src/model/input/consoleKeys.lua`).

What brings the screen back from a scrolled view is one rule
(the maintainer's ruling of November 17, 2026): input does not,
a line that runs does, and so does a change of what the screen is
for. Typing, the arrows, Escape, Enter on a line that does not
run, and a key or a text a running program takes all leave the
view where it is, as new output does. The screen comes back:

- when a line runs: Enter on a console line that loads
  (`ConsoleController:_evaluate_input`), and an answer a
  program's field accepts (`UserInputController:submit_flow`
  calls `on_accepted`, which the console sets on the field it
  builds);
- on End with an empty field, and on Ctrl+L;
- at a transition: a run starts, stops, pauses or continues, a
  project opens or closes, the editor comes forward or steps
  aside, and a running program's input field comes up
  (`ConsoleController:pass_time`); a paused program's field
  leaves the keys to the console.

Every one of these is a call of `CanvasModel:to_rest`. One
consequence: behind a text program that takes every key, no key
the program takes brings a scrolled view back, End included; a
reserved chord that stops or pauses it (Ctrl+Q, Ctrl+Pause) does,
as any transition. The mouse wheel scrolls the output three rows
a notch, in the console and behind a program that leaves the
wheel (`ConsoleController:output_wheel`); behind a program that
leaves them, the output's own scrolling keys scroll it too
(`output_key`, "A program that can act owns all input").
`CanvasView:draw_cues` draws the editor's continuation cue
(`src/view/continuationCue.lua`) at a cut edge of a scrolled view.

A key reaches these from the console's own route, and from behind a
program that can act only when the program's chain leaves it and it
is one of the output's scrolling keys (`output_key`; a program's own
`love.keypressed` takes every key, its `love.draw` none).

---

## Project Lifecycle

### Opening a project

`open_project(name)` (consoleController.lua:782):
- Closes any currently open project first
- Calls `ProjectService:opreate(name)` which opens an existing project or creates a new one with example code
- Registers a custom `package.loader` that loads modules from the project directory (prepended to `package.loaders` so it takes priority)

The custom loader is stored in `self.loaders[name]` so it can be removed on close.

### Running a project

`run_project(name, stopped, entry)`:
- With `entry` (`run(nil, "second.lua")`, `run("name", "second.lua")`; Option 2 of the multi-entry-point proposal, its two-argument form only), checks the file name as file names are checked (`Project.writable_name`) and that the project holds it as a file (`FS.exists(path, 'file')`: a folder is refused), before anything changes; a missing file is refused "There is no second.lua in this project." It records `self.entry`, the file, when the file loads, and the run's end forgets it in the flush, by any way the run ends: the entry point lives with the run (the maintainer's ruling of November 16, 2026). Ctrl+R (`restart()`) restarts a live program from it, and does nothing with none live, in the console and the editor alike (`reserved_restart`, asking `program_live`, as Ctrl+Q's stop does); Ctrl+T from the editor runs `main.lua`. Known limit: a project with a second entry point has no key that runs it from the editor (Beads `compy-ide-run-key-for-a-second-entry-point`)
- Calls `ProjectService:run()` which loads `main.lua`, or `entry`, via the project's filesystem mount
- Sets state to `running`
- Calls `run_user_code(f, cc, path)` which: executes the chunk in `use_canvas`, then calls `set_user_handlers(env['love'], cc)` to detect and register any `love.*` event handlers the project defined
- If the project defines no blocking handlers (`love.draw`, `love.update`), state immediately returns to `ready`; with no input widget shown and no pointer handler either, nothing of the program answers the pointer while the console is on screen, so `restore_console_mouse` puts the mouse back, even if keys or serial handlers still reach the program

### Stopping vs suspending vs quitting

**`stop_project_run()`**: The one flush, `flush_program_state` (Beads `compy-ide-terminate-flush`): a stop, Ctrl+Q, the close of a project (through `_close_project`), an error in a program's first lines (which removes `compy.before_exit` without calling it) and the run seam's stop all end there. It drops what the program queued for the board, calls `compy.before_exit`, forgets the modules, puts the console's mouse, handlers and draw back, destroys the input field, keeps the program's canvas with the background colour it set and shows the console (`ScreenModel:ended`; `reset()` clears the canvas), pops what the program pushed and never popped and resets the graphics state (no program code is on the stack at a stop, and the IDE's own push around a program's draw is never popped), puts the master volume back to LÖVE's 1 (the IDE sets none), ends looping on what plays and lets it play out (`love.audio.pause()` returns every playing source, LÖVE 11; each is set not to loop and played again from where it was; a source the program paused or stopped is left; `compy.audio`'s sounds are one-shots), puts key repeat and text input back as `main.lua` set them, clears the program's handlers, hooks, shortcuts and serial handlers, makes the environment anew, so the program's globals go, and collects garbage twice when a run ended there. State → `ready`. A pause flushes nothing. A program's natural end is a stop (`ConsoleController:end_naturally`): when its first lines have run and it can no longer act (`Controller.program_owns_input`), or when an event finds it can no longer act (the route wrapper in `controller.lua`, through `End.defer` once the event is done), it gets this flush, `before_exit` called; at the end of its first lines a program that drew leaves its picture on show (`ScreenModel:ended_by_itself`). The flush has two halves. Ending what a program left (what was queued for the board, `before_exit`, the environment made anew, the garbage collected) happens once for each end, by construction: there is something to end while a run is live, a program holds the screen or waits paused (`app_state` other than `ready` and `editor`), or a typed line has run since the last flush (`state_left`), and the flush clears all three and returns whether it ended something. A second path to the same end (play mode's quit, whose close stops again; a program's first lines can no longer call `stop()` and then raise, since the call ends them) finds nothing to end, so a line `before_exit` queued for the board stays queued. Putting the IDE's baseline back (handlers, mouse, input field, modules, picture, graphics, looping, volume, keyboard) is idempotent and happens every time. A close whose stop made the environment anew tells the open that follows, which does not make it again. The console's `reset()` (`ConsoleController:reset`) is the flush too, a program live or not (a running one is stopped, its `before_exit` called; with nothing live a `before_exit` a typed line set is removed, not called), then `love.audio.stop()`, the explicit silence, then the output and kept rows erased as Ctrl+L erases them, and the program's canvas cleared, then `Runtime reset for <project>. All files kept.` in the output, the one line on the screen, and `ConsoleController:reset` returns `{ scope = "runtime", project = <name>, snapshot = nil }` (the reset specification's IS4.1 and API4.1); called from code, `reset()` ends that code and returns nothing (design B, below); with an argument it is refused, since the reset specification's scoped resets are later work.

### A program that can act owns all input

The maintainer's ruling of November 17, 2026: "hide the console when any program
runs/all input is the program's while it runs". While the program whose route
holds the input can still act (`can_act` in `controller.lua`: an update or a
draw, a hook or a non-empty shortcut table on any channel, its own shown field,
or a serial handler), every key, text, pointer and touch event is the program's,
and what its chain leaves goes nowhere, with one exception below. The console's
field and cursor are hidden meanwhile (`Controller.program_owns_input`, which
`ConsoleView:draw` asks each frame; `UserInputView.field_hidden` renders the
status line alone and the field's rows background, while the notice band still
draws above the visible status line in `text` and `combined` modes). While the
field is hidden and the program shows none of its own, the output takes the
field's row and the status line goes to the screen's bottom, naming the project,
the file it runs from and "running" in yellow (see "The Output and Its Kept
Rows" and "The status line's colours and words" above). A program that wants
typing shows its own field, drawn over the console's. A program that can do none
of these has ended at its last line: the first event after that releases the
route (`release_keyboard_route`) and goes to the console, whose field shows
again; a finished program whose picture stays (`run_live`) counts as ended, so a
draw-once lesson goes on typing. A pause gives the input and the field back to
the console, and `continue()` gives them back to the program. The predicate is
asked as each event comes, before the program's chain; the hook table is the one
record of a program's own handlers (they are seeded there when the run begins).
The reserved chords are the gate's, untouched. The console's key card comes up
only while F1 reaches the console, so behind a program only while it is paused.
A key pressed while the input went back to the console during that press (the
program could no longer act) is the console's: its repeats and release go there.

The one exception, ruling 1.1: "the scrollback area is *visible* so it takes keys and mouse events that normally belong to it, if the program doesn't take these keys and events". A key press the program's chain leaves that is one of the output's scrolling keys (Ctrl+Up and Ctrl+Down, PgUp and PgDn, Home and End, Ctrl+PgUp and Ctrl+PgDn, as `consoleKeys.lua` names them; Home and End go to the oldest row and back, the field being hidden, as Ctrl+PgUp and Ctrl+PgDn do) scrolls the output (`ConsoleController:output_key`), and a wheel event it leaves scrolls it three rows a notch (`output_wheel`, which the console's own wheel uses too). "Takes" is per event: a key press is taken when a shortcut or a hook for it returns truthy, or a shown field takes it, and a program's own `love.keypressed`, seeded as a hook, takes every key press, so behind it only the wheel scrolls; a wheel event is taken the same way by a wheel shortcut or hook, its own `love.wheelmoved` among them. No other key of the console's acts behind a program.

A draft typed before the program took the input is kept and not shown: while no field is drawn the status line is the screen's last row whatever the draft's rows, and the draft is back with the field.

### The screen's modes and their keys

F12 is a reservation (`src/model/input/reservedKeys.lua`, `screen_mode`): in the console, idle, running or paused, it moves the screen to its next mode (`ScreenModel:step`, `doc/development/drawing_system.md`); in the editor, in a packaged build and between a pause's request and the pause (`snapshot`, whose `ScreenModel:pause` saves the mode `continue()` brings back) it does nothing. Like every reservation it consumes its whole press, does nothing under a key card, and acts once a press. The console's key card lists it, idle and live, as "screen"; the editor's card does not.

The full picture has no field, and when F12 brings it up with no running program (`not Controller.program_owns_input()`) it shows the status line (`picture`, `view>F12`, the console's dark ground at opacity `screen.combined.ground`) on the last row for two seconds from the first frame drawn (`ScreenModel.BANNER_SECONDS`, `ScreenModel:banner_drawn`, `ScreenModel:pass_time`, `ConsoleController:picture_status`, `ConsoleView:draw`). While it shows and no program that can act holds the input (`picture_only` in the gate, `controller.lua`: not a packaged build, which has no console, the mode is `picture`, the state is not `editor`, and `Controller.program_owns_input`, item 1's `can_act`, is false), any key but a modifier or a lock alone goes back to the text (`ScreenModel:back`), whatever showed before the picture, and is the IDE's for its whole press; a program that can act no more is found ended at the entry of every event the gate takes, keys, text, buttons, moves, the wheel and touches alike, before the reservations, the key card and the way back (`found_ended`, through the gate's `enter`, so that nothing that takes an event can do so ahead of it), and a picture on show stays on show through that end: the end itself sets the screen from what shows as it is made (`end_naturally`'s `shown`), at once or once the frame's update returns, where the click timer's derived clicks come, after the event that found it; a derived click may find the end and never goes back from the picture. Known limit: an end found inside a held `End` (which the event pump never does for a person's input) waits for the hold's close, and Ctrl+R in between still finds the run live and starts it again, so that a key or a click goes back and F12 steps from the picture; a reserved chord acts as well, so Ctrl+T leaves the picture for the editor and Ctrl+Escape quits. The key's text goes nowhere, by two rules that need no guess about whether a key or its text comes first: every text that comes while the full picture shows is dropped, which is the key's own text on a Compy, where text comes first; and after the key's press a text is dropped only if it is the key's own character, whatever its case, before the key's release and before any other key's press or repeat, which is the desktop's order (`swallow_for`, `own_char`, which knows a key's own character, the space's and the keypad's). Any other text is typed. A key held from before the picture repeats into nothing while the picture shows: a repeat goes to the console only while its draft can be seen. A shifted character other than a letter's, such as Shift+1's `!`, slips through on a desktop; a Compy, which sends the text first, never shows it. Between a pause's request and the pause (`snapshot`) neither F12 nor a key changes the mode, which the pause saves for `continue()`. A mouse button or a touch goes back the same way, and its release goes nowhere (`hold_press` records it in `receivers` as going to no receiver, as under a key card; a key that goes back is recorded there as the IDE's, as a reserved chord's key is), and a button's moves go nowhere until its release, also into a program resumed meanwhile (`back_buttons`), or until a move finds it up, the window loses focus or the same button is pressed again, any of which ends a release that was lost; the wheel, a move and the derived clicks do nothing there, so the hidden output does not scroll. A program that can act keeps every key and click on its picture, and F12 is its way back.

The console's status line names the mode with the key that steps it, `text>F12`,
`comb>F12` or `view>F12`, eight columns each (the maintainer's rulings of
November 19, 2026; `UserInputModel.screen_source`, `Status.mode`,
`Statusline:draw`'s `MODE_LABEL`), in its right block, packed to the right with
the rest of it: two columns before what follows it, or at the edge on the bare
line behind a running program (`ConsoleController:running_status`) or on F12
into the full picture (`ConsoleController:picture_status`) when nothing follows.
The line under a key card names no mode, since the card holds F12 back
(`KeyCardView:draw_cells`); the label is back once F1 is released. A program's
own field names no mode on its line (the maintainer's ruling of November 17,
2026: "when the user creates their own input widget, drop 'text' and
'running'"), which round j1 had put there. A pause whose program has drawn
appends ` (F12 shows the picture)` to the pause's message in the output, or
prints `F12 shows the picture` alone after a bare `pause()` or a handler error's
pause (`ConsoleController:suspend`, `messages.picture_hint`).

### A lifecycle call ends the code that made it

The maintainer's ruling of November 16, 2026 (design B): `stop()`, `reset()`, `run(...)`, `project(...)`, `close_project()`, `reset_scratchpad()`, and `edit(...)` when it must stop a program idle behind the console, called from a program or a typed line, end the code that made the call at once and are made once that code has returned to the IDE (`src/util/program_end.lua`). Each records one request and raises a private value, `ENDED`, which unwinds the calling code, the functions it was called from included. Every place the IDE calls into a program or a typed line counts the call and takes `ENDED` as no error, saying nothing: `wrap` in `controller.lua` (every handler, hook, shortcut and owed release, `love.update`, `love.draw`), `run_user_code` (a program's first lines, a typed line), `framework_before_exit`, the serial dispatcher, a field's parser and highlighter as the field renders (`End.counted`, in `UserInputModel:highlight`); `project_env.eval` runs its chunk directly without `pcall`, so `ENDED` unwinds through it naturally (and `util.eval.eval` still passes it on). Every place the IDE enters from LÖVE or starts a run holds the request (`End.held`: the route's handler wrapper, the update wrapper, both draws, the console's and a program's, `evaluate_input`, `run_project`), and the outermost of them makes it at its end, once, off the canvas and after the draw wrapper's `pop()`. So nothing after `stop()` in the same handler runs, and nothing a program does can undo the stop's flush. A typed `stop(); print(1)` prints nothing after the stop, and `r = reset()` assigns nothing: `reset()` called from code does not return, so the reset specification's API4.1 table reaches only the IDE's own call. A refusal is said at the call and ends nothing, the code going on: "Nothing is running." for `stop()`, an argument to `reset()`, a project name that cannot be one, every refusal of an `edit()` that would stop a program (`_edit_admit`), and every refusal of a run (`_run_accepted`, the file to run read as `ProjectService:run` reads it), each asked again when the call is made. A typed `run()` while a program runs or is paused is refused, "A project is already running"; a program's own `run()` replaces it, the stop and then the run as Ctrl+R makes them (a run is the program's when it is made deeper than the typed line's own code, `ConsoleController.typing`). The first request wins: the code after it never ran, and only the program's own `pcall` or `coroutine.resume`, which swallow `ENDED`, reach a second, which is dropped. A request made while a stop is under way, in `compy.before_exit`, ends the hook and is dropped: the stop goes on. A key or a click whose handler made a request goes no further: the console does not get it before the run ends. `pause()` is no such call: it pauses the program at the end of its frame, its code going on (`suspend_run`). Code the IDE calls from inside a program's own call, such as a field's callback during `compy.input.show`, ends at the request; the program's call it came from goes on to its end, and the request is made after it. Limit: a program's own `pcall(stop)`, a `pcall` around code that makes such a call, or a `coroutine.resume` of a coroutine that makes one, swallows `ENDED`, and its code runs on; the request stays and is made when that code returns to the IDE.

**`suspend_run(msg)`**: Requests a pause, for a program that runs or one idle behind the console that can still act (`program_owns_input`: one with only key handlers, say); with neither it does nothing. State → `snapshot` → `inspect` at the end of the frame's update. Handlers saved; default handlers restored temporarily. The console gets its mouse back and the program's is saved. The program's serial handlers wait too (`SerialPort:programPaused`, `programContinued` at `continue()`). A pause a program's first lines ask for goes on when the program then idles, and `continue()` resumes it idle. User can inspect and continue.

**`continue()`**: Restores project handlers and the program's mouse from the saved copies. State → the one the pause found the program in (`love.state.paused_from`: `running`, or `ready` for a program idle behind the console that can still act).

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
| `compy.terminal` | VT-100 terminal control (`gotoxy`, `clear`, `setEcho`); a `gotoxy` position outside the screen is taken to the nearest edge |
| `compy.screen` | Screen mode and notice band (`show(mode)`, `getMode()`, `showNotice(text)`) |
| `compy.graphics` | Extended graphics (`shape2d`) — `src/util/graphics/shape2d.lua` |
| `compy.fonts` | Font path constants (`mono`, `sans`, `serif`, etc.) — `src/util/namespace/fonts.lua` |
| `compy.input` | Text input widget surface (`show`/`hide`/`configure`/`clear`/`set_text`) — see [`user_input.md`](user_input.md) |

`compy.terminal` wraps the VT-100 terminal instance directly (the same terminal
that renders the console output), and is also exposed as the shorthand `tty`.
Projects can use it for text-mode output within their run context.

`compy.terminal.setEcho(on)` (also `tty.setEcho(on)`) takes one boolean `on`,
returns no values, and switches whether accepted console lines echo to the
output (`CanvasModel:echo` in `ConsoleController:_evaluate_input`). Echo starts
on, and a change takes effect on the next accepted line: turning echo off still
echoes the line that called it, and turning echo back on is silent. History,
printed output, refusals, and errors are unchanged. Every accepted run, stop (a
natural end included), `reset()`, and restart restores echo to on
(`ConsoleController:_restore_defaults`, called from `flush_program_state` and
the run seam in `_run_project`); `pause()` and `continue()` keep the run's
setting, and an idle console change holds until the next flush or run start.
Passing anything other than one boolean raises
`compy.terminal.setEcho: expects one boolean` at the calling line before
changing anything.

`compy.screen.showNotice(text)` takes one string `text`, returns no values, and
displays `text` in the console's notice band (`UserInputController:notice`,
orange on black, word-wrapped up to three rows with `…` on overflow), replacing
any previous message; `""` clears the band. After a non-repeat key press other
than a lone modifier or lock (`Key.is_lone`) acts in `handlers.keypressed`
(`src/controller/controller.lua`), a notice that has been drawn goes unless a
key card now shows (`UserInputController:dismiss_seen`); a notice created by the
press itself, by its text, or while hidden in `picture` mode stays until drawn.
A key or a character that reaches the console's own field still clears its
message before it acts, drawn or not, as for the field's other messages
(`ConsoleController:keypressed` and `:textinput`).
During a run, `ConsoleView:draw` draws the band directly above whichever status
line is visible — the program's own input field's status line when one is shown
(`love.state.user_input` outside `inspect`), otherwise the console's (or bare)
status line — in the `text` and `combined` modes; the `picture` mode draws no
band, and a notice still current on return to `text` shows there. Every accepted
run, stop (a natural end included), `reset()`, and restart clears the band
through `ConsoleController:_restore_defaults`; a pause leaves the band
untouched, and `continue()` keeps it. Passing anything other
than one string raises `compy.screen.showNotice: expects one string` at the
calling line before changing anything.

---

## Key Files

| File | Role |
|---|---|
| `src/controller/consoleController.lua` | Everything: env setup, project lifecycle, REPL eval, widget input API |
| `src/model/consoleModel.lua` | Model aggregate (input, editor, output canvas, project service) |
| `src/model/canvasModel.lua` | The output: the terminal grid, its kept rows, the scrolled view, the echo; and the program's canvas, kept apart (`doc/development/drawing_system.md`) |
| `src/model/screenModel.lua` | The screen's mode: text, combined or the full picture |
| `src/model/keptRows.lua` | The rows scrolled off the output's top |
| `src/model/project/project.lua` | `ProjectService` and `Project` — open/run/close, file I/O, filesystem mount |
| `src/model/io/redirect.lua` | Redirects `print()` output to the terminal |
| `src/view/consoleView.lua` | Top-level view compositor |
| `src/util/audio.lua` | `compy.audio` sound effect library |
| `src/util/namespace/fonts.lua` | `compy.fonts` font path constants |
