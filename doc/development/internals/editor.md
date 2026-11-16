# Editor — Implementation Overview

<!-- authored By LLM; human-approved NOT YET -->

## The Core Concept: Block-Centric Editing

The editor does not operate on lines. For Lua files, it operates on **blocks** — top-level syntactic units produced by the metalua chunker. A block is either a `Chunk` (one or more source lines forming a complete top-level statement/expression) or an `Empty` (one blank line; a run of blank lines is a run of `Empty` blocks). The selection highlight, navigation, submit, delete, insert, and move operations all act on blocks, not on individual lines.

The newline ending a file's last line belongs to that line, so no block stands for it: after the last block comes the end position, which has no row of its own. A blank line at the end of the file is an `Empty` like any other.

For plain text and Markdown files, each line is its own block, and a submitted draft is stored as written, one block per line. A file of no lines has no block, in either kind.

This distinction pervades the entire editor stack. Understanding it is the prerequisite for understanding anything else here.

---

## Syntax Processors and Buffer Initialization

The editor names no file type: what differs between kinds of file is the file's **syntax processor**'s to say (`src/model/syntax/`, the maintainer's ruling "The syntax processor"). `EditorController:open()` (`src/controller/editorController.lua`) asks `Syntax.for_name(name)` for the file's syntax, chosen by its name's extension, and gives it to the `BufferModel` and to the file's field as its evaluator. `tests/syntax/editor_names_no_type_spec.lua` checks that the editor's controllers, its buffer and editor models and its views name no type.

| Extension | Syntax | Module |
|---|---|---|
| `.lua` | `lua` | `src/model/syntax/lua.lua`, around the Lua language layer's parser, formatter and gate |
| `.md` | `markdown` | `src/model/syntax/markdown.lua`, the text syntax with Markdown's colors |
| anything else | `text` | `src/model/syntax/text.lua`: a block per line, a draft taken as typed |

`Syntax.register(extension, processor)` adds a syntax, or removes one given nil; `tests/syntax/t4_syntax_spec.lua` drives the editor through keys with a fourth. A processor is a table with these members:

| Member | What it answers |
|---|---|
| `name` | The syntax's name |
| `spans_lines` | Whether a block may span lines; the status line then shows the browsed block's number and its lines, and otherwise its line alone |
| `blocks(lines)` | The file's blocks (`Chunk` and `Empty`, `src/model/editor/content.lua`), tiling lines 1 to n, as a `Dequeue`; nil when the syntax cannot split the text, and the file is then a block per line (`invalid`) |
| `submit(lines, width, max_block)` | A draft's verdict, `{lines, formatted, blocks?, failure?, cursor?, refusal?}`: `blocks` accepts the draft as those blocks. Otherwise `failure` (an `Error` at the failing character) refuses it with the parser's message and the cursor there; any other verdict is shown as the syntax returns it: when `formatted` or `cursor` the field shows `lines` as one undoable change, the cursor at `cursor` (`{l, c}`) or, without one, following the text it stood at, under `refusal` (the notice's text) when there is one. A verdict with no failure and no refusal is a draft that goes on, such as Lua's unfinished draft (IS3.5) |
| `format(lines, width)` | `text, ok, why`: the text formatted, whether the syntax could format it (a text already formatted comes back unchanged, `ok` true), and when not, a phrase the notices put after "The file" or after the file's name, such as "has nothing to format" |
| `loads(lines)` | `ok, why, merges`: whether the file still holds together after a cut or a move, the notice's text when not, and whether the change merged two blocks |
| `highlight(lines)` | The whole text's colors, line by line and column by column (`SyntaxColoring`), or nil; a character with no color takes the color of the one before it in its block |
| `references(lines)` | The files the text names, `{line, name, file}`, `file` being the file Ctrl+J opens |
| `evaluator()` | The evaluator of the file's field |

A `BufferModel` (`src/model/editor/bufferModel.lua`) is created with the syntax and immediately asks it for the file's blocks. A Lua file is read as its lines (`src/util/textfile.lua`), the final newline part of the last one; a file without one reads the same, and saving gives it one. **If the Lua text does not parse, the buffer is marked `invalid = true`** and its blocks are its lines, one block per line, each kept as it is. The editor's parser reads less than LuaJIT: a byte order mark, names outside ASCII, a lone `;`, a form feed, `goto` and labels, and `1LL` make a file `invalid` that LuaJIT runs, so the notices say the editor cannot split the file into blocks, not that it is not Lua. The file opens like any other: text can be inserted, and every other line is written back unchanged. Edit (`F2`) opens a line as it opens any block, formatted when the line parses alone and as it stands otherwise, and `Ctrl+Delete` cuts it into the input; either way the draft is judged at submission as any draft is, on its own (`check.gate`): it must parse by itself, and a line that is half a statement goes on to a new line in the draft (IS3.5) until it is whole. The check that refuses a change which would stop a Lua file loading or merge two blocks (`_reuse_refusal`) leaves such a file alone, since its blocks are lines (`_reads_whole`). A `#!` first line is the language layer's matter, and the editor has no code for it: the parser skips it as LuaJIT does and refuses any other line that starts with `#`, the chunker makes it a block of its own, and the formatter keeps it (the maintainer's ruling of November 14, 2026). Everything else follows from the rule that a change leaves the file loadable (`_reuse_refusal`): F2 loads the line and Enter takes it back, changed or not; cutting it is accepted and Ctrl+Z puts it back; moving it down, moving a block above it, entering text above it, and a `#!` line entered anywhere but first are refused, since Lua could not run the file after them. In a file that already does not load that rule does not apply, so a `#!` line lands anywhere there. An empty Lua file has no block (`blocks` in `src/model/syntax/lua.lua`). Each change re-chunks the file, so once the text parses the blocks are statements again and `invalid` is cleared (`file_blocks` in `bufferModel.lua`).

**Every block is the file's own lines.** The chunker (`source_blocks` in `src/model/lang/lua/parser.lua`) takes the source lines each statement and each comment spans; spans that share a line are one block, a blank line is an `Empty` (one of spaces keeps them, as `Empty.text`), and a line nothing claims, such as a `#!` line, is a block of its own. A block's text is never re-rendered or wrapped: the view wraps long lines on screen only. `file_blocks` then checks that the blocks hold lines 1 to n, each once, in order and as read; when they do not, the file comes a line per block, as text that does not parse does, so that no line is lost on the next save.

**Line endings.** On opening, LF, CRLF and a lone CR each end a line (`textfile.lines`), and the buffer holds the lines without them; opening writes nothing. `save` writes every line with LF, the last one included, so a last line without a terminator gets one (IS1.2), and a CRLF or CR file becomes an LF file at its first save (the ruling "A file is written with LF line ends"). `stored` keeps the text as read, so a file that was only opened is still the one the editor read.

**A file is written only over what the editor last read or wrote there.** The buffer's `disk_seen` holds that text, or `false` for a file missing when it was opened (`_note_read` and `_note_saved` in `src/controller/editorReuse.lua`). Before every write, the undo and redo included (`_timeline_ready`), the one guard `_refuse_stale` asks `_baseline`, which reads the file again: `same` lets the write go on; `changed` (other text, a file removed, or one created since) and `unknown` (the file is there and gives no text) refuse it with a notice, and nothing changes: the draft, the target and the timeline stay. This is the editor's whole handling of storage that fails or changes under it (the ruling "A lost SD card is the IDE's failure to handle"). A file that is there and gives no text is not opened at all (`ConsoleController:edit`; `Project:readfile` fails for it), nor one the editor could not save, such as a file in a folder of the project. A missing file opens as a new one.

After construction, `lateinit` calls `analyze()` immediately to populate semantic info.

---

## The Input Widget's Role

The editor does not have its own widget — it reuses `UserInputModel` / `UserInputController` / `UserInputView`, the same widget as the console REPL. The input strip at the bottom is how you type content to put into the buffer.

The editor is in one of three states, which nothing stores: `EditorController:state_name()` derives it. A replacement target (`BufferModel.loaded`) means **replacing**; otherwise a non-empty draft in the input means **inserting**; otherwise the editor is **browsing**. The browsing position is `buffer:get_selection()`, and the end position, after the last block, is `blocks + 1`. A file opens in the browsing state at the end position.

The workflow is:
1. Browse to the block of interest (`Ctrl+Up`/`Ctrl+Down`, or bare `Up`/`Down` while the input is empty)
2. Press `F2` (Edit) to **load** the block's text into the input; the block becomes the replacement target
3. Edit in the input
4. Press `Enter` to **submit** the input back, replacing the target

Text typed without a target is inserted: `Enter` puts it before the block at the browsing position, or at the end of the file from the end position. `Esc` aborts an edit (the draft and the target are dropped), and from the browsing state steps back from the file. `Ctrl+Insert` copies the viewed block into the input, `Ctrl+Delete` cuts it there, and `Alt+Up`/`Alt+Down` move it (`src/controller/editorReuse.lua`).

A refused action never asks a question: `EditorController:refuse(msg)` knocks and shows a notice, wrapped between words, in a band directly above the status line (`EditorView:draw_message`, which draws the field's notice band, `UserInputView:draw_notice`; the console shows in the same band why a line was not taken, and a pause's text). The band covers the document view's last rows; the status line, the input and the view stay where they are. A syntax failure's message shows the same way, as kind `'error'` (`refuse(msg, 'error')`): the band, which has no frame, is black and writes an error in red and a notice in orange (`colors.input.notice`: `bg`, `error`, `warning`, kept apart from a program's own `error_bg` and `error`, which hold the same colours); it stands apart from the console's status line, which is a near-black gray, #181818 (`colors.statusline.console`; its `warning`, `[no sd card]`, is the other status lines' orange), as is the console's key card, which takes its surface's status-line colours; `EditorController:message_kind()` tells the view which it is. The next key press dismisses the message and does its ordinary work, `Esc` included; a modifier or a lock key alone leaves it showing. `F1`, while held, shows the keys the current state admits (`src/model/editor/keyCard.lua`), in the editor and in the console. The card is decided once, by the F1 press itself: the console's and the editor's key handlers each record the keys whose press reached them (`ConsoleController.pressed`, `EditorController.pressed`), the gate clears a key's record at its release whichever route has the keys (`handlers.keyreleased`, `ConsoleController:key_released`), and a card shows while F1 is held and the surface in front recorded its press (`KeyCard.shows`). A press a program took (its field, a hook, a shortcut, its own handler, or a program holding the screen, where nothing falls through) is recorded nowhere: there is no card and nothing is suspended until F1 is released and pressed again, whatever modifiers come and go and whatever runs or stops meanwhile. While either card shows, the gate holds back every key press but F1's, the reserved chords included, and every text event (`ConsoleController:card_shows`, asked in `love.handlers.keypressed` and `textinput` in `controller.lua`), so no key reaches the console, the editor or a program behind the console's card; a key's repeats and release go on exactly where its press did (`delivered`), and text, which carries no key, only while no card shows, so a key pressed under the card and still held when it closes types its repeats from then on. For the same reason, Ctrl+R held, Ctrl let go and R held on types R's repeats into the restarted program, while R's key events stay the IDE's. Ctrl+Escape is never suspended: its exit is decided when Escape goes down with Ctrl held and comes on Escape's release, whatever is held by then. While either card shows, the gate holds back every mouse and touch event (`ConsoleController:card_shows`, asked in `love.handlers.mousepressed`, `mousereleased`, `mousemoved`, `wheelmoved`, the derived clicks, `touchpressed`, `touchmoved` and `touchreleased`): nothing reaches the console, the editor or a program behind the console's card. A button's release goes where its press went, and a touch's release where its start went, by the touch's id: one held back holds back its release after the card, and one that went through gets its release under the card. The key press during which the editor comes to the front (the gate's Ctrl+T, the Enter of a console `edit()`, a program's key hook) does nothing in it, nor do that key's repeats: a key repeats in the editor only where its press reached it (`came_forward` empties `EditorController.pressed`). The text a printable key's repeats send is not held back: such a key that made a program call `edit()` types into the new draft while it stays held.

The `LuaEditorEval` evaluator (`src/model/interpreter/eval/evaluator.lua`) is the Lua syntax's `evaluator()`, set on a Lua file's field. It parses and colors the draft as a submission reads it, and carries the line rules of `src/model/lang/lua/check.lua` (`line_validators`: the 64-character line, the code conventions' limit).

**Three heights.** `input_max` (14) is the block size limit, the code convention's: a whole block, `function` and `end` included, has at most 14 lines. `bufv:get_max_size()` returns it, and the editor passes it to the gate. It also sizes the input's canvas (`UserInputView`), and the console's field shows up to that many rows. `LINES` (`cfg.view.lines`, 16) is the document view's height (`BufferView`). The editor's field shows at most half the rows it shares with the document view, `floor((lines + 1) / 2)`, 8 on a Compy (`UserInputModel:init_visible`, IS3.13): it grows upwards over the view's last rows (`EditorView:fit_buffer`), and a taller draft, a 14-line block included, scrolls to keep the cursor's row shown (`_follow_cursor`). A Compy's values for both limits, the 64-column line and the 14-line block, live in `src/conf/display.lua`, where tools that format away from a Compy read them.

---

## The `loaded` Tracker — Why It Exists

`BufferModel.loaded` records which block index was most recently loaded into the input. This prevents a specific foot-gun: if you load block 3, then navigate the selection to block 7 (the highlight moves), then press Enter, you don't want to overwrite block 7 with what you loaded from block 3.

A submission with a replacement target replaces that block, wherever the browsing position stands by then (`EditorController:_land`). Browsing during a replacement moves the highlight only; the target keeps its own mark, and `Esc` drops it. The document view draws the browsed block white and the target yellow, each the screen's whole width; a block that is both is yellow with a strip of white one character cell wide at each side (`BufferView:draw`).

**Two marks at the edges.** The continuation cue (FR4.8; `src/view/continuationCue.lua`) marks an edge of the document view beyond which rows of the browsed block or of the target lie (`BufferView:draw`, `draw_cues`), and an edge of the field beyond which rows of the draft lie (`UserInputView:render_input`, for the editor's, the console's and a program's field alike): the edge row's own background is laid over it in 16 bands, `fade` opaque at the edge, and its last column carries `^` or `v`, `mark_alpha` opaque on a `box_alpha` box. A block the view merely cuts has none. The notice band, drawn after the view, covers a cue at the bottom edge until the next key. A wrapped line's marks (`src/view/wrapMark.lua`) are small fillets: the pixels of a `size`-by-`size` corner outside the circle round its far corner, drawn as runs of one-pixel rectangles. One stands at the top right of every row that goes on below, against the last text column (`drawableChars * fw`), and one, mirrored, at the bottom left of every row that continues the one above (`WrapMark.places`). They are drawn under the text in the document view (after the highlights) and in the field (before the draft's text), so the glyphs, a selection and the cursor paint over them. An edge row that carries a continuation cue takes no top-right mark, since the cue stands in that column (`bare`); a field's row kept for the cursor after its text is no row of a line. The colours, opacities and the marks' colour (the status lines' orange), `size` (8) and outer-corner `round` are the theme's (`colors.editor.cue`, `colors.editor.wrap_mark`, `src/conf/colors.lua`). The console's printed output has no mark: the terminal's grid does not know which rows were one line.

---

## The Submit Pipeline

Pressing `Enter` on non-empty input goes through `_handle_submit`, which asks the file's syntax for its verdict (`submit`). The text and Markdown syntaxes take a draft as typed, a block per line. In a Lua file the verdict is the Lua syntax's (`src/model/syntax/lua.lua`), the file editor's one way into the Lua language layer (`src/model/lang/`, the vendored metalua), which the editor does not change. A draft that is no Lua where it lands is refused with its parse failure before anything else (IS3.2): at the failing character (`failure`, which reads the token the parser stopped at; IS3.4). A draft that is only unfinished is no failure: the syntax returns it with a line break added at its end and the cursor on the new line (`went_on`; IS3.5), and the editor shows that as it shows any draft the syntax returns. The field's evaluator asks the same question of the same code through its parser's `unparsed` (`M.parser()`), so the console's field goes on in the same way and colors no failure red. Otherwise the verdict is the language layer's own, `check.gate(lines, width, max_block)` in `src/model/lang/lua/check.lua`, which every other tool that wants it calls too; `submission` only presents it, naming the line a line refusal is for. A draft's empty lines are what the formatter leaves of them, a run of them one empty line at the draft's start, between statements and at its end, and a draft of empty lines alone one empty line (the ruling "The formatter decides a draft's empty lines", which departs from IS3.7's empty-line block per empty line); the editor puts none back. The gate:

1. **Format** — `format.format(lines, width)` (`src/model/lang/lua/format.lua`) rewrites the text through metalua's printer (`ast_to_src`). The result may differ from what was typed (spacing, indentation, end-placement). Where the source has one or more blank lines before a statement or an own-line comment, at any nesting depth, the printer emits exactly one empty line. The start of an indented body keeps none, so the indented placeholder line of an empty function body is regenerated and never read as a typed blank line. Blank lines ending the text follow no token the printer measures from; `format` keeps one there. The formatted text must parse to the same program, with the same comment text, and must come out unchanged when formatted again; otherwise, and when the text does not parse, `format` returns it as it was. The printer's own behaviour is covered by `tests/interpreter/ast_spec.lua`, `format`'s by `tests/interpreter/format_spec.lua`.
2. **Line and parse rules** — `check.check` runs on the formatted text: line length (the Compy's 64 columns), then a parse. A line over the limit is refused with a notice naming the line and its length; the input shows the formatted text, and the cursor stays where it stood (IS3.9). A long line the formatter wraps is no refusal.
3. **Chunk and measure** — the formatted text is chunked into the blocks that will be stored, and a block longer than `max_block` (the block size limit, `input_max` = 14) makes the verdict name that block. The syntax refuses the whole draft with a notice that gives the block's length and the limit: the draft stays, shown formatted as one undoable change to it, and the cursor stays where it stood (IS3.9).
4. **No blank line of the editor's own** — nothing adds an `Empty` beyond what step 1 keeps. Blank lines outside the accepted block stay as they are: the chunker makes one `Empty` per blank line, so re-chunking the whole file after the write keeps every run.
5. **Replace or Insert** — `_land` puts the formatted lines in the target's place (`replace_lines`) or before the browsing position (`insert_lines`): a splice of the file's lines, after which the whole file is chunked again (see Block Position Tracking).
6. **Auto-save** — `buf:save()` is called immediately. Every accepted submit writes to disk, each line with LF (see Line endings above), the last one included.

Without a replacement target the new block(s) are inserted before the browsing position, or appended at the end position, and the position ends on the block after them, so typing goes on below. An empty draft inserts one empty line. `Shift+Insert` submits the same way and keeps the draft in the input.

`Alt+F` in the browsing state (`format_file`) formats the whole file as the syntax's `format` does, at the window's width; during an edit it refuses with a notice that says why. In a Lua file that is the same `format` function as above. Every run of blank lines in the file becomes one, a run made one empty line at a time with Enter on an empty field (IS4.3) included: the one place blank lines outside a block change, because the user asked. When the syntax cannot format the text (`ok` false), the editor refuses with "The file" and the syntax's reason, such as "The file has nothing to format." in a text or Markdown file, and the file stays; a Lua file the editor cannot split into blocks (`invalid`) is refused with a notice that says so. A file the formatter leaves as it is changes nothing, and nothing is shown. The selection keeps its place among the blocks with text: on the block with as many blocks with text before it as before, and from an empty line on the next block with text. The REPL's `tidy(name)` formats a file through its syntax's `format` at a Compy's width (`src/conf/display.lua`) and writes it through a `BufferModel`, so it keeps what Alt+F keeps, a `#!` first line included, and writes LF line ends (see Line endings above). `util/compyfmt.lua --fix` formats at the same width and writes every line with a newline. compyfmt reports the gates and the lints (`src/model/lang/lua/lint.lua`); without `--fix` it changes nothing and also names each file formatting would change.

---

## Monster Blocks

A block with more source lines than the editor's size limit is a **monster block**. These can exist in files written outside the editor or imported. The editor handles them without data loss:

- **Viewing** — monster blocks are displayed in the buffer normally; content beyond the visible window is scrolled.
- **Loading** — `F2` opens a monster block as it opens any block: the editor judges no block at loading, whatever it holds (the maintainer's ruling of November 14, 2026, over IS1.3; `_editable_lines` refuses only the end position and an empty line). `Ctrl+Delete` cuts the block out of the file into the input instead, and the browsing position stays at its place. The editor's field shows eight of its rows at a time (see Three heights) and scrolls to the cursor.
- **Submitting** — the draft goes through the submit pipeline like any other. If every block it chunks into is within the size limit, they replace the target, or, after a cut, are inserted at the browsing position, which is the cut block's place unless it was moved (effectively splitting it). If one is still over the limit, the whole draft is refused with a notice that gives that block's length and the limit, and the draft, the target and the cursor stay.

The practical editing pattern: open the monster block with `F2`, edit it into valid code that chunks into conforming-size pieces, submit. Multiple resulting chunks each become their own block in the buffer, separated by the empty lines the formatter leaves between them: one where the draft had one or more (step 1 of the submit pipeline).

Source: commit `2ff95f03b8f8` ("Split monster block"); logic in `editorController.lua` (`_handle_submit`, `_editable_lines`) and in the Lua syntax's `submit`.

---

## Block Position Tracking

Each `Chunk` carries a `pos: Range` recording which source lines it occupies (e.g. `{3-7}` means lines 3 through 7). Since a block's lines are its source lines, `pos` and the rendered text agree, and an insertion or a replacement splices lines at `pos` (`_splice`) and re-chunks the whole file. The re-chunk may split the file anew, from lines into statements when a file that did not parse parses again, or back: so `_splice` keeps the browsing position as a source line, and leaves it on the block that now holds the line it stood on, or, that line gone, the line after the new ones. A caller that knows better sets it after: `_land` on the block after the landed lines, `move` on the moved block, an undo or a redo on the positions its step took in the text it puts back.

This matters because the revmap (source line → block index), used for semantic info, is rebuilt only on `analyze()`, which runs on `buf:save()`. Between saves, the revmap may be stale. In practice this is fine because semantic info is only read by Ctrl+J, and only in the browsing state, which an accepted change leaves saved.

---

## The Visible Content

**`VisibleStructuredContent`** (`src/view/editor/visibleStructuredContent.lua`) is the document view's visible slice of a buffer, for every syntax. Each block wraps independently: it becomes a `VisibleBlock` (`src/view/editor/visibleBlock.lua`) that holds its own `WrappedText` and its rows of the syntax's colors, which the view takes from the whole text's `highlight` and maps through the wrap breaks. `VisibleContent` (`src/view/editor/visibleContent.lua`) is the input field's: it wraps the raw line array and keeps a scroll range over the wrapped lines.

Text in the editor passes through three coordinate spaces (documented with a worked example in `doc/development/editor/visible.md`):

1. **Normal coords** — original source line numbers, as stored in the file
2. **Wrapped coords** — apparent lines after wrapping at the screen's last column, whatever character stands there (the ruling "Long lines wrap at the column"); a single long source line may produce multiple wrapped lines
3. **Visible coords** — the subset of wrapped lines currently in the scroll window

Each block has **two position fields** tracking the first two spaces:
- `pos` — the block's position in source lines (normal coords)
- `app_pos` — the block's position in wrapped/apparent lines (what the view uses for rendering and scroll)

These diverge whenever any block has lines longer than the screen width. Scrolling, selection visibility, and line number display all operate in apparent-line space; source queries (semantic info, revmap) operate in source-line space. The mapping between them is maintained in `VisibleStructuredContent.reverse_map` and recalculated in `recalc_range()`.

The `WrappedText` base class (`src/util/wrapped_text.lua`) provides the three-table mapping structure: `wrap_forward` (source line → list of display lines), `wrap_reverse` (display line → source line), `wrap_rank` (display line → its offset within the wrap break sequence). These are used for cursor coordinate translation in the input and for highlight remapping in `VisibleBlock`.

---

## Leaving and Hiding the Editor

The editor has no modes: the browsing, inserting and replacing states described above are all there is. `EditorController:keypressed` looks each key's full chord up in the state's table (`src/model/editor/editorKeys.lua`), which names its action, whether it repeats while held and the key card's words for it; a chord the table does not name goes to the text field's table (`src/model/input/fieldKeys.lua`, through `UserInputController:names`), and does nothing if that does not name it either. It has no search; Ctrl+F does nothing in it.

`PgDn` and `PgUp` browse a page at a time (`EditorController:_page`, `BufferView:page`): PgDn goes to the first block not wholly visible below the view and shows it from the view's top, PgUp to the last block not wholly visible above and shows it to the view's bottom; with none, PgDn goes to the end position and PgUp to the first block. While rows of the browsed block are hidden beyond the edge in the key's direction, the view moves a page further into the block (to its edge at most) and the position stays, as IS2.2 does a row at a time for the arrows. `Home` and `End` while browsing (`file_edge`) go to the first block and to the end position, and stay there while held; in a draft they are the field's own keys. The view scrolls through browsing alone: there is no key that scrolls it apart from the browsing position.

The whole-editor exits (`Ctrl+T`, `Ctrl+Q`) leave from the browsing state; Ctrl+R does nothing in the editor, where no program is live (`reserved_restart`). `Ctrl+Q` returns to the console with every buffer closed and the project still open (`reserved_stop` in `controller.lua`, which calls `ConsoleController:finish_edit`). A run (`Ctrl+T`, which runs `main.lua`) only hides the editor (`ConsoleController:hide_editor`): every buffer stays as it is, and `Ctrl+T` shows them again (`show_editor`). Hiding dismisses the message, as the key that hides acts (`EditorController:hide`), so no message waits in a hidden file for the editor's return. No program runs or idles behind a shown editor: every way it comes to the screen (`Ctrl+T`, `edit()` from the console or from an idle program's handler) passes `ConsoleController:_enter_editor`, which stops a live program first (`_program_live`: running, paused, or idle with `run_live`), so that none of its hooks or handlers takes the editor's keys or stops, runs or closes the project during an edit. When it had to stop one it shows nothing and its caller asks again, since the program's exit hook may have changed the project. During an edit `EditorController:refuse_to_leave` refuses them with a notice, because the input may hold the only copy of a cut block.

---

## Semantic Analysis

`BufferModel:analyze()` runs on every `save()`. It:
1. Asks the syntax for the files the text names (`references`); the Lua syntax gives the `require()` and `dofile()` calls that write a name out, with their line numbers and the file each names, a module's dots made folders (IS1.5)
2. Builds `revmap` (source line → block index) from block positions
3. Converts them into `BufferSemanticInfo` (`requires`), which replaces line numbers with block indices

This gives the editor **Follow require** (Ctrl+J): if the selected block contains a `require('foo')` or `dofile('foo.lua')` call, open the file as a new buffer on top of the stack. The language layer's own analyzer (`src/model/lang/lua/analyze.lua`) is not called from the editor.

`analyze()` calls the syntax's `references` in `pcall`: when it fails, `analyze()` returns at once and silently, and `self.semantic` stays as it was: nil before the first analysis that succeeded, which leaves Ctrl+J with no file to follow, and the last one's files otherwise.

---

## Buffer Stack and File Navigation

`EditorModel.buffers` is a `Dequeue<BufferModel>` used as a stack (front = active). `EditorView.buffers` is a parallel table keyed by buffer ID (the Lua table address as a string — not the filename). The two stay in sync manually.

Opening a file (`EditorController:open`) pushes a new buffer to the front and tells the view to create a new `BufferView` for it. Escape in the browsing state (`close_buffer`) pops the front buffer and activates the next one. If only one buffer remains, it closes the editor entirely and returns to the console.

Ctrl+J (`follow_require`) calls `self.console:edit(name, true)`, which opens the file only when the project holds it, through a full new `open` call that pushes another buffer. This creates a chain: file A → file B → file C, navigable back with Escape, one file at a time; Ctrl+Q leaves the whole chain for the console. A run of the project from the editor (Ctrl+T, and Ctrl+R on that run, whose way back is Ctrl+T) keeps the chain in memory, untouched. A buffer that comes to the front in the browsing state, the front one when Ctrl+T shows the editor again (`EditorController:show`) and a caller that Escape steps back to (`pop_buffer`), shows what storage holds (`_take_outside_change`): `_baseline` answers, and on `changed` the buffer reads the file anew (`BufferModel:reload`) and its timeline starts afresh, the browsing position keeping its block number while the file has that block and going to the end position otherwise (the end position stays the end); text that is not UTF-8 is not taken (IS1.2). On `unknown` nothing is replaced, and the guard refuses the next write. A change made while the editor shows the file is met by the guard at the next write. `edit()` in the console starts a new editor session (IS1.1): the hidden chain closes as leaving closes it, and the file opens alone at its end position; only Ctrl+T goes back into a hidden chain (IS1.4). Each buffer owns its field (`BufferModel.input`, a `UserInputModel`): its draft, cursor and the draft's undo steps; the editor's field shows the front buffer's (`EditorController:_front`), so a file that goes from the front keeps them with nothing copied. Neither following a file nor a run is leaving it (IS6.6, which names Escape, IS1.6). Leaving is Escape on the file, Ctrl+Q, and a project closed or switched (`_close_project`): the buffers go, and their timelines.

The buffer ID ensures the view can retrieve the right `BufferView` even after the model stack changes order. A buffer popped from the stack takes its view with it (`EditorController:_let_go`), and leaving the editor (`EditorController:close`) empties both tables; while the editor is hidden for a run, both stay.

Only the front buffer can be in an edit: a buffer goes below another one only by Ctrl+J, which is refused during an edit, as is every key that hides or leaves the editor (`refuse_to_leave`); a hidden editor is one left from the browsing state. The guards that refuse leaving therefore ask the front buffer alone.

---

## Key Files

| File | Role |
|---|---|
| `src/controller/editorController.lua` | All input handling, the states, submit pipeline |
| `src/model/editor/bufferModel.lua` | Buffer state, block operations, loaded tracker, save, analyze |
| `src/model/editor/content.lua` | `Chunk` and `Empty` block types |
| `src/model/editor/editorModel.lua` | Model aggregate (input, buffers) |
| `src/model/editor/bufferSemanticInfo.lua` | Gives the files a buffer names their block indices |
| `src/view/editor/bufferView.lua` | Scroll, selection visibility, draw orchestration |
| `src/view/editor/visibleStructuredContent.lua` | Scroll/wrap of a file's blocks |
| `src/view/editor/visibleBlock.lua` | Per-block wrap + highlight remapping |
| `src/util/wrapped_text.lua` | Core wrap tables (forward/reverse/rank) |
| `src/model/syntax/init.lua` | The syntax processors: a file's syntax by its name, and the interface |
| `src/model/syntax/lua.lua` | The Lua syntax, the editor's one way into the Lua language layer: the editor's rules on Lua text around the parser, the formatter and the gate |
| `src/model/input/cursorMap.lua` | The cursor through a reformat of the field's text, and the text's elements |
| `src/model/lang/lua/format.lua` | Formatting: the text as the editor writes it |
| `src/model/lang/lua/check.lua` | Gates: line, parse and block-size rules, and `gate`, the editor's verdict |
| `src/model/lang/lua/lint.lua` | Lints: conventions reported, never refused |
| `src/model/interpreter/eval/evaluator.lua` | Evaluator types including LuaEditorEval |
