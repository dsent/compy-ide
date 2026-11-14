# Changelog

Protocol: `CURRENT_SCOPE` holds everything not yet released. When a version
ships, this section is emptied and its content moves down into a new
section named for that version. Released versions are listed below it,
newest first.

## CURRENT_SCOPE

A new project input API: one widget with a simple wrapper (`compy.ask`) and a
precise surface (`compy.input`), a lifecycle the project configures, first-class
keyboard/mouse/touch shortcuts, and the removal of the legacy polling globals.
Project-author guide: `doc/input_api.md`.

> **Breaking, pre-1.0:** the legacy text-input globals are removed with no
> compatibility shim (see *Removed*). This is a `1.0.0-rc`, so the break is
> announced here rather than in the version number.

### Added

- **A simple way to ask a question — `compy.ask`.** `compy.ask(prompt, …)` asks,
  `compy.on_answer(text)` receives the answer (or `nil` on Escape),
  `compy.on_key(...)`'s return value decides who consumes a key, and `compy.unask()`
  withdraws the question. A wrapper over the same widget — no second widget or event
  path.
- **The precise surface — `compy.input`:** `show`, `hide`, `configure`, `clear`,
  `set_text`, `set_cursor`, `get_text`, `get_cursor`, `is_shown`, plus callbacks,
  hooks, shortcuts and `fn`. One `show` and a callback (`on_text_entered`) replace the
  poll-a-global-every-frame idiom. Its lifecycle is set by **four independent flags** —
  `clear_on_submit`, `hide_on_submit`, `clear_on_cancel`, `hide_on_cancel` — each a
  mode that persists until unset. Content-bearing callbacks receive one `\n`-joined
  string; `validator`/`highlighter` receive the lines.
- **New set of capabilities to manage input events: shortcuts, hooks, dispatching chain:** 
  keyboard/mouse/touch **shortcuts** by combo and
  per-event **hooks** (`compy.input.hooks`), plus per-binding **repeat/propagation
  control** (`compy.input.fn`) and **`compy.before_exit`** to restore device state
  before a run ends. Details in `doc/input_api.md`.

### Changed

- Colouring, the submit gate and the submit action are three independent, optional
  keys (`highlighter`, `validator`, `on_text_entered`) rather than a choice of function
  name (`input_text` / `input_code` / `validated_input`).
- Keyboard and text input are no longer blocked while the widget is shown — a project
  keeps receiving its own `love.*` events while the user types.
- A project's own `love.*` input handlers (`keypressed`, `textinput`, `mousepressed`,
  …) are **captured and driven by the input system** rather than served directly by
  LÖVE — they were not served directly before either; they now seed into the matching
  hook and join the unified dispatch chain.
- **`singleclick` / `doubleclick` are repositioned** as input channels
  (`compy.input.hooks.singleclick` / `.doubleclick`, replacing the preceding
  `compy.singleclick` / `compy.doubleclick` for the uniformity). 
- **The file editor works in three states and asks no questions.** With an empty field
  you browse the file block by block; text you type is inserted before the highlighted
  block, or at the end of the file, on Enter; F2 loads the highlighted block into the
  field, and Enter then replaces it. The status line names the state, and holding F1
  shows the keys it admits. `doc/EDITOR.md` has the key table.
- **A file opens at its end, ready to append.** An empty or new file starts with no
  line at all, and a new file is created by the first text you submit.
- **Escape is the one way back.** It dismisses a notice, drops the text in the field
  or the replacement, and with an empty field steps back from the file: to the file
  you came from with Ctrl+J, at the place you left it, or to the console.
- **Refusals are one-line notices over the field.** A notice says what was refused and
  what would work, and the next key dismisses it. A failed save names the file and the
  reason and keeps your text in the field.
- **The text cursor is a blinking block.** In the file editor, the console and a
  project's input alike, the cursor is a block on the character it stands before,
  which stays readable on it, and on the empty cell at a line's end. It blinks as
  the `blink` setting says and stays shown for a moment after every key press, and
  after a project moves it with `compy.input`.
- **A notice is orange, the parser's message red.** The message above the status
  line has no frame.
- **Leaving waits for the edit to end.** Ctrl+T, Ctrl+Q, Ctrl+Alt+R and the
  deprecated Ctrl+Shift+S are refused with a notice while there is text in the field
  or a block is being replaced; submit it or drop it first. Ctrl+J is refused the same
  way.
- **Ctrl+Q stops the program and returns to the console; the project stays open.**
  It stops a program that runs, one that is paused, and one that has finished and
  still shows its picture behind the console. In the file editor it leaves the editor
  for the console, with every file you had opened. In the console with no program it
  does nothing. It takes the place of Ctrl+S.
- **No key closes the project any more.** `close_project()` in the console does, and
  so does opening another project.
- **Ctrl+S reaches your program.** It is no longer a reserved key, so a program can
  use it, for example to save.
- **Blocks are reused through the field.** Ctrl+Insert copies the highlighted block
  into the field, Ctrl+Delete cuts it there, Shift+Insert submits and keeps the text,
  and Alt+Up / Alt+Down move the block. Ctrl+Z and Ctrl+Y undo and redo both typing and
  changes to the file.
- **Text and Markdown files hold one block per line.** A line is accepted as written,
  with no syntax check and no formatting, and nothing is added after the last line. A
  file whose name ends in neither `.lua`, `.txt` nor `.md` opens as plain text.
- **Ctrl+J follows `dofile("name.lua")` as well as `require`.** A file that is missing,
  already open, unreadable, not UTF-8 text or in a folder of the project (which the
  editor cannot save) is refused with a notice, and `edit()` on such a file says so in
  the console and opens nothing.
- **Two statements sharing a line are one block.** Editing elsewhere in such a file no
  longer breaks it.
- **A file keeps its line ends.** Its lines are shown and edited without them. A line
  keeps the line end it had when it is moved, and when undo or redo puts it back; a
  line that comes from the field takes the one most of the file's lines have (Windows
  CRLF, LF or CR), the first in the file when two are as common.
- **A Lua file the editor cannot split into blocks opens, so you can fix it:** one with
  a syntax error, or Lua the editor does not read, such as `goto`. Each of its lines
  is a block until the editor can read the file: you can add text, and Ctrl+Delete
  cuts a line into the field to repair it. F2 on such a line is refused with a notice.
  Once the file parses, its blocks are statements again, and the browsing position
  stays on the one that holds the line it was on.
- **An SD card that cannot be read refuses the key, and forgets nothing.** Enter, a
  cut, a move, Ctrl+Z and Ctrl+Y say the file could not be read; the same key works
  once it can. With the card out, `edit()` and Ctrl+J say the file could not be read
  and open nothing.
- **The file editor shows no program behind it.** `edit()` in the console while a
  finished program still holds its handlers, or from such a program's own handler,
  stops the program first, as Ctrl+T does: its keys, hooks and calls no longer reach
  the editor or close its files.
- Ctrl+Up / Ctrl+Down browse blocks in every state, PageUp / PageDown browse ten
  blocks, and Ctrl+K in the field deletes to the end of the line.

### Removed

- **Ctrl+Shift+R, the reset.** The key does nothing in the console and the editor, and
  a running program receives it. Nothing clears the console's history in its place.
- **The editor's navigation, editing and block-reorder modes**, with their keys: Enter
  no longer opens a block (F2 does), Ctrl+Enter and Ctrl+Shift+Enter no longer open
  an empty block, Ctrl+M no longer starts a move (Alt+Up / Alt+Down move a block), and
  Shift+Esc no longer leaves or discards (Escape does).
- **The editor's questions.** Nothing asks "discard the changes?" or about an unsaved
  file any more; see *Changed* for the notices that replace them.
- A draft is no longer carried along when Ctrl+J opens another file: Ctrl+J waits for
  the edit to end.
- **Polling user input is gone entirely.** The idiom of reading input by checking a
  global every frame is removed; use the new event-driven, asynchronous API, which
  shows/hides and manages the input widget through its own calls and callbacks.
- **Breaking: the legacy text-input globals**, with no shim — `input_text`,
  `input_code`, `validated_input`, `user_input` and `write_to_input`. `doc/input_api.md`
  (*"Migration from the legacy globals"*) maps each to its replacement.
- The four evaluator objects (`InputEvalText`, `InputEvalLua`, `ValidatedTextEval`,
  `LuaEditorEval`) are no longer reachable from a project; what a project needs is
  exported narrowly instead (`LuaHighlighter`, `LuaSyntaxValidator`, `LineValidators`).

### Fixed

- **A letter outside ASCII no longer crashes the IDE.** Enter on a Lua line such as
  `п = 1` or `x = é` in the console or the file editor stopped the IDE; the message now
  names the whole letter. A message holding bytes that are not UTF-8 shows `�` for them,
  and a file name that is not UTF-8 is refused with a reason.
- **On a computer, AltGr only types.** A character typed with AltGr no longer runs a Ctrl
  or Alt command as well: on Windows, which reports AltGr as Ctrl+Alt, AltGr+L cleared the
  console, AltGr+F opened search and AltGr+R restarted the program. On a Compy the right
  Alt stays an Alt.
- **Opening a Lua file no longer loses lines.** A comment line after a line that ends in
  a comment, the later lines of a long comment that starts after code, a `#!` first
  line and a line of spaces were dropped or emptied on opening, and the next save wrote
  the loss. Every line now opens as it is written and is written back unchanged.
- **A long line in a multi-line comment no longer sends an edit to the wrong block.**
- **The editor writes a file only over what it last read or wrote there.** A file that
  could not be read opened empty and was written over by the first Enter, and a missing
  file that something else created before the first Enter was replaced; both are
  refused with a notice now.
- **Ctrl+Z reaches back to the opening of the file**, not only the latest 32 actions,
  and holding Escape no longer leaves the file after cancelling an edit.
- A line of spaces in a text or Markdown file is saved as typed.
- **Ctrl+T from a file reached with Ctrl+J comes back to the whole chain** of files,
  each where it was left and with its undo history; Escape then returns to the caller.
- **`tidy()` keeps a `#!` first line and the file's line ends**, as Ctrl+Shift+F does;
  it emptied the one and rewrote the others as LF.
- **Text pasted with Windows (CRLF) or old Mac (CR) line breaks** is split into lines
  as typed text is: in a CRLF file it no longer writes an extra empty line.
- Multi-line string content now writes — `show{text = "a\nb"}` / `set_text("a\nb")`
  previously wrote nothing silently — and the two spellings of the text shape now agree.
- Non-text content is refused with a readable message that names the failing call.
- The error boundary no longer swallows crashes in a project's `love.update` or pointer
  handlers, and no longer drops callback arguments on non-LuaJIT (PUC 5.1) runtimes.
- Unconsumed project input no longer accumulates in the console while the console is
  not visible.
