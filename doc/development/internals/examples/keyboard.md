# keyboard — how typed characters are accepted

<!-- authored By LLM; human-approved NOT YET -->

**Scope:** how the keyboard example decides that a character the player produced counts, and how it
keeps one physical press from counting twice. Two of its subgames judge typed characters — the
Alt-keys scene and Words — and this is the mechanism both use. The example's other subsystems
(scenes, gauge, layout, sound) are not covered. The example ships from
<https://github.com/dsent/compy.keyboard>.

**Status: this describes the shipped code.** An earlier revision of this document described a
*recommended* design that was never implemented and has been superseded — see "What changed, and
why" at the end.

## The problem

For one physical key LÖVE delivers `keypressed(key, scancode, isrepeat)` and, if the key produces a
character, `textinput(text)` — with **no guaranteed order between the two channels**
(`../user_input.md`, "Data flow").

Anything that asks which keys are down at `textinput` time therefore answers *which build is
running*, not *what the player did*. That is a defect this example shipped: acceptance dropped every
character whose key was held, so wherever `keypressed` arrives first — the key is always held by the
time its own character arrives — nothing was ever accepted and the game was **deaf**. Attested on
desktop Linux, run as `love src`; the owner's expectation is that Android from an assembled `.apk`
worked, on the grounds that the author uses it there.

**No claim is made here about which platform delivers which order.** The order is not a guarantee, a
LÖVE release could change it, and a mechanism that is correct only under one of them is not correct.
That is the whole reason for the shape below.

`textinput` also carries **no repeat flag of its own** — `keypressed` gets one, as its third
argument — so on that channel an OS key-repeat and a deliberate press look identical.

## The paradigm: the character claims its key, and the device releases the claim

**One `textinput` is accepted per physical press.** The mechanism is one table and one poll, in
`input.lua`:

- **`GLYPH_CLAIMED`** — the keys whose character has been delivered to a scene.
- **`spendGlyph(k)`** — returns true (drop this character) if `k` is already claimed; otherwise
  claims it and returns false. Called by each judging scene as the first line of its `textinput`
  handler.
- **`inputTick()`** — runs once per frame from `love.update` and clears any claim whose key
  `love.keyboard.isDown` reports **up**.

**Nothing consults the other channel, and nothing consults a clock.** The question a claim answers —
*has a character for this key been taken since the key was last down* — has the same answer in either
delivery order, because neither half of it is an event.

**Why the release is a poll and not `keyreleased`.** On the release channel, a genuine release and a
trailing repeat character are the same shape: clearing the claim when the release arrives lets a
repeat character that trails it through **as a fresh one** — a wrong answer nobody typed. The
previous mechanism swallowed that with a one-frame grace window stamped from `DBG_FRAME`, the debug
logger's counter, and paid for it by discarding a genuinely fast tap. Asking the keyboard needs
neither: whether a key is down is a frame-time question about physical state, which is what a poll is
for (`../../../input_api.md`, "Held keys"). `keyreleased` holds **no** acceptance state at all; its
only remaining job is dispatch, which `bubble.lua`'s hold judge needs.

**`inputTick` runs in `love.update`, not in `updateStep`.** `updateStep` returns early before the
first draw, while paused, and while the help overlay is shown — and `Alt+P`, which pauses, claims
its `P`, so a claim would outlive its key in ordinary use rather than in a corner case.

### The character → key inference, and its limit

A claim is keyed by the **physical key**, so a produced character must be mapped back to one:
`glyphBaseKey` (`input.lua`) sends `" "` to `"space"`, a shifted symbol through `SHIFT_MAP` inverted
(`"~"` → `` "`" ``), a letter to its lowercase key, and anything else to itself. It lives in
`input.lua` because both judging scenes need it and scene files are lazy-loaded; `config.lua`, which
holds `SHIFT_MAP`, is loaded long before.

**The inference cannot always succeed**, and the failure matters because
**`love.keyboard.isDown` raises on a string that is not a LÖVE key constant** — *"Invalid key
constant: ~"*, measured, not assumed. A character from an IME or a dead-key composition may name no
key this keyboard has. So a claim that cannot be polled is **never taken**: `spendGlyph` asks
`isDown` once per key name under `pcall`, remembers the answer, and refuses to claim an unpollable
name. **The stated residue:** such a character is accepted, and holding one would repeat it. No
scene targets one, and the alternative is a per-frame loop that can raise — which is exactly the
crash this cost before the guard existed.

### A chord owns its trigger key

A chord's trigger keeps producing characters if its modifier is released while the key stays down —
Alt+P, then letting go of Alt, leaves `P` repeating and those characters are not a typed answer. So
**whoever takes a chord claims its trigger**, without judging it:

- the swallowing classes do it — `alt+*` and `alt+shift+*`, two of them because a class is its
  modifier set *exactly* while the hand-written test they replaced said only "Alt and not Ctrl";
- `alt+p` and `ctrl+alt+h`, exact bindings (an exact combo wins over the class), claim for
  themselves;
- and `appKeypressed` claims the trigger whenever Ctrl or Alt is down, which covers the chords that
  are **not** swallowed and reach the scene by design.

The claim is released by the same poll as any other, so the suppression lasts exactly as long as the
key is held.

**The rule is not only about chords: whoever *consumes* a key owns it.** A scene transition consumes
one too — `menuKeypressed` opens a game with `gotoScene` *inside the handler*, so on a
keypress-first build the digit's own character arrives at the game just opened, whose first target is
already live, and is judged as a typed answer. The menu therefore claims the digit before it
switches. Upstream had no such leak only because its held set was written before the menu dispatch;
the protection was incidental, and it left with the set.

**`Ctrl+Alt+H`, the teacher chord, is one of these exact bindings** — it re-arms the active scene's
hint through an `onHint` scene-descriptor entry, the way `Ctrl+Alt+Up` reaches `onNotch`, and only
the Alt scene defines one. It was a hand-written three-key match inside that scene's `keypressed`.
**Accepted with it:** a shortcut is swallowed in *every* scene, where the hand match let a bare `h`
reach the games that judge key targets (Press, Find, Blow the bubble) and knock there. The dispatch
also keeps the pause gate the scene handler gave it for free, so the chord stays inert behind the
pause screen — unlike the notch, which upstream deliberately handled above that gate.

## What happens before a scene sees a character

Two things in `input.lua`'s shared `appTextinput` run **upstream of every scene**:

- **the chord filter** — a character produced with Alt or Ctrl held never reaches any scene. Only
  Shift modifies a target;
- **Caps reconciliation** — `capsReconcile(t, Key.shift())` for alphabetic characters, **before**
  dispatch and therefore before any suppression. Repeats and characters arriving during a
  celebration are all valid evidence of a lock state nobody reported, and the estimate serves every
  scene that shows the Caps decal, not just the judging ones.

Both read live modifier state, and both are **outside acceptance**. That distinction is the point:
the original defect was acceptance *inferring* a repeat from held state, not a dispatcher asking
whether a modifier is down.

## What the game actually requires

These rules come from the game's own scoring (`gauge.lua`), not from input theory, and they are what
keeps the mechanism small:

1. **A repeated wrong character changes nothing** in the Alt scene — `gaugeOnWrong` is idempotent per
   presentation (`if st.fumbled then return end`). Several wrong keys read as one miss, by design.
   **Words is different:** `wordsBad` plays its knock every time and has no such flag, so a repeat
   reaching it is audible.
2. **A correct character advances the target immediately.** In the Alt scene `gaugeOnCorrect` calls
   `gaugeNext` synchronously; in Words `WORDS.pos` advances by one. Either way a repeat of the
   *winning* character would be matched against a target the player has not answered yet.

So of all the repeat cases input plumbing has historically tried to suppress, the ones that change an
outcome are covered by a single property: **one accepted character per physical press.**

## Two consumers, and why that is what the mechanism is keyed on

`alt.lua` presents **one item at a time** — a character, or a key name (`backspace`, `tab`, `return`)
matched on `keypressed` instead, selected by `altIsKeyTarget`. `words.lua` presents **a position in a
string**: `WORDS.pos` walks a generated line, typed strictly left to right, and **consecutive
identical targets are ordinary** — 224 words in its corpus carry a doubled letter.

That difference is why acceptance is keyed on the **press**, not on the character's content. A
content test — *drop it if it repeats the last accepted character* — is sound only where consecutive
targets cannot repeat. In Words it would make the word `"all"` untypeable: the second `l` would be
discarded, and the player could only unstick it by typing something wrong.

**This is the premise an earlier revision of this document rested on, and it named the trigger for
its own revision:** *"if a later stage ever asks the player to type a word, this design must be
revisited"*. Words is that stage, and it arrived from upstream.

## Consequences, accepted

- **An OS repeat and a deliberate re-press of the same character are distinguished by the key going
  up**, which is the only thing that separates them. Nothing measures time.
- **A character whose `textinput` arrives after its own `keyreleased` is accepted.** Nothing couples
  to that channel, so a fast tap cannot lose its character. Every version of this game before this
  one dropped it.
- **A release that never arrives costs nothing.** The poll resolves it on the next frame, so a focus
  change mid-hold leaves no stranded claim. This is a property, not a motive: focus-shaped risks are
  tolerable in this example, and a risk cleared by repeating a gesture is an inconvenience.
- **Acceptance adds no modifier guard of its own.** It does not need one: the shared handler already
  drops anything produced with Alt or Ctrl held, and Shift must pass, since Shift is how every
  capital is typed.
- **A character produced after a chord's modifiers are released is an ordinary character** unless the
  chord claimed its key — which it does. A player who reaches `h` by releasing Alt from `Alt+H` while
  `H` is still down produces nothing; one who releases `H` and presses it again has typed `h`, and
  that is a win (owner ruling, 2026-08-08).
- **`bubble.lua` keeps judging on `keyreleased`, and that is a ruling, not an omission** (owner,
  2026-08-12). **Not because the API cannot express it** — a frame poll measures a hold just as well,
  by accumulating while the device still reports the key down. It stays because the channel is the
  **author's** decision to make: they may have reasons for tracking the event, and a migration should
  not quietly redesign what it was asked to carry across. Its failure mode is a release lost to a
  focus change, and `bubbleGrow`'s own timeout pops the bubble a moment later: the child retries — an
  inconvenience, not a wedge. The caution is written where the handler is.
- **The window in which a trailing repeat is swallowed is one frame, and it is measured from the
  frame boundary rather than from the keyup.** The mechanism this replaced stamped a grace window
  from the keyup itself, so in the direction it guarded — a repeat character arriving just after its
  release — the old window could be marginally longer than the new one. Reaching the difference needs
  a repeat that lands after the frame's poll but within a frame of the release, and the cost is one
  character accepted that the player did not intend to type. Weighed against what the grace window
  cost — a genuinely fast tap, in ordinary play — this is the cheaper residue, which is why the
  boundary moved.
- **A release and a re-press inside the same frame lose the second character.** Claims are cleared
  only by `inputTick`, once per `love.update`, so a re-press with no update in between finds its
  claim still standing. That is ~16 ms — below a deliberate keystroke, and the smoke row it would
  threaten (`B5`, "press it again immediately") is a human *immediately* of 50-100 ms. It is the one
  residue of clearing from the device rather than from an event.
- **No test suite.** The repository has none, so everything here is reasoned or exercised by hand.

## Caps Lock

On Compy, the IDE status line reads the Android activity's Caps Lock state.
Hardware key events carry the latch. At startup, on focus gain, and after
input devices change, the activity can request the keyboard LED state from
the rooted system, including before the first keypress.

The **key** arrives normally as `keypressed('capslock', …)`. Three things do not:

- **the lock state** — LÖVE 11.5 has no API to query it, so `CAPS_STATE.on` is an estimate the
  example maintains;
- **the state at startup**, and any toggle made while the window was unfocused;
- **`keyreleased('capslock')`, reliably.**

**`capslock` is exempt from the repeat filter in `appKeypressed`** (`if isr and k ~= "capslock"`).
That exemption is **inherited from upstream, where it was exempt from the held-set staleness test for
a reason that no longer applies** — a release that never arrived would wedge the held set and freeze
the estimate for the session. Under an `isrepeat` filter a fresh press is never flagged as a repeat,
so nothing can eat a toggle, and the exemption's only remaining effect is that capslock **repeats**
reach `capsToggle`. It is kept deliberately, to preserve upstream's behaviour exactly; if a platform
repeats lock keys the estimate flickers while the key is held, which is upstream's property and not
this feature's. Correcting the estimate from `textinput` is what recovers either way.

## Smoke checklist — owed by a human

Nothing in this mechanism can be exercised where the code is developed: the container cannot inject
keystrokes and has no device. **The runnable checklist lives in
[`../../smoke_checklists.md`](../../smoke_checklists.md)**, `keyboard`'s section — one list, kept
beside the other examples', so it does not drift from a second copy here. It marks which cases
exercise this mechanism rather than pre-existing behaviour.

The cases this design turns on, for a reader who wants them without leaving this page: a **fast tap**
of the target character registers; a **doubled letter** in Words registers twice; a **shifted symbol**
in Words does not raise; and `Ctrl+Alt+H` with **the modifiers released while `H` stays down** puts no
stray character into the scene.

## What changed, and why

The revision this replaces specified a different mechanism: `textinput` as the only judge, a
scene-local `ALT_JUDGE` table with `lastText` and `blocked`, and the subtraction of the claim table
outright. It was written when the Alt scene was the only consumer, and it was never implemented.

Two things retired it. **Words** arrived from upstream as a second consumer, and its targets can
repeat — which the content test cannot serve, and which that revision had itself named as the
condition for revisiting. And the **release boundary** turned out to be answerable by the device
rather than by an event, which removed the grace window, the frame counter and the `blocked` field
together, and closed the release-loss case that a `lastText` design still had.

The result both alternatives ran into is §"The problem" above: with no guaranteed order between
`keypressed` and `textinput`, acceptance cannot be decided at the moment a character arrives —
whatever is asked then answers which build is running. That is what rules out a `textinput`-only
judge, and it is the whole argument this design is derived from.
