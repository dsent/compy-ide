# Manual smoke checklists

Checklists a **human** runs, for the parts of this project no automated suite can reach: the nested
example repos have no tests, and nothing in CI can press a key. Each list is written to be run
top-to-bottom in one sitting, with the expected result stated so a failure is unambiguous.

**Referenced from:** `doc/development/tests.md` (what is and is not covered), the feature's own PR
gate — where each detached example repo's gate is a human smoke pass — and the step that last
changed the code.

**Which examples owe a list** (measured 2026-08-13; Phase G carries the full reasoning): this
feature changed code in twelve examples — nine tracked and three detached. **The owed lists
exist**: `keyboard`, `maze`+`draw` and `balloons` (detached, so its PR's only gate is this pass).
Sapper owed one too and ships from <https://github.com/dsent/compy.sapper>, outside this
repository.
The remaining tracked examples ride the platform PR's review pass.

**A fifth was added 2026-08-30: `turtle`.** It moved onto the widget's own hide at `FEAT-02`, so its widget
lifecycle is now the framework's rather than its own — the class of change that earns a list — and
it is the only in-tree consumer of the key. **It changed again on 2026-09-08** (`BUG-03-03`):
its two keyboard channels moved from `love.keypressed`/`love.keyreleased` to
`compy.input.hooks.*`, because a handler captured from `love.*` now consumes its channel and would
have shielded turtle's own widget. Nothing a player does should differ — group C is the pass that
says so.

**A sixth was added 2026-09-08: `sine`.** It owes a list for one row, and the row is the only
behaviour this release changes for a user of the console: a project that draws once and returns
leaves the prompt **typeable** again (`BUG-03-01`). No per-example list reached that behaviour,
because every example that owns a list either hooks a keyboard channel or shows a widget.

**Run them in this order**, which is by *upstream sensitivity* — least exposed first, so that a
result nobody can invalidate is banked before the exposed ones:

| step | list | why it sits here |
|---|---|---|
| **1** | `balloons` | 5 ahead / 0 behind its upstream — no divergence to reconcile, so no later merge can invalidate the result |
| **2** | `keyboard` | reconciled 2026-08-11; upstream may have moved since |
| **3** | `maze` + `draw` | reconciled against a base dated 2026-07-24 |
| **4** | `turtle` | in-repo, and the last mechanism to land |
| **5** | `sine` | in-repo, one row, no game to learn; run it last or first, it depends on nothing |

*(**The upstream merges run before these passes, not after**, so "no later merge can invalidate the
result" is true of every row above and not only the first.)*

**Report a result by the list's name — `balloons`, `keyboard`, `maze` + `draw`,
`turtle` — and by the commit it ran against.** These rows were once keyed by the development
sprint's own step ids; the numbers above are reading order for one sitting and nothing else. A
checklist outlives the plan that scheduled it, and a result filed under a step id becomes
unreadable the moment that plan is gone.

**A clean pass is worth pinning.** Tag the exact state a green run was made against — the tags
themselves live in the repository, which is what outlives any registry of them — so that "it
passed" names a commit rather than an afternoon.

**Keep this document current with the code.** A checklist that tests a mechanism the code no longer
has is worse than none, because it passes.

---

## keyboard

**Repository:** `src/examples/keyboard` (separate remote, own PR). **Last mechanism change:**
2026-08-12, the way a typed character is accepted, and the teacher chord `Ctrl+Alt+H` becoming a
registered shortcut instead of a hand-matched combo — see `internals/examples/keyboard.md`. Cases marked **[new]** exercise that mechanism and have never been
run by a human; the rest are regression checks against behaviour the example already had.

### The four commits a result should be reported against

A smoke result is only investigable if the four states it ran on are named. Quote these with any
finding, and **refresh them (`git -C <repo> rev-parse --short HEAD`) if the tree has moved before you
run** — a row that fails against a state nobody recorded costs a bisect.

| what | ref | commit |
|---|---|---|
| `keyboard`, the branch under test | `newinput` (local, unpushed) | **`e568961`** |
| `keyboard` upstream it is diffed against | `origin/dsent/dev` | **`025e858`** |
| platform repo running it | `feature/77-newapi-analysis-s20260615` | **`c7e065c3`** |
| platform edge upstream, for comparison | `dsent/dsent/dev` | **`9ed375d4`** |

*(Re-pinned 2026-08-12 after P-18-19/20 — the last three behavioural differences against upstream
closed, and the tidy batch. **At this head the gesture-parity diff against upstream is zero** across
108 fresh-press stimuli and 108 repeats. The platform id is this pin's parent; the pin commit changes
nothing but this table.)*

### How to launch

- **Desktop / nodejs:** from the repo root, `love src play src/examples/keyboard`.
- **Device:** the assembled `.apk`.
- **The exit rows (D9, G1) need the IDE, not play mode.** Under `love src play …` the console is
  disabled (`consoleController.lua`, the `cfg.mode == 'play'` branches), so there is nothing to come
  back to and neither row can be *observed* — the code under test runs either way. Start the
  console with `love src`, launch the game from it (`run(<project>)`), and come back to it.
- The **menu** lists eight games in this order: **1** Press the key · **2** Find the key ·
  **3** Asteroids · **4** Alt characters · **5** Words & phrases · **6** Blow the bubble ·
  **7** Hide and seek · **8** Load the train. Press the digit to enter; `Shift+Esc` returns.
- A game's difficulty is `Ctrl+Alt+Up` / `Ctrl+Alt+Down` ("the notch"). **Alt characters** reaches
  its symbol and capital targets at the higher notches; **Words** adds capitals at rung 3 and
  punctuation at rung 4.

### A — the intro and the menu

| | do | expect |
|---|---|---|
| A1 | launch; while the intro is still typing, press a **letter** | the typewriter jumps to the end |
| A2 | relaunch; while it types, press **Alt alone** (nothing else) | **[new]** it keeps typing — Alt does *not* skip it |
| A3 | relaunch; while it types, press **Shift alone** | it *does* skip. Known asymmetry, deliberate: upstream behaves this way |
| A4 | from the menu press `4` to enter Alt characters; `Shift+Esc` back; press `5` to enter Words | **[new]** neither entry knocks — the first target of each is untouched, and Words' first word keeps its gauge unit. *(The digit used to be judged by the game it opened.)* |

### B — Alt characters (game 4): the main judging scene

| | do | expect |
|---|---|---|
| B1 | enter game 4, press the character shown above the board | accepted — sound, burst on that key, next target |
| B2 | **tap the target character as fast as you physically can** | **[new]** it registers. Every earlier version of this game dropped a fast tap |
| B3 | press and **hold** the correct key for ~2 seconds | exactly one hit; when you let go, the *next* target is untouched — no knock, no miss |
| B4 | press and **hold** a wrong key for ~2 seconds | one knock, not a stream of them |
| B5 | press the target, release, press it again immediately | both presses count as their own answer |
| B6 | raise the notch to reach a **symbol** target (`!`, `?`, `:`) and type it with Shift | **[new]** accepted; the burst lands on the *unshifted* key (`1`, `/`, `;`) |
| B7 | at a `backspace`, `tab` or `return` target, **hold Shift** then press the target | no knock from Shift; the target still matches |
| B8 | press `Ctrl+Alt+H`, then type the letter the hint points at | the hint re-arms and the letter registers |
| B9 | press `Ctrl+Alt+H`, then **release Ctrl and Alt while keeping H down** | **[new]** nothing happens: no knock, no miss, the target is not fumbled. *(This is the case the mechanism was rebuilt for.)* |
| B10 | press `Alt+Shift+`*any letter* | **[new]** ignored — no knock, no miss |
| B11 | **hold** `Ctrl+Alt+H` for ~2 seconds | **[new]** the hint re-arms **once** — one blip, one finger sweep from the start, not one per repeat frame |
| B12 | `Alt+P` to pause, press `Ctrl+Alt+H`, then `Alt+P` again | **[new]** the pause screen ignores it: no blip while paused |
| B13 | press `Ctrl+Alt+Shift+H` | **[new]** re-arms the hint exactly as `Ctrl+Alt+H` does. *(It stopped working during the migration and was restored — the sixth gesture of that family.)* |

### C — Words & phrases (game 5): the second judging scene

| | do | expect |
|---|---|---|
| C1 | enter game 5 and type the line shown, left to right | each correct character greens and advances; the gauge fills per finished word |
| C2 | find a line with a **doubled letter** (`all`, `been`, `little`) and type it | **[new]** *both* letters register. This was impossible under the design this replaced |
| C3 | type a **wrong** character | a knock; the cursor does **not** advance; the word loses its gauge unit; typing the right character continues normally |
| C4 | press and **hold** a wrong key for ~2 seconds | one knock per press, not one per frame |
| C5 | type `~` or `\|` (Shift + backtick, Shift + backslash) | **[new]** a knock and nothing else. **It must not crash** — this crashed the game before 2026-08-12 |
| C6 | raise the notch to rung 4 and type a line with `,` and `.` | both accepted |

### D — the reserved chords and the help overlay

| | do | expect |
|---|---|---|
| D1 | in any game, **hold** `Alt+H` | the help overlay appears and the game freezes behind it |
| D2 | release **H** first | the overlay disappears |
| D3 | hold `Alt+H`, then release **Alt** first, keeping H down | **[new]** the overlay disappears **and** no stray `h` is typed into the game — no knock, no miss |
| D4 | `Shift+Esc` | leaves the game for the menu |
| D5 | `Alt+Shift+Esc` | **[new]** also leaves. *(It stopped working during the migration and was restored.)* |
| D6 | `Ctrl+Alt+Up`, `Ctrl+Alt+Down` | the notch moves one step per press — **not** repeatedly while held |
| D7 | `Ctrl+Alt+Shift+Up` | **[new]** also moves the notch |
| D8 | in a timed game, `Alt+P`, then `Alt+P` again | pause on, pause off — once per press, and the pause survives a held key |
| D8b | in a timed game, `Alt+Shift+P`, then `Alt+Shift+P` again | **[new]** also pauses and resumes. *(It stopped working during the migration and was restored — the fifth gesture of that family.)* |
| D9 | `Ctrl+Esc` | the IDE exits and starts again; the project is not stopped first and its `compy.before_exit` does not run. **Needs the IDE launch** — see "How to launch" |
| D10 | in game 1 or 6 (no `onHint`), press `Ctrl+Alt+H` | **[new]** nothing happens: no knock, no miss, no sound |

### E — Caps Lock and the decals

| | do | expect |
|---|---|---|
| E1 | in game 1 or 2, press `Caps Lock`, then type a letter | the **Caps** decal and the keycap case agree with what was typed |
| E2 | toggle `Caps Lock` while the window is **not** focused, then return and type a letter | the decal corrects itself on that letter |
| E3 | **hold** `Caps Lock` for ~2 seconds | **[new]** watch the decal. If it *flickers*, say so — it settles an open question and is not a regression |
| E4 | type capitals with Shift held, releasing Shift at various moments | the decal never contradicts the letters that appeared |

### F — the untouched scenes (regression only)

| | do | expect |
|---|---|---|
| F1 | game 6, hold the glowing key and release while the bubble's edge is inside the ring | success. Holding past the ring, or letting go early, pops it |
| F2 | games 1, 2, 3, 7, 8 — play each for a few seconds | nothing misbehaves; a modifier pressed alone never counts as a wrong key |

### G — on the way out

| | do | expect |
|---|---|---|
| G1 | leave the game with `Ctrl+S` and use the console (**IDE launch**, as D9) | **[new]** the pointer behaves as it did before the game was started — the project puts relative mode back in `compy.before_exit`. *(The IDE now puts the mouse back itself when any run ends, so a pass here no longer tells the project's restore from the IDE's.)* |

### What a failure here means

- **A2, A4, B2, B6, B9, B10, B11, B12, B13, C2, C5, D3, D5, D7, D8b, D10, G1** are the new mechanism and its restorations. A failure is
  a defect in the 2026-08-12 work — see the four commits named above.
- **E3** is a question, not a test: either answer closes it.
- Everything else is a regression check. A failure there means the migration changed behaviour it was
  not supposed to touch, which is the thing that ruling exists to prevent.

---

## maze (and draw)

**Repository:** `src/examples/maze` (separate remote, own PR). **Last mechanism change:** 2026-09-08
(`af7d8e8`) — the two channels still written as `love.*` became hooks, because a captured handler
now consumes its channel outright and both programs show the command widget. **What to watch:** a
click still toggles the grid in `maze` and the hint in `draw`'s picture mode, and **the Shift
release still ends a macro recording — section D, rows D1–D4**, which is the one behaviour reached
through the migrated channel. Before that, 2026-08-13
— the command editor moved onto the project input API, `Shift+Esc` became a registered combo, and
three pieces of remembered keyboard state were replaced by asking the keyboard.

**This repo now ships TWO programs**, `maze` and `draw`, built from one source tree. Both share the
command editor, so **section C must be run in both**.

**Everything in this section is [new].** Nothing in this work has been run by a human, in either
program, at any commit — no level has been reached and no key pressed. The automated suite covers the
command *core* (42 assertions) and does not touch input at all, by ruling: this list is the only gate.

### The four commits a result should be reported against

Quote these with any finding, and refresh them (`git -C <repo> rev-parse --short HEAD`) if the tree
moved before you run.

| what | ref | commit |
|---|---|---|
| `maze`, the branch under test | `newinput-edge` (local, unpushed) | **`ca59903`** |
| `maze` upstream it is diffed against | `dsent/dsent/dev` | **`b8cc436`** |
| platform repo running it | `feature/77-newapi-analysis-s20260615` | **`c7e065c3`** |
| platform edge upstream, for comparison | `dsent/dsent/dev` | **`9ed375d4`** |

### How to launch — this changed, and the old command no longer works

The source root **is not a runnable project** any more: it emits `maze/` and `draw/` as separate
projects (`BUILD.md`). `love src play src/examples/maze` now fails with *"main.lua does not exist"*.

```sh
cd src/examples/maze && ./.compy/build /abs/path/out
cd <repo root> && love src play /abs/path/out/maze     # and .../draw
```

- **The exit row (E1) needs the IDE, not play mode** — under `play` the console is disabled, so
  `Ctrl+Esc` has nothing to return to. Start with `love src`, open the project from the console.
- **maze's menu** offers three tracks: **1** Drive the robot (direct keys) · **2** Plan a path (tile
  buffer) · **3** All mazes (the sandbox, which is where the **command editor** levels are).
- **draw's menu** offers Free draw and the picture tasks. **Free draw keeps its command widget shown
  the whole time**, which is what makes section C and row B1 matter there.

### A — the command editor (run in **maze track 3** and in **draw**)

| | do | expect |
|---|---|---|
| A1 | enter an editor level | the command widget is shown, **empty**, prompting `Commands:` |
| A2 | type a valid program and press Enter | it runs; the robot moves |
| A3 | after that run ends without winning | the prompt returns **once**, with the program still in the widget to edit |
| A4 | type an invalid command (e.g. `FFX`) and Enter | the **error message replaces the prompt** and the typed text stays for correction |
| A5 | correct it and Enter | it runs; the prompt goes back to `Commands:` |
| A6 | in maze: crash into a wall, then press Tab | the robot goes home and the **kept program** is back in the widget |
| A7 | type a long command, watching each character | each character appears **once** — the game now also sees every keystroke, and should do nothing with it |

### B — Shift+Esc, the gesture this work adds

| | do | expect |
|---|---|---|
| B1 | on an **editor level with the widget shown**, press `Shift+Esc` | you return to the menu. **This is the new capability** — it previously could not reach the program at all |
| B2 | look at the screen after B1 | **no command widget is left over the menu** |
| B3 | immediately press a menu digit | the track starts, and **the digit does not also land in the widget** |
| B4 | on a **direct-control** level, press `Shift+Esc` | returns to the menu, as before |
| B5 | at the menu, press `Shift+Esc` | **nothing happens** — the menu is the top level; `Ctrl+Esc` is how you leave to the console |
| B6 | type a draft, then `Shift+Esc` | you leave — the draft is not silently wiped *and then* the game left, which is what one keystroke doing both would look like |
| B7 | in **draw**, `<` typed as a command | still exits to the draw menu. **It was deliberately kept** |
| B8 | on an editor level, `Alt+Shift+Esc` | **[new]** also leaves for the menu |
| B9 | on an editor level, `Ctrl+Shift+Esc` | **[new]** also leaves — and the run is **not** stopped back to the console behind it |
| B10 | on an editor level, `Ctrl+Alt+Shift+Esc` | **[new]** same as B9 |
| B11 | on a **Track 2 (plan)** level, press `Shift+Esc` | **[new]** returns to the menu, and **no plan strip is left over it**. *(B4 covers direct-control only; the plan track has its own widget-like surface.)* |

**B8–B10 have never been pressed by anyone.** The game registers all four
members of the family, but two of them — the Ctrl-bearing ones — used to reach
the platform's gate first, which read them as `Ctrl+Esc` and tore the project
down on the release. That is what D-EXACT-RESERVE changed (a reservation now matches
its modifiers exactly), and `da9d1c2` restored the family on the maze side. The
two halves have never been exercised together on a device.

### C — the menu digit and its echo (run in **maze**, entering track 3)

| | do | expect |
|---|---|---|
| C1 | from the menu press `3` to enter the sandbox | the command widget is shown **empty** — no stray `3` in it |

*(If a `3` appears, the fix is the documented one-shot `textinput` guard, and the row becomes a
defect against `P-17-03` §5, not a mystery.)*

### D — the keyboard state that stopped being remembered

| | do | expect |
|---|---|---|
| D1 | on a **direct-control** level, hold `Shift` | the screen dims — "you are about to name a macro" |
| D2 | still holding `Shift`, press a letter, then release `Shift` | a macro is recorded under that letter, as before |
| D3 | hold `Shift`, then **click away to another window and back**, then press a letter | the letter **runs as a command** and the screen is **not** stuck dim. *(Before this work the lost release wedged it: every key started a recording and the dim never cleared until restart.)* |
| D4 | hold **both** Shift keys, release one, press a letter | it names a macro. **Stated widening**: this used to run as a command |
| D5 | on a **Track 2 (plan)** level, hold a direction key | **one** tile is appended, not a run of them |
| D6 | on a **direct-control** level, hold a direction key | the robot queues a **run** of moves — unchanged, this one is supposed to repeat |
| D7 | on a plan level, hold a direction, click away and back, press it again | it still works. *(A lost release used to kill that direction for the session.)* |
| D8 | on a plan level, build a plan of several tiles and submit it | **[new]** the robot runs the **whole** plan, in order — the buffer delivered every tile, not just the last |
| D9 | on a plan level, submit a plan that misses the goal | **[new]** the run ends back at home, as a crash does. *(Upstream behaviour, checked here as a regression: the plan track is the one place our press/repeat change reaches that the other rows do not exercise end-to-end.)* |

### E — Tab, and on the way out

| | do | expect |
|---|---|---|
| E1 | leave with `Ctrl+Esc` (**IDE launch**) | you are back in the console |
| E2 | win a level, press `Tab` | the next level starts |
| E3 | **hold** `Tab` | the level advances **once**, not repeatedly |
| E4 | press `Shift+Tab`, then `Ctrl+Tab` | each still advances/resets as a bare Tab does — these were preserved deliberately, one registration each |
| E5 | on an **editor level**, press `Tab` | the level acts **and** a tab reaches the widget, as it did before. *(Odd, pre-existing, deliberately not changed.)* |
| E6 | in **draw**, complete a picture and press `Tab` | the next picture starts |

### What a failure here means

- **A1–A5, B1–B3, D3–D5, D7, E3** are the new mechanisms. A failure is a defect in the 2026-08-13
  work — see the four commits named above.
- **D4** is a **stated behaviour change**, not a bug: confirm it reads acceptably rather than whether
  it differs.
- **E5** and **B7** are deliberate preservations. A failure there means the migration changed
  something it promised not to.
- Everything else is a regression check against behaviour the example already had.

---

## balloons

**Repository:** `src/examples/balloons` (separate remote, own PR). **Detached, so this pass is its
PR's only gate** — there is no automated suite in that repo and no reviewer downstream of it.
**Last mechanism change:** the migration off the retired poll idiom onto the continuous-session
`compy.input.*` API, five commits ending `99ad70f`.

**Everything in this section is [new].** No part of the migration has been exercised by a human.

### The four commits a result should be reported against

Quote these with any finding, and refresh them (`git -C <repo> rev-parse --short HEAD`) if the tree
moved before you run.

| what | ref | commit |
|---|---|---|
| `balloons`, the branch under test | `main` (local, unpushed) | **`99ad70f`** |
| `balloons` upstream it is diffed against | `origin/main` | **`9e7a1e1`** |
| platform repo running it | `feature/77-newapi-analysis-s20260615` | **`c7e065c3`** |
| platform edge upstream, for comparison | `dsent/dsent/dev` | **`9ed375d4`** |

*(`main` is **5 ahead, 0 behind** `origin/main` — a clean fast-forward, and the five commits are
exactly this feature's work.)*

### How to launch

- **Desktop / nodejs:** from the repo root, `love src play src/examples/balloons`.
- **The exit row (D1) needs the IDE, not play mode** — under `play` the console is disabled, so
  `Ctrl+Esc` has nothing to return to. Start with `love src` and open the project from the console.

**The game:** balloons rise carrying questions (*"Print missing letter in 'giraf..e':"*, *"What is
3 + 4?:"*). You type the answer and press Enter. Three states matter: **loaded** (the splash, which
takes the command `start`), **active** (answering), and **finished** (which takes `restart`).

### A — the session stays open, which is the whole migration

The retired idiom re-armed the input widget after every submit. The new one activates **once** and
stays open; `after_submit` clears the line. If that is wrong, the symptom is a widget that vanishes
or stops accepting text — not a crash.

| | do | expect |
|---|---|---|
| A1 | launch, and look at the splash | the command widget is **shown and empty**, hinting `To start: Type <start>` |
| A2 | type `start`, press Enter | the game starts; balloons begin rising |
| A3 | look at the widget immediately after A2 | it is **still shown**, and **empty** — not gone, not still holding `start` |
| A4 | answer a balloon correctly (e.g. `f` for `giraf..e`) and press Enter | it scores; the hint shows `Your answer: <f>` |
| A5 | keep answering five in a row without touching anything else | every one is accepted — the session does **not** need re-arming between submits |
| A6 | let the game finish, then type `restart` and Enter | it restarts, and the widget is shown and empty again |

### B — submit delivers the command string the handlers expect

The API hands `on_text_entered` the submitted content as **one string** (D-ONE-PAYLOAD), which is the
shape the game's handlers index by, so `terminal.lua` passes it straight through. It used to hand
an array and `deliver` joined it; either way a mistake here does not crash — it silently compares
the wrong thing, so **every answer reads as wrong**, which is what makes B1 worth walking.

| | do | expect |
|---|---|---|
| B1 | answer one balloon **correctly** | it is accepted. *(If a correct answer scores as wrong, the join is the suspect, not the game logic.)* |
| B2 | answer one **incorrectly** on purpose | it is rejected — the rejection path still works |
| B3 | press Enter with the widget **empty** | nothing breaks; the game does not raise |
| B4 | type an answer with a trailing space, then Enter | behaves as it did before the migration |

### C — ESC clears, and cannot strand you

`ESC` clears the line and **leaves the widget shown** by default. That is deliberate: the command
line is the only way to talk to this game, so a dismissable widget would be a dead end with no
re-arm.

| | do | expect |
|---|---|---|
| C1 | type a few characters, press `ESC` | the line clears; **the widget stays shown** |
| C2 | immediately type again | the characters appear — you are not stranded |
| C3 | press `ESC` with the widget already empty | nothing happens; still shown |

### D — on the way out

| | do | expect |
|---|---|---|
| D1 | leave with `Ctrl+Esc` (**IDE launch**) | you are back in the console |
| D2 | type a long answer, watching each character | each appears **once** — no echo |

### What a failure here means

- **A3, A5, C1–C2** are the continuous-session mechanism. A failure is a defect in this migration.
- **B1** failing while B2 passes points at the lines-to-string join in `terminal.lua`, not at the
  game.
- **D2** is the echo check every list carries; a doubled character is a platform-side defect, not a
  balloons one.
- Everything else is a regression check against behaviour the example already had.

---

## turtle

**In-repo** (`src/examples/turtle`), so it ships with the platform PR and has no separate remote.
**Last mechanism change:** 2026-09-09, `FLAGS-01` — the key that hides the widget is now
**`hide_on_submit = true`** on its single `show` (it was `auto_hide` from `FEAT-02`, 2026-08-30,
and a hand-written `after_submit = function() compy.input.hide() end` before that). What is left in
`after_submit` is the `i` echo guard, which is re-armed for the next show. **One row's expectation
changed with it — A6**: Escape now hides the widget and keeps what was typed.

**Nothing a user does should look different.** This list is a regression pass with one new
mechanism inside it, so a row that fails is either the framework's `hide_on_submit` or the
re-armed guard — the game's own logic did not move.

### The two commits a result should be reported against

Quote these with any finding, and refresh them (`git rev-parse --short HEAD`) if the tree moved
before you run.

| what | ref | commit |
|---|---|---|
| platform repo, the branch under test | `feature/77-newapi-analysis-s20260615` | **`8b52d5b5`** |
| platform edge upstream, for comparison | `dsent/dsent/dev` | **`617bbe65`** |

### How to launch

- **Desktop / nodejs:** from the repo root, `love src play src/examples/turtle`.
- **The exit row (D1) needs the IDE**, as elsewhere: `love src`, then open the project from the
  console.

**The game:** a turtle sits in the middle of the screen. **`i`** shows the widget, labelled
`TURTLE`; type a command and press Enter to move it. The commands are `forward`/`fd`, `back`/`b`,
`left`/`l`, `right`/`r` and `pause`. `space` toggles the debug readout, `Shift+R` sends the turtle
home — **both only while the widget is hidden**.

### A — the widget hides itself, and stays that way

The mechanism this list exists for. `hide_on_submit` is a **mode**, not a one-off: it is set once
at the `show` and applies to every later submit. A3 is the row that catches a flag that wrongly clears
itself — the widget would stay shown from the second command on.

| | do | expect |
|---|---|---|
| A1 | launch, press `i` | the widget is shown, labelled `TURTLE`, **empty** |
| A2 | type `forward`, press Enter | the turtle moves up **and the widget hides itself** |
| A3 | press `i`, type `back`, Enter; repeat three or four times | **every** cycle hides on submit — not just the first. *(A widget that stays shown from the second command on is the flag failing to persist.)* |
| A4 | press `i`, type `xyzzy` (not a command), Enter | the widget hides and the turtle does not move — hiding follows a **successful submit**, and an unknown word is still a valid submission here (this game installs no validator) |
| A5 | press `i`, press Enter with **nothing typed** | **nothing happens and the widget stays shown** — an empty submit is not a submit, so nothing hides |
| A6 | **with the widget still shown from A5** (do not press `i` again — the guard is spent, so it would type an `i`), type `left`, then press **Escape** | **the widget hides and `left` is not run** — Escape is a way out that destroys nothing. Press `i` again: the widget comes up **empty**, because `show` seats the content and this one passes none |
| A7 | type `left` again and press Enter | it moves and the widget hides, leaving you where A3 left off |

### B — the echo guard, re-armed from `after_submit`

`i` is both the trigger and an ordinary character. The guard eats exactly one `i` per open and is
re-armed on submit — which is now `after_submit`'s only job, so B2 is what proves the refactor.

| | do | expect |
|---|---|---|
| B1 | press `i` and look at the widget | it is **empty** — no `i` was typed into the widget it showed |
| B2 | submit a command (the widget hides), then press `i` again | still **empty**. *(A stray `i` here means the guard was not re-armed — the one thing `after_submit` still does.)* |
| B3 | with the widget shown, type `iii` | all three appear — the guard is spent after the first, and `i` is ordinary content afterwards |
| B4 | type a long command, watching each character | each appears **once** — the echo check every list carries |

### C — the game's own keys while the widget is shown

`turtle` guards its whole `love.keypressed` with `compy.input.is_shown()`, which is the documented
idiom for a project whose hooks run above the widget.

| | do | expect |
|---|---|---|
| C1 | with the widget **shown**, press `space` | the debug readout does **not** toggle |
| C2 | with the widget **hidden**, press `space` | it toggles |
| C3 | with the widget **shown**, press `Shift+R` | the turtle does **not** jump home, and an `R` lands in the widget |
| C4 | with the widget **hidden**, press `Shift+R` | the turtle returns to the centre |

### D — on the way out

| | do | expect |
|---|---|---|
| D1 | leave with `Ctrl+Esc` (**IDE launch**) | you are back in the console |
| D2 | reopen the project and press `i` | the widget is shown empty — nothing from the previous run survived |

### What a failure here means

- **A2–A5, A7 and B2** are the 2026-08-30 change. A failure is a defect in `FEAT-02` or in the echo
  guard's new home — see the two commits named above.
- **A3 specifically** distinguishes the mode from a one-off: if only the first submit closes, the
  flag is being cleared somewhere it should not be, and that is a **platform** defect, not turtle's.
- **A6 changed on 2026-09-09** (`FLAGS-01`): Escape hides a project's widget and keeps the draft,
  where it used to clear the line and leave the widget standing. The row is the one place a user
  meets that change, so confirm it reads acceptably as well as passing.
- **C1–C4** are pre-existing behaviour the change was not supposed to touch.

---

## sine

**In-repo** (`src/examples/sine`), so it ships with the platform PR. **Last mechanism change:**
2026-09-08, `BUG-03-01` — the project route stopped consuming events nobody consumed, so an
unconsumed key goes back to the console.

**What this list is for, and it is one thing.** `sine` is thirty lines of top-level drawing: no
`love.update`, no `love.draw`, no hooks, no widget. It runs, returns, and leaves the console prompt
underneath it. Before this release the project route held every channel for the whole of
`project_open`, so **the prompt below took nothing** — the run had to be stopped before the console
answered again. At the PR base it stayed typeable, and this restores that.

### How to launch

**The IDE launch, always** — this list is about the console, so `love src play …` cannot run it.
Start `love src`, then `run("sine")` from the prompt.

| | do | expect |
|---|---|---|
| A1 | `run("sine")` from the console prompt | the sine curve is drawn and the run returns |
| A2 | type at the prompt | **the characters appear** — the prompt is live while the project is still open |
| A3 | press Enter on something evaluable (`print(1 + 1)`) | it evaluates and prints, as it would with no project open |
| A4 | `Ctrl+Esc` | back to the console with the project stopped, as before |

### What a failure here means

- **A2 is the release change.** A dead prompt means the fall-through did not fire: either the walk's
  verdict is being discarded again, or the draw gate is shut when it should be open
  (`doc/development/internals/event_dispatch_layers.md`, *"What becomes of an event nobody
  consumed"*).
- **A2 succeeding for a project that OWNS the screen would also be a failure**, and it is the
  opposite direction: a project that takes over `love.draw` must keep the console deaf, because the
  prompt is not visible. Any of the blocking examples — `clock`, `pong`, `life` — is the control,
  and none of them owes a list for it.
