---
description: What the test suite covers, the shared input fixtures, the tag vocabulary, and the named gaps
status: active
audience: developer
authored: llm
reviewed: none
---

# Test Suite Review

Assessment of `tests/` relative to the codebase and the knowledge base under `doc/development/`. Organised into: relevant infrastructure, coverage map, gaps.

---

## Test Infrastructure Worth Knowing

**`EditorSession`** (`tests/helpers/editor_session.lua`) — A keystroke-driven test harness for the editor. Drives `EditorController` via simulated key events. Key methods: `open(src, nb)` asserts block count on open; `select_block(n)` navigates to block n; `select_and_open_block(n)` selects and presses Escape (asserts `buffer.loaded == n`); `submit(newtext)` alters input and sends Return; `assert_cursor_at(line, col)` checks cursor position and visibility in the input's scroll range. The comment in `select_block` notes it works reliably only before the input multiline buffer is activated (before Escape is pressed) — a known limitation tracked in issue #117.

**`mock.lua`** — `mock_love(t)` injects a minimal `love` global. `mock.keystroke(keystr, press)` parses strings like `"C-return"`, `"S-escape"`, `"M-up"` (prefixes: `C`=Ctrl, `S`=Shift, `M`=Alt) into modifier state + key call. Primary driver for all editor and input tests.

**`testutil.lua`** — Shared constants: `wrap=64` (screen width, matching the code convention line limit), `LINES=16` (buffer display height), `SCROLL_BY=8`. `get_save_function(init)` returns a save callback paired with a `reftable` handle — the same callable-table-as-mutable-reference pattern used by `user_input()` handles in project code.

**`input_fixture.lua`** (`tests/helpers/input_fixture.lua`) — full input standup for the `#input` contract suite (Compy input API, 1.0.0-rc20260712). Stands up the REAL `love.handlers` gate over a REAL `ConsoleController` (gfx/font stubbed, never a real display), the persistent singleton input widget exactly as `main.lua` wires it, and the click/update path — module-level, once, shared across the whole spec file. Exposes `F`: `F.activate_project(natives)` drives the real project-activation path (`Controller.set_user_handlers`) and returns the project-facing `compy.input` surface; `F.compy_input()` resolves the same surface a project sees; `F.show_widget(opts)` / `F.show_selectable_widget(lines)` activate the singleton or a selection-enabled widget; `F.is_widget_visible()` answers "is a widget shown" the way the framework does — through `love.state.user_input`, the field the draw loop paints on and the console route forwards on, rather than the widget's own `is_shown()` self-report; `F.session` is the keypress-level driver (see below); `F.reset()` (called `before_each`) stops the real project route, then clears fixture state. Consumed, never copied — the ~175 lines of MVC/gfx/font boilerplate this replaces used to live inline in the spec file.

**`input_session.lua`** (`tests/helpers/input_session.lua`) — the keypress-level driver `input_fixture.lua` builds `F.session` from. One emitter per gateway entry (`press`, `repeat_press`, `release`, `type`, `mousepressed`, `mousereleased`, `touchpressed`), each firing a REAL event through `love.handlers.*` — never straight into a controller — so a contract test exercises the same path a keystroke takes from LÖVE. Distinct from `EditorSession`: that helper bypasses the `love` slots and drives `EditorController` directly, below the gate.

**`editor_keys.lua`** (`tests/helpers/editor_keys.lua`) — the editor driven the way a user drives it, built on `input_fixture`. `K.reset(contents)` opens a project held in memory (`contents` maps file names to text; writes land back in it, and Ctrl+T runs its `main.lua`) with a clipboard of the test's own; `K.open(name)` types `edit("name")` in the console and presses Enter. **Keystrokes have the device's shape:** `K.keys(...)` presses a chord and releases it in reverse, and a key that types a character (alone or with Shift) sends it between its press and its release, as LÖVE does; `K.type(text)` types each character with its key where it has one (letters, digits, Space), as text alone where it has none, and refuses a line break, which is a key (`K.type_lines` puts Shift+Enter between lines); `K.hold(k)` and `K.release(k)` are for what happens while a key is down. Shift with a key other than a letter types nothing through `K.keys` (its character depends on the layout): type it with `K.type`. `K.browse_to(b)` and `K.browse_to_end()` browse with the spec's keys as many presses as it takes, since a tall block may scroll first. `K.restart()` resets everything but the memory card's files, for a test that opens a second file from the console. **A frame passes after each keystroke** (`K.frame(dt)` for more), since the editor waits on frames (a Space that answers a question swallows its own character until the next one). `K.fail_writes(reason)` makes every write fail, as a full card would. `K.write_outside(name, text)` changes a file on the card not through the editor. Caps Lock is a device state its key toggles, answered through `love.keyboard.isModifierActive`. Everything else is a **read-only** accessor, in the spec's terms where the spec has one: `K.position()` (a block's number or `"end"`), `K.target()`, `K.state()` (`"browsing"`, `"inserting"`, `"replacing"`), `K.draft()`, `K.cursor()`, `K.blocks()`, `K.file_name()`, `K.file_type()`, `K.message()`; what the screen shows: `K.view_rows()`, `K.in_view(b)`, `K.rows_shown(b)`, `K.highlights()` (the blocks under the white and the yellow highlight, read from what the view's draw actually fills) and `K.highlight()`; `K.text_colours()`, the colours the view's draw prints its text in; `K.field_highlight()`, the token classes and the parse-error position the editor field's render colours the draft from (read from the field's model, since the field draws to a canvas the fixture does not render), `K.status_text()`, `K.console_text()`, `K.console_draft()`; and the clipboard, a file's text and the writes made. Tests read through the accessors and never drive the editor by calling a controller or a model, which is what sets it apart from `EditorSession`. `K.cleanup()` in `after_each` puts back the project, its loader, the filesystem and the clipboard. `K.block(n)` and `K.block_lines(n)` give a canonical Lua block of `n` lines for fixtures, so a test never depends on whether the editor formats a file when it opens it. Its own cases and a journey (type, submit, save) are in `tests/editor/editor_keys_spec.lua`.

**Run order is load-bearing.** The suite is green in declaration order and only in
declaration order — `busted tests --shuffle` fails a few dozen rows, at the PR base as well
as today. Do not read a shuffled failure as a regression, and do not add `--shuffle` to a
runner without reading `technical_debt/general.md`, "The test suite passes only in
declaration order".

---

## Coverage Map

### Well covered

| Area | Spec files |
|---|---|
| Utilities | `util/string_spec`, `table_spec`, `dequeue_spec`, `range_spec`, `tree_spec`, `class_spec`, `wrap_spec`, `termcolor_spec`, `debug_spec`, `fs_spec`, `mock_spec` |
| Interpreter pipeline | `parser_spec`, `chunker_spec`, `analyzer_spec` (incl. `ast_to_src`), `ast_spec`, `eval_spec`, `error_spec`, `markdown_spec` |
| Editor model + view | `buffer_spec`, `chunker_spec`, `editor_spec`, `visible_content_spec`, `visible_structured_content_spec` |
| Input widget | `input_text_spec`, `cursor_spec`, `history_spec`, `input_spec`, `user_input_model_spec`, `user_input_view_spec` |
| Input routing / dispatch contracts (Compy input API) | the `input_*_spec.lua` contract suite (`#input`; see Input Contract Suite below) |

`analyzer_spec.lua` tests `parser.ast_to_src` — the pretty-printer central to the editor submit pipeline. It is the primary executable specification for that function's formatting behaviour.

### Not covered

| Area | Notes |
|---|---|
| `ConsoleController` | Deeply coupled to LÖVE2D runtime state; exercised by harmony integration tests instead. The input contract suite now stands up a REAL instance (gfx/font stubbed) as its routing target, but only its input-routing role is exercised — its own save/restore/snapshot behaviour is not |
| `Controller.lua` | Draw override detection. Click detection timer + handler registration are now covered by `input_shortcuts_click_spec`'s "framework click detection" and the `input_events_spec` rows |
| `ProjectService` | File I/O, project open/create, filesystem mount |
| `SearchController` | Editor Search is characterized through Ctrl+F, typed text, Enter jump, and Escape in `editor_spec`; it is an editor contract, not project input API |
| `SearchModel` | Narrowing and selection scroll have no direct unit tests |
| Drawing system | Depends on LÖVE2D graphics context |
| Views (rendering) | Expected; view testing requires LÖVE2D |

---

## Input Contract Suite (Compy input API)

The `#input` contract suite is grouped by the API's **three surfaces** — the same three the guide names — as `input_*_spec.lua` files under `tests/input/`. **Inbound events** (what the framework does with an event that arrives): `input_routing_spec` (which route an event reaches), `input_events_spec` (the dispatch chain and consumption), `input_shortcuts_click_spec`, `input_route_lifecycle_spec` (connect, disconnect, teardown, `compy.before_exit`). **Widget control** (how a project drives the widget): `input_widget_control_spec` (show/hide/reset, `configure`, `clear`), `input_cursor_text_spec`. **Widget callbacks** (what the widget reports back): `input_widget_callbacks_spec` (submit, cancel, validators, boundary outputs, and the one-lifecycle claim — Enter and Escape mean the same thing on every route). `input_nfr_mechanism_spec` belongs to no surface: it guards cross-cutting non-functional requirements. Each carries the file-level `#input` tag and builds the shared `input_fixture` from a `setup()` hook (torn down in `teardown()`, reset per test in `before_each`) — so every file is runnable standalone. The suite enforces the input contract — every test tracing to a corpus clause cited in a comment (never in the test description). It drives the real production path throughout: the REAL `love.handlers` gate, a REAL `ConsoleController`, and the real project-activation call (`Controller.set_user_handlers`) via the `input_fixture`/`input_session` helpers described above — never a spy on an internal method except one deliberately-noted sink-signature row.

Nearly every row is a behaviour contract, asserted live. Two kinds of row are not, and `input_nfr_mechanism_spec.lua` collects both under headings that say so, precisely so nobody reads them as promises:

- **characterized behaviour** — factual today, with no stakeholder mandate to stay this way (e.g. compy declaring no `wheelmoved` gateway entry of its own). Asserted live, not pending, so an accidental change still fails the build while a deliberate one reads as expected.
- **mechanism / NFR guards** — identity and allocation checks that deliberately poke internals, which is what an NFR guard is for.

Tags beyond the file-level `#input`:

- `#legacy` (`input_shortcuts_click_spec`) — proves the retired poll-idiom globals (`user_input`, `input_code`, `input_text`, `write_to_input`, `validated_input`, and the debug-only `astv_input`) are gone as ordinary `nil` fields — no shim, no deprecation path. The replacement surface (`compy.input`) is exercised throughout the rest of the suite, so the "Not covered: `user_input` overlay API" row from an earlier version of this doc no longer applies.
- `#lifecycle` (`input_widget_callbacks_spec`, the `the same lifecycle on every route` group) — the one-lifecycle claim: Enter submits and Escape cancels identically in the console, the editor and a project widget.
- `#history` (`history_spec`) — history recall, including the console's Up-at-the-top recall through the real key path.
- `#disputable` (`input_shortcuts_click_spec`) — marks a contract whose *desirability* is contested even though the assertion is factually true. One group remains: global shortcuts fire without consuming the key. The second group — the console line receiving what a hidden widget declined — was retired on 2026-08-03 when the console route lost its widget step entirely (`../decisions/input.md`, D-ROUTE-OWNS); those rows moved to the project route in `input_widget_control_spec`, where a hidden widget is a real decision, and the tag went with the dispute.

**The pending tests are named gaps, not failures.** `busted tests` reports them as pending, with no failures and no errors; the success count moves with the suite and is deliberately not quoted here. Each pending row documents a cell in the mode × channel routing grid that is either out of the input API's scope or not black-box observable today:

| Location | Row | Why it's pending, not red |
|---|---|---|
| `input_routing_spec.lua:68` | `routes the key release to the console` | A key release carries no text, so console delivery has no observable mutation to assert on — only the project-route release is directly witnessed |
| `input_routing_spec.lua:144` | `routes the pointer to the editor` | The production editor widget disables selection, so pointer delivery has no observable outcome without extra scaffolding |
| `input_routing_spec.lua:214` | `touch reaches the active route` | Touch has no gateway entry yet; both the widget and route touch handlers are no-ops, so delivery isn't black-box observable. Greens when a touch consumer lands |

**A second kind of pending row, added deliberately: the reserved combos' own effects.** `input_global_shortcuts_spec.lua` asserts one property live — that a project cannot suppress a global shortcut by registering the same combo — and lists the remaining reserved combos (`ctrl+alt+r`, the profiler pair, `f10`, `ctrl+s`, `ctrl+shift+r`, and `ctrl+escape` on release) as pending. Those are not unobservable like the rows above; they are simply **someone else's contract**. What each one *does* is the framework's own behaviour, worth asserting eventually and out of scope for the input API's suite, so the gap is named where a reader will meet it rather than left to be rediscovered. `ctrl+pause` and `ctrl+q` are absent from that list because their effects are asserted live, and **`ctrl+t` left it on 2026-09-09** for the same reason, once both arms of `reserved_quickswitch` were covered — the running one in that file, the editor one in `input_editor_keys_spec.lua`. `ctrl+s` stays: only its run-stop arm is a gap, since the editor cases pin that nothing else claims it.

---

## Editor spec tests

The editor is checked against its spec, the editor principles (`docs/editor-principles.md` in compy-project), item by item. The tests live under `tests/editor/spec/` and drive the editor only through `editor_keys.lua`.

**A spec test's name opens with the item's id and name**, as the spec writes them, then the case: `IS5.7 Cancel an edit with Escape: the draft is dropped`. A journey's id has no second number: `CUJ3 Revise a Block: …`. The id is in the name, not in a comment, so a run's output says which item failed and a script can count the tests per item. Unlike the input contract suite, which cites its corpus in comments, this one is counted.

**Three marks** (`tests/helpers/spec_marks.lua`). Each refuses a name without an id, a missing body, and a second test of the same name in the file. A mark is called from the spec file itself, as a statement, since it finds busted's `it` there.

| Mark | When | What it does |
|---|---|---|
| `spec_it(name, fn)` | the editor complies | an ordinary test |
| `spec_gap(name, fn)` | the editor does not comply yet | `fn` receives `gap` and calls it **once**, with the spec's check: `spec_gap(name, function(gap) …steps…; gap(function() assert…(what the spec wants) end) end)`. The steps are ordinary: one that fails fails the test. The check must fail **by an assertion**; once it passes, the test fails (*"file:line: IS… now complies: remove the mark"*), so a fixed gap cannot go unseen, and any other error fails too, so a broken check cannot hide as a gap. Tagged `#spec_gap` |
| `spec_deviation(name, ruling, fn)` | the editor departs from the spec on purpose; `ruling` names where that was decided | an ordinary test of what is built, tagged `#spec_deviation` and counted apart from the gaps |

**Why a gap fails:** `SPEC_GAP_WHY=1 util/run-busted tests/editor/spec` prints each gap's failed check, to audit that it fails for its item's reason and not because a step missed (a key the editor lacks makes the check fail too, which is still the gap).

**The count:** `luajit util/spec_count.lua tests/editor/spec/*.lua` prints, per item, its marks (every test), how many of them are gaps, and how many deviations, then the totals. It reads the files and runs nothing, skipping comments: a mark's name must be a string literal opening with the id. A mark call it cannot read is reported as `file:line`, and the script exits 1.

**An item that keys cannot drive** gets a test of the source or of its structure instead, or, where only the device can show it, a line in the manual checks below.

---

## Manual smoke — what no suite here can reach

Nothing in CI can press a key, and the example projects carry no suite of their own — the detached
repositories (`src/examples/{keyboard,maze,balloons}`) have none at all, and the in-repo examples
are exercised by nobody but a human. Where an example's **input mechanism** changed, the gate is
therefore a person, and the checklists live in
**[`smoke_checklists.md`](smoke_checklists.md)** — written to be run top-to-bottom with the expected
result stated, and kept current with the code by whoever changes the mechanism. A checklist that
tests a mechanism the code no longer has is worse than none, because it passes.

**That document is the list of lists** — it says which examples owe one and why, and it covers
in-repo examples as well as detached ones. Do not re-enumerate them here; a second copy of the set
is how this paragraph went stale twice.

## Gaps — Areas Worth Filling

**SearchModel** narrowing (`Search:narrow` with case-insensitive substring match) and selection scroll could be unit-tested similarly to `history_spec`.

**Tag organisation** — `.busted` excludes `delay`-tagged tests by default. Tags in active use: `#parser`, `#chunk`, `#analyzer`, `#ast`, `#src`, `#editor`, `#input`, `#markdown`, `#visible`, plus `#legacy`, `#lifecycle`, `#history` and `#disputable` (across the `input_*_spec.lua` contract files; see the Input Contract Suite section above). No tests currently use the `delay` tag, so the exclude is defensive rather than active.
