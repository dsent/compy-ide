---
description: Text encoding across runtimes — which utf8 library you get, bytes vs characters, and the rules that keep the two from mixing
status: active
audience: developer
authored: llm
reviewed: none
---

# Text Encoding — UTF-8, bytes, characters, and three runtimes

All text in Compy is UTF-8. Lua strings are byte arrays and know nothing about that, so every
piece of code that measures, slices or positions text is implicitly choosing a **unit** — bytes or
characters — and the bugs in this area are all the same bug: two pieces of code choosing
differently and meeting.

This document is about the mechanics, not about any particular subsystem. Read it before writing
code that indexes into text, and before assuming a number you were handed is a character count.

## Which `utf8` you are running is not fixed

`src/util/string/utf.lua` picks the implementation at load time, and there are **three**:

| condition | implementation |
|---|---|
| `_VERSION == 'Lua 5.1'` and no `love` global | the **`lua-utf8`** rock (luautf8) |
| under LÖVE | LÖVE's **bundled** `utf8` module |
| otherwise (PUC Lua 5.3+) | the **standard library** `utf8` |

`src/util/string/string.lua` assigns the result to the **global** `utf8`, so most code sees it
without requiring anything.

The practical consequence is that **the suite and the application may not exercise the same
library**. A container running LuaJIT without LÖVE gets `lua-utf8`; the shipped app gets LÖVE's;
a developer on PUC Lua 5.4 gets the standard one. They agree on everything documented below, but
"the tests pass" is evidence about the interpreter that ran them and nothing more. When a claim
about text handling matters, say which runtime it was checked on.

## The one contract everything leans on

**`utf8.len(s)` returns the character count for valid UTF-8, and `nil` plus the byte position of
the first invalid sequence otherwise.** All three implementations provide this, and a surprising
amount of code depends on the `nil` half rather than the count.

The idiom for *making* a string valid is to trim and retry until it is:

```lua
local function sanitize_utf8(s)
  local r = s
  local n, pos = utf8.len(r)
  while not n do
    r = string.sub(r, 1, pos - 1) .. string.sub(r, pos + 1)
    n, pos = utf8.len(r)
  end
  return r
end
```

The same shape, trimming from the end rather than cutting out a byte, converts a byte offset that
may land *inside* a character into a character position — a prefix cut mid-character is invalid,
so shortening it until `utf8.len` answers walks back to the character's start, which is where a
caret belongs anyway.

**`string.ulen` is `utf8.len`**, including the `nil`. It is not a safe drop-in for `#`: `#` can
never fail, and `ulen` can, so `math.min(x, string.ulen(s) + 1)` raises on invalid input where the
byte version would merely have been wrong.

## Sanitise at the boundary, assume validity inside

The rule that makes the paragraph above tolerable: **text is validated where it enters, and
interior code may then assume every stored string is valid UTF-8.**

Get this right and `ulen` never returns `nil` in the interior. Get it wrong — add a new write path
that skips the boundary — and the failure does not appear at the new path. It appears in whatever
arithmetic first adds `1` to a `nil`, somewhere else entirely.

So when you add a way for text to enter a subsystem, the question is not "is this input trusted"
but **"does this path pass through the same sanitiser as the others"**. Sources worth treating as
hostile: file reads, anything a project computes and hands back, and any string
assembled from bytes.

## Which helpers count what

`src/util/string/string.lua` mixes both units deliberately. The distinction is not visible from a
call site, so it is worth knowing:

| helper | unit | note |
|---|---|---|
| `#s`, `string.sub`, `string.find` | **bytes** | Lua's own, unchanged |
| `string.ulen` | **characters** | `utf8.len`; may return `nil` |
| `string.usub`, `string.char_at` | **characters** | via `utf8.offset` |
| `string.split_at` | **characters** | ASCII fast path, see below |
| `string.lines`, `string.split` | either, safely | see "Splitting is safe" |

`string.split_at` shows the standard fast path: `if string.ulen(str) ~= #str` — when the two agree
the string is pure ASCII and byte operations are exact, so it uses the cheap ones. **That test
also treats invalid UTF-8 as multi-byte** (`nil ~= #str`), which routes into `usub`, which returns
`''` for it. Silent empties downstream of a text operation are worth suspecting here first.

## Splitting on ASCII delimiters is safe

UTF-8 is **self-synchronising**: bytes `0x00–0x7F` are always single characters, lead bytes are
`0xC2–0xF4` and continuation bytes are `0x80–0xBF`. An ASCII byte can therefore never occur
*inside* a multi-byte character.

So splitting on `\n`, `\t`, `,` or any ASCII delimiter with plain byte operations is exactly
equivalent to doing it by character. No `utf8` call is needed and none is cheaper. This is why
`string.lines` can be byte-based and still correct.

The same reasoning does **not** extend to searching for a non-ASCII substring with byte
operations — that can match starting mid-character unless the pattern is itself a whole number of
characters and the haystack is valid.

## `string.lower` / `string.upper` are byte-wise and locale-dependent

They apply C `tolower`/`toupper` per byte. They do **not** case-fold non-ASCII text: `('Ы'):lower()`
returns `'Ы'` unchanged. Do not reach for them expecting Unicode casing — there is none in the
standard library.

They are also nominally locale-sensitive. This project runs in the `"C"` locale (metalua's lexer
calls `os.setlocale("C")` at load), where only `A–Z` are affected, which makes them deterministic.

Where case-insensitive matching is needed, the defensible pattern is **symmetry rather than
correctness**: apply the identical transformation on both the storing side and the looking-up
side, in the same process. Then whatever the function does — including nothing, for non-ASCII —
the two sides agree by construction, and the match works without the transformation itself having
to be Unicode-aware.

## Byte offsets arrive from outside; convert them at the door

Character positions are the interior convention: cursors, columns, selections and the view's own
loops all count characters. **Values produced outside that convention are usually byte offsets**,
and the classic defect is passing one straight into code expecting the other.

Known producers:

- **Parser and compiler errors.** A Lua syntax error's column comes from a lexer working on the
  raw string, so it is a byte offset into the line. `src/model/lang/lua/parser.lua` reads it out
  of metalua's message.
- **Anything `string.find` returns**, including through helpers that wrap it.
- **`utf8.len`'s second return value** — a byte position, not a character index.

The failure is quiet and looks like an off-by-N that grows with the amount of non-ASCII text.
On a pure-ASCII line the two units coincide, so the code looks correct in every test written in
English. That is the reason this class of bug survives review.

**Convert once, at the boundary where the value enters the subsystem — not at each consumer.**
A byte column typically has more than one consumer (seat the caret, colour the error, scroll to
it), and fixing them one at a time leaves the rest wrong while making the code look fixed.

## Writing tests that would notice

A test in ASCII cannot fail for a units bug, because the two units agree. Any test covering
measurement, slicing or positioning wants a multi-byte case alongside its plain one — a Cyrillic
or accented string is enough, and `'привет'` is a convenient marker at 6 characters in 12 bytes,
far enough apart that an off-by-N is unmistakable.

Worth covering explicitly when the code is measuring text:

- a multi-byte string, so bytes and characters disagree;
- a position at the exact end (`n + 1` for a caret) and one past it, to catch a clamp using the
  wrong unit;
- invalid UTF-8, if the code can be reached without passing the sanitiser.
