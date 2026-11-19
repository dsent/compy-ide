### Input validation

To check what the user types before `on_text_entered` runs, pass a `validator`
to `compy.input.show`. The built-in `LineValidators` helper turns one or more
line-filter functions into a validator.

A filter takes one line string and returns `true`, or `false` and either a
message string or an `Error`. An `Error` holds a message (`msg`) and an
optional location with character and line fields (`c` and `l`, both defaulting
to `1`).

Example:

```lua
function non_empty(s)
  if string.ulen(s) == 0 then
    return false, Error('Input is empty!')
  end
  return true
end
```

A completely empty submission is not accepted and skips validation, so
`non_empty` above is only an illustration of a filter's shape.

`LineValidators` runs every filter on every submitted line. On multi-line
input, returning a plain error string (`return false, "too short!"`) tags the
error with the failing line automatically; returning an `Error(msg, c, l)` uses
the line number you supply (omitting `l` defaults to line `1`). To highlight
the text in red from the first offending character onward on a single-line
prompt, pass its character index to `Error`:

```lua
function min_length(n)
  return function(s)
    local l = string.ulen(s)
    if n < l then
      return true
    end
    return false, Error("too short!", l)
  end
end
```

To check a line character by character, use `string.forall()` with the `Char`
classifier functions. `string.forall()` runs a predicate on each character and
returns `true` if every character passes, or `false` and the index of the first
offending character:

```lua
function is_lower(s)
  local ok, err_c = string.forall(s, Char.is_lower)
  if ok then
    return true
  end
  return false, Error("should be lowercase", err_c)
end
```

Check `is_upper()` in `main.lua` for a manual loop over characters.

#### Invoking

Pass the list of filter functions to `LineValidators` in `compy.input.show`:

```lua
compy.input.show({
  validator = LineValidators({
    min_length(2),
    is_lower
  }),
  on_text_entered = function(text)
    print(text)
  end
})
```

Pass the filter functions by name (`is_lower`), or call a factory that returns
a filter function (`min_length(2)`).

#### Helper functions

* `string.ulen(s)` - length in Unicode characters
* `string.usub(s, from, to)` - Unicode substring
* `string.forall(s, fn)` - returns `true`, or `false` and the first failing
  character index
* `Char.is_alpha(c)` - whether `c` is a letter
* `Char.is_alnum(c)` - whether `c` is a letter or digit
* `Char.is_lower(c)` - whether `c` is lowercase
* `Char.is_upper(c)` - whether `c` is uppercase
* `Char.is_digit(c)` - whether `c` is a digit
* `Char.is_space(c)` - whether `c` is whitespace
* `Char.is_punct(c)` - whether `c` is punctuation (`!`, `?`, `&`, `;`, ...)
* `Char.is_ascii(c)` - whether `c` is ASCII

Letter and case checks apply to the English alphabet.

* `Error(msg, c, l)` - creates an error; `c` and `l` are optional and default
  to `1`
