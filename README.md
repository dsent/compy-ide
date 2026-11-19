# Compy

A console-based Lua-programmable computer for children based on
the [LÖVE2D][löve2d] framework.

## Principles

- Command-line based UI
- Full control over each pixel of the display
- Ability to easily reset to initial state
- Impossible to damage with non-violent interaction
- Syntactic mistakes caught early, not accepted on input
- Possibility to test/try parts of program separately
- Share software in source package form
- Minimize frustration

# Usage (IDE mode)

Rather than the default LÖVE storage locations (save directory,
cache, etc), the application uses a folder under _Documents_ to
store projects. Ideally, this is located on removable storage to
enable sharing programs the user writes.

For simplicity and security reasons, the user is only allowed to
access files inside a project. To interact with the filesystem,
a project must be selected first.

The status line at the bottom of the screen starts with the
project and, in yellow, what has the keys: `console` on dark
gray; `running` on dark gray while a program runs and `paused`
on red while it is paused, each after the file the program
started from; and the editor's state (`browsing`, `inserting`,
`replacing`) on blue, after the open file; while the block you
replace is out of view, an arrow after `replacing` points to
it. Without an SD
card, `[no sd]` stands in front, in orange. At its right end,
in yellow, it shows where the cursor is in what you type, as
`line:column`; before that, while the output is scrolled back,
how far, as `L-4`, and in the editor the block and its lines,
as `B3 L3`. A number past 9999 is written in thousands, as
`10K`. A program that asks for typing shows its own
question there instead, and where the cursor is in the answer.

## Keys

| Command                                                           | Combination                                   |
| :---------------------------------------------------------------- | :-------------------------------------------- |
| Clear the console's screen and the output it keeps                | <kbd>Ctrl</kbd>+<kbd>L</kbd>                  |
| Stop the program and return to the console (the project stays open) | <kbd>Ctrl</kbd>+<kbd>Q</kbd>                  |
| Restart project                                                   | <kbd>Ctrl</kbd>+<kbd>R</kbd>               |
| Exit application                                                  | <kbd>Ctrl</kbd>+<kbd>Esc</kbd>                |
| Pause project                                                     | <kbd>Ctrl</kbd>+<kbd>Pause</kbd>              |
| Toggle edit/run                                                   | <kbd>Ctrl</kbd>+<kbd>T</kbd>                  |
| Show the screen's next mode: text, combined, picture (console)    | <kbd>F12</kbd>                                |
| **Console output**                                                |                                               |
| Scroll the output a row (the field keeps its text)                | <kbd>Ctrl</kbd>+<kbd>⇧</kbd>/<kbd>Ctrl</kbd>+<kbd>⇩</kbd> |
| Scroll the output a page of 15 rows                               | <kbd>PageUp</kbd>/<kbd>PageDown</kbd>         |
| To the oldest / newest row of the output (empty field)            | <kbd>Home</kbd>/<kbd>End</kbd>                |
| To the oldest / newest row of the output (the field keeps its text) | <kbd>Ctrl</kbd>+<kbd>PageUp</kbd>/<kbd>Ctrl</kbd>+<kbd>PageDown</kbd> |
| **Input**                                                         |                                               |
| Move cursor horizontally                                          | <kbd>⇦</kbd>/<kbd>⇨</kbd>                     |
| Move cursor vertically                                            | <kbd>⇧</kbd>/<kbd>⇩</kbd>                     |
| Move in history (if in first/last line)                           | <kbd>⇧</kbd>/<kbd>⇩</kbd>                     |
| Jump to start                                                     | <kbd>Ctrl</kbd>+<kbd>Home</kbd>               |
| Jump to end                                                       | <kbd>Ctrl</kbd>+<kbd>End</kbd>                |
| Jump to the start of the row (a long line takes several rows)     | <kbd>Home</kbd>                               |
| Jump to the end of the row                                        | <kbd>End</kbd>                                |
| Insert newline                                                    | <kbd>Shift</kbd>+<kbd>Enter ⏎</kbd>           |
| Undo / redo the typing                                            | <kbd>Ctrl</kbd>+<kbd>Z</kbd> / <kbd>Ctrl</kbd>+<kbd>Y</kbd> |
| Delete the previous word                                          | <kbd>Ctrl</kbd>+<kbd>Backspace</kbd> / <kbd>Ctrl</kbd>+<kbd>W</kbd> |
| Delete to the end of the line                                     | <kbd>Ctrl</kbd>+<kbd>K</kbd>                  |
| Move the cursor's line up / down                                  | <kbd>Alt</kbd>+<kbd>Shift</kbd>+<kbd>⇧</kbd>/<kbd>⇩</kbd> |
| Place the cursor                                                  | click in the field                            |
| Select a part of the draft; typing replaces it, Backspace or Delete removes it | <kbd>Shift</kbd>+movement, drag, or <kbd>Shift</kbd>+click; a word: double click |
| Evaluate input                                                    | <kbd>Enter ⏎</kbd>                            |
| **Editor**                                                        |                                               |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; _same as Input in the field, except for:_ |                                               |
| Browse the file block by block                                    | <kbd>Ctrl</kbd>+<kbd>⇧</kbd>/<kbd>Ctrl</kbd>+<kbd>⇩</kbd> |
| Browse block by block (empty field) / move the cursor a row (text in the field) | <kbd>⇧</kbd>/<kbd>⇩</kbd>                     |
| Page down / up: the next block hidden below comes to the top, the one above to the bottom | <kbd>PageDown</kbd>/<kbd>PageUp</kbd>        |
| To the first block / the end of the file (empty field)            | <kbd>Home</kbd>/<kbd>End</kbd>                |
| To the first block / the end of the file (the field keeps its text) | <kbd>Ctrl</kbd>+<kbd>PageUp</kbd>/<kbd>Ctrl</kbd>+<kbd>PageDown</kbd> |
| Back to the block being replaced (while replacing)                | <kbd>Ctrl</kbd>+<kbd>G</kbd>                  |
| Insert the field's text before the highlighted block, or at the end of the file | <kbd>Enter ⏎</kbd>                            |
| Insert an empty line (empty field)                                | <kbd>Enter ⏎</kbd>                            |
| Load the highlighted block into the field, to replace it          | <kbd>F2</kbd>                                 |
| Replace the loaded block with the field's text                    | <kbd>Enter ⏎</kbd>                            |
| Insert or replace, and keep the text in the field                 | <kbd>Shift</kbd>+<kbd>Insert</kbd>            |
| Break a line in the field                                         | <kbd>Shift</kbd>+<kbd>Enter ⏎</kbd> / <kbd>Alt</kbd>+<kbd>Enter ⏎</kbd> |
| Drop the field's text or the replacement; step back from the file (empty field) | <kbd>Esc</kbd>                                |
| Leave the editor for the console, every open file with it (empty field) | <kbd>Ctrl</kbd>+<kbd>Q</kbd>                  |
| Copy the highlighted block into the field                         | <kbd>Ctrl</kbd>+<kbd>Insert</kbd>             |
| Cut the highlighted block into the field (empty field)            | <kbd>Ctrl</kbd>+<kbd>Delete</kbd>             |
| Move the highlighted block up / down                              | <kbd>Alt</kbd>+<kbd>⇧</kbd>/<kbd>Alt</kbd>+<kbd>⇩</kbd> |
| Undo / redo                                                       | <kbd>Ctrl</kbd>+<kbd>Z</kbd> / <kbd>Ctrl</kbd>+<kbd>Y</kbd> |
| Follow the require or dofile of the highlighted block (empty field) | <kbd>Ctrl</kbd>+<kbd>J</kbd>                  |
| Format the whole file (empty field)                               | <kbd>Alt</kbd>+<kbd>F</kbd>                   |
| Show the keys of the current state                                | hold <kbd>F1</kbd>                            |

The console keeps the last 1,000 rows that scroll off the top of
its output, and the keys above scroll over them. A scrolled view
fills the screen and is marked at its edges where more lies
beyond. New output leaves it where it is, and so does typing:
you can look at what scrolled away while you write the next
line. <kbd>Enter</kbd> on a line that runs brings the screen
back, as do a program's start, stop or pause. Each line the
console runs is
written to the output in blue before it runs, and its error
after it, in red. When the error is a call of a global name
that does not exist, and exactly one global you can call
differs from it only in capitals and underscores, the error
names that one too: `listProjects()` says
`There is no listProjects. Did you mean list_projects?`. A
field, such as `compy.input.setText()`, gets no such line. A
command that refuses says why in the output,
in orange. The band above the status line belongs to the line
being typed: it says why a line did not run because it does not
parse, and, in orange, that a statement is not finished yet,
when <kbd>Enter</kbd> begins its next line instead of running it.
<kbd>Ctrl</kbd>+<kbd>L</kbd> empties the console: the
screen, the kept rows and output still waiting to be written;
`compy.terminal.clear()` from a program clears the screen alone.
The mouse wheel scrolls the output too. While a program runs and
can still act, all input is the program's and the console's
field is hidden, but the output keeps its scrolling keys and the
wheel for itself whenever the program does not take them; a
program with its own `love.keypressed` takes every key, which
leaves the wheel.

Each combination is a key of its own: a key pressed with a modifier the
table does not name does nothing. <kbd>Ctrl</kbd>+<kbd>Enter</kbd> is not
<kbd>Enter</kbd>, and <kbd>Ctrl</kbd>+<kbd>⇧</kbd> in the console is not
<kbd>⇧</kbd>.

## Projects

A _project_ is a folder in the application's storage which
contains at least a `main.lua` file. Projects can be loaded and
ran. At any time, pressing <kbd>Ctrl-Q</kbd> stops the program and
returns to the console. The project stays open: no key closes it,
and `close_project()` does.

There is always a project open: the application starts on the
default `scratchpad` project, which can be used to persist files.
Closing a project returns to `scratchpad`.

`stop()`, `reset()`, `run()`, `project()`, `close_project()` and
`reset_scratchpad()`, called from a program or from a line typed
in the console, end that code at once: nothing after the call
runs, and the IDE does what it asks once the code has returned.
A call that is refused, such as `stop()` with nothing running,
says why and ends nothing. A program's own `pcall` around such a
call lets its code run on, and the call is done when that code
returns.

- `list_projects()`

  List available projects.

- `project(proj)`

  Open project _proj_ or create a new one if it doesn't exist.
  New projects are supplied with example code to demonstrate the
  structure.

- `current_project()`

  Print the currently open project's name (if any).

- `run_project(proj?)` / `run(proj?)`

  Run either _proj_ or the currently open project if no
  arguments are passed. `run(nil, "second.lua")` runs another
  file of the open project as the program, from a clean start
  as `run()` does, and `run("proj", "second.lua")` opens _proj_
  first; a file the project does not hold is refused. Ctrl+R
  restarts a program that runs, is paused or idles behind the
  console, from the file it runs from, and does nothing when
  none does; Ctrl+T from the editor runs `main.lua`. _proj_
  must exist: `run` makes no
  project, and a name no project has is refused with a hint to
  make it with `project()` first. While a program runs or is
  paused, a typed `run()` is refused, and Ctrl+R stops it and
  runs it again; a program's own `run()` replaces it, as Ctrl+R
  does, once its code has returned. Each run starts afresh: a program idle behind the
  console ends first, as `stop()` ends it, and its handlers,
  input hooks and shortcuts go with it; then no variable,
  `love` handler or module of an earlier run, or of a line
  typed before it, is there, and the graphics settings are
  reset. Stopping a program, by `stop()`, Ctrl+Q, an error in
  its first lines or closing its project, clears them too and
  puts the keyboard and the volume back as the IDE set them; a
  sound it started plays to its end,
  and one set to repeat plays once more and stops. A pause keeps
  everything for `continue()`.

  A program also stops by itself when its code has run to the
  end and nothing of it can act any more: no `love.update` or
  `love.draw`, no key, mouse or touch handler, hook or shortcut,
  no input field showing, no serial handler. That is a stop
  like `stop()`: what the program made goes, its variables and
  functions too. To keep what a file defines and use it from
  the console, run it with `dofile("main.lua")`: it runs in the
  console's environment, as it stands, and what it defines
  stays there. `run()` runs a program that starts clean and
  leaves nothing behind.

### The screen

What a program prints goes to the console's text, and what it
draws goes to its picture, kept apart. The screen shows them in
one of three ways:

- **text**: the console's text, the status line and the field;
- **combined**: the console's text over the picture, the way to
  draw from the console;
- **picture**: the picture alone, on the whole screen.

A run starts with the text. When the running program first
draws, its picture shows; a line typed in the console that draws
shows the text over the picture. A pause shows the text, and
`continue()` brings back what showed before. A stop shows the
text and keeps the picture until the next run or `reset()`.

- `compy.screen.show(mode)`

  Show `"text"`, `"combined"` or `"picture"`, from a program or
  a line typed in the console. A program's choice holds against
  its first drawing until the run ends; any other name stops the
  program with an error on the line that called it.

- `compy.screen.getMode()`

  The mode the screen shows: `"text"`, `"combined"` or
  `"picture"`.

<kbd>F12</kbd> shows the next mode, text, combined, picture and
text again, whether a program runs, is paused or none is; the
status line names the mode and the key, `text>F12` or
`comb>F12`, except under the key card while <kbd>F1</kbd> is
held. When <kbd>F12</kbd> brings the full picture up, the
status line shows on the last row for two seconds over a dimmed
band, reading `picture` and `view>F12`, then disappears, or
leaves with the view on a key or mouse button; a picture a
program brings up by itself shows none. In the editor
<kbd>F12</kbd> does nothing, and its status line names no mode.
A running program never gets <kbd>F12</kbd>.

On the full picture, any key or mouse button goes back to the
text, and types or clicks nothing. While a program that can still act runs, its keys and clicks
are its own on the full picture too, and <kbd>F12</kbd> is the
way back. A pause with a picture says so: `F12 shows the
picture`.

- `example_projects()`

  Copy the included example projects to the projects folder.

- `close_project()`

  Close currently opened project and return to the default
  `scratchpad` project.

- `reset()`

  Stop the program if one runs, clear what it and the lines
  typed before left (variables, handlers, settings), silence
  every sound, empty the console as
  <kbd>Ctrl</kbd>+<kbd>L</kbd> does and clear the program's
  picture; then it says
  `Runtime reset for <project>. All files kept.`; like `stop()`,
  it ends the code that called it and returns nothing. The history
  and the editor's files stay. Only `reset()` with
  nothing between the brackets exists yet.

- `reset_scratchpad()`

  Set the default `scratchpad` project aside as
  `scratchpad.old` (or `scratchpad.old.N` when that is taken) and
  start it again with factory contents.

- `edit(file)`

  Open file in editor. If it does not exist yet, a new file will
  be created. See [Editor mode](#editor)

### Files

Once a project is open, file operations are available on it's
contents.

- `list_contents()`

  List files in the project.

- `readfile(file)`

  Open _file_ and return it's contents as a single string.

- `readlines(file)`

  Open _file_ and return a string table of it's lines.

- `writefile(file, content)`

  Write to _file_ the text supplied as the _content_ parameter.
  This can be either a string, or an array of strings.

- `tidy(file)`

  Lay out the code in _file_ (`main.lua` if none is given) the
  way the editor writes it. Returns `true` when the file is
  tidy; when it cannot be tidied, says why and leaves it as it
  is.

## Editor

If a project is open, the files inside can be edited or new ones
created. Run the `edit()` command to do so.

![edit](./doc/interface/open_edit.apng)

When a file is opened, the editor is scrolled to the end by
default, and entered input will be appended to the end.

![hello](./doc/interface/hello.apng)

The editor is always in one of three states, which the status
line names. With an empty field you are _browsing_: the
highlight shows the block you are on, or no block at the end of
the file. Once you type, you are _inserting_: <kbd>Enter ⏎</kbd>
puts the text before the highlighted block, or at the end of the
file. Hold <kbd>F1</kbd> to see the keys of the current state.

To modify an existing block, navigate there with
<kbd>⇧</kbd>/<kbd>⇩</kbd>. Load it into the field by pressing
<kbd>F2</kbd>: you are now _replacing_ it. Make the desired
changes, then send it back with <kbd>Enter ⏎</kbd>.
<kbd>Esc</kbd> drops the change and leaves the block as it was.

![capitalized](./doc/interface/hello_cap.apng)

In a Lua file a block is a statement, a comment or an empty
line, and a text that is not valid Lua is not accepted. In a text or
Markdown file every line is a block, and a line is accepted as
written.

When the highlighted block, or the block you are replacing, goes
on beyond the top or the bottom of the screen, the row at that
edge fades toward it and shows a faint `^` or `v` in its last
column. Other blocks the screen cuts off get no mark. The field
does the same when its text has more rows than it shows. A line
too long for one row goes on in the next: a tiny orange corner
at the top right of a row says it goes on, and one at the bottom
left of the next row says it continues.

When the editor cannot do what a key asks, it shows a notice
just above the status line that says why and what would work.
The next key dismisses it and does its usual work. The editor
asks no questions.

Happy with the modifications now, we can leave the editor by
pressing <kbd>Esc</kbd> with an empty field, which steps back one
file at a time, or <kbd>Ctrl-Q</kbd>, which returns to the console
from any file.
While there is text in the field or a block is being replaced,
leaving is refused with a notice: submit the text with
<kbd>Enter ⏎</kbd> or drop it with <kbd>Esc</kbd> first.

![quit](./doc/interface/quit_editor.apng)

#### Moving

Browse to the block you want to move and press
<kbd>Alt</kbd>+<kbd>⇧</kbd> or <kbd>Alt</kbd>+<kbd>⇩</kbd>: each
press moves it one block up or down, and the file is saved with
it. <kbd>Ctrl-Z</kbd> takes a move back.

![move1](./doc/interface/move_line.apng)
![move2](./doc/interface/move_block.apng)


# Usage (playback mode)

`love compy.love play <project>`

* `<project>` is either
  * a `.compy` package (a zipped project)
  * a folder containing a valid project

Paths will be searched in the following order:
* for zips:
  * current directory (or absolute path)
  * compy storage directory
* for folders
  * current directory (or absolute path)
  * compy storage directory
  * projects directory

## Keys

| Command          | Combination                                 |
| :--------------- | :------------------------------------------ |
| Restart project  | <kbd>Ctrl</kbd>+<kbd>R</kbd>             |
| Exit application | <kbd>Ctrl</kbd>+<kbd>Esc</kbd>              |

#

[löve2d]: https://love2d.org
