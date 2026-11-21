# Project Documentation Review

<!-- authored By LLM; human-approved NOT YET -->

Assessment of `doc/` relative to the codebase and the knowledge base under `doc/development/`. Organised into: relevant (usable as-is), drift (needs attention), gaps.

---

## Relevant — Recommended for Active Use

**`doc/mermaid/fsm.md` + `fsm_f.md`** — App state machine. The clearest single-file reference for all `app_state` transitions, including editor↔running toggle and inspect↔editor paths. The KB (`console.md`) summarises the table; the Mermaid diagrams show the full graph. Consult when reasoning about state transitions.

**`doc/mermaid/eval.md`** — The "Planned refactor" section (upper half) accurately describes the current `Evaluator` + `Filters` architecture. Useful as a type-level reference for the evaluator pipeline.

**`doc/development/editor/visible.md`** — Three coordinate spaces (normal → wrapped → visible) with a worked ASCII example. More concrete than the description in `editor.md` and worth reading alongside it.

**`doc/development/lib_deps.md`** — Full module dependency graph and utility tier breakdown. `overview.md` references it; consult directly when tracing load-order or dependency questions.

**`doc/EDITOR.md`** — The editor's principles, its keys by state, and how a file
is browsed, inserted into and replaced in. Authoritative for what a user meets;
`internals/editor.md` has the mechanism, and `src/model/editor/editorKeys.lua`
is the key table both follow.

**`doc/AST.md`** — Metalua AST token reference table. Accurate. Useful when working on the parser, analyzer, or any code that walks the AST.

**`doc/development/error_explorer.md`** — Documents the `src/lib/error_explorer` third-party library. Referenced from `overview.md`.

**`doc/intro.md`** — Hardware/platform context (7" Android device, SD card storage layout). Referenced from `overview.md`.

---

## Drift — Worth Developer Attention

**`doc/mermaid/classes.md`** — References `InterpreterModel` and `InterpreterController`, which were refactored into `UserInputModel`/`UserInputController`. The class diagrams reflect a prior architecture and are misleading as current reference.

**`doc/mermaid/eval.md` — "Current" section** (lower half) — Describes an old `EvalBase` inheritance chain (`TextEval --|> EvalBase` etc.) that no longer exists. The "Planned refactor" section is what was implemented.

**`doc/mermaid/input.md`** — Same pattern as eval.md. The "Planned refactor" describes the current `UserInputModel` structure; the diagram is now the ground truth, but the framing as "planned" is confusing.

**`doc/interface/*.apng`** — The animations `README.md` and `doc/EDITOR.md` show
were recorded with an earlier editor and its status line, which names no state.
`open_edit.apng` types `edit('README')`, where the turtle project's file is
`README.md` now and `edit('README.md')` opens it. `hello.apng` (a line typed
and added with Enter) shows gestures that still hold, under that status line.
`hello_cap.apng` loads a block with Escape, where F2 loads it now;
`quit_editor.apng` leaves with Ctrl+Shift+Q, where Escape while browsing or
Ctrl+Q leaves now; `move_line.apng` and `move_block.apng` move a block with
Ctrl+M, arrow presses and Enter, where Alt+Up and Alt+Down move it now. No
script in this repository records them.

---

## Gaps — Areas Without Developer Documentation

- **Console mode** — no developer-facing doc in legacy `doc/`. Covered by `doc/development/internals/console.md`.
- **Drawing system** — pen-and-paper vs real-time draw modes. Covered by `doc/development/drawing_system.md`.
- **Project environments** — the three Lua environments (`main_env`, `base_env`, `project_env`). Covered by `internals/console.md`.
- **The retired `user_input` polling API** — `input_text()`, `validated_input()`, `user_input()`. **Removed in 1.0.0-rc20260712**, no shim; `internals/console.md` records what it was, and [`input_api.md`](../input_api.md) documents `compy.input`, which replaced it.
- **Harmony testing mode** — covered by `doc/development/tests.md`, "Harmony scenarios".
- **`doc/development/editor/buffer.md`** — file exists but is empty.
