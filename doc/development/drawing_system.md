# Drawing System

The console's text and a program's picture are two records kept apart:
the output (the terminal grid and its kept rows) and the program's
canvas. The screen shows them in one of three modes. This is the
proposal "The Program's Canvas and the Viewing Modes", built as if
accepted (the maintainer's ruling of November 17, 2026).

## Two Ways A Program Draws

**Once, or on events.** Code calls `gfx.*` at its top level, in a
handler, or in `love.update`. What it draws stays on the canvas, since
nothing clears the canvas between frames. Example: `src/examples/sine`
plots its curve once and defines no `love.draw`.

**Each frame.** The program defines `love.draw`. The IDE's own
`love.draw` calls it each frame onto the canvas, after clearing the
canvas to the program's background colour with the transform at its
origin, as `love.run` clears the screen before a LÖVE program's draw.
The canvas then holds the last frame drawn.

Either way, every line of program code and every typed line runs with
the canvas bound (`ConsoleController:use_canvas`): top-level code and
typed lines (`run_user_code`), every routed event (`with_canvas_and_errors`
in `controller.lua`), `love.update`, `love.draw` (`draw_program`),
`compy.before_exit` and the serial handlers (`SerialPort:update`). A
field's validator, highlighter and parser are the one exception: they
run while the IDE renders the field into its own canvas. What the code pushed and did not pop is popped when
it returns, raises or is ended, before the target goes back: a push
saves the state it is made in, the program's canvas bound, and one left
behind would bind it again wherever it is popped. A program's `love.graphics.setCanvas()` with no
target binds its canvas, as LÖVE's binds the screen, and its
`getCanvas()` answers `nil` there, and its `reset()` makes its canvas the
target again (`prepare_project_env`). So a program
that draws through a canvas of its own and goes "back to the screen"
lands on its picture.

## The Canvas Record

`CanvasModel.canvas` (`src/model/canvasModel.lua`) is the screen's size.

- A run's start (the run seam, Ctrl+R) clears it, so does `reset()`.
- A stop keeps it: `stop()`, Ctrl+Q, Ctrl+T, an error in top-level code,
  the program's own quit, a project's close. What `before_exit` draws
  stays too.
- A pause keeps it, and the paused frame is the last one drawn: the
  pause takes no screenshot.
- `CanvasModel:clear_canvas` clears the whole canvas whatever scissor or
  colour mask the program left, and puts the caller's state back.
- With the canvas the record keeps whether anything is drawn on it
  since it was cleared (`is_drawn`) and the background colour the
  program chose (`get_background`): the program's
  `love.graphics.setBackgroundColor` keeps each colour it sets there, and
  so do its `pop()` when it puts another back and its `reset()`, so
  neither the flush's reset nor the state a draw gives back after its
  frame changes it. A program's `love.draw` frame is cleared to it,
  premultiplied, as the canvas holds its colours.

## The Screen's Modes

`ScreenModel` (`src/model/screenModel.lua`) holds the mode; every change
of it is one call there.

| Mode | Draws (`CanvasView:draw`) | Status line and field |
| --- | --- | --- |
| `text` | The output on its ground, no picture | Shown |
| `combined` | The picture on its ground, then the output on a translucent ground, without cell backgrounds | Shown |
| `picture` | The picture on the program's background colour, on the whole screen | None |

In the combined mode the theme's `screen.combined.ground` is the opacity
of the output's ground over the picture, and `screen.combined.text` that
of its characters (`src/conf/colors.lua`), which the output's canvas
takes as it is drawn, its characters whole on it. The program's canvas
is drawn with premultiplied alpha, since what is drawn on a canvas
carries its alpha in its colour already.

What sets the mode:

| Event | Mode |
| --- | --- |
| A run starts | `text` |
| A running program's first drawing call of its run | `picture` |
| A typed line's drawing call, in `text` | `combined` |
| A pause | `text`, whatever the program draws while paused; `continue()` brings back the mode before it, or the picture when the program first drew while paused, whatever F12 showed meanwhile |
| A stop, an error in top-level code, `reset()` | `text` |
| `compy.screen.show(mode)`, from a program or a typed line | `mode`, which holds against the run's first drawing (`ScreenModel:choose`) |
| F12 in the console (`ScreenModel:step`) | the next of `text`, `combined`, `picture` |
| A key or a button on the full picture while no program can act (`ScreenModel:back`) | `text` |

A drawing call is one of the program's `love.graphics` drawing
functions (`arc`, `circle`, `draw`, `drawInstanced`, `drawLayer`,
`ellipse`, `line`, `points`, `polygon`, `print`, `printf`,
`rectangle`) or a fill or stroke of its `compy.graphics.shape2d`; each
calls `ConsoleController:drew`. `clear` erases and draws nothing. Lua's
`print` goes to the output alone.

## The IDE's Draw

`set_love_draw` (`controller.lua`) installs the IDE's `love.draw` for
good: the program's frame onto its canvas (`draw_program`), then
`View.draw`, which draws the screen by its mode in the IDE's own
graphics state (`src/view/ownState.lua`), then a running program's own
input field, over every mode, then the frame-rate overlay.
