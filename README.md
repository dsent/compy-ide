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

## Keys

| Command                                                           | Combination                                   |
| :---------------------------------------------------------------- | :-------------------------------------------- |
| Clear the console's screen and the output it keeps                | <kbd>Ctrl</kbd>+<kbd>L</kbd>                  |
| Stop the program and return to the console (the project stays open) | <kbd>Ctrl</kbd>+<kbd>Q</kbd>                  |
| Restart project                                                   | <kbd>Ctrl</kbd>+<kbd>R</kbd>               |
| Exit application                                                  | <kbd>Ctrl</kbd>+<kbd>Esc</kbd>                |
| Pause project                                                     | <kbd>Ctrl</kbd>+<kbd>Pause</kbd>              |
| Toggle edit/run                                                   | <kbd>Ctrl</kbd>+<kbd>T</kbd>                  |
| **Console output**                                                |                                               |
| Scroll the output a row (the field keeps its text)                | <kbd>Ctrl</kbd>+<kbd>⇧</kbd>/<kbd>Ctrl</kbd>+<kbd>⇩</kbd> |
| Scroll the output a page of 15 rows                               | <kbd>PageUp</kbd>/<kbd>PageDown</kbd>         |
| To the oldest / newest row of the output (empty field)            | <kbd>Home</kbd>/<kbd>End</kbd>                |
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
| Evaluate input                                                    | <kbd>Enter ⏎</kbd>                            |
| **Editor**                                                        |                                               |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; _same as Input in the field, except for:_ |                                               |
| Browse the file block by block                                    | <kbd>Ctrl</kbd>+<kbd>⇧</kbd>/<kbd>Ctrl</kbd>+<kbd>⇩</kbd> |
| Browse block by block (empty field) / move the cursor a row (text in the field) | <kbd>⇧</kbd>/<kbd>⇩</kbd>                     |
| Page down / up: the next block hidden below comes to the top, the one above to the bottom | <kbd>PageDown</kbd>/<kbd>PageUp</kbd>        |
| To the first block / the end of the file (empty field)            | <kbd>Home</kbd>/<kbd>End</kbd>                |
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
beyond; new output leaves it where it is, and any other key but
a modifier, a lock key or <kbd>F1</kbd> brings the screen back,
as do a program's start, stop or pause and a key the program
takes. Each line the console runs is
written to the output in blue before it runs, and its error
after it, in red. A command that refuses says why in the output,
in orange. The band above the status line belongs to the line
being typed: it says why a line did not run because it does not
parse, and, in orange, that a statement is not finished yet,
when <kbd>Enter</kbd> begins its next line instead of running it.
<kbd>Ctrl</kbd>+<kbd>L</kbd> empties the console: the
screen, the kept rows and output still waiting to be written;
`compy.terminal.clear()` from a program clears the screen alone.
While a program's input field shows, or the program takes the
keys itself, the scrolling keys are the program's.

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
  arguments are passed.

- `example_projects()`

  Copy the included example projects to the projects folder.

- `close_project()`

  Close currently opened project and return to the default
  `scratchpad` project.

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
too long for one row goes on in the next, and each row that
continues it has a tiny rounded corner at its top left.

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
