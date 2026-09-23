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
  - Hence, submitting the content only replaces if the highlight
    is the same it was loaded from.

### Keys

| Command                                                           | Keymap                                        |
| :---------------------------------------------------------------- | :-------------------------------------------- |
| Clear terminal                                                    | <kbd>Ctrl</kbd>+<kbd>L</kbd>                  |
| Stop project                                                      | <kbd>Ctrl</kbd>+<kbd>S</kbd>                  |
| Quit project (stop and close)                                     | <kbd>Ctrl</kbd>+<kbd>Q</kbd>                  |
| Reset application to initial state                                | <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>R</kbd> |
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
| Jump to line start                                                | <kbd>Home</kbd>                               |
| Jump to line end                                                  | <kbd>End</kbd>                                |
| Insert newline                                                    | <kbd>Shift</kbd>+<kbd>Enter ⏎</kbd>           |
| Delete current line                                               | <kbd>Ctrl</kbd>+<kbd>Y</kbd>                  |
| Duplicate current line                                            | <kbd>Ctrl</kbd>+<kbd>D</kbd>                  |
| Copy                                                              | <kbd>Ctrl</kbd>+<kbd>C</kbd> / <kbd>Ctrl</kbd>+<kbd>Insert</kbd> |
| Cut                                                               | <kbd>Ctrl</kbd>+<kbd>X</kbd> / <kbd>Shift</kbd>+<kbd>Delete</kbd> |
| Paste                                                             | <kbd>Ctrl</kbd>+<kbd>V</kbd> / <kbd>Shift</kbd>+<kbd>Insert</kbd> |
| Select text                                                       | <kbd>Shift</kbd>+<kbd>⇦</kbd>/<kbd>⇨</kbd>/<kbd>⇧</kbd>/<kbd>⇩</kbd> |
| Evaluate input                                                    | <kbd>Enter ⏎</kbd>                            |
| **Editor**                                                        |                                               |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; _same as Input, except for:_ |                                               |
| Move the active line by one line (nav)                            | <kbd>⇧</kbd>/<kbd>⇩</kbd>                     |
| Move the active line by a page (nav)                              | <kbd>PageUp</kbd>/<kbd>PageDown</kbd>         |
| First / last line of the file (nav)                               | <kbd>Home</kbd> / <kbd>End</kbd>              |
| Move the cursor through the block (editing)                       | <kbd>⇧</kbd>/<kbd>⇩</kbd>                     |
| Jump block-wise (nav) / accept and jump (editing)                 | <kbd>Ctrl</kbd>+<kbd>⇧</kbd>/<kbd>Ctrl</kbd>+<kbd>⇩</kbd> |
| Accept the block, write it to the file (editing)                  | <kbd>Enter ⏎</kbd>                            |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; _additionally_               |                                               |
| Open the selected block for editing (nav)                         | <kbd>Enter ⏎</kbd> / typing                   |
| New empty block below / above, opened (nav)                       | <kbd>Ctrl</kbd>+<kbd>Enter ⏎</kbd> / <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>Enter ⏎</kbd> |
| Accept and return to navigation (editing)                         | <kbd>Ctrl</kbd>+<kbd>Enter ⏎</kbd>            |
| Discard the edit, asks when changed (editing) / leave (nav)       | <kbd>Shift</kbd>+<kbd>Esc</kbd>               |
| Confirm / cancel a dialog                                         | <kbd>Enter ⏎</kbd> or <kbd>Space</kbd> / <kbd>Esc</kbd> |
| Delete the previous word (editing)                                | <kbd>Ctrl</kbd>+<kbd>Backspace</kbd> / <kbd>Ctrl</kbd>+<kbd>W</kbd> |
| Undo / redo: text (editing), file operations (nav)                | <kbd>Ctrl</kbd>+<kbd>Z</kbd> / <kbd>Ctrl</kbd>+<kbd>Y</kbd> |
| Peek-scroll one line, the selection stays                         | <kbd>Alt</kbd>+<kbd>⇧</kbd>/<kbd>Alt</kbd>+<kbd>⇩</kbd> |
| Peek-scroll one page                                              | <kbd>Alt</kbd>+<kbd>PageUp</kbd>/<kbd>Alt</kbd>+<kbd>PageDown</kbd> or <kbd>Alt</kbd>+<kbd>⇦</kbd>/<kbd>Alt</kbd>+<kbd>⇨</kbd> |
| Peek to the start / end of the file                               | <kbd>Alt</kbd>+<kbd>Home</kbd> / <kbd>Alt</kbd>+<kbd>End</kbd> |
| Copy block                                                        | <kbd>Ctrl</kbd>+<kbd>C</kbd> / <kbd>Ctrl</kbd>+<kbd>Insert</kbd> |
| Cut block                                                         | <kbd>Ctrl</kbd>+<kbd>X</kbd> / <kbd>Shift</kbd>+<kbd>Delete</kbd> |
| Paste                                                             | <kbd>Ctrl</kbd>+<kbd>V</kbd> / <kbd>Shift</kbd>+<kbd>Insert</kbd> |
| Delete the selected block (nav)                                   | <kbd>Delete</kbd> / <kbd>Ctrl</kbd>+<kbd>Delete</kbd> |
| Checkpoint the file (asks when one exists)                        | <kbd>Ctrl</kbd>+<kbd>K</kbd>                  |
| Restore from the checkpoint (asks)                                | <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>K</kbd> |
| Follow the require under selection                                | <kbd>Ctrl</kbd>+<kbd>J</kbd>                  |
| Block reorder mode                                                | <kbd>Ctrl</kbd>+<kbd>M</kbd>                  |
| Search definitions                                                | <kbd>Ctrl</kbd>+<kbd>F</kbd>                  |
| Format the whole file (nav)                                       | <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>F</kbd> |
| Scroll to start / end                                             | <kbd>Ctrl</kbd>+<kbd>PageUp</kbd> / <kbd>Ctrl</kbd>+<kbd>PageDown</kbd> |
| Scroll up / down by one line                                      | <kbd>Shift</kbd>+<kbd>PageUp</kbd> / <kbd>Shift</kbd>+<kbd>PageDown</kbd> |

### Usage

If a project is open, the files inside can be edited or new ones
created. Run the `edit()` command to do so.

![edit](./interface/open_edit.apng)

When a file is opened, the editor is scrolled to the end by
default, and entered input will be appended to the end.

![hello](./interface/hello.apng)

To modify an existing block, navigate to it with
<kbd>⇧</kbd>/<kbd>⇩</kbd>. Open it for editing by pressing
<kbd>Enter ⏎</kbd>, make the desired changes, then send it back
with <kbd>Enter ⏎</kbd>

![capitalized](./interface/hello_cap.apng)

Happy with the modifications now, we can leave the editor by
pressing <kbd>Shift-Esc</kbd>

![quit](./interface/quit_editor.apng)
