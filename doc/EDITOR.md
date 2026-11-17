# Editor

## Principles

- The contents only change on either <kbd>Enter</kbd> or
  combinations of at least two keys (such as
  <kbd>Ctrl</kbd>+<kbd>Delete</kbd>).
- The editor shows a file as the SD card holds it, and writes
  nothing over a change made outside it. A file that a run of your
  project or a console command such as `tidy()` changed while the
  editor was away comes back with its new text when you return with
  <kbd>Ctrl</kbd>+<kbd>T</kbd>, and its undo history starts again;
  so does a file you return to with <kbd>Escape</kbd>. A file
  changed while the editor shows it keeps the text it had: each
  key that would write it (<kbd>Enter</kbd>, a cut, a move,
  <kbd>Alt</kbd>+<kbd>F</kbd>,
  <kbd>Ctrl</kbd>+<kbd>Z</kbd>, <kbd>Ctrl</kbd>+<kbd>Y</kbd>) says
  it changed and saves nothing, and so does each when the file
  cannot be read. To see what the SD card holds then, leave the
  editor (<kbd>Ctrl</kbd>+<kbd>Q</kbd>) and open the file again
  with `edit()`.
- `edit()` in the console starts the editor afresh: the files a
  run came from close, and the file opens alone, at its end.
  <kbd>Ctrl</kbd>+<kbd>T</kbd> is the way back to them.
- A change to a Lua file is saved only as valid Lua, and only if
  the file still loads after it; in a file that does not load,
  only the change's own text is checked, so that you can repair
  it. A text or Markdown file is saved as you write it.
- Editor contents should only change when it's the user's
  explicit aim. Operations which could be interpreted otherwise
  should not make changes as a side effect.
  - Hence, submitting the content only replaces the block that
    was loaded with <kbd>F2</kbd>, wherever the highlight has
    moved since; any other text is inserted as new blocks.
- The editor asks no questions. A refused action shows a notice
  and changes nothing.
- Each combination is a key of its own: a key pressed with a
  modifier the table below does not name does nothing.
  <kbd>Ctrl</kbd>+<kbd>Enter</kbd> is not <kbd>Enter</kbd>.
- While <kbd>F1</kbd> is held and the card shows, in the editor
  or in the console, every other key does nothing,
  <kbd>Ctrl</kbd>+<kbd>Q</kbd> and the other reserved keys
  included, and so does the mouse; only
  <kbd>Ctrl</kbd>+<kbd>Esc</kbd> acts. In your program F1 holds
  back nothing.
- A click in the field places the cursor, as in the console and
  in your program's input; a click on the file does nothing.
  <kbd>Shift</kbd> with a movement key, or a drag of the mouse,
  selects a part of the draft: typing replaces it, and
  <kbd>Backspace</kbd> or <kbd>Delete</kbd> removes it, which
  <kbd>Ctrl</kbd>+<kbd>Z</kbd> takes back. Nothing copies or
  pastes: <kbd>Ctrl</kbd>+<kbd>Insert</kbd>,
  <kbd>Ctrl</kbd>+<kbd>Delete</kbd> and
  <kbd>Shift</kbd>+<kbd>Insert</kbd> keep their meaning for
  blocks.
- Held down, a key repeats, and each stops by itself: a held
  <kbd>Enter</kbd> adds an empty line per repeat, a held
  <kbd>Ctrl</kbd>+<kbd>Delete</kbd> removes the empty lines down
  to the next block with text, cuts it and stops, and a held
  <kbd>Alt</kbd>+<kbd>Up</kbd> moves the block up to the file's
  start. <kbd>Ctrl</kbd>+<kbd>Z</kbd> and
  <kbd>Ctrl</kbd>+<kbd>Y</kbd> repeat through the field's own
  changes only. These keys act once per press:
  <kbd>Escape</kbd> (a repeat would leave the file, and with it
  the undo of a cut block; <kbd>Ctrl</kbd>+<kbd>Q</kbd> leaves
  every file at once), <kbd>Shift</kbd>+<kbd>Insert</kbd> and
  <kbd>Ctrl</kbd>+<kbd>Insert</kbd> (each repeat would add a
  copy), <kbd>Ctrl</kbd>+<kbd>J</kbd> (rushing through files
  confuses), <kbd>Ctrl</kbd>+<kbd>T</kbd> and
  <kbd>Ctrl</kbd>+<kbd>R</kbd>, and <kbd>Enter</kbd> in the
  console and in your program's input field.

### Keys

| Command                                                           | Keymap                                        |
| :---------------------------------------------------------------- | :-------------------------------------------- |
| Clear terminal                                                    | <kbd>Ctrl</kbd>+<kbd>L</kbd>                  |
| Stop the program and return to the console (the project stays open) | <kbd>Ctrl</kbd>+<kbd>Q</kbd>                  |
| Restart project                                                   | <kbd>Ctrl</kbd>+<kbd>R</kbd>               |
| Exit application                                                  | <kbd>Ctrl</kbd>+<kbd>Esc</kbd>                |
| Pause project                                                     | <kbd>Ctrl</kbd>+<kbd>Pause</kbd>              |
| Toggle edit/run                                                   | <kbd>Ctrl</kbd>+<kbd>T</kbd>                  |
| **Input**                                                         |
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
| Select a part of the draft; typing replaces it, Backspace or Delete removes it | <kbd>Shift</kbd>+movement, or drag |
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

### Usage

If a project is open, the files inside can be edited or new ones
created. Run the `edit()` command to do so.

![edit](./interface/open_edit.apng)

When a file is opened, the editor is scrolled to the end by
default, and entered input will be appended to the end.

![hello](./interface/hello.apng)

The editor is always in one of three states, which the status
line names. With an empty field you are _browsing_: the
highlight shows the block you are on, or no block at the end of
the file. Once you type, you are _inserting_: <kbd>Enter ⏎</kbd>
puts the text before the highlighted block, or at the end of the
file. Hold <kbd>F1</kbd> to see the keys of the current state.

To modify an existing block, navigate to it with
<kbd>⇧</kbd>/<kbd>⇩</kbd>. Load it into the field by pressing
<kbd>F2</kbd>: you are now _replacing_ it. Make the desired
changes, then send it back with <kbd>Enter ⏎</kbd>.
<kbd>Esc</kbd> drops the change and leaves the block as it was.

![capitalized](./interface/hello_cap.apng)

In a Lua file a block is a statement, a comment or an empty
line, and a text that is not valid Lua is not accepted. Its empty lines are
the formatter's: a run of them is kept as one. <kbd>F2</kbd> loads
any block, one longer than 14 lines or with a line longer than
64 characters too; <kbd>Enter ⏎</kbd> accepts it once it keeps
to those limits. In a text or Markdown file every line is a
block, and a line is accepted as written.

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
A text that is not valid Lua gets the parser's message there,
in red; a notice is orange. The next key dismisses the message
and does its usual work. The editor asks no questions.

Happy with the modifications now, we can leave the editor by
pressing <kbd>Esc</kbd> with an empty field, which steps back one
file at a time, or <kbd>Ctrl-Q</kbd>, which returns to the console
from any file.
While there is text in the field or a block is being replaced,
leaving is refused with a notice: submit the text with
<kbd>Enter ⏎</kbd> or drop it with <kbd>Esc</kbd> first.

![quit](./interface/quit_editor.apng)
