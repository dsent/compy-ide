# Editor — Implementation Overview

<!-- authored By LLM; human-approved NOT YET -->

## The Core Concept: Block-Centric Editing

The editor does not operate on lines. For Lua files, it operates on **blocks** — top-level syntactic units produced by the metalua chunker. A block is either a `Chunk` (one or more source lines forming a complete top-level statement/expression) or an `Empty` (one blank line; a run of blank lines is a run of `Empty` blocks). The selection highlight, navigation, submit, delete, insert, and move operations all act on blocks, not on individual lines.

The newline ending a file's last line belongs to that line, so no block stands for it: after the last block comes the view's append row. A blank line at the end of the file is an `Empty` like any other.

For plain text and Markdown files, each line is its own block, and a submitted draft is stored as written, one block per line. A file of no lines has no block, in either kind.

This distinction pervades the entire editor stack. Understanding it is the prerequisite for understanding anything else here.

---

## Content Types and Buffer Initialization

`EditorController:open()` (`src/controller/editorController.lua`) determines content type from the file extension and wires up the right tools:

| Extension | Content type | Tools |
|---|---|---|
| `.lua` | `lua` | metalua chunker, pretty-printer, truncer, highlighter |
| `.md` | `md` | markdown highlighter only |
| anything else | `plain` | none |

A `BufferModel` (`src/model/editor/bufferModel.lua`) is created with these tools and immediately tries to chunk the file content. A Lua file is read as its lines (`src/util/textfile.lua`), the final newline part of the last one; a file without one reads the same, and saving gives it one. **If the Lua text does not parse, the buffer is marked `invalid = true`** and its blocks are its lines, one block per line, each kept as it is. The editor's parser reads less than LuaJIT: a byte order mark, names outside ASCII, a lone `;`, a form feed, `goto` and labels, and `1LL` make a file `invalid` that LuaJIT runs, so the notices say the editor cannot split the file into blocks, not that it is not Lua. The file opens like any other: text can be inserted, and every other line is written back unchanged. Edit (`F2`) is refused on such a line with a notice; `Ctrl+Delete` cuts it into the input for repair. The check that refuses a change which would stop a Lua file loading or merge two blocks (`_reuse_refusal`) leaves such a file alone, since its blocks are lines (`_reads_whole`). A `#!` first line is skipped by the parser as by LuaJIT, and kept by every action, Ctrl+Shift+F included; a `#` line anywhere else is a syntax failure, a draft's first line included unless the draft lands as the file's first lines (`check.gate`'s `at_head`: Enter with the target or the browsing position on block 1), so that a cut `#!` line goes back with Enter. Each change re-chunks the file, so once the text parses the blocks are statements again and `invalid` is cleared (`file_blocks` in `bufferModel.lua`).

**Every block is the file's own lines.** The chunker (`source_blocks` in `src/model/lang/lua/parser.lua`) takes the source lines each statement and each comment spans; spans that share a line are one block, a blank line is an `Empty` (one of spaces keeps them, as `Empty.text`), and a line nothing claims, such as a `#!` line, is a block of its own. A block's text is never re-rendered or wrapped: the view wraps long lines on screen only. `file_blocks` then checks that the blocks hold lines 1 to n, each once, in order and as read; when they do not, the file comes a line per block, as text that does not parse does, so that no line is lost on the next save.

**Line endings.** The buffer holds lines without them, and each line's own ending beside them, in `BufferModel.ends`. Every change goes through `_splice`, which keeps the two in step: a cut, a move, and an undo or redo (a step holds the endings of the lines it removed and inserted) keep each line's ending. Lines that come from the field, or that Ctrl+Shift+F rewrites, have none of their own, except those the same as the line they replace at either edge of the change; `save` writes a line with none with the file's main ending, the one most of its lines have, the first in the file on a tie. A last line without an ending gets that one (IS1.2).

**A file is written only over what the editor last read or wrote there.** The buffer's `disk_seen` holds that text, or `false` for a file missing when it was opened (`_note_read` and `_note_saved` in `src/controller/editorReuse.lua`). Before every write, and before every undo and redo, `_baseline` reads the file again and gives one of three answers. `same`: the action goes on. `changed` (other text, a file removed from its project folder, or one created since): writes are refused with a notice (`_refuse_stale`), and Ctrl+Z or Ctrl+Y ends the timeline's actions, which no longer match the file (IS6.6; `_timeline_ready`, and `outdated` until the next write). `unknown`, when the file is there and gives no text or the project folder itself is gone (the SD card out): nothing is written and nothing forgotten, and the action is refused with a notice that the file could not be read (`_refuse_unread`), so the same key works once it can. A file that is there and gives no text is not opened at all (`ConsoleController:edit`; `Project:readfile` fails for it), nor is one missing from a project folder that is itself gone, the `unknown` answer at opening, nor one the editor could not save, such as a file in a folder of the project. A file missing from a folder that is there opens as a new one.

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

A refused action never asks a question: `EditorController:refuse(msg)` knocks and shows a notice, wrapped between words, in a band directly above the status line (`EditorView:draw_message`). The band covers the document view's last rows; the status line, the input and the view stay where they are. A syntax failure's message shows the same way, as kind `'error'` (`refuse(msg, 'error')`): the band, which has no frame, writes an error in the input's error colour and a notice in the status line theme's `warning` colour, the one the console's status line uses for `[no sd card]`; `EditorController:message_kind()` tells the view which it is. The next key press dismisses the message and does its ordinary work, `Esc` included; a modifier or a lock key alone leaves it showing. `F1`, while held, shows the keys the current state admits (`src/model/editor/keyCard.lua`).

The `LuaEditorEval` evaluator (`src/model/interpreter/eval/evaluator.lua:168`) is set on the editor input for Lua files. It adds a 64-character line length validator — the same limit as the code conventions — enforced live as you type.

**`input_max` vs `LINES`** — two separate height limits. `input_max = 14` is the input strip height, used as the `VisibleContent` `size_max` in `UserInputModel` and to calculate the physical pixel height of the input widget. `LINES = 16` is the buffer viewport height. `input_max = 14` was deliberately chosen to match the code convention (the whole block, `function` and `end` included, ≤ 14 lines): a conforming block fills the input view exactly, with no scrolling needed.

The block size limit is `input_max`: `bufv:get_max_size()` returns it, and the editor passes it to the gate. A Compy's values for both limits, the 64-column line and the 14-line block, live in `src/conf/display.lua`, where tools that format away from a Compy read them.

---

## The `loaded` Tracker — Why It Exists

`BufferModel.loaded` records which block index was most recently loaded into the input. This prevents a specific foot-gun: if you load block 3, then navigate the selection to block 7 (the highlight moves), then press Enter, you don't want to overwrite block 7 with what you loaded from block 3.

A submission with a replacement target replaces that block, wherever the browsing position stands by then (`EditorController:_land`). Browsing during a replacement moves the highlight only; the target keeps its own mark, and `Esc` drops it. The document view draws the browsed block white and the target yellow, each the screen's whole width; a block that is both is yellow with a strip of white one character cell wide at each side (`BufferView:draw`).

---

## The Submit Pipeline (Lua Mode)

Pressing `Enter` on non-empty input goes through `_handle_submit`, which asks the gate in `src/model/lang/lua/check.lua` for its verdict. `check.gate(lines, width, max_block)` is the editor's whole verdict on accepting a block, and every other tool that wants that verdict calls the same function:

1. **Format** — `format.format(lines, width)` (`src/model/lang/lua/format.lua`) rewrites the text through metalua's printer (`ast_to_src`). The result may differ from what was typed (spacing, indentation, end-placement). Where the source has one or more blank lines before a statement or an own-line comment, at any nesting depth, the printer emits exactly one empty line. The start of an indented body keeps none, so the indented placeholder line of an empty function body is regenerated and never read as a typed blank line. Blank lines ending the text follow no token the printer measures from; `format` keeps one there. The formatted text must parse to the same program, with the same comment text, and must come out unchanged when formatted again; otherwise, and when the text does not parse, `format` returns it as it was. The printer's own behaviour is covered by `tests/interpreter/ast_spec.lua`, `format`'s by `tests/interpreter/format_spec.lua`.
2. **Line and parse rules** — `check.check` runs on the formatted text: line length (the Compy's 64 columns), then a parse. The input shows the formatted text, and a refusal moves the cursor to the error. A long line the formatter wraps is no refusal.
3. **Chunk and measure** — the formatted text is chunked into the blocks that will be stored, and a block longer than `max_block` (the input's height, `input_max` = 14) makes the verdict name that block and how many lines it has too many. The editor refuses it with a message after its own visibility checks, and moves the cursor to the block's first line.
4. **No blank line of the editor's own** — nothing adds an `Empty` beyond what step 1 keeps. Blank lines outside the accepted block stay as they are: the chunker makes one `Empty` per blank line, so re-chunking the whole file after the write keeps every run.
5. **Replace or Insert** — `_land` puts the formatted lines in the target's place (`replace_lines`) or before the browsing position (`insert_lines`): a splice of the file's lines, after which the whole file is chunked again (see Block Position Tracking).
6. **Auto-save** — `buf:save()` is called immediately. Every accepted submit writes to disk, each line with its ending (see Line endings above), the last one included.

Without a replacement target the new block(s) are inserted before the browsing position, or appended at the end position, and the position ends on the block after them, so typing goes on below. An empty draft inserts one empty line. `Shift+Insert` submits the same way and keeps the draft in the input.

`Ctrl+Shift+F` in the browsing state (`format_file`) formats the whole file with the same `format` function at the window's width. Every run of blank lines in the file becomes one: the one place the editor changes blank lines outside a block, because the user asked. When `format` hands the text back as it was, the editor refuses with a message and the file stays. The selection stays on the statement the active line was on; from a blank line or a comment it moves to the statement below. The REPL's `tidy(name)` formats a file through the same `check.tidied` at a Compy's width (`src/conf/display.lua`) and writes it through a `BufferModel`, so it keeps a `#!` first line and each line's ending where the line stays, as Ctrl+Shift+F does. `util/compyfmt.lua --fix` formats at the same width and writes every line with a newline. compyfmt reports the gates and the lints (`src/model/lang/lua/lint.lua`); without `--fix` it changes nothing and also names each file formatting would change.

---

## Monster Blocks

A block with more source lines than the editor's size limit is a **monster block**. These can exist in files written outside the editor or imported. The editor handles them without data loss:

- **Viewing** — monster blocks are displayed in the buffer normally; content beyond the visible window is scrolled.
- **Loading** — `F2` on a monster block is refused with a notice that names the limit. `Ctrl+Delete` cuts the block out of the file into the input model for repair, even though only `input_max` (14) lines are visible in the input strip at once. The rest is reachable by scrolling the input.
- **Visibility tolerance** — the submit handler uses `bufv:is_selection_visible(true)` (the oversize-tolerant variant) when checking whether to proceed. A monster block whose start line is at the top of the visible range is considered "visible enough" to edit, even though it extends beyond the bottom.
- **Submitting** — the submitted content is chunked. If all resulting chunks are within the size limit, they replace the monster block (effectively splitting it). If any chunk is still oversized, that chunk is rejected and the cursor moves to its first line (`reject_oversized`).

The practical editing pattern: cut the monster block, edit it into valid code that chunks into conforming-size pieces, submit. Multiple resulting chunks each become their own block in the buffer, separated by the blank lines typed between them and no others (step 1 of the submit pipeline).

Source: commit `2ff95f03b8f8` ("Split monster block"); logic in `editorController.lua:_handle_submit` and `bufferView.lua:is_selection_visible`.

---

## Block Position Tracking

Each `Chunk` carries a `pos: Range` recording which source lines it occupies (e.g. `{3-7}` means lines 3 through 7). Since a block's lines are its source lines, `pos` and the rendered text agree, and an insertion or a replacement splices lines at `pos` (`_splice`) and re-chunks the whole file. The re-chunk may split the file anew, from lines into statements when a file that did not parse parses again, or back: so `_splice` keeps the browsing position as a source line, and leaves it on the block that now holds the line it stood on, or, that line gone, the line after the new ones. A caller that knows better sets it after: `_land` on the block after the landed lines, `move` on the moved block, an undo or a redo on the positions its step took in the text it puts back. The older `replace_content` and `insert_content` adjust `pos` by arithmetic instead; no editor path calls them.

This matters because the revmap (source line → block index), used for semantic info, is rebuilt only on `analyze()`, which runs on `buf:save()`. Between saves, the revmap may be stale. In practice this is fine because semantic info is only used at search time, which always follows a save in the normal workflow.

---

## The Two Visible Content Types

The view layer has two parallel implementations for the visible slice of a buffer:

**`VisibleContent`** (`src/view/editor/visibleContent.lua`) — used for plain/md files. Wraps the raw line array at the configured character width, manages a scroll offset/range over the resulting wrapped lines. Straightforward.

**`VisibleStructuredContent`** (`src/view/editor/visibleStructuredContent.lua`) — used for Lua. Must handle blocks, where each block wraps independently. Each block becomes a `VisibleBlock` (`src/view/editor/visibleBlock.lua`) that holds its own `WrappedText` and pre-maps syntax highlighting through wrap breaks.

Text in the editor passes through three coordinate spaces (documented with a worked example in `doc/development/editor/visible.md`):

1. **Normal coords** — original source line numbers, as stored in the file
2. **Wrapped coords** — apparent lines after word-wrapping at screen width; a single long source line may produce multiple wrapped lines
3. **Visible coords** — the subset of wrapped lines currently in the scroll window

For Lua buffers, each block has **two position fields** tracking the first two spaces:
- `pos` — the block's position in source lines (normal coords)
- `app_pos` — the block's position in wrapped/apparent lines (what the view uses for rendering and scroll)

These diverge whenever any block has lines longer than the screen width. Scrolling, selection visibility, and line number display all operate in apparent-line space; source queries (semantic info, revmap) operate in source-line space. The mapping between them is maintained in `VisibleStructuredContent.reverse_map` and recalculated in `recalc_range()`.

The `WrappedText` base class (`src/util/wrapped_text.lua`) provides the three-table mapping structure: `wrap_forward` (source line → list of display lines), `wrap_reverse` (display line → source line), `wrap_rank` (display line → its offset within the wrap break sequence). These are used for cursor coordinate translation in the input and for highlight remapping in `VisibleBlock`.

---

## Editor Modes

`EditorController.mode` holds two modes:

**`nav`** (default) — the browsing, inserting and replacing states described above; `_normal_mode_keys` dispatches their keys.

**`search`** (Ctrl+F) — definition search. The buffer's `semantic.definitions` (all assignments found by the analyzer) are loaded into `Search`. As you type, `Search:narrow()` filters the list with a case-insensitive substring match (lowercase input = case-insensitive, mixed = case-sensitive). Enter jumps to the selected definition's block and scrolls to its first line.

The only transitions are `nav` to `search` and back. This is enforced in `set_mode`.

The whole-editor exits (`Ctrl+T`, `Ctrl+Q`, `Ctrl+Alt+R`, and the deprecated `Ctrl+Shift+S`) leave from the browsing state. `Ctrl+Q` returns to the console with every buffer closed and the project still open (`reserved_stop` in `controller.lua`, which calls `ConsoleController:finish_edit`). A run (`Ctrl+T`, `Ctrl+Alt+R`) only hides the editor (`ConsoleController:hide_editor`): every buffer stays as it is, and `Ctrl+T` shows them again (`show_editor`). Hiding dismisses the message, as the key that hides acts (`EditorController:hide`), so no message waits in a hidden file for the editor's return. No program runs or idles behind a shown editor: every way it comes to the screen (`Ctrl+T`, `edit()` from the console or from an idle program's handler) passes `ConsoleController:_enter_editor`, which stops a live program first (`_program_live`: running, paused, or idle with `run_live`), so that none of its hooks or handlers takes the editor's keys or stops, runs or closes the project during an edit. When it had to stop one it shows nothing and its caller asks again, since the program's exit hook may have changed the project. During an edit `EditorController:refuse_to_leave` refuses them with a notice, because the input may hold the only copy of a cut block.

---

## Semantic Analysis

`BufferModel:analyze()` runs on every `save()`. It:
1. Rechunks the current text (to get a fresh AST)
2. Runs `analyzer.analyze(ast)` which walks the AST and collects assignments (global/local/function/method/field) and `require()` and `dofile()` calls with their line numbers (`src/model/lang/lua/analyze.lua`)
3. Builds `revmap` (source line → block index) from block positions
4. Converts the flat `SemanticInfo` into `BufferSemanticInfo` which replaces line numbers with block indices

This gives the editor two capabilities:
- **Search** (Ctrl+F): filter and jump to definitions by name
- **Follow require** (Ctrl+J): if the selected block contains a `require('foo')` call, open `foo.lua` as a new buffer on top of the stack

`analyze()` is wrapped in `pcall` — analysis failure is silent and leaves `self.semantic = nil`, disabling search and follow-require for that buffer.

---

## Buffer Stack and File Navigation

`EditorModel.buffers` is a `Dequeue<BufferModel>` used as a stack (front = active). `EditorView.buffers` is a parallel table keyed by buffer ID (the Lua table address as a string — not the filename). The two stay in sync manually.

Opening a file (`EditorController:open`) pushes a new buffer to the front and tells the view to create a new `BufferView` for it. Escape in the browsing state (`close_buffer`) pops the front buffer and activates the next one. If only one buffer remains, it closes the editor entirely and returns to the console.

Ctrl+J (`follow_require`) calls `self.console:edit(name, true)`, which opens the file only when the project holds it, through a full new `open` call that pushes another buffer. This creates a chain: file A → file B → file C, navigable back with Escape, one file at a time; Ctrl+Q leaves the whole chain for the console. A run of the project from the editor (Ctrl+T, or Ctrl+Alt+R, whose way back is Ctrl+T) keeps the chain in memory, untouched. A buffer that comes to the front in the browsing state, the front one when Ctrl+T shows the editor again (`EditorController:show`) and a caller that Escape steps back to (`pop_buffer`), shows what storage holds (`_take_outside_change`): `_baseline` answers, and on `changed` the buffer reads the file anew (`BufferModel:reload`) and its timeline goes (IS6.6), the browsing position keeping its block number while the file has that block and going to the end position otherwise (the end position stays the end). On `unknown` nothing is replaced or dropped, and the next key that needs storage refuses with the could-not-read notice. A buffer with a draft or a replacement target is never read over: it keeps its text and the outside-change notice shows (no key reaches that, since only the browsing state leaves a file). A change made while the editor shows the file is checked at the next key that needs storage, which refuses the write ("Reopen it to go on"). `edit()` in the console starts a new editor session (IS1.1): the hidden chain closes as leaving closes it, and the file opens alone at its end position; only Ctrl+T goes back into a hidden chain (IS1.4). Each buffer owns its field (`BufferModel.input`, a `UserInputModel`): its draft, cursor and the draft's undo steps; the editor's field shows the front buffer's (`EditorController:_front`), so a file that goes from the front keeps them with nothing copied. Neither following a file nor a run is leaving it (IS6.6, which names Escape, IS1.6). Leaving is Escape on the file, Ctrl+Q and Ctrl+Shift+S, and a project closed or switched (`_close_project`): the buffers go, and their timelines.

The buffer ID ensures the view can retrieve the right `BufferView` even after the model stack changes order. A buffer popped from the stack takes its view with it (`EditorController:_let_go`), and leaving the editor (`EditorController:close`) empties both tables; while the editor is hidden for a run, both stay.

Only the front buffer can be in an edit: a buffer goes below another one only by Ctrl+J, which is refused during an edit, as is every key that hides or leaves the editor (`refuse_to_leave`); a hidden editor is one left from the browsing state. The guards that refuse leaving therefore ask the front buffer alone.

---

## Key Files

| File | Role |
|---|---|
| `src/controller/editorController.lua` | All input handling, mode transitions, submit pipeline |
| `src/model/editor/bufferModel.lua` | Buffer state, block operations, loaded tracker, save, analyze |
| `src/model/editor/content.lua` | `Chunk` and `Empty` block types |
| `src/model/editor/editorModel.lua` | Model aggregate (input, buffers, search) |
| `src/model/editor/bufferSemanticInfo.lua` | Converts SemanticInfo line numbers to block indices |
| `src/model/editor/searchModel.lua` | Search state, narrowing, scroll |
| `src/controller/searchController.lua` | Search keyboard handling |
| `src/view/editor/bufferView.lua` | Scroll, selection visibility, draw orchestration |
| `src/view/editor/visibleContent.lua` | Scroll/wrap for plain/md |
| `src/view/editor/visibleStructuredContent.lua` | Scroll/wrap for Lua blocks |
| `src/view/editor/visibleBlock.lua` | Per-block wrap + highlight remapping |
| `src/util/wrapped_text.lua` | Core wrap tables (forward/reverse/rank) |
| `src/model/lang/lua/analyze.lua` | AST walker producing SemanticInfo |
| `src/model/lang/lua/format.lua` | Formatting: the text as the editor writes it |
| `src/model/lang/lua/check.lua` | Gates: line, parse and block-size rules, and `gate`, the editor's verdict |
| `src/model/lang/lua/lint.lua` | Lints: conventions reported, never refused |
| `src/model/interpreter/eval/evaluator.lua` | Evaluator types including LuaEditorEval |
