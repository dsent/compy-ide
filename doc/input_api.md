---
description: Project-author guide to compy.input — the input widget, its config table, the submit lifecycle, hooks and shortcuts
status: active
audience: project author
authored: llm
reviewed: none
---

# Compy Input API

`compy.input` is what a project running inside Compy uses to **ask the user
for text** and to **react to input events** — every event the device produces,
not only the ones the widget cares about.

**There is also a simple way in** — `compy.ask`, `compy.on_answer`,
`compy.on_key` and `compy.unask`, four names on `compy` itself for a program
that just needs an answer. They drive the same widget this guide describes;
see *"Two surfaces: simple and precise"* below. Everything under
`compy.input` is what this guide calls the **precise** API, and it is three
surfaces:

1. **The input widget** — put it on screen and change it while it is
   there: `show`, `hide`, `configure`, `set_text`, `set_cursor`, `clear` —
   and the reads `is_shown`, `get_text`, `get_cursor`.
2. **Callbacks** — what the widget tells you back: a submission, a cancel, a
   cursor hitting a boundary, a validator's verdict.
3. **Inbound events** — shortcuts and hooks over the keyboard, the mouse and
   the touchscreen.

The third stands on its own: **a project that never shows the widget can still
use `compy.input` for hotkeys, combos and click handling.** Nothing here is
polled, and there is no compatibility shim — a project reads events by
registering for them.

## Vocabulary

A few terms that show up everywhere in this guide. Reading this once saves
re-reading the sections that use them.

**Widget.** The thing `show()` puts on screen and `hide()` takes away: a label
and a line the user types into. **It is called the widget, here and everywhere
else** — not an overlay, not an area, not a field, and not a prompt. It is
**shown** and **hidden**, which is the vocabulary the calls themselves use
(`show`, `hide`, `is_shown`, `hide_on_submit`) — **so it is never opened, closed, up
or down**: those four spellings are out for this sense exactly as the four
nouns are. Its content is **text**
(`text`, `set_text`, `get_text`), so "clear the text" says what "clear the
field" used to.

*Why this is worth a paragraph: `prompt` is a **config key** and it means the
**label**, so a sentence like "the prompt closes" names the widget with the
word already reserved for one of its parts. The other three are ordinary
English that read as new concepts when a reader meets them beside `widget`.
Note the words are only out **for this sense** — an on-screen overlay drawn
over a scene is still an overlay (the framework's compositing pass, the
`keyboard` example's help card, the FPS corner), and a table's `field` is
still a field.*

**Draft.** The text the user has typed and **not yet submitted**. It is a
first-class term in this guide, deliberately: the widget's content key is
`text`, so prose needs a separate word for *content that is still the user's*,
and `discard_draft()` is named for it. A draft is what a validator rejects
without losing, what Escape clears, and what survives a `configure`.

*The word means **only** that. Configuration a project has staged for a widget
that is not shown yet is **pending config**, never a draft; and an earlier
version of a document or an argument is a **variant**. The distinction is worth
holding because the two things it separates belong to different people — a
draft is the user's, pending config is the programmer's.*

**Content callbacks and lifecycle callbacks.** The widget's callbacks are two
sets, and which set a callback is in decides **where you may set it**. The four
**content** callbacks are about the text being edited — `on_text_entered`,
`on_limit_reached`, `validator`, `highlighter` — and they are settable both
ways: in the config table of `show()` or `configure()`, or as fields on
`compy.input.callbacks`. The four **lifecycle** callbacks are about the
finalization around it — `before_submit`, `after_submit`, `before_cancel`,
`after_cancel` — and they are **assignment-only**: `compy.input.callbacks` is
their home, and naming one in a config table raises and says so.

*The split follows the use rather than the implementation: a project names
content callbacks at the moment it asks a question, and sets lifecycle
callbacks structurally, once.*

**Channel.** One kind of device event — `keypressed`, `textinput`,
`mousepressed`, `singleclick`, etc. Every channel carries exactly the arguments
LÖVE delivers for it (e.g. `keypressed` carries `key, scancode, isrepeat`).
Keyboard, pointer and touch channels all work the same way; a project registers
for them in the same tables.

**Combo.** A string that names *what the user pressed*: the held modifiers plus
one trigger key or button. `'ctrl+s'` is a combo. `'mouse2'` is a combo. The
modifiers are optional (`'s'` is also a valid combo — bare, unmodified S), they
come in a fixed order (ctrl, alt, shift — there are three), and left/right fold
together, so `'Ctrl+Alt+S'` and `'ctrl+alt+s'` are the same binding.

**Hook.** The primary, generic handler for an entire channel (`compy.input.hooks.<channel>`). A hook carries your project's main, generalized event processing logic (such as overall game controls, canvas drawing, or state transitions). There is at most one hook per channel. When your project defines `love.keypressed`, `love.mousepressed`, etc., those functions are automatically installed as hooks — so existing LÖVE code keeps working. A handler installed that way **consumes its channel**, exactly as it does under plain LÖVE, where assigning `love.keypressed` means owning the key; a hook you write into `compy.input.hooks` yourself follows the truthy convention instead. If your project shows the input widget, write the hook — see "How events reach your project".

**Shortcut.** An optional guard function registered in front of the hook for a specific key or button combo (`compy.input.shortcuts.<channel>[combo]`). Shortcuts allow intercepting events early for specific combos — most often to process and stop event propagation (or just stop), and optionally to ride along without consuming (`fn.side_run`).

**Modifier class.** A combo with `*` as its trigger: `'alt+*'` matches every
Alt chord. An exact shortcut wins over the class, so you can have a catch-all
`'alt+*'` and still bind `'alt+p'` specifically.

**Dispatch chain.** The fixed order in which every input event is offered to your
project's handlers. For each event, the framework tries three consumers in order:

```
  1. shortcut  — compy.input.shortcuts.<channel>[combo] (optional early guard)
  2. hook      — compy.input.hooks.<channel> (generic channel handler)
  3. widget    — the input widget (only when shown; stateful terminal consumer)
```

The walk stops at the first consumer that **consumes** the event.

**Consume.** A shortcut or hook consumes an event by returning a truthy value
(`return true`). That tells the framework "I handled this; nothing below should
see it." A shortcut that returns nothing (or a falsey value) lets the event fall
through to the hook, and a hook that returns nothing lets it reach the widget.
The input widget, when shown, always consumes — it is the terminal consumer.
**One exception, and it is the reason to register hooks yourself:** a hook the
framework captured from your `love.*` handler consumes whether it returns
anything or not, because that is what assigning `love.keypressed` means in
LÖVE.

This is the entire event model: three consumers, tried in order, stop on the
first truthy return. There is no bubbling, no capturing, no priority numbers.
The rest of this guide is the detail of each surface.

## Two surfaces: simple and precise

There are two ways to ask the user for text, and they drive **the same widget**.

**The simple API** is four names on `compy` itself. Use it when your program
just needs an answer:

```lua
compy.on_answer = function(text)
  if text then greet(text) else print("never mind") end
end

compy.ask("Your name?")
```

**The precise API** is `compy.input.*` — everything else in this guide. Use it
when you want the widget to stay, to decide what a submit or an Escape leaves
behind, or to keep the question open while your program reacts.

You do not have to choose once and for all: `ask` is a wrapper that writes the
precise API's own fields for you and puts them back when the question ends. A
reader who learns `ask` first and `show` later finds that the second contains
the first.

## Quick start — the simple API

```lua
compy.on_answer = function(text)
  print("hello, " .. (text or "stranger"))
end

compy.ask("Your name?")
```

`compy.ask(...)` puts the question on screen. When the user presses Enter,
`compy.on_answer` is called with what they typed and the question is taken
down. When they press Escape instead, `on_answer` is called with **`nil`** —
that is how you tell *answered* from *abandoned*, and it works even for an
empty answer, because `''` is truthy in Lua while `nil` is not.

`ask` takes optional positional arguments:
`compy.ask(prompt, highlighter, text, cursor)`. So a question can specify
a `highlighter` function, initial `text`, and an initial `cursor` position.

**`compy.on_key`** reports keys while a question is open, and its **return
value decides who gets them**:

```lua
compy.on_key = function(key)
  if key == "f1" then show_help(); return true end   -- claimed
  -- everything else falls through and edits as usual
end
```

Return truthy and the key is yours — the text field never sees it. Return
nothing and the field handles it normally, so `backspace` still deletes.
Modifier keys alone are never reported, and neither are ordinary characters
(those are just typing). Held keys repeat, the same way typing does. The full
signature is `on_key(key, scancode, isrepeat)`.

**`compy.unask()`** takes a question back when your program changes its mind.
It closes the question and restores everything, and it does **not** call
`on_answer` — nobody answered. Use it rather than `compy.input.hide()`, which
belongs to the precise API and leaves the question half-installed.

One rule to know: `compy.ask` **raises** if your program already installs a
`compy.input.hooks.keypressed` or a `love.keypressed`, because a question needs
that channel. Nothing is lost — a program that wants both writes what it wants
with the precise API instead.

## Quick start — the precise API

```lua
compy.input.show{
  prompt = "say something:",
  on_text_entered = function(text)
    print(text)
  end,
}
```

That is a complete prompt. The input widget stays shown after a successful
submit and the field is emptied for the next one, both by default, so a
continuous prompt needs nothing else. Escape does nothing unless you ask it
to.

## The input widget — showing it and changing it

Everything that puts the widget on screen and alters it while it is there.

### `show(config)`

`compy.input.show(config)` activates the input widget. All keys are optional.

| Key | Meaning |
|---|---|
| `prompt` | Label shown beside the text the user types. |
| `text` | Initial content: a string or list of line strings — the two spellings mean the same thing. |
| `cursor` | Initial `{line, col}` after `text` is applied. |
| `highlighter` | `function(lines) -> coloring`; changes display only. |
| `validator` | `function(lines) -> true` or `false, Error[]`; gates submit. |
| `on_text_entered` | `function(text)` called after successful validation, with the submitted content as one string. |
| `on_limit_reached` | Called when cursor movement reaches a boundary. |
| `force` | `show` only: re-show a widget that is already shown. |
| `clear_on_submit` | Empty the text after every successful submit. **On by default.** |
| `hide_on_submit` | Hide the widget after every successful submit. |
| `clear_on_cancel` | Empty the text when the user presses Escape. |
| `hide_on_cancel` | Hide the widget when the user presses Escape. |

The last four are the **lifecycle flags**: one per (verb × outcome), and each
is an independent setting you turn on or off. **Exactly one is on out of the
box** — `clear_on_submit`, so a submitted answer does not sit in the field
waiting to be sent again. **Escape has no default outcome at all**: it neither
hides nor clears until you say so. Flags persist once set, until changed again or
unset with `false`. You can set them via `compy.input.configure{...}` before or
between shows, or pass them in a `show{...}` call — both change the flags and
both persist. Set any of them to `false` to turn it off, and see *"Setting the
lifecycle once"* below.

`show` on an active input widget warns and does nothing unless `force = true`.
With `force`, it is a **full re-setup** — the same thing a first `show` does,
with the config you passed. `force` answers that one question and nothing
else: a forced `show` with no `text` leaves the content alone, exactly as a
bare one does.

**`show` never throws content away on its own.** `text` you pass is the
content; `text` you leave out changes nothing, so a `show` after a `hide`
comes back to what was there. What empties the widget is a lifecycle flag you
set — `clear_on_submit` is on for a project's widget — or a `clear()` of your
own, or `text = ''` on the `show` itself.

Two kinds of key live in this table, and the difference is who owns the thing
they set:

- **Your content** — `text` and `cursor` — belongs to the person typing, so
  only `show` seats it. While the widget is shown, `set_text`, `set_cursor` and
  `clear` are the ways to change it.
- **`force` describes the `show` itself** — it answers "replace the widget
  that is already shown", which is not a question `configure` can be asked — so it
  is `show`-only and raises from `configure`, naming `show`.
- **Everything else** belongs to your project, the lifecycle flags
  included. Those keys
  are set only when you name them, and stay until you replace them: leaving one
  out changes nothing, and there is no key that `show` applies and `configure`
  quietly drops.

`false` is how you unset any project-owned key (`prompt`, `highlighter`, `validator`, `on_text_entered`, `on_limit_reached`, and the four lifecycle flags). Passing `false` restores the key to its absent/default state, making expressions like `custom_validator or false` safe to pass when dynamically toggling settings.

For `prompt`, `''` is an empty label and `false` restores the default one. A
`cursor` of `false` seats none, leaving the baseline `show` just applied. A
`text` of `false` is the same as leaving `text` out — the content is left
alone — because `false` is the unset everywhere and an unset `text` is a
`show` that says nothing about content. **`text = ''` is the explicit empty**:
that is text given, and given text is what the widget shows.

A `cursor` that is not a `{line, col}` pair of numbers raises, naming the
shape. Out-of-range numbers are fine and clamp — `{1, 999}` lands at the end
of line 1.

A key outside this table **raises**. The config table is closed, so an
unrecognised key can only be a mistake, and a mistake you can see beats one
that leaves the input widget quietly not doing what you asked. This includes
lifecycle callbacks such as `after_submit`: assign those to
`compy.input.callbacks` instead.

```lua
-- Wrong: raises, naming the key and where it belongs.
compy.input.show{ after_submit = function() end }

-- Right: a direct callback assignment.
compy.input.callbacks.after_submit = function(text)
  log_answer(text)
end
```

### `hide()`

`compy.input.hide()` takes the input widget off screen. It does **not** tear
it down, and there is no call that does: the widget belongs to the surface it
serves — for a project, to the run — so `hide` and a later `show` are state
flips on one instance, never a rebuild. Your project never holds the widget
object, and nothing survives the end of a run.

**A hide takes nothing away.** `prompt`, `highlighter`, `validator`, the
callbacks and the lifecycle flags are all still in force at the next `show`,
because they are yours and stay until you replace them — and so is the text,
the caret, the selection and where a history walk had got to. A `hide`
followed by a `show` puts the widget back as the user left it.

```lua
compy.input.show{ prompt = 'name?', text = 'ada' }
compy.input.hide()
compy.input.show()   -- still labelled 'name?', still 'ada'
```

If you want the widget to come back **empty** instead, say so on the `show`:

```lua
compy.input.show{ text = '' }
```

`get_text()` and `get_cursor()` read the content and the caret if you want to
keep a copy of your own — for a save file, say, rather than for the widget.

```lua
local text = compy.input.get_text()
local l, c = compy.input.get_cursor()
```

**Both reads must happen before a `hide`.** While the widget is hidden they
answer `nil` — a plain "nothing to report" rather than a refusal, so neither
warns the way the mutating calls do, and a save written after the `hide`
silently saves nothing.

**The widget's input history is its own, not yours to read.** The widget keeps
a history of what has been entered, but no call reaches it — the public surface
is `show`, `hide`, `configure`, `set_text`, `set_cursor`, `clear`, `get_text`,
`get_cursor` and `is_shown`, and none of them reads, walks or empties that
history. If you want recall — an up/down walk through earlier answers, the way
the IDE console offers — **keep your own list** and drive the field with
`set_text`. `on_limit_reached` is the hook the console itself builds recall on:
it fires when the caret tries to move past the first or last line, so it is
where "the user asked for the previous entry" arrives. You get that trigger; the
console's own step back and forward through its history is internal, so a project
reproduces the *behaviour* on a list of its own rather than sharing the widget's.

### Live changes

`compy.input.configure(config)` changes the project's own settings on the
input widget — `prompt`, `highlighter`, `validator`, `on_text_entered`,
`on_limit_reached`, and the four lifecycle flags. It raises on an unrecognised
key by the same rule as `show`.

`configure` never touches your content, so `text`, `cursor` and `force` raise
from it as keys belonging to another call, the way a lifecycle callback already
does. Use `show` to seat content, and `set_text` / `set_cursor` / `clear` to
change it while the widget is shown.

Calling `configure` while the widget is hidden is fine and does not warn: the
settings apply straight away and are still in force at the next `show`. To
show a widget with content already in it, pass the content to that `show` —
it is applied before anything is on screen.

`compy.input.is_shown()` tells you whether the input widget is shown. Use it when a
project must not act twice — showing the widget from a key that is also
typed *into* it, for example:

```lua
compy.input.hooks.keyreleased = function(key)
  if key == 'i' and not compy.input.is_shown() then
    compy.input.show{ prompt = 'command' }
    return true -- consumed; while it is shown, 'i' is the widget's
  end
end
```

That guard stops *later* presses of `i` from re-showing the widget. It does
not stop the `i` that showed it from being typed into it — see "Worked
example: the trigger key echoes into the widget it showed" below.

**While the widget is shown, your own handlers keep running.** Hooks and
shortcuts sit *above* it — see "Why the widget sits at tier 3" — so every key
the user types reaches yours first. An unguarded handler acts on that typing:
a space toggles your mode, a capital `R` moves your world, and the keystroke
still lands in the widget, so nothing looks wrong from either side.

The remedy is one line, and it covers the **whole** handler:

```lua
compy.input.hooks.keypressed = function(key)
  if compy.input.is_shown() then return end
  -- the rest of your handler, inert while the widget is shown
end
```

**Those are two different guards and you want both.** The narrow one above
belongs on the key that *shows* the widget, which must still act while the
widget is hidden. The blanket one belongs on everything else.

A blanket guard switches your own hotkeys off for as long as the widget is
shown. That is usually what you want, and it does not strand anyone: the
combos the platform keeps are answered before your project sees the event, so
`ctrl+escape` still ends the run no matter what your handler does — see
"Combos the framework keeps".

`compy.input.set_text(text [, keep_cursor])` replaces content. `clear()`
empties it. `get_text()` reads it back. `get_cursor()` returns `line, col`;
`set_cursor(line, col)` moves it. Mutating calls warn and do nothing while
the input widget is hidden.

**`get_text()` answers one string**, with `\n` between
lines — the same spelling `on_text_entered` is given, and one you can hand
straight back to `set_text`. An empty widget answers `''`; a hidden one
answers `nil`, so the two are never confused. Like `get_cursor()`, reading
while hidden is not an error and does not warn: there is simply nothing to
report.

It is the only way to see what the user has typed **without waiting for a
submit** — useful when your project decides the moment: a timeout that takes
whatever has been entered so far, or a hotkey that acts on the current text.

`col` is a **caret position between characters**, not a character index: it
ranges from `1`, before the first character, to one past the last, at the
end of the line. So on `"lemon"`, `set_cursor(1, 3)` puts the caret between
`e` and `m` — typing inserts there (`"leXmon"`) and Backspace deletes the
character before it (`"lmon"`). Out-of-range values clamp to that range
rather than failing.

**Characters, not bytes.** The line `"привет"` is six characters, so its
caret positions are `1 .. 7` — not `1 .. 13`, which is what its length in
bytes would give. Every cursor position the widget reports or accepts is
counted this way.

**Newlines always start a new line, in either spelling.** Content is a
string or a list of line strings, and the two mean the same thing:
`set_text("a\nb")` and `set_text{"a\nb"}` both give you two lines, exactly
as `set_text{"a", "b"}` does. A newline is never kept as a character
*inside* a line — if it were, the caret could sit past a line terminator
and `col` would no longer say where you are. Blank elements are content
and survive: `set_text{"a", "", "b"}` is three lines. The same holds for
`text` at `show`.

**A list must be a dense run of strings from `1`, and anything else is
refused** — `set_text{"a", 42}` raises
`compy.input.set_text: text must be a string or a list of line strings`,
and `show` raises the same message under its own name. The widget will
reshape how your content is *spelled*, but it will not guess what you
meant by a value that is not text: convert it yourself with `tostring`
where you want a number shown. The refusal leaves the current content
untouched.

## What the widget tells you — callbacks

Everything the widget calls back about: a submission, a cancel, a boundary, a validation.

### Submit lifecycle

Enter submits; Shift+Enter inserts a newline. On a non-empty submission the
order is:

1. `before_submit(text)`, if assigned. A truthy return vetoes the
   submit: steps 2-4 do not run and the text stays.
2. `validator(lines)`, if assigned.
3. `on_text_entered(text)`, if assigned.
4. `after_submit(text)`, if assigned.

**Every callback that can see your content is handed the same thing: one
string, lines joined with `\n`.** `on_text_entered` and `after_submit` are told
apart by *when* they run, not by what they carry — 3 before 4, both after
validation. `validator` and `highlighter` are the exception and receive
`lines`, because they work position by position and a validator has to be able
to say *which* line failed. A rejecting validator returns
`false, errors`, where `errors` is a list of positioned `Error` values; the
input widget displays the error and steps 3–4 do not run. A highlighter has no
submit or validation authority: it only controls how the current text looks.

**Which one should your work go in?** Either, or both — this is a
recommendation and nothing enforces it. Reach for `on_text_entered` when the
work is about the text the user typed, and for `after_submit` when it is
machinery that happens to run at submit time: re-arming a guard, starting the
next step. Only the order separates them, so if you set just one, set the one
whose name says what you are doing. Following it costs nothing and buys a reader of your project one
less question; ignoring it breaks nothing.

**Clearing and hiding are not callback work.** They are the lifecycle flags,
and they have already happened by the time your callbacks run: the widget is
emptied and taken down first, and then the callbacks are called with the
content as their argument. So `after_submit` reading `get_text()` gets an
empty widget — read the text it is handed instead. The order is deliberate:
it means a callback can ask the **next** question, with a plain `show`, and
the submit it belongs to will not take that new question down.

The input widget clears and remains shown after a submit. To close it as well,
pass `hide_on_submit = true` — that is the form to reach for, and it is covered
in *"Asking one question"* below.

Escape first runs `before_cancel(text)`. A truthy return vetoes the cancel
outright: nothing is cleared, nothing is hidden, and `after_cancel` does not
run either. Otherwise the cancel flags act, and then `after_cancel(text)` is
called. Both are handed the draft, so a veto can look at what it is about to
refuse to throw away.

**By default Escape does nothing at all**: your widget is not hidden and your
draft is not cleared, and `after_cancel` is where you decide what Escape should
mean for your project. If you want an outcome, ask for it — see *"Setting the
lifecycle once"* below.

### Setting the lifecycle flags

The lifecycle flags belong to your project: each applies and persists until you
pass `false` for it or set a new value. `configure` and `show` are simply **two ways to
change a flag** — setting a flag via `show` overrides its previous value and that
new value persists for subsequent submits, exactly as if set via `configure`.

Setting flags with `configure` before your first `show` is recommended when setting up your program's configuration:

```lua
compy.input.configure{ hide_on_submit = true }
compy.input.configure{ clear_on_submit = false }

compy.input.show{ prompt = "..." }
```

Passing them directly on `show` does the exact same thing:

```lua
compy.input.show{
  prompt = "...",
  hide_on_submit = true,
  clear_on_submit = false,
}
```

In both cases, `hide_on_submit = true` and `clear_on_submit = false` persist until changed again or set to `false`.

Be explicit about Escape: nothing is seated on it by default (`hide_on_cancel = false`, `clear_on_cancel = false`), so a project that never sets Escape flags leaves Escape inert.

### Asking one question — `hide_on_submit`

When your project is not *about* input and just needs an answer, setting `hide_on_submit = true` hides the widget after a successful submission:

```lua
compy.input.show{
  prompt = "Your name?",
  on_text_entered = function(text) greet(text) end,
  hide_on_submit = true,
}
```

The answer arrives as the callback's argument, the field is emptied by `clear_on_submit` (on by default), and `hide_on_submit` puts the widget away.

- It hides after a **successful** submit, so a `before_submit` veto, an empty
  widget or a rejecting validator all leave it shown, with the draft intact.
- Your own `after_submit` still runs, and runs **last** — the widget is
  already empty and already hidden by then, so read the content from the
  argument you are given rather than from the widget.
- If one of your callbacks **raises**, the widget is left hidden: the clearing
  and hiding ran before it. Your project suspends with the error, which is the
  failure worth seeing.
- **Escape does nothing unless you ask it to.** If a question the user can
  dismiss is what you want, pass `hide_on_cancel = true`, and
  `clear_on_cancel = true` to empty the field with it. Ask deliberately: if
  your project shows the widget once and has no way to show it again, a
  dismissable widget is one the user can lose for the rest of the run.
- **Asking a follow-up question from inside your callback: just ask it.** The
  hide belonging to this submit has already happened, so a plain
  `compy.input.show{...}` from `on_text_entered` or `after_submit` opens the
  next question. (Note: if `hide_on_submit` was set to `true`, it persists on the next `show` unless explicitly cleared with `hide_on_submit = false`).

### Validation and highlighting

Projects can use the supplied helpers or provide functions with the same
shapes. The helpers are globals in the project environment:

| Helper | Use |
|---|---|
| `LuaHighlighter(lines)` | Lua syntax coloring for the input widget. |
| `LuaSyntaxValidator(lines)` | Accepts valid Lua or returns positioned parse errors. |
| `LineValidators(filters)` | Adapts one filter or a list of line filters into a validator. |

A line filter receives one string and returns `true`, or `false, error`.
`LineValidators` applies every filter to every submitted line and turns
rejections into positioned `Error` values.

```lua
local natural = function(line)
  if line:match("^%d+$") then return true end
  return false, Error("Expected a natural number", 1)
end

compy.input.show{
  prompt = "Guess a number:",
  validator = LineValidators(natural),
  on_text_entered = function(text)
    check(tonumber(text))
  end,
}
```

For code entry, choose the display and submit policies independently:

```lua
compy.input.show{
  prompt = "Lua:",
  text = string.lines(body),
  highlighter = LuaHighlighter,
  validator = LuaSyntaxValidator,
  on_text_entered = function(text)
    body = text
  end,
}
```

### Callback assignments

`compy.input.callbacks` is writable. These entries may also be supplied in
`show` or `configure` and persist until replaced: `on_text_entered`,
`on_limit_reached`, `validator`, and `highlighter`. `prompt` and the four
lifecycle flags are not callbacks, but they persist the same way — set one once and it stays
until you set it again.

Assigning here and passing the key to `show` / `configure` are the same
write, and either takes effect immediately. Set any of them to `false` to
unset it.

The lifecycle entries are direct assignments only: `before_submit`,
`after_submit`, `before_cancel`, and `after_cancel`. Each is handed the
content as one string, the same string `on_text_entered` gets.

## Inbound events — shortcuts and hooks

Everything that reaches your project from the keyboard, the mouse and the
touchscreen — with or without a widget on screen. The terms *shortcut*, *hook*,
*combo*, *channel*, *consume* and *dispatch chain* are defined in the
Vocabulary section above.

### How events reach your project

When LÖVE fires an input event (a keypress, a mouse click, a touch), the
framework first checks whether the platform has a reserved combo for it (see
"Combos the framework keeps" below — these are things like Ctrl+Escape to
stop the project). Platform reservations act **and pass the event on** — they
never consume.

Then, while your project is running, every event walks the dispatch chain:

```
  LÖVE event arrives
    │
    ▼
  ① shortcut — is there a shortcut for this combo?
    │            yes, and it returned truthy → stop (consumed)
    │            no match, or returned falsey → fall through
    ▼
  ② hook — is there a hook for this channel?
    │        yes, and it returned truthy → stop (consumed)
    │        no hook, or returned falsey → fall through
    │        (a hook picked up from your love.* handler always
    │         stops here — see below)
    ▼
  ③ widget — is the input widget shown?
               yes → the widget handles it (always consumes)
               no  → nobody handled it
```

The arguments every consumer receives are LÖVE's own, unchanged —
`keypressed` gets `(key, scancode, isrepeat)`, `mousepressed` gets
`(x, y, button, istouch, presses)`, and so on. A handler you wrote as
`love.keypressed` works unchanged when it becomes a hook, because the
signature is the same.

**One difference, and it is at tier ②: a handler picked up from `love.*`
consumes its channel.** It stops the walk whether it returns anything or
not — which is what it did under plain LÖVE, where assigning
`love.keypressed` means owning the key and there is nothing below you to
fall through to. Your code was written under that convention, so the
framework keeps it rather than reading a return value you never chose.
A hook you assign yourself is the other case: you have met the truthy
convention by writing it, so `compy.input.hooks.keypressed` falls
through on falsey like everything else in the chain.

**What this means in practice:** if your project shows the input widget
*and* handles keys, write `compy.input.hooks.keypressed = function(k)`
rather than `function love.keypressed(k)`, and **return a meaningful
value** — truthy for the keys you are claiming, nothing for the ones the
widget should have. Keep the legacy spelling and your handler eats every
key before the widget sees it, and the user cannot type — not even Enter
to submit. A project with no widget is unaffected: nothing sits below the
hook for it to shield, which is why plain LÖVE code keeps working.

### Why the widget sits at tier 3

Placing shortcuts and hooks *above* the widget gives your project full control to intercept events flexibly (blocking or bypassing them using filter-like functions) before they reach the text surface. The input widget itself is a stateful component that consumes events without the ability to pass them further down in pipeline style. Placing it after shortcuts and hooks ensures that a shown widget does not lock out your project's custom hotkeys or event guards unless your handlers explicitly allow them to fall through.

### Event hooks and shortcuts — when to use which

- **Hooks (`compy.input.hooks.<channel>`)** are your project's **generic event handlers**. Use a hook for complex, generalized event processing across an entire channel (such as character movement, drawing on canvas, or general game state handling). There is at most one hook per channel.
- **Shortcuts (`compy.input.shortcuts.<channel>[combo]`)** are **optional early guards** configured in front of the hook. Use a shortcut for clearly detectable, combo-specific alternative interceptions earlier in the dispatch walk — most often to process and stop propagation (or just stop), and optionally to ride along without consuming (`fn.side_run`).
- **A captured `love.*` handler** is the third way in, and it is the one to avoid when a widget is involved. It reaches the same hook slot, but it **consumes its channel unconditionally** — see "How events reach your project" — so nothing below it runs.

**The recommendation, in one sentence:** a project that intends to use the `compy.input` widget **and** to run its own key handling in front of it should **not** use the native `love.*` form — register the hook as `compy.input.hooks.<channel>` and return a meaningful propagation-stopping flag, so *you* decide per event whether the widget sees it.

That is the whole of the difference. The legacy spelling says "this channel is mine", which is what it meant in LÖVE and is still the right answer for a project with no widget — a game that owns the screen and reads the keyboard needs nothing else. The hook spelling says "this channel is mine *when I say so*", and only the second one can share a channel with the widget you are showing.

`compy.input.shortcuts.keypressed[combo]` registers a combo-specific
function. `shortcuts.keyreleased` and `shortcuts.textinput` work the same
way.

Held modifiers are not among the event arguments: ask `Key` for them —
`Key.shift()` for a modifier, `Key.any_pressed(k)` for any other key —
which works inside a handler and outside one alike; see "Held keys" below.

The combo vocabulary is covered in the Vocabulary section above. Three
additional rules: Super/Cmd is **not** a modifier (there are exactly three:
ctrl, alt, shift), a combo naming two triggers or none **raises**, and a
combo is **case-insensitive** — `'Ctrl+S'`, `'ctrl+S'` and `'ctrl+s'` are
one binding, and typing `I` fires the same `shortcuts.textinput['i']` that
typing `i` does. Only the *matching* ignores case: the handler still
receives the character the user actually typed as its first argument, so
a shortcut that needs to tell `I` from `i` reads its own argument.

The trigger may be `*`, which binds the whole modifier class: `'alt+*'` is
every Alt chord, and the handler receives the actual key as its first
argument. An exact binding wins — with both `'alt+*'` and `'alt+p'`
registered, Alt+P runs the exact one. A class is its modifier set exactly, so
`'alt+*'` does not catch Ctrl+Alt+H, and it never fires for the modifier's own
press.

A bare `'*'` raises: a class needs modifiers to be a class *of*. For every key
on a channel, use a hook — that is what hooks are.

```lua
compy.input.shortcuts.keypressed['alt+*'] = function() return true end
compy.input.shortcuts.keypressed['alt+p'] = function()
  pause()
  return true
end
```

A held key repeats, and shortcuts and hooks see every repeat. Three
**wrappers** under `compy.input.fn` let you declare repeat and propagation
behaviour at the registration site, so the handler function itself does not
have to know:

| wrapper | effect |
|---|---|
| `fn.ignore_repeat(f)` | skip `f` on a repeat; says nothing about propagation |
| `fn.stop_here([f])` | run `f` if given, then consume — the event stops here |
| `fn.side_run([f])` | run `f` if given, and let the event carry on |

They are orthogonal — one about whether your function *runs*, two about where
the event *goes* — and they compose:

```lua
local fn = compy.input.fn
-- a reserved key: acts once per press, nothing below sees it
sc['ctrl+alt+up'] = fn.stop_here(fn.ignore_repeat(function() notch(1) end))
-- swallow a whole class, with nothing to run
sc['alt+*'] = fn.stop_here()
-- a side effect: acts once, and the key still reaches the widget
sc['backspace'] = fn.side_run(fn.ignore_repeat(note_deleting))
```

`stop_here` and `side_run` both take the function optionally, and `side_run`
lets the event through even when the wrapped function returns truthy — the
declaration at the registration site outranks the handler, which is the point
of declaring it there.

Without them you would end handlers with `return true`, which makes a function
that merely toggles a pause know what happens after it returns, and carry that
knowledge wherever it is reused.

All three wrap a hook the same way, but think before you do: a whole-channel
hook wrapped in `stop_here(ignore_repeat(...))` swallows every repeat on that
channel, so held backspace and held arrows stop repeating in the input widget too.

Combos of ordinary keys — "A and B held together" — are deliberately not
expressible. Every binding would otherwise become conditional on nothing else
being held, so holding a movement key would silently break unrelated
shortcuts. Anything beyond exact-or-class matching belongs in a hook, which
sees every event on its channel; "Choosing the mechanism" below covers what to
do when a binding and a held key have to work together.

**Hooks** are the fallback after shortcuts. `compy.input.hooks.keypressed`,
`.keyreleased`, and `.textinput` each hold one function per channel. At
activation, an existing project `love.*` handler seeds the matching hook when
no explicit hook was supplied, so a project that already defines
`love.keypressed` keeps working without changes — and consumes its channel,
as it did under plain LÖVE ("How events reach your project").

### Combos the framework keeps

A few combinations belong to the platform. They are answered before your
project's route exists, so **a project cannot override one by naming it** — but the
platform does not swallow the key either: **your binding still runs**, and the
platform's action happens as well.

That combination is worth reading twice, because it is the opposite of how your
own shortcuts behave. Yours consume by returning truthy. A reserved combo never
consumes; it acts *and* passes the key on.

The practical consequence is only visible for the ones that end a run: your
handler runs, and then the project is stopped anyway. Nothing suppressed you —
the route you were bound to was taken down underneath you.

**A reservation is its modifier set exactly.** It does not extend to chords it
does not name, so `ctrl+shift+escape` is yours to bind even though `ctrl+escape`
is not, and `ctrl+shift+t` is yours even though `ctrl+t` is not. Adding a
modifier to a reserved combo is a reliable way to get a nearby chord for
yourself.

| Combo | What the platform does | When |
|---|---|---|
| `ctrl+escape` (on **release**) | stops the run; quits when there is nothing to go back to | always |
| `ctrl+alt+r` | restarts the project | always |
| `ctrl+t` | switches between running and the editor | development only |
| `ctrl+s` | stops a running project | development only |
| `ctrl+q` | quits the project | development only |
| `ctrl+pause` | suspends the run | development only |
| `ctrl+shift+r` | resets: quits and wipes the console | development only |
| `ctrl+alt+p` / `ctrl+alt+shift+p` | starts / stops the profiler | profiling builds |
| `f10` | cycles the FPS overlay corner | profiling builds |

"Development only" means the combo is inert in a packaged build, where the
console it returns you to is not there to return to. Note `f10` is the one
reservation with no modifier at all: bare F10 is the platform's in a profiling
build, and F10 with any modifier is yours.

It is also the only F-key worth binding at all. On the current hardware the
function row is the keyboard's Fn layer — Insert is Fn+F12, Scroll Lock is
Fn+F10, mute and the media keys are Fn+F5 through Fn+F8 — so **F1 to F9 never
reach your project**; the firmware answers them. F10 does arrive, which is why
the platform could take it; F11 and F12 are untested. Bind help, pause and debug
gestures to letter chords instead: an example that wants a held help overlay
uses Alt+H (`doc/development/keyboard.md` is the per-key availability table).

Ctrl+Shift+S also does something in the **editor** — it leaves the edit — but
that is the editor's own handling, not a reservation: it applies when you are
editing, not while your project runs. Bare Ctrl+S does nothing there; the
editor keeps it for itself.

**Known limitation, and it ships this way.** Ctrl+Shift+S and Ctrl+T both leave
the editor **without writing an open, changed block** — the changes are lost
without a prompt. Shift+Esc is the supported way out and the only *exit* that
asks before discarding; use it. (One further path discards a draft without
asking, without leaving the editor: Ctrl+J while editing moves you to another
file, and a Shift+Esc after it no longer sees an edit in progress.) Both chords predate this release and are documented
rather than fixed here — the contract is
`doc/development/decisions/input.md`, `D-EDITOR-KEYS`, statement 6.

### Pointer and click hooks

Pointer events run the same chain as keyboard ones, so they are hooks like
any other: `hooks.mousepressed`, `.mousereleased`, `.mousemoved`,
`.wheelmoved`, `.touchpressed`, `.touchreleased`, `.touchmoved`. Each
receives exactly the arguments LÖVE delivers, and each is seeded at
activation from your `love.*` handler of the same name, so an existing
`function love.mousepressed(x, y, btn)` keeps working untouched — and,
like every seeded handler, consumes its channel ("How events reach your
project").

Two more are **derived**: the framework watches the raw presses and decides
whether they amount to one click or two, then delivers the verdict as an
ordinary event.

```lua
compy.input.hooks.singleclick = function(x, y) place(x, y) end
compy.input.hooks.doubleclick = function(x, y) remove(x, y) end
```

A single click waits up to 0.4 seconds after release so the framework can
recognize a double-click. Moving 2.5 pixels or more on either axis after
release confirms the single immediately at its saved release position. A second valid release within that window and
within 2.5 pixels on each axis delivers a double-click immediately; each
pair is consumed separately. Clicks at separate positions remain singles.

Moving 2.5 pixels or more on either axis while holding the button cancels
that gesture, including moving away and back. Once you release the button,
moving the pointer confirms the completed click once it crosses the
tolerance. Handlers receive the
saved release position. Stopping a project clears its pending gestures.

Being ordinary chain participants, pointer hooks **consume on a truthy
return** like keyboard ones: return truthy and a shown input widget does not see
the event. Return nothing and it carries on to the input widget, which is what
you want while an input widget is shown for its own reasons.

Pointer events take shortcuts too, and the vocabulary is the same one: the
button is the trigger, written `mouse1` (left), `mouse2` (right), `mouse3`
(middle).

```lua
compy.input.shortcuts.mousepressed['mouse2'] = function(x, y)
  open_context_menu(x, y)
  return true
end
compy.input.shortcuts.mousepressed['ctrl+mouse1'] = function(x, y)
  add_to_selection(x, y)
  return true
end
```

`mousepressed` and `mousereleased` name a button. The channels that have no
discrete trigger — `mousemoved`, `wheelmoved`, the touch events, and the
derived clicks — take modifier classes only, so `shortcuts.mousemoved['ctrl+*']`
is a ctrl-drag and an unmodified move goes straight to the hook.

### Held keys

There are three ways to find out that a key is held, and they are **not
equal alternatives** — the further down this list you go, the more likely it
is that the logic wanted to be a binding and became a hardware question
instead.

**1. Register a combo — the mechanism, and the first thing to reach for.** To
react to a *modified event* — a click with Ctrl, `Shift+Enter`, `alt+p` —
register a shortcut and let the framework match it:
`shortcuts.keypressed['ctrl+s']`. That says it once, as data, in a vocabulary
that is already folded and already the same on every channel. Asking about
modifiers imperatively inside a handler turns into a cascade repeated at every
call site. When a binding and a held key have to work together, see
"Choosing the mechanism" below.

**2. Ask `Key` — allowed, and worth a second look.** `Key` is available to
every project, like `compy`. `Key.shift()`, `Key.ctrl()` and `Key.alt()`
answer whether that modifier is held right now, either side:

```lua
function love.draw()
  draw_keycaps(Key.shift())
end
```

Each folds its own left/right pair, so you never name `lshift` and `rshift`
yourself — the same folding a combo string does. Nothing is wrong with these
calls, but a project that reaches for them repeatedly is usually describing a
binding it has not written yet; that is the cascade combos exist to replace.

**3. Ask `Key.any_pressed` — for a key that is not a modifier.** It takes any
number of key names and answers about the device as it is right now, for
**any** key:

```lua
function love.draw()
  draw_keycap('space', Key.any_pressed('space'))
end
```

This is the rung to use when the folded accessors have no answer — an
ordinary key, which is what drawing a keyboard and lighting its pressed caps
needs. Names are LÖVE's own, so left and right modifiers are two separate
keys here and you name both when either will do — `Key.any_pressed('lshift',
'rshift')` is what `Key.shift()` already says. **Several names mean *any* of
them**, exactly like the device call it wraps. Prefer the folded accessors
whenever the question is about a modifier, and reach here when it is not.

`love.keyboard.isDown` still works and is what this calls; using `Key` for
both kinds of question just keeps one surface in your code instead of two
spellings of the same question in one expression.

Every rung works anywhere: in a handler, and in `love.draw`, which is the
point — a project that *draws* held state has no event argument to consult.
Handlers need nothing added to their arguments for it, and get nothing added:
every shortcut, hook and widget call receives LÖVE's own argument list.

### Choosing the mechanism: transitions, state, and what not to build

The API offers three ways to reach input, and they answer different questions.
Choosing by question rather than by taste is what keeps a project predictable.

**A shortcut or hook is for a one-off transition of your own state** — start the game,
end it, switch mode, show the widget. It is an *independent* change that stands
on its own once made. Its purpose is decomposition: one binding per thing,
listable as data, instead of one hook demultiplexing a dozen combos by hand.

**Polling of pressed keys is for continuous state** — is the paddle key down, is Ctrl held
while this drag happens, which caps to light while drawing. Ask `Key` at the
moment you need the answer. This is not a lesser rung: the device is
self-correcting, and asking it costs nothing but the call.

**Do NOT 'pair' shortcuts on different channels to toggle state.** Setting a flag on
`keypressed` and clearing it on `keyreleased` for the same combo looks tidy... *and
is not reliable*, because the closing event is not guaranteed to arrive in the
shape the opening one expects:

```lua
-- DON'T: the flag can outlive the key.
compy.input.shortcuts.keypressed['alt+h']  = fn.side_run(function() peek = true end)
compy.input.shortcuts.keyreleased['alt+h'] = fn.side_run(function() peek = false end)
```

Release Alt before `H` and the second event serialises as plain `'h'`, so the
clearing binding never runs and `peek` stays true. Hold an unrelated modifier
while releasing and a bare `'space'` binding misses the same way. Lose the
window to a notification and no release arrives at all. **A modifier's own
release cannot even be bound**, so for some chords the closing half is not
writable.

Ask instead, at the moment the answer matters:

```lua
-- DO: a question with no state to go stale.
local function peeking()
  return Key.any_pressed('h') and Key.alt() and not Key.ctrl()
end

compy.input.hooks.mousemoved = function(x, y)
  if Key.shift() then paint(x, y) end
end
```

Reacting on `keyreleased` is still a fine *choice* — it is a natural fit for
"act once when the key comes up", and it sidesteps key repeat without any
filtering. What it must not be is the closing half of a mirrored pair. (For
"act once on press", `fn.ignore_repeat` does the same job on the press
channel.)

**Do not rebuild "what is held" from the event stream.** Keeping your own table
of keys currently down — or a boolean mirroring one key — is virtual state with
no path back to the truth: a release lost to focus change or a hiccup leaves it
lying, and nothing corrects it afterwards. If your project has a reason to do
it anyway, make that an explicit decision taken in awareness of the drift, not
a default. The framework does not maintain such a table, and deliberately so.

**Perform hardware polling before complex processing.** When logic gets complicated, read the keyboard
early — at the top of the handler or `update` — into names that mean something
in your game, then let the rest of the logic run on those:

```lua
local fast   = Key.shift()          -- one place asks the hardware
local precise = Key.ctrl()

move(fast, precise)                  -- everything below is deterministic
```

It keeps the non-deterministic part visible in one place instead of scattered
through code that is otherwise a pure function of your own state.

### Worked example: the trigger key echoes into the widget it showed

Not a recommended shape — a **worked example of an awkward case**, and of how
the pieces above combine to solve one. Most projects show the widget from a
modified combo, where nothing below arises.

Bind a bare character key to show the widget and it appears with that
character already in it. LÖVE delivers a `keypressed` **and** a
`textinput` for one physical key and does not promise their order, so the
trigger's own echo arrives on the other channel, either side of the `show`. The
`is_shown()` guard does not help: it is about the *next* press, not this one.

Guard the trigger with a one-time shortcut on the `textinput` channel.
Shortcuts run before the input widget, so it swallows the echo whichever side of
the `show` it lands on, and it unregisters itself so the character is typable
as content afterwards:

```lua
local function arm_echo_guard()
  compy.input.shortcuts.textinput['i'] = function()
    compy.input.shortcuts.textinput['i'] = nil
    return true -- the echo is consumed, not typed
  end
end
arm_echo_guard()

-- the next show needs a fresh guard, however the widget was hidden
compy.input.callbacks.after_submit = arm_echo_guard
```

**Re-arming** is registering that guard again, and it is needed wherever the
input widget is hidden: one hidden without a fresh guard takes the echo on its
next `show`. That is your own `hide()` call **or `hide_on_submit` hiding it for
you** — the hide runs before `after_submit`, so a guard armed there is armed
for the next opening either way. If you also ask Escape to hide the widget
(`hide_on_cancel`), the same line covers that path.

Use a **bare** key as the trigger. A modified combo cannot be guarded this
way: the two channels do not share a combo string for it — `shift+i` on
`keypressed` against `shift+I` on `textinput` — and the upper-case form
cannot be registered.

## Stop hook — `compy.before_exit`

A settable slot on `compy` itself, not on `compy.input`: it is a
project-*run* lifecycle hook, not an input-channel callback. It exists so a
project can put back global device state it changed imperatively — the
sandbox clones the `love` table but shares the underlying C functions, so
calls like `love.keyboard.setKeyRepeat(false)` change real state that
outlives the run.

```lua
love.keyboard.setKeyRepeat(false)

compy.before_exit = function()
  love.keyboard.setKeyRepeat(true)
end
```

- **Signature:** no arguments — the project knows its own state.
- **Return value:** ignored. It cannot suppress or defer the stop.
- **Timing:** runs *before* the framework's own teardown, so `love.*` calls
  inside it are still safe.
- **Fires on:** every framework-invoked stop of a running project —
  `Ctrl+Esc`, quitting the project, switching away to the editor, and app
  shutdown in play mode.
- **Does NOT fire when the project's own code raises.** A raise in top-level
  code ends the run without a stop, and a raise inside a handler suspends it
  instead; neither is a stop path. Do not rely on this hook to undo something
  a crash could leave behind — see
  [technical debt](development/technical_debt/input.md), "A project that
  raises leaves global device state dirty".
- **Reset:** back to the default no-op once the run ends, by whichever path
  it ended — so one project's hook never fires for the next one. Like every
  other project participant, it does not survive the run that installed it.
- **Default:** a no-op that logs in debug mode.

## Migration from the legacy globals

The retired polling globals have no replacement compatibility layer. Move
their work into a callback:

| Old shape | Replacement |
|---|---|
| `user_input()` plus a per-frame poll of the handle it returned | `on_text_entered = function(text) ... end`. **There is no handle now** — nothing is returned to poll, and the text arrives as the callback's argument. |
| `input_text(prompt, text)` | `show{ prompt = prompt, text = text, on_text_entered = fn }` |
| `input_code(prompt, text)` | `show{ prompt = prompt, text = text, highlighter = LuaHighlighter, validator = LuaSyntaxValidator, on_text_entered = fn }` |
| `validated_input(filters, prompt)` | `show{ prompt = prompt, validator = LineValidators(filters), on_text_entered = fn }` |
| `write_to_input(text)` | `compy.input.set_text(text)` |
| `function compy.singleclick(x, y)` | `compy.input.hooks.singleclick = function(x, y) ... end` |
| `function compy.doubleclick(x, y)` | `compy.input.hooks.doubleclick = function(x, y) ... end` |

The old evaluator globals — `InputEvalText`, `InputEvalLua`,
`ValidatedTextEval`, `LuaEditorEval` — are **not in your environment**. They
used to be visible there by accident, never as API; they are withheld now. Use
`LuaHighlighter`, `LuaSyntaxValidator` and `LineValidators`, which are exported
and go in the `highlighter` and `validator` keys.

## Proposed updates/changes

> [!NOTE]
> All proposals below have been evaluated and incorporated into the shipping API (or resolved with ratified decisions). This section is retained for proposal tracking and historical context until final PR assembly (`PR-01-06`).

### @dsent DevX amendments

Rationale comes from the usage survey of upstream's examples, the IDE's console and editor, and our games (`maze`, `balloons`, `sapper`). Synchronous input is a separate product proposal: `sync-input-proposal.md`.

#### 1. Add `compy.input.get_text()` **(Status: BUILT)**

- Change: export the widget's content getter, returning a string; works while hidden.
- Why: `love.draw` has no event to consult, and the 64-character cap needs the length while typing. With item 2 the callbacks see the draft as their argument; the getter covers everything outside them.

remark: de-facto implemented (see above), exported as `compy.input.get_text()`.

#### 2. One payload shape: the string **(Status: BUILT)**

- Change: every callback that can see content receives the same string. `on_text_entered(text)`, `after_submit(text)`, `before_submit(text)`, `before_cancel(text)`, `after_cancel(text)`. `validator(lines)` and `highlighter(lines)` keep lines.
- Why: every program-facing consumer wants a string; only positional plumbing wants lines. Today two callbacks are told apart by payload shape, and `lines[1]` on a string fails silently. A callback that ignores the argument loses nothing, and a veto can look at the draft.

remark: built (`D-ONE-PAYLOAD`), all five content callbacks receive the unified string.

#### 3. Submit clears the field by default **(Status: BUILT)**

- Change: after a successful submit the field is empty. `auto_clear = false`, a persistent key like `auto_hide`, keeps the text.
- Why: five of seven real prompts clear after submit and each writes the same `after_submit`. The two that keep text, `tixy` and the maze, already hold it themselves.

remark: built (`D-LIFECYCLE-FLAGS`), `clear_on_submit = true` by default.

#### 4. Escape hides, and does not clear **(Status: RESOLVED)**

- Change: cancel takes the widget down and leaves the content. `before_cancel` veto and `after_cancel` stay. The always-shown console and editor widgets keep their own Escape.
- Why: Escape is "get back from whatever is active". Clearing on Escape is the P1 data-loss hazard, reachable from the right mouse button.

remark: resolved on least-destructive basis (`D-LIFECYCLE-FLAGS` statement 3) — Escape is opt-in, defaulting to no-op (`hide_on_cancel = false`, `clear_on_cancel = false`).

#### 5. `show{...}` is a new question; `show()` brings the field back **(Status: BUILT)**

- Change: a `show` with a table starts from its `text` or empty. A bare `show()` re-shows the field as it was left. Settings persist as today.
- Why: unrelated prompts in one program must not inherit a stale draft; a re-show after `auto_hide` must. The distinction needs no new verb.

remark: built — `show{text=...}` applies given text or `text=''` empty; bare `show()` preserves content.

remarks from discussion:
- soft objections: semantically inobvious behaviour difference (show() vs show({}) would be hard to comprehend; its not clear whether case frequency justifies optimizing API for it)
- alternative: bind auto-clear on hide, and see if `(auto_clear x auto_hide)` covers required scenarios and if better names for these flags could be figured out
- alternative 2, currently suggested by docs: `get_text` before hide + save and reset content in external variable

### @nagydani - simplified minimalistic set **(Status: BUILT)**

Here's how I see the desired input API. It is asynchronous, but extremely simple, with one function and two callbacks:

One callback, something like compy.input(text) is called when text is entered (i.e. Enter pressed), with the argument containing the actual text.
The other callback, something like compy.inputControl(key) is called when some control key is pressed, when editing.
The function is something like compy.ask(prompt, highlighter, initialText, cursorPosition) where prompt defaults to "text", highlighter defaults to everything being black (highlighters for Lua syntax, numbers, etc. should be provided), initialText defaults to empty string, cursorPosition defaults to 0.

When any of the callbacks are called, the input is removed from the screen. If editing should be continued for whatever reason, compy.ask should be called again from that callback.

#### resolution

In the live discussion it was agreed to expose current (aka 'low-level' API) and suggested simple surface altogether under same compy.input namespace. Projects can use what they need. 
Details to be figured out.

remark: built as simple surface (`D-SIMPLE-SURFACE`) — `compy.ask`, `compy.on_answer`, `compy.on_key`, `compy.unask`.

## See also

- [User Input — Implementation Overview](development/internals/user_input.md)
