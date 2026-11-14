# Implementation Overview

<!-- authored By LLM; human-approved NOT YET -->

High-level implementation details for Compy. Load this when you need architecture context beyond what CLAUDE.md provides.

## Hardware and Platform Context

Compy is a physical 7" portable educational computer running Android, designed as a modern take on the ZX Spectrum-era home computer experience for children. The primary storage is an SD card mounted at `/storage/<uuid>/Documents/compy/` — projects live under `projects/` within that path. On desktop Linux the equivalent path is `~/Documents/compy/`. `src/main.lua:android_storage_find()` handles SD card detection. The intro document `doc/intro.md` describes the intended runtime environment.

---

## Entry Points

- `src/conf.lua` — `love.conf()`, parses CLI args into `love.start` (`{mode, path?, testflags?}`)
- `src/main.lua` — `love.load()`, sets up storage, instantiates MVC, handles startup modes

## Application Modes

| Mode | Invocation | Description |
|---|---|---|
| `ide` | `love src` | Full IDE: console REPL + editor |
| `play` | `love src play <path>` | Runs a single project; no editor UI |
| `test` | `love src test [flags]` | IDE with optional autotest and draw-test overlays |
| `harmony` | `love src harmony` | Scenario-driven screenshot testing |

Test flags: `--auto` (run `tests/autotest.lua` on startup), `--size` (smaller terminal), `--draw` (blend-mode grid, implies `--size`).

---

## MVC Structure

Top-level wiring in `love.load` (`src/main.lua`):
```
ConsoleModel → ConsoleController → ConsoleView
```

### Model (`src/model/`)

| Path | Purpose |
|---|---|
| `consoleModel.lua` | Top-level aggregate: input, editor, output (canvas), projects |
| `input/` | `UserInputModel`, `InputText`, `Cursor`, `History`, `InputSelection` |
| `editor/` | `EditorModel`, `BufferModel`, `VisibleContent`, `BufferSemanticInfo`, `luaLayer` |
| `interpreter/eval/` | `Evaluator` — validate → parse → transform pipeline for user input |
| `lang/lua/` | Lua parser (via metalua), semantic analyzer, highlighter, error types |
| `lang/md/` | Markdown parser |
| `project/` | `ProjectService` — list/open/run/close projects, file I/O |
| `canvasModel.lua` | Virtual drawing canvas + VT-100 terminal |

### Controller (`src/controller/`)

| File | Purpose |
|---|---|
| `controller.lua` | LÖVE2D handler setup; draw/update loop; user handler detection |
| `consoleController.lua` | Main controller; project lifecycle; canvas routing |
| `editorController.lua` | Editor state machine |
| `userInputController.lua` | Input widget logic |

### View (`src/view/`)

| Path | Purpose |
|---|---|
| `consoleView.lua` | Top-level view compositor |
| `canvas/` | `CanvasView` (composites background + terminal + user canvas), `TerminalView` |
| `editor/` | `EditorView`, `BufferView`, `VisibleBlock`, the key card |
| `input/` | `UserInputView`, statusline, custom status |

---

## OOP Pattern (`src/util/class.lua`)

Two patterns in use:

**Constructor pattern** — most common:
```lua
Foo = class.create(function(x) return { x = x } end)
-- with lateinit (called after constructor, for derived state):
Bar = class.create(new_fn, lateinit_fn)
```

**`new` method pattern** — when metatable setup must be manual:
```lua
Baz = class.create()
function Baz.new(cfg)
  return setmetatable({ ... }, Baz)
end
```

Classes are typically globals (e.g. `ConsoleModel`, `UserInputModel`). Instantiation uses call syntax: `Foo(args)`.

---

## Global Namespace

`src/util/lua.lua` injects helpers into `_G` on load: `prequire`, `codeload`, `noop`, `identity`, `parse_int`, `b2s`.

Many model/view/controller classes are also set as globals at module load time (not returned via `require`). This is intentional — it supports the file = console equivalence principle.

---

## Input Evaluation Pipeline

User input flows through `Evaluator` (`src/model/interpreter/eval/evaluator.lua`):

1. **Line validators** — reject syntactically bad input before it enters the model
2. **Parser** (`src/model/lang/lua/parser.lua` via metalua) — parse to AST
3. **AST validators** — semantic checks on the parsed tree
4. **Transformers** — mutate AST before execution

---

## Drawing System

See [`drawing_system.md`](drawing_system.md) for the full explanation of virtual canvas, pen-and-paper vs real-time draw modes, and the `love.draw` override detection mechanism.

---

## Key Libraries (`src/lib/`)

| Library | Role |
|---|---|
| `metalua/` | Lua 5.1 parser (git submodule); used for AST, syntax checking, highlighting |
| `djot/` | Djot markup parser |
| `hump/timer.lua` | Timer utility |
| `error_explorer.lua` | Interactive LÖVE2D error screen (by kira); on unhandled error shows stack, locals, and source. Documented in `doc/development/error_explorer.md`. |

`src/util/string/` is also a git submodule (string utilities).

### Dependency graph

A full module dependency graph (Mermaid flowchart) is maintained in `doc/development/lib_deps.md`, including a utility tier breakdown. Consult it when tracing load-order or dependency questions.
