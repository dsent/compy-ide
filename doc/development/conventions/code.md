# Code Conventions

<!-- authored By LLM; human-approved NOT YET -->

> These conventions are not fully fixed — they evolve with experience. Some are unique to this project by design.
> Further discussion: https://github.com/compy-toys/compy/issues/54

---

## Formatting

Formatting is handled automatically by the metalua pretty-printer. No manual formatting rules are enforced — the built-in Compy editor auto-reformats on save. **Published examples must be idempotent under the editor** (run the editor over the code before publishing; it should produce no changes).

### Style examples

```lua
-- if/for/function: `end` on the same line as the last statement in the block
if condition then
  ...end

for iteration do
  ...end

function outer(args)
  local inner = function(args)
    ...  end
end

-- empty table: spaces inside braces
empty = { }

-- array/table: each element on its own line
array = {
  1,
  2,
  3
}

-- all comments on their own line (not inline)

-- at most one blank line between non-blank lines
```

---

## Structural Limits

| Rule | Limit | Checked by |
|---|---|---|
| Line length | 64 characters (fits the Compy screen) | the editor refuses a longer line |
| Function length | 14 lines | compyfmt reports it |
| Parameters per function | 4 (`self` aside) | compyfmt reports it |
| Nesting depth | 4 levels, counted in each function | compyfmt reports it |

The editor also refuses a block of more than 14 lines. `util/compyfmt.lua` reports what the editor would change or refuse in a file and what these limits flag; `--fix` formats the file first.

---

## Code Style

**Extract compound conditions to named locals:**
```lua
-- avoid
if a and b or c then end

-- prefer
local cond = a and b or c
if cond then end
```

**Do not use local variables outside their block.** A local should be scoped as tightly as possible.

**File = console equivalence.** Code in a `.lua` file and the same code typed into the Compy console must have identical effect. This guides how modules and scripts are structured.

---

## Standard Abbreviations

```lua
local gfx = love.graphics
local sfx = compy.audio
```
