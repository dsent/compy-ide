# tixy

<!-- authored By LLM; human-approved NOT YET -->

**Live-coded pixel grid** inspired by tixy.land. A 16×16 grid of circles whose radii and colors are driven by a user-editable formula `tixy(t, i, x, y)`.

## Architecture

Single-file (with `mathlib.lua` for extra math and `examples.lua` for preset formulas). Overrides `love.draw`, `love.update`, `love.mousepressed`.

## Live coding mechanism

The heart of the example:

```lua
function setupTixy()
  local code = "return function(t, i, x, y)\n" ..
      "  " .. body ..
      "  return r\n" ..
      "end"
  local f = loadstring(code)
  if f then
    setfenv(f, _G)
    tixy = f()
  end
end
```

`body` is a single line of Lua (e.g. `r = math.sin(t + x)`). `loadstring` compiles it wrapped in a function in the program's environment, `setfenv(f, _G)` keeps working redundantly on the same environment, and the returned closure becomes `tixy`. This is called whenever the user submits new code.

## Input pattern

Uses `compy.input.show{}` with `LuaHighlighter` and `LuaSyntaxValidator` **(supported since 1.0.0-rc20260712)** — the input widget has Lua syntax highlighting and validation. `love.update(dt)` now only advances `time`; there is no polling of an input handle. See [Compy Input API](../../../input_api.md) for the full usage guide.

*Clearing `legend` on submit is intentional: the caption describes the initial
prebuilt example, so a submitted custom formula retires it.*

```lua
local function submit_body(text)
  body = text
  setupTixy()
  legend = ""
end

compy.input.callbacks.after_cancel = function()
  compy.input.set_text(string.lines(body))
end

function love.update(dt)
  time = time + dt
end

compy.input.show{
  prompt = "function tixy(t, i, x, y)",
  text = string.lines(body),
  highlighter = LuaHighlighter,
  validator = LuaSyntaxValidator,
  on_text_entered = submit_body,
}
```

`submit_body` (wired as `on_text_entered`) consumes the submitted text as one string while the session is active. Cancel clears the field, so `after_cancel` is a direct callback assignment that restores the current body.

`compy.input.set_text(body)` in `load_example()` pre-fills the live input with the current formula when loading a preset — the user sees the formula they're about to run before submitting. This replaces the old `write_to_input(body)` call.

The old `r = user_input()` / `input_code(...)` polling pattern is **(deprecated, removed in 1.0.0-rc20260712)**.

## Example cycling

`examples.lua` is a table of `{code, legend}` pairs. Left click advances, right click randomizes. `advance()` and `retreat()` call `load_example()`, which calls `setupTixy()` and `set_text`.

## Points of attention

- `setfenv(f, _G)` gives the live code full access to the global environment. This is intentional (educational context, trusted user) but means any global can be clobbered by a formula.
- If `loadstring` fails (syntax error in `body`), `setupTixy` silently leaves the old `tixy` function in place.
- `tonumber(tixy(ts, index, x, y)) or -0.1` — graceful fallback if the formula returns nil or non-numeric.

## Files

`src/examples/tixy/` — main.lua, mathlib.lua, examples.lua
