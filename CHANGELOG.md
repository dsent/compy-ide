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

- **In the console's output a character wider than its cell shows whole.** The next
  cell's background used to cut it at the cell's right edge. A block or a box line now
  keeps the faint pixel it has at each side, and an arrow or a CJK character runs a few
  pixels over the cell after it. Letters, digits and signs of ASCII, Latin-1 and Russian
  fit their cells and look as they did.
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
  which stays readable on it, and on the empty cell at a line's end. It blinks
  slowly, 0.6 seconds shown and 0.6 hidden, as a terminal's cursor does, and stays
  shown for a whole blink after every key press, and after a project moves it with
  `compy.input`.
- **A notice is orange, the parser's message red.** The message above the status
  line has no frame.
- **The console's status line is a near-black gray**, so that the black band of an
  error or a notice above it stands apart; its key card is the same gray. The editor's
  status line and a paused program's are as before.
- **Leaving waits for the edit to end.** Ctrl+T, Ctrl+Q and Ctrl+R are refused
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
- **Ctrl+R runs the project anew**, in the console, the editor and over a running
  program; Ctrl+Alt+R does nothing now. The `r` a Compy sends as text with the chord
  reaches no field and no program. The terminal example restarts the micro:bit with Ctrl+M.
- **Ctrl+G goes back to the block being replaced.** While replacing, it brings the
  highlight back to the block loaded with F2 and shows it; the field's text stays. In
  the other states it does nothing.
- **The status line shows a block's lines as `L2-21`**, without the count that
  followed in brackets.
- **The status line is 37 pixels high**: its text sits in a row's 33 at the line's top,
  four pixels lie under it, and a strip of two pixels stays under the field at the
  screen's bottom.
- **A block that goes on beyond the editor's edge is marked there.** While the
  highlighted block or the block being replaced has rows above or below the view, the
  edge row fades toward the edge and its last column carries a translucent `^` or `v`;
  the field's edges are marked the same way while the text in it has rows out of sight.
- **A wrapped line has tiny orange corners**: one at the top right of every row that
  goes on, one at the bottom left of every row that continues it, in the editor's view
  and in every text field. They lie under the text, which does not move; an edge row
  with a continuation cue has no corner where the cue stands.
- **PageDown and PageUp page through the file.** PageDown brings the first block hidden
  below the view to its top, PageUp the last one hidden above to its bottom, and the
  highlight goes with it; at the file's end or start they go to the end position or the
  first block. A block taller than the screen is paged through first. They work in
  every state, and repeat while held.
- **One text field, the same everywhere.** The console, the file editor and a program's
  input field take the same keys: Ctrl+Backspace and Ctrl+W delete what
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
- **Held down, a key repeats until it stops by itself**, in the file editor and the
  console: a held Enter in the editor adds an empty line per repeat, a held Ctrl+Delete
  removes the empty lines down to the next block with text, cuts it and stops, Alt+Up
  and Alt+Down move the block to the file's edge, and Ctrl+Z and Ctrl+Y repeat through
  the field's own changes only. Enter in the console and in a program's input field,
  Escape in the editor, Shift+Insert, Ctrl+Insert, Ctrl+J, Ctrl+R and Ctrl+T act once
  per press.
- **Every chord is a key of its own.** A key pressed with a modifier that nothing
  binds does nothing, in the file editor, the console and a program's input field:
  Ctrl+Enter no longer submits in the console or a program's input, Ctrl+Up and
  Ctrl+Down no longer move the cursor or recall in the console, and Shift+Escape no longer cancels
  a program's input. The F1 key card is drawn from the same key tables and lists every
  key the editor or the console takes, the reserved ones (Ctrl+T, Ctrl+Q, Ctrl+R,
  Ctrl+Esc) included, but the trivial ones: the arrows, Home and End within a draft,
  Backspace, Delete and paging. Ctrl+Home and Ctrl+End, to the text's start and end,
  are on it. Only a bare F1 brings it up.
- **The console keeps its output.** The last 1,000 rows that scroll off the top of the
  console's output are kept, each with its colors, and Ctrl+Up / Ctrl+Down scroll over them
  a row at a time, PageUp / PageDown a page of 15 rows with one carried over, and, while the
  field is empty, Home and End go to the oldest and the newest row. A scrolled view fills
  the screen, carries the editor's continuation cue at an edge with more beyond, and stays
  where it is while new output arrives; any other key but a modifier, a lock key or F1
  brings the screen back, and so do a program's start, stop or pause, a key or text a
  running program takes, and its input field coming up. The field keeps its text and
  cursor. PageUp and PageDown no longer recall the history, which Up and
  Down still do. While a program's input field shows, or the program takes the keys
  itself, the keys are the program's. The key card lists Ctrl+Up/Down and Home/End.
- **Ctrl+L empties the console**: the screen, the kept output, and output still waiting
  to be written when it is pressed. A program's `compy.terminal.clear()` clears the
  screen alone, and what was on it is gone. `list_projects()` no longer clears the screen:
  it lists below what is there.
- **Each line the console runs is written to its output**, in blue, before it runs, so that
  what it prints follows it; a line that fails also has its error written there, in red,
  after its output. A line that ran leaves the field, whether it ended well or in an
  error, and Up brings it back from the history. A line the syntax check refuses is not
  written and stays in the field, as does one Lua does not load or one not yet finished.
- **The console says what a command did in its output, and what the line being typed
  needs in a band above the status line.** A typed line's error and a program's error are
  written to the output in red, which is for errors alone; a console command's refusal,
  which is no error, in a burnt orange; answers such as "Project x opened" keep the
  output's colour. A line the syntax refuses or Lua does not load shows its message in
  the band, over the output's last rows, without the `Errors:` heading; the line stays
  in the field with its cursor, red from a syntax failure, and the status line no longer
  moves. The message blocks nothing: the next key dismisses it and does its work, so
  Enter tries the line again, Escape clears it and Up recalls the history. Enter on a
  statement that is not finished begins its next line, as before, and the band now says
  so in orange: "Unfinished code: type the rest, then press Enter." A pause's text, from
  `pause("text")` or Ctrl+Pause's "BREAK into program", shows in the band in orange too,
  and the program's screen is left as it was. A program's own input field shows its
  errors as before. `run()` while a project is paused now says "A project is
  already running: Ctrl+Q stops it." in the output, where before its message was cleared
  as it appeared.
- **A program's graphics settings no longer reach the IDE's own drawing.** After a program
  that set a scissor, wireframe or a colour was stopped, or while it was paused, the key
  card and the file editor were drawn under them, clipped to the program's scissor and
  outlined; the shipped build did the same. The IDE now draws its console, status line,
  key card, editor and a program's input field in its own settings, and gives the
  program its own back, so a paused program resumes as it was. A run that ends for good
  (`stop()`, Ctrl+Q, an error in its first lines, the project's close) also resets them,
  so a line typed next draws as the IDE does.
- **Each run starts afresh.** A run, by `run()`, `run("name")`, Ctrl+R or the editor's run
  key, first ends a program idle behind the console, as `stop()` ends it: its handlers,
  input hooks and shortcuts, `before_exit` hook, serial handlers and input field go.
  (`run()` while a program runs or is paused is still refused; Ctrl+R stops it first.)
  Then it starts from the project's environment as opening the project makes it: a
  variable, a `love` handler or a module of an earlier run, or a variable typed in the
  console before it, is gone, and so is a bundled library's state the program loaded,
  such as a timer's pending calls; the graphics settings it changed are reset, though a transform
  it pushed and never popped stays. Before, a handler deleted from `main.lua` went on running
  until another project was opened or the IDE restarted. What a run leaves stays for the
  console to look at until the next run, and `continue()` and `dofile()` keep everything
  as it is.
- **`run("name")` makes no project.** A name no project has is refused, "There is no
  project mzae: project("mzae") creates it.", and nothing changes; before, `run` made the
  project and ran its example. `project("name")` still makes one.
- **One sentence for each refusal.** `stop()` and `pause()` with nothing running say
  "Nothing is running.", and `continue()` with nothing paused "Nothing is paused."; a file
  the open project does not hold is "There is no NAME in this project." wherever it is
  asked for; and `project()` with no name says "A project needs a name:
  project("name").".
- **A project is always open.** `project()` with a name that cannot be a project's, such
  as `project("a/b")`, closed the open project, stopping its program and closing its
  files, and left none open, so commands that need one refused until another was opened.
  Such a name is now refused before anything is closed: the program and the files stay
  as they were, and only the reason is said. If a project cannot be opened or made on the
  SD card, the one that was open is opened again. Only an SD card that cannot hold
  `scratchpad` leaves no project open; every command that needs one then says "No
  project is open: the SD card cannot be used." `dofile()` of a file Lua does not load says Lua's error instead of saying the file
  is not there.
- **The console's history works as a classic shell's.** It holds only the lines that ran:
  Up no longer adds the line being typed, an edit to a recalled line no longer replaces
  the line that ran, and Escape no longer stores the line it clears. The line being typed
  waits below the newest line and comes back on Down, which no longer empties the field.
  An edit to a recalled line stays while you move away and back, until Enter runs it as
  a new line. A line that repeats the newest one, typed again or recalled and run
  unchanged, is not stored again.
- **Ctrl+Z and Ctrl+Y undo and redo the typing in every input**, the console's and a
  program's as well as the editor's. Ctrl+Y no longer deletes the line.
- **While the key card shows, every other key does nothing**, in the file editor and
  in the console alike, Ctrl+Q and the other reserved keys included, and no key
  reaches a program behind the console's card; Ctrl+Esc always quits. Holding F1 in
  your own program, where no card shows, blocks nothing.

### Removed

- **`compy.terminal.show_cursor()` and `hide_cursor()`** (also on `tty`). They never
  worked: `show_cursor()` stopped the program with an error, and the output is drawn
  over the grid's cursor, so even a working call would have shown nothing. A person
  types in the field under the status line, and the output only shows text, so a cursor
  there would mark nothing. `gotoxy` and `clear` stay.
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

- **A long output costs less while it is written.** A program that prints thousands of
  lines at once made every frame copy all the output still waiting to be written, and
  draw each of the screen's 1,024 cells in two calls to the graphics card. Now the
  waiting output is copied once each time it has halved, and a row is drawn in a few
  calls: a rectangle for each run of one background, a print for each run of one color.
- **`gotoxy` given something other than a number names the program's line.**
  `compy.terminal.gotoxy('x', 'y')` stopped the program with an error about `floor` on
  a line of the IDE's terminal; it now stops it with `compy.terminal.gotoxy: x and y
  must be numbers` on the line that called it.
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
  of the keys it holds back. While a card shows the mouse and touch do nothing: a
  click no longer moves the hidden draft's cursor, and no mouse or touch event reaches
  a program behind the console's card. A press or a touch begun under the card ends
  there; one begun before it still gets its release.
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
