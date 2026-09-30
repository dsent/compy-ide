---
description: The why behind Compy keyboard/text input routing and the project-facing input widget — the ratified decisions
status: active
audience: developer
authored: llm
reviewed: none
---

# Input subsystem — architecture & key decisions

The *why* behind Compy's keyboard/text input routing and the project-facing input widget.
For how it works under the hood — the exact dispatch order, the mechanism behind each
guarantee, file-by-file wiring — see [`../internals/user_input.md`](../internals/user_input.md).
For the project-author usage guide — the `show()` config table, worked examples — see
[`../../input_api.md`](../../input_api.md). This doc records the decisions those two describe;
it does not restate their mechanism.

The surface these decisions describe ships as **1.0.0-rc20260712**; "the input API" below
always means that surface.

The subsystem replaced an older input API that was polling-based and routed by widget
presence. Understanding what it was chosen *over* is most of the rationale, so the contrast
appears throughout.

---

## Vocabulary — hook, callback, handler

Three words name assignable functions in this subsystem; they are kept distinct on purpose.

- **hook** — a function keyed by a **LÖVE event name** (`hooks[event]`: `keypressed`,
  `textinput`, `keyreleased`). The namespace is **closed and externally defined**: it can only
  ever hold names LÖVE itself emits. You never invent a hook name.
- **callback** — a function keyed by a **Compy-chosen name** (`callbacks.on_text_entered`,
  `validator`, `highlighter`, `on_limit_reached`). The namespace is **open and Compy-defined**:
  the names are ours to extend, and none of them is a LÖVE event.

Both are mount points for a function, so it is tempting to collapse them into one concept. We
do **not** — the split records *which authority owns the name*. A closed, LÖVE-dictated event
set and an open, self-authored callback set are different contracts even where the assignment
mechanics coincide; merging the vocabularies would erase that boundary just where a reader most
needs it.

- **handler** — exactly what LÖVE means by it: the function occupying `love.<event>`, and the
  `love.handlers[name]` entry that dispatches to it. Compy adds no second sense; where this doc
  says "handler" it is always the runtime one.

**Where that trips people up.** A project writing `love.textinput = f` believes it is installing
a handler. It is not. While the project runs, the route owns `love.textinput`, and the project's
function is captured and seeded as `hooks.textinput` (D-HOOKS-SEEDED) — it runs in hook position,
with hook semantics (truthy consumes). Writing `compy.input.hooks.textinput = f` says the same
thing plainly, and is the encouraged form.

**Pointer events used to be the exception; they no longer are** (D-ONE-LIFETIME). A project's
`love.mousepressed` and friends are seeded and run in hook position exactly like the keyboard
ones, so the paragraph above applies unchanged to every channel. The hook namespace is still
closed and externally defined, with one qualification: it also holds the two events the framework
*derives* rather than receives — `singleclick` and `doubleclick`. LÖVE does not emit those; the
click timer synthesises them and emits them through the gateway, so they are hooks by the same
rule that governs the rest.

---

## The problem this shape solves

The previous input API had three structural faults that projects tripped over:

- **Polling, not events.** A project called `input_text()` / `input_code()` /
  `validated_input()` / `user_input()`, then re-checked a reference variable on every update
  tick to notice a submission. There was no way to be *told* when the user submitted.
- **Keyboard lockout during input.** While the widget was on screen, the project's own
  `love.keypressed` / `love.textinput` handlers were not called at all — routing was gated on
  widget presence, so a shown widget swallowed the project's key events wholesale. Reacting to
  a hotkey *while* soliciting text was impossible.
- **No show/hide without teardown.** The widget could not be hidden and brought back at all:
  dismissing it meant tearing it down, and asking again meant building a new one.

The design goal was an event-driven input surface consistent with LÖVE's own callback style,
expressive enough that the console REPL and the editor input strip *could* be rebuilt on it,
while keeping the simple case simple — a student shows the widget and gets the result through
one callback, with no framework internals in view.

---

## ACTIVE

Decisions currently in force — the rules the shipped system is built to and the ones a change
must be checked against. An amendment narrows, corrects, or partially supersedes an earlier
entry without retiring it, so the amended entry stays here alongside the amendment that reshaped
it; only a decision superseded in full, or one struck outright as never having been a decision,
moves to RETIRED below.

## D-ROUTE-OWNS — routing is route-centric, not widget-centric

**Decision.** The application mode selects **exactly one active route** — console, editor, or
project — and every keyboard/text event is dispatched to that one route. A widget never
selects the route. Widget visibility is *state on the widget*, never a routing condition.

**Why.** The old model routed by asking "is a widget shown?" at the gateway, which is what
produced the keyboard lockout above: the widget's mere presence diverted events away from the
project. Making the *mode* the sole routing authority means showing or hiding the widget is a
state change with no routing consequence — the project route stays connected and keeps
receiving key events whether or not its widget is shown. This is the single structural change the
whole subsystem hangs off of: the widget gate is gone.

**Consequence.** The three routes are siblings. Today the editor is still reached through the
console route's internal fork rather than as a fully independent third sibling; converging the
console and editor onto the same chain the project route already uses is deliberately left as a
follow-on, not attempted in the pass that introduced this model. The project route is the
proving ground for the shape.

## D-CHAIN-OF-3 — a three-component chain with truthy-consume

**Decision.** Inside the active route, every keyboard/text event runs one chain of three
components, in order:

1. **`shortcuts[event][combo]`** — per-combo functions the project registered (D-COMBO-TABLES's
   per-event keying and canonical-combo normalisation apply unchanged).
2. **`hooks[event]`** — one per-event hook, absorbing both the old per-event generic
   callback and the legacy project `love.*` handler seeding path into one hook (D-HOOKS-SEEDED).
   **The one named exception to truthy-consume lives here** (2026-09-08): a hook *seeded* from a
   project's own `love.*` handler consumes unconditionally, because its author wrote it under LÖVE's
   convention and never chose a return value. A hook the project registered itself follows the rule
   above. See D-HOOKS-SEEDED, *"a seeded handler consumes"*.
3. **the widget** — terminal. Its *shownness*, not its return value, decides whether it
   consumed the event: shown → the widget runs and the chain reports consumed; hidden → the
   widget is skipped and the chain reports not-consumed. **The chain makes that call, not the
   widget** — see *"why the widget cannot answer for itself"* below.

A **truthy return at any component consumes** the event: it travels no further, the widget
included. A falsey return falls through. The same three-component shape runs on **every**
channel — the keyboard trio (`keypressed`, `textinput`, `keyreleased`) and the pointer
channels alike, which reach it through the same dispatch with a combo vocabulary of their own
(D-ONE-LIFETIME and D-BUTTON-TRIGGER); a component with no participant simply falls through.

**Three components, and no fourth.** Nothing above the chain claims Enter or Escape: their
default behaviour is the widget's own (D-EDIT-LIFECYCLE), and the gateway's power keys sit outside
this chain entirely. So a project shortcut registered on Enter or Escape wins exactly as it
does on any other combo, and the DOM-style "handled stops propagation" convention below
applies without a carve-out.

**Why.** One uniform shape on every channel is the predictability meta-rule made concrete:
nothing "special" gets its own routing rule; a released key and a typed character travel the
same path a pressed key does. The truthy-consume convention is the familiar DOM-style
"handled-stops-propagation" that projects already understand. A tier that special-cased
exactly two keys (Enter, Escape) would be a rule to remember at every reading;
removing it doesn't lose capability — it removes a component that was purpose-built for a job the
widget can now do itself, uniformly, like any other chain participant.

**Recognized external constraint — no cross-channel ordering guarantee (an inherited
platform fact, not a decision of this subsystem's).** LÖVE/SDL documents *no* ordering
between the `keypressed` and `textinput` channels for a single keystroke. Upstream code
assumes `keypressed` arrives first, and on desktop SDL it usually does — but that order is an
accident of one backend's implementation, documented nowhere and promised by no one, and **the
target device has been observed delivering the reverse.** It matters here because code written
against the usual order is relying on a guarantee that does not exist. The independent-channel shape above is what makes that a
non-issue rather than a hazard: a project judges typed text on the `textinput` channel (in
`on_text_entered`), never by gating a glyph on a `keypressed` flag, so the design is
order-*independent* — strictly safer than depending on an order the platform never promised.
The corollary for tests is binding: a spec must **not** bake a canonical
`keypressed`→`textinput` order in as an invariant, or a synchronous harness goes green while
the device fails.

**Why the widget cannot answer for itself, and the chain answers for it.** The other two
components are **passthrough filters**: a shortcut or a hook runs, and its return value *is* its
answer — handled, or fall through. **The widget is not that.** It is a stateful machine whose
outcomes are reported **asynchronously, through its callbacks** (`on_text_entered`,
`on_limit_reached`, and the rest — D-EDIT-CALLBACKS), not through the call that fed it a key. There
is no moment at which it could return "I consumed this", because its actual answer arrives later
and by a different route.

**So the widget is never partly involved: it either swallows the event or is not in the walk at
all** — and **the dispatching layer decides which**, on the one piece of state that settles it.
`projectInputController.lua`'s `dispatch` tests `is_shown()` and returns `true`/`false` on the
widget's behalf; the widget's own return is discarded and means nothing to the chain.

*(The widget also carries an internal `if not self.shown then …` no-op, which mutates nothing and
only debug-logs. It is **not** what the chain reads — but it is load-bearing on the **console**
route, which calls `input:keypressed(k)` unconditionally rather than through this chain. Both
checks exist, they answer to different callers, and the earlier claim that only the internal one
existed was wrong about this route.)*

**The chain's own return is defined and returned even though nothing reads it today.** The gateway
calls the route occupant and discards the answer. It is kept because a walk that reports whether it
consumed is a **coherent interface**, and because it leaves input chains stackable or nestable if
that is ever wanted — **at exactly zero cost**. To be explicit, since the strategic frame asks:
this is **not** generic machinery built for a speculative need. Nothing is abstracted, no hook is
added, no shape is generalised. A boolean that already had to be computed is returned instead of
dropped.

Widget visibility still carries **no routing weight** (D-ROUTE-OWNS): what `is_shown()` selects is
whether the last component of an already-chosen route's chain participates, never which route the
event reaches.

**Consequence.** Dispatch is a short-circuit walk — the first truthy return wins — written as
three guarded `if`s rather than as `shortcuts(...) or hooks(...) or widget(...)`
(`projectInputController.lua`, `dispatch`). Every tier is sparse: an unregistered shortcut or
hook is **absent**, not a no-op, and plumbing no-op defaults through the tables to buy the
one-line form was declined. So each tier is tested for presence before it is called, and the
widget's own test is `is_shown()`.

## D-WIDGET-AT-BOOT — a boot-provisioned widget per surface, not per-session construction

**AMENDED IN PART, 2026-08-27.** The **project** widget is created per project **run**, not at
load. Everything else stands: the console's, the editor's and the search strip's widgets are still
boot-provisioned, and within a run `show()`/`hide()` are still state flips on one instance, never
construction and teardown. The NFR below is not withdrawn — it is applied at the boundary it
actually names.

**AMENDED, 2026-09-09 — the three host surfaces refuse to hide, and that refusal is ratified
here.** `UserInputController:always_shown()` marks the console line and the editor's input and
search strips at construction. It does two things: `shown = true`, which those surfaces need
because they start visible without a `show()` call, and `always = true`, which makes `hide()`
return without effect. **The owner ruled the guarantee KEPT**, reversing the 2026-09-06 ruling that
would have deleted it: *"we keep `always_shown` guarantee exactly because pre-feature there was no
chance that persistent widgets will receive stray `hide()` (or any `hide()`) … and now we need
explicit guard in persistent widgets that blocks hiding."*

**The reason is a comparison with the base, not a defence against a caller that exists.**
Pre-feature there was no shownness at all — a widget was live iff `love.state.user_input` was set —
and nothing could take a host surface down because no `hide()` existed to call. This API introduced
both the call and the flag, so an impossibility that used to be structural has to be re-stated as
code. **That the guard refuses nobody today is the point rather than an objection to it:** it is
what keeps that route from opening, and a flag anything may clear is a convention, not the
guarantee the name claims.

**Walked 2026-09-09, so the guarantee is a fact about the tree and not about one file.** `hide()`
is the only writer of `shown = false` (`grep -n "shown *=" src/controller/*.lua`), and the two
sites that clear `love.state.user_input` without it — the shutdown path in `controller.lua` and
`consoleController.lua`'s `hide_input_widget` fallback, which runs only when there is no project
widget — cannot reach a host surface's flag. Host surfaces never occupy that handle either: only
`show()`/`open_widget` writes it, and they are marked at construction instead. Pinned by
`tests/input/input_widget_control_spec.lua`, *"an always-shown widget refuses to hide"*, with an
ordinary widget hiding normally beside it as the control.

**Decision (as amended).** A surface's input widget is created **once per lifetime of the surface
it serves** and reused across every session on it. For the console, the editor and the search strip
that lifetime is the application, so those three are boot-provisioned. For a project it is the
**project run**: the widget is constructed when the run starts and destroyed when it stops.
Projects reach it through the `compy.input.*` surface and never hold the widget object; `show()` /
`hide()` are state flips on that instance, not construction and teardown.

**Why.** A non-functional requirement forbids allocating a fresh object graph **per input
session** — the device is memory-constrained and the common pattern is repeated prompting.
Repeated prompting happens *within* a run, so a per-run widget satisfies that requirement in full:
a project that prompts a hundred times allocates once. The requirement was previously applied one
boundary wider than it states, and that wider boundary was never examined. A shared-within-the-run
instance also gives hiding the widget without tearing it down, and showing it again — for nothing: the widget and
everything the project set on it are not destroyed while the project that owns it is alive, and it
is what makes D-ROUTE-OWNS cheap.

**What comes back is the widget, the project's settings — and, since 2026-09-07, the user's text
too.** `hide()` has always preserved the content: it flips `shown` and clears
`love.state.user_input`, nothing more. What used to discard it was the **next `show()`**, and
D-CFG-BOUNDARY statement 1 no longer does that — activation carries no implicit destruction, so a
bare `show()` after a `hide()` reopens on what was there. The case that pinned the old rule
(*"a fresh activation with no text is empty"*) migrated with the amendment on 2026-09-09 and is
now *"a bare re-activation keeps the content"*. **The paragraph's own
point is unchanged and is the reason it is kept:** this decision buys hiding *without removing*,
which is about **teardown** — it was never a promise about the user's text either way, and it is not
one now.

**Per-run is strictly less allocation than the system this feature replaced.** At the PR base the
project's widget was built **per activation** — model, controller and view, fresh on every
`input_text` / `input_code` call. The application-lifetime singleton is this feature's own
invention, not inherited behaviour, and it shipped on the same memory-constrained device without
complaint while doing considerably more allocation than a per-run widget does.

**What it buys.** A store that belongs to a project now *dies with that project*, structurally,
rather than by a hand-maintained wipe list at teardown. Two cross-project leaks were fixed by
extending that list, and a third had been missing from it for months.

**Consequence.** Four instances exist, not one, and what they share is the widget **code**, not
the object: the project's (created at the run seam), the console's REPL line
(`consoleController.lua`), and the editor's input and search strips (`editorController.lua`). What differs between them is the
evaluator attached, the capability flags set at construction, and which route handles the
result — never the widget's own behaviour. `show()` on an already-active session is a no-op (it *warns*
rather than swallowing — see D-FROZEN-SHELL's discipline) unless `{force = true}` is passed.

## D-NO-POLLING — callbacks replace polling

**Decision.** Nothing is polled, in either direction. **Inbound** device events reach a
project through its **hooks and shortcuts**; what the **widget reports back** — submission
above all — reaches it through its **callbacks**. Neither direction is ever read from a
polled reference. *(The two are different classes and this decision covers both: a submission
is not an input event arriving, it is a result leaving. `D-EDIT-CALLBACKS` and `D-EDIT-LIFECYCLE`
draw that line between them — content and lifecycle respectively.)* The legacy text-input globals and the
reference-variable idiom they fed are **removed outright** — no shim, no compatibility flag.

**Why.** Polling is inconsistent with LÖVE's event-driven style and forced every project into a
per-frame re-check. Callbacks eliminate the poll, and — combined with D-ROUTE-OWNS — eliminate the
keyboard lockout that made polling-plus-hotkeys impossible in the first place. The clean break
(rather than wrapping the old functions) was a deliberate stakeholder call: this is pre-1.0, the
full set of callers is known and small, the examples exist to demonstrate good code, and a
legacy shim left in a release would teach the pattern the feature exists to retire. The break is
bounded to text fields; the project's keyboard handling keeps working (D-HOOKS-SEEDED).

**Consequence.** The old globals (`input_text`, `input_code`, `validated_input`, `user_input`,
`write_to_input`) are gone from the project environment as ordinary `nil` fields. Their examples
migrate to `compy.input.*`; the replacement mapping is documented in the usage guide.

## D-EDIT-CALLBACKS — the widget talks about the content being edited through callbacks

*(`EDIT` in this id and in `D-EDIT-LIFECYCLE` is the input widget's **content editing**, not the
code editor of `internals/editor.md` — the two meet in this file, where `editor` means the latter.)*

**Decision.** Everything the widget has to say about **the content being edited** travels through
a fixed set of four callbacks:

- `on_text_entered(lines)` — fires at submit, with assembled line strings. **Amended twice: by
  D-PAYLOAD-SPLIT (2026-08-30), which made this payload the joined string and gave `after_submit`
  the line list; then by D-ONE-PAYLOAD (2026-09-09), which retired that split — `after_submit`
  receives the same string, and the three guard callbacks receive it too.**
- `on_limit_reached(direction, scope)` — fires when the cursor tries to move past a boundary
  (`direction` up/down/left/right; `scope` whole-input or current-line).
- `validator(lines)` — gates submit.
- `highlighter(lines)` — display-only.

These are set at `show()` / `configure()`, or assigned as `compy.input.callbacks` fields — one
underlying callback, two ergonomics. **The widget's *lifecycle* callbacks are a different set with
its own decision behind it** (D-EDIT-LIFECYCLE), and they are assignment-only.

**Why callbacks at all is not this decision's question.** D-CHAIN-OF-3 settles it, under *"why the
widget cannot answer for itself"*: the widget is a state machine whose answer is produced by a run
of interactions rather than by the event in hand, so there is no call to return it from. One
consequence carries over and is worth stating here, because a retired metaphor keeps reappearing:
these are **not a "half" of the dispatch chain**. That chain is synchronous and linear — one event,
one walk, one answer — and an outcome has no position in its walk at all.

**What this decision settles is which four, and why exactly these.** They are the questions a
project asks when it solicits input, in the order it meets them: *what did the user type* — what
the whole exercise is for; *is it acceptable* — because rejecting bad input is the second thing
every prompting project needs; *how should it look while it is typed*; and *has the cursor run out
of room*, which is what a project needs to page a history or a list under the widget. **Nothing
here is speculative surface**: each answers a use case common enough that a project lacking the
callback would have to reconstruct it, and there is one callback per state transition that means
something outside the widget — not one per event, and not one per key.

**No return-value channel, and this is the concrete form of it.**
`UserInputController:keypressed` returns **nothing**: the old limit flag it used to thread out
(`local limit = input:keypressed(k)`) is retired, and `on_limit_reached` is the sole notification
path for every consumer, the console included. A domain result riding a keypress return is the
shape this decision exists to remove.

**Horizontal boundaries were added to it**, so `on_limit_reached` now fires on left/right as well
as up/down and carries a `scope`. That is a **capability the widget did not have** — the four
directions and the two scopes are what makes the callback usable for horizontal paging, not a
symmetry kept for its own sake.

**Consequence.** A project gets soliciting input working with nothing but
`show{ ...callbacks... }` — no chain knowledge required. Console's history navigation
(Page-equivalent Up/Down at a boundary) is wired through its own instance's `on_limit_reached`,
filtered to the vertical direction; editor's search widget is a different class with its own,
unrelated return contract and is untouched (a discovered, pinned behaviour; see D-DEFACTO-KEPT).


## D-EDIT-LIFECYCLE — submit and cancel are widget-owned callback-driven flows, not a framework tier

*(`EDIT` here is the input widget's content editing, not `internals/editor.md`'s editor — this
entry's own body names both.)*

**Decision.** Enter and Escape are ordinary chain participants (D-CHAIN-OF-3), not a framework
tier. The widget provides their *default* behaviour as callback-driven flows of its own, not
framework-owned ones:

```
submit_flow:  before_submit() → validator → [flags] → on_text_entered → after_submit()
cancel_flow:  before_cancel() →             [flags] →                   after_cancel()
```

*(`[flags]` is D-LIFECYCLE-FLAGS' per-instance clear and hide, implemented 2026-09-09. Until then
cancel's clear was **hardwired** at that position, which is why an unconfigured widget was not
inert; the flags are what made this entry's own "stay open unless asked" true of every instance.)*

**The four lifecycle callbacks are this entry's set** — `before_submit`, `after_submit`,
`before_cancel`, `after_cancel` — and they are **assignment-only**: `compy.input.callbacks` is
their home, and a config table naming one raises and says so. The **content** callbacks the flows
run past on the way (`validator`, `on_text_entered`) belong to D-EDIT-CALLBACKS and are settable
both ways. The split follows the use: a project names content callbacks at the moment it asks a
question, and sets lifecycle callbacks structurally, once.

**They are the two moments a project can want around a finalization**: before, to decide whether it
happens at all, and after, to do whatever comes next. Two flows, two moments each — that is where
the number four comes from, and there is no third moment because the step in between is the
widget's own.

Three substantive changes, and they are what this entry is for:

- **Either `before_` callback may veto, and a veto skips the WHOLE flow** — both flags and the
  trailing `after_` with them, not only the step in the middle. That is what the code has always
  done (`cancel_flow` returns on a truthy `before_cancel`); the earlier wording here, *"skips the
  step it guards"*, read as though `after_cancel` still ran, and it never did.
- **Auto-close defaults to OFF.** `after_submit`/`after_cancel` are no-ops, so the widget stays
  open unless a project asks otherwise. The old one-shot mechanism is not restored by a keep-open
  flag with its polarity flipped; **a project that wants "ask once, then hide" sets
  `hide_on_submit`** (D-LIFECYCLE-FLAGS, implemented 2026-09-09), which is that request written as
  a mode rather than as a hook kept for its side effect.
- **Enter and Escape are shadowable.** A project shortcut on `'return'` or `'escape'` wins over
  the widget's default, like any other combo.

**Withdrawn guarantee — recorded explicitly, not left implicit.** Nothing prevents a project from
shadowing submit or cancel while the widget is shown, and one that overrides
`after_submit`/`after_cancel` owns the lifecycle act itself. No stakeholder requirement asked for
the old guarantee — cancel/dismiss notification was left *"may be expected — to be confirmed"* and
never confirmed — and it was never the safety net either: the gateway's power keys (`RESERVED`,
`controller.lua`, pre-dating this feature) run before any route and cannot be shadowed by a
project, a chain participant or a widget. That is the permanent escape hatch, and it answers
exactly the chords it names (D-EXACT-RESERVE) — non-overridable, not indiscriminate.

**One path for every instance.** `UserInputController:keypressed` never branches on
`love.state.app_state`. A context that must not run the flows arranges it at its own layer: the
editor consumes Enter/Escape upstream through `block_input()` and **seats no lifecycle flags, so
what does reach its widget does nothing**; the console seats `clear_on_cancel` and no callbacks, so
its Escape clears and its submit is the console's own evaluation path; and the project widget seats
the two the release ships. Per-instance capability flags (`disable_selection`,
`allow_duplicate_line`) work the same way — the owner enables them at construction; the widget never
reads a mode. *(This paragraph read "the console sets no lifecycle callbacks so its flows are
no-ops" until 2026-09-09. It was false while the clear was hardwired, and it is still not what the
console is: it sets no callbacks and does seat a flag.)* Branching inside the widget instead would leave a
reusable component that cannot be reasoned about, or migrated, without knowing it is "the editor",
which is the leak a framework tier was covering for in the first place.

**Consequence.** Deactivate-on-submit is per-*instance* configuration rather than route policy, so
console and editor inherit "stay open" for free and a future editor migration (D-ROUTE-OWNS) extends
an existing seam. `hide()` fires **no** cancel flow — cancel is the user-facing Escape path only.

## D-FROZEN-SHELL — freeze the container and its sub-table identities; leaves are writable

**Decision.** `compy.input` itself, and the *identity* of each of its three sub-tables
(`shortcuts`, `hooks`, `callbacks`), are frozen — a project cannot do
`compy.input.shortcuts = {}` or replace the container. Every **leaf** inside those sub-tables is
freely writable: `shortcuts[event][combo] = fn`, `hooks[event] = fn`, `callbacks[name] = fn`.
Everything else — `show`, `hide`, `configure`, `clear`, the cursor/text calls — is callable API
that **errors loudly on assignment**.

`callbacks` carries **eight** members — the four **content** callbacks (`on_text_entered`,
`on_limit_reached`, `validator`, `highlighter` — D-EDIT-CALLBACKS) and the four **lifecycle** ones
(`before_submit`, `after_submit`, `before_cancel`, `after_cancel` — D-EDIT-LIFECYCLE) — unified
under one definition: **a callback is any function the widget itself invokes**, whether on a
lifecycle trigger, at submit-time validation, or at render for highlighting. What this decision
says about them is the same for all eight, which is why the split does not matter here: the
container is frozen and every leaf inside it is writable.

**Why.** The surface must be configurable (projects wire callbacks by plain assignment,
LÖVE-style) and tamper-resistant (a project must not replace `show`, or swap a whole sub-table) at
once. A shape rule does both with nothing to keep in sync: refuse every direct-container and
sub-table-identity write, permit every leaf. The guard lives in the surface's metatable, one level
down per sub-table, so a mistyped assignment fails at the point of the mistake rather than
corrupting the API — loudly, never a silent swallow.

> **Amended in place, 2026-08-27 (ARC-01).** "Frozen identity" binds the **project**, not the
> framework. `compy.input.callbacks` **resolves to** the current widget's `callbacks` table
> (owner ruling 2026-07-20, re-made 2026-08-27), and the widget lives for one project run
> (D-WIDGET-AT-BOOT, as amended) — so the identity is constant for the whole of the only lifetime a
> project has, and a project cannot observe the resolution. `shortcuts` and `hooks` are the
> surface's own tables and are unchanged. **The decision is unchanged:** the container and all
> three sub-table identities remain unassignable, and every leaf remains writable.

**Consequence.** `shortcuts.keypressed`'s normalising behaviour (D-COMBO-TABLES) stays reachable only
through its combo-keyed leaves; protecting that invariant is what the frozen-identities clause is
for.

**Adding a namespace member elsewhere?** The general practice behind this shape — a live platform
table reaches a project through `__index`, never as a value, because the project environment is a
deep clone — is in `../conventions/architecture_principles.md`, *"A Namespace Hands Out Live Tables
by Reference, Never by Value"*.

## D-COMBO-TABLES — per-combo registration, in tables keyed per event

**Decision.** A project registers behaviour **per combo**, rather than testing keys inside one
hook. The tables live on `compy.input.shortcuts` and are keyed **event-type-first**:
`shortcuts.keypressed[combo]`, `shortcuts.keyreleased[combo]`, `shortcuts.textinput[combo]`. A
single flat `[combo]` table serving all channels is forbidden.

**Why combo tables exist at all, which is what this entry decides.** The alternative is one hook
per channel with the key and modifier tests written inside it, and there every unrelated shortcut
a project owns shares one function. A per-combo table makes each binding **its own addressable
thing** — registered, replaced or removed by name, without touching its neighbours — so a
project's event handling can be assembled from parts instead of growing as a single block. That
is the decision, and it is about **modularity**; nothing in it is about matching.

**How the tables are assembled and matched is downstream of that, and the simplest form was
taken:** exact lookup of a canonically serialised string. The mechanics are recorded below
because a decision whose mechanics live only in code cannot be checked against the code — not
because any of them was weighed as an alternative at this altitude.

**Combo serialisation** folds left/right and orders modifiers in fixed precedence
(`ctrl`, `alt`, `shift`, `gui`), `+`-joined — `"ctrl+s"`, `"alt+shift+f4"`, bare `"escape"`.
The folded form is the **only** representation a consumer meets: modifier state is read from the
device at match time (D-ASK-THE-DEVICE), and the left/right key names survive nowhere but inside
the fold table that produces the generic name (`util/key.lua`, `mod_triples`).

> **Amended by D-THREE-MODS, 2026-08-10.** `gui` is withdrawn from the modifier set: the
> precedence order is `ctrl`, `alt`, `shift`. The serialisation rule itself — fold left/right,
> fixed precedence, `+`-joined, trigger last — is unchanged; only the membership of the list
> moves.

`shortcuts` tables normalise assigned keys to canonical form on assignment, and dispatch matches
through an overloadable matcher (default exact match), left as a marked seam for future
glob/prefix needs.

> **Canonical form is lower-case. Clarified 2026-08-31 (owner) — assumed from the start, and
> written down only because leaving it unwritten cost a defect.** Case folding is part of the
> canonical form on the same footing as folding left/right and ordering the modifiers, so
> `'Ctrl+S'`, `'ctrl+S'` and `'ctrl+s'` are one binding. It went unstated because it is the
> practically universal convention for key bindings, not because it was undecided.
>
> Unstated is not free. Registration folded case; serialisation did not, so a `textinput` shortcut
> bound to an upper-case character could never fire — the two sides of "normalise, then match
> exactly" disagreed about what canonical meant, and neither side was written down to be checked
> against. Both halves fold now.
>
> **Only the matching ignores case.** Dispatch passes the raw payload, so a `textinput` handler
> still receives the character the user actually typed and can tell `I` from `i` from its own
> first argument. The fold decides *which* handler runs, never *what it is told*.

**Substance unchanged; container renamed.** This decision's mechanics — per-event keying,
normalisation-on-assignment, the matcher seam — are exactly as originally ratified. Only the
container's name changed: the table was called `handlers`, now **`shortcuts`** — `handlers`
collided with LÖVE's own vocabulary (a local variable literally named `handlers`, bound to
`love.handlers`, sits in the very gateway function this subsystem's dispatch discusses), and the
combos are, in effect, project-registered shortcuts (`ctrl+s` etc.), so the new name reads
naturally. `hooks[event]` (D-HOOKS-SEEDED) is now symmetric with `shortcuts[event]`.

**Why per-event keying, and not one flat table** — a mechanics question, answered here because the
answer is not obvious. One flat combo table across channels was a known derivation-drift attractor
— it makes a keypressed combo and a textinput combo collide in one namespace. Per-event keying keeps them
separate by construction. Folding l/r only at serialisation gives projects a stable, readable
combo string to register against while preserving the precise held set for anyone who needs to
tell the two Ctrls apart. Normalising on assignment means a project can register `['Ctrl+S']`
and still match.

**A second, adjacent naming collision, resolved.** The gateway's unconditional, pre-route keys
(Ctrl+Q, Ctrl+Break, etc.) are called **power keys** in this subsystem's own prose, deliberately
avoiding the bare word "shortcuts" for them — reusing "shortcuts" for both the gateway's
unconditional keys and `compy.input`'s project-registered, fully-overridable table would violate
this same taxonomy's own "reserve each word for one role" principle. The in-code comment
(`controller.lua`, already labelled "Power shortcuts") is unchanged; "power keys" is this
document's label for discussing the same concept without the collision.

## D-HOOKS-SEEDED — one `hooks[event]` table, seeded once at activation

**Decision.** `compy.input.hooks` is where a project's per-event handling belongs, and a project
that installs a `love.*` handler instead is **re-wired there silently**. A project's own handler
for **any** bindable channel — the keyboard trio, the seven pointer channels, and the two derived
click events alike — auto-provisions into `hooks[event]` (D-CHAIN-OF-3's second chain component),
where it is a chain participant **with one difference from a hook the project wrote itself: it
consumes its channel** (the 2026-09-08 amendment below, and the named exception to D-CHAIN-OF-3).
*(This sentence read "where it is an ordinary chain participant" until that amendment, which is
what "ordinary" no longer is.)* `hooks[event]` is a single table and the single
source of truth: at project activation, any event for which the project has not already set an
explicit hook gets seeded once with its captured project handler (if any); after that moment the
table **is** the whole story — nil-ing a hook clears it, full stop, with no fallback
resurrection.

**What the project gets is ours, not LÖVE's** — worth stating plainly, because a project aiming to
install a `love.*` handler installs a **hook**. It does not get `love.<event>`; the route owns that
for as long as the run lasts. **The signature is unchanged and code written against LÖVE works as
expected.** What the seam adds is one thing: the return value — which LÖVE ignores, and which no
handler had a convention for — now means *consume* in hook position (D-CHAIN-OF-3;
`projectInputController.lua`, `dispatch`) **for a hook the project registered itself**. A project
author who registers combos has already met that convention; one who only ever wrote
`love.keypressed` has not, and returns nothing anyway — **which is why, since 2026-09-08, a captured
handler consumes rather than having its incidental return read**. See the amendment below.

**AMENDED 2026-09-08 — a seeded handler consumes.** A captured `love.*` handler is seeded wrapped,
so it stops the walk whether it returns anything or not; a hook written into `compy.input.hooks`
keeps the truthy convention above. The owner's terms: *"we can restore parity by wrapping legacy
`love.` hook into fn.stop_here — which would match the project expectation that occupying what it
thinks is the whole channel leaves no silent receivers. if dev installs a hook into
`compy.input.hooks` they are presumed to know the fallthrough-by-return convention … it guarantees
exact compatibility with love conventions."* This is **the named exception to D-CHAIN-OF-3**, and it
is what makes the console fall-through (`T-ROUTE-EATS-UNCONSUMED`) exact base parity per channel
rather than a repair that lets a handler's incidental return decide who else hears the event: at the
PR base, a project defining `love.keypressed` displaced the console's outright.

**What the amendment costs, stated because a paragraph below was written the other way.** A seeded
handler now stops the walk **before the project's own widget**, so a project that both handles keys
and shows the widget must register the hook explicitly. `turtle` was exactly that shape and was
migrated with this change — the owner, on being shown it: *"turtle is very specific case which
requires precise machinery. Decision to use love. hooks in it was purely for illustrative purpose,
and now it does not fit … Programs using legacy love. hooks were not aware of widget anyway."*
`doc/input_api.md` states the rule and the practical consequence for a project author.

**~~The seam is dirty, tolerable, and easily removable — the position of record~~** (owner,
2026-09-05; **superseded 2026-09-08 by the amendment above, and kept for its reasoning**).
Imitating the old effect *exactly* would mean seeding each captured handler wrapped in
`fn.stop_here`, so it consumes the way it did when it was the end of the line (D-STOP-AND-SIDE).
**That is what a released platform would owe its users, and this one is not released**: there is no
userbase beyond our own reach, and the release is already backwards-incompatible, so a safety net
bought with a second implicit behaviour buys nothing. *(What changed the answer is that the console
fall-through landed: once an unconsumed event has somewhere to go, the missing wrap stops being a
tolerated inelegance and starts deciding, per handler and by accident, whether the console also
receives.)* The live alternative runs the other way — **remove the capture entirely**, decoupling
this surface from LÖVE's, on the ground that a project that wants to overwrite a LÖVE primitive and
break dispatch should be allowed to. That one is still open and registered
(`technical_debt/input.md`, *"PROPOSAL: the `love.*` capture is a seam…"*).

**Both spellings survive the release, and the re-wiring is silent on purpose.** Announcing the
new place by *breaking* `love.keypressed` would cost more than it teaches: that form is what every
LÖVE tutorial writes, and it stays useful **pedagogically** — a project can be read, or taught, in
plain LÖVE terms and still run here. So this decision **encourages** the new spelling without
disabling the old: `compy.input.hooks.keypressed = f` is the encouraged form (this document's
*Vocabulary*, *"where that trips people up"*), and **which of the two is primary is revisable
later** without invalidating anything written against either.

**What makes `compy.input.hooks` the more appropriate place is separation, not taste** (owner,
2026-09-05). Everything a project installs sits on one surface that the project owns, so the whole
of it can be **detached from dispatch and reattached as a unit** — which is what any future
reconsideration of project sandboxing would need, and which assignments scattered across `love.*`
cannot offer however faithfully they are captured. The legacy spelling reaches the same table; what
it does not do is constitute a surface.

**One-time seed, never re-resolved.** The hook is read from the project's captured handler
**once, at activation**, and never re-consulted: `hooks[event]` is thereafter the whole story,
so nil-ing a hook clears it with no fallback and no resurrection.

**Why a seeded handler is a chain participant** *(and, since 2026-09-08, one with its own consume
rule — the clause "they consume on truthy, fall through on falsey" below is superseded by the
amendment above; the rest of the paragraph is why the hook TIER is where a captured handler lands at
all, which is unchanged)*. Treating project handlers as chain participants keeps the model uniform (they consume on
truthy, fall through on falsey, like anything else) and is what makes the keyboard-lockout fix
(D-ROUTE-OWNS) reach legacy code too: a project handler now sees events even while the widget is
shown. The alternative — a widget-aware wrapper that gated the native on visibility — would
reintroduce the exact special-case the subsystem exists to remove. "One table, one truth" is also
a strictly more predictable contract than a precedence rule invisible from the table's own
contents — a project (or a debugger) inspecting `hooks.keypressed` could not otherwise tell
whether a handler was silently active underneath a `nil`. The resurrection-on-nil behaviour was
never asked for; it was an artifact of two separate storage locations being resolved late.

**Consequence, accepted.** Because project handlers fire while the widget is shown, the two examples that
combined a project handler with widget solicitation changed behaviour and were migrated alongside
the change. Breaking-and-fixing the affected examples was the explicit expectation, not a
regression to avoid; handler-only projects (no widget) are unaffected.

**Consequence, restated after the 2026-09-08 amendment.** A seeded handler now fires while the
widget is shown **and consumes**, so the widget below it receives nothing. The class this affects is
the same one named above — a project that combines a captured `love.*` handler with widget
solicitation — and the remedy is the same shape: the example migrates. `turtle` did, to
`compy.input.hooks.keypressed`/`.keyreleased`, and it was the only **defect**: everywhere else the
widget's use of the affected channels is **selection**, which a project widget disables at
construction (`consoleController.lua`, `build_input_widget`: `UserInputController(model, true)`).
**Three examples combine a captured handler with a widget** — `turtle`, `tixy` and `maze` — and all
three were migrated, `tixy` and `maze` for consistency with the recommendation rather than to fix
anything. `sapper` was migrated too, for a different reason: it is the one non-blocking example with
a captured handler, so it is the one where falling through would have reached the console.
*(A previous version of this paragraph said `turtle` and `maze` were the only two. It was written
while looking at the keyboard channels and missed `tixy`'s `mousepressed`. Per-example measurement:
`../wip/77-new-input-api/validation/notes/S83-legacy-handler-blast-radius.md`.)*

**Four examples deliberately keep the legacy spelling** — `clock`, `colors`, `life`, `pong`. They own
the screen, show no widget, and have nothing below the handler for the wrap to shield, so for them
this decision's *"code written against LÖVE works as expected"* is exactly true, and they are what
demonstrates it. Handler-only projects are unaffected as a class, which is the whole rule: the
recommendation in `doc/input_api.md` is scoped to a project that shows the widget **and** handles the
same channel in front of it.

## D-ROUTE-LIFETIME — the route is held by an open project, released at its stop

**SUPERSEDED IN PART, 2026-08-03** — see D-ONE-LIFETIME. The original decision released
keyboard/text at the `'running' → 'project_open'` boundary while exempting pointer, and justified
the asymmetry as inherited platform behaviour. That justification did not survive checking (below);
the release is gone and every channel now shares one lifetime. What stands unchanged is the
teardown invariant, which is the part later decisions depend on.

**Decision (as amended).** The project route occupies **every** input channel — keyboard, text,
pointer and the derived click events — from activation until the project stops. A non-blocking
project reaching `'project_open'` keeps them; `Ctrl+Esc` is the way back to the console. On project
stop, every handler restores to framework defaults and every project participant — handler tables,
callbacks, widget configuration — resets.

**Why the original rationale was withdrawn.** It read: *"This is the established platform
behaviour, adopted as a design constraint because no product ruling motivated changing it,"* and
called the keyboard/pointer asymmetry *"intentional and load-bearing"*. Checked against the PR base
`3256aac`: `set_default_handlers` is called from exactly two sites — `suspend()` and
`stop_project_run()` — and the `running → project_open` transition releases nothing. Both channels
stayed installed until suspend or stop. There was no asymmetry to inherit. `release_keyboard_route`
was introduced *by this feature*, keyboard-only, and pointer then had to be exempted from a release
that had not previously existed — so the exemption was a consequence of the new mechanism, not a
constraint on it. The asymmetry was also unreachable in practice: the release fired only when
`user_is_interactive()` was false, and that predicate is "a widget or a pointer handler exists",
so at the only moment it ran there were no pointer handlers to exempt.

**Changed baseline behaviour.** Before this API, a running project without its own keyboard/text
handler left the console callback installed. With no shown project widget, unhandled input could
therefore accumulate in the hidden console and Enter could evaluate it. The project route now
occupies keyboard/text handlers for every running project: an event reaches a shortcut, hook, or
shown widget, otherwise it has no effect. A future fallback would need to be an explicit route
participant with its own contract; it must not return by omission.

**Consequence — a teardown invariant.** No callback, combo entry, or widget configuration
survives the project that installed it — including **pending config** left by a hidden
`configure`, which is widget configuration that has not reached a widget yet rather than an
exception to the rule. *(Called a "draft" here until 2026-09-04; renamed by owner ruling, because
that word is now reserved for the **user's** unsubmitted text and this is the **programmer's**
staged configuration. The old wording also said "unspent", which carried the one-shot stash
semantics `D-CFG-BOUNDARY` retired — pending config now persists until replaced rather than being
spent by the next `show`.)* Combined with the connection rule, stale configuration can
never act outside its creator's window: a disconnected route's participants receive nothing, and
a widget whose owning route is inactive goes unhonoured. `inspect` mode is the model case of the
latter (`../internals/user_input.md`, *"inspect mode"*).

---

## D-DEFACTO-KEPT — de-facto contracts: reverse-engineered behaviour is preserved and formalised, not silently changed

**Decision.** Where behaviour of this subsystem is found that no design document mandated —
mostly **before** implementation, by reverse-engineering the system on purpose and codifying what
it already did into tests and documentation, and in some cases only later, when a
post-implementation controversy surfaced one nobody had noticed — behaviour that fell out of how the code was built rather than from a
ruling — the standing rule is to **preserve it and record it as a contract**, not to "fix" it in
passing. Such behaviour is treated as a **de-facto standard set by the implementation**; documenting
and test-pinning it makes the implicit explicit. Changing any of it is a **separate, owner-gated
decision**, never a side effect of a refactor or cleanup.

**Why.** This subsystem reached its shipped shape partly by accretion — successive consumers (the
project widget, console, editor, inspect) were integrated by local additions rather than by
extending a shared abstraction, so real, live behaviours existed that no decision named.
Reverse-engineering during validation surfaced them. Altering them opportunistically while "tidying"
would smuggle behaviour changes in under the banner of cleanup — the exact failure mode this
validation phase exists to prevent. Freezing and documenting them instead cleanly separates *what the
system does* (now pinned and reviewable) from *what we choose to change* (explicit rulings).

**Consequence.** Doc entries and tests that record a reverse-engineered behaviour carry this rationale
explicitly ("discovered as existing behaviour, no mandate to alter — de-facto standard per the
implementation"). Current members include: the submit guard being *Enter-without-Shift* (so Ctrl+Enter
and Alt+Enter submit, not only bare Enter); `SearchController:keypressed` returning a jump target up
its caller; and the input widget view's per-frame-render workaround keyed by widget identity. Each is
individually revisable — but only by a named ruling, not by drift. See
[`../technical_debt/input.md`](../technical_debt/input.md) for the live list.

---

## D-UNKNOWN-RAISES — unrecognised show/configure configuration raises

**Status: implemented** (owner ruling, 2026-07-30). Enforced by `check_keys` /
`bad_key_message` in `consoleController.lua`, which cite this decision back.
**Added to by D-CFG-BOUNDARY** (owner, 2026-08-27): `text` and `cursor` join
`force` as `show`-only keys. Nothing here is withdrawn.

**Decision.** A key outside the documented config table, supplied to
`show(config)` or `configure(config)`, **raises**. A recognised field that is
only writable by direct assignment — the lifecycle callbacks — is equally
unrecognised in this table and raises with a message naming
`compy.input.callbacks`. `force` is a `show`-only key and raises from
`configure`.

**The `show`-only category, added 2026-08-27 (D-CFG-BOUNDARY).** `text` and
`cursor` are `show`-only on the same terms as `force` and raise from
`configure` with a message naming where they belong. They are the user's
content, and `configure` never touches it. This is an addition to the list
above, not a reinterpretation of it: a key that belongs to another call is
already the shape this decision raises on, and `force` was already its
precedent.

**Why — DevX: strict contract enforcement, explicit failure mode.**
Warn-and-ignore would be right if these functions took a general-purpose
document and applied whichever subset they understood. They do not: the config
table is small and closed, so a key outside it can only be an authoring error.
Ignoring it leaves the project running in a shape its author did not ask for,
with the evidence buried in a log line nobody is reading; raising stops it at
the typo. This also makes the surface uniform — `compy.input.shortcuts = {}`
already raises under D-FROZEN-SHELL, so a structural violation raising here
is the rule, not a new one.

**Scope — violations raise, runtime states do not.** A raise means *the project
asked for something that does not exist*. A call that is a no-op because of the
runtime **state** is not that, and keeps warning per D-WIDGET-AT-BOOT: `show` on an
already-active widget without `force`, and `set_text` / `set_cursor` / `clear`
while hidden. Those are legitimate calls at an inconvenient moment, not
mistakes in the project's source.

That list is exhaustive and `text` / `cursor` at `configure` were never on it.
They raise in **both** states, shown and hidden: the call is wrong whatever the
widget is doing, so there is no inconvenient moment for it to be legitimate at.

**Consequence.** `show` and `configure` raise on the first offending key, with
the trace on the project's own call line. A project's error surfaces the normal
way: raised from top-level project code it aborts the run and reports; raised
from a `love.*` handler it suspends the run with the message. The project guide
names the accepted keys, and the retired `eval` / `result` keys now raise
instead of warning.

---

## D-BEHAVIOUR-TEST — behavioural evidence is the default test evidence

**Status: implemented.**

**Decision.** Tests for the project input API prove observable project and
framework behaviour through real entry points and public surfaces. Do not add
test coverage merely because an internal edge is reachable; coverage is earned
by the feature's complexity, criticality, and externally meaningful behaviour.

**Exception.** A direct controller/model seam, mock, or interception is
allowed only when it is necessary to isolate a mechanism that cannot be
practically observed through the real path. The test must state why the seam
is used and must not present itself as an end-to-end contract test.

**Why.** Recreating lifecycle or routing logic in fixtures can validate the
fixture instead of the product. A behavioural default keeps the input suite
credible without demanding disproportionate coverage of rare, exotic, or
non-critical internals.

**Execution.** The bounded fixture pass uses real default installation and
project-stop teardown. It retains the narrow activation seam where a full
runner is inappropriate for an isolated handler test, with that reason stated.

---

## Implementation note — making the mechanism reusable (non-normative, no project-facing contract change)

Two structural extractions ride this redesign, so that the mechanism a future console/editor
adoption (D-ROUTE-OWNS) needs is reusable rather than bound to one controller's instance fields.
Neither changes project-facing behaviour — both are pure refactors:

- **Dispatch as a free function.** `dispatch(shortcuts, hooks, widget, event, trigger, ...)`
  operates over plain tables and a widget reference; `compy.input`'s guarded surface is a thin
  project-facing wrapper *over* it, not the mechanism itself.
- **The widget-method surface as a factory.** The methods `compy.input` exposes
  (`show`/`hide`/`configure`/`set_cursor`/`set_text`/`get_cursor`/`clear`) were hardwired to the one
  global project-widget instance. A `build_widget_api(get_widget, get_active_flag)` factory,
  parameterized by instance, lets any adopter — not only the project widget — get the same
  ergonomics over its own instance.

Multiple `UserInputController` instances remain required — console's REPL state must persist
independently through `inspect` mode (`../internals/user_input.md`, *"inspect mode"*) and would be
clobbered by a single shared
instance. What these extractions share is the *wrapper shape*, never the instance. This resolves a
standing in-tree question about a shared dispatcher without committing to when — or whether —
console/editor actually migrate onto this surface; that migration remains deliberately deferred per
D-ROUTE-OWNS's consequence text. Whether to unify further — one instance-record class holding
`shortcuts`/`hooks`/`callbacks`/methods together, with `dispatch` as a method rather than a free
function — was raised and deliberately left open (this codebase states a preference for functional
style over classes, `agents/rules.md`, versus the ergonomic appeal of one cohesive object); not
resolved here.

---

## The ergonomics payoff

The measure of the design is the before/after in project code. The old pattern set up the widget,
then polled a reference every update tick and manually tore it down; reacting to any key
while it was shown was not possible at all. The new pattern is a single `show{...}` with
the callbacks inline:

```lua
compy.input.show{
  prompt = 'name?',
  on_text_entered = function(text) greet(text) end,
}
```

No per-frame poll, no manual teardown, and — because the project route stays connected while the
widget is shown — the project's other key handlers keep firing throughout. The widget also stays
open by default after a submit or cancel (D-EDIT-LIFECYCLE), so continuous prompting needs
nothing more than clearing the field from `after_submit` — there is no re-`show()` involved at
all; richer uses layer on `validator`, `highlighter`, `on_limit_reached`, and the cursor/text
calls. The simple case stays one call; the expressive case is reachable without reading framework
internals.

---

## Implementation alignment

The public `show` table now matches the intended project surface: validation
and highlighting are separate callbacks, the submitted value reaches the
project through `on_text_entered` — as the joined text since D-PAYLOAD-SPLIT,
as line arrays when this was written, and D-ONE-PAYLOAD has since given
every content-bearing callback that same string. `eval` and `result`
are retired rather than carried as compatibility keys. The internal evaluator
objects used by console and editor remain implementation details.

---

## D-ONE-STATE-ASK — the widget answers one state question: `is_shown()`

**Status: implemented** (owner ruling, 2026-07-31).

**Decision.** `compy.input.is_shown()` returns whether the widget is
currently up. It is the only state query on the surface, and it is read-only.

**Why.** A project cannot determine this any other way. Its `love` is a
sandboxed deep clone (`../internals/project_sandbox_env.md`), so
`love.state.user_input` read from inside a project is **always** `nil` — the
framework writes the real global, the project sees its copy. Two examples had
already written that read as a guard; it silently never fired, and one of them
therefore re-showed the widget on every tick.

**Why only this one.** Everything else a project might poll — content, cursor,
error state — it already receives through callbacks, which is D-NO-POLLING's
whole point. Shownness is different: it is the one fact the framework changes
without telling the project (a stop tears the widget down, a hide from another
callback lowers it), so a project that must not act twice has nothing to read.
The internal flag it exposes is the widget's own `is_shown()`, so the answer
cannot drift from the one the dispatch walk uses.

**Consequence.** `show` on an already-active widget stays a warn-and-no-op
(D-WIDGET-AT-BOOT): a project that wants "open it only if it is closed" now writes
that, instead of relying on the warning as flow control.

---

## D-COMBO-SHAPE — a combo names modifiers plus one trigger, or a class

**Status: implemented** (owner ruling, 2026-08-03).

**Decision.** A combo string is modifiers plus **exactly one** trigger token.
A combo naming two triggers, or none, **raises at registration**. The trigger
may be the marker `*`, which binds the whole modifier class: `alt+*` is every
Alt chord. Dispatch tries the exact combo first and consults the class only on
a miss, so an exact binding always wins. A class never matches when the
trigger is itself a modifier.

**A bare `*` raises** (owner ruling, 2026-08-03). It satisfies the one-trigger
rule, and the empty modifier set is a class like any other, so it would bind
every *unmodified* key — `q` yes, `ctrl+s` no, that being the `ctrl+*` class.
But "every key on this channel" is exactly what `hooks[event]` is, and a
second spelling for it that reads like a narrow binding is the kind of thing a
reader has to be told about rather than can infer. A class needs modifiers to
be a class *of*; the raise says so and names the hook as the alternative.

**Why the rule is enforced rather than canonicalised.** The canonical form kept
the *last* non-modifier token and dropped the rest, silently: `ctrl+a+b` was
stored as `ctrl+b`, and `a+b+*` as a bare `*` — the widest binding there is,
from a string written to mean the narrowest. Raising is the treatment
`show`/`configure` already give an unrecognised key (D-UNKNOWN-RAISES).

**Why classes.** Some rules are about a modifier class, not a key: *every*
`alt+x` is a chord, whatever `x` is. Without the class form a project writes
one entry per key, or keeps the rule in a hook and hand-tests the modifiers —
which `examples/keyboard` did, and which needed an explicit "and not Ctrl"
clause to keep `ctrl+alt+h` out of the Alt class. A class gets that exclusion
for free: a different modifier set is a different class.

**Why the trigger, not the modifiers, may be starred.** The ratified combo
format is a *serialisation* — modifier-first fixed precedence, l/r folded,
`+`-joined (frozen design, salvage register) — and the **matcher is a marked
extension seam**. A trailing `*` extends the matcher within that seam and
needs no change to the serialisation: `*` is simply a non-modifier token, so
`normalize_combo` already canonicalises `Ctrl+Alt+*` unchanged, and the class
key at dispatch is the same `combo_string` call with `'*'` as the trigger.

**Why exactly one trigger stays the rule.** Exact-lookup dispatch is sound
because a combo names every modifier that matters — `ctrl+s` deliberately does
not fire while Alt is held. Extending that to ordinary keys would make every
binding conditional on nothing else being held: hold `a` for movement, press
`space`, and the `space` binding stops firing because the combo is now
`a+space`. Multi-key chords therefore stay out of the combo grammar. A project
that wants them uses a hook, which sees every event on its channel, and asks
the device for the key state it needs.

> **Amended in place, 2026-08-10.** The paragraph above named the
> held-key view as a hook argument and `compy.input.keys_pressed` as the
> out-of-event path. The first was already wrong — D-LOVE-ARGS gives every
> consumer LÖVE's own argument list and nothing added — and the second is
> dissolved by D-ASK-THE-DEVICE. **The decision itself is unchanged:** one trigger,
> and a hook for everything past exact-or-class matching. Only where the hook
> gets its key state has moved.

**Consequence.** `shortcuts` stays the easy, predictable mechanism: exact
match, one optional class marker, no corner cases to design against. Anything
more sophisticated is a hook, with no capability lost.

---

## D-IGNORE-REPEAT — `compy.input.fn.ignore_repeat`

**Status: implemented** (owner ruling, 2026-08-03).

**Decision.** Dispatch does **not** gate on `isrepeat`: a held combo fires on
every OS key repeat, and a hook sees every repeat too. A binding that should
act once per physical press wraps its handler in
`compy.input.fn.ignore_repeat(fn)`, which skips `fn` on a repeat.

**Scope: whether the handler runs, and nothing else.** A fresh press returns
whatever `fn` returned; a skipped repeat returns nothing, so the event carries
on down the chain exactly as an unhandled one would. Consumption is declared
separately (D-STOP-AND-SIDE) — the two are orthogonal and compose.

**It only bites on `keypressed`.** `isrepeat` is the third argument LÖVE gives
that one channel and no other, so a `textinput` or pointer participant wrapped
in `ignore_repeat` reads `nil` there and always runs. Harmless, and worth
knowing before wrapping a hook that is not a key press.

**Why not a dispatch rule.** Filtering repeats inside the shortcut tier was
weighed and rejected: it suppresses with no way to recover a hold-to-act
binding, and it would leave the same hand-written check in `hooks.keypressed`,
where commands are equally idiomatically bound. A wrapper has one signature
and composes across all three tiers.

**Withdrawn on the way here.** An earlier pass shipped `suppress_repeat`
(skip the handler *and* consume the repeat) and `bypass_repeat`. Measuring
them showed `suppress_repeat` offered an incoherent middle: with a
non-consuming handler the *fresh* press fell through to the hook while every
repeat was consumed, so press 1 behaved differently from presses 2+. Both are
gone; `ignore_repeat` is `bypass_repeat` renamed, because "bypass" claimed
something about where the event goes and that is no longer this wrapper's
business.

**On hooks.** It wraps a hook as readily as a shortcut. Whether that is wise
is the project's call: a *whole-channel* hook wrapped in it, combined with
`stop_here`, stops the widget's own held backspace and held arrows from
repeating. The guide states the caveat; it is not prevented.

**Prior art in the record.** The frozen design carried a provisional leaning
toward fresh-only at the combo tiers (salvage register, "Combo-tier repeat
semantics"), explicitly **not ruled** and parked to settle near
implementation. This settles it the other way, for the reasons above; the
constraint attached to it — existing combos keep current behaviour unless
explicitly altered — is satisfied, since the wrapper is opt-in.

---

## D-NO-LOG-NOISE — an unhandled event is not logged

**Status: implemented as no change** (owner ruling, 2026-08-03).

**Decision.** `dispatch` does not log when an event is consumed by nobody. The
walk keeps its `nil` checks and gains no unhandled branch.

**What this settles.** The design's chain diagram gave tier 3 a "DEFAULT: noop
(+debug log)", and the design notes proposed *default noop + debug log* as the
standard for all project-facing callbacks, so that "silent failure is replaced
by a visible hint in debug mode". The tree implements the behaviour — an
unhandled event falls through and mutates nothing — but not the log.

**Why the log is declined.** Taken literally at the combo tier it is a line per
keystroke that is not a bound combo, i.e. on ordinary typing, every frame a key
repeats. That is not a hint. The one variant worth anything — the chain *has*
participants and the event still fell through all of them — is a
platform-debugging question, and a platform developer can add the line to
`dispatch` for the length of an investigation. A project developer lives
without it.

**Why the noop default is declined too.** The other half of the same proposal
was a `__index` returning a noop, so dispatch could always call. It is refused
for a reason that outweighs the tidier call site: **whether a hook is set is
information**. Code that installs or removes a handler depending on what
another part of the project already installed needs to read `nil` and get
`nil`. A defaulting `__index` does not hide a check, it removes an
introspection capability — and it would also silently break `seed_hooks`,
whose "is this unset?" test is what D-HOOKS-SEEDED's capture path runs on.

**Consequence.** The nil guards in `dispatch` are deliberate and documented as
such, not an oversight to tidy later.

---

## D-STOP-AND-SIDE — `compy.input.fn.stop_here` and `.side_run`

**Status: implemented** (owner ruling, 2026-08-03).

**Decision.** Two wrappers declare what becomes of the event, at the
registration site rather than inside the handler:

| wrapper | runs `fn` | returns |
|---|---|---|
| `stop_here([fn])` | if given | `true` — the event stops here |
| `side_run([fn])` | if given | `false` — the event carries on |

Both take the function optionally. `stop_here()` with none is a binding whose
only job is to swallow; `side_run` always lets the event through, **including
when the wrapped function returns truthy** — the declaration outranks the
handler, which is the point of declaring it.

**Why.** A binding that must not fall through otherwise says so by ending
every handler with `return true`. That is the dark side of the DOM idiom: it
forces the function to know its **propagation context** — a function that
merely toggles a pause has to know what happens after it returns, and carries
that knowledge wherever it is reused. These move the statement to the dispatch
map, where a reader of the registration table can see it:

```lua
sc['alt+p'] = compy.input.fn.stop_here(pauseToggle)
sc['alt+*'] = compy.input.fn.stop_here()
sc['f5']    = compy.input.fn.side_run(log_keystroke)
```

**Not a reversal of D-IGNORE-REPEAT.** That one refused to let a repeat wrapper
decide consumption behind the developer's back. This is the developer
deciding, explicitly, where the binding is declared. The difference is who
chooses, not where the `true` comes from.

**Composes with D-IGNORE-REPEAT, and that is the whole design.** One wrapper
about invocation, two about propagation, none knowing about the others:

- `stop_here(ignore_repeat(fn))` — a reserved key: acts once per physical
  press, and nothing below ever sees it.
- `side_run(ignore_repeat(fn))` — a once-per-press side effect: acts on the
  fresh press and claims nothing, so the widget still receives every key.

**Naming.** They are named for their effect on the **event**, in dispatch
terms, rather than for their return value (`always_true`/`always_false`, which
is what they are underneath). A registration table is read to answer "what
happens to this key", and the names answer it there.

**They are called wrappers, uniformly — not combinators** (owner, 2026-09-04).
The word had drifted into this entry, into `consoleController.lua` and into
`input_events_spec.lua`, while `doc/input_api.md` — the document a project
author actually reads — has said *wrapper* throughout. The guide's word wins,
and it is also the accurate one: **these are not combinators, they are the
functions being combined.** `stop_here(ignore_repeat(fn))` composes three
ordinary functions; nothing here is an operator over them. Calling a wrapped
handler a combinator invites a reader to look for a combinator algebra that
does not exist, in a surface whose whole claim is that there is no machinery
to learn.

**Namespace.** They live under `compy.input.fn`, not on `compy.input`
directly: they are stateless functions *about* functions, not part of the
widget or dispatch surface, and grouping them says so. Writes to `fn` raise
like every other frozen sub-table.

## D-ONE-LIFETIME — one route, one chain, one lifetime for every input channel

**Decision.** Pointer events (`mousepressed`, `mousereleased`, `mousemoved`, `wheelmoved`,
`touchpressed`, `touchreleased`, `touchmoved`) and the framework's derived click events
(`singleclick`, `doubleclick`) are dispatched by the project route through the same chain as
keyboard and text, with the same error boundary and the same lifetime. Concretely:

- **The widget is the chain's terminal**, not a parallel recipient. Previously the gateway
  broadcast a pointer event to the widget *first* and then to the project's handler
  unconditionally. Delivery order therefore reverses: the project's hook runs first, the widget
  last, and an unconsumed event still reaches both.
- **A pointer hook consumes on a truthy return**, like any participant. This is new expressive
  power — a shown widget can now be starved of a click aimed past it — and it was free: no
  example pointer handler returned a value, and the return was discarded in any case.
- **No shortcuts tier for pointer.** A combo names a key; a pointer event has none. Pointer
  enters the walk at the hook tier, and `find_shortcut` answers nil for a missing table rather
  than each channel special-casing itself. A pointer combo grammar is deliberately not invented
  here.
- **Payloads are exactly LÖVE's arguments.** No modifier state is appended: a project that wants
  it asks the device (D-ASK-THE-DEVICE), and appending it would change the signature every existing
  pointer handler was written against.
- **Derived clicks are events, not a bespoke surface.** The click timer only decides *which*
  event the raw presses amount to and applies the drift check, then emits through
  `love.handlers.singleclick(x, y)` like any native event. `compy.singleclick` /
  `compy.doubleclick` are removed; projects bind `compy.input.hooks.singleclick`. The console and
  editor do not use these events, so on those routes the slot is empty and the emit is a silent
  no-op.
- **One error boundary, at route entry.** `guarded(CC, fn)` wraps the point where a route is
  entered rather than each participant. The chain itself has no error handling, so wrapping
  participants had left `shortcuts[...]` and directly-assigned `hooks[...]` — the two surfaces
  this guide teaches — unprotected, and made a raise in the third look like a falsey "did not
  consume", so the walk continued into the widget of a project that had just crashed.

**Why.** The keyboard/pointer split was this feature's own invention rather than inherited
behaviour (D-ROUTE-LIFETIME, amended). Once that was established, every remaining argument for keeping
pointer outside the chain dissolved: the lifecycle difference was self-inflicted and unreachable,
the consume contract cost nothing because nothing returned a value, and the pieces that looked
like distinct machinery — a second wrapper, a second install path, a bespoke click surface —
existed only to serve the split. Unifying removes mechanism instead of adding it.

**Consequence, accepted.** A non-blocking project with no interaction surface keeps the keyboard
until it stops, where it previously handed it back at `'project_open'`. That is the pre-feature
behaviour, and `Ctrl+Esc` remains the documented exit.

**Settled since, see D-BUTTON-TRIGGER.** The open question this entry left — whether pointer should
gain a combo vocabulary — is answered: it did, and it needed no vocabulary of its own.

## D-LOVE-ARGS — every consumer receives LÖVE's own argument list

**Decision.** Shortcuts, hooks and the widget receive exactly the arguments LÖVE delivers for the
event, unchanged and in LÖVE's order: `keypressed(key, scancode, isrepeat)`,
`mousepressed(x, y, button, istouch, presses)`, and so on. No argument is added, removed or
reordered on the way through the chain. Modifier state is not among them: a consumer asks the
device, which works inside a handler and outside one alike (D-ASK-THE-DEVICE).

**Why.** The chain used to hand keyboard and text consumers a `(k, keys_pressed, isrepeat)` triple
of its own invention while pointer channels got LÖVE's arguments untouched — so the "uniform
signature" was uniform across three channels and different from LÖVE on all of them. Two costs
followed. A project's own `love.keypressed`, seeded as a hook (D-HOOKS-SEEDED), silently received
something other than what it was written against; and every per-channel method had to know its
own payload shape, which is what kept `keypressed`/`keyreleased`/`textinput` from collapsing into
the same generated channel as the other nine.

The `keys_pressed` argument in particular bought nothing once the set was made globally readable —
an intermediate step, itself withdrawn by D-ASK-THE-DEVICE — and a project that RENDERS held state has
to read it that way regardless, since a per-frame draw has no event argument in hand.

**Consequence, accepted.** `scancode` reaches consumers although nothing inside compy reads it,
and combo triggers remain key-name-only (`doc/development/technical_debt/input.md`, "Combo
triggers are key-name-only"). That is the same bargain the pointer channels already made with
`istouch` and `presses`: passing LÖVE's list verbatim is the rule, and an unread argument is the
price of not having a second rule.

**Consequence, accepted.** The console/editor route still narrows to `CC:keypressed(k)`. It has no
widget tier to thread the rest to, and its own dispatch predates the feature.

## D-BUTTON-TRIGGER — one combo vocabulary, with the button as a trigger

**Decision.** Every channel carries a shortcuts tier, and every combo is written the same way:
modifiers plus a trigger, or modifiers plus `*` for the class. What differs is only what the
channel has to name. `mousepressed` and `mousereleased` name the **button**, serialised `mouse1` /
`mouse2` / `mouse3` — so `shortcuts.mousepressed['mouse2']` is a right-click and
`'ctrl+mouse1'` a ctrl-click. Channels with no discrete trigger — `mousemoved`, `wheelmoved`, the
touch events, the derived clicks — take modifier classes only, and with no modifier held there is
nothing to name, so the event goes to the hook tier.

**Why.** The guide had argued a pointer tier was impossible because "a combo needs a key to name".
It does not: `combo_string('*', keys)` already built a triggerless class key — that is what
`alt+*` has always been. The asymmetry was an accident of nobody wiring it, not a design.

Excluding the button was considered and rejected, on the owner's challenge. The argument for
excluding it — "the button already arrives as an argument, so the handler can test it" — applies
word for word to the keyboard, where the key also arrives as an argument and is a combo trigger
anyway. Taken seriously it abolishes the shortcuts tier entirely and puts every binding back
behind `if button == 2`, which is the string-tag dispatch `agents/rules.md` forbids in as many
words. A shortcuts tier exists precisely so a handler does not have to test what it was
registered for.

**Consequence, accepted.** A channel's trigger is read from a different argument position per
channel (first for keys and text, third for buttons). That is one table of accessor functions,
not a branch, and it is the only per-channel knowledge the route holds.

**The derived clicks keep `(x, y)` and name no button** (owner ruling, 2026-08-07). They are not
LÖVE events and their signature does not resemble one, so there is no stock shape to converge on
and no reason to widen them for symmetry's sake. They take modifier classes only. A project that
needs to distinguish which button produced a click binds `mousereleased` and does its own timing,
which is what the framework's timer does on its behalf.

**Fast path preserved.** For a triggerless channel the held-modifier test runs before any combo
string is built, so an unmodified `mousemoved` allocates nothing. A bare `'*'` still raises on
every channel: it would mean "every event", which is what a hook is.

## D-STOP-IS-FW — stopping is the framework's; the project's hook is called from inside it

**Decision.** The framework owns a teardown function of its own, and it is the **only** place a
project's `compy.before_exit` is invoked. The project's hook is called directly from inside it,
inside a `pcall`, with its return value not read. The framework function itself returns nothing, so
no caller can read one either. Resetting the slot to the default is part of the same function, after
the call, unconditionally.

**Why.** `before_exit` sits in the project's namespace next to `compy.input.hooks`, and everything
else in that neighbourhood signals by returning truthy — that is what a chain consumer does. Exiting
is not a chain. **Stopping is a lifecycle step the framework performs, not one the project
participates in**, and exposing a hook at all is a convenience: somewhere to save a score, flush a
memo, stop a timer.

Guarding the call site was not enough, because it left the guarantee as a property of one call
site's current code. Two defects reached the tree on exactly that footing within one session — a
nil hook and a raising hook each abandoned teardown from its first statement. The indirection makes
the guarantee structural: there is one invocation, it is not a dispatch, and there is no return
value in the chain for a later edit to start honouring by accident.

**Consequence, accepted.** A project cannot refuse to stop, cannot defer the stop, and cannot break
it by failing. A raise is logged and the stop continues. This is the hook's final form, not a
deferred question.

**Consequence, intended.** The framework now has a named place to do teardown of *its* own. Forced
restore of global device state a project altered — key repeat, text input, anything a crashed
project leaves dirty — belongs here when it is built
(`doc/development/technical_debt/general.md`). That gap is the one this hook cannot close on the
project's behalf: a project that raises before reaching a clean state never runs its own teardown,
because the raise ends the run rather than the stop.

## D-ASK-THE-DEVICE — modifier state is read from the device; `keys_pressed` is dissolved

**What it withdraws — the whole held-key-set arc, which took three decisions and is now this one.**
The framework used to maintain a table of currently-held keys and expose it as
`compy.input.keys_pressed`: a read-only view of the live set — reads passing through, assignment
raising — arriving as the second argument of every chain signature, then readable at any time so
that a per-frame `love.draw` could ask, and finally declared the framework's truth for event-time
questions. **All of it is withdrawn**: the table, the view, the argument and the surface. Nothing
replaced it, because the device answers the same question with no model to keep in step.

Two details of that arc are kept here because they still bite. The view was **index-only in
practice** on the shipping LuaJIT/Lua 5.1 runtime — `pairs` ignores `__pairs`, so iteration
yielded nothing while indexing worked, and the iterability was carried for a 5.2+ host that never
arrived. And the consumer that justified exposing it at all — `examples/keyboard`, which renders
shifted key labels **during draw**, where no event argument is in hand — is served by
`love.keyboard.isDown` directly, which is why removing the surface cost that example nothing.

D-COMBO-TABLES, D-COMBO-SHAPE, D-LOVE-ARGS and D-BUTTON-TRIGGER (combo serialisation, combo naming,
LÖVE's own argument list, one combo vocabulary) **stand unchanged** — only the *source* the
matcher reads from changes.

**Decision.** Four statements, in force together.

1. **Modifier state is read from the device.** `Key.ctrl()` / `Key.alt()` / `Key.shift()` —
   i.e. `love.keyboard.isDown` — is the single source of held-modifier truth.
   **`compy.input.keys_pressed` and `Controller.keys_pressed` are dissolved from all
   occurrences**, production and test. This reverts an *implementation-time* decision: the
   tracked set was never a requirement — no stakeholder requirement asks for it — and it is
   reverted on that basis.
2. **`Key.*` is legitimate inside the shortcut matcher.** The combo-string builder
   (`combo_string` / `any_mod`, D-COMBO-TABLES) reads the device to name the modifiers it
   serialises. This is the one place a direct read is not merely permitted but correct.
   **Shape ruled in place, 2026-08-09 (owner):** the builder calls `Key.ctrl()`/`Key.alt()`/
   `Key.shift()` **directly** — it does not keep its table parameter and receive a per-key
   device lookup. The rejected alternative would have left the builder source-blind and
   table-testable; the ruling prefers symmetry with the pre-dispatch gate, which already polls
   this way, and one literal source of modifier truth over an adapter standing in front of it.
   **Consequences, stated because they are costs and not side effects:** `combo_string` and
   `any_mod` lose their parameter and every caller changes; the matcher can no longer be
   driven by a synthetic table, so the test cases that do so are rewritten against a patched
   `love.keyboard.isDown`; and the mock's variadic fix becomes a prerequisite (see the
   amendment note below).
3. **`Key.*` at a call site remains a smell.**
   > **AMENDED by D-USAGE-SHAPE, 2026-08-11.** This is **withdrawn as a general claim**. An
   > imperative modifier test is the correct answer for **continuous state** — "is this held
   > right now" — and is a smell only when it answers a *transition* that a binding should have
   > expressed, or when it re-implements the fold. D-USAGE-SHAPE states the boundary. The rest of
   > this point stands unchanged.

   In projects today, and eventually in
   console/editor too, an imperative modifier test at a call site should be replaced by the
   **shortcuts mechanism**. The one place this does not apply is **the gate** — the block in
   `controller.lua` that runs *before* dispatch and tests its own universal set of key
   combinations by direct polling, typically for the non-overridable ones: shutdown, exit,
   quickswitch. The gate is **not an exempt list of privileged combos**; it is a distinct layer,
   and what it lacks is a *mechanism*, not a justification — no shortcuts table exists at that
   position. **It could build its own table** — the introspectability reason the rule exists
   applies to it too: bindings that can be listed, documented and rendered rather than read out
   of a cascade. **That is not committed to** (owner, 2026-08-09): naming the layer does not
   oblige the table, and building one is out of scope for this feature's PR and may never be
   done. If it ever is, it must be visibly a **second, privileged table**, structurally separate
   from a project's own and stating its non-overridability where it lives — otherwise the win
   arrives with a false promise of override.

   > **Amended by D-RESERVE-TABLE, 2026-08-16.** The table is **built**. What is withdrawn is only
   > the *not committed to* — the separateness requirement above stands unchanged and is now a
   > build instruction it satisfies (`RESERVED`, `controller.lua`, which states both its
   > non-overridability and its opposite consumption rule where it lives). The cascade of
   > modifier predicates this point describes is therefore gone: the gate builds one canonical
   > combo string per event and matches it, so exactness is a property of the representation
   > rather than a discipline at each branch. D-EXACT-RESERVE is the prerequisite that made a
   > combo-keyed entry well-defined.
4. **When a shortcut does not fit, the shortcut sets a flag — it does not grow.** Where the
   logic cannot be carved into exactly one isolated shortcut function, the recommended shape is
   a **tiny shortcut that sets a feature flag and does not consume its triggering event**. The
   hook then runs the heavy logic against **feature flags** rather than against hardware state.
   This keeps the declarative binding intact and moves the branching off the device entirely.

**Why the tracked set is withdrawn — the core rationale.** It is a **stateful abstraction model
over an entity we do not control**. Nothing prevents it drifting from reality, and nothing
reconciles it once it has: a release that never arrives leaves an entry that no later event
clears. The sharpest form of the objection is that **the only way to detect drift in the tracked
model is to compare it against the device poll** — which makes the device the authority and the
tracked set a cache of it. A cache that needs the authority to validate it is strictly more
machinery than asking the authority.

Polling is, by contrast, **stateless and self-healing**: there is no accumulated model, so there
is nothing to go stale, nothing to reconcile, and no recovery path to design. Its errors are
**ephemeral** — bounded by one frame's batch, and gone on the next read.

**Why the combo mechanism survives the change intact.** The two questions were conflated for most
of this feature's life and they are separable. Combos are a **dispatch** improvement:
declarative binding instead of imperative branching; the cascade replaced by a table lookup;
**introspectable** bindings that can be listed, documented, rebound and rendered into a help
overlay, which a tree of `if`s can never be; and explicit precedence (exact before class,
consumption by truthy return) where a cascade has precedence only by accident of line order.
None of that depends on where the modifier answer comes from — `combo_string` takes the held
state as a parameter. **The dispatch argument never implied the state-source argument.**

**Corroborating evidence, recorded because it is easy to lose.** This codebase already contained
**two** poll-shaped fakes of the input surface before the feature, and both survive it:
`src/harmony/init.lua` `patch_isDown`, and `tests/mock.lua` `keystroke`, which sets `held[m]` for
each modifier and emits no modifier event. The tracked set was the only source of truth in the
system that neither of them could drive.

**Consequence, accepted — the batch-skew error.** LÖVE pumps the whole event queue and then
dispatches its events one at a time, so a device poll taken while dispatching the first of
several queued events reports the state after the last. A combo can therefore be misread when
two key events land in the same frame. This is **accepted**, on these grounds: it requires the
user to act faster than a frame accumulates — an unusual hit-and-release, or input typed into an
engine already stalled for seconds, where glitchy input is expected — and the error is
**ephemeral and dissolved by ordinary user reaction** (release and repeat, hold the modifier
longer). Its frequency is **unmeasured**; so was the staleness it replaces.

**Consequence, accepted — the failure mode is no longer testable.** A poll fixture is always
self-consistent, because SDL's batch timing is not modelled by the mock. The tracked set's
staleness *was* expressible in a test; this is not. Accepted as the price of having no state.

**Consequence — a prerequisite, not an option.** `tests/mock.lua`'s `isDown` is single-argument,
so every variadic `Key.ctrl()` under test consults only the **left** key of the pair. It must
become variadic (harmony's `patch_isDown` shape) before the suite can be trusted about modifiers
at all.

> **Amended in place, 2026-08-09 — scope corrected, then reinstated by ruling.**
> An earlier pass challenged this paragraph and was right on the facts as they then stood: no test can
> reach a state where left and right differ (the mock's token map writes only `lctrl`/`lshift`/
> `lalt`, and no test installs its own keyboard `isDown`), so making the mock variadic changes
> **zero existing test results**, and the single-argument `isDown` is pre-existing and untouched
> by this branch. "Before the suite can be trusted about modifiers at all" overstated it.
>
> **The owner has since ruled the matcher's shape (2026-08-09): the combo-string builder calls
> `Key.ctrl()`/`Key.alt()`/`Key.shift()` directly** rather than being handed a per-key device
> lookup. Under that shape all modifier truth in dispatch routes through the two-argument call,
> so the fix is a genuine prerequisite again — precisely scoped: **not** that existing results
> are wrong, but that **no test proving the new matcher can exercise a right-hand modifier
> until the mock is variadic and its token map gains `rctrl`/`rshift`/`ralt`** (the `held` table
> already has the slots). It lands first, as its own commit, ahead of the test rewrite.

**Consequence — debt that ceases to exist.** The focus-loss staleness fix, the gateway's
event-set migration, the harmony reconciliation that migration would have forced, and the open
questions on recovery path, serialised form and repeat counting are **all** properties of the
tracked set. They are withdrawn with it rather than deferred.

---

## D-THREE-MODS — the modifier set is closed, and it is `ctrl`, `alt`, `shift`

**Amends D-COMBO-TABLES**, whose serialisation rule named a fourth modifier row. D-COMBO-SHAPE and
D-ASK-THE-DEVICE stand unchanged and are the reason this one is small: D-COMBO-SHAPE already rules
what a combo may name, and D-ASK-THE-DEVICE already rules where modifier state is read from.

**Decision.** The framework recognises exactly three modifiers — `ctrl`, `alt`, `shift`, each a
left/right pair folded to its generic name. `gui` (super / cmd / win) is **not** a modifier.
Combo serialisation orders the three in that fixed precedence; `Key` exports an accessor per
modifier and no more; and `lgui`/`rgui` are ordinary key names.

**Why `gui` is withdrawn rather than completed.** No stakeholder requirement asks for it and no
shortcut has ever registered one. It was added for **symmetry** with a builder that folded
whatever held-key table it was handed — a shape where a fourth row cost one line and answered
itself. D-ASK-THE-DEVICE dissolves that shape: the builder now asks the device through a named accessor
per modifier, and `gui` has none, so the row that was free becomes a thing to build and maintain
for a capability nobody requested. This is the same ground D-ASK-THE-DEVICE gives for the tracked set
itself: an implementation-time addition, reverted on the basis that it was never a requirement, in
a change whose purpose is to leave the input API simpler than it found it.

**What "not supported" means concretely** — it is a boundary, not a gap, and it is observable:

- **A `gui` combo is refused at registration.** With `gui` outside the modifier set, `gui+s` names
  two triggers, so `shortcuts.keypressed['gui+s']` raises D-COMBO-SHAPE's registration error. A
  project asking for the capability is told so, rather than binding something that never fires.
- **`lgui` becomes an ordinary trigger.** `shortcuts.keypressed['lgui']` is a valid binding and
  fires on the Super key, exactly as `shortcuts.keypressed['f5']` does. Membership of the modifier
  set is precisely what makes a token a modifier rather than a trigger, and this is that same rule
  running the other way.
- **Nothing else observes it.** No shipped project or example registers a `gui` combo, so the
  withdrawal removes no working behaviour.

**Supportable in principle.** Re-adding it is a bounded change — a `gui()` accessor beside the
other three, the row restored to the fold table, and the precedence list extended — and it should
be done **if a requirement ever asks for it**, not for symmetry. The technical-debt register
carries the pointer so the option stays discoverable from that side too.

## D-USAGE-SHAPE — how the input API is meant to be used: transitions, state, and no reconstruction

**Amends D-ASK-THE-DEVICE point 3** (`Key.*` at a call site is a smell), which is withdrawn as a
general claim and replaced by the boundary below. D-COMBO-TABLES, D-COMBO-SHAPE, D-LOVE-ARGS,
D-ASK-THE-DEVICE and D-THREE-MODS stand unchanged: this decision is about **use**, not about
mechanism.

**Why it exists.** The feature introduced a framework-tracked held-key set on an early sense that
polling needed to be a legitimate, centralised method — and deferred the analysis of that sense to
*"we will see how it is used"*. Use has now been seen, across the example corpus: the same
left/right fold re-implemented independently in three projects, a poll-plus-mirror rebuilding an
edge the event channel already delivers, and three separate defects of one shape (a state opened
by one event and closed by another that never matched). The set was withdrawn (D-ASK-THE-DEVICE); this
decision is the deferred analysis arriving, and it is stated as guidance because the mechanism was
never the problem.

**Decision — five statements, in force together.**

1. **A shortcut is for a one-off transition of the project's own state.** Start, end, mode change,
   show the widget: an independent change that stands on its own once made. Its purpose is
   **decomposition** — one binding per thing, listable as data — not capability. It is *not* the
   instrument for holding a state that stops being true when the triggering condition dissolves.
2. **Interdependent shortcuts are an architectural smell.** Specifically, a state opened on
   `keypressed` and closed on `keyreleased` with the same combo is an **antipattern**: a combo
   serialises from its trigger plus the modifiers held *at that instant*, so the closing event can
   serialise differently from the opening one and never match. A modifier's own press or release
   has no expressible combo at all (D-COMBO-SHAPE), so for some chords the closing half **cannot be
   written**. Window focus loss removes the closing event entirely.
3. **Choosing the release channel is legitimate; pairing it is not.** Reacting on `keyreleased` is
   a fair UX choice and sidesteps key repeat without filtering. `fn.ignore_repeat` answers the
   same need on the press channel. Note that a *modified* combo can be missed on release when a
   modifier comes up first, so prefer the release channel for bare keys.
4. **Polling the device is the right paradigm for continuous state** — is this held right now,
   what should this key cap look like, is Ctrl down during this drag. The state is
   **self-correcting**, and the abstraction masks nothing. `Key` answers both kinds of question:
   the folded accessors for a modifier, `Key.any_pressed` for any other key, so project code has
   one surface rather than two.
5. **Held state is not reconstructed from events.** A project does not rebuild "what is down" from
   `keypressed`/`keyreleased` — nor the mouse equivalent — **unless it is a deliberate,
   project-specific decision taken in awareness of the trap**: it is virtual mutable state with no
   path back to the truth, and its drift is invisible, surviving whatever caused it. The framework
   maintains no such table, deliberately (D-ASK-THE-DEVICE).

**What this does NOT say.** It does not deprecate `Key.*`, and it does not ask projects to convert
working code. An imperative modifier test answering a continuous question is correct; the smells
are the **chain** (a fold or an exclusion re-implemented at each call site) and the **depth**
(hardware consulted inside logic that is otherwise a pure function of project state). The
recommended remedy for depth is to read the keyboard early, into names with game meaning, and run
the logic on those.

**If event-sourced held state ever proves genuinely required**, it belongs to the framework rather
than to each project — maintained centrally, exposed for reads, and kept **separate from the
physical polling surface**, so a reader always knows which question they are asking: what the
events say is held, or what the device says. Conflating those two is the "two clocks" problem this
feature spent its length removing. Recorded as a direction, not a commitment; the register carries
the proposal.

## D-EXACT-RESERVE — a framework reservation matches its modifier set exactly

**Owner ruling, 2026-08-16.** Amends nothing; it states for the **gate** the rule
D-COMBO-SHAPE already states for everyone else. D-COMBO-SHAPE, D-ASK-THE-DEVICE and D-THREE-MODS
stand unchanged — D-COMBO-SHAPE rules that a combo *is* its modifier set exactly, D-ASK-THE-DEVICE
rules where modifier state is read from, D-THREE-MODS closes the set at three.

**Decision.** Every combination the framework reserves for itself matches **exactly**:
the modifiers it names are held, and **no other modifier is**. A reservation written as
a device poll must therefore exclude the modifiers it does not name — `Key.ctrl() and
not Key.alt() and not Key.shift() and k == 'escape'`. A reservation that names no
modifier is claimed only when none is held.

**Why — two reasons, the second the stronger.**

1. **A project's exact combo must not dissolve into a framework one.** A project may
   register a richer combination that contains a reserved one: `ctrl+shift+escape`
   contains `ctrl+escape`. Under a tolerant reservation the project's binding fires
   *and* the framework's does, so the richer gesture decays into the poorer one and the
   project cannot express it at all. `examples/maze` hit exactly this: of its restored
   Shift+Escape family, the two Ctrl-bearing members return the game to its menu on the
   press and are torn down on the release, because the gate reads the chord as
   Ctrl+Escape.

2. **Framework shortcuts are not overridable, so they must be narrow — least
   privilege.** A project cannot take a reserved combo back — the property the
   framework-shortcuts suite pins (`tests/input/input_global_shortcuts_spec.lua`);
   the gate runs at the raw pump entry, before any route. That is unlimited power over
   the input surface, and unlimited power is exactly what should be granted on the
   narrowest possible condition. A reservation that claims chords it does not name is
   privilege taken by accident rather than by design — the input equivalent of a
   permission granted with a wildcard.

**What this changes.** The reserved gestures keep working as named; what stops is their
claim on **extensions** of themselves. Ctrl+Shift+Escape, Ctrl+Shift+T,
Ctrl+Shift+S and Ctrl+Alt+Shift+R stop being the framework's — the first three become the
project's, and the fourth stops firing `restart` and `reset` in one event, which is the same
looseness producing an outright defect. Plain Ctrl+Escape is untouched, so the recovery path out
of a running project is exactly as it was: the safety property does not depend on
tolerance, and never did.

**Scope — confirmed by the owner, 2026-08-16.** The rule binds the **pre-dispatch gate**
and nothing else: the block that runs before a route is forwarded to, and whose power is
non-overridable. Console and editor key handling is route-level — it competes with no
project, since no project is running while the console owns the route — and its combos
are **sorted out when those routes are adopted onto the combo mechanism**, not here.

**Cost, stated because it is a cost.** This is a framework behaviour change made inside
a feature whose mandate is the project-facing input API, and it owes the PR description
a justification line. The ground for it is that this feature made every other layer
exact and left the one layer with the most power tolerant.

**Amended by the `MERGE-01-05` import, 2026-09-05 — the worked example's other half moved,
and the rule is what let it move alone.** Bare `ctrl+s` used to close the editor's buffer;
upstream PR #45 **deleted that**, made leaving `Shift+Esc`, and the owner ruled 2026-09-04 that
**#45 holds the product authority there**. **What #45 does NOT do is reserve the key** — its
checkpoint is **`Ctrl+K`** (`Ctrl+Shift+K` restores), in its code and in its own `doc/EDITOR.md`,
whose only `Ctrl+S` row is *"Stop project"*. A **stale comment in its `controller.lua`** says
*"reserved for the checkpoint"*, left behind when the close was deleted, and this corpus believed
it for a day. So bare `ctrl+s` in the editor is **unclaimed, not reserved** — which reopens
whether our close had to go at all: `technical_debt/input.md`, `T-CTRL-S-UNCLAIMED`. So in the editor
`ctrl+s` now does nothing and `ctrl+shift+s` still leaves — which is only expressible
*because* reservations are exact: under the tolerant matching this entry retired, changing
one would have changed both. **Neither is a gate reservation.** `ctrl+shift+s` stays where
the Scope paragraph above puts it, at route level in `EditorController:_leave_keys`, and the
gate's `ctrl+s` reservation is unchanged — it stops a *running* project and has never had an
editor branch. See `technical_debt/input.md`, `T-CTRL-S-UNCLAIMED`.

## D-RESERVE-TABLE — the gate's reservations are combo strings in a privileged table

**Owner ruling, 2026-08-16.** **Amends D-ASK-THE-DEVICE point 3**, which named this
table, declined to commit to it, and required that if it were ever built it be
"visibly a second, privileged table, structurally separate from a project's own".
That requirement stands and is now a build instruction rather than a condition on
a hypothetical. What is withdrawn is only the *not committed to*.

**Decision.** The pre-dispatch gate expresses each reservation as a **canonical
combo string**, matched **exactly**, in a table keyed per event —
`reserved.keypressed['ctrl+t']`, `reserved.keyreleased['ctrl+escape']` — rather
than as a cascade of modifier predicates and `if k == …` branches.

**Why this follows rather than being a new idea.** Each step made the next one
available:

1. D-EXACT-RESERVE made reservations exact, so a chord maps to **one** action. While
   `ctrl+alt+shift+r` matched both the reset and restart gates, a combo-keyed
   table had no well-defined entry for it; exactness is what makes the table
   possible at all.
2. Exactness is most naturally *expressed* as the canonical combo string the
   project already builds (`combo_string`, D-COMBO-TABLES's precedence) — and a
   string equality cannot tolerate an unnamed modifier, so the rule of
   D-EXACT-RESERVE becomes a property of the representation instead of a
   discipline to remember.
3. Once every reservation is a string, the cascade **is** a table written the
   long way. Writing it as a table is the smaller form, not the more elaborate
   one.

It also serves the reason D-ASK-THE-DEVICE point 3 gave for wanting it: the reserved
set becomes listable, documentable and renderable rather than read out of a
cascade — which is what the input guide's reserved-combo section owes.

**The two tables are distinguished, and this is the load-bearing part.** They
share a shape and differ in both directions:

- **Override.** A project cannot take a reserved combo; the reservation table is
  consulted before any route exists. This is the property already pinned by the
  framework-shortcuts suite.
- **Consumption — the opposite of a project's rule.** A project's shortcut
  consumes by returning truthy. **A reservation never consumes**: the key
  continues to the route afterwards, exactly as it does today. Same shape,
  opposite contract, and the more misleading of the two — so it is stated **at
  the table**, in the code, not only here.

**What does not change.** Which combos are reserved, what each does, when each
applies, and the gate's position in the flow. This is representation, not
behaviour: the live cases from D-EXACT-RESERVE's sweep are the proof, and **none of
them should need editing**.

**Device reads.** Incidental, but it is the reason the shape is also cheaper: the
cascade asks the device once per predicate — up to about twenty per keypress —
where a single canonical string per event asks three. The route asks three of its
own, or six when the exact combo misses and the class key is built after it;
sharing one answer between the two layers was considered and **rejected** —
a cached combo is a model of device state with no path back to the truth, the
shape D-ASK-THE-DEVICE dissolved `keys_pressed` for, and the dispatch walk is
deliberately reachable without the gate.

---

## D-CFG-BOUNDARY — the configuration boundary: the user's content is `show`'s alone

**Owner-ruled 2026-08-27.** **Adds a `show`-only key category to D-UNKNOWN-RAISES** (below).
D-WIDGET-AT-BOOT, D-EDIT-LIFECYCLE and D-ONE-STATE-ASK stand unchanged: this decision is about *which call
may set what*, not about lifecycle or routing.

**The shape.** A config table carries two kinds of field, separated by **who owns the thing it
sets**:

| | owner | set by |
|---|---|---|
| `text`, `cursor` | **the user** — they are typing in it | `show` (the baseline), and `set_text` / `set_cursor` / `clear` while it is up |
| `prompt`, `highlighter`, `validator`, `on_text_entered`, `on_limit_reached`, and the four lifecycle flags | **the project** | `show` **and** `configure`, set-if-given, persisting until replaced |

**The `show`-only side is `text`, `cursor` and `force`, and the three belong there for two different
reasons.** `text` and `cursor` are the **user's**, and a call that changes
settings must not reach into what somebody is typing. `force` is there because it is *meaningless*
at `configure` — it answers *"replace the widget already shown"*, a question `configure` never faces.
**Neither reason is "it describes this session"**: a key that configures the widget's own behaviour
is the project's, whatever its lifetime, and lifecycle is not something the user owns.

**Decision — four statements, in force together.**

1. **`show` owns the content baseline — and AMENDED 2026-09-07: it no longer destroys.** `text`
   given is the content. **`text` absent leaves the content alone**, so a re-show finds what the
   last lifecycle verb left. `cursor` is applied after it.
   **Owner ruling:** *"i feel with the flags covering wide range of use cases we do not need to
   hardcode any implicit destructive behavior into `show`."* Destruction now has exactly one home —
   the `(verb × outcome)` flags of `D-LIFECYCLE-FLAGS` — and activation has none. **This is what
   makes the four flags answer the stakeholders' re-show proposal**: `show()` and `show{}` stay
   identical, and the *"semantically inobvious"* distinction that proposal asked for is never
   needed.
   **The consequence to state at the call site, because it is a real change of meaning:** a table
   without `text` — `show{prompt = 'Name?'}` — now **inherits the previous draft**. A project
   opening an unrelated question passes `text = ''` (or lets the previous verb's `clear_on_*` do
   it). The old rule made that free and made the re-show impossible; the new one makes the re-show
   free and the fresh start explicit, which is the trade the ruling takes.
   **IMPLEMENTED 2026-09-09.** `reset_content` is one branch — `if cfg.text ~= nil then set_text`
   — and the entry that carried the obligation, `../technical_debt/input.md`, `T-SHOW-DESTROYS`, is
   retired. **Two edges the amendment implied and did not state, settled by owner ruling the same
   day** (*"text given changes the content, text omitted does not. Force is orthogonal — it
   determines whether `show()` is allowed to run on an already shown widget"*):
   - **`text = false` reads as absent**, so it keeps the content. It is the uniform unset of
     statement 3, and `checked_text` normalises it to `nil` at the boundary; the explicit fresh
     start is **`text = ''`**, which is text *given*. *(This reverses a behaviour pinned and
     documented in 2026-09-01's boundary lift, where `false` came to mean "opens empty".)*
   - **`force` gains no content meaning.** A forced show with no `text` keeps the draft exactly as a
     bare one does; `force` answers *"may this run over a widget already shown"* and nothing else.
   **Three things beyond the text survive a re-show with it**, because `clear_input()` took all four
   together: the selection, the custom status and the history index. Each has its own case in
   `tests/input/input_widget_control_spec.lua` — the old call's silent breadth is exactly what an
   unpinned reader could not see.
   *(Prior statement 1: `text` absent was an empty field — *"absent means empty"* — and a project
   wanting the previous draft back had to pass it.)*
2. **`configure` never touches the user's content.** `text` and `cursor` at `configure` are **keys
   that belong to another call** and are refused as such — the treatment the lifecycle callbacks
   already get, with a message naming where they belong. `set_text` and `set_cursor` are the live
   writes; `clear` is the live reset.
3. **Everything the project owns is set-if-given, in both calls.** A field the caller did not name
   is left alone — never cleared, never defaulted. `false` is the unset: every consumer tests
   truthiness, so a stored `false` takes the same path as a field that was never set. For `prompt`,
   `''` is an empty label and `false` restores the default one.
4. **`show` is `configure` plus the content baseline plus activation.** `show{force = true}` over a
   live widget is a full re-setup — the same path a first `show` takes — and without `force` it is
   refused with a warning (D-WIDGET-AT-BOOT). There is no third policy, and no field that one call applies
   and the other silently drops.

**Why this shape.**

- **Separation of concerns.** The split is not a list to memorise but a question to ask: *does the
  user own this?* Content is theirs, and a call that changes settings must not reach into what
  somebody is typing. Everything else is the project's, and persists because the project is the one
  who set it.
- **Least astonishment.** The alternative in force before this decision let one call apply a field,
  drop a second and defer a third to the *next* activation. A closed config table that raises on a
  key it does not know, while silently discarding one it does, teaches the wrong lesson twice.
- **DRY.** `show` composes `configure` rather than reimplementing it. One function applies the
  project-owned fields, and it is the same function in both paths, so the two cannot drift.
- **KISS.** One rule and one deliberate exception, in place of three content policies reachable from
  one function. The exception is the user's content, and it is stated rather than encoded in the
  order in which two helpers happen to run.

**What this adds to D-UNKNOWN-RAISES.** That decision raises on unrecognised configuration and keeps
*runtime-state* no-ops to a warning — `show` on an already-active widget without `force`, and
`set_text`/`set_cursor`/`clear` while hidden. `text`/`cursor` at `configure` **raise**: they are not
a legitimate call at an inconvenient moment but a call to the wrong function, true whether the
widget is shown or hidden.

This is an **addition, not an amendment** (owner, 2026-08-27). D-UNKNOWN-RAISES's warn list names three
runtime states and `configure{text}` was never one of them, so nothing there is being reversed; and
the decision already raises for *a key that belongs to another call* — `force` is a `show`-only key
and raises from `configure`. `text`/`cursor` join that existing category rather than crossing a line
the decision had drawn elsewhere.

**What this changes for a project — three things, all stated rather than discovered.**

**First, a forced `show` with no `text` now clears.** Before this decision it preserved the content,
which is what the spec approved in round 2 said (*"content replaced if `text` is provided, preserved
otherwise"*) and what a test pinned deliberately. Statement 4 reverses it, because a `force` that
sometimes re-sets-up and sometimes half-does is the third policy this decision exists to remove, and
because the stakeholder's own words for the flag were *"override the existing one"* — a request that
outranks a parenthetical inside a package they approved. A project that wants the draft kept passes
it, or does not pass `force`.

**Second, a hidden `configure` no longer retains `text`/`cursor` for the
next `show`.** Nothing is lost: content for a widget that is about to be shown is set **by the `show`
that brings it up**, before it is visible, and any richer deferral is a local variable in the
project. The retained `prompt` is unaffected — it is project-owned, applies immediately, and is
still there at the next `show`.

**Third, content is not preserved across `hide` → `show` either, and the approved design said it
would be** (owner-ruled 2026-09-02). The ratified spec required restoration in as many words —
*"Content preserved for the next `show()` without `text`"* — and the round-2 reviewed text spelled
it out: *"Input content is preserved (subsequent `show()` will display it unless `text` is
provided)"*. Statement 1 is why it is not: `show` seats the content baseline, so a bare `show()`
opens empty whether or not a `hide()` came before it. Note the boundary, because the sentence above
is loose about it: **`hide()` itself preserves the content** — it flips the shown flag and clears
`love.state.user_input` and does nothing else. What a project loses is the round trip.

**The requirement is retired as unfeasible-for-the-need, not overlooked.** It was approved in a
batch and never checked against a use case. There is no scenario, in this tree or in the
stakeholder's ask, that hides a widget and needs exactly the same text and cursor back — and the two
`hide()` call sites that exist (`maze_main.lua:126`, `draw_main.lua:233`) both **abandon** the
widget to return to a menu, so they want the clearing, not the restoration. Making restoration
first-class would put a content-lifetime rule into a surface whose entire content story is *"`show`
seats it"*, which is more API to explain than the case is worth.

**If a project ever needs it, it saves and restores the content itself, and it can do all of that.**
`get_text()` and `get_cursor()` read the content and the caret before the `hide`, and
`show{text = …, cursor = …}` puts both back; both reads answer `nil` while hidden, so the save
happens before hiding either way. The **content getter is this release's** (2026-09-03, owner:
*"write it as active technical debt to be resolved before release"*) and it was added **because of
this ruling**: the fallback offered here covered the caret and not the text, which made
`doc/input_api.md`'s *"keep it yourself"* advice unfollowable for anything the user had typed. It is
one function, symmetrical with `get_cursor` and useful for more than this — and deliberately **not**
a return to preservation, which is a lifetime rule that would have to interact with the content
baseline in every call that seats it.

**The retirement rests on the scenario, not on the fallback**, which is why closing the gap changes
nothing here: there is no case that needs restoration, and a project that ever meets one now has two
reads and a `show` rather than a rule.

**No CHANGELOG line is owed for this**, unlike the two above. Preservation was never shipped: at the
PR base the widget was rebuilt per activation, so content survived nothing, and this is a design
requirement that was not built rather than a behaviour a user could notice changing. (The getter has
its own `Added` line, as an addition to the surface — that line is the function's, not this
retirement's.)

**Recommended and deliberately not built: `reset()`.** `clear()` resets what the **user** owns.
Nothing resets what the **project** owns, so returning a widget to its defaults means naming every
field with its own falsey value. A `compy.input.reset()` — `configure` with the platform defaults —
completes that symmetry with one verb on each side of the ownership line. It is a public addition
rather than a deletion, so it is **recommended for a later release, not made part of this one**. If
it is built: it must not clear content (that is `clear()`'s job, and doing both would make `clear()`
redundant), and it must state whether the lifecycle callbacks — assignable only on
`compy.input.callbacks` — fall to it, since "configure with defaults" leaves them standing.

## D-AUTO-HIDE — `auto_hide`: the widget hides itself on submit

**Status: SUPERSEDED by `D-LIFECYCLE-FLAGS`, in force nowhere — `FLAGS-01` landed 2026-09-09**
(owner ruling, 2026-08-30; superseded 2026-09-06/07; the code followed on 2026-09-09). `auto_hide`
is **not a key any more**: it left `show`, `configure`, the guide and the CHANGELOG with the sprint,
and `hide_on_submit` is the only name. Three further things below no longer hold: **statement 3**,
*"submit only — cancel is not a close"*, which the cancel hide cell overrules; **statement 5**'s
raise edge — with disposal running before the callbacks, a raising callback leaves the widget
**hidden** rather than standing, taken deliberately (*"let it be, documented"*); and **statement 4's
rationale**, reversed — the widget goes, then the project reacts. **The entry is kept for its
reasoning, not for its rules**: why an implicit hide is worth a key at all, and why the name is a
mode rather than a one-off, are arguments `D-LIFECYCLE-FLAGS` inherits rather than restates.

**Decision.** Five statements, in force together.

1. **`auto_hide` hides the widget after a clean submit**, without the project installing a
   lifecycle callback to do it.
2. **It is an ordinary project-owned setting** — accepted at `show` **and** `configure`, applied
   when given, `false` to unset (D-CFG-BOUNDARY, statement 3), and **persistent until replaced**,
   exactly like `validator`. A later bare `show()` inherits it; **silence is not a disarm**. It is
   not a `show`-only key: that category protects what the **user** owns, and the user does not own
   lifecycle.
3. **Submit only — cancel is not a close.** `cancel_flow` clears and leaves the widget standing
   (D-EDIT-LIFECYCLE), and no reading of this flag changes what Escape does. A project that wants
   Escape to close writes `after_cancel = function() hide() end`, the same one-liner on the other
   channel. **The asymmetry is documented, not hidden**: a project relying on `auto_hide` alone has
   no dismissal path, and its user's Escape clears the content while the widget stays shown.
4. **It composes with `after_submit`; it does not refuse one.** The project's callback runs first
   and the close follows it, so a project can both react to the submission and have the widget go
   down. Refusing the combination would force exactly the boilerplate this key exists to remove.
5. **A raised callback leaves the widget standing.** The error boundary wraps the **route entry**
   (`controller.lua`, `with_canvas_and_errors`), not the chain, so a raise in `on_text_entered`
   already unwinds past `after_submit`; closing anyway would mean a protected call and a re-raise
   inside `submit_flow`, for a case whose first failure is **not** silent — the project suspends
   and its error is reported. The widget's fate matches what the hand-written `after_submit = hide`
   would have done, which is the behaviour this key is sugar for. *A widget standing behind a
   reported error is the smaller of the two failures, not a second one.*

**It replaces `oneshot`.** The API this one supersedes had the same capability under a name no
project could write: `oneshot` was an internal model constructor argument carrying three unrelated
jobs — history suppression, the retired poll event, and a view draw-path switch. What returns is
the **capability**, rebuilt as one project-facing setting that does one thing, and the name went
with the complexity: `oneshot` names a single occurrence while this is a standing mode, so keeping
it would have meant shipping a warning beside it. `auto_hide` matches the surface's own verbs —
`compy.input` has `show` and `hide`, and `close` appears nowhere on it. **The one cost, stated
because someone will hit it:** the developer who asked for this flag asked for `oneshot`, and will
not find that word.

**Why it exists.** The capability **preceded this feature**, so this is a restoration rather than
an invention; and it was **asked for from outside the input work** — by the author of the `serial`
API (owner attestation; that surface is not in this repo, so the request is not checkable here) —
which makes it a request rather than an ergonomic preference of this work's own.

**The one-line question is the case in its own right.** A project whose subject is *not* user input
— a game, a tool, a demo — wants to ask the user something and get on with it. With `auto_hide`
that is a single call carrying a label and a callback, and **no boilerplate at all**: nothing to
install beforehand, nothing to tear down after. Without it the same project must also assign
`after_submit = function() compy.input.hide() end`, a hook that exists purely for its side effect
and that the author has to know to write. **The cost of not having the flag falls hardest on
exactly the projects least equipped to pay it.**

**On counting examples — don't.** In this tree only `turtle` closes on submit, and it keeps an
`after_submit` regardless to re-arm an echo guard, so a census of `src/examples/` scores the flag at
one call saved. That census measures the wrong thing: the shipped examples were written *for* the
API as it stands, and four of them (`valid`, `repl`, `guess`, `balloons`) demonstrate the
repeated-prompting pattern deliberately, which is the pattern `auto_hide` is not for. The evidence
for a convenience is who asks for it and what it costs the project that lacks it.

**No reader, and the general line behind it.** `is_auto_hiding()` and a `config` namespace were
both proposed and refused: disarming is unconditional, so there is nothing to ask before acting.
**A read-only query earns its place when the framework can change the value, not when only the
project can.** That is why `is_shown()` exists — shownness moves for reasons a project cannot
derive — and why this flag has no getter.

**The edge it does not close.** A callback doing `show{force = true, auto_hide = true}` from inside
the submit chain re-arms the flag, and the close belonging to the submit **already in progress**
still fires: the close reads the flag at the END of the submit it is running, not before the
callbacks. Owning the close by the submit that armed it needs a generation token, and that state
was judged not worth it. **The escape is to pass `auto_hide = false` on the follow-up**, or to
re-show after the widget is hidden; `../../input_api.md` says so. Leaving the follow-up plain is not
an escape, because the flag persists (statement 2).

**Consequence.** `show` and `configure` each carry one more key, so the guide, the config-key lists
and `CHANGELOG.md` move with them. Nothing existing changes behaviour: absent the key, submit
behaves exactly as it did.

## D-PAYLOAD-SPLIT — the submit callbacks are told apart by their payload

**Status: RETIRED, replaced by `D-ONE-PAYLOAD` — in force nowhere; `PAYLOAD-01` landed 2026-09-09**
(owner ruling, 2026-09-06; the code followed three days later). The split it decided **does not
exist in the tree**: `after_submit` receives the same string `on_text_entered` does, and the two are
told apart by *when* they run. **The entry is kept for its reasoning, not for its rules** — the
argument about which callback deserves which shape, and the migration analysis that named every
in-tree site, are what the successor inherits rather than restates. Read `D-ONE-PAYLOAD` below for
what is true.

*Prior status, superseded in place: "SUPERSEDED by owner ruling, 2026-09-06 — one payload, and it is
the string. DECIDED, NOT YET IMPLEMENTED", with the note that the body below described the shipped
behaviour until the implementation landed. It has landed; the body below describes nothing that
ships.*

**What the reversal costs, recorded because it was ruled with the cost stated.** The distinction
this decision invented is removed **inside the release that documented it**, so the guide, the
`CHANGELOG` and the off-repo `serial` consumer all migrate a second time. The stakeholder's argument
that carried it is the one this entry could not answer: *"every program-facing consumer wants a
string; only positional plumbing wants lines"*, and `lines[1]` on a string fails **silently** —
which is the same silent-failure class this entry itself identified when it moved the three indexing
examples.

**What separates the two submit callbacks now that the payload does not: *when they run*.**
`on_text_entered` fires first, then `after_submit`, both after validation. That is a weaker
distinction than a payload and the surface reflects it — the simple surface being built in the same
release folds them into one entry point, `compy.on_answer` (the answer plus the disposal), and the
low-level pair remains for a project that needs the two moments apart. **A reader must be able to
state the difference in one sentence**, which was this entry's own test, and after the change the
sentence is about order rather than shape.

*Prior status — implemented* (owner, 2026-08-30; built at `FEAT-01-04`). `T-PLAINTEXT-ENTERED` is
retired. This decision is also the **answer to `FIX-02-01`**, which asked whether the two callbacks
are one thing configured two ways — closed with it, as `FEAT-01-03` required.

**Decision.** `on_text_entered` receives the submitted content as a **single concatenated string**.
`after_submit` receives it as the **list of lines**. Both still fire, in that order, after
validation. The recommended division of labour — *use `on_text_entered` to process the text, use
`after_submit` for everything else* — is a **convention, not an enforcement**: neither callback is
restricted to its recommended use.

**Why.** Today both callbacks receive the identical argument, so the surface offers two names for
one moment and the guide cannot say what distinguishes them. That is the defect `FIX-02-01` names,
and the cheap-looking fix — delete one — costs a real capability, because the two run at different
points of the flow and a project may legitimately want both. Giving them **different payloads**
resolves the redundancy without removing anything: each callback acquires a reason to exist that a
reader can state in one sentence.

The choice of *which* gets the string is not arbitrary. `text` names a text object, so a callback
called `on_text_entered` handing back an array of lines contradicts its own name; and the
concatenation is what consumers do anyway — `repl` writes `print(string.unlines(lines))` and three
more examples take `lines[1]`, which is the same operation for the single-line case they all use.

**Half of this decision is already true.** `after_submit(lines)` is what the submit chain passes
today (`userInputController.lua`, submit flow) and what the guide documents. **The change is
one-sided**: only `on_text_entered`'s payload moves, from the line list to the joined string.

**Consequence, and it is smaller than it looks.** The change is breaking on a documented callback,
so it carries a CHANGELOG entry and a justification-table line. But **not one consumer in this tree
wants the list** — which is the strongest evidence the split is right, and a consumer that does want
it still has `after_submit`. Four of the seven — `maze`'s `submit_program`, `tixy`'s `submit_body`,
`balloons`'s `deliver` and `repl` — call `string.unlines` on the payload as their *first statement*,
which is this decision performed by hand at each call site; the other three (`turtle`, `valid`,
`guess`) take `lines[1]`.

**The migration is not uniform, and the asymmetry runs opposite to the sentence above** (verified in
code at `FEAT-01-03`, 2026-08-30):

- **The four that join keep working untouched.** `string.unlines` is idempotent over a string —
  `string.join` returns its argument unchanged when handed one (`util/string/string.lua`) — so
  `string.unlines(already_joined)` is a no-op. Rewriting them is *clarity* work, which is exactly
  what `FEAT-01-07` weighs example by example, and `wontfix` on any of them costs nothing.
- **The three that index break, and break silently.** `("abc")[1]` is `nil` in Lua, not an error, so
  `turtle` would `eval(nil)`, `valid` `print(nil)` and `guess` `tonumber(nil)`. These are the
  migration, and they land **with** `FEAT-01-04`, not after it.
- **Both separate-repo consumers are in the safe group** (`maze`, `balloons`); all three mandatory
  sites are in-tree. The breaking half of this change therefore needs **no cross-repo coordination**
  — worth knowing before `CHG-01`'s migration note is written for an audience.
- **For those three the payloads are only identical while the input is one line.** Shift+Enter is a
  line feed in any widget, so after the split they receive the whole text where they used to receive
  its first line. Arguably a latent bug fixed rather than a regression, but it is a behaviour change
  on three shipped examples and belongs in the migration note.

---

## D-ONE-PAYLOAD — every content-bearing callback receives the same plain string

**Status: IMPLEMENTED, 2026-09-09 (`PAYLOAD-01`).** Owner ruling, 2026-09-06, on the stakeholders'
proposal block: *"let it be — same payload where reachable, plaintext."* **It retires
`D-PAYLOAD-SPLIT`**, which is kept above for its reasoning and rules nothing. Debt entry:
`../technical_debt/input.md`, `T-ONE-PAYLOAD`, paid.

**Placed here rather than at the end of the ledger**, immediately after the entry it replaces, so a
reader who arrives at the retired decision meets its successor next. That is a departure from the
file's chronological order and it is deliberate.

**Decision.** Five callbacks receive the submitted or drafted content as **one concatenated
string**: `on_text_entered`, `after_submit`, `before_submit`, `before_cancel` and `after_cancel`.
**`validator` and `highlighter` keep the line list** — they are positional plumbing, run per line,
and `LineValidators` reports *which* line failed. There is no other content payload on the widget.

1. **The three guard callbacks gain an argument they never had.** `before_submit`, `before_cancel`
   and `after_cancel` received nothing at all, so **a veto could not look at what it was vetoing** —
   which is the concrete defect the ruling names, and the reason this is not merely a shape change.
   That half is **purely additive**: a callback that ignores its argument loses nothing.
2. **`after_submit` changes shape, and that half is breaking on a documented callback.** It broke
   **silently** where a consumer indexes — `("abc")[1]` is `nil` in Lua, not an error. Measured
   before the change rather than assumed: **not one in-tree consumer reads the payload of any of the
   four**; every example declares its lifecycle callback with no parameter. The migration is the
   off-repo `serial` API's alone, and it is the **second** time that consumer migrates, which the
   owner ruled with the cost stated.
3. **What now separates `on_text_entered` from `after_submit` is *when they run*, not what they
   carry.** `on_text_entered` fires first, both after validation and after disposal. That is a
   weaker distinction than a payload, and the release reflects it rather than hiding it: the simple
   surface folds the pair into one entry point (`D-SIMPLE-SURFACE`, `compy.on_answer`), and the
   precise pair remains for a project that needs the two moments apart.
4. **The payload is read once, above the disposal, on both verbs.** A callback therefore receives
   the content the verb was about even when a lifecycle flag has already emptied the widget
   (`D-LIFECYCLE-FLAGS`, *"Ordering is UNIFORM"*). On the cancel side the single read is also what
   `before_cancel` sees, so a veto and the `after_cancel` that follows a non-veto agree on what the
   draft was.
5. **`before_submit` still runs ahead of the empty guard**, and the model is re-read after it, so a
   `before_submit` that edits the content keeps deciding the submit exactly as it did before. Its
   payload is the draft as it stood when the verb began.

**Why the string and not the list.** The stakeholder's argument is the one `D-PAYLOAD-SPLIT` could
not answer: *every program-facing consumer wants a string; only positional plumbing wants lines*.
The evidence was already in that entry — four of seven in-tree consumers called `string.unlines` on
the payload as their first statement, which is this decision performed by hand at each call site,
and three took `lines[1]`, which is the same operation for the single-line case they all used.

**What it costs, recorded because the ruling was taken with the cost stated.** A distinction this
release invented is removed inside the same release, so the guide, the `CHANGELOG` and the off-repo
consumer all migrate a second time, and `PR-01-02` owes a justification row for it.

---

## D-CONTENT-NORM — content is normalised so the cursor address is unambiguous

**Status: implemented** (owner, 2026-09-01; built at `BUG-02-01`). Ruled while weighing whether
`set_text`'s list branch should split embedded newlines, and stated as the general rule rather than
as that fix, because the rule already governed a behaviour nobody had written down.

**Decision.** Content entering the widget is **normalised before it is stored**, in both spellings of
the documented shape — a string, or a list of line strings. Normalisation is: drop bytes that do not
form valid UTF-8, then split on newlines. `set_text("a\nb")`, `set_text{"a\nb"}` and
`set_text{"a", "b"}` therefore produce identical state. Empty elements are content and survive.
**No line ever contains `\n`.** (`\r` is *not* treated — nothing in the model or the string
utilities mentions it, so `set_text("a\r\nb")` yields `{"a\r", "b"}` and the stray `\r` is counted
as an ordinary column. Pre-existing, unchanged by this decision, and filed as debt; the rule below
is stated over `\n` because that is what the code implements.)

**Why — the cursor.** The widget addresses content as `(line, column)`, and both halves of that
address are only meaningful over normalised content:

- **invalid bytes leave a column's *length* undefined** — `utf8.len` cannot measure the line, so
  there is no last column to clamp to;
- **a newline inside a line leaves a column's *position* undefined** — the caret could sit past a
  line terminator, at a coordinate that names no place a user can see.

This is why the two normalisations are one rule and not two conveniences, and it is the ground the
owner ruled on: *"the key reason is same as for utf-8 sanitization — we need cursor to be set
without ambiguity."* It also settles the shape of the code — **a single storage path preceded by a
normalisation step**, rather than per-spelling branches that each decide what to normalise. Branches
that decide separately drift apart, which is exactly what had happened: UTF-8 was sanitised on both
spellings and newlines on only one.

**Scope: what a project hands the widget.** The rule governs `text` at `show` and the live
`set_text`. It is not a claim about what the widget hands back — the submit payloads are
D-ONE-PAYLOAD's business — nor about `add_text`, which never had the problem: the controller
normalises with `string.unlines` before the model sees it.

**What it does not license.** Normalisation is not validation. A project's content is still its own:
nothing here truncates, escapes or re-flows what is set. The rule removes representations that
cannot be addressed, and nothing else.

**The boundary, stated as the pair it is: normalise representation, refuse structure**
(owner, 2026-09-01). The two are different mistakes and deserve different answers.

- **A representation variance is one value spelled differently** — a string against a list, an
  embedded newline, a byte that is not valid UTF-8. The project meant text and we can tell what
  text. Normalise silently; that is everything above.
- **A structure error is a value that is not text at all** — a number, a boolean, a table where a
  line belongs. **Refused at the project boundary**, with `checked_text` beside `checked_cursor`
  (`consoleController.lua`), raising `compy.input.set_text: text must be a string or a list of line
  strings` under the name of the call that failed.

Coercing the second would be tolerance producing a lie. **The contract is documented and closed,
so a value outside it can only be a mistake** — and rendering `42` as a visible line hides that
mistake behind content that looks deliberate. A project that genuinely has a number and wants it
shown converts it itself, which costs one `tostring` and says what was meant. **Tolerance is for
input we can read; it is not for input we would have to guess at.**

*(An earlier variant of this paragraph argued instead that `{"a", 42}` is the argument shape of
`UserInputModel:insert_text_line(text, li)`, so such a list most likely comes from confusing two
functions. That reasoning does not hold and is recorded as withdrawn rather than quietly dropped:
`insert_text_line` is a model method, absent from `compy.input` and from this guide, and
unreachable from a project's sandbox — nobody can confuse `set_text` with a function they cannot
see or call. The conclusion survives on the closed-contract argument above, which needs no such
story.)*

This settles `text` the same way `BUG-01-08` settled `cursor`: a malformed value earns **one**
message naming the call and the expected shape, rather than a raw Lua error from inside the
framework or a silent repair. **It settles those two keys and no others** — `show{validator = 42}`
and `show{on_text_entered = 42}` are still accepted and still fail later at
`userInputController.lua` with a raw `attempt to call` error.

**And it settles exactly the right two, which is not a coincidence and is no longer left open**
(owner ruling, 2026-09-01). `text` and `cursor` are the **user's content**; every other key is
**project-owned** — D-CFG-BOUNDARY's line, the same one that decides what `configure` may touch. The
two classes fail differently and so are treated differently: *pass a wrong `text` and you confuse
the **user**, who did not write it and cannot fix it; pass a wrong `validator` and you confuse
**yourself**, in your own code, with a raise that names `validator` — the very key you set.* The
first must be refused at the door; the second is self-diagnosing, so loud-and-late is an acceptable
answer where silent was not. Extending the treatment to the callable keys is therefore **ruled
against, not merely unscheduled**: *"I'd just not enroll too much input checking ceremony beyond
necessary. its edu project, not space rocket navigation."* Retired in
`../technical_debt/input.md`, *"The callable config keys are unchecked"*.

**Consequence.** No public surface changes, and no capability of the documented shape is removed:
the state normalisation eliminates — a line holding a raw newline — could not be produced by typing
or by pasting, and reached one documented shape through one call while rendering wrong in both draw
paths. It **was** observable, and the earlier claim here that it "could not be read back at all" was
too strong (corrected 2026-09-01 by cold peer review): the `compy.input` surface has no content
*getter*, so no set/get round-trip is affected, but `after_submit` received the line list itself
(D-PAYLOAD-SPLIT, retired by D-ONE-PAYLOAD on 2026-09-09 — it is the joined string now), so a
project could see the difference at submit and will now see something else.
That is exactly why the change carries a `CHANGELOG.md` line. The behaviour change is
recorded in `CHANGELOG.md`, stated for a project author in `../../input_api.md`
(*"Live changes"*), and described for a maintainer in `../internals/user_input.md`
(*"Multiline input"*).

**One fossil retired with it.** `set_text`'s string branch called `_update_cursor(true)` and the list
branch did not — an asymmetry inherited from the commit that first wrote the function, where
`jump_end()` already ran unconditionally afterwards and overwrote its result. The call had therefore
never had an effect on this path, which is why the branch lacking it behaved identically and nobody
noticed. It is deleted rather than copied to the other branch: the unified path ends by seating the
cursor deliberately (`jump_end`, or `_clamp_cursor_pos` under `keep_cursor`), and one seat is the
point.

`_update_cursor` itself is left in place — **but it is not sound, and this decision does not
ratify it.** Its intent is this decision's own: *seat the caret at the end of the content*, which is
what it did correctly when the input was single-line. The multiline migration broke it, and what it
owes is filed as debt, not settled here. See `../technical_debt/input.md`, *"`_update_cursor`
measures the column on the wrong line"*.

---

## D-LIFECYCLE-FLAGS — four flags, one per (verb × outcome); they supersede `auto_hide`

**Status: IMPLEMENTED, 2026-09-09 (`FLAGS-01`). The holistic pass RAN before it and the matrix
survived — widened, not reshaped** (owner rulings, 2026-09-06/07).

**What the implementation added to the design, and it is one thing:** *how* an owner seats its
cells was deliberately left open here, and it is `UserInputController:seat_lifecycle(flags)`, a
chained method in the shape of `always_shown()`. Constructor arguments were the idiom this entry
gestured at and they do not extend — two are positional already, and four more would put the
constructor at seven against `agents/rules.md`'s limit of four. The seating is the same write
`configure_core` makes, so an owner's defaults and a project's `show` cannot drift apart.

**The nine acceptance criteria hold**; the cases are in `tests/input/`, chiefly
`input_widget_callbacks_spec.lua`'s *"the lifecycle flags"*, with the editor's half in
`input_editor_keys_spec.lua` and the class default pinned against a bare widget rather than
inferred from a host. Criterion 7's *"the `auto_hide` cases migrate"* is done by migration and not
by deletion: every property that entry pinned — persistence, `false` as the unset, `configure` as
an entry point, the successful-submit edge — is pinned on `hide_on_submit` today, and criterion 5's
alias case is **not** among them, because the alias was pulled before the sprint ran.

**Three things the pass settled, and they change this entry rather than merely confirming it.**

1. **The four cells stand, and they answer three proposals rather than two.** The owner's ruling is
   *"configured via 4 flags as project sees fit"*, and it covers the **re-show** proposal as well —
   which statement 1 below explicitly excludes. The mechanism: **if destruction is only ever
   flag-driven at a verb, activation has no reason to clear**, so `show()` and `show{}` need not
   differ, and the proposal's own *"semantically inobvious"* dissent never has to be answered.
   Statement 1's parenthesis is therefore **too narrow** — the matrix does not answer the re-show
   question *directly*, it removes the need for it, which is a stronger result and the reason the
   taxonomy is justified at four cells rather than two.
2. **The defaults are the stakeholder's, and that is a ruling on the product, not on the
   mechanism** (owner, 2026-09-07): *"@dsent requests for behaviours are authoritative, we support
   them via defaults."* So the **project widget** seats `clear_on_submit` **on**, `hide_on_cancel`
   **on** and `clear_on_cancel` **off** — submit consumes the content, cancel preserves it and takes
   the widget down. This **replaces the seating in statement 3**, which preserved today's behaviour
   while the question was open. The class default (all four off, an unconfigured widget inert) is
   unchanged and is a different sense of the word.
   **AMENDED 2026-09-09 — the cancel half of this is reversed.** The stakeholder's requested
   behaviour is still authoritative *as a behaviour*; what changed is that **supporting it via a
   default** was measured and found to strand five example programs, so it is supported via one
   documented line of `configure` instead. `hide_on_cancel` is **not** seated. The rest of this
   point stands, and the reasoning is in statement 3's *"least-destructive basis"* paragraph.
3. **One acceptance criterion inverts with it — see criterion 4**, which was written to *preserve*
   `after_cancel` seeing an empty widget. Under the ruled seating it sees the draft. *(Still true
   after the 2026-09-09 amendment, and for a plainer reason: cancel seats no cell, so there is
   nothing to empty the widget before the callback runs.)*

**The mechanical question point 1 rests on is now RULED (owner, 2026-09-07):** *"we do not need to
hardcode any implicit destructive behavior into `show`."* `D-CFG-BOUNDARY` statement 1 is amended —
activation no longer clears when `text` is absent — so **destruction has exactly one home, and it is
this matrix**. The code still clears (`reset_content`), and that gap is
`../technical_debt/input.md`, `T-SHOW-DESTROYS`.
The implementation is registered as active debt with a roadmap sprint — `../technical_debt/input.md`,
`T-LIFECYCLE-FLAGS`. Until it lands, `D-AUTO-HIDE` describes the shipped behaviour and this entry
describes the target.

**The third clause is the owner's and it qualified the first two — the pass it waited for has now
run, and the status block above carries its result.** This entry was derived
**mid-session from two proposal bullets** (#3 and #4) while the question being answered was a
different one; the holistic reading of the whole proposal block — the step that decides what the
release absorbs — **had not happened and now runs first**. The owner's words: *"FLAGS just is based
on partial answer figured out on the spot."* So the matrix may survive that pass unchanged, be
widened, or be reshaped, and **it does not constrain the pass by having been written first.** What
is settled is the *shape of the question* — lifecycle outcomes are per-(verb × outcome) settings
rather than callbacks — not the final inventory of cells or their defaults.

**Decision.** The widget's two lifecycle verbs have two possible outcomes each, and the four
combinations are **four independent, project-owned boolean settings**:

|  | **hide** | **clear** |
|---|---|---|
| **submit** | `hide_on_submit` | `clear_on_submit` |
| **cancel** | `hide_on_cancel` | `clear_on_cancel` |

1. **The space is (verb × outcome), and it was always four cells.** The shipped API covered two of
   them by unrelated means — `auto_hide` was `hide_on_submit` under another name, and cancel's clear
   was **hardwired inside `cancel_flow`** rather than being a setting at all. The two empty cells
   are exactly what the stakeholders' proposals ask for: #3 *"Submit clears the field by default"*
   is `clear_on_submit`, and #4 *"Escape hides, and does not clear"* is `hide_on_cancel` with
   `clear_on_cancel` off. **Naming the matrix turns two proposal bullets into a choice of booleans
   rather than two separate surface additions**, which is what a holistic pass is for. ***Superseded parenthesis, kept because the status block at the head of this entry argues against
   it and a reader needs the text it argues with:*** *"Two, not three. Proposal #5 — `show()` versus
   `show{...}` — is about what a re-show inherits, not about what a verb leaves behind, and this
   matrix does not answer it; `D-CFG-BOUNDARY` statement 1 governs that question instead."* **It is
   three, not two** — the matrix does not answer the re-show question *directly*, it removes the need
   for it, and `D-CFG-BOUNDARY` statement 1 was amended on 2026-09-07 to make that true.
2. **They are ordinary project-owned settings**, on `D-AUTO-HIDE`'s statement 2 unchanged: accepted
   at `show` **and** `configure`, applied when given, `false` to unset (`D-CFG-BOUNDARY`), and
   **persistent until replaced**. Silence is not a disarm. They are not `show`-only keys — that
   category protects what the **user** owns, and the user does not own lifecycle.
3. **The class default is OFF for all four**, so a widget that sets no flags and no callbacks
   **does nothing at all** on Enter or Escape. This is the property `D-EDIT-LIFECYCLE` already
   claimed and did not have (statement 6), and making it the base case is the point of this entry as
   much as the four names are. **Each owner then seats its own** — these are two different senses of
   "default" and the entry keeps them apart:
   - **the editor seats none**, so it is inert on both verbs;
   - **the console seats `clear_on_cancel`**, which is exactly what it does today;
   - **the project widget seats `clear_on_submit` and NOTHING on the cancel side** — **owner
     ruling, 2026-09-09**, on the least-destructive basis; see the paragraph below, which is where
     that basis is argued. Submit consumes the content, because a project processes a submission
     through its callbacks and the next entry starts empty; **Escape is a no-op unless the project
     asks for an outcome.** **This is a change to documented behaviour, deliberately made**: the
     guide's *"Submit lifecycle"* and `../../../CHANGELOG.md` describe a different pairing, so the
     change carries its own guide edit, changelog line and justification row rather than arriving
     silently. *(Prior seatings, both superseded: `clear_on_cancel` alone, which preserved the
     shipped contract while the question was open; then `clear_on_submit` + `hide_on_cancel`, the
     2026-09-07 ruling that took the stakeholders' requested behaviours as the defaults — reversed
     on the cancel side two days later, by the evidence below.)*

   **The least-destructive basis, and it is a ruling about how a DEFAULT is chosen** (owner,
   2026-09-09). A default is not settled by which behaviour is most wanted; it is settled by
   **which behaviour is safe to be wrong about**. Seating a cell destroys something — content, or
   the surface itself — on behalf of a project that never asked, and a project cannot un-ask
   before the first Escape reaches it. Seating nothing costs a project one line of `configure`.
   The two errors are not the same size, so the empty cell wins ties.

   **This was ruled on measured evidence, not on principle alone.** `hide_on_cancel` shipped as a
   seated default on 2026-09-09 and the consumer sweep the next sprint ran found **five example
   programs stranded by it** — `guess`, `tixy`, `repl`, `valid` and `balloons` each show the
   widget once, at load, with no re-show path, so one Escape ended the program's only input
   surface for the rest of the run (`../technical_debt/input.md`,
   `T-EXAMPLES-PREDATE-THE-FLAGS`; the per-example table is
   [`../wip/77-new-input-api/validation/notes/S86-example-lifecycle-needs.md`](../wip/77-new-input-api/validation/notes/S86-example-lifecycle-needs.md),
   which dies with that tree). Reading down its cancel column: **not one example asked for
   `hide_on_cancel`**, one needs cancel not to destroy, one relied on the older clear, and five say
   nothing at all. A default that no consumer wants and that five cannot recover from is the
   definition of the wrong side of this trade.

   **Cancel therefore has no shipped outcome at all** — `hide_on_cancel = false` and
   `clear_on_cancel = false` — which makes Escape's behaviour **fully opt-in** and, because these
   are ordinary settings, **re-bindable per project**. It is also the reading that costs the
   product nothing: a project that wants the stakeholders' *"Escape hides, and does not clear"*
   writes one line for it, and that line is visible in its source where a seated default is not.

   **The recommended way to ask, and it is now the guide's:** call `configure` **once, before the
   first `show`**, one flag per line —

   ```lua
   compy.input.configure{ hide_on_cancel = true }
   compy.input.configure{ clear_on_submit = false }
   compy.input.show{ prompt = 'name?' }
   ```

   The flags are persistent until replaced (statement 2), so this reads as *"set the defaults for
   this program"* rather than as configuration of one prompt — which is exactly what it is. Passing
   them on `show` stays legal and is what a genuinely per-prompt outcome should use.

   *Seating is per instance, as `disable_selection` and `allow_duplicate_line` already are. **How**
   it is passed is an implementation choice and deliberately not fixed here — those two are
   positional constructor arguments, and four more would put the constructor at seven against
   `agents/rules.md`'s limit of four, so the implementation owes a different carrier.*
4. **`clear` means `model:cancel()`'s existing semantics — remember, then clear** — on **both**
   verbs. `cancel()` is `handle(false)` → `_remember()` when the text is non-empty → `reset()` →
   `clear_input()`, so the abandoned text reaches the input history before the line is emptied. That
   history push is a real behaviour the console depends on, and a flag named *clear* must not
   silently drop it. **`clear_on_submit` therefore also remembers** — which is the behaviour a
   console-like prompt wants, and is why it is one operation and not two.
   **It is NOT `compy.input.clear()`**: that call is `clear_input` + `clear_error` and does **not**
   touch history. Two operations, one English word, and the surface keeps both — so any prose
   naming a flag must say which.
5. **`auto_hide` is superseded by `hide_on_submit`** — and as built, the old name is gone
   entirely; the paragraph below records the reasoning that got there. *Both names are accepted for one release, the
   alias resolving to the flag, and **when both are given the explicit `hide_on_submit` wins.**
   **The compatibility argument is weaker than it looks and is stated honestly:** nothing has
   shipped — `../../../CHANGELOG.md` has only a `CURRENT_SCOPE` section and no released one — so
   within *this* repository a hard rename would break nothing. What the alias protects is the
   off-repo consumer `D-AUTO-HIDE` records under *"Why it exists"* (the `serial` API's author, an
   owner attestation about a surface not in this repository and therefore **not checkable here**).
   **Removal trigger, single and explicit:** the owner confirms no consumer writes `auto_hide`.
   Absent that confirmation it is carried, and it costs one alias.
   **PULLED 2026-09-06, on an assumption rather than a confirmation, and the distinction is the
   point.** Asked whether anything off-repo writes the key, the owner answered *"lets assume not
   yet"* — so **the alias is not carried and `hide_on_submit` ships as the only name**. This is
   deliberately recorded as weaker than the trigger's own wording: nobody checked the `serial` API,
   because it is not in this repository and cannot be checked from here. What makes the assumption
   safe to act on is the same arithmetic that made the compatibility argument weak — **no released
   consumer can write a key that no release ever contained**, and shipping a name deprecated on the
   day it first appears is the *"merely more elaborate"* half of the strategic frame. **If the
   `serial` API's author says otherwise, this reverts to the alias**, and that is a change to one
   statement rather than to the design.*
6. **This supersedes `D-AUTO-HIDE` and amends `D-EDIT-LIFECYCLE`.** `D-AUTO-HIDE`'s statement 3
   (*"Submit only — cancel is not a close"*) is **overruled**: cancel gains a hide cell, which is
   what proposal #4 asks for. `D-EDIT-LIFECYCLE`'s *"the console sets no lifecycle callbacks so its
   flows are no-ops"* was false while the clear was hardwired — a defect rather than a design
   change, `T-NO-CALLBACKS-IS-NOT-A-NOOP` — and **making it flag-driven did not make it true**:
   the console seats `clear_on_cancel`, so its Escape still clears, by its own request. The
   sentence was corrected rather than fulfilled when this landed (2026-09-09); what became true is
   the class default it was reaching for — **an instance that seats nothing does nothing**.

**Composition with callbacks: flags do not refuse a callback and a callback does not refuse a flag.
`before_*` vetoes the whole flow — every flag-driven outcome and the `after_*` with it.** **A raised
callback now leaves the widget HIDDEN, not standing** — disposal runs before the callbacks
(2026-09-07), so the raise no longer unwinds past a trailing `hide`. The owner took that inversion
deliberately (*"let it be, documented"*): *"the failure worth seeing"* is the project suspending with
the error, which the reorder does not touch. **`D-AUTO-HIDE`'s statement 5 is superseded on this
point**, and the guide sentence that states it is rewritten by the sprint.

**Ordering is UNIFORM: dispose, then notify — owner ruling, 2026-09-07.** Both flags of a verb act
**before** that verb's callbacks.

| flow | order |
|---|---|
| **submit** | `before_submit` veto → empty guard → validate → **`clear_on_submit`, then `hide_on_submit`** → `on_text_entered` → `after_submit` |
| **cancel** | `before_cancel` veto → **`clear_on_cancel`, then `hide_on_cancel`** → `after_cancel` |

**Why the ruling, and it fixes a defect class rather than tidying a table.** Post-callback disposal
makes the flow act on **whatever widget state the callback left behind**, and the callback is
entitled to leave behind a *new question*. The stakeholders' own simple-surface idiom is exactly
that — *"if editing should be continued for whatever reason, `compy.ask` should be called again from
that callback"* — so the closing `hide` takes down the question the callback just asked. The shipped
surface handles this by **pushing the burden onto the caller** (`../../input_api.md`, *"Asking one
question"*: a follow-up needs `force = true` **and** must disarm the flag, or it *"is closed straight
away, before the user can type into it"*), and a wrapper that seats the flags itself cannot pass
that burden on.

**And the same-day amendment to `D-CFG-BOUNDARY` statement 1 turns the other flag into the same
defect.** Now that activation no longer clears, a **post-callback `clear_on_submit` would wipe the
content the follow-up `show` just seated** — the hide bug with a different flag. Both flags,
therefore, and not just the hide.

**Acting before the callbacks removes the class rather than guarding it.** Nothing draws between the
two, so the ordering is **invisible to the user** and visible only to code; and the callbacks do not
lose the content, because it reaches them **as their argument** (`D-ONE-PAYLOAD` gives every
content-bearing callback the string). *(A generation counter over the activation
was considered and is strictly worse: it guards the symptom, keeps the asymmetric table, and leaves
the guide's disarm paragraph standing.)*

**Three consequences, stated because each overturns something written down.**

1. **`after_submit` no longer sees the content *in the widget*.** It receives it as an argument. The
   guide's *"the widget is still live while it does, so it can read or clear the text"* inverts, and
   the four examples that hand-write `compy.input.clear()` there become redundant rather than wrong.
2. **`D-AUTO-HIDE`'s statement 4 rationale is overturned** — *"the project reacts, then the widget
   goes"* becomes *the widget goes, then the project reacts*. That argument was about code order, not
   about anything a user can see.
3. **The raise edge inverts, and the inversion is ACCEPTED (owner, 2026-09-07: *"let it be,
   documented"*).** Today a callback that raises leaves the widget **standing**, because the raise
   unwinds past the trailing `hide` (`D-AUTO-HIDE`, statement 5; the guide says *"If one of your
   callbacks raises, the widget stays shown"*). With disposal first, **a raising callback leaves the
   widget hidden**. It was put to the owner as a re-ruling rather than inherited silently, and the
   answer is to take it and say so — *"the failure worth seeing"* is the project suspending with the
   error, which the reorder does not touch; the widget's remaining on screen was never what carried
   it. **`D-AUTO-HIDE` statement 5 is superseded on this point, and the guide's bullet is rewritten
   by `FLAGS-01-04`**, not left to be discovered.

***Prior framing — the asymmetry the 2026-09-07 ruling replaced.* It was deliberate and it was a
preservation, and it is kept because it records what the shipped code does until the sprint lands,
and because its final paragraph is the reason the uniform order goes *dispose-first* rather than
*notify-first*: generalising submit's old ordering to cancel would have handed `after_cancel` the
draft, and the ruling generalises the other way.** `submit_flow` reads
`auto_hide` **after** the callbacks (and `D-AUTO-HIDE`'s statement 4 argues why: the project reacts,
then the widget goes). `cancel_flow` clears **before** `after_cancel`, and that ordering is a
**documented contract** — `../../input_api.md`, *"Submit lifecycle"*: *"Otherwise it clears the text
and calls `after_cancel()`"* — so `after_cancel` sees an **empty** widget and always has.
**Generalising submit's ordering to cancel would silently hand `after_cancel` the draft instead**,
which is a behaviour change to a documented contract that no test would catch, because the pinned
cases assert callback *order* rather than what the widget *contains*. *(An earlier draft of this
entry did exactly that, in a sentence claiming composition was unchanged. Caught by this decision's
cold review; recorded rather than quietly repaired, because the failure is the interesting part.)*

***Prior framing, superseded 2026-09-07 by the uniform dispose-then-notify order — `hide_on_cancel`
now runs BEFORE `after_cancel`, with the rest of its verb's disposal.*** It read: *"`hide_on_cancel`
goes last, after `after_cancel`, matching submit's 'the project reacts, then the widget goes' — it is
a new cell, so it has no shipped order to preserve, and the parallel is the reason to put it
there."* **The parallel it invoked is exactly what the ruling reversed**, on both verbs and for the
reason stated in the ordering section: a callback is entitled to leave a new question behind, and a
trailing hide takes it down.

**A veto skips everything the flow would have done**, including `after_*`. That is what the code
does today (`cancel_flow` returns on a truthy `before_cancel`) and it is stated here because
`D-EDIT-LIFECYCLE`'s *"a truthy return skips the step it guards"* reads as skipping only the
destruction. **That sentence is wrong about the shipped code**, independently of this decision, and
`FLAGS-01-04` corrects it.

**Why flags rather than callbacks for the destruction.** Expressing the clear as a *default
callback* was considered and rejected: today `after_cancel` is **additional** to the clear, so a
project that sets one still gets clearing. If the clear became the default `after_cancel`, a project
setting its own would **silently lose** it — the same call, a different outcome, no error. That is
the exact failure class this subsystem has now been bitten by twice, and keeping callbacks purely
additive is worth one more setting.

**Acceptance criteria** — the sprint is not done until all nine hold:

1. **The editor's Escape matches #45's expectations** (owner, 2026-09-06). Bare Escape in
   navigation and in editing does **nothing**, per the routing contract **Vadim1987 attested on
   2026-09-06** for his own tree, by probing it rather than reading it; `Shift+Esc` is unaffected
   and still never reaches the widget. The contract is `D-EDITOR-KEYS`, which states it in full.
2. **The edit-mode half of AC1 is a fix, and it must be pinned as one.** Today bare Escape in the
   editor's **edit** mode empties the block the user opened, in place, while staying in edit mode —
   probed 2026-09-06, and it is data loss on the primary editing path rather than the harmless
   clear of an empty line that `T-NAV-ESCAPE` describes for navigation. **A breaking test asserting
   the block's CONTENT survives** — not which callback fired — is the criterion; the existing pins
   assert callback order and would stay green through this defect.
3. **A widget with no flags and no callbacks is inert** on both verbs — statement 3's class default,
   tested directly rather than inferred from a host's behaviour.
4. **Ordering is pinned per cell**, against the table above **as amended 2026-09-07 — disposal runs
   before the verb's callbacks, on both verbs.** So: a callback sees the widget **after** its flags
   have acted, and receives the content **as its argument** rather than by reading the widget;
   `after_cancel` sees an **empty** widget wherever `clear_on_cancel` is seated (the console) and the
   **draft** where it is not (the project widget, under the ruled defaults). **A test that asserts
   only callback order does not satisfy this** — it must assert what the widget contains when each
   callback runs, **and one case must pin the re-ask**: a `show` issued from inside a callback
   survives the flow that called it.
   **On the project widget this criterion INVERTS under the 2026-09-07 seating**: `clear_on_cancel`
   is not seated there, so `after_cancel` sees **the draft**, and the case pinning it must say so.
   *(This criterion was originally written as a preservation of the shipped contract — `after_cancel`
   always sees empty. That contract is what the ruled default removes, and the criterion is kept
   rather than deleted because the console still holds the preserved half. Read as written, it would
   have pinned exactly the behaviour the release retires.)*
5. **The console's Escape is unchanged** — remember-then-clear, now because `clear_on_cancel` is
   seated on its instance rather than because the widget destroys unconditionally.
6. **The project surface's documented behaviour CHANGES, and the second branch of this criterion is
   the live one** (owner, 2026-09-07): the change is recorded in `../../input_api.md` **and**
   `../../../CHANGELOG.md`, with a justification-table row, for **both** verbs — submit now clears,
   cancel now hides and keeps. *(The first branch — preserve it by seating `clear_on_cancel` — was
   the live one while the proposals were unruled.)*
7. **The four cells are independently settable and independently tested**, each **through
   `configure` as well as `show`**, with `false` unsetting and the setting persisting across a bare
   `show()` (statement 2, `D-CFG-BOUNDARY`). The `auto_hide` cases migrate with the suite arithmetic
   stated, and one case pins the alias resolving to `hide_on_submit`.
8. **A `before_*` veto skips the flow entirely**, `after_*` included — the composition section
   above, pinned rather than assumed.
9. **`hide()` still fires no cancel flow** (`D-EDIT-LIFECYCLE`) — a flag-driven hide is an outcome
   of a flow, never an entry into one, and the two must not become mutually recursive. Note that
   `hide_on_*` is **inert on an `always_shown` widget**, since `hide()` declines there; that is
   correct and is not a cell to special-case.

**What the matrix deliberately cannot express.** `hide` is an **outcome** here and never a verb, so
there is no *clear-on-hide* cell — the stakeholders' own alternative in the same proposals block
(*"bind auto-clear on hide"*) is **not** expressible in this shape. That is a real narrowing and it
is chosen: `hide()` fires no flow (AC9), so hanging destruction off it would make a state flip into
a lifecycle entry, which is the coupling `D-EDIT-LIFECYCLE` exists to prevent. **A project wanting
that composes it — `get_text()` before `hide()`** — which is what the guide already advises.

**What this no longer leaves open — the defaults are RULED (owner, 2026-09-07).** Which defaults the
**project** widget carries — whether submit clears (#3) and whether cancel hides rather than clears
(#4) — was `PROP-01`'s to rule, and it ruled **both in**, on the stakeholders' authority over
product behaviour. This entry did what it was built to do: the ruling was **a choice of booleans
rather than a redesign**, and the pass that took it was free to find four cells the wrong count and
found them the right one — covering a third proposal the entry had excluded. *(Statement 1's
parenthesis is the excluded one; see the status block at the top, which is where the correction
lives.)*

---

## D-EDITOR-KEYS — the editor's key contract is the product's, and this is the record of it

**Status: RETROFITTED, 2026-09-06.** This entry records a design that was decided and built outside
this ledger, and it exists because we were reasoning about those keys without a written statement of
what they are supposed to do. **Nothing here is a new ruling of ours.**

**Authority, and the rationale this entry deliberately does not carry.** The contract is
**@dsent's** — the product owner — decided and authorized by them on **UX grounds, whose details are
not reproduced here**. That omission is the point rather than a gap: the argument is a product
argument about how the editor should feel to use, it was not made to us, and a second-hand paraphrase
in our ledger would become the thing later readers cite instead of the source. What this entry
carries is **what the keys do** and **who owns the answer**. The implementation was attested on
2026-09-06 by **Vadim1987**, author of the editor rework, who probed his own tree rather than reading
it.

**The contract.**

| key | in the editor |
|---|---|
| `Shift+Esc` | **always consumed** — leave, and discard. *(Remark, 2026-09-09 — de facto, verified in `editorController.lua`: the four states that claim bare Escape below claim it **regardless of modifiers**, so in a confirmation dialog, over an error message, in a block reorder and in search, `Shift+Esc` does what bare Escape does. It is still **consumed**; what it is not is leave-and-discard. That meaning belongs to navigation and editing — the two modes where bare Escape is silent. The two rows therefore dovetail rather than conflict: **Escape's four states are exactly the states this row's second clause does not apply in**. Owner ruling: a harmless overlook in the statement, corrected in place.)* |
| bare `Escape` | **consumed in exactly four states**: dismissing an error, cancelling a confirmation dialog, cancelling a block reorder, and closing search. In navigation and in editing it does **nothing** |
| `Ctrl+S` | **not the editor's** — reserved at application level, where the reservation runs **before** the route and does **not consume** (`D-RESERVE-TABLE`). So the key *does* reach the editor controller, which does not claim it — the rework's checkpoint is `Ctrl+K` (`../technical_debt/input.md`, `T-CTRL-S-UNCLAIMED`) — and it falls through to the widget, which has no binding for it. Nothing happens: ***not the editor's* is about claim, not about reach** |
| `Ctrl+Shift+S` | **not in the editor's own spec** — an inherited binding this branch **re-expresses in `EditorController:_leave_keys`** (statement 3), whose effect is the console's `finish_edit`. It is not in the reservation table at all, so *"application level"* describes where the **effect** lives, not the binding. **Leaves the editor without writing an open changed block** (statement 6) |
| `Ctrl+T` | **not the editor's** — the application's run/editor quickswitch. In `nav` or `edit` it leaves the editor **and starts the project run**. With a changed block open it first asks `Shift+Esc`'s discard question; confirming discards the change and takes the exit (statement 6) |

1. **Bare Escape is silent in both main modes**, and this is the row with teeth. It binds **our**
   tree, not only the editor's own code: a key the contract says is silent must be silent **after
   routing**, whichever component would otherwise consume it. **Ours honours it since 2026-09-09**
   (`FLAGS-01`, `D-LIFECYCLE-FLAGS`): the key is still unclaimed and still reaches the widget's
   `cancel_flow`, and the flow now does nothing there, because the editor's widget seats no
   lifecycle flags. *Prior state — it violated the row in both modes, clearing in navigation and
   emptying the open block in editing (`../technical_debt/input.md`, `T-NAV-ESCAPE`).* **Silence is
   achieved by the widget's own inertness rather than by the editor consuming the key**, which is
   what keeps the fix inside this feature's code and out of the editor's.
2. **Leaving and discarding are always `Shift+Esc`.** There is no second way out that the contract
   recognises, which is what makes an unrecognised one worth finding rather than preserving.
   **Two were found and are now named — see statement 6**, which amends this one: `Shift+Esc`
   remains the only *guarded* way out, and it is no longer the only one that exists.
3. **`Ctrl+S` and `Ctrl+Shift+S` are above the editor**, so neither is the editor's to define and
   neither is ours to re-express at route level. We do re-express the second one
   (`../technical_debt/input.md`, `T-LEAVE-KEYS-LOSES-BLOCK`), and it reaches a path with no
   acceptance step, so it loses an open changed block. The chord ships **deprecated** by owner
   ruling, **and the loss is now RULED — it ships, documented** (2026-09-07; statement 6, which also
   names the second exit this statement does not: `Ctrl+T`).
4. **What this does not decide.** @dsent has stated a **direction of travel** for the keymap —
   collapsing the exits onto `Ctrl+D`, dropping `Ctrl+Q`, and moving plain `Escape` into
   `Shift+Esc`'s role with confirmation before anything destructive. **That is stated intent and is
   not ratified here.** It is implemented nowhere today and it postdates both the rework and this
   feature. This entry ratifies the contract **as it stands**; adopting the redesign is a separate
   decision, and the release does not take it.
5. **Ratifying a behaviour does not test it.** **Measured 2026-09-09** (`EDKEYS-01`): every row is
   now pinned, and the net is `tests/input/input_editor_keys_spec.lua` plus the cases it cites in
   `tests/editor/editor_spec.lua` and `tests/input/input_widget_callbacks_spec.lua`. **Its two
   FLIP cases inverted on 2026-09-09, as they were written to**: the editing half now asserts the
   open block survives bare Escape (the breaking test for that data loss), and the navigation half
   asserts the flow is still reached and destroys nothing. *Prior state: both asserted this
   contract's opposite on purpose, because the tree violated row 2 in both modes.* *Prior state, and the reason the
   entry existed: which of these rows the suite actually pinned was **unmeasured**, and the
   measurement was owed rather than assumed* — `../technical_debt/input.md`, `T-KEYS-UNPINNED`. A contract recorded and unpinned is how the last one was lost: the exclusion
   upstream expressed as code, this branch re-expressed as an expectation, and **an expectation
   cannot fail**.

6. **Two exits are historically unguarded, and the release ships them that way** (owner ruling,
   2026-09-07, at `OP-04`: *"ship both, document the defect"*).

   **AMENDED 2026-09-30: `Ctrl+T` is guarded, and so are the gate's project chords.** With a changed
   block open, `Ctrl+T`, `Ctrl+Q`, `Ctrl+Shift+R` and `Ctrl+Alt+R` ask `Shift+Esc`'s own question
   (`EditorController:ask_to_leave`); Enter or Space discards the change as `Shift+Esc` does and
   takes the exit, anything else keeps the block open. No key and no dialog is added: this is the
   *editor-side `request_leave`* named below. `Ctrl+Shift+S` alone still leaves without asking. The
   pinned case is now *"Ctrl+T asks before it drops a changed block"*, with the four chords under
   *"the project exits ask first"*. What follows is the entry as ruled.

   **NARROWER THAN THE CODE, and the gap is recorded rather than ruled** (found the same day, after
   this statement was written): *"two exits"* is exact **about exits**, and a **third** path loses a
   draft without leaving the editor at all — `Ctrl+J` is not mode gated, so it can move the mode to
   `nav` out from under a live draft, after which `Shift+Esc` meets `discard_edit`'s
   `mode ~= 'edit'` early return and discards without asking. It is **inherited and present at
   #45's tip**, so parity and the ruling above are untouched. **Widening this statement is the
   owner's call**; `../technical_debt/input.md`, `T-EXITS-BYPASS-GUARD` carries the analysis and the
   category question it raises — *a guard keyed on `mode` assumes mode changes imply the draft was
   dealt with, and `open()` breaks that.* **`Ctrl+Shift+S` and `Ctrl+T` both
   reach `ConsoleController:finish_edit()`, which stores the clipboard and drops the buffers with no
   acceptance step**, so an open, modified block is lost silently. This **amends statement 2**: the
   contract recognises one way out, and two others exist and are now named here rather than left to
   be rediscovered.

   **Neither is new and neither is ours.** Both are at the PR base; `Ctrl+T`'s editor arm is
   byte-identical across the #45 import, and #45's only change to the `Ctrl+S` block was to remove
   *bare* `Ctrl+S`, leaving the `Shift` leave standing. **What this branch changed is the layer** —
   `Ctrl+Shift+S` re-expressed at route level as `_leave_keys`, `Ctrl+T` as a `RESERVED` entry — and
   re-homing a binding is adopting it, which is why they are named in our contract at all.

   **Why they ship.** At #45's own tip both doors lose the block, so shipping them is **exact parity
   with #45**, which is the standing requirement; adding an acceptance step would be a deliberate
   divergence, and it is a contract change across three call sites in a pre-existing path. The loss
   is therefore **knowingly shipped and documented**, not overlooked.

   **The recommended fix, for the future rather than this release.** #45 already built the policy
   one level down — `discard_edit` asks before losing a draft, `accept_block` refuses to read a
   failed write as accepted — and routed its own `Shift+Esc` through it. **The guard is unreachable
   from these two keys because it is a method on `EditorController` while both exits sit above the
   editor and call the console.** The direction is to give the editor a *may I leave?* step the
   exits must pass — `finish_edit` returning a refusal its callers honour, or an editor-side
   `request_leave` that runs the existing confirmation and completes the exit on confirm — so the
   policy stays where #45 put it and only its reachability changes. **Full analysis, both guard
   chains and the shape of the work: `../technical_debt/input.md`, `T-EXITS-BYPASS-GUARD`**
   (`BACKLOG`), with the chord's own history on `T-LEAVE-KEYS-LOSES-BLOCK`.

   **The one exit that IS guarded is pinned**: `tests/editor/editor_spec.lua`, *"leaving through
   Shift+Esc (2.3)"* — a dirty block asks instead of leaving.

   **All three exits are pinned as of 2026-09-09** (owner ruling, at `EDKEYS-01`), and the two
   unguarded ones carry a marker: `tests/input/input_editor_keys_spec.lua`, *"Ctrl+Shift+S leaves
   **(w/o confirmation)**"* and *"Ctrl+T leaves and runs **(w/o confirmation)**"*, each citing this
   statement and `../technical_debt/input.md`, `T-EXITS-BYPASS-GUARD`. *Prior wording, withdrawn —
   "the two above are deliberately unpinned, because a passing test over them would fix the loss in
   place."* **The marker is what answers that objection**: the case names the behaviour a known
   defect that is slated to change, so a green test cannot be read as the specification, and the
   exits are inside the regression net instead of outside it. It is the same annotate-don't-invert
   treatment `EDKEYS-01` gives the navigation-Escape case that pins this contract's opposite.

**Relation to `D-LIFECYCLE-FLAGS`.** Its first acceptance criterion — *the editor's Escape must match
#45's expectations* — is row 1 of this table, and the two entries divide the work cleanly: that one
supplies the **mechanism** (the editor seats no flags, so the widget is inert on both verbs), this
one supplies the **standard** the mechanism is measured against. Neither replaces the other, and if
they ever disagree, this entry is the one carrying a stakeholder's ratification and wins.

---

## D-SIMPLE-SURFACE — two named surfaces; the simple one is a wrapper on `compy`, not a second API

**Status: IMPLEMENTED, 2026-09-09 (`SIMPLE-01`)** (owner rulings, 2026-09-07, amended 2026-09-09).
`T-SIMPLE-SURFACE` is paid. **Five amendments came out of building it, and each is an owner ruling
of 2026-09-09:**

1. **A fourth name ships — `compy.unask()`** (statement 2 said three). It disposes, restores and
   **concludes nothing**: `on_answer(nil)` means *the user abandoned*, and a program withdrawing its
   own question already knows — a callback that could not tell the two apart would loop for anything
   that re-asks from `on_answer`. It exists because both alternatives are silently wrong:
   `compy.input.hide()` leaves the stubs armed (statement 6's uncovered path), and calling
   `on_answer(nil)` by hand fakes a conclusion without disposal or uninstall.
2. **`on_key`'s payload is LÖVE's own argument list — `(key, scancode, isrepeat)` — not a combo
   string** (statement 7 said combo string). A combo string occupies the first position and
   forecloses parity; the main API abandoned the same idea for the same reason (`D-LOVE-ARGS`). A
   program reads modifiers from the device (`D-ASK-THE-DEVICE`). **Repeats are delivered**, which
   this amendment reinforces rather than changes: the flag now has a position.
3. **The tier is `hooks`, not the recommended `shortcuts`** — measured, not preferred. `shortcuts`
   cannot bind unmodified keys at all: a bare `*` **raises at registration** (`util/key.lua`,
   `check_combo`; `D-COMBO-SHAPE`), and its message says *"for every key, use
   `compy.input.hooks`"*. The scenario `on_key` exists for is mostly bare keys.
4. **A collision RAISES rather than chains.** `ask` refuses when `hooks.keypressed` is set or the
   project defines `love.keypressed`, naming the precise API as the way out. Owner: *"people should
   decide themselves what they want (no capability is blocked, as they can build whatever they want
   with precise API)."* This supersedes statement 7's memoize-and-chain mitigation, which was written
   for the tier that was not chosen.
5. **The uninstaller is boilerplate `ask` installs, not the user's callback.** It reverts every
   configuration tweak **first** and then calls `on_answer` with the payload — the same
   dispose-then-notify ordering `D-LIFECYCLE-FLAGS` gives the flags, one level up, and what lets
   `on_answer` ask the next question with a plain `ask`.

**What building added that no ruling covered:** whether a question is armed is read off the
**installed stub**, not a boolean. A question can be lost without concluding, and a flag that
outlived it restored a stale configuration over the next question. Found by a test.

*Prior status — DECIDED, NOT IMPLEMENTED* (owner rulings, 2026-09-07), with the implementation
registered as active debt: `../technical_debt/input.md`, `T-SIMPLE-SURFACE`. It exists
because the stakeholders answered the shipped API with a **minimal-surface proposal**, and the
release absorbs it.

**Decision — seven statements, in force together.**

1. **The release ships two named surfaces: the *precise* API and the *simple* API** (owner ruling on
   the names, 2026-09-07 — chosen without strong preference, and recorded that way rather than
   dressed as a principle). **Both documents use that pair and nothing else**: not *low-level*, not
   *simplistic*, not *minimal*. *Precise* is a claim about exactness, so prose calling that surface
   *legacy* or *raw* contradicts this statement.
2. **The simple surface is names on the `compy` namespace itself, not under `compy.input`** — so a
   program that only asks a question never meets the precise API's namespace. **Three names ship —
   `compy.ask`, `compy.on_answer` and `compy.on_key`** (the third added 2026-09-07; statement 7).
   **Three things make this consistent rather than a reversal of the click-hook migration.**
   `D-NO-POLLING` distinguishes *"an input event arriving"* from *"a result leaving"* — the migration
   moved **events**; these are **results**. `compy.before_exit` is already a project-assignable
   callback on the namespace. And the shell permits it: `get_compy_namespace`'s `__newindex` refuses
   `input` (`D-FROZEN-SHELL`) and `rawset`s everything else.
3. **It is a wrapper, and that is normative.** `compy.ask` seats the content baseline, the
   project-owned settings and the lifecycle flags on **the same widget the precise API drives**, and
   arms stubs into the precise callbacks. There is no second widget, no second state and no second
   event path. **A reader who learns `ask` first and `show` later must find that the second contains
   the first.**
4. **The stubs read the namespace slots when they fire; they never capture them.** That is what
   makes `on_answer` a **callback** rather than an argument: assigning it before or after `ask` both
   work, and reassigning it between questions works. Exactly one place holds the user's function —
   the `compy` slot — and the precise callback holds a framework stub, so this is not a second
   installation path for a user's callback.
5. **A question concludes exactly once, through `on_answer`.** `on_answer(text)` is *answered*;
   **`on_answer(nil)` is *abandoned*** — armed by `ask` on the cancel path. The two are
   distinguishable because **Lua's `''` is truthy**, so `if text then` separates *answered with
   nothing* from *abandoned* **regardless** of whether the widget's empty-submit guard is ever
   lifted. *(That guard is inherited and unruled — `../technical_debt/input.md`, "The empty-submit
   guard is inherited from the console and was never ruled" — and this statement deliberately does
   not rest on it.)*
6. **`ask` seats the one-shot disposal and disarms what it arms.** Both verbs clear and hide, so a
   question disposes of itself however it ends; and the stubs are removed on the paths `ask` itself
   seats. **One path is not covered and is named rather than hidden:** a project that calls
   `compy.input.hide()` itself, never answering, leaves them armed. Re-arming idempotently at the
   head of every `ask` bounds it; closing it needs the close callback the register already records
   as missing.
7. **`compy.on_key` ships, and it reports keys without concluding the question** (owner,
   2026-09-07, reversing a deferral taken the same day once the design turned out to be cheap).
   **Its defining property is that the callback's RETURN VALUE decides consumption**: truthy claims
   the key and the widget never sees it; falsey lets it through to editing. That is
   `EditorController`'s own `block_input()` expressed as an ordinary Lua return, and it is what makes
   the requester's stated scenario — *"the API should make it easy to implement something like the
   built-in editor"* — reachable from the simple surface rather than only from the precise one.
   **It also dissolves a problem three earlier designs were built around:** `ask` needs no list of
   the keys editing owns, because the **program** decides. Return falsey and `backspace` still
   deletes.
   **What `ask` filters before reporting, and it is only two things:** a **bare modifier** never
   fires it (the requester's own rule, and `D-COMBO-SHAPE`'s), and a key that will arrive as **text**
   never fires it (a single printable with no `ctrl`/`alt`), because reporting those is noise on
   every keystroke. **Repeats are delivered, not suppressed** — the requester asked for typing's own
   delivery, an editor-like program wants a held key to repeat, and `compy.input.fn.ignore_repeat`
   is the existing opt-out. **The payload is a combo string** (`'ctrl+f'`), the same vocabulary a
   shortcut is keyed by.
   ***Which tier `ask` installs it on is deliberately open, with a recommendation.*** The
   **shortcuts** tier is recommended: it is a separate tier nothing auto-seeds, so it cannot collide
   with a project's own handler, at the cost of one registration per modifier class inside `ask`.
   The **hooks** tier costs one registration but takes the project's single `keypressed` slot, which
   `D-HOOKS-SEEDED` seeds from the project's sandboxed `love.keypressed` — so a program that writes
   both collides. **If the hook tier is chosen, the owner's mitigation is the design of record**
   (2026-09-07): `ask` memoizes the previous hook, chains to it when `on_key` declines the key, and
   reinstalls it on the exit paths — **with one guard, because `D-HOOKS-SEEDED` forbids
   resurrection**: restore only if the installed hook is still `ask`'s own, so a hook the project
   cleared mid-question stays cleared.

**Two deviations from the requester's literal proposal, stated here because they must be told to him
rather than shipped quietly.**

- **His model terminates on a control key** (*"when any of the callbacks are called, the input is
  removed from the screen"*). **Ours does not**: our widget spends `Ctrl+C`/`V`/`X`, `Ctrl+Y`,
  `Ctrl+W`, `Ctrl+Home`/`End` and `Ctrl+D` on **editing**, so a terminating report would end a
  question while the widget pastes into it — and his own scenario, the editor, does not close its
  input on `Ctrl+F` either. *(Recorded first as a contradiction in his statements; that reading is
  withdrawn — the terminating sentence describes the **ask** shape, which `on_answer` implements
  exactly, while the editor scenario is about **capability**.)*
- **His model reports abandonment as a key**; ours reports it as `on_answer(nil)`, which keeps
  *conclusion* in one callback and leaves `on_key` to report without concluding. *(`on_key` is not
  an observer: its **return value consumes**. Conclusion and consumption are different axes, and the
  surface separates them on purpose.)*

**What this decision does not fix.** Whether the three namespace members are **plain fields or
metatable-intercepted slots** is an implementation choice, deliberately open. The recommendation is
**plain fields**: `before_exit` is an upvalue behind the metatable, and `table.clone` reuses the
metatable by reference, so every env clone shares one slot — an oddity the register already records
as reading *"accidental"*, and one worth not multiplying by three.

**Why a wrapper rather than a second implementation.** The stakeholder ask this release answers is a
*simpler* input API. A parallel surface would double the state a maintainer reasons about and would
let the two drift; a wrapper cannot drift, because it has nothing of its own to drift with. It also
keeps one key vocabulary and one widget lifetime, which is what lets a program that outgrows `ask`
step onto the precise surface without relearning anything.

---

## RETIRED

**Empty, and that is a state rather than an oversight.** Six entries stood here — five superseded
in full by a later decision, and one that its own heading called NOT A DECISION. All six were
vacuumed on 2026-09-01, under `agents/rules/ledgers.md` §2: a ruling we made for ourselves may be
swept once it rules nothing, and none of the six came from a stakeholder.

**What made the sweep safe is the naming, not the emptiness.** That rule keeps retired entries
*"while the ledger is numbered"*, because a citation resolving to nothing is worse than one
resolving to a tombstone — under numbering, the number a sweep misses still exists and now means a
different decision. Under names it dangles visibly and greps out. So the tombstones were doing one
job, and that job ended when the numbers did.

**The six themselves are archived, not destroyed** — moved to the feature's working tree under
`agents/rules/ledgers.md`, *"Vacuuming is a move, not a deletion"*. That archive leaves the
release when the working tree is deleted, which is correct: none of it is the product's
history. It answers *what did the ledger used to contain* and *what work happened here* without a
trip through `git log`, and it is **not** a second ledger — nothing in it rules anything.

**Where the content went, for the three that had any worth keeping.** The held-key-set arc — a
read-only view of the live set, then a globally readable surface, then the framework's truth for
event-time questions — is described in full by **D-ASK-THE-DEVICE**, *"what it withdraws"*, including
the two details that still bite. The `inspect` narrative, whose entry had said in its own body
that it belonged elsewhere, is `../internals/user_input.md`, *"inspect mode"*. The remaining two
were superseded in full and left nothing behind — one ruled uniform chain signatures and
`isrepeat` threading, now D-LOVE-ARGS; the other deferred input unification, now D-ONE-LIFETIME and
D-BUTTON-TRIGGER.

Future retirements land here in the ordinary way.


---

## Crosswalk — the numbers these decisions used to have

**Why this table exists.** Until 2026-09-01 every decision here was cited by a number, and the
numbers are still in circulation: commit messages, the feature's working notes, and any document
written before that date all say `Decision 21` where the ledger now says `D-COMBO-SHAPE`. A reader
arriving from one of those needs the mapping, and it has to live where the decisions are — the
feature's own working tree is scheduled for deletion, so a crosswalk kept there would go with it.

**The numbers are not reused.** A removed decision's name is simply never minted again, and an
added decision disturbs nothing, so this table is closed: it will not grow and no entry in it will
ever mean something else. That property is the whole reason for the conversion — under
renumbering, a citation the sweep missed would resolve to a *different, existing* decision and read
as authoritative; under names it dangles visibly and greps out.

| was | is | |
|---|---|---|
| Decision 1 | `D-ROUTE-OWNS` | |
| Decision 2 | `D-CHAIN-OF-3` | |
| Decision 3 | `D-WIDGET-AT-BOOT` | |
| Decision 4 | `D-NO-POLLING` | |
| Decision 5 | `D-EDIT-CALLBACKS` | |
| Decision 6 | `D-EDIT-LIFECYCLE` | |
| Decision 7 | `D-FROZEN-SHELL` | |
| Decision 8 | `D-COMBO-TABLES` | |
| Decision 9 | — | **removed**; superseded by `D-LOVE-ARGS` |
| Decision 10 | `D-HOOKS-SEEDED` | |
| Decision 11 | `D-ROUTE-LIFETIME` | |
| Decision 12 | — | **removed**; was never a decision. The behaviour it described is `../internals/user_input.md`, *"inspect mode"* |
| Decision 13 | — | **removed**; the held-key arc, now `D-ASK-THE-DEVICE`, *"what it withdraws"* |
| Decision 14 | `D-DEFACTO-KEPT` | |
| Decision 15 | `D-UNKNOWN-RAISES` | |
| Decision 16 | — | **removed**; superseded by `D-ONE-LIFETIME` and `D-BUTTON-TRIGGER`, and it left nothing behind in the corpus |
| Decision 17 | `D-BEHAVIOUR-TEST` | |
| Decision 18 | `D-ONE-STATE-ASK` | |
| Decision 19 | — | never existed; the sequence had a gap |
| Decision 20 | — | **removed**; the held-key arc, as 13 |
| Decision 21 | `D-COMBO-SHAPE` | |
| Decision 22 | `D-IGNORE-REPEAT` | |
| Decision 23 | `D-NO-LOG-NOISE` | |
| Decision 24 | `D-STOP-AND-SIDE` | |
| Decision 25 | `D-ONE-LIFETIME` | |
| Decision 26 | `D-LOVE-ARGS` | |
| Decision 27 | `D-BUTTON-TRIGGER` | |
| Decision 28 | `D-STOP-IS-FW` | |
| Decision 29 | — | **removed**; the held-key arc, as 13 |
| Decision 30 | `D-ASK-THE-DEVICE` | |
| Decision 31 | `D-THREE-MODS` | |
| Decision 32 | `D-USAGE-SHAPE` | |
| Decision 33 | `D-EXACT-RESERVE` | |
| Decision 34 | `D-RESERVE-TABLE` | |
| Decision 35 | `D-CFG-BOUNDARY` | |
| Decision 36 | `D-AUTO-HIDE` | |
| Decision 37 | `D-PAYLOAD-SPLIT` | retired 2026-09-09; `D-ONE-PAYLOAD` stands in its place |
| Decision 38 | `D-CONTENT-NORM` | |
| — | `D-LIFECYCLE-FLAGS` | **no number** — decided 2026-09-06, after the numbers were retired (`DEC-01`) |

**The six that were vacuumed are archived**, not destroyed — the feature's working tree holds
them in full, and the overruled half of `D-AUTO-HIDE` beside them. (Seven rows map to nothing: Decision 19 is the
seventh, and it never existed to archive.) The archive goes with the working tree; the mapping
above is the part that stays.

**Reading a `D-1`…`D-10` instead?** That is a different, dead namespace — the design-time ids from
this subsystem's design phase, which lived only in the feature's working tree and never reached
code or this corpus. Digits after the prefix mean that one; letters mean this one.
