## colors

Prints every color Compy can draw, then paints a picture using only
colors you can call by name.

Press `Space` to swap between the two screens.

### The palette

Compy knows 64 colors, numbered `0` to `63`. You can always ask for one
by number:

```lua
gfx.setColor(Color[2])
```

...but numbers are hard to read, so every color also has a name. The
name *is* the number — `Color.red` is just another way of writing `2`:

```lua
gfx.setColor(Color[Color.red])
```

Both lines draw exactly the same red. Use the name; a reader of your
program should not have to remember what `2` looks like.

### Plain and bright

Every color comes in two strengths. The plain one is what you get from
the name on its own. Add `Color.bright` for the strong one:

```lua
gfx.setColor(Color[Color.red])                 -- a deep red
gfx.setColor(Color[Color.red + Color.bright])  -- a vivid red
```

This works because a name is a number, so you really are doing
arithmetic: `Color.bright` is `8`, and `Color.red` is `2`, so
`Color.red + Color.bright` is `10`. That is why every entry on the
list screen carries a small square to its right: the wide block is
`2 red`, and the square beside it is `10`, the same red gone bright.

The plain version is the bright one at three quarters strength. Three
quarters of black is still black, so `8` is a dark grey picked by
hand, and adding `Color.bright` always takes you somewhere new.

### Groups of sixteen

The 64 colors come in four groups of sixteen. Within any group, the
first eight are the plain colors and the next eight are the same eight
gone bright, which is why adding `8` always moves you from one to the
other.

| Numbers | What lives there |
| --- | --- |
| `0`-`15` | the classic eight: black, blue, red, magenta, green, cyan, yellow, white |
| `16`-`31` | the everyday extras: orange, brown, tan, pink, purple, grey and friends |
| `32`-`47` | colors that fill in the color wheel: coral, gold, turquoise, azure |
| `48`-`63` | soft, pale colors: khaki, mint, lavender, powderblue |

### Reading the picture

The second screen is drawn with nothing but named colors — no raw
numbers anywhere. Look at `drawTree` for the shortest example:

```lua
function drawTree(x, y)
  gfx.setColor(Color[Color.brown])
  gfx.rectangle("fill", x - 12, y - 78, 24, 84)
  gfx.setColor(Color[Color.springgreen])
  gfx.circle("fill", x, y - 116, 52)
  ...
end
```

A trunk in plain `brown`, then leaves in `springgreen` with brighter
greens layered on top. Nowhere does the code say `#964B00`; it says
`brown`, and the reader can picture it.

### Try it

* Change a color name in `drawHouse` and run it again.
* Take `Color.bright` off the sun and watch it dull.
* Add a flower to the `FLOWERS` list. Each entry is `{ x, y, color }`.
