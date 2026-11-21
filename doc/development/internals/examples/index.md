# Examples — Index

<!-- authored By LLM; human-approved NOT YET -->

The examples live under `src/examples/`, apart from balloons and keyboard, which
have repositories of their own. Each is a self-contained project with a
`main.lua`. They demonstrate different combinations of framework capabilities.

Detailed docs for each are in this directory. For the project-author usage guide to the input API used throughout this table, see [Compy Input API](../../../input_api.md).

Input mode column uses `compy.input.*` **(supported since 1.0.0-rc20260712)** throughout; the legacy `user_input()`/`input_text()`/`input_code()`/`validated_input()`/`write_to_input()` poll-a-reftable API is **(deprecated, removed in 1.0.0-rc20260712)**.

**Draw mode** distinguishes three shapes. *Real-time* redraws every tick from `love.draw`/`love.update`.
*Pen-and-paper* draws too, but on demand — to a canvas that persists between events rather than being
repainted each frame. *Terminal only* draws nothing at all: no `love.draw`, no canvas, output goes to
the terminal via `print`.

| Example | One-line description | Draw mode | Input mode |
|---|---|---|---|
| [balloons](balloons.md) | Real-time typing game — pop balloons before they fill the screen | real-time `love.draw` | `compy.input.show{}` continuous session |
| [clock](clock.md) | Animated digital clock with randomised color cycling | real-time `love.draw` + `love.update` | keyboard (`love.keyreleased`) |
| [guess](guess.md) | Number guessing game with per-character validation | terminal only (no drawing) | `compy.input.show{ validator = LineValidators(...) }` continuous session |
| [keyboard](keyboard.md) | Typing tutor — separate repo; doc covers its input judgement only | real-time `love.draw` | `compy.input.hooks.{keypressed,keyreleased,textinput}` + shortcut combos |
| [life](life.md) | Conway's Game of Life with mouse and keyboard controls | real-time `love.draw` + `love.update` | `love.keypressed`, `love.mousepressed` |
| [pong](pong.md) | Full Pong game with AI opponent and fixed-timestep physics | real-time `love.draw` + `love.update` | keyboard + mouse; selectable AI strategy |
| [repl](repl.md) | Minimal input loop — prints each submitted line back; does not evaluate it | terminal only (no drawing) | `compy.input.show{}` continuous session |
| [sine](sine.md) | One-shot sine wave plot drawn at init, no update loop | pen-and-paper (init only) | none |
| [tixy](tixy.md) | Live-coded pixel grid — edit the tixy formula in-app | real-time `love.draw` + `love.update` | `compy.input.show{ highlighter = LuaHighlighter, validator = LuaSyntaxValidator }` |
| [turtle](turtle.md) | Turtle-graphics interpreter driven by typed commands | real-time `love.draw`, draws trails | `compy.input.show{}` one-shot (on `i`) + `love.keypressed` |
| [valid](valid.md) | Validator showcase — collects user input with custom rules | terminal only (no drawing) | `compy.input.show{ validator = LineValidators(...) }` continuous session |
