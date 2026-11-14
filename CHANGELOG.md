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
  field, and Enter then replaces it. F2 loads any block, one over the 14-line limit or
  with a line over 64 characters included; Enter refuses a Lua block that still breaks
  a rule, with a notice that says which. The status line names the state, and holding
  F1 shows the keys it admits. `doc/EDITOR.md` has the key table.
- **A file opens at its end, ready to append.** An empty or new file starts with no
  line at all, and a new file is created by the first text you submit.
- **Escape steps back.** It dismisses a notice, drops the text in the field or the
  replacement, and with an empty field steps back from the file: to the file you came
  from with Ctrl+J, at the place you left it, or to the console.
- **Refusals are notices just above the status line.** A notice says what was refused
  and what would work, wraps between words when it is long, and the next key dismisses
  it and does its usual work. A failed save names the file and the reason and keeps
  your text in the field.
- **The text cursor is a blinking block.** In the file editor, the console and a
  project's input alike, the cursor is a block on the character it stands before,
  which stays readable on it, and on the empty cell at a line's end. It blinks as
  the `blink` setting says and stays shown for a moment after every key press, and
  after a project moves it with `compy.input`.
- **A notice is orange, the parser's message red.** The message above the status
  line has no frame.
- **Leaving waits for the edit to end.** Ctrl+T, Ctrl+Q and Ctrl+Alt+R are refused
  with a notice while there is text in the field or a block is being replaced; submit
  it or drop it first. Ctrl+J is refused the same way.
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
- **A run of empty lines in Lua text is kept as one.** The formatter decides a Lua
  draft's empty lines, at its start, between statements and at its end, and the editor
  puts none back; Enter on an empty field still adds one empty line at a time. Text and
  Markdown files keep every empty line as typed.
- **Text and Markdown files hold one block per line.** A line is accepted as written,
  with no syntax check and no formatting, and nothing is added after the last line. A
  file whose name ends in neither `.lua`, `.txt` nor `.md` opens as plain text.
- **Ctrl+J follows `dofile("name.lua")` as well as `require`.** A file that is missing,
  already open, unreadable, not UTF-8 text or in a folder of the project (which the
  editor cannot save) is refused with a notice, and `edit()` on such a file says so in
  the console and opens nothing.
- **Two statements sharing a line are one block.** Editing elsewhere in such a file no
  longer breaks it.
- **A file is written with LF line ends.** LF, Windows CRLF and old Mac CR each end a
  line when a file opens, and opening writes nothing; the first change saved writes
  the whole file with LF, as Lua and every other tool on the Compy read it.
- **A Lua file the editor cannot split into blocks opens, so you can fix it:** one with
  a syntax error, or Lua the editor does not read, such as `goto`. Each of its lines
  is a block until the editor can read the file: you can add text, and F2 or
  Ctrl+Delete takes a line into the field to repair it.
  Once the file parses, its blocks are statements again, and the browsing position
  stays on the one that holds the line it was on.
- **A file that cannot be read is not written.** Enter, a cut, a move, Alt+F,
  Ctrl+Z and Ctrl+Y say the file could not be read, save nothing, and keep the text in
  the field.
- **A run keeps the editor's files, and `edit()` starts afresh.** Ctrl+T back from
  a run shows every file as you left it, with its place and undo history. A file
  that the run or a console command such as `tidy()` changed meanwhile shows what
  the SD card holds, and its undo history starts again; so does a file you step back
  to with Escape. `edit("name")` in the console closes the files a run came from and
  opens the file alone, at its end.
- **The file editor shows no program behind it.** `edit()` in the console while a
  finished program still holds its handlers, or from such a program's own handler,
  stops the program first, as Ctrl+T does: its keys, hooks and calls no longer reach
  the editor or close its files.
- Ctrl+Up / Ctrl+Down browse blocks in every state, and Ctrl+K in the field deletes to
  the end of the line. With an empty field Home goes to the first block and End to the
  end of the file, where new text is added.
- **Formatting the file is Alt+F.** Ctrl+F is kept free for a search to come.
- **PageDown and PageUp page through the file.** PageDown brings the first block hidden
  below the view to its top, PageUp the last one hidden above to its bottom, and the
  highlight goes with it; at the file's end or start they go to the end position or the
  first block. A block taller than the screen is paged through first. They work in
  every state, and repeat while held.
- **One text field, the same everywhere.** The console, the file editor and a program's
  input field take the same keys: Ctrl+Backspace, Alt+Backspace and Ctrl+W delete what
  Ctrl+Left moves over (at a line's start, the line break and the word before it),
  Ctrl+K the rest of the line, and Alt+Shift+Up and
  Alt+Shift+Down move the cursor's line, in every field. Alt+Up and Alt+Down move a
  block in the file editor and do nothing elsewhere. A click places the cursor in every
  field, the file editor's included. No field selects text: Shift with an arrow, Home or
  End does nothing, and neither does a drag.
- **Alt+F says why it refuses**, in a notice that blocks nothing: in a text or
  Markdown file, "The file has nothing to format.", and during an edit. `tidy()` on a
  text or Markdown file says it has nothing to format, where it named an error or said
  the file could not be tidied.
- **After Alt+F the highlight keeps its place among the blocks with text.** On
  a comment it stays on that comment, where it moved to the statement below; from an
  empty line it goes to the next block with text.
- **The file editor names no file type.** What differs between Lua, Markdown and text
  files is the file's syntax processor's to say (`src/model/syntax/`, chosen by the
  file's name): its blocks, its verdict on a draft, its formatting, its colors and the
  files it names. Every file is drawn as blocks, its colors taken from the whole text.
- **Held down, a key repeats only if it writes nothing and changes no state**, in the
  file editor and the console: typing, moving the cursor, browsing, deleting in the
  field, Shift+Enter, and Ctrl+Z and Ctrl+Y through the field's own changes. Enter,
  Escape, F2, Shift+Insert, Ctrl+Insert, Ctrl+Delete, Alt+Up and Alt+Down, Ctrl+J,
  Alt+F and the other commands act once per press: a held Enter adds one empty
  line, and a held Ctrl+Delete cuts one block. A program's own input keeps its repeats.
- **Every chord is a key of its own.** A key pressed with a modifier that nothing
  binds does nothing, in the file editor, the console and a program's input field:
  Ctrl+Enter no longer submits in the console or a program's input, Ctrl+Up and
  Ctrl+Down no longer move or recall in the console, and Shift+Escape no longer cancels
  a program's input. The F1 key card is drawn from the same key tables and lists every
  key the editor or the console takes, the reserved ones (Ctrl+T, Ctrl+Q, Ctrl+Alt+R,
  Ctrl+Esc) included, but the trivial ones that move the cursor, delete a character or
  page; only a bare F1 brings it up.
- **PageUp and PageDown do nothing in the console**: they no longer recall the history,
  which Up and Down still do, and are kept for paging the output.
- **Ctrl+Z and Ctrl+Y undo and redo the typing in every input**, the console's and a
  program's as well as the editor's. Ctrl+Y no longer deletes the line.
- **F1 holds back Ctrl+Q and the other reserved keys in the file editor only.** In the
  console Ctrl+Q stops the program while the card shows, and holding F1 in your own
  program blocks nothing.

### Removed

- **The editor's checkpoints and `revert()`.** The editor no longer writes or restores
  `name.~save` checkpoint files (Ctrl+K and Ctrl+Shift+K had already gone), and the
  console's `revert()` is gone with them: saving a copy of a project is the reset
  feature's, which is still to come. A `.~save` file already on the card is an ordinary
  file: it is listed with the project's files and opens as plain text.
- **Ctrl+Shift+R, the reset.** The key does nothing in the console and the editor, and
  a running program receives it. Nothing clears the console's history in its place.
- **The editor's navigation, editing and block-reorder modes**, with their keys: Enter
  no longer opens a block (F2 does), Ctrl+Enter and Ctrl+Shift+Enter no longer open
  an empty block, Ctrl+M no longer starts a move (Alt+Up / Alt+Down move a block), and
  Shift+Esc no longer leaves or discards (Escape does).
- **The editor's questions.** Nothing asks "discard the changes?" or about an unsaved
  file any more; see *Changed* for the notices that replace them.
- **The editor's search (Ctrl+F)**: Ctrl+F does nothing in the editor now. Search is
  not in the editor's specification and needs a design of its own, which it may get
  later.
- **A click on the file editor's text no longer browses to a block.** The mouse needs
  a design of its own.
- **Ctrl+Shift+S**, which left the editor; Ctrl+Q does.
- **The Alt look-around keys** (Alt+PageUp, Alt+PageDown, Alt+Left, Alt+Right, Alt+Home,
  Alt+End), which scrolled the file editor's view apart from the highlight; PageUp and
  PageDown page with it.
- **Ctrl+D**, which duplicated the field's line, and **Shift+Delete**, which cut a
  block as Ctrl+Delete does.
- **Text selection**, with Shift and the arrows or with the mouse, and Shift+Delete in a
  field: with the clipboard gone nothing used it.
- **The system clipboard in the text field**: Ctrl+C, Ctrl+X and Ctrl+V do nothing in
  the console, the file editor or a program's input, and Ctrl+Insert and Shift+Insert
  keep only the editor's own meanings; like search, it needs a design of its own.
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
- **`tidy()` keeps a `#!` first line**, as Alt+F does; it emptied it.
- **Holding F1 shows a key card only where its press went to the console or the
  editor.** Over a program that takes the keys, with its input field, a key hook or a
  shortcut, the card showed while the program kept them; there F1 is the program's
  now, and Ctrl+Q stops the program while F1 is held, with or without other keys
  pressed since. A card that shows stays until F1 is released, and so does the pause
  of the keys it holds back.
- **A `#!` first line is kept, and edited like any line.** Alt+F and `tidy()`
  keep it, F2 loads it, and a cut takes it out; a change that would leave a `#!` line
  anywhere but first, or put anything above it, is refused, since Lua could not run
  the file after it.
- **Alt+Shift+Up and Alt+Shift+Down in a field move the cursor's line, the cursor
  with it**, and Ctrl+Z puts the cursor back where it was. At the first or last line
  nothing moves; the keys swapped the two lines below or above.
- **The key press that brings the editor to the front does nothing in it.**
  Enter that made a program open a file with `edit()` added an empty line to it, and
  one held a moment too long after `edit()` in the console added one per repeat; the
  Ctrl+T that came back to a file changed outside the editor dismissed the notice
  saying so.
- **A held Enter submits a program's input once.** Its repeats called
  `before_submit` and `on_text_entered` again; a program's own hooks and shortcuts
  still see them.
- **A held key repeats only where its press went.** A held Ctrl+T runs the program
  once instead of going back and forth between the program and the editor, and a held
  Escape that leaves the last file no longer clears the console's line.
- **Text with Windows (CRLF) or old Mac (CR) line breaks** that a program puts in a
  field is split into lines, and no carriage return reaches a line.
- Multi-line string content now writes — `show{text = "a\nb"}` / `set_text("a\nb")`
  previously wrote nothing silently — and the two spellings of the text shape now agree.
- Non-text content is refused with a readable message that names the failing call.
- The error boundary no longer swallows crashes in a project's `love.update` or pointer
  handlers, and no longer drops callback arguments on non-LuaJIT (PUC 5.1) runtimes.
- Unconsumed project input no longer accumulates in the console while the console is
  not visible.
