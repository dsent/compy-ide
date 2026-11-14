# Editor

## Principles

- The contents only change on either <kbd>Enter</kbd> or
  combinations of at least two keys (such as
  <kbd>Ctrl</kbd>+<kbd>Delete</kbd>).
- The contents shown on canvas always correspond to the contents
  on disk (SD card).
- The contents are always validated, changes cannot be persisted
  unless syntactically valid.
- Editor contents should only change when it's the user's
  explicit aim. Operations which could be interpreted otherwise
  should not make changes as a side effect.
  - Hence, submitting the content only replaces the block that
    was loaded with <kbd>F2</kbd>, wherever the highlight has
    moved since; any other text is inserted as new blocks.
- The editor asks no questions. A refused action shows a notice
  and changes nothing.

### Keys

| Command                                                           | Keymap                                        |
| :---------------------------------------------------------------- | :-------------------------------------------- |
| Clear terminal                                                    | <kbd>Ctrl</kbd>+<kbd>L</kbd>                  |
| Stop the program and return to the console (the project stays open) | <kbd>Ctrl</kbd>+<kbd>Q</kbd>                  |
| Restart project                                                   | <kbd>Ctrl</kbd>+<kbd>Alt</kbd>+<kbd>R</kbd>   |
| Exit application                                                  | <kbd>Ctrl</kbd>+<kbd>Esc</kbd>                |
| Pause project                                                     | <kbd>Ctrl</kbd>+<kbd>Pause</kbd>              |
| Toggle edit/run                                                   | <kbd>Ctrl</kbd>+<kbd>T</kbd>                  |
| **Input**                                                         |
| Move cursor horizontally                                          | <kbd>⇦</kbd>/<kbd>⇨</kbd>                     |
| Move cursor vertically                                            | <kbd>⇧</kbd>/<kbd>⇩</kbd>                     |
| Go back in command history                                        | <kbd>PageUp</kbd>                             |
| Go forward in command history                                     | <kbd>PageDown</kbd>                           |
| Move in history (if in first/last line)                           | <kbd>⇧</kbd>/<kbd>⇩</kbd>                     |
| Jump to start                                                     | <kbd>Ctrl</kbd>+<kbd>Home</kbd>               |
| Jump to end                                                       | <kbd>Ctrl</kbd>+<kbd>End</kbd>                |
| Jump to the start of the row (a long line takes several rows)     | <kbd>Home</kbd>                               |
| Jump to the end of the row                                        | <kbd>End</kbd>                                |
| Insert newline                                                    | <kbd>Shift</kbd>+<kbd>Enter ⏎</kbd>           |
| Delete current line                                               | <kbd>Ctrl</kbd>+<kbd>Y</kbd>                  |
| Copy                                                              | <kbd>Ctrl</kbd>+<kbd>C</kbd> / <kbd>Ctrl</kbd>+<kbd>Insert</kbd> |
| Cut                                                               | <kbd>Ctrl</kbd>+<kbd>X</kbd> / <kbd>Shift</kbd>+<kbd>Delete</kbd> |
| Paste                                                             | <kbd>Ctrl</kbd>+<kbd>V</kbd> / <kbd>Shift</kbd>+<kbd>Insert</kbd> |
| Select text                                                       | <kbd>Shift</kbd>+<kbd>⇦</kbd>/<kbd>⇨</kbd>/<kbd>⇧</kbd>/<kbd>⇩</kbd> |
| Evaluate input                                                    | <kbd>Enter ⏎</kbd>                            |
| **Editor**                                                        |                                               |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; _same as Input in the field, except for:_ |                                               |
| No text selection: Shift with an arrow moves the cursor, and Ctrl+C and Ctrl+X do nothing | <kbd>Shift</kbd>+<kbd>⇦</kbd>/<kbd>⇨</kbd>/<kbd>⇧</kbd>/<kbd>⇩</kbd>, <kbd>Ctrl</kbd>+<kbd>C</kbd>, <kbd>Ctrl</kbd>+<kbd>X</kbd> |
| Browse the file block by block                                    | <kbd>Ctrl</kbd>+<kbd>⇧</kbd>/<kbd>Ctrl</kbd>+<kbd>⇩</kbd> |
| Browse block by block (empty field) / move the cursor a row (text in the field) | <kbd>⇧</kbd>/<kbd>⇩</kbd>                     |
| Browse ten blocks                                                 | <kbd>PageUp</kbd>/<kbd>PageDown</kbd>         |
| Insert the field's text before the highlighted block, or at the end of the file | <kbd>Enter ⏎</kbd>                            |
| Insert an empty line (empty field)                                | <kbd>Enter ⏎</kbd>                            |
| Load the highlighted block into the field, to replace it          | <kbd>F2</kbd>                                 |
| Replace the loaded block with the field's text                    | <kbd>Enter ⏎</kbd>                            |
| Insert or replace, and keep the text in the field                 | <kbd>Shift</kbd>+<kbd>Insert</kbd>            |
| Break a line in the field                                         | <kbd>Shift</kbd>+<kbd>Enter ⏎</kbd> / <kbd>Alt</kbd>+<kbd>Enter ⏎</kbd> |
| Drop the field's text or the replacement; step back from the file (empty field) | <kbd>Esc</kbd>                                |
| Leave the editor for the console, every open file with it (empty field) | <kbd>Ctrl</kbd>+<kbd>Q</kbd>                  |
| Copy the highlighted block into the field                         | <kbd>Ctrl</kbd>+<kbd>Insert</kbd>             |
| Cut the highlighted block into the field (empty field)            | <kbd>Ctrl</kbd>+<kbd>Delete</kbd> / <kbd>Shift</kbd>+<kbd>Delete</kbd> |
| Delete the character after the cursor (text in the field)         | <kbd>Shift</kbd>+<kbd>Delete</kbd>            |
| Move the highlighted block up / down                              | <kbd>Alt</kbd>+<kbd>⇧</kbd>/<kbd>Alt</kbd>+<kbd>⇩</kbd> |
| Undo / redo                                                       | <kbd>Ctrl</kbd>+<kbd>Z</kbd> / <kbd>Ctrl</kbd>+<kbd>Y</kbd> |
| Delete the previous word in the field                             | <kbd>Ctrl</kbd>+<kbd>Backspace</kbd> / <kbd>Ctrl</kbd>+<kbd>W</kbd> |
| Delete to the end of the line in the field                        | <kbd>Ctrl</kbd>+<kbd>K</kbd>                  |
| Duplicate the field's current line                                | <kbd>Ctrl</kbd>+<kbd>D</kbd>                  |
| Scroll the view one page, the highlight stays                     | <kbd>Alt</kbd>+<kbd>PageUp</kbd>/<kbd>Alt</kbd>+<kbd>PageDown</kbd> or <kbd>Alt</kbd>+<kbd>⇦</kbd>/<kbd>Alt</kbd>+<kbd>⇨</kbd> |
| Scroll the view to the start / end of the file                    | <kbd>Alt</kbd>+<kbd>Home</kbd> / <kbd>Alt</kbd>+<kbd>End</kbd> |
| Checkpoint the file (asks when one exists)                        | _no key at present_                           |
| Restore from the checkpoint (asks)                                | _no key at present_                           |
| Follow the require or dofile of the highlighted block (empty field) | <kbd>Ctrl</kbd>+<kbd>J</kbd>                  |
| Search definitions                                                | <kbd>Ctrl</kbd>+<kbd>F</kbd>                  |
| Format the whole file (empty field)                               | <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>F</kbd> |
| Show the keys of the current state                                | hold <kbd>F1</kbd>                            |
| Leave the editor (deprecated; empty field)                        | <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>S</kbd> |

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

In a Lua file a block is a statement or an empty line, and a
text that is not valid Lua is not accepted. In a text or
Markdown file every line is a block, and a line is accepted as
written.

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
