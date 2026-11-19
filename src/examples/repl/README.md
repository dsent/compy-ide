### REPL

This example shows the smallest program that reads text from the user with
`compy.input`. It echoes every submitted line back to the console.

#### Reading user input

Text entry is event-driven: show the input widget with `compy.input.show` and
provide an `on_text_entered` callback that receives each submitted line as a
string.

```lua
compy.input.show({
  on_text_entered = function(text)
    print(text)
  end
})
```

By default, the widget stays shown after each submission and clears its text
for the next line (`clear_on_submit = true`, `hide_on_submit = false`), so a
continuous prompt needs no `love.update` loop and no extra lifecycle flags.

For Lua code entry instead of plain text, pass the built-in helpers:

```lua
compy.input.show({
  highlighter = LuaHighlighter,
  validator = LuaSyntaxValidator,
  on_text_entered = function(text)
    print(text)
  end
})
```

For custom validation filters, see the `valid` example. For a one-off question,
use `compy.ask` and `compy.on_answer`. See `doc/input_api.md` for the full API.
