---
description: How text/keyboard and pointer input actually work — routing, the dispatch chain, and the mechanism behind each guarantee
status: active
audience: developer
authored: llm
reviewed: none
---

# User Input — Implementation Overview

Input handling in Compy has two mostly independent layers: **text/keyboard input** (the input widget instances used across console, editor, and projects) and **mouse/pointer input** (mouse/touch channels a project can hook, plus mouse interaction with the input widget itself). Both run through the same project-route dispatch chain (`ProjectInputController`, "Keyboard Handling" below) while a project runs; what differs per channel is only which argument names the combo trigger (see "Mouse Input" below). This doc covers both, with mode-specific notes where the behavior differs.

For the project-facing usage guide (examples, the `show()` config table, the submit lifecycle from a project author's point of view), see [Compy Input API](../../input_api.md). This doc is the "how it works under the hood" narrative — routing, the dispatch chain, and the mechanism behind each guarantee. For the two-layer `love.handlers.*` vs `love.<event>` wiring underneath the gateway (§"Dispatch chain" below), see [Event Dispatch Layers](event_dispatch_layers.md).

---

## Two surfaces, one widget

The project-facing API has **two named surfaces**, and a maintainer reading anything below should
know which one a symptom came from before reading further (`../decisions/input.md`,
`D-SIMPLE-SURFACE`).

- **The precise API** — `compy.input.*`: `show`/`configure`/`hide`, the callback table, the
  lifecycle flags, `shortcuts` and `hooks`. Everything else in this document describes it.
- **The simple API** — four names on `compy` itself:
  **`compy.ask(prompt, highlighter, text, cursor)`**,
  **`compy.on_answer`**, **`compy.on_key`** and **`compy.unask()`**. A program that only asks a
  question never touches the `compy.input` namespace.

**The simple surface is a wrapper, and that is the load-bearing fact.** `ask` drives **the same
widget** the precise API drives — there is no second widget, no second state and no second event
path, so every mechanism below applies unchanged to a question asked with `ask`. What `ask` does is
write the precise API's own fields on the project's behalf, remember what it overwrote, and put it
all back when the question ends. Implementation: `consoleController.lua`, `build_simple_surface`.

What one `ask` writes, and reverts:

| written | reverted to |
|---|---|
| the four lifecycle flags, all **on** — a question disposes of itself however it ends | whatever the project had seated |
| `callbacks.on_text_entered` — boilerplate that concludes with the text | the project's own callback |
| `callbacks.after_cancel` — boilerplate that concludes with `nil` | the project's own callback |
| `hooks.keypressed` — the key stub behind `on_key` | whatever was there (normally nothing) |

Content and prompt are **not** reverted: they are the user's, and restoring them would be `show`
undoing itself.

**Three details that are decisions rather than mechanics**, each with a failure mode worth
recognising:

1. **The stubs read `compy.on_answer` / `compy.on_key` when they fire; they never capture them.**
   The read goes through the **live project environment**, not through the namespace table the
   closure was built with — `table.clone` copies fields and shares the metatable, and the project
   env is cloned twice *after* `compy` is seated, so a captured table would be the pre-clone one.
   That is `compy.before_exit`'s shared-slot oddity, and this is the place it was not repeated.
2. **Whether a question is armed is read off the installed stub**, not off a boolean. A question can
   be lost without concluding — a project that calls `compy.input.hide()` itself never answers — and
   a flag that outlived it would restore a stale configuration over the *next* question.
3. **A collision raises rather than chains.** `ask` refuses if `hooks.keypressed` is already set or
   the project defines `love.keypressed`, and says so naming the precise API. Nothing is blocked by
   refusing: a program that wants both builds it with `show` and its own hook.

**`on_key`'s return value is the whole design.** The stub passes through everything that is not
reportable — a bare modifier, and any key arriving as text (a single-character key constant, or
`space`, with neither Ctrl nor Alt held) — and for everything else calls `on_key(key, scancode,
isrepeat)`, LÖVE's own argument list. **Truthy consumes; falsey falls through to the widget**, which
edits exactly as it always does. So `ask` holds no list of the keys editing owns: `backspace` still
deletes because the program declined it, not because the framework knew what `backspace` meant.
Repeats are delivered, like typing; `compy.input.fn.ignore_repeat` is the opt-out.

**`unask()` concludes nothing.** It disposes, restores and returns. `on_answer(nil)` means *the user
abandoned the question*, and a program withdrawing its own question already knows — a callback that
could not tell the two apart would loop for anything that re-asks from `on_answer`.

---

## Text Input Widget

> "What differs is the configuration: decoration (prompt), initial text and callbacks responsible for evaluation, highlighting, and actions on submit/cancel"

`UserInputModel` / `UserInputController` / `UserInputView` form a shared widget reused in three contexts: the console REPL, the editor input strip, and project-created widgets. The widget is always the same code; what differs is the host evaluator and the controller handling the submission.

### Data flow

```
LÖVE2D textinput event
  → love.handlers.textinput (gateway)
    → console/editor route (default handler):
        ConsoleController:textinput (dispatches by app_state)
          → editor mode: EditorController:textinput
          → console mode: UserInputController:textinput
            → UserInputModel:add_text
              → updates InputText (cursor-aware string)
                → view re-renders
    → project route (while a project is 'running'):
        ProjectInputController:textinput
          → the three-consumer walk ("Keyboard Handling" below);
            the terminal consumer is the same
            UserInputController:textinput/add_text path
```

A project hooks `textinput` either via `compy.input.shortcuts.textinput[combo]` /
`compy.input.hooks.textinput` (the shortcuts/hooks consumers of the chain) or by
defining its own `love.textinput` — the pre-API shape, kept working by a
compatibility path that reinstalls the captured function as the seeded hook when
no explicit `hooks.textinput` is set (see "Keyboard Handling" below) — reaching
the widget is what happens only when nothing upstream consumes the event.

Text characters arrive via `love.textinput` (OS-processed, handles IME and layout, fires only for character-producing keys). Raw key events arrive via `love.keypressed` — but `keypressed` is **not** restricted to non-character keys: LÖVE2D fires it for every physical key, textual or not. Pressing `q` fires both `keypressed('q')` and `textinput('q')`. (LÖVE2D does not guarantee the relative *order* the two arrive in for the same physical key.)

The "keypressed = control channel, textinput = character channel" split used throughout this doc is therefore **compy's own convention, not a LÖVE2D guarantee**. Nowhere does compy's `keypressed` code filter out or ignore textual keycodes — it simply never gives `k` a match that means "insert this character" (see `UserInputController:keypressed` below: every branch checks `k` against a fixed set of named control keys, or a modifier + letter combo used as a *shortcut*, e.g. Ctrl+C). A bare `keypressed('q')` with no modifier held matches nothing and falls through untouched. All literal character insertion (`UserInputModel:add_text`) is reachable only from `textinput` handlers, plus two `keypressed`-triggered paths that move **existing** text (not the pressed key) into the model — clipboard paste (Ctrl+V) and `load_selection` (Escape, editor mode, loads buffer text into the input).

Every channel carries LÖVE's own argument list end to end, unchanged. LÖVE calls `love.handlers.keypressed` with `(key, scancode, isrepeat)`; the gateway keeps all three, and the project route forwards all three to every consumer — shortcut, hook and widget alike. A handler written as `love.keypressed(key, scancode, isrepeat)` therefore behaves identically once it is seeded as a hook, which is the point (D-LOVE-ARGS).

The console/editor route is the one place that narrows: its default handler accepts the arguments and calls `CC:keypressed(k)` (and from there `EditorController:keypressed(k)`), so console/editor mode dispatch sees neither `scancode` nor `isrepeat`. It has no widget step to thread them to — see "Keyboard Handling".

Shortcuts dispatch (the `compy.input.shortcuts` combo tables) does not gate on `isrepeat` — see "Key state" below.

### Multiline input

The input is not single-line. `Shift+Enter` inserts a newline (`line_feed()`). The cursor model tracks both line and column. Lines are stored as a `Dequeue<string>` in `InputText`. The view wraps long lines at `drawableChars` width (same wrap machinery as the editor's `VisibleContent`).

LÖVE has no multiline-text concept of its own; it only delivers discrete `textinput`/`keypressed` events, one character or one key at a time. Assembly is entirely compy's own: `UserInputController:keypressed`'s `newline()` local (`userInputController.lua:568-574`) calls `input:line_feed()` whenever Shift+Enter is detected — **unconditionally**. There is also no separate "keystroke assembly" buffer: `textinput` mutates the model's persistent text immediately and continuously, and Enter (a `keypressed`, not a `textinput`) is a purely discrete control signal that reads whatever the *current* buffer state is (`get_text()`) at the moment it fires. Nothing replays or buffers a keystroke history to reconstruct the submitted text; the live model state *is* the submitted text. True uniformly for console, editor, and the project's input widget (all three read `get_text()` at submit time); search has no evaluator/submit concept at all — its Enter jumps to the currently-selected result, not the typed query.

**`set_text` normalises both spellings, and the cursor is the reason.** `UserInputModel:set_text`
accepts a string or a list of line strings, which the project-facing guide documents as one shape
with two spellings, so both are normalised identically: `string.lines` is polymorphic over
`string | string[]` and delegates a list to `string.split_array`, which splits each element and
explicitly preserves empty ones. `set_text("a\nb")`, `set_text({"a\nb"})` and `set_text({"a","b"})`
all produce the same two lines and the same cursor.

**The rule is the same one the UTF-8 sanitisation on this path serves**, and it is ratified as
**D-CONTENT-NORM** (`../decisions/input.md`): the cursor addresses content as `(line, column)`, so
content that is not normalised makes that address ambiguous. Invalid bytes leave a column's *length*
undefined; a newline inside a line leaves its *position* undefined — the caret could sit past a line
terminator. Both are normalised at the same seam for the same reason, and neither is a convenience.

**Structurally this is one path, not two branches that agree.** `normalized_lines` takes either
spelling and returns the lines; `set_text` stores them and seats the cursor. The decision's
structural half is that per-spelling branches which each decide what to normalise **drift apart** —
which is precisely what had happened, UTF-8 being sanitised on both spellings and newlines on only
one. An unsupported value normalises to nothing and leaves content standing, as both branches did.

**A dead cursor call went with the unification.** The string branch called `_update_cursor(true)`
and the list branch did not, an asymmetry inherited from the commit that first wrote the function
(`472c6bba`) — where `jump_end()` already ran unconditionally afterwards. `_update_cursor` sets
`cursor.c` from the line at the *old* cursor index in the *new* text and `cursor.l` to `#t`, so its
result is incoherent by construction, and `init_visible` plus `jump_end` then overwrite both the
cursor and the visible range it moved. The call had **never** had an effect on this path, which is
why the branch lacking it behaved identically. Deleted at `BUG-02-01`, mutation-tested first.

**`_update_cursor` itself stays, and it is not sound** (corrected 2026-09-01, same day: an earlier
version of this paragraph said `_set_text_line` and `clear_input` "call it live, and there the line
it reads is the line it just wrote" — both halves are wrong). Its intent is *seat the caret at the
end of the content*, which it satisfied when the input was single-line and `self.entered` was a
string; the multiline migration made it index a list and measure `t[cl]` — the line the caret was
on — while setting `.l` to `#t`. `_set_text_line` writes line `ln`, which need not be either.
Today nothing observes this: `_set_text_line`'s call is guarded by `if not keep_cursor` and all
seven of its callers pass `true`, so it is unreachable, and `clear_input`'s content is empty, where
every line measures zero. Filed in `../technical_debt/input.md`, *"`_update_cursor` measures the
column on the wrong line"*, with the repair-vs-delete call left open.

**The list branch did not always split.** Until 2026-09-01 it stored each element verbatim, so
`set_text({"a\nb"})` produced one line holding a raw newline that the model counted as an ordinary
character — three characters long, caret positions `1..4`. The defect was **pre-existing** (at this
branch's base the list branch is `InputText(text)`, with no split and no sanitise) and unreachable
from in-tree code, every caller passing a raw string or `string.lines(…)`; what this feature added
was the per-element sanitise pass and the surface that let a project reach the branch at all. It is
recorded because a reader meeting the old shape in an older tree needs to know why the two branches
no longer differ. The `add_text` path never had the split, having normalised with `string.unlines`
at the controller before it reaches the model.

The input view height is `input_max = 14` lines. This is a display limit only — the model can hold more lines, and scrolling within the input works normally. In the editor context this becomes relevant when loading a monster block: the editor's buffer viewport is `LINES = 16`, a **separate** limit from `input_max`, so a block can exceed the 14-line input strip — all content stays in the model, but only 14 lines are visible at once. **Open:** `input_max` (14) and `LINES` (16) currently differ, and whether 14 or 16 is the correct monster-block threshold is **not yet settled** — reconciling them is a pending review item (see `editor.md` — *`input_max` vs `LINES`* and *Monster Blocks*).

### Selection

Text selection works across lines. `Shift+arrow` extends selection; releasing shift releases it. `UserInputController.disable_selection` suppresses selection, and it is a **constructor argument, set per instance**: the console's widget is the only one that leaves it unset (`consoleController.lua:44`). The editor's input and search instances (`editorController.lua:12,16`) and **the project's widget** (`consoleController.lua`, `build_input_widget` — the instance published as `love.state.user_input_controller` for the length of a run) are all constructed with it — the editor because it uses its own block-level selection model rather than character-level selection in the input.

Mouse click on the input widget (translated from screen coordinates to input grid via `_translate_to_input_grid`) sets the cursor position, and drag extends selection. There is one `UserInputController` class and the project route passes the `love.state.user_input_controller` instance as its widget, so there is no project-specific translation path — but **the translation is reached only by the console's widget**, because every mouse entry point returns immediately on `disable_selection` (`userInputController.lua:772,789,803,818`) and every other instance sets it. A project's input widget therefore does not take a click to the cursor at all, and did not at this branch's base either. The coordinate translation is bottom-relative: line 0 is the bottom line of the input, which is non-obvious.

### Error state

When an error is set on the model (`set_error()`), the input is visually locked: text input and most keys are ignored until the error is cleared. Cleared by: Enter, space, or arrow keys. This is used for parse errors, runtime errors, and validation failures.

### Evaluator and validation

Each `UserInputModel` has an `Evaluator` that runs on submit:
- **Console**: `LuaEval` — metalua parse, validates Lua syntax before accepting the submit
- **Editor input (Lua file)**: `LuaEditorEval` — same as LuaEval but adds 64-char line length validator
- **Project widgets**: the internal plain evaluator (`Evaluator.plain`, chosen at
  construction) plus project callbacks for validation and display
- **Search**: `nil` evaluator (search input is free text, no validation)

**A project supplies functions; it never supplies the evaluator.** The two are easy
to conflate and the distinction is enforced, not merely stated: there is no
`evaluator` key on `show`/`configure` — the config table is closed and would raise —
`set_eval` is not on the `compy.input` surface, and `consoleController` **withholds**
`InputEvalText`, `InputEvalLua`, `ValidatedTextEval` and `LuaEditorEval` from
`project_env`, which starts as a clone of the application environment carrying them.
What a project configures is the `validator` (runs at submit, receives `string[]`,
returns `true` or `false, Error[]`) and the `highlighter` (display only). The
evaluator decides what a submit *means* for the widget; those two are the project's
hooks into it.

Host evaluators can validate during editing. The project widget's public
validator runs at submit and receives `string[]`; it returns `true` or
`false, Error[]`. `LuaHighlighter`, `LuaSyntaxValidator`, and
`LineValidators` are the only evaluator-derived helpers exported to a project.

### Cursor manipulation and "reset" — three API layers, now all connected

Cursor access exists at three layers. **Model** (`UserInputModel`) has the full primitive surface
(`cursor_left/right`, `move_cursor`, `jump_home/end`, `jump_line_start/end`, `get/set_cursor_pos`,
`set_cursor(c)`) — used internally by the model's own `keypressed` handling in response to
arrow/Home/End. **Controller** (`UserInputController`) exposes a narrower passthrough plus a
clamped 2D mover: `get_cursor_info`/`get_cursor_pos`/`set_cursor(Cursor)`/`jump_home`/
`set_cursor_pos(line, col)` — the last one (`userInputController.lua`, `set_cursor_pos`) computes
its own clamp against line/text length rather than relying on `move_cursor`'s
fallback-to-previous-position behaviour. **`compy` (project-facing)** now has its own surface on the input widget:
`compy.input.get_cursor()` / `set_cursor(line, col)` / `get_text()` / `set_text(text[, keep_cursor])`
(`consoleController.lua`, `build_widget_api` — named rather than cited by line, which drifts) —
**the two reads return `nil` while hidden** (a plain "nothing to report" read, not a refusal, so
neither warns); `set_cursor`/`set_text` no-op **and warn** while hidden. `get_text` answers one
string with `\n` between lines — `on_text_entered`'s spelling, and the one `set_text` takes back
unchanged; `''` when the widget is shown and empty, which is how a project tells *nothing typed* from
*nothing to report*. **It is the only read of the content outside a submit**, and until it was added
(2026-09-03) there was none: the surface wrote content and never read it, so a project could not
save what the user had typed.

There are four call sites that manipulate the cursor programmatically (i.e., not as a direct
response to a cursor-movement keypress): two in `editorController.lua` — `load_selection`
(`:590-604`, reads/restores the cursor via the **controller** API to preserve the caret across an
insert) and `reject_oversized` (`:628-633`, called from two live submit paths, jumps the cursor to
a rejected block's start via **`input.model:move_cursor` directly, bypassing the controller**) —
one in the model itself, `_apply_eval`, which seats the caret on the error position when an
evaluation is rejected, and the project-facing `compy.input.set_cursor`/`set_text` above. Console
and search never touch it programmatically.

**A separate population writes the cursor's fields directly**, bypassing every mover above, and a
sweep over cursor semantics needs both lists: `_update_cursor`, `_advance_cursor` and
`insert_text_line`. The last is the one on a hot path — it sets `self.cursor.l` unvalidated and runs
on **every Shift+Enter** (through `line_feed`) and on **Ctrl+D** duplicate-line, where the other two
are reached rarely or not at all. The census above is *callers of the cursor API*; this is *writers
of the content*, and a site can be neither, either or both. Enumerated with the case for reviewing
them in `../technical_debt/input.md`, *"`_update_cursor` measures the column on the wrong line"*.

**`_apply_eval` is the site that converts units, and it is the reason the census is worth keeping
accurate.** It is fed by the Lua parser, which reports an error column as a **byte** offset, while
every cursor position in the input subsystem is a character position — so it converts at the door
(`char_col`) rather than handing the raw value on. It was missed by a sweep that enumerated
everything *reading* the cursor bound and not everything *feeding* it; see
`text_encoding.md`, *"Byte offsets arrive from outside; convert them at the door"*, and the debt
register's error-highlight entry
for the other consumer of the same value. `UserInputModel:set_cursor(c)` is a raw, **unvalidated** assignment
(`self.cursor = c`) — safe because every caller supplies a pre-validated `Cursor`; the project path
instead routes through `UserInputController:set_cursor_pos`, which clamps rather than trusting the
raw model setter with an arbitrary project-supplied pair.

**An initial cursor position — one of the setup parameters the widget was required to accept,
alongside initial text, highlighter, validator and prompt label — is implemented at the controller
layer, not the model's.**
`UserInputModel.new(cfg, eval, custom_label)` (`userInputModel.lua:45-63`) still hardcodes
`cursor = Cursor()` — always `(1, 1)`, no cursor constructor parameter — but an activation
(`open_widget`) applies a `cfg.cursor = {line, col}` via `set_cursor_pos` after `text` is applied.
A forced `show` takes that same path, so it seats `cursor` like any other activation; repositioning
a session you are *not* re-activating is `compy.input.set_cursor`'s job.

"Reset the widget" is four bespoke, mutually inconsistent mechanisms, not one shared primitive:

- **console** — Escape and Ctrl+Q reset content and keep history, Ctrl+Shift+R wipes both, and
  Ctrl+L clears the terminal only;
- **editor** — Ctrl+W, content only, with Escape repurposed for `load_selection`;
- **search** — its own `clear()`, which reaches past its controller straight into
  `self.model.input:clear_input()` and skips `clear_error()`. Harmless while search has no
  evaluator, so no error can be set in the first place;
- **a project** — no single call. `compy.input.clear()` empties content and cursor and
  `configure{ prompt = … }` sets the prompt, but nothing combines them into a session reset.

Carried as-is; not touched by this pass.

---

## Keyboard Handling

The project route runs a per-event chain, a dumb three-consumer walk,
each consumer tried only if the previous one returns falsey —
`shortcuts[event][combo]` → `hooks[event]` → the widget — stopping at
the first that consumes. Enter and Escape are ordinary participants in
that walk, shadowable like any other combo (see "Submit and cancel"
below); the widget's own participation is decided by its *shownness*,
not a return value, with the hidden-check *internal* to the widget
itself.

### Dispatch chain

```
love.handlers.keypressed (k, scancode, isrepeat)
  → global shortcuts — controller.lua
    → love.keypressed — the active route
      ├─ console/editor (the default handler):
      │    → input widget shown (except inspect):
      │        UserInputController:keypressed
      │          (k, scancode, isrepeat)
      │    → else ConsoleController:keypressed
      │        → if editor state: EditorController:keypressed
      │        → else: console key handling
      │          → history navigation (PageUp/Down)
      │          → UserInputController:keypressed
      │          → Enter → ConsoleController:evaluate_input
      └─ project run: ProjectInputController — the free function
           `dispatch(shortcuts, hooks, widget, event, trigger, ...)`
           (projectInputController.lua), same shape on
           keypressed/keyreleased/textinput:
           1. compy.input.shortcuts[event][combo]  (project
                shortcuts; per-event tables, normalising —
                D-COMBO-TABLES)
           2. compy.input.hooks[event]  (one hook per event,
                seeded once at activation with the project's
                captured love.* handler where unset — no
                per-event precedence re-resolution — D-HOOKS-SEEDED
                revised)
           3. the widget (UserInputController) — terminal;
                consumes whenever it is shown (its own internal
                `self.shown` flag via `is_shown()`), skipped
                (and reports not-consumed) when hidden
         Truthy at shortcuts/hooks, or shown at the widget,
         consumes (stop); falsey/hidden falls through — and a
         SEEDED hook (one captured from the project's own
         love.*) consumes unconditionally, D-HOOKS-SEEDED's
         2026-09-08 amendment.
           → nobody consumed: back to the console's own handler
             for that channel, unless the project owns
             love.draw (Controller._defaults[event], gated on
             user_draw; the two derived clicks have no console
             default and fall through to nothing)
```

**The last line is a repair, not a tier.** The walk is still three consumers; what changed is that
its verdict is now read at the binding site instead of discarded, so a project that consumes nothing
leaves the prompt below it live — which is what the PR base did per channel. The gate, the
ten-against-twelve caveat and the one deliberate narrowing are in
[`event_dispatch_layers.md`](event_dispatch_layers.md), *"What becomes of an event nobody
consumed"*; the regression it pays is [`../technical_debt/input.md`](../technical_debt/input.md),
`T-ROUTE-EATS-UNCONSUMED`.

`app_state == 'starting'` is never observed by any input path: `main.lua`'s `love.load()` sets it, then flips it to `'ready'` a few lines later — both synchronously, before LÖVE's event pump runs, so no `love.handlers.*` entry point can ever see the `'starting'` value.

Global shortcuts are answered in `love.handlers.keypressed` before anything reaches the active route's controller. They live in `RESERVED` (`controller.lua`, in `setup_callback_handlers`): a **second, privileged combo table** keyed per event, structurally separate from a project's `compy.input.shortcuts` — same shape, consulted before any route exists, never overridable by one, and never consuming (`decisions/input.md`, D-RESERVE-TABLE). Its keys are canonical combo strings: `ctrl+pause` suspends, `ctrl+q` quits the project, `ctrl+s` stops a run, `ctrl+shift+r` resets the application, `ctrl+alt+r` restarts the project, `ctrl+t` quick-switches between run and edit, `ctrl+alt+p` / `ctrl+alt+shift+p` start and stop the profiler, and bare `f10` cycles the FPS-overlay corner. `ctrl+escape` (quit) is the one reservation living on the release side, in `RESERVED.keyreleased`, not keypressed. Each entry is a function that also checks the state it applies in — the project- and console-management ones no-op in playback (`cfg.mode == 'play'`), the profiler three require a profiling build — which is why the project guide's table carries a "when" column.

Each of these matches its modifier set **exactly** — the modifiers it names held, and no other (`decisions/input.md`, D-EXACT-RESERVE). Since a reservation is looked up by the canonical combo string built for the event, that exactness is a property of the representation: a string equality cannot tolerate an unnamed modifier. "Intercepted" describes what the gate may *claim*, not what passes through it: every keypress enters here, and one the gate does not claim is forwarded to the route unchanged, exactly as a claimed one is (the gate consumes nothing — see below).

Ctrl+S in the **editor** shows both halves of that. The chord reaches the gate like any other; the gate declines it — Ctrl+Shift+S because the modifiers do not match the reservation, plain Ctrl+S because the reservation acts only while `app_state == 'running'` — and forwards it to the route, where `ConsoleController` hands it to the editor and `EditorController:_leave_keys` decides: Ctrl+Shift+S leaves the edit, and bare Ctrl+S reaches the editor and **nothing acts on it** — the upstream editor rework deleted the close and put its checkpoint on Ctrl+K, so the key is **unclaimed** rather than reserved (`../decisions/input.md`, D-EXACT-RESERVE's 2026-09-05 amendment). Deciding that inside the route is the point: it is the editor's business, and the gate has no opinion on it. None of these consume the key: it still reaches the active route afterward (§6.3 non-consuming shortcuts).

The gateway (`love.handlers.*`) routes on the **active route** and nothing else: widget presence is not a routing condition, so the active route's controller always receives the event. The project route runs the three-consumer walk above: the project's captured `love.*` handler auto-provisions as the seeded hook (once, at activation — seen even while the widget is shown, only when the project set no explicit `hooks[event]`; an explicit hook always wins), **consuming its channel** where an explicit hook would fall through on falsey (D-HOOKS-SEEDED, *"a seeded handler consumes"*), so the widget below a captured handler receives nothing, and the widget is the terminal consumer with its hidden-check *internal* (`is_shown()` reads a strictly-internal `self.shown` flag; the widget no-ops while hidden, so a hidden widget mutates nothing without any external gate). The console route reaches its widget by a plainer path: each console channel forwards straight to `ConsoleController`, which calls its own widget instance (`consoleController.lua`, `textinput` / `keyreleased`) — it consults neither `love.state.user_input` nor the widget's shownness, because it owns that instance outright. The widget is never a routing destination of the gateway and never the active route.

**One lifetime for every channel the project route occupies.** Keyboard, text,
pointer and the derived clicks are installed together at run start
(`occupy_input`) and released together at the project's stop, when
`stop_project_run` reinstalls the console's own handlers through
`set_default_handlers`. The `'running'` → `'project_open'` transition releases
nothing: a non-blocking project that returns (no `update`/`draw` hooked) drops
to `'project_open'` and keeps every channel, so its widget's submit/cancel and
any pointer hook keep working.

`Controller.release_keyboard_route` exists for one case only — defensive cleanup
when a project raises at top level (`consoleController.lua`, `run_project`'s
failure branch). `occupy_input` is only reached after a successful top-level
run, so in that branch there is usually nothing to disconnect; it is not a step
of the normal lifecycle.

`Controller.user_is_interactive()` — `love.state.user_input ~= nil or
user_pointer`, the latter set when a project installs any pointer/click handler
and reset in `set_default_handlers` — gates exactly one thing: `love.quit`
treats `'project_open'` **plus** interactivity the same as `'running'`, so
Ctrl+Esc stops the project back to the console instead of quitting the app. An
idle console reached through `'project_open'`, with neither a widget nor a
pointer hook, falls through and the app quits.

`ProjectInputController` carries no per-event "am I still running?" guard: once
`stop_project_run` re-points `love.keypressed` and friends at the console, the
route is simply unreachable, so there is nothing to guard between events.

### inspect mode — the console owns every channel

**`inspect` mode overrides all of the above.** While `app_state == 'inspect'` (a paused/broken-into project), the console REPL owns every input channel and a project-set widget is not honoured, regardless of the routing described above. The mechanism is two things at once. Events: `ConsoleController:suspend()` physically swaps `love.keypressed`/`textinput`/`draw`/`update` back to the console's own functions through `set_default_handlers`, rather than short-circuiting them, so every `love.handlers.*` entry point reaches the console's default handler. Drawing: `get_user_input()` (`controller.lua`) returns `nil` unconditionally while `app_state == 'inspect'`, and both of its call sites are draw paths, so the widget is not painted either. The console additionally runs the *paused project's own* environment while inspecting: `get_effective_env()`/`evaluate_input()` select `project_env` (not the console env) when `app_state == 'inspect'`, so REPL input mutates the paused project's globals — a live debugger console, not a separate idle console. This behaviour is carried as characterized status quo, not a ratified contract — its shape under a future console/editor migration is an open call for the owner, not settled here.

### Key state: modifier reads and `combo_string`

Modifier state is read from the device. `Key.ctrl()` / `Key.alt()` /
`Key.shift()` (`util/key.lua`) are `love.keyboard.isDown` over the
left/right pair of one modifier, and they are the single source of
held-modifier truth in dispatch (`../decisions/input.md`,
D-ASK-THE-DEVICE). The framework maintains no held-key table of its own:
there is no accumulated model to go stale when a release never
arrives, and so nothing to reconcile against the device afterwards.

`Controller.combo_string(k)` serialises a key event into a canonical
combo string. It asks the device about each modifier row of
`Key.mod_triples` in fixed precedence order — `ctrl`, `alt`,
`shift` — prepends the generic name of every row that is
held, then appends the triggering key. Left/right fold to the
generic name here (`lctrl`/`rctrl` → `ctrl`, etc.), which is the
only place the fold happens at dispatch. A key with no held
modifiers serialises to just the key name.

```lua
-- left ctrl held, s triggers  → "ctrl+s"
-- left alt + shift held, f4   → "alt+shift+f4"
-- escape with nothing held    → "escape"
```

There are three rows, not four: `gui` is not a modifier
(`../decisions/input.md`, D-THREE-MODS), so `lgui`/`rgui` are
ordinary key names and reach the builder as triggers like any
other key.

`Controller.any_mod()` answers "is any modifier held at all" and is
the cheap pre-check the **triggerless** lookup runs first: a pointer
event has no key to name, so its shortcut is a modifier class and is
serialised with `'*'` in the trigger position — an unmodified
`mousemoved` therefore builds no string and allocates nothing.

Neither function takes a held-key table any more; both ask the
device themselves. The matcher is consequently **not** source-blind
— it cannot be driven by a synthetic table, and a test that proves
it patches `love.keyboard.isDown` instead.

Both surfaces are consumed by the free-function `dispatch`
(`projectInputController.lua`, "the three-consumer walk", called from
`ProjectInputController:_dispatch`), which serialises every
project-route keyboard/text event with `Controller.combo_string`
and looks the result up first against `compy.input.shortcuts.<event>`,
then `compy.input.hooks[event]`. Downstream consumers — shortcuts,
hooks, and the widget, project code included — receive LÖVE's own
argument list and nothing added (D-LOVE-ARGS); a consumer that wants
modifier state asks the device for it, and so does a project that
*renders* held state, since `love.draw` has no event argument to
consult (`examples/keyboard` draws shifted key labels this way).

**The clock this answers on, and the error it accepts.** A device
poll reports what is held *now*. LÖVE pumps the whole event queue
and then dispatches its events one at a time, so a poll taken while
dispatching the first of several queued events reports the state
after the last: with a press and a release queued in the same frame,
the combo built for the **press** can already see the key released.
That error is accepted (D-ASK-THE-DEVICE). It is bounded by one frame's
batch and gone on the next read, whereas a tracked set's staleness
persists until some later event happens to correct it — and the only
way to detect that drift is to compare the set against this same
poll, which makes the poll the authority either way.

The whole keypressed path hands the widget LÖVE's own
`(key, scancode, isrepeat)` — the widget is included by design
(one signature across the path) — but only on the project route;
see "Data flow" above for what the console route narrows. Dispatch
never gates on `isrepeat`, so a shortcut fires on **every** repeat
and not only on a fresh press. A binding that wants fresh-only
wraps itself: `compy.input.fn.ignore_repeat`
(`../decisions/input.md`, D-IGNORE-REPEAT) is a convenience for the
binding to apply, deliberately not a rule the tier enforces.

### Console-specific keys

- **PageUp/PageDown**: history back/forward
- **Up/Down at input boundary**: also triggers history navigation (handled as a "limit reached" return from `UserInputController:keypressed`)
- **Enter** (no shift): submit → `evaluate_input()`
- **Ctrl+L**: clear terminal output
- **Shift+Enter**: insert newline in input (multiline expression)

These are interpreted by `ConsoleController` itself (console-mode-specific dispatch), not the
generic controller — see the dispatch chain above: the console/editor route forks in
`ConsoleController:keypressed` before any of this runs.

**The "limit reached" boundary signal used to travel two independent paths; the return-value one is
retired (D-EDIT-CALLBACKS).** `cursor_vertical_move`/`is_at_limit` return `true` at a boundary, but
`UserInputController:keypressed` no longer threads that out as its own return value at all — the
method returns nothing now. The sole notification path, for every consumer, is the widget's callback:
the same boundary check calls `self.callbacks.on_limit_reached(dir, scope)` directly from inside the
widget itself (`emit_limit`, `userInputController.lua:554-557`, called from both `vertical()` and
`horizontal()`) — this is the `compy.input.callbacks.on_limit_reached(direction, scope)` widget
output a project sets via `show()`/`configure()` or a direct field assignment (a leaf-write on
`callbacks`, same as console/editor's own instances). **Console's history navigation** now goes
through this same callback: `ConsoleController.new` wires `console_widget.callbacks.on_limit_reached`
directly on its own `UserInputController` instance (`consoleController.lua:49-52`) to call
`history_back()`/`history_fwd()`, replacing the old `local limit = input:keypressed(k)` return-value
capture (`ConsoleController:keypressed` now calls `input:keypressed(k)` purely for its editing side
effects, return value unused — D-EDIT-CALLBACKS). Editor never needed the signal at all, since it
independently computes boundary state via `inputView:is_at_limit(...)` at the view layer.

**A project must be able to hear key events that produce no character in the widget** — Ctrl
combinations, navigation and function keys. **That requirement's keyboard exclusion is resolved as
of 1.0.0-rc20260712.**
Historically, while `love.state.user_input` was set, `controller.lua`'s
`handlers.keypressed`/`handlers.textinput` called *only* the widget — the project's own
`love.keypressed`/`love.textinput` were not called at all (binary, not partial). With the gate
removed, project key/text events always reach the project route (`ProjectInputController`); which
surface consumes them (the widget while shown, the project's handler — seeded as a
hook — while hidden) is the route's internal delegation, no longer a gateway drop. Mouse had no
such gate to begin with: at the time, `handlers.mousepressed`/`mousereleased` called the widget
conditionally but called the project's own handler **unconditionally**, regardless of widget
state — which is why touch and mouse needed no scope item of their own; only keyboard was ever
exclusively gated. That mouse-specific shape is itself now retired: pointer channels (mouse and
touch alike) have since been folded into this very same project-route dispatch chain as
keyboard/text — see "Mouse Input" below for the current routing and what changed.

### Editor-specific keys

See `editor.md` for full detail. Key differences from console mode:
- No history navigation (PageUp/Down scroll the buffer instead)
- Up/Down at input boundary moves buffer selection, not history
- Escape loads selected block text into input
- Ctrl+M / Ctrl+F switch modes

The difference is now **one** fork, not two. The **outer** fork is the ConsoleController/
EditorController split already covered above (console handles escape/history/Ctrl+L itself; editor
delegates to `EditorController:keypressed`'s own `edit`/`reorder`/`search` mode dispatch instead).

There used to be a **second, inner** fork: the shared `UserInputController:keypressed` branched on
`love.state.app_state == 'editor'` to decide whether to run its own Enter/Escape submit/cancel at
all. That fork was **removed** (2026-07-21) — a reusable input widget reaching up into global
app-mode to change its own behaviour was an abstraction leak (the widget could not be reasoned about,
or migrated, without knowing it was "the editor"). It is gone; `UserInputController:keypressed` now
runs **one uniform path** for every instance (see the shared-keypressed section below).

The editor's Escape→`load_selection()` (which just repopulated the input) is no longer protected by
a mode-gate inside the widget. Instead the editor **consumes Enter/Escape upstream**: each handled
branch of `EditorController:_normal_mode_keys`' `submit()` (plain Enter, Ctrl+Enter) and `load()`
(plain/Shift Escape) now calls `block_input()`, so `passthrough` is false and the shared widget never
receives that key — its uniform `submit_flow`/`cancel_flow` simply never runs for the keys the editor
owns. The one Enter variant the editor does *not* handle (Alt+Enter) does fall through to the widget's
`submit_flow`, harmlessly: the editor's own input instance sets no submit callbacks, so it is a no-op
(the same no-op console relies on). Search and reorg modes never reach `UserInputController:keypressed`
at all (see "Search" below and reorg's own `_reorg_mode_keys`), so they need no blocking.

Console's own always-shown instance is not blocked and does run the uniform `submit_flow`/`cancel_flow`
on its own Enter/Escape — harmlessly, since console sets no `before_submit`/`after_submit`/
`before_cancel`/`after_cancel` callbacks, so they are no-ops alongside console's own `evaluate_input`/
history handling. The project widget runs the flows for real (that IS its submit/cancel). So the
per-context behaviour that the old `app_state` fork encoded is now expressed honestly: the editor
consumes upstream, console/project set (or don't set) callbacks — no instance interrogates global state.

### UserInputController keypressed (shared)

`UserInputController:keypressed` handles the low-level input operations that apply regardless of which route is driving it (console, editor, or the project widget): removers (backspace, delete, Ctrl+Y delete line), vertical cursor movement, horizontal movement (Left/Right, Home/End, Alt+Home/End for line vs field boundaries), Shift+Enter newline (unconditional — see "Multiline input" above), Ctrl+D duplicate line, copy/cut/paste (Ctrl+C/X/V and Shift+Insert/Delete), selection management. It never inserts literal characters — see "Text Input Widget" above for why `keypressed` and `textinput` divide the work this way.

The body is a **single uniform sequence** (no `love.state.app_state` branch since 2026-07-21):
`removers → vertical → horizontal → newline → (modify if enabled) → copypaste → selection`, then
the lifecycle keys. **`modify` (Ctrl+D duplicate-line) is gated on a per-instance
`allow_duplicate_line` flag**, a constructor parameter
(`UserInputController(model, disable_selection, allow_duplicate_line)`),
set only by the editor's main input; console and the project widget leave it off. This is the honest
replacement for the old "editor branch runs `modify`" gate — a widget capability the owner enables at
construction, like `disable_selection`, not something the widget reads from global mode. (A future
combo-table owned by the widget would supersede the one-off flag — see `technical_debt/input.md`.)

Enter and Escape are ordinary keys handled at the end of
this same shared method, **uniformly for every instance**: `Key.is_enter(k) and not Key.shift()`
calls `self:submit_flow()`; `k == 'escape' and not Key.ctrl()` calls
`self:cancel_flow()` — see "Submit and cancel" below. **The guard is "Enter without
Shift", not "bare Enter": Ctrl+Enter and Alt+Enter submit too** (only Shift+Enter is carved out, as
the newline); likewise Escape-without-Ctrl cancels. This is a de-facto contract (D-DEFACTO-KEPT,
guard shape `return and not shift_held`), pinned by `tests/input/input_widget_callbacks_spec.lua`, the
`the same lifecycle on every route` group.
The widget's own
Enter/Escape handling IS the submit/cancel mechanism; there is no route-level interception above it.
Contexts that must NOT run the flows arrange it themselves: the editor consumes the key upstream
(`block_input()` in its own `submit()`/`load()`); console sets no callbacks so its run is a no-op and
its real work is `ConsoleController:evaluate_input` afterward; the editor's real submit is
`EditorController:_handle_submit`. No instance branches on global state to decide.

### Key release

On the **project route** keyreleased runs the same unified walk as keypressed/textinput
(shortcuts → hooks → widget-if-shown, DOM-style truthy-stops-propagation) — see the
dispatch-chain diagram above. The rest of this section concerns the **console route**, which this
pass deliberately did not touch (its legacy fork stays until the console/editor migration).

`keypressed`/`textinput` get careful three-way routing (console / editor / project); **`keyreleased`
gets route-level delegation but no editor fork.** Since 1.0.0-rc20260712, `ProjectInputController:keyreleased`
runs the same three-consumer walk as the other channels (shortcuts → `hooks.keyreleased` → widget), the released
key already absent from the held set. On the
console route the default handler forwards to a shown widget, else falls to `CC:keyreleased`
= `ConsoleController:keyreleased` (`consoleController.lua:1203-1206`), which **unconditionally** calls
`self.input:keyreleased(k)` — console's own instance — with **no `app_state == 'editor'` fork**.
`EditorController` and `SearchController` do not define a `:keyreleased` method at all. Net effect:
editor's and search's own `UserInputController` instances never receive `keyreleased`, under any
circumstance, even while their mode is the one actually on screen.

`UserInputController:keyreleased` only does two things: release character-selection on Shift-release,
and clear an error on Space-release. Checked whether the gap is currently observable: it isn't, but
only incidentally — editor's and search's own instances have `disable_selection = true` (so the
selection-release job is moot for them), and their error state is also clearable via **any**
`textinput` character (`editorController.lua:291-292`, unconditional clear-on-error, same as console),
which covers Space too, since Space is itself a text-producing key. So the missing fork happens to be
inert today, not silently broken — but it is still a real asymmetry against the otherwise-careful
routing discipline. Carried as-is; out of this pass's scope (console/editor's own `keyreleased`
routing is untouched by the input API).

### Search — a third widget instance, live only in editor/search mode

`EditorController`'s constructor (`editorController.lua`) wraps a `SearchController`/`Search` model
pair around a `UserInputController` instance of its own — a **third** consumer of the shared widget primitive, alongside console's and
the editor's main input. It is live only while `app_state == 'editor'` and
`EditorController.mode == 'search'` (Ctrl+F, see "Editor-specific keys" above), reached through
`EditorController:_search_mode_keys` for keys and `EditorController:textinput` for characters.

**It borrows the widget's model, not its behaviour.** `SearchController:keypressed` owns its key
handling outright and never delegates to its instance's `keypressed`: it drives navigation,
backspace/delete and Enter itself, and touches the instance only through `update_view` and
`add_text`. Consequences, in order of how likely they are to surprise a reader:

- The instance **never runs the shared submit/cancel flow**, which is why it needed no change when
  the `app_state` fork was removed.
- There is **no evaluator** — search input is free text — and **Enter returns the selected result**
  (a jump target `{block, line}`) up to `_search_mode_keys` rather than submitting what was typed.
  That is the same "keypress return carries a domain result" shape the shared widget's limit-flag
  return was retired for (D-EDIT-CALLBACKS). It stays: `SearchController` is a different class, out
  of the input API's scope (`technical_debt/input.md`).
- `SearchController` defines **no `:keyreleased`** — with the missing editor fork above, this
  instance never receives a release under any circumstance.
- `SearchController:clear()` reaches past its own controller into `self.model.input:clear_input()`,
  skipping the `clear_error()` that `UserInputController:clear` pairs with it. Harmless today (no
  evaluator, so no error can be set), but a layering inconsistency against every other reset path
  above. Its `keypressed` removers reach the same way.

No design document mentions this surface; it is live code the design corpus never covered, and this
is its first record in the permanent one.

### Future editor migration path (analysis, not scheduled)

The input API **(1.0.0-rc20260712)** makes a later editor migration possible; it does not migrate
the editor. The reusable
seam is the three-consumer dispatch shape — shortcuts, hook, widget — over plain tables and a widget
instance. It must not be mistaken for an instruction to share the project widget: console, editor,
and Search keep independent text, cursor, history, and view state.

A future migration should proceed by mode, preserving the controller that owns each mode's meaning:

1. Keep normal editor commands upstream. Enter/Escape and Ctrl+D already demonstrate this split:
   the editor consumes its own commands, while ordinary editing can reach its widget. Introduce an
   editor-local adapter to the shared dispatch shape only after naming the editor's shortcut and hook
   tables; do not expose the project `compy.input` table to editor internals.
2. Keep Search's controller-owned policy explicit. Its arrows, removers, Enter-to-jump, and Escape
   are search operations, not widget submit/cancel. A migration may use its widget for text editing,
   but must preserve that priority and the selected-definition jump. `tests/editor/editor_spec.lua`
   characterizes Ctrl+F, typing, Enter, and Escape through real editor entry points for this reason.
3. Keep reorder as an editor-owned, widget-free mode until it has an actual text-input requirement.
   It is not a missing widget route.
4. Do not add editor/Search `keyreleased` forwarding merely for symmetry. It is inert today; first
   identify a release-time consumer and specify its mode semantics.

This is implementation-derived migration guidance, not a new project-facing input API or a scheduled
refactor. Any migration must retain the editor-level characterization tests and add tests for each
newly adopted mode before replacing its current handler.

---

## Mouse Input

### Unified dispatch

Pointer events — `mousepressed`, `mousereleased`, `mousemoved`, `wheelmoved`, `touchpressed`,
`touchreleased`, `touchmoved` — now run through the very same project-route dispatch chain as
keyboard/text (`ProjectInputController`, "Keyboard Handling" above), not a broadcast. Previously
the gateway (`controller.lua`) called the widget unconditionally when present, then called
the project's own handler unconditionally as well — neither delivery order nor consumption could
be affected by the other, and nothing could stop the other from also seeing the event. Now the
project's *hook* runs first; the widget is the walk's terminal consumer, reached only if nothing
upstream consumed the event — so a pointer hook returning truthy now stops the widget from ever
seeing that event, the reverse of the old always-both delivery.

Pointer channels run the same three tiers as keyboard/text, with one combo vocabulary across all
of them (D-BUTTON-TRIGGER). `mousepressed`/`mousereleased` name the button as their trigger, serialised
`mouseN`, so `compy.input.shortcuts.mousepressed['mouse2']` is a right-click and `'ctrl+mouse2'` a
modified one. The channels with no discrete trigger — `mousemoved`, `wheelmoved`, touch, the
derived clicks — take modifier classes only; with no modifier held `find_shortcut` returns before
building a combo string (so an unmodified `mousemoved` allocates nothing) and the event goes to
the hook. A project's own `love.mousepressed` (etc.), if defined, is auto-seeded as that
event's hook exactly like keyboard/text (see "Keyboard Handling" above; the seeding is generic
over every bindable channel, `controller.lua`); an explicit `compy.input.hooks.<event>` write
still wins over the seed.

Pointer payloads are exactly LÖVE's own arguments, unchanged (`projectInputController.lua:30-39`),
as every other channel's are (D-LOVE-ARGS); a project that wants held modifier state inside a
pointer handler asks the device for it, the same way the matcher above does.

### Framework-level click handling

Click detection is framework-owned in `controller.lua`. The mouse gateway
tracks button 1 from press to release, rejecting movement of 2.5 pixels or
more on either axis while held. A valid release starts one fixed 0.4-second
pairing window. A second nearby valid release within that window emits
`love.handlers.doubleclick(x, y)` immediately and consumes the pair.
An unrelated second release completes the first single and starts its own
window. Otherwise `set_love_update` expires the pending single through
`love.handlers.singleclick(x, y)` using its saved release position.

Pointer motion of 2.5 pixels or more on either axis after release confirms
the pending single immediately at its saved release position. Raw
release delivery precedes a derived double-click. Route activation and
teardown clear pending press and click state, so a gesture stays with its
project. These derived events use the same gateway and route as native
pointer events. The public contract is in
[`Pointer and click hooks`](../../input_api.md#pointer-and-click-hooks).


`compy.singleclick` and `compy.doubleclick` — fields on the project's `compy` table that the old
framework code looked up and called directly — are **repositioned, not merely removed**. The firing
moved onto the `love.handlers.*` surface, where the click timer emits the derived event through the
gateway exactly as a native one arrives (`controller.lua`, the synthesis block); project consumption
moved to `compy.input.hooks` / `compy.input.shortcuts`. So they are ordinary
events: a project reaches them as `compy.input.hooks.singleclick` /
`compy.input.hooks.doubleclick`, through the identical dispatch chain as every other pointer
channel (`projectInputController.lua`, `dispatch`). **They are auto-seeded like every other
channel**: `_bindable` (`controller.lua`) and the seeder's own `EVENTS`
(`projectInputController.lua`) both carry the derived pair, so a project that defines
`love.singleclick` gets it seeded as `hooks.singleclick`, exactly as `love.mousepressed` is.
Keeping three hand-maintained subsets in step is precisely what failed before — a project
writing `love.singleclick` got nothing while the same project writing `love.mousepressed` got a
seeded hook — which is why seeding, teardown and dispatch now read one list.

Single-click confirmation waits for the pairing window, pointer motion
beyond the tolerance, or a subsequent click at another position. Double-click confirmation occurs on the second
release.

### Direct mouse events

`love.mousepressed`, `love.mousereleased`, `love.mousemoved`, `love.wheelmoved` still reach a
project the same way syntactically (projects set `love.mousepressed = function(...) end`), but the
mechanism underneath is the one described in "Unified dispatch" above, not a direct forward: an
unset `compy.input.hooks.<event>` is seeded from this function once at project activation, then
the seeded hook runs as an ordinary dispatch-chain participant — truthy consumes, falsy falls
through toward the widget. Error catching and canvas routing are no longer applied per handler:
`guarded` (`controller.lua`) wraps the point where the route is *entered*, so the whole walk —
shortcuts, hooks and widget alike — runs with the project canvas bound and one error handler above
it. (`ConsoleController:wrap_handler`, which used to do this per handler, is gone.)

### Input widget mouse

`UserInputController` handles mouse events on the input widget:
- `mousepressed`: translates screen (x, y) → input grid (col, line) via `_translate_to_input_grid`. Grid is bottom-relative (y increases upward in input space). Calls `im:mouse_click(l, c)` to set cursor.
- `mousemoved`: if left button held, calls `im:mouse_drag(l, c)` to extend selection.
- `mousereleased`: calls `im:mouse_release(l, c)` then releases selection.

Mouse events on the input widget are only processed when `disable_selection` is false. In editor mode, the input widget's controller has `disable_selection = true` — mouse interaction with the input strip is suppressed, and the editor uses keyboard-only navigation.

### Touch

Touch handlers (`touchpressed`, `touchreleased`, `touchmoved`) are stubbed with `-- TODO` in
`UserInputController` (no-op bodies) — but touch runs through the same project-route dispatch
chain as every other pointer channel ("Unified dispatch" above): a project's own `love.touchpressed`
(etc.), if defined, is seeded as `compy.input.hooks.touchpressed` exactly like mouse, and the widget
still counts as consuming the event whenever it is shown (the shown-widget rule applies uniformly,
regardless of what the stub body does).

---


## The `user_input` Widget — Input Perspective

### Widget lifecycle (introduced in an earlier build)

`UserInputController` for the project widget is created **when a project run starts** and
destroyed when it stops (`consoleController.lua`, `build_input_widget` / `destroy_input_widget`,
called from `run_project` and `stop_project_run`); while it exists it is stored in
`love.state.user_input_controller`. **Between runs that field is nil**, and every consumer of it
resolves it dynamically and guards. The same model, controller, view — and the widget's own
evaluator — are reused across every widget session *within* the run, so per-session allocation is
eliminated, which is what the NFR asks for (`decisions/input.md`, D-WIDGET-AT-BOOT as amended).

The run boundary, not the open boundary: `restart()` and the `Ctrl+T` quickswitch call
`stop_project_run` + `run_project` directly and never re-open, so a widget built at open would
survive into a restart. Destruction is bound to the **stop**, never to the
`running → project_open` transition — a non-blocking project (sapper) lives in `project_open` and
still owns its widget there.

Activation: `compy.input.show(config)` calls
`UserInputController:show(config)`, which sets
`love.state.user_input = { M = model, C = widget, V = view }`
and runs a view update. Deactivation: `UserInputController:hide()` (or
`hide()` on the `compy.input` table) sets `love.state.user_input = nil`.
`compy.input.*` is the sole project-facing input surface
**(supported since 1.0.0-rc20260712)**; the five legacy globals
(`user_input`, `input_text`, `input_code`, `validated_input`,
`write_to_input`) and the debug-only `astv_input` are
**(deprecated, removed in 1.0.0-rc20260712)** — gone from the
project environment, an ordinary `nil` field, no shim.

`show()` on an already-active widget is a no-op unless
`{ force = true }` is passed — and the suppression **warns**
(`Log.warn('UserInputController:show ignored — widget already
active...')`, `userInputController.lua:319-320`), matching the
framework's warn-don't-swallow convention. With `force`, the text
is replaced if a `text` field is in the config; otherwise the
existing text is preserved. No cancel sequence fires in either case.

### Dispatch while active

While a project runs, `compy.input.show(config)`/etc. drive the *same* widget instance and the
*same* routing already described under "Keyboard Handling" above. In short: the gateway always calls the active
route's occupant; the console/editor route's default handler goes straight to its own surface
(the console line, or the editor fork) with no widget test in front of it — widget visibility is
state on the widget, never a routing condition (`../decisions/input.md`, D-ROUTE-OWNS); the project
route always reaches the widget as its walk's terminal consumer. The widget view is drawn via `user_input.V:draw()` inside
the framework's `love.update` wrapping of the project draw function (`controller.lua`,
`set_love_update`).

There is no per-frame polling. When the user presses Enter, submit runs synchronously within that
one keypress — see "Submit and cancel" below for the exact order.

### Submit and cancel — widget-owned callback sequences

Enter and Escape are **ordinary keys handled by the widget itself** (D-EDIT-LIFECYCLE), with no
non-overridable interception above it: a project
shortcut registered on `'return'`/`'escape'` (`compy.input.shortcuts.keypressed['return']`, etc.)
wins over the widget's default, same as any other combo (**withdrawn guarantee**, deliberate — see
D-EDIT-LIFECYCLE's "Withdrawn guarantee" note in `decisions/input.md`; the gateway's power keys, Ctrl+Q etc.,
remain the real, permanent escape hatch, non-overridable by any shortcut — though only for the
chords they name exactly, per D-EXACT-RESERVE). Only once no shortcut/hook
consumes the key does the widget's own `UserInputController:keypressed` reach its lifecycle guard
(`Key.is_enter(k) and not Key.shift()` → submit; `k == 'escape' and not Key.ctrl()` → cancel — so
Ctrl+Enter and Alt+Enter submit too, only Shift+Enter is the newline), and only while the widget is
shown — hidden, the widget is skipped entirely by the dispatch walk.

**Submit** (`UserInputController:submit_flow`):

```
local draft = string.unlines(self.model:get_text())
if run_callback(self, 'before_submit', draft) then return end  -- truthy = veto
if self.model:get_text():is_empty() then return end
local lines = self.model:get_text()
if not gate(self.model, self.callbacks.validator, lines) then return end
local text = string.unlines(lines)
dispose(self, self.clear_on_submit, self.hide_on_submit)  -- the flags, BEFORE the callbacks
run_callback(self, 'on_text_entered', text)
run_callback(self, 'after_submit', text)                -- DEFAULT: no-op
```

**Every content-bearing callback receives the same joined string** (D-ONE-PAYLOAD): both submit
callbacks, and the three guards — `before_submit` here, `before_cancel` and `after_cancel` below —
which received **no argument at all** until 2026-09-09, so a veto could not look at what it was
vetoing. What tells the two submit callbacks apart is **when they run**, not what they carry;
D-PAYLOAD-SPLIT's shape distinction is retired. The `validator` keeps the lines: it runs per line,
and `LineValidators` reports which one failed.

**The payload is read once, above the disposal, on both verbs** — which is why a callback sees the
content the verb was about even when a flag has already emptied the widget. On the cancel side that
single read is also what `before_cancel` sees, so a veto and a following `after_cancel` agree on
what the draft was. `before_submit` is the one read taken before the empty guard, and the model is
re-read after it, so a `before_submit` that edits content still decides the submit.

**The callbacks run after the disposal, and receive the content as their argument** — `lines` is
captured above the clear, and `clear_input()` replaces the model's `entered` table rather than
emptying it, so the payload survives whatever the flags did. A truthy `before_submit` **vetoes** the
submit outright: nothing downstream runs, no flag acts and the text stays. It is a guard on
*whether to submit at all*; rejecting bad input with a message is still the `validator`'s job.

**What a verb leaves behind is four flags, one per (verb × outcome)** (D-LIFECYCLE-FLAGS):
`clear_on_submit` / `hide_on_submit` here, `clear_on_cancel` / `hide_on_cancel` below. They are
**project-owned and persistent** — seated in `configure_core` like every other project-owned field,
so `show` and `configure` both set them, set-if-given, and each applies until a call passes `false`.
The class default is all four **off**, so a widget nobody configured does nothing at all on either
verb; each owner seats its own with `seat_lifecycle()` at construction (the console
`clear_on_cancel`, the project widget `clear_on_submit` **alone**, the editor **none**).

**The project widget seats nothing on the cancel side, and that is a ruling about how defaults are
chosen** (D-LIFECYCLE-FLAGS, *"the least-destructive basis"*, 2026-09-09): a seated cell destroys on
behalf of a project that never asked, and five shipped examples were measured stranded by a seated
`hide_on_cancel` — each shows once at load with no re-show path, so one Escape ended the program's
only input surface. Escape is therefore **opt-in**, and the recommended way to ask is a `configure`
call before the first `show`, one flag per line.

**Disposal runs before the callbacks, and that placement is the design rather than an ordering
detail.** A callback is entitled to ask a new question, and a trailing hide would take it down —
which is what the shipped surface pushed onto the caller as `force = true` plus a disarm. Placing
the flags first also gives the edges for free: every early return above suppresses them, and a
callback that **raises** now leaves the widget **hidden**, because the raise unwinds to the route
boundary past callbacks the disposal already ran ahead of. That inversion is ruled and accepted
(owner, 2026-09-07), and `D-AUTO-HIDE` statement 5 is superseded on it.

**Cancel** (`UserInputController:cancel_flow`):

```
local draft = string.unlines(self.model:get_text())
if run_callback(self, 'before_cancel', draft) then return end  -- veto, skips everything
dispose(self, self.clear_on_cancel, self.hide_on_cancel)  -- the flags, BEFORE the callback
run_callback(self, 'after_cancel', draft)              -- DEFAULT: no-op
```

`before_cancel`'s return value is honoured the same way `before_submit`'s is: a truthy return
vetoes the whole flow (content and widget state untouched, `after_cancel` does not fire). What
Escape *does* is this instance's two cancel flags and nothing else: on the console it clears and
stays (`clear_on_cancel`), and on **both** a project's widget and the **editor's** it does nothing
at all — neither seats a cancel cell. On the project widget that is the least-destructive default
and the outcome is the project's to ask for; on the editor it is what makes the bare-Escape
fall-through harmless — the editor claims the key nowhere, the widget gets it and starts a cancel
that is deliberately empty (`../decisions/input.md`, D-EDITOR-KEYS row 2, and D-LIFECYCLE-FLAGS
statement 3).

`run_callback(self, name, ...)` (`userInputController.lua:438-442`) looks up `self.callbacks[name]`;
absent → no-op + debug-log. `self.callbacks` is the widget's own table, seeded at construction with
`DEFAULT_CALLBACKS` (`after_submit`/`after_cancel`/`on_limit_reached` = stay-open no-ops) and
re-seeded — never wiped to `nil` — on project teardown (D-ROUTE-LIFETIME; a nil'd `after_cancel` must
not silently mean "stays open forever" for the next project). For the **project widget**,
`compy.input.callbacks` **resolves to this exact same table** (owner ruling 2026-07-20, re-made
2026-08-27; resolved per access in `get_compy_input`, not captured) — a project's
`compy.input.callbacks.after_submit = fn` write lands directly on `self.callbacks.after_submit`, no
copy, no bridging. It resolves to the **current** widget, so a project sees one stable table for its
whole run and cannot observe the resolution. `highlighter` lives in this table too, and the
widget's evaluator **resolves** the slot rather than holding a copy of it
(`UserInputController:bind_highlighter`) — see "One home for the highlighter" below.
Console/editor set their own instance's `self.callbacks.X` directly (they are trusted host code, not routed through
`compy.input` at all — see `consoleController.lua:49-52` for console's own `on_limit_reached` wiring).

A project wanting "ask once, then hide" sets `hide_on_submit`; it is a flag rather than a
hand-written callback precisely so that a project setting its own `after_submit` cannot silently
lose it (D-LIFECYCLE-FLAGS, "Why flags rather than callbacks").

`compy.input.hide()` (the programmatic path) fires **no** cancel sequence — cancel is the
user-facing Escape path only.

The `before_*`/`after_*` hooks and the widget-output keys (`on_text_entered`,
`on_limit_reached`, `validator`, `highlighter`) are **one surface under two spellings**:
`self.callbacks` inside the controller, `compy.input.callbacks` to a project. The four
output keys are exactly `consoleController.lua`'s `CALLBACK_KEYS`. See "Keyboard
Handling" above for the three-consumer dispatch walk they hang off.

### `compy.input` namespace

**The call shapes live in the project-author guide, [Compy Input API](../../input_api.md), and this
section does not restate them.** What it records is what the table *is*, where it comes from, and
what its shape is fixed by.

`compy.input` is created **once for the application**, not once per project (`get_compy_input()` in
`consoleController.lua`, wrapped into the project's `compy` table by `get_compy_namespace()`): it is
built inside `prepare_project_env`, which `ConsoleController.new` calls a single time at
construction. Cloning the environment does not separate instances either — the container is
metatable-only and `table.clone` copies the metatable, so every clone resolves to the same private
state. Anything held there that must not outlive a run is therefore cleared by the stop teardown, or
kept on the widget where that teardown already reaches (D-ROUTE-LIFETIME).

Through it a project can raise and dismiss the widget, ask whether it is shown (D-ONE-STATE-ASK, and
the reason it must ask *here* is below), read and write the content and cursor (see "Cursor
manipulation" above for the layering that sits under it), reconfigure a live session, and register
its inbound handlers and outbound callbacks. Those registrations go through three sub-tables, each
with a decision of its own: **`shortcuts`** — the per-event combo tables (D-COMBO-TABLES);
**`hooks`** — the one seeded hook per event (D-HOOKS-SEEDED); **`callbacks`** — the widget's own
`self.callbacks` table, the same object rather than a copy (see "Submit and cancel" above).

The container and those three sub-table identities are **frozen** (D-FROZEN-SHELL — see the
"compy.input's write boundary" comment in `consoleController.lua`); every leaf inside them is freely
writable. Assigning over one of the method names, or over a sub-table itself, raises loudly rather
than replacing it silently (`build_input_surface`, `consoleController.lua`).

`compy.input.is_shown()` is the one state predicate on this surface (D-ONE-STATE-ASK). It returns the
widget's own internal `self.shown` flag (`UserInputController:is_shown()`), so a project's answer
cannot drift from the one the dispatch walk reads.

Reading `love.state.user_input` from inside a project instead does **not** work, and never did: a
project's `love` is a sandboxed deep clone (`project_sandbox_env.md`), so the framework writes the
real global while the project sees its own copy, which stays `nil` forever. An untracked scratch
project guards a per-tick re-arm with exactly that read; the guard has never fired, which is why
that project re-issues `show()` on every tick. That dead guard is the concrete reason the
predicate was added.

#### `show(config)` — activate

The field table is the guide's. What belongs here is that it is **closed**: the
project wrapper checks the config before it reaches `configure_core`, so an
unrecognised key **raises at the project's call line** rather than being dropped
(`decisions/input.md`, D-UNKNOWN-RAISES). The same check catches lifecycle names
such as `after_submit` — those are direct `compy.input.callbacks` assignments
rather than `show` keys, and the message says so. The wrapper exposes neither
the host evaluator nor the legacy result paths.

#### `configure(config)` — the live-reconfigure surface

`configure` carries the **project-owned** fields and only those. Each is applied
only when given, immediately, and stays until replaced; there is no partial
application — a field either applies in full or is not named at all. The content
keys **raise** here, because they belong to the other call: that is
D-UNKNOWN-RAISES's show-only category, added by D-CFG-BOUNDARY, and the message
names where each key belongs. The live writes for content are `set_text` /
`set_cursor` / `clear`.

Hidden or shown makes no difference. `configure` writes the fields
onto the widget, and the widget outlives its own visibility, so
there is nothing to defer and nothing to stash: a hidden
`configure` applies at once, is still in force at the next `show`,
and never warns (it is not a refusal). It is **run-scoped** by
construction rather than by a teardown step — the widget it wrote
on does not survive the run (`decisions/input.md`, D-ROUTE-LIFETIME), so
it cannot reach the next project's widget. Between runs there is no
widget at all and the call is inert.

`show{force = true}` over a live widget is the **same activation
path** a first `show` takes: a full re-setup with the config
passed, content baseline included. It is not a narrower mechanism
alongside `configure`, and there is no field it applies that
`configure` drops or vice versa. **`force` carries no content
meaning of its own** (owner ruling, 2026-09-09): activation seats
content only when `text` is given, forced or not, so a forced
`show{prompt = 'x'}` leaves the draft where it is.

**Activation destroys nothing** since 2026-09-09
(`decisions/input.md`, D-CFG-BOUNDARY statement 1 as amended):
`reset_content` is `if cfg.text ~= nil then set_text(cfg.text)`,
so a re-show finds what the last lifecycle verb left. The call it
lost, `clear_input()`, also dropped the **selection, the custom
status and the history index**, none of which `set_text('')`
touches — that breadth is why the removal needed a case each
rather than one, and it is what a project now keeps across a
hide/show cycle.

#### Why `prompt` is sticky rather than per-show

`prompt` is set-if-given and persists until replaced, like every
other project-owned field. It reads like an oversight — the label
is the most per-question-looking thing on the widget — and it was
questioned twice on exactly that ground before being ruled correct
(owner, 2026-08-27).

The evidence is **balloons**. In the pre-feature era the label died
with each `input_text()` call, so the example kept a shadow copy
(`ui_messages.hint`) and re-asserted it on every state transition.
A per-show `prompt` would make that shadow copy *necessary* rather
than vestigial: every project that wants a stable label would have
to re-send it on every activation, and forgetting once shows a
widget with no label. Sticky puts the label where the rest of the
project's configuration already is, and the shadow copy becomes
deletable.

This is recorded here rather than only in the feature's working
notes because the reasoning is not recoverable from the code: what
the code shows is a field that could as easily have been either.

#### One home for the highlighter

`highlighter` is a project callback like the other three, and it
lives in the widget's `callbacks` table with them. What makes it
different is where it is *read*: `UserInputModel:highlight` reads
`self.evaluator.highlighter`, not the callbacks table.

It is not copied there. `UserInputController:bind_highlighter`
gives the widget's own evaluator a metatable that **resolves** the
callbacks slot, so a `compy.input.callbacks.highlighter = fn`
assignment and a `show`/`configure` key are the same write by
construction. That matters because a copy step is something every
writing path has to remember, and one did not: a direct assignment
used to do nothing at all until an unrelated later call flushed it.

Resolution rather than a forwarding function, deliberately: the
model branches on the *truth* of `ev.highlighter`, and with none
set it must stay `nil` so the validation-colouring fallback still
runs. A forwarder would be permanently truthy and would replace
that fallback silently.

Bound only where the evaluator is the widget's **own**. The console
and editor share theirs and it carries a *language* highlighter —
not a project callback, and not something to resolve away.

#### `clear()`

Empties the active session's content and puts the cursor back at
the start; no widget-output callback fires. While hidden it is a
no-op and logs a warning — unlike `configure`, this call *is* a
refusal (there is no active session to clear).

---

## Key Files

| File | Role |
|---|---|
| `src/controller/userInputController.lua` | Keyboard, mouse, and text event handling for the input widget |
| `src/model/input/userInputModel.lua` | Input state: text, cursor, selection, history, error, evaluator |
| `src/model/input/inputText.lua` | Multiline string with cursor-aware insert/delete |
| `src/model/input/cursor.lua` | Cursor position model |
| `src/model/input/selection.lua` | Selection range model |
| `src/model/input/history.lua` | Command history (console) |
| `src/view/input/userInputView.lua` | Renders the input strip and status line |
| `src/controller/controller.lua` | Gateway (`love.handlers.*`), global shortcuts, `combo_string`/`any_mod`, route management |
| `src/controller/projectInputController.lua` | The project route: the three-consumer dispatch walk (`shortcuts` → `hooks` → widget), hook seeding |
| `src/controller/consoleController.lua` | Console/editor route dispatch, `compy` namespace + `compy.input` surface construction |

`controller.lua` is consumed from `main.lua` (wires
`set_default_handlers`) and `consoleController.lua` (calls into it on every mode
transition — run, stop, suspend, inspect). `projectInputController.lua` is used
only by `controller.lua` (the single `Controller.project_input` instance) and is
never referenced by console/editor code directly. `userInputController.lua`
instances are constructed by `consoleController.lua` (the project's widget, at the run seam),
`editorController.lua` (its own main input and its `search` sub-widget), and
implicitly by console (`consoleModel`/`consoleController`) — see "Search" above
for the third, less obvious instance.
