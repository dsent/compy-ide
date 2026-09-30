# Drawing System

<!-- authored By LLM; human-approved NOT YET -->

## Two Modes

User projects can draw in one of two ways, selected by whether `love.draw` is overridden.

### Pen-and-paper mode (default)

Project code calls `gfx.*` primitives imperatively — in response to events (clicks, input) or at startup. There is no per-frame redraw loop. The framework composites everything on each frame regardless, but the virtual canvas only changes when the project explicitly draws to it, so unchanged content persists for free while the program runs. The canvas is cleared when the run stops (see [Canvas lifetime](#canvas-lifetime)).

**Example:** `src/examples/sine` — plots the curve once at startup and defines no `love.draw`; the plot stays on the canvas with nothing redrawing it.

### Real-time draw mode

Project sets `love.draw` directly. The framework detects this on the next `update()` tick, wraps the user draw in `gfx.push/pop` + error handling, and appends the input widget if it is shown. The framework console UI is bypassed.

**Example:** `src/examples/balloons` — sets `love.draw = hooks["draw"]` and `love.update = hook("update")` in `game_init()`.

---

## How It Works

### Virtual canvas

`CanvasModel` holds a `love.Canvas` (`model.output.canvas`) that serves as the drawing surface for all user project code. It is composited over the terminal by `CanvasView:draw()` during the framework's render pass (`src/view/canvas/canvasView.lua`).

### Canvas lifetime

The canvas belongs to the run that drew on it, and to the console between runs:

- A run starts on a blank canvas. A project that fails to load clears it too, so its error shows on a blank console.
- Every stop clears it: Ctrl+S, Ctrl+T, `stop()`, restart (Ctrl+Alt+R), Ctrl+Q, the program's own quit, and a top-level error. `_stop_project_run` clears it after the project's `before_exit` hook, so what the hook draws goes too.
- The clear covers the whole canvas whatever scissor or colour mask the program left; `CanvasModel:clear_canvas` puts the caller's graphics state back.
- A handler that calls `stop()` and goes on drawing is cleared again when its `use_canvas` call unwinds (`stop_count`, `run_live`). A run started during that call (restart) keeps its canvas.
- Drawing typed at the console shares the canvas: it lasts until the next stop, run or close, and a stop clears it too, with no program running.
- A paused run (Ctrl+Pause, an error in a handler) has not stopped: its canvas stays, and `continue()` draws on it again.
- A run that finishes its top-level code is in `ready`, not stopped, and keeps its picture until it stops or the project closes. That covers a run with nothing live (no handlers, no widget), as the sine example is, and a run with live handlers but no `update` or `draw`. Ctrl+S stops a `running` program only, so it leaves a `ready` one alone; `stop()`, Ctrl+T, restart and Ctrl+Q end it.

### `use_canvas(f)` — `ConsoleController:use_canvas` in `src/controller/consoleController.lua`

```lua
function ConsoleController:use_canvas(f)
  gfx.setCanvas({ canvas, stencil = true })
  local r = f()
  gfx.setCanvas()
  return r
end
```

Project input code is wrapped in `guarded` (`controller.lua`), which calls `use_canvas` internally. It wraps the point where a **route is entered** rather than each handler, so a whole dispatch walk — shortcuts, hooks and the input widget alike — runs with the canvas bound (`../decisions/input.md`, D-ONE-LIFETIME). User `love.update` is also run inside `use_canvas` (see `controller.lua`, `set_love_update`). This means any `gfx.*` calls in project input handlers or update automatically go to the virtual canvas, not the screen.

### User `love.draw` detection — `src/controller/controller.lua`, `set_love_update`

On each frame's `update()`, the framework compares `love.draw` against its last known value (`View.prev_draw`). If they differ, it replaces `love.draw` with a wrapper:

```lua
local draw = function()
  gfx.push('all')
  wrap(ldr, CC)        -- user draw, error-handled
  gfx.pop()
  -- append the input widget if it is active
  local ui = get_user_input()
  if ui then ui.V:draw() end
end
love.draw = draw
View.prev_draw = draw
```

The framework console UI is not drawn in this path; only the user draw and the optional input widget.

### Framework's default `love.draw` — `src/view/view.lua`, `src/controller/controller.lua:set_love_draw`

Calls `View.draw(CC, CV)` which renders: background → terminal → virtual canvas, in blend-mode layers. The virtual canvas is drawn with `gfx.draw(canvas)` as a single texture blit per frame.

---

## Summary

| | Pen-and-paper | Real-time |
|---|---|---|
| Draw trigger | Event / explicit call | Every frame (`love.draw`) |
| Draws to | Virtual canvas (via `use_canvas`) | Screen directly (framework wraps it) |
| Framework UI | Composited on top | Bypassed; input widget appended separately |
| GC / CPU cost | Low — canvas persists until the run stops | Per-frame cost, project's responsibility |
| Suitable for | Board games, static visuals | Animations, physics, continuous updates |
