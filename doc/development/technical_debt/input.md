---
description: Input subsystem debt — sorted ACTIVE / BACKLOG / RETIRED by release scope
status: active
audience: developer
authored: llm
reviewed: none
---

> REVIEW: drop everything resolved, actualize the list, and maybe make it a bit more comprehensive (less prose, more facts). ToC (list) at the beginning would also help
> REVIEW: absolutely no mentioning of particular commits is allowed, they will be reassembled for the PR

# Input subsystem

Keyboard/text/pointer routing, the console and project input controllers
(`src/controller/controller.lua`, `userInputController.lua`,
`projectInputController.lua`, `consoleController.lua`), and the project-facing
`compy.input` surface. Cross-reference: `internals/user_input.md`,
`../input_api.md`. "The input API" below means the `compy.input` surface
introduced in **1.0.0-rc20260712**.

Three sections below, in release-scope order — not severity, not intent:
**ACTIVE** must be resolved before this release ships. **BACKLOG** is real and
acknowledged, but deliberately deferred past this release. **RETIRED** is
paid, or turned out not to be debt.

---

## ACTIVE

**Five entries, as of 2026-09-09 (session89), and every one of them is prose.** `T-GUIDE-LIFECYCLE-IDIOM`
retired earlier — paid by session87's input guide updates — after `T-RELEASE-LEAVES-POINTER`, the release's
**final code defect**. What remains in this register is documentation and vocabulary: nothing left here changes `src/`. *(Nine before that, and the paragraph below is
that count's arithmetic.)* **Down from six the same day (session89):** `T-HISTORY-UNREACHABLE` moved
to `BACKLOG` — its documentation half paid in the guide, its capability half deferred as **our own**
finding against a stakeholder objective rather than an explicit stakeholder request.

**Nine entries earlier the same night, and the number was unchanged after a day that moved four
things:** `T-ONE-PAYLOAD` **retired** (`PAYLOAD-01` built it, and the ruling has its own decision now
— `../decisions/input.md`, `D-ONE-PAYLOAD`); `T-EXAMPLES-PREDATE-THE-FLAGS` **opened and retired the
same day**, the sweep having found five examples stranded by `FLAGS-01`'s seated `hide_on_cancel`
and the owner having answered at the level of the default rather than of the five files; and
`T-GUIDE-LIFECYCLE-IDIOM` **opened** for the documentation pass. So the arithmetic is
15 − 6 + 1 − 1 − 1 + 1. **Six left that day and the arithmetic is 15 − 6.**
Two before the sprint: `T-KEYS-UNPINNED`, paid by `EDKEYS-01`'s regression net, and
`T-ALWAYS-SHOWN-UNRATIFIED`, **ratified rather than paid** — the owner reversed the ruling that
would have deleted the `always_shown` guarantee, so the construct now sits in
`../decisions/input.md`, `D-WIDGET-AT-BOOT`, which is exactly what the entry asked for. Three with
it: **`FLAGS-01` paid `T-LIFECYCLE-FLAGS`, `T-NO-CALLBACKS-IS-NOT-A-NOOP` and `T-NAV-ESCAPE`
together**, which is why it was one sprint rather than three — the four flags, the hardwired cancel
step made flag-driven, and the editor going inert with no editor-side change. And one straight
after it: **`T-SHOW-DESTROYS`**, taken as its own step by owner ruling the same evening, so
activation destroys nothing and the flags are the only home destruction has. *(The opening count
read "fifteen" from 2026-09-08 until the morning of 2026-09-09, one entry after the first of these
retired.)* What follows describes the fifteen as they stood on 2026-09-08 (evening): four were
opened out of one design conversation and
its successor, and **three of the four have since left this register**. `T-CONSOLE-INPUT-UNUSABLE`,
the obligation that *"`compy.input` must work in the console environment"*, was **deferred past this
release on 2026-09-08** and moved to `../wip/input-in-console/` with the design it belongs to; a
BACKLOG stub below records that it is deferred rather than dropped. **`T-ROUTE-EATS-UNCONSUMED` and
`T-SEEDED-HOOK-FALLS-THROUGH` are RETIRED the same evening**, paid by `BUG-03-01` and `BUG-03-03`:
the first was the only **regression from the PR base** in this register — the project route consumed
every event the walk left unconsumed, so a project that hooks nothing left the console taking
nothing, where the base left it typeable — and the second was opened the same day it was found, a
consume convention a legacy `love.*` handler was never written against, which became reachable the
moment the first landed and shipped with it. Of the one that remains from that conversation,
**`T-CONSOLE-SURFACE-INTERFERES` is RETIRED the same evening** by
`BUG-03-02`, which paid it by **deletion**: the console's own `compy.input` resolved the **same
widget** as the project's, so it could reconfigure a running project's widget while its own `hooks`
were dispatched by nobody, and the member is gone from that namespace rather than made to work.
**`T-RELEASE-LEAVES-POINTER`** was measured while answering the question that followed:
`release_keyboard_route` reinstalls three channels of the ten it took and leaves the pointer seven
pointing at a dispatcher it just emptied. `T-ONE-PAYLOAD`, `T-SHOW-DESTROYS` and `T-SIMPLE-SURFACE`
were opened by the owner's rulings on the proposals block, and all three are the same shape as
`T-LIFECYCLE-FLAGS`: a decision ruled, and the code not yet carrying it. **`T-SEAM-UNRATIFIED`** is
newer still and is a **vocabulary** finding — a word this feature minted, now load-bearing in the
corpus. `T-HISTORY-UNREACHABLE` is different in kind — **not a
ruling awaiting code, but a gap found by measuring the surface against a stakeholder's stated
objective**, and one of the rulings enlarged it. **(Moved to `BACKLOG` 2026-09-09 — its
documentation paid in the guide, its capability deferred as our own finding; see `BACKLOG` below.)** Three arrived with the `MERGE-01-05` import
(`T-CTRL-S-UNCLAIMED`, `T-NAV-ESCAPE`, `T-BLOCK-AT-OPEN`), one is `D-EDITOR-KEYS`'s unmeasured
coverage (`T-KEYS-UNPINNED`), one with the verb sweep that ran ahead of it
(`T-TEARDOWN-READS-AS-DESTRUCTION`), one predates both (`T-EXAMPLE-README`), and **five came out of
`OP-03`** on 2026-09-06 — `T-LIFECYCLE-FLAGS` and `T-NO-CALLBACKS-IS-NOT-A-NOOP` (the root defect
and the sprint that pays it), `T-LEAVE-KEYS-LOSES-BLOCK`, `T-EDITOR-SEAM-DEFAULT-OPEN` and
`T-ALWAYS-SHOWN-UNRATIFIED`. **Read the first two together**: the decision is ratified, the code
does not implement it, and one sprint closes both plus `T-NAV-ESCAPE`. A further entry,
`T-CHROME-UNRATIFIED`, was found by the owner on 2026-09-06 and was **read with
`T-ALWAYS-SHOWN-UNRATIFIED`** — the word and the construct were minted in the same commit, and one
ruling settled both. **That pairing ended on 2026-09-09**: the reversal keeps the construct and
leaves the word to be replaced, so the vocabulary entry is now read with `T-SEAM-UNRATIFIED` and
both land at `DOC-01-03`.

**Read the paragraph above as a history, not as the list.** Five of the entries it introduces are in
`RETIRED` below, each with what paid it; the ten that remain are the `### ` headings between here and
`## BACKLOG`. *(`T-SHOW-DESTROYS` was in that list for a few hours: the sprint it named as its blocker landed,
and the owner had it built the same evening.)*

**THREE entries left this section by owner ruling, and none of them was paid** — each ships as a
known state with its reason recorded, which is what `BACKLOG` is for:

- `T-EDITOR-SEAM-DEFAULT-OPEN`, 2026-09-06 — the release does not close the seam structurally.
- `T-LEAVE-KEYS-LOSES-BLOCK`, 2026-09-07 — *"ship both, document the defect"*; the loss is named in
  `../decisions/input.md`, `D-EDITOR-KEYS` statement 6 and in the shipping guide. Paid on
  2026-09-30 and now in `RETIRED`.
- `T-CTRL-S-UNCLAIMED`, 2026-09-07 — *"we do not intervene, ship what was shipped by #45"*; bare
  Ctrl+S stays unbound and is theirs to rebind.

**So the fifteen of 2026-09-08 are the ones enumerated above** — less those three, which are named there and
are no longer here — **plus `T-CHROME-UNRATIFIED` and `T-SEAM-UNRATIFIED`**, which the two
sentences before this list introduce, **less the three `BUG-03` retired on the evening of
2026-09-08**. *(This sentence carried "fourteen" against a stated total of sixteen from 2026-09-07
until 2026-09-08; the count in the opening line is the one to trust, and it is checkable — `### `
headings between `## ACTIVE` and `## BACKLOG`.)*
Everything else **in this file** that had to be resolved before
this release ships is paid, and each is in `RETIRED` below with what paid it. `BACKLOG` is still
full, deliberately, and nothing there blocks the release.

**This file is not the whole of the release's input obligations.** Two of the three `ACTIVE`
entries in [`general.md`](general.md) are this work's, filed there because they are cross-cutting
rather than input-specific: **`T-NEVER-SHIPPED`** (scoped to *this file's* `RETIRED` section) and
**`T-ARGUES-INTERIM`** (`../decisions/input.md`). A reader scanning for *what is still owed* reads
both files. *(Two more were paid on 2026-09-03: the version question, which the owner ruled, and the
verification of this file's `RETIRED` claims, which `FIX-02-05` ran.)*


### T-TEARDOWN-READS-AS-DESTRUCTION — *"tear down"* survives beside the widget, where nothing is destroyed

**RULED 2026-09-07 (owner, at `FIX-02-30`) — DROP THE UMBRELLA, NAME THE ACTIONS:** *"lets say
widget hides, clears without umbrella terms because actions on submit/cancel are very configurable
now."*

**This changes the fix rather than approving it.** The row was written to add a sentence saying the
verbs are **non-destructive** — a claim *about* a lifecycle, which keeps the lifecycle in the
reader's head. The ruling removes the frame instead: **say what happens — the widget *hides*, the
widget *clears* — and use no covering term at all**, neither *tear down* nor a coined replacement.

**The reason is the flags, and it is why this is now easy.** With `D-LIFECYCLE-FLAGS`, what submit
and cancel do is **per-instance configuration** — `clear_on_submit` / `hide_on_submit` /
`clear_on_cancel` / `hide_on_cancel`. There is no single lifecycle left to name, because two widgets
in the same program can differ. An umbrella term would have to describe a thing that varies by
instance, which is exactly how *tear down* misleads today. **The flag names are the vocabulary**:
they say *clear* and *hide* and nothing else, and prose that matches them needs no umbrella.

**Consequence for the row's scope, and it is a simplification:** `FIX-02-30` no longer owes a
*"these verbs are non-destructive"* clause on `D-WIDGET-AT-BOOT`. It owes the removal of the
umbrella at the sites listed above, replaced by the plain verbs. **The one real destruction still has
no umbrella either** — it is the project run's end, and it is named as that (`D-WIDGET-AT-BOOT`'s
per-run boundary) rather than as a phase of a lifecycle.

- **Where:** the sites `FIX-02-09`'s verb sweep deliberately **kept**, because *tear down* is a
  different concept from *hide* and collapsing the two would have destroyed a real distinction:
  `CHANGELOG.md:116`, `../decisions/input.md:76`, `:218`, `:796`, and
  `tests/input/input_widget_control_spec.lua:682`. Re-derive rather than trusting these:
  `git grep -nE "tear(ing|s)? (it|them|the widget) down|take (the widget|them) down|torn down" -- doc/ ':!doc/development/wip/' CHANGELOG.md src/ tests/`.
- **The defect is what a developer concludes, not what the sentences say.** Each is true in its
  own frame — *hiding the widget without tearing it down* is precisely the property
  `D-WIDGET-AT-BOOT` bought — but a reader who meets *tear down* beside *the widget* infers an
  **object lifecycle**, and then reads *hide*, *submit* and *cancel* as points on it. **None of
  the three destroys anything**, and that is checkable:
  - `hide()` **flips `shown` and clears `love.state.user_input`, nothing more**
    (`D-WIDGET-AT-BOOT`: *"state flips on that instance, not construction and teardown"*).
  - **submit** leaves the widget shown by default — `after_submit` is a no-op
    (`userInputController.lua`, the stay-shown defaults; `D-EDIT-LIFECYCLE`).
  - **cancel** runs `before_cancel` → `model:cancel()` → `after_cancel` and **stays shown**:
    `cancel_flow` clears **content**, and clearing content is not tearing down a widget.
  The one place an instance really is destroyed is the **project run's end**, which is
  `D-WIDGET-AT-BOOT`'s per-run boundary and has nothing to do with any of the three verbs.
- **Why this is worth an entry rather than a sweep.** The fix is **not** to delete *tear down*:
  it names the real thing at every one of those sites, and the ruled `shown`/`hidden` pair
  deliberately does not cover it. What is missing is that the corpus never says the **submit /
  cancel** pair and the **hide** verb are all non-destructive, in one place, so the reader has to
  assemble it from four decisions. The likely shape is a clause in `../../input_api.md`'s
  `Vocabulary` → *Widget* entry naming the three and what each does **not** do, and a matching
  one on `D-WIDGET-AT-BOOT`.
- **The pending proposal is what makes it urgent rather than tidy** (owner, 2026-09-05).
  `../../input_api.md`'s proposals block carries *"#### 4. Escape hides, and does not clear"* —
  **non-destructive hide on cancel**, not ratified but considerable. If it lands, cancel stops
  clearing and starts **hiding**, so the word *hide* has to already mean *"stops being on screen,
  and nothing is destroyed"* by the time a reader meets it there. Absorbing that proposal into a
  corpus where *hide* sits beside *tear down* is how a developer concludes the widget is gone.
- **Reachability:** every project author reading the guide or either decision. No runtime effect;
  the cost is a wrong mental model, and the mental model decides whether they write
  `after_cancel` to rebuild state that was never lost.
- **Provenance: ours.** Both the vocabulary and the lifecycle are this feature's. The word *tear
  down* is not the branch's invention, but *hide*, *submit* and *cancel* as a triple are.
- **Found:** 2026-09-05 by the owner, reading `FIX-02-09`'s residual list. The sweep's decision to
  keep these was right, and the owner's point is the one the sweep could not see from inside its
  own rule: **a word correctly kept can still mislead, when what misleads is the pairing rather
  than the word.**
- **Roadmap:** `FIX-02-30`.

### T-BLOCK-AT-OPEN — the editor's opening selection moved, and no document says so

- **Where:** the editor's opening path — `src/model/editor/bufferModel.lua`, which our merge took
  from upstream PR #45 whole (`git diff f4cf338c HEAD -- src/model/editor/bufferModel.lua` →
  empty, so ours is byte-identical to theirs). Observable from
  `tests/input/input_widget_callbacks_spec.lua`, *"editor Alt+Enter, an unclaimed variant"*.
- **What changed.** Before the import the editor opened with the **last** block selected; at HEAD it
  opens with the **first**. Measured on the document `{ 'first line', 'second line', '' }` that
  three of our cases use: at `21eb7f53^` the selection was **3** and `up` walked to `'second line'`;
  at HEAD it is **1**, `up` moves nothing, and Enter loads `'first line'`. The HEAD half is no
  longer a probe — the Alt+Enter case asserts `{ 'first line' }` literally as of 2026-09-06.
- **What is owed is a record, not a change.** The behaviour is upstream's, deliberate, and taken
  faithfully; nothing here proposes to reverse it. The obligation is `MERGE-01-05`'s own rule, which
  this corpus applied correctly once in the same range and missed here: **a behaviour change gets a
  record and a renaming does not.** `T-NAV-ESCAPE` exists because that rule was followed; this entry
  exists because the import's re-pins classified the same class of change as a renaming — the commit
  that moved this case said it *"needed only its setup moved from Escape to Enter"*, and it needed
  more than that.
- **Where the record belongs is deliberately not decided here** (owner, 2026-09-06). The candidates
  are the editor internals doc, `CHANGELOG.md` if the release is judged to be shipping it to users,
  and the guide if anything there predicts the old selection. Choosing among them is the work; doing
  it now, from a session that is not fixing it, would be guessing.
- **Reachability: every time the editor opens**, which makes it broad and undramatic — nobody loses
  data and nothing misbehaves. **The cost is to us, not to users**, and it has already been paid
  once: navigation cases written before the import have setups that no longer navigate. Three still
  press an `up` that walks from the top of the document to the top of the document; one has been
  dropped with a comment, the two in *"editor Escape falls through to the widget"* are harmless and
  left. A reader debugging any of them will assume the selection moved.
- **Found:** 2026-09-05 by session75's delivery review (its `F3`), while checking whether the
  import's five re-pins were renamings or behaviour changes. Four were what they claimed; this was
  the fifth. **Registered as its own entry by owner ruling, 2026-09-06** — the review had proposed a
  clause on `T-NAV-ESCAPE`, and a documentation obligation that lives as a sub-clause of another
  entry's *"what changed"* is not findable by anyone looking for it.
- **Roadmap:** `DOC-01-03` (owner ruling, 2026-09-06). It is a documentation obligation with no
  mechanism to build, and it is release-scope because the release imports the change — so it belongs
  to the sprint that passes over the internals docs rather than to one that changes behaviour.
  **The row inherits the open question above rather than closing it:** which document takes the
  record is still the work, and `DOC-01-03`'s pass is where a writer has all three candidates open
  at once. *(Opened with no row on 2026-09-06 and slugged the same day, after the S76 delivery
  review named the gap: an `ACTIVE` entry with no roadmap row is release-blocking work nobody has
  scheduled.)*

### T-EXAMPLE-README — two shipped example READMEs still teach the removed polling idiom

- **Where:** `src/examples/repl/README.md` — the *"How this translates into code"* block
  (`r = user_input()`, `r:is_empty()`, `local input = r()`) and the two-options list under it
  (`input_text()`, `input_code()`); `src/examples/valid/README.md` — the opening sentence and the
  worked snippet (`user_input()`, `validated_input({non_empty})`).
- **State:** both examples' `main.lua` **are** onboarded onto `compy.input`. Only the READMEs were
  left behind, so each project ships working code beside a document teaching an API that no longer
  exists — a reader following the README calls a `nil`.
- **Why this is not the entry beside it.** *"Per-example internals docs still describe a retired
  polling idiom"* covers `../internals/examples/*.md`, a different set of files in the development
  corpus. These two ship **inside the example project**, which is the first place a project author
  looks, and neither entry's sweep would have found the other's files.
- **Size: not a find/replace.** `repl`'s README is a tutorial whose narrative *is* the poll loop —
  create a handle, test it for emptiness, read the value — and the replacement has no handle and no
  polling at all. Each needs a real rewrite, the same conclusion the internals-docs entry reached
  about its own set.
- **Found:** 2026-09-03, while base-checking `FIX-02-17` by differencing `project_env`'s keys at
  `3256aac` against HEAD. Nothing was looking for it; the retired names simply still had hits.
- **Release scope, ruled by the owner 2026-09-03** — filed `BACKLOG` on the day it was found, with
  the argument stated both ways, and promoted the same day: *"document README drifts as active
  defects to be fixed."* Shipped, project-author-facing documentation that is now false is a defect
  the release would otherwise ship.
- **Roadmap:** `FIX-02-27`.

### T-SEAM-UNRATIFIED — *"seam"* is this feature's own word, and it is load-bearing in ~30 corpus sites

- **The measurement, and this entry is inside it.** Re-run
  `grep -rn "seam" doc/ --include=*.md | grep -v "wip/"` rather than citing a figure: it returned
  **30** when this entry was written and **38** a few commits later, because the entry's own prose
  discusses the word at length. **The share and the named sites are citable; a total is not** — the
  same trap `T-EPHEMERAL-IDS` documents for sprint ids. It was **about thirty sites** across `technical_debt/input.md`, `decisions/input.md` and `internals/user_input.md`.
  **At the PR base there are none**: `git grep -c "seam" 3256aac -- 'doc/*' 'src/*'` is empty. The
  word entered with this feature's own analysis.
- **It is not one word, it is two uses.** Most sites use the ordinary software sense — *a place where
  behaviour can be altered without editing in place*: the `love.*` capture seam, the run seam, the
  matcher seam, the activation seam. That usage is standard and defensible. **One site uses it as a
  name for a defect class**, `T-EDITOR-SEAM-DEFAULT-OPEN`, and there it buries the claim: what the
  entry is about is that the editor's **key pass-through defaults to open** and the block list lives
  in another feature's file. A reader who does not already know that cannot get it from the slug.
- **The owner adopted it back**, which is how this class becomes invisible: `decisions/input.md`
  records *"a seam the owner names as dirty but justifiably tolerable and easily removable"*
  (2026-09-05). **That is the same path `T-CHROME-UNRATIFIED` took** — a word minted by the analysis,
  used back to the owner, and thereafter treated as vocabulary we had.
- **Raised by the owner, 2026-09-07**, on the defect-class use: *"mistakenly named seam, which I'd
  discourage"*.
- **What is owed is a judgement, not a sweep.** Three options and they are not equally cheap:
  keep the ordinary sense and rename only the defect entry (cheapest, and the slug appears in **no
  code** — `grep -rn "T-EDITOR-SEAM" src/ tests/` → nothing, so renaming is cheap by
  `agents/rules/roadmap.md`'s own renumber-vs-rename test); replace the word everywhere with the
  thing it names in each site; or ratify it in the glossary as this subsystem's term.
- **Why it is filed rather than swept now:** the corpus compaction pass reads every one of these
  sites anyway, and a vocabulary sweep run before it is a broom over a moving floor. **Read with
  `T-CHROME-UNRATIFIED`** — same class, same remedy, and the two should be ruled together.
- **Found:** 2026-09-07, by the owner questioning one entry's name.
- **Roadmap:** `DOC-01-03`, which is the pass that reads `decisions/` and `internals/`.

### T-CHROME-UNRATIFIED — *"chrome"* is this feature's own word for the host surfaces, and no ledger ratifies it

- **What it names:** the three permanent input surfaces a host owns — the console line, the editor's
  input strip, the editor's search strip — as against a project's transient widget. The distinction
  is real and ratified; the **word** is not.
- **It is ours, and the check is the one the phase prescribes** — compare against the PR base.
  `git grep -il "chrome" $(git merge-base master HEAD) -- src/ tests/ doc/` returns exactly one
  path, `src/assets/fonts/ubuntu_mono_bold_nerd.ttf`, which is a glyph name inside a font binary.
  The same query against `master` returns the same single font. **The word appears nowhere in the
  base's prose or code**, so it entered with this feature.
- **Where it entered:** `git log -S"Host chrome" --format='%h %ad %s' --date=short` → the comment
  now at `src/controller/editorController.lua`, *"Host chrome, not a transient widget"*, whose
  wording dates to `25b9742e` (2026-08-07), *"fix(input): make `always_shown` a guarantee, not a
  convention"*. It was minted while arguing that entry's own construct, which is
  `T-ALWAYS-SHOWN-UNRATIFIED`.
- **Its reach in the persistent corpus is three sites**, and they are the whole of it:
  `src/controller/editorController.lua` (the comment above),
  `tests/input/input_widget_control_spec.lua` (*"they are host chrome, not a"*), and
  `technical_debt/input.md`'s `T-ALWAYS-SHOWN-UNRATIFIED` (*"Host chrome has to start visible
  without a `show()`"*). Re-derive with
  `grep -rn "chrome" src/ tests/ doc/ --include=*.lua --include=*.md | grep -v 'wip/'`; the
  example projects' own `chrome pastel` is a colour name in a nested repo and unrelated.
- **Why it is registered rather than swept.** The vocabulary this feature may mint is the owner's
  call, and one has already been made in this family: *"prompt"* was **ruled out** as a fifth name
  for the widget. *"Chrome"* is a borrowed UI term of art, not a name the design ratified, and it
  survived the terminology unification pass (`FIX-02 (c)`) because that pass swept the names it knew
  about. Three outcomes are open: ratify it into the glossary, replace it (*host surface*,
  *permanent surface* — the latter is already the phrasing of `always_shown`'s own doc comment), or
  leave it as informal comment vocabulary with the decision recorded.
- **Found:** 2026-09-06 by the owner, in conversation, on hearing the assistant use it — *"why word
  'chrome' started appearing in our conversations?"*. The assistant had picked it up the same day
  from the code comment above while reading `always_shown`'s construction sites, which is the
  mechanism the phase already knows about: **unratified vocabulary in the corpus becomes the
  vocabulary of everything written from it.**
- **RULED 2026-09-06: replace it, do not ratify it.** The owner: *"I do not think we need either
  'chrome' term or `always_shown` guarantee."* One ruling settled both, as the entry anticipated —
  the word and the construct were minted in the same commit. The replacement is **not** a
  find-and-replace to a single token: each of the three sites is a sentence that can say what it
  means (*the console's and the editor's permanent input surfaces*), and `always_shown`'s own doc
  comment already reaches for *permanent surface* without needing the borrowed term.
- **The word outlived the construct it was minted with, 2026-09-09.** The owner reversed the
  `always_shown` half of the 2026-09-06 ruling — the guarantee stays, and is now ratified at
  `../decisions/input.md`, `D-WIDGET-AT-BOOT` — while the replacement of *"chrome"* stands as
  ruled. So the pair is no longer read together as one remedy: the construct is ratified and this is
  a vocabulary sweep of three sentences, the third of which is `T-ALWAYS-SHOWN-UNRATIFIED`'s own
  text in `RETIRED` below.
- **Roadmap:** `DOC-01-03`, moved there by the same reversal, which closed `SHOWN-01` — the owner:
  *"the only actionable item is removing word 'chrome' — this step goes to the docs sweep pass."*
  **Read with `T-SEAM-UNRATIFIED`**, which is the same class (a word this feature minted, never
  ratified) and already lands on that row. **Two of the three sites are code comments** rather than
  prose, which is the one way this differs from that row's other work.


## BACKLOG

### T-REPLACE-NEEDS-POSIX-RENAME — a save renames over the file, which Windows' rename refuses

- **Where:** `src/util/filesystem.lua`, `FS.replace` → `FS.rename` → `os.rename`.
- **Scenario:** under Windows, saving a file that exists fails: the C runtime's rename refuses an
  existing target, so every save after the first, every checkpoint overwrite and every restore
  fails.
- **Why it stays (2026-09-30):** there is no Windows build; Linux and Android rename over an
  existing file, and the card does too (checked on a Compy). `FS.replace`'s comment says so.

### T-GLYPH-ONLY-SPACE-ANSWERS-NOTHING — a keyboard that sends a Space as text alone cannot answer an editor question with it

- **Where:** `src/controller/editorController.lua`, `_dialog_textinput`: while a question is open a
  glyph neither answers nor cancels it; only a fresh key press does (`keypressed`).
- **Scenario:** on an on-screen keyboard, which sends a Space as text with no key press, Ctrl+Q asks
  about a changed block and Space does nothing. Enter still answers: it arrives as a key press.
- **Why it stays (2026-09-30):** a glyph carries no repeat flag, so letting one answer let a held
  Space give consent to questions the person never saw. The Compy has a hardware keyboard, whose
  Space sends a key press.

### T-MOUSE-LEAVES-QUESTION — with editor mouse input on, a click leaves a question on another block

- **Where:** `src/controller/editorController.lua`, the mouse navigation that accepts an open block
  and leaves edit mode without dropping `pending_confirm`.
- **Scenario, with `cfg.editor.mouse_enabled = true`:** change `x = 1` to `x = 2`, raise
  `Shift+Esc`'s question, click the line `y = 1`. The block is accepted and the question stays;
  Enter answers it against `y`, recording a discard pair, and Ctrl+Z then deletes `y` from the file.
- **Why it stays (2026-09-30):** the shipped build turns editor mouse input off (`src/main.lua`).
  A fix drops the question on any pointer action that moves the selection or leaves edit mode.

### T-LATE-CHORD-GLYPH-CANCELS — a chord's glyph arriving after its modifiers are up cancels the question

- **Where:** `src/controller/editorController.lua`, `_dialog_textinput`: a glyph is taken as part
  of a chord only while Ctrl or Alt is held.
- **Scenario:** change a block, press and release Ctrl+Q, then its glyph `q` arrives. The question
  is cancelled; Enter then accepts and saves the draft, and the exit is not taken.
- **Why it stays (2026-09-30):** a Compy delivers a key's glyph before its press, so the order does
  not arise there, and nothing is lost when it does: the draft is kept and Enter saves it.

### T-PROGRAM-SWITCH-DROPS-DRAFT — a program that switches projects under the editor drops its draft

- **Where:** `src/controller/consoleController.lua`, `open_project` → `_close_project` →
  `stop_project_run` → `finish_edit`, reached from a program's own code; the editor's exit question
  (`EditorController:ask_to_leave`) sits on the gate's chords and is not consulted.
- **Scenario:** a program that stays idle in `ready` keeps a pointer hook that calls
  `project('b')`. Open the editor, change a block, click: the hook switches projects, the editor
  closes, and the change is gone unwritten and unasked.
- **Why it stays (2026-09-30):** older than this branch, and it needs a program that switches
  projects under the person editing. Asking there means teardown that can wait for an answer: the
  program's `project()` call would have to be deferred until the question is answered, which is
  more than a contained change.

### T-CTRL-ESC-DROPS-CHANGE — Ctrl+Esc exits the IDE with a changed block open, unasked

- **Where:** `src/controller/controller.lua`, the `keyreleased` reservation
  `['ctrl+escape'] = Application.request_application_exit`, which no editor question guards;
  `love.quit` lets the exit through in `app_state == 'editor'`.
- **Scenario:** change an open block, hold Ctrl, press and release Escape. The IDE exits; the draft,
  and any draft `Ctrl+J` left in another file, were never written.
- **Why it stays (2026-09-30):** `Ctrl+Esc` is the untaught key that leaves the IDE from any state,
  and the keys are frozen for 0.5.0. `../decisions/input.md`, `D-EDITOR-KEYS` statement 6 and the
  input guide say it does not ask. A fix would route the reservation through
  `EditorController:ask_to_leave` and request the exit on confirmation.

### T-HISTORY-UNREACHABLE — no project-facing way to read, navigate or clear the input history (capability deferred; the limitation is documented)

**MOVED FROM `ACTIVE` TO `BACKLOG` 2026-09-09 (session89).** The entry was `ACTIVE`
for one reason: the release ships a `clear_on_submit`-on default that writes every
submitted line into a store a project cannot read, so the guide had to *say so*.
**That documentation is now paid** — `../../input_api.md`, *"The widget's input
history is its own, not yours to read"*, in the `hide()`/`get_text` section, which
states that the history is the widget's own, that a project keeps its own list, and
that `on_limit_reached` is the trigger the console itself uses. With the limitation
documented, nothing release-blocking remains; what is left is a capability, and it
is deferred.

- **What is deferred:** a project-facing way to **read, navigate or clear** the
  widget's history. `src/model/input/userInputModel.lua` holds `history` (a
  `History`, sized from `cfg.input_history`) with `history_back` / `history_fwd` on
  the model and controller; the public surface reaches none of it.
- **Why `BACKLOG` and not `ACTIVE` — the provenance test (owner rule, 2026-09-09).**
  `ACTIVE` would require the capability to have been **explicitly requested by a
  stakeholder** in the attestations that formed `PROP-01`. It was not: the proposal
  block never mentions history, and @nagydani's attestation of 2026-09-07 (A2) names
  key handling and a **general objective** — *"the API should make it possible to
  write programs similar to the IDE"* — not a history or recall surface. The gap is
  **our** finding, derived by measuring the shipped surface against that objective;
  the owner ruled it *"let it be, documented"* (2026-09-07). A capability we invented
  against a stakeholder criterion and the owner deferred is deferred-past-release
  debt, which is what `BACKLOG` is for. *(It keeps its `T-` slug: a slug is earned
  when an entry is `ACTIVE` and kept thereafter.)*
- **How the IDE does it (the shape a later release would expose).** The console
  builds recall on the **public** `on_limit_reached` callback and finishes with
  **internal** methods (`src/controller/consoleController.lua`): at the vertical
  boundary it calls `IC:history_back()` / `IC:history_fwd()`. A project gets the
  trigger and not the action, so a child copying the console keeps a parallel list
  and drives it with `set_text`. Buildable; not parity. The smallest honest
  capability is a read/navigate pair beside `get_text`, inheriting every boundary
  question `../decisions/input.md`'s `D-CFG-BOUNDARY` already answers.
- **Not the console/project "same space" request** (owner's question, 2026-09-07):
  there is no single input history — one exists **per widget instance**. The
  console's is built at boot and lives for the session; a project's is built at run
  start and dropped at stop, with its own `UserInputModel` and `History`. A project
  reading its own widget's history crosses no boundary and moves no sandbox. Two
  things make the gap smaller than it looks: a project's history **dies with its
  run**, so recall is within-run; and `input_history` (`src/main.lua`, 1000) is
  shared as a **number**, not as a store.
- **Found:** 2026-09-07, by the second analysis of @nagydani's attestation, not by
  the proposal block.
- **Revisit:** a later release that chooses to expose recall on the public surface.
  Not owed by this one.

### `compy.input` in the console environment is required and unmet — DEFERRED, with its own workspace

**The obligation stands and this release does not meet it.** Owner, 2026-09-08: *"tools are not part
of nearest release … making it working in console is a separate design task which we half-designed
(and which shape may change if sandboxing mechanics is reviewed)."*

- **What the release does instead:** removes the `input` member from the console namespace
  (`T-CONSOLE-SURFACE-INTERFERES`, option (a)), so the surface that never worked raises rather than
  misbehaves, and the PR base's asymmetry is restored.
- **Where the detail lives:** `../wip/input-in-console/` — the drafted design, its spec, and a draft
  register carrying the full entry (`T-CONSOLE-INPUT-UNUSABLE`). It was ACTIVE here until
  2026-09-08 and was moved, not dropped.
- **A blocker that precedes the design and is NOT ours:** a module `require`d at the prompt runs in
  the **project's** environment whenever the project hooks `love.update` or `love.draw` — the project
  loader `setfenv`s each chunk with `get_effective_env()`. Verified at the PR base `3256aac`,
  unchanged by this feature.

### The empty-submit guard is inherited from the console and was never ruled

- **Where:** `src/controller/userInputController.lua`, `submit_flow` —
  `if self.model:get_text():is_empty() then return end`, the second line of the flow.
- **It predates this feature.** The identical line is at the PR base
  (`git show 3256aac:src/controller/userInputController.lua`), inside a `submit()` whose body then
  called `input:evaluate()`. **It is the console's rule** — an empty line has nothing to evaluate —
  and it became every widget's rule when the widget became project-facing. Nobody generalised it on
  purpose; it was simply already there, and `../decisions/input.md`, `D-DEFACTO-KEPT` is the reason
  it survived unexamined.
- **It is documented but not argued.** `../../input_api.md` states it twice — *"On a **non-empty**
  submission the order is…"* and *"a `before_submit` veto, an **empty widget** or a rejecting
  validator all leave it shown"* — and `D-LIFECYCLE-FLAGS`'s ordering table names *"empty guard"* as
  a step. **No decision says why**, and none weighs it against a project's use.
- **The open question is whether `''` is legitimate content.** For a console line it is not. For a
  project prompt it plainly can be — *"press Enter to skip"*, an optional field, a default the user
  accepts by answering nothing. Today those are unreachable: Enter on an empty widget does nothing
  and the project is not told.
- **One wart it already produces:** `before_submit` runs **before** the guard, so a project's veto
  callback fires on an empty Enter and the flow then stops silently. With one payload for every
  content callback (`T-ONE-PAYLOAD`), that callback will at least receive `''` and be able to tell.
- **Why it is filed rather than fixed:** no stakeholder asked for it, the release already carries
  several deliberate default changes on this surface, and removing a guard that two documented
  sentences describe is a documented-contract change of its own. **Filing it converts an inheritance
  into a decision**, which is the point.
- **Nothing else depends on it.** In particular the simple surface's *cancellation answers with
  `nil`* does **not**: Lua's `''` is **truthy**, so `if text then` separates *answered with nothing*
  from *abandoned* whether or not the guard stays.
- **Found:** 2026-09-07, by the owner asking where the guard came from and whether `''` is legit
  text. The honest answer is that nobody decided it.
- **Revisit:** with any future work on the widget's submit path, or whenever a project needs an
  optional answer.

### T-CTRL-S-UNCLAIMED — the reason bare Ctrl+S stopped closing the buffer is not true

**RULED AND MOVED TO `BACKLOG`, 2026-09-07** (owner, at `MERGE-01-08`): *"we do not intervene, ship
what was shipped by #45, mark unbound Ctrl+S a tech debt (backlog). maybe they will rebind it
later."*

**What is ruled is the behaviour question, which is the only thing that was open.** The false
premise was corrected at four sites on 2026-09-05; what waited was whether to take our
`close_buffer()` back now that *unclaimed* had been shown not to be *reserved*. **The answer is no —
we do not intervene.** Bare Ctrl+S ships as #45 ships it: doing nothing in the editor.

**The reasoning is the owner's and it is about ownership, not about cost.** The key is
**theirs to rebind**, and re-taking a binding they had just vacated would re-assert a claim on a
surface this release has said twice is not ours to define (`D-EDITOR-KEYS` statement 3). *"Maybe they
will rebind it later"* is the disposition: the key stays unbound and available rather than
re-occupied by us.

**What ships is a loss against pre-feature functionality, and it is knowingly taken** — before the
import, bare Ctrl+S closed the editor buffer. That is why this stays a debt entry rather than
retiring: the record of a capability given up, kept so that a later reader finds the reason rather
than the gap. **It does not block the release** — the code already behaves this way, and the
comment stating the correct reason is on `reserved_stop_run` (moved there 2026-09-07, so that a
future author adding an editor branch meets the constraint at the site).

- **Where:** the claim, as this corpus stated it for one day — *"upstream PR #45 reserves bare
  Ctrl+S for its checkpoint"*. Corrected at four sites the same day
  (`../decisions/input.md`, `D-EXACT-RESERVE`'s amendment; `../internals/user_input.md`'s
  worked Ctrl+S walk; `src/controller/editorController.lua`'s `_leave_keys`;
  `tests/input/input_global_shortcuts_spec.lua`'s reservation pair). The **original** statement
  is older than the import — it is in `T-DRIFT-PR45`'s filing (`general.md`, now `RETIRED`),
  written when the merge was still being planned.
- **What is actually true**, measured against the imported base `f4cf338c`:
  - #45's checkpoint is **`Ctrl+K`**, restore is **`Ctrl+Shift+K`** —
    `git show f4cf338c:src/controller/editorController.lua` at `checkpoint_key()`, which returns
    early unless `k == 'k'`.
  - #45's **own** `doc/EDITOR.md` lists **`Ctrl+K` / `Ctrl+Shift+K`** for checkpoints, and its
    only `Ctrl+S` row is ***"Stop project"*** — the platform reservation, not an editor claim.
  - What #45 actually did to `controller.lua` is **one deletion**: upstream's
    `CC:close_buffer()` on bare Ctrl+S in the editor branch.
  - **The sole source of "reserved for the checkpoint" is a comment #45 left in place of that
    deletion**, which its own bindings contradict.
- **So bare Ctrl+S in the editor is UNCLAIMED, not reserved**, and the difference is the whole
  entry: a reserved key is a collision and an unclaimed one is a choice.
- **What this reopens, and it is the owner's.** The 2026-09-04 ruling has two halves. *"#45 holds
  the product authority"* still stands — they deliberately removed the close, in their own
  subsystem. *"Their checkpoint reservation stands"* is **false**, and it was the half that made
  deferring look free. **Our `close_buffer` on bare Ctrl+S could have been kept with zero
  collision**, so what was taken as a forced concession was an unforced one. The behaviour is a
  **loss against pre-feature functionality** — bare Ctrl+S closed the buffer at the PR base and
  does nothing now — and whether to accept it is a product call, not a merge call.
- **It is ORIGINAL to #45, not collateral from its force-push** (checked 2026-09-05 after the
  owner raised the opposite hypothesis — that the unbinding looked like a slip made while
  compacting 52 commits into 9). `git show 16eb33d7:src/controller/controller.lua` at `:592` is
  **byte-identical** to the imported version: old #45 already had the `close_buffer()` deletion,
  already carried this comment, already bound checkpoints to `Ctrl+K`, and its own `doc/EDITOR.md`
  already gave `Ctrl+S` one row, *"Stop project"*. **The reshape changed no executable content at
  all**, proven rather than assumed: each source file's non-comment lines were sorted before and
  after the force-push and compared, and the two sets are identical — the push corrected two
  documentation tables and nothing else.
  So the comment has been wrong since #45's first push, which makes this a **standing
  contradiction in their tree** rather than a fresh slip — and it *strengthens* the reading that
  the unbinding was deliberate.
- **A second contradiction rides with it, and it points at us.** Old #45's `doc/EDITOR.md` carried
  *"Leave editor (close all buffers) — `Ctrl+Shift+S`"*; **the force-push dropped that row while
  `controller.lua` kept the binding**, so upstream now has `Ctrl+Shift+S` **bound and
  undocumented**, with leaving documented only as `Shift+Esc`. That is the key
  `EditorController:_leave_keys` supplies on our side. **If they are retiring the spelling rather
  than merely de-documenting it, we are holding a door open they mean to close** — a question for
  them, not an inference for us.
- **Both contradictions are upstream's to resolve** (owner, 2026-09-05: *"we need to record
  contradictions and sort them out with Vadim"*). Nothing here proposes changing #45; what is
  recorded is that our ruling rested on a reason #45's own code does not support.
- **Why it was believed.** #45's comment is inside the block our `RESERVED` table replaced, so it
  was read as the authority on the key it sits beside. **This project had already measured it
  correctly five days earlier** — `REC-01`'s drift measurement recorded *"**checkpoints** on
  Ctrl+K / Ctrl+Shift+K"* and *"bare Ctrl+S no longer closes the editor"* as **two separate
  facts**. **A measurement was on disk and a comment was read instead.**
- **Reachability:** the false reason reached the decisions ledger, an internals doc, a `src`
  comment and a spec comment before it was caught — one day, four sites, and it would have
  reached the PR description as a justification line.
- **Found:** 2026-09-05 by the S75 delivery review, which checked #45's bindings instead of
  accepting the session's reading of #45's comment.
- **Roadmap:** `MERGE-01-08`, **closed 2026-09-07**. It was blocked on an owner ruling rather than on work, and the ruling is the header of this entry: *do not intervene*.

### T-EDITOR-SEAM-DEFAULT-OPEN — our widget acts on every editor key the editor does not block, and the block list is theirs

- **Where:** `src/controller/editorController.lua`, `_normal_mode_keys` — `passthrough` initialises
  to **`true`** and `block_input()` clears it; the tail reads `if passthrough then
  input:keypressed(k) end`. So `src/controller/userInputController.lua`'s `keypressed` runs on the
  editor route for **every key the editor did not explicitly claim**.
- **The defect is not that a seam exists. It is that the seam's default is open and its enforcement
  lives in the other feature's code.** Our blast radius on that route is decided by `block_input()`
  calls in a file this branch does not own; when that file changes, **nothing fails**, because an
  expectation cannot fail. That is why `T-NAV-ESCAPE` was found by an unrelated spec rather than by
  a test.
- **Provenance: CORRECTED 2026-09-07, and the correction is most of this entry's weight.** The
  earlier text read *"ours, and it is an inversion rather than an omission"*, said upstream ran an
  **allow-list** under which *"an unclaimed key therefore did nothing"*, and said Phase R *"turns an
  allow-list into a block-list"*. **Both halves are wrong**, and the owner found it by asking whether
  the machinery was ours or pre-existing. Measured:
  - **The `passthrough` / `block_input()` gate is UPSTREAM'S and pre-dates this branch entirely.**
    `git show 3256aac:src/controller/editorController.lua | grep -c "passthrough\|block_input"` →
    **14**, identical at `af9a5782`; #45 grew it to **29**, which is also HEAD. **We did not turn an
    allow-list into a block-list — the block-list was always the outer gate, and it is still theirs.**
  - **The widget's own `app_state == 'editor'` fork was not an allow-list either.** At the base its
    editor arm ran **nearly the whole handler set** — `removers`, `horizontal`, `vertical`,
    `newline`, `modify`, `copypaste`, `selection`, `submit` — so an unclaimed key did **almost
    everything**, not nothing. **The fork differed both ways**: the editor arm omitted **`cancel`**,
    and the other arm omitted **`modify()`** — so the difference that matters for *this class* is
    `cancel`, the one handler that the un-fork **added** to the editor route. `modify()` kept its
    editor-only scope through the un-fork as a constructor flag, so it moved nowhere.
  - **So what Phase R actually changed is one handler.** `affc9320` (2026-07-21, *"un-fork UIC
    app_state"*) removed the fork; `modify()` kept its editor-only scope as a constructor flag
    (`-  if love.state.app_state == 'editor' then / -    modify()` → `+  if self.allow_modify then
    modify() end`), and **`cancel` joined the editor route**. Nothing else moved.
  - **That one handler is `T-NAV-ESCAPE`, and it was latent until #45.** The editor claimed Escape,
    so our cancel was unreachable; #45 moved the load onto Enter and the discard onto `Shift+Esc`,
    stopped claiming bare Escape, and the latent path went live. **That is the `R11` class exactly —
    *they changed a line we moved*.**
  - **Consequence for release scope:** the class's other live members (`Ctrl+D`, `Shift+Enter` in
    nav) are **pre-existing upstream behaviour**, not regressions this branch introduced — `modify()`
    and `newline()` reached the editor route at the base too. **`FLAGS-01` removes our only
    contribution** (the cancel), after which **this branch adds nothing to this class**.
- **Known live instance: one.** `T-NAV-ESCAPE` — bare Escape reaches `cancel_flow`, whose clear is
  hardwired past the callbacks. **Cleared instances:** `Alt+↑/↓` (our `swap_line` is destructive,
  but the editor takes the whole `Alt` branch with `block_input(); return`, and its comment records
  the deliberate retirement of the block swap).
- **The rest of the class was PROBED 2026-09-06** (throwaway spec against `input_fixture`, driving
  the real wired editor; nothing under `tests/` touched), and the result is what decides whether the
  seam must be closed structurally for this release:
  - **`Ctrl+D` in nav — LIVE.** The widget's `modify()` duplicates its current line: content goes
    from one empty line to two. `allow_duplicate_line` is true for exactly this widget.
  - **`Shift+Enter` in nav — LIVE.** `newline()` adds a line feed to the widget's pending input.
  - **bare `backspace` and `Ctrl+W` in nav — inert.**

  **The mechanism behind each, added 2026-09-07 so the list survives without the probe** (which was
  a throwaway spec and is gone — that is itself the point of the entry):
  - **Why any of them arrive:** `_normal_mode_keys` leaves `passthrough` true for keys it does not
    claim, and the tail runs `input:keypressed(k)`. Nav claims `ctrl+c/x/v`, `ctrl+z/y`, `ctrl+k`,
    `ctrl+enter`, `shift+delete`, `shift+insert`, `shift+escape`, the `alt`/`ctrl` arrow families,
    plain `delete` and plain Enter — **not** `ctrl+d`, **not** `shift+enter`.
  - **`Ctrl+D`:** the widget's `modify()` is `if Key.ctrl() and k == 'd' then
    input:insert_text_line(input:get_current_line())`, reached because the call site is
    `if self.allow_duplicate_line then modify() end` and the editor constructs its widget with that
    flag **true**. In nav the user is not typing, so the effect lands in a pending input nobody is
    looking at: one empty line becomes two. **Cruft, not loss** — and `doc/EDITOR.md` documents
    *"Duplicate current line — Ctrl+D"* under **Input**, so the handler is wanted; what is wrong is
    only the context it is reachable from.
  - **`Shift+Enter`:** `newline()` is `if Key.shift() and Key.is_enter(k) then input:line_feed()`.
    Same shape, same document (*"Insert newline — Shift+Enter"*).
  - **Plain Enter, the double dispatch:** the editor accepts the block **and** the widget's
    `submit_flow` runs. Inert because the editor sets **no callbacks** on its widget and `auto_hide`
    is `nil` there, so the flow reaches its end with nothing to call and nothing to hide.
  - **`backspace` / `Ctrl+W`:** `removers()` runs, but `backspace()` on an empty pending input has
    nothing to delete, and `backspace_word()` is gated on `input.editing`, which nav is not.
- **`always_shown` is NOT the guard for any of this, and the distinction matters because it is the
  obvious place to look** (owner's question, 2026-09-07). The editor's widget **is** `always_shown()`
  (`editorController.lua`, with the search strip likewise), and the flag guards **`hide()` alone** —
  `cancel_flow` does not consult `self.always`, so an Escape that reaches the widget clears whether
  or not the flag is set. **Restoring or keeping that guard would not have prevented `T-NAV-ESCAPE`**;
  what prevents it is the cancel flow ceasing to destroy unconditionally, which is `FLAGS-01` and is
  on **our** side of the boundary — no change to the editor's dispatch required, which is what
  `OP-03` judged.
  - **Plain `Enter` on the accept path — LIVE, and it confirms the double-dispatch.** Instrumenting
    `submit_flow` shows **one call** after Enter accepts a block in edit mode: the editor accepts
    *and* the widget's submit flow runs. Both lifecycle verbs double-dispatch, exactly as the
    symmetry predicted.
- **But none of the live members is a defect, and that is the finding.** `Ctrl+D` and `Shift+Enter`
  are **documented editor behaviour** — `doc/EDITOR.md` lists *"Duplicate current line — Ctrl+D"*
  and *"Insert newline — Shift+Enter"* in the **Input** section, and its Editor section reads
  *"same as Input, except for:"*. So the editor **wants** those keys in its text field; what they
  leave behind in navigation is stray content in a pending input, which is cruft rather than loss.
  The `Enter` member is observably inert (no callbacks, `auto_hide` nil). **After the cancel flow
  stops destroying content, this class has no member that loses data or contradicts the editor's
  own keymap** — which is why closing it structurally is a recommendation and not a release gate.
- **What bounds the damage today, and it is worth stating because it is what makes a fix cheap:**
  the editor sets **no callbacks at all** on its widget
  (`grep -n "callbacks\|after_submit\|before_cancel" src/controller/editorController.lua` → no
  hits), so it carries `default_callbacks()`; and `auto_hide` is `nil` on it, being reachable only
  through `configure`, which is the project surface. So `submit_flow` is **inert** there and
  `cancel_flow`'s only live effect is the unconditional clear.
- **Reachability:** every key press in the editor. Harmless per-key until our side grows a
  destructive handler for a key their side stops claiming — which is what happened once already.
- **What the decline does and does not accept, restated after the provenance correction.** It does
  **not** accept shipping a defect of ours in the hope it will not fire: after `FLAGS-01` this branch
  contributes **no** member to the class. What it accepts is **declining to restructure a
  pass-through that is upstream's, pre-dates us, and whose current members are their documented
  behaviour**. **The residual risk is real and it is invisibility, not damage**: nothing fails when
  either side changes, because an expectation cannot fail.
- **A mitigation cheaper than the migration, and it addresses exactly the invisibility:** pin the
  measured members in a spec — `Ctrl+D` and `Shift+Enter` in nav leaving stray content, plain Enter
  double-dispatching inertly, bare `backspace` and `Ctrl+W` inert — so that the next change on either
  side **fails a test instead of being found by an unrelated one**. That is what the class has never
  had, and it is the reason `T-NAV-ESCAPE` was found the way it was. **Not scheduled: proposed**,
  and it belongs with `EDKEYS-01`, which is already the sprint that writes the editor's regression
  net.
- **Found:** 2026-09-06, by `OP-03`'s seam analysis, looking for the class rather than the instance.
- **RULED 2026-09-06: the release does NOT close this structurally.** The owner: *"we decided it
  does not. We provide compatibility and document a **recommendation** to move somewhere (likely in
  debt backlog) — maybe even with specific direction or migration plan."* So the seam stays open,
  the class ships registered rather than closed, and **what this entry owes is the direction**, which
  is written below rather than cited. The reasoning behind the decline is the measurement two bullets
  up: once the cancel flow stops destroying content, **no member of this class loses data or
  contradicts the editor's own keymap** — against which the migration is a large diff in a subsystem
  this branch does not own, with no line in the PR's justification table, in a release whose gate is
  reviewability from `doc/input_api.md` alone.
- **The recommended direction, stated here because the analysis that produced it does not survive
  the release.** Move the editor onto the same `dispatch(shortcuts, hooks, widget, event, trigger,
  ...)` chain the console and project routes already use. Four things make it a recommendation
  rather than an aspiration, and each was measured rather than argued:
  1. **The machinery was extracted for exactly this.** `dispatch` is a free function over plain
     tables (`src/controller/projectInputController.lua`) and `build_widget_api(get_widget,
     get_active_flag)` is a factory — `../decisions/input.md`'s implementation note says in terms
     that this was *"so that the mechanism a future console/editor adoption (`D-ROUTE-OWNS`) needs is
     reusable rather than bound to one controller's instance fields"*.
  2. **The shape fits, including the parts that are not combo-shaped.** `dispatch` runs
     `shortcuts[combo]` → `hooks[event]` → widget-terminal, each consuming on truthy. The editor's
     combo-shaped handlers map onto the shortcut table; the three that are not — submit/open selected
     by *is-empty and plain Enter*, the mode-dependent ownership of up/down, and the ordered
     fall-through — belong in `hooks.keypressed`, which runs after the combos, before the widget,
     with full access to mode and state.
  3. **The file was free when this was measured**, and that is a condition rather than a fact: the
     edge did not touch the editor route at all. **Re-measure before acting** — `git diff --stat
     <edge-base> <edge-head> -- src/controller/editorController.lua
     src/controller/userInputController.lua src/model/editor/` was empty on 2026-09-06 and says
     nothing about a later edge.
  4. **There is a safety net and it is the editor author's own** — the import brought **111** cases
     in `tests/editor/editor_spec.lua` and **29** in `tests/editor/buffer_spec.lua`, asserting his
     key semantics. Re-derive with `grep -c "it(" tests/editor/editor_spec.lua
     tests/editor/buffer_spec.lua`.
  **What it buys:** the class is closed structurally rather than registered, so it cannot acquire a
  new member the next time either side moves. **What it costs** is stated in the decline above, and
  whoever takes it also owes a device pass — a restructured editor route is a smoke surface.
  *(Do not look for an older plan: the fork-options study that predates this argues the seam INTO
  existence — option E is what we implemented — so it is stale for this purpose in the opposite
  direction from the usual one.)*
- **Roadmap:** the instance is `MERGE-01-07`. **This entry is the class, it is `BACKLOG` by the
  2026-09-06 ruling, and it is deliberately not slugged** — a slug is a commitment to fix before
  release and the ruling is that we do not. It is kept in full rather than compacted because the
  direction above is the deliverable the ruling asked for.

### PROPOSAL: the `love.*` capture is a seam, and the honest options are to wrap it or to drop it

- **Where:** `D-HOOKS-SEEDED` — a project's `love.*` handler is captured at
  activation and seeded as `compy.input.hooks[event]`, where it runs in hook
  position and its **return value now means *consume*** (`projectInputController.lua`,
  `dispatch`). LÖVE ignores that return; nothing about the signature changes and
  code written against LÖVE works as expected.
- **State: not a defect — a seam the owner names as *dirty but justifiably
  tolerable and easily removable*** (2026-09-05). Recorded so the tolerance is a
  stated position rather than something a later reader has to infer from the fact
  that nobody objected.
- **The two honest alternatives, neither taken:**
  - **Wrap the seeded handler in `fn.stop_here`**, which would imitate the old
    effect exactly: under LÖVE the project's handler *was* the end of the line, and
    `stop_here` returns `true` unconditionally (D-STOP-AND-SIDE). **This is what a
    released platform would owe its users.** It is declined here because the
    platform **is not released** — no userbase beyond our own reach, and the release
    is already backwards-incompatible, so a safety net paid for with a second
    implicit behaviour buys nothing.
  - **Remove the capture entirely**, decoupling `compy.input` from LÖVE's surface.
    The argument is ownership: a project that wants to overwrite a LÖVE primitive
    and break dispatch **should be able to**, and the capture quietly denies it.
    **This is the owner's preferred direction and is explicitly for a future
    discussion**, not this release.
- **Why it is worth an entry:** the two point in opposite directions — one adds
  compatibility, the other removes the coupling — and the thing that decides
  between them is **whether the platform has users**, which is a fact about the
  release rather than about the code. An entry keeps that reasoning attached to the
  seam; a later reader would otherwise re-derive it or, worse, treat the seam as
  load-bearing.
- **Provenance: ours.** The capture is this branch's.
- **Revisit: after the release**, and `PROP-01-01` if it comes up sooner. Not
  release scope: nothing here is broken, and both options are behaviour changes.

### PROPOSAL: a callback can be installed two ways, and neither is documented as primary

- **Where:** `compy.input.show{ on_text_entered = ... }` and
  `compy.input.callbacks.on_text_entered = ...` both install the same callback.
  `consoleController.lua`'s `api_show`/`api_configure` funnel config keys into the
  same store the `callbacks` table writes (`merge_callback_keys`), so the two are
  one mechanism with two spellings.
- **Scope, corrected 2026-09-05:** this entry is about the **two spellings**
  only. That the two are not offered for *every* callback is a **separate
  question with its own entry** — *"the three installation paths do not accept
  the same set"*, below. They were briefly filed as one and the owner separated
  them: they are different contradictions and each is owed its own reading.
- **State: not a defect — an unweighed API-shape question**, and it is raised
  from the reader's side rather than found in code. `internals/examples/repl.md`
  showed a project installing `after_submit` through the table and
  `on_text_entered` through the `show` config **in the same six lines**, which is
  what prompted it: *"config installs callback, which raises a question of API
  shape (why not have separate callbacks interface as the only way to set
  callbacks?)"*
- **Why it is worth an entry rather than a fix:** the guide documents both paths
  and neither is wrong, so nothing is broken today. What is missing is a stated
  reason to prefer one, which means every example picks by taste and a reader
  infers a distinction that does not exist. **This is distinct from
  `FIX-02-01`/Decision 37**, which settled why `on_text_entered` and
  `after_submit` both exist; this asks why each of them has two installation
  sites.
- **Provenance: ours.** Both spellings are this branch's.
- **Revisit: `PROP-01-01`**, the holistic pass over the proposal block, and
  **low priority there** (owner, 2026-09-05) — nothing in the release depends on
  the answer. That row already weighs API-shape items against the shipped surface
  and rules in-release or after it, and this is the same kind of question from a
  different source. **Registered here rather than left in a review marker**
  because a marker dies with the document it sits in (`FIX-02-07`, 2026-09-04).

### PROPOSAL: the three installation paths do not accept the same set, and one of them catches typos while another does not

- **Where:** `show()`, `configure()` and `compy.input.callbacks`. The matrix,
  read out of `consoleController.lua` (`CALLBACK_KEYS`, `WIDGET_KEYS`,
  `SHOW_ONLY_KEYS`, `LIFECYCLE_KEYS`) and **confirmed by running the surface**,
  not by reading it:

  | key | `show{}` | `configure{}` | `callbacks` table |
  |---|---|---|---|
  | `on_text_entered`, `on_limit_reached`, `validator`, `highlighter` | yes | yes | yes |
  | `before_submit`, `after_submit`, `before_cancel`, `after_cancel` | **raises** | **raises** | yes |
  | `prompt`, `auto_hide` | yes | yes | n/a — not callbacks |
  | `text`, `cursor`, `force` | yes | **raises** | n/a — not callbacks |

- **Two asymmetries, and only one of them is ruled.** The `text`/`cursor`/`force`
  row is `D-CFG-BOUNDARY`'s show-only category and has a stated reason: the user
  owns that content and only activation seats it. **The lifecycle row has no such
  ruling** — four callbacks are settable three ways minus two, and the rule a
  reader must infer is *"content callbacks may ride a config table, lifecycle
  callbacks may not."*
- **The sharper half, found 2026-09-05: the paths differ in whether a typo is
  caught.** The config table is **closed** — `show{ on_txet_entered = f }` raises
  and names the key (`D-UNKNOWN-RAISES`). The callbacks table is a **plain Lua
  table with no guard** — `compy.input.callbacks.on_txet_entered = f` is accepted
  silently, stored, and never fires. So for the four callbacks that have both
  spellings, **one spelling catches the misspelling and the other loses it**, and
  a project cannot tell from the surface which it is using. Verified by driving
  the real project route through `tests.helpers.input_fixture`; **no spec pins
  this difference**, in either direction.
- **It may well be justified, and the reframing states a justification for the
  first asymmetry** (owner, 2026-09-05): a project names content callbacks at the
  moment it asks a question and sets lifecycle callbacks structurally, so the
  frequent case gets the short spelling. `D-EDIT-CALLBACKS` and
  `D-EDIT-LIFECYCLE` own the two sets. **What has not happened is either
  asymmetry being weighed on its own terms**, and the outcome may equally be
  *justified*, *tolerated*, or *worth closing*. This entry does not prejudge it.
  Two loose ends for whoever weighs it: `on_text_entered` fires **on the submit
  path** while belonging to the content set, and the unguarded table is a
  silent-failure mode rather than a shape preference.
- **Provenance: ours**, and **it was raised once before and lost.**
  `internals/examples/repl.md`'s first marker asked, among three proposals,
  *"or allow installing all callbacks via show?"* — this question. The 2026-09-04
  disposition read the marker as answered by Decision 37, which answers only the
  first of the three, and filed only the third. **A marker carrying several
  proposals is dispositioned proposal by proposal**, which is the transferable
  half.
- **Revisit: `PROP-01-01`**, low priority (owner, 2026-09-05) — nothing in the
  release depends on the answer. **The typo half may not wait that long** if the
  weighing decides an unguarded surface is a defect rather than a shape.

### `release_keyboard_route` is named for a lifecycle step that no longer exists

- **Where:** `controller.lua`, `Controller.release_keyboard_route`. One call
  site: `consoleController.lua`, `run_project`'s failure branch.
- **State:** the name asserts three things that are not true. It is **not
  keyboard-specific** — it calls `project_input:deactivate()`, dropping the
  whole route, and empties the derived click slots. It is **not a lifecycle
  release** — the `'running' → 'project_open'` release is gone and every channel
  shares one lifetime ending at the project's stop (`../decisions/input.md`,
  D-ROUTE-LIFETIME as amended). And it is **not reached on the transition it
  names**: the crash path is its only caller.
- **Why this is not simply a rename, which is why `FIX-02-06` left it.** The
  caller follows it immediately with `clear_user_handlers`, which clears every
  bindable channel; the two together are the crash teardown, and this one covers
  the part the other does not. Naming it accurately means first deciding whether
  they should be **one** function — a design call, not a docs sweep. A rename
  chosen without that decision would just be a second inaccurate name.
- **What it costs today:** the doc comment now opens with *"NOT a lifecycle
  step, despite the name"*. That is a comment paying rent for a name, which is
  the smell — not a defect. No behaviour is wrong and no reader is misled now
  that the comment says so.
- **Trigger:** revisit when the crash teardown is touched, or if
  `clear_user_handlers` changes. Found 2026-09-02 at `FIX-02-06`, whose own
  triage (`ACC-01-02-findings-triage.md`, old `FIX-02-14`) proposed the rename
  and did not have this dependency in view.
- **Not slugged** — no commitment to fix before release.

### `_set_text_line` has an unreachable table branch

- **Where:** `src/model/input/userInputModel.lua` —
  `UserInputModel:_set_text_line`, where
  `elseif type(text) == 'table' and ln == 1 then` is nested **inside**
  `if type(text) == 'string' then`, so its guard can never hold.
- **State:** dead code that reads as a supported shape. A reader looking for
  "can `_set_text_line` take a list?" finds a branch saying yes, and it has
  never run.
- **Provenance: pre-existing**, and the same fossil family as the dead
  `_update_cursor` call `BUG-02-01` retired — a shape carried through a
  migration and never re-checked. Found by that row's cold peer review,
  2026-09-01.
- **Not slugged**; nothing depends on it and no behaviour changes when it goes.
- **Revisit:** a one-line deletion inside the `_update_cursor` review below —
  same function, same pass, and the two should not be walked twice.

### Content normalisation treats `\n` but not `\r`

- **Where:** `src/util/string/string.lua` — `string.lines` splits on `'\n'`;
  nothing in `src/model/input/`, the string utilities or
  `userInputController.lua` mentions `'\r'` at all.
- **State:** `set_text("a\r\nb")` yields `{"a\r", "b"}`. The stray `\r` stays
  inside a line and the model counts it as an ordinary column, so the line
  measures one character longer than it displays and the caret can be seated on
  a position that renders nowhere. That is precisely the ambiguity
  **D-CONTENT-NORM** says normalisation removes — the decision is now scoped to
  `\n` explicitly because that is what the code implements.
- **Reachable:** a project setting content it read from a CRLF file. Whether the
  clipboard path is exposed is **unverified** — SDL may normalise
  `love.system.getClipboardText`, and nothing in the tree states either way; the
  project-sets-a-CRLF-string path needs no such assumption.
- **Provenance: pre-existing**, and not `#77`'s. `string.lines` has always split
  on `'\n'` alone. Found by the cold peer review of `BUG-02-01`, 2026-09-01.
- **Not slugged** — no commitment to fix; the release does not depend on it, and
  no shipped example reads CRLF content.
- **Revisit:** with the `_update_cursor` pass below, if one happens — both are
  about the model's idea of what a line is. Note the fix is **not** obviously
  "split on `\r\n` too": stripping a lone `\r` is a content change, and whether
  the framework should silently rewrite what a project set is the same
  tolerance question D-CONTENT-NORM bounds.

### `_update_cursor` measures the column on the wrong line

- **Where:** `src/model/input/userInputModel.lua` — `UserInputModel:_update_cursor`.
- **State:** it sets `cursor.c` from `t[cl]`, the line the caret was on
  *before* the change, and `cursor.l` to `#t`, the last line of the content
  *after* it. When those differ the result is a column measured on one line and
  reported against another, and it can be **out of range**: on
  `{'one','twotwo','xx'}` with the caret on line 2, it yields `(3, 7)` — line 3
  is `"xx"`, whose caret positions are `1..3`. Probed, not inferred.
- **The intent is not in doubt, and the function used to satisfy it.** Before
  multiline it read, in full:
  `self.cursor.c = utf8.len(t) + 1` over a **string** `self.entered` — *seat the
  caret at the end of the content*, which is exactly what `jump_end` now does
  for a line list. The multiline commit (`19351528`, 2023-07-17, *"add multiline
  input representation"*) rewrote it to index a list and **measured the wrong
  line**: to preserve the intent it needed `t[#t]`, the line `.l` is being set
  to, and it used `t[cl]`.
- **The empty `else` is not a missing feature**, though it reads like one. The
  pre-multiline version was `if destructive then … end` with no `else` at all;
  the migration wrote the no-op branch out longhand and left it empty. Nothing
  has ever depended on it, in any revision.
- **Why it is BACKLOG and not ACTIVE: nothing observes it today.** After
  `BUG-02-01` deleted the `set_text` call, two call sites remain and neither
  exposes the defect. `_set_text_line`'s is guarded by `if not keep_cursor` and
  **all seven of its callers pass `true`**, so it is unreachable. `clear_input`
  reaches it, but on empty content every line measures zero, so the wrong line
  cannot give a wrong answer — it lands at `(1,1)`, which is correct by
  accident rather than by construction.
- **Why it is still debt:** it is a trap with no warning sign. The first caller
  to pass `keep_cursor = false` to `_set_text_line`, or the first content change
  that leaves `clear_input` non-empty, gets an out-of-range cursor with no raise
  — and the function's name and privacy marker both suggest it is a settled
  primitive.
- **The mechanism is that it bypasses the validated path.** `move_cursor` is the
  model's checked mover: it rejects an out-of-range line or column, falling back
  to the previous value, and it measures the line length **on the line it is
  moving to**. `_update_cursor` writes `self.cursor.l` and `self.cursor.c` as
  raw fields instead, so nothing catches the mismatch. Routed through
  `move_cursor` the bad `(3,7)` above could not have been produced, which is the
  same statement as saying `jump_end` already does this correctly: it computes
  `#ent` and `ulen(ent[last_line]) + 1` from the *same* line and hands both to
  `move_cursor`.
- **There are THREE raw writers, not two, and the third is on a hot path.
  Corrected 2026-09-01 by cold peer review**, which refuted this entry's
  original claim that `_update_cursor` and `_advance_cursor` were "the only two".
  `UserInputModel:insert_text_line` does `self.cursor.l = l + 1` unvalidated, and
  it is reached on **every Shift+Enter** (`UserInputModel:line_feed`) and by
  Ctrl+D duplicate-line (`userInputController.lua`, the `modify` handler in
  `_normal_mode_keys`) — where the other two are reached rarely or not at all.
  The correction **strengthens** this entry's disposition rather than weakening
  it: the population to review is three, one of them live on ordinary editing,
  so *"review the cursor writers"* is a bigger and better-justified pass than
  *"repair this body"*. (`UserInputModel:set_cursor` also replaces the whole
  `Cursor` with no check, but it takes a constructed `Cursor` rather than
  writing fields, so it is a different shape.)
- **The likelier disposition is not a repair at all: this is a partial,
  unvalidated duplicate of `jump_end`, and what wants reviewing is its USAGE.**
  Both exist to seat the caret at the end of the content — that is what
  `_update_cursor` did correctly when it was single-line, and it is what
  `jump_end` does now. `jump_end` computes `#ent` and
  `string.ulen(ent[last_line]) + 1` **from the same line**, routes both through
  the checked `move_cursor`, and finishes the job: it settles the selection and
  moves the visible range. `_update_cursor` derives half its answer from a
  different line, writes raw fields, and does neither. So the review to run is
  *"does each call site want `jump_end`?"* rather than *"is this body right?"*,
  and repairing `t[cl]` to `t[#t]` in place would leave a second way to do one
  thing — which is what D-CONTENT-NORM's structural half exists to stop.
- **It is not a drop-in swap, which is why this is a review and not an edit.**
  At `clear_input` — the only reachable call site — `jump_end` would land the
  caret identically at `(1,1)`, but it also calls `end_selection` and
  `visible:to_end()`. `clear_input` already calls `clear_selection()` just
  above, so the first is redundant rather than wrong; whether the visible-range
  reset is *wanted* on a clear is a real question and has not been checked.
  Answer it before swapping, not after.
- **The narrow repair stays on the table** — `t[#t]` for the column, one token
  — as the answer if the review finds a caller that genuinely wants a raw,
  unvalidated seat. Nothing today does.
- Either way it touches a shared model primitive rather than this feature's own
  surface, which is why it is not being decided inside `#77`.
- **Provenance: pre-existing, and not this feature's.** The slip is from 2023,
  three years before this branch, and `#77` neither introduced nor widened it —
  it only deleted the one call site that made the asymmetry visible.
- **Not slugged** — a slug is the commitment to fix, and whether this is fixed
  before the release is not decided. Nothing user-visible depends on it.
- **Revisit: a pure-refactoring pass over the cursor writers, not a bug fix**
  (owner, 2026-09-01) — it does no harm unless another caller reaches it or the
  call sites change, so it waits for the pass that would review
  `_update_cursor` against `jump_end` and decide whether the first should exist
  at all. Marked at the site with a `DEBT:` comment so a reader of the code
  meets the entry rather than the bug.

### The error highlight compares a byte column against a character index

- **Where:** `src/view/input/userInputView.lua` — `ec = perr.c` is read off the
  parse error, and the draw loop that counts `tl = string.ulen(s)` compares its
  character index against it.
- **State:** the parser reports an error column as a **byte** offset
  (`model/lang/lua/parser.lua`, `get_error`, read out of metalua's message),
  while the loop that colours the line counts **characters**. On a line holding
  multi-byte content the byte column exceeds the character index it is compared
  with, so the error colouring starts further right than the error is. On ASCII
  the two coincide and it looks correct, which is why nobody has seen it.
- **Sibling, already fixed:** the same byte column reached the **caret** through
  `_apply_eval`, where the new character bound refused it outright and the caret
  stopped moving. That was a live regression and was fixed with a `char_col`
  conversion. This site is the other consumer of the same value, found by the
  same review.
- **Why it stands (owner ruling, 2026-08-31):** deferred past this release. It
  is cosmetic — a wrong colour extent, never wrong content and never a crash —
  it reaches only the console and editor error display, and it is not the input
  API's surface. **No slug**, by the convention that a slug is the commitment to
  fix.
- **What the guide promises, and why that promise still holds.** `../input_api.md`
  (*"Characters, not bytes"*) says *"every cursor position the widget reports or
  accepts is counted this way"*. The sprint's peer review read that as
  over-reaching, on the argument that an error column is a position the widget
  accepts. It is not one: `ec`/`el` reach `userInputView` only to choose a
  colour, and no project-facing call reports or accepts them — `get_cursor`,
  `set_cursor` and `show{cursor}` are the whole surface the sentence governs,
  and all three now count characters. The sentence stands as written; it is
  recorded here because the reasoning is not obvious from either document and
  the next reader will otherwise re-open the question.
- **Shape when taken:** reuse `char_col` (`model/input/userInputModel.lua`), or
  lift it where the model and the view can both call it. Do not fix the view
  alone — the unit should be settled once, at the boundary where the parser's
  answer enters the input subsystem, rather than at each consumer.
- **Revisit:** when the error display is next touched, or if mis-coloured errors
  are reported on non-ASCII source.

### D-ROUTE-OWNS — console/editor convergence onto the shared chain is unimplemented

- **Where:** `src/controller/consoleController.lua` (`ConsoleController:keypressed`,
  `:1516`) and `src/controller/editorController.lua`
  (`EditorController:keypressed`, `:825`) — each still runs its own narrow,
  single-argument dispatch, not the project route's `dispatch(shortcuts, hooks,
  widget, event, trigger, ...)` chain.
- **State:** D-ROUTE-OWNS (`../decisions/input.md`) names this convergence as
  "deliberately left as a follow-on, not attempted," and D-LOVE-ARGS and
  D-EXACT-RESERVE repeat the same scope note in different words. The decision text
  is honest about the gap; the gap itself is still open.
- **Why it stands:** out of this feature's mandate — scoped out on filing, not
  an oversight found later.
- **Revisit:** when the console/editor routes are migrated onto the combo
  mechanism. See also "Console and editor route handlers bind by hand-written
  modifier tests," which is this gap's symptom one layer down.
- **Release scope:** **BACKLOG, not ACTIVE** — the decision itself calls the convergence a
  deliberate follow-on, so it is deferred past this release by the ruling that created it.
  Re-sorted 2026-08-27 by the cross-check in `agents/rules/ledgers.md` §5: it was the one
  ACTIVE entry with no roadmap row, and the absence was the symptom, not the cause.

### Widget sink reaches the singleton via `love.state` global + nil-guard (RESOLVED-IN-PART by the input-API redesign)

- **Where:** was `src/controller/projectInputController.lua`, `_sink` — read
  `love.state.user_input_controller` on each call and guarded it with
  `if ui then …`.
- **Old state:** The old tier-4 `_sink` reached the widget through a global
  rather than an injected instance field (`self.input`), and defended with
  a nil-check against a value the singleton convention said was always
  present.
- **Resolution:** The sink is gone. `dispatch` (the free-function extraction
  recorded as an implementation note in `decisions/input.md`,
  `projectInputController.lua:74-86`) is now a free function that takes the
  widget **as a parameter** rather than reaching for a global itself — the
  concern moves one level up, to `ProjectInputController:_dispatch`
  (`:93-97`), which is the one remaining place that resolves
  `love.state.user_input_controller`. The nil-guard (`if widget and
  widget:is_shown()`) is carried at that boundary, not inside the reusable
  mechanism.
- **Revisit:** Whether `_dispatch` itself should inject `self.input` at
  construction instead of reading the global, and turn its nil-guard into
  an assertion, remains open — the same question, one layer up.

### The Web build has no coverage, and carried a feature-era regression unseen

- **State:** nothing in `busted tests` exercises the `_G.web` branch. A
  defect reachable only on the Web build is therefore invisible to every
  check this project runs.
- **Amended 2026-08-28:** this entry used to add "and the suite runs on
  LuaJIT". It does not — it runs on whatever interpreter the developer's
  `busted` uses, and on the owner's machine that is PUC Lua 5.1. That is how
  the retired `wrap` arity defect surfaced. The lint proposed below would
  not have caught it either: the call was not bare, it was on the guarded
  branch. A second interpreter in CI remains the only check that would.
- **The worked example, found 2026-08-03:** the dispatch chain introduced by
  `56c4284f` wrapped project keyboard handlers in a **bare**
  `xpcall(fn, handler, unpack(args))`, with no web branch. On PUC Lua 5.1 —
  what the Web build runs — `xpcall` drops the trailing arguments, so every
  adopted `love.keypressed` / `textinput` / `keyreleased` would have been
  called with nil for `key`, the held-key view and `isrepeat`. Before the
  feature there was exactly **one** `xpcall` in `controller.lua`, inside
  `wrap`'s guarded branch; the feature added a second, unguarded one. The
  wrapper collapse (`f1dc6aee`) removed it again, so the count is back to one
  — the regression is fixed, but it lived undetected for the whole feature
  because no check could see it.
- **Why it stands:** running the suite against PUC Lua 5.1, or building and
  driving love.js in CI, is infrastructure this project does not have, and
  neither is in this feature's scope.
- **Shape:** cheapest useful step is a lint or a review checklist item —
  **no bare `xpcall` with arguments in `src/`**; argument-forwarding goes
  through `wrap`. A grep is enough to enforce it and would have caught this.
- **Revisit:** if a Web build is released, or when CI grows a second
  interpreter.

### A project that raises leaves global device state dirty; no force-reset exists

- **State:** the sandbox deep-clones the `love` table but shares leaf C
  functions, so a project's imperative `love.*` calls — `setKeyRepeat`,
  `setTextInput`, `setRelativeMode`, raw audio — mutate real SDL/LÖVE state.
  The only mechanism that restores any of it is the project's own
  `compy.before_exit`, and by ratified contract that hook fires on **stop**
  paths only; crash is explicitly out of its scope. A project that mutates
  global state in top-level code and then raises therefore never restores it:
  `run_project`'s failed-run branch drops to `project_open` without ever
  calling `stop_project_run`, so nothing fires, and the dirty state bleeds
  into the next run. `examples/keyboard` is the canonical mutator — it calls
  `love.keyboard.setTextInput(true)` and `love.mouse.setRelativeMode(true)`
  at startup. *(This entry used to name `setKeyRepeat(false)` there; that
  call has never existed in that repo's history — checked with `git log -S`
  across all refs. The platform's `src/main.lua:297` is the only
  `setKeyRepeat` caller and it turns repeat **on**, corrected 2026-08-12.)*
- **Why it stands:** two separate rulings, both deliberate. The hook is scoped
  to stop paths by design — crash/hard-kill was called out as a later layer,
  not an oversight. And firing a *partially initialised* project's teardown
  was ruled against (owner, 2026-08-03): no proper start, no contract is
  expected to run. Resetting the slot is a different question and IS done —
  a dead project's hook must not survive to fire against the next project's
  state (fixed 2026-08-03, `226628ae`).
- **Shape:** a framework-owned **force-reset** of the global surfaces the
  sandbox shares, run on every run-ending path including the crash ones, and
  independent of `compy.before_exit` — a project that crashed cannot be
  trusted to clean up after itself, which is exactly why its own hook is the
  wrong instrument here.
- **Revisit:** owner ruled 2026-08-03 to record it and implement the
  force-reset later; revisit when that work is scheduled.
- **The stop path is project-by-project until then (2026-08-12).**
  `examples/keyboard` now restores relative mode in its own
  `compy.before_exit` (P-18-05), which closes the leak for that project on
  every stop path and for no other. The framework-side question — should the
  platform tear down device modes a project changed, rather than trusting
  each project to — is the "Shape" bullet above, and is not answered by that
  fix. It is worth noting that the example's comment asserted for months that
  *"the runner restores it on exit"*: a project author's reasonable
  assumption about a platform that in fact restores nothing.
- **Where it goes when built (2026-08-07):** `framework_before_exit`
  (`consoleController.lua`) is now the framework's own teardown function and
  the only caller of a project's hook (D-STOP-IS-FW). It is the seam this entry
  has been describing — a framework-owned step, adjacent to but independent of
  `compy.before_exit`. Note the crash path still does not reach it: it calls
  `reset_before_exit` only, deliberately, since a partially initialised project
  runs no teardown. Wiring the force-reset means calling the framework half on
  the crash path too, which is a decision this entry does not pre-empt.

### `compy.before_exit` is a closure slot

- **Where:** `src/controller/consoleController.lua`, `get_compy_namespace` —
  `before_exit` is a metatable-intercepted upvalue rather than a field of the
  namespace table.
- **State:** `table.clone` copies with `pairs` and reuses the metatable **by
  reference**, so a closure-captured slot is invisible to the copy and every
  clone of the namespace shares one variable. `base_env.compy.before_exit` and
  `project_env.compy.before_exit` are therefore the same slot, permanently. A
  plain field would be deep-copied per clone instead.
- **Why it stands:** Nothing tests, documents or depends on the sharing, and
  the suite passes with a plain field — so on its own it reads accidental. But
  `compy.input` survives cloning by the *same* mechanism, so a plain field
  would make `before_exit` the odd member of the namespace, and the sharing may
  be load-bearing for a path not yet identified.
- **Revisit:** Decide whether the sharing is intended. If it is, say so where
  the slot is built; if not, a plain field is simpler. Evidence, with probe
  transcripts: the frozen-surface audit run during this feature's
  implementation.
- **Not to be confused with** the crashes fixed on 2026-08-07: the call site is
  now guarded against both an absent hook and a raising one, which is orthogonal
  to how the slot is stored.

### A truthy `hooks[event]` return silently disables `on_limit_reached`

- **Where:** `src/controller/projectInputController.lua` (the free-function
  `dispatch`) — `hooks[event]` runs before the widget; `userInputController.lua`
  (`emit_limit`) fires `on_limit_reached` only from inside the widget itself.
- **State:** A project that sets `compy.input.hooks.keypressed` (or the
  text/release siblings) and returns truthy consumes the event at the
  hooks step, so `dispatch` never reaches the widget and the widget's
  `on_limit_reached` callback never fires for that keystroke — no
  error, warning, or other signal marks the drop. Carried through the
  input-API redesign unchanged — renamed from the old tier-3/tier-4
  vocabulary to hooks/widget, but the underlying coupling is the same.
- **Why it stands:** The truthy-consume shape (decisions/input.md,
  D-CHAIN-OF-3) is working as designed; it just wasn't checked against
  this specific hooks/widget interaction. No dedicated guard exists.
- **Revisit:** Note the coupling wherever `on_limit_reached` is
  documented for project authors, or decide it needs a guard.

### A raise from project top-level and from a handler surface differently

- **Status:** owner ruled (2026-07-31) to leave the behaviour as-is and refer
  the question to stakeholders; recorded here with the options as ruled.
- **Where:** `consoleController.lua` `run_project` / `run_user_code` versus
  `controller.lua` `user_error_handler`.
- **State:** the same authoring error reaches the author two different ways,
  decided by which `pcall` catches it. Raised from **top-level project code**:
  `run_user_code`'s `pcall` returns, `run_project` prints `'Error: ' .. msg`
  and drops to `project_open` — one console line, the project still open,
  nothing else on screen. Raised from a **`love.*` handler or hook**: `wrap`
  → `user_error_handler` → `suspend_run(msg)` → the error window over the
  project's last frame.
- **Why it matters:** balloons (smoke report 5) passed a lifecycle callback
  inside `show{}`, which D-UNKNOWN-RAISES makes a raise. The raise printed its line
  and left the user "in a console that gave no signal they were still inside a
  project" — which is the failure mode D-UNKNOWN-RAISES's own rationale ("explicit
  failure mode") is meant to prevent.
- **Options:** (a) route a top-level raise through the same suspend/error
  window path as a handler raise — one failure surface for one class of
  failure; (b) keep the console line but make the state legible (name the open
  project and how to leave it); (c) leave as is. **Recommended: (a)** — the
  asymmetry is an accident of which `pcall` caught it, not a decision anyone
  took, and (b) preserves the accident while adding words to it.
- **Revisit:** AFTER the PR merges, not during its review (owner,
  2026-08-03). Deferred deliberately to keep the PR's scope to the
  stakeholders' ask, and to leave them room to contest the suggested fix —
  a glitch may have had a reason nobody here can see.

### A raise at `project_open` is swallowed whole, so pen-and-paper projects report errors worse than any other kind

- **Status:** open — found while probing the dispatch path's nil-safety during
  the widget-lifetime work; **not a feature regression**, the gate below is
  verbatim at the PR base. Sibling of the entry above: same class (what the
  author sees depends on something they did not choose), different cause —
  there it is *which `pcall` caught it*, here it is *what `app_state` happened
  to be*.
- **Where:** `controller.lua` `user_error_handler` → `consoleController.lua`
  `suspend_run`, whose first act is `if love.state.app_state ~= 'running' then
  return end`.
- **State:** a raise inside a hook or a `love.*` handler reaches
  `user_error_handler`, which calls `suspend_run` — and `suspend_run` does
  nothing unless the app is in `'running'`. A **non-blocking** project settles
  in `'project_open'` and lives there (see "Input-only / pointer-only projects
  stay live in `project_open`"), so for that whole lifetime a raise produces
  **no error window and no state change**. The only trace is the console line
  `user_error_handler` prints afterwards, and in pen-and-paper mode the
  project's canvas is what the user is looking at.
- **Confirmed by probe, not by reading:** the same raise in the same hook sets
  `suspend_msg` while `'running'` and sets nothing at `'project_open'`.
- **Why it matters:** this is the class of project — `sapper` is the shipped
  example — whose *entire* logic runs in hooks. Every authoring error in the
  part of the program that does the work is invisible, while the same error in
  the same project's top-level code is not. The gate reads as a guard against
  suspending something that is not running; the projects it silences are
  running in every sense the author cares about.
- **Options:** (a) drop the `'running'` gate and let `suspend_run` fire from
  `'project_open'` too — needs a check that the snapshot/resume path is sane
  from that state; (b) leave the gate and give the `project_open` case its own
  surfacing; (c) leave as is. No recommendation yet: (a) is small but touches
  the suspend path, which is not this feature's territory.
- **Revisit:** with the entry above — same decision-maker, same session,
  **after the PR merges**. Both are pre-feature behaviour and neither belongs
  in the stakeholders' ask.

### The error lock is correct, documented, and hostile

- **Status:** owner ruled (2026-07-31): behaviour is pre-feature, so leave it;
  record the UX concern with options for stakeholder review.
- **Where:** `userInputController.lua` — while `model:has_error()` holds,
  `textinput` is dropped and `keypressed` is swallowed except Enter / Space /
  arrows, which clear the error.
- **State:** to a user this is a freeze with no stated exit. It is what
  smoke reports 1 (guess, "froze after entering a symbol") and 9 (valid,
  "entering '1' stops processing any input") describe. The error band itself
  IS rendered and, since the widget-paint fix, IS visible; nothing in it says
  which keys resume.
- **Pre-feature check (asked for at the ruling):** nothing to reproduce. At
  the PR base `3256aac` the same lock exists and is **stricter** — only Enter,
  Up and Down cleared it, where today's also accepts Left, Right and Space.
  The band's invisibility was equally pre-existing (same render path, same
  unpainted widget). The input API neither introduced the lock nor narrowed
  its exits; it widened them.
- **Is the widening drift? No — it is the ratified behaviour, and it also
  matches what the docs already claimed.** The frozen design (`§10 Edge
  cases`) reads "input locked until acknowledged **(Enter/Space/arrows)**",
  and the widening landed under that AC with the reason in its commit message
  (`9bb6d29`, "Widen the sink's has_error() lock-clear gate to
  Space/Left/Right"). It is not a side effect of the 2D cursor/limit work —
  no other commit touches that key list. Independently, `internals/user_input.md`
  described the exit set as "Enter, space, or arrow keys" **at the PR base**,
  while the code did Enter/Up/Down: the change aligned code with both the spec
  and the doc. Narrowing it now would be a design change to a frozen document,
  not a drift fix.
- **The quirk worth naming:** an arrow key *acknowledges* the error and is
  then swallowed — it does not also move the caret to the offending character,
  which is what a user pressing Left after "not allowed" is trying to do. And
  `keyreleased` clears on Space as well, so Space acknowledges twice
  (harmless, but the two handlers duplicate the rule).
- **Options:** (a) append a hint line to the rendered error band ("Enter or
  Space to continue") — smallest change, no semantics touched;
  (b) clear the error on the next `textinput`, which makes a rejected line
  silently editable and drops what the lock is for; (c) leave it documented
  only. **Recommended: (a)**.
- **Revisit:** AFTER the PR merges, not during its review (owner,
  2026-08-03). Deferred deliberately to keep the PR's scope to the
  stakeholders' ask, and to leave them room to contest the suggested fix —
  a glitch may have had a reason nobody here can see.

### `repl` does not evaluate, and its name says it does

- **Status:** owner ruled (2026-07-31): behaviour is pre-feature, so keep it;
  record the UX concern for stakeholder review.
- **Where:** `src/examples/repl/main.lua`.
- **State:** the example prints each submitted line back — `on_text_entered`
  pipes lines to `print`, and the widget runs the plain-text evaluator
  (`InputEvalText`), which has no parser. `x = 2 + 3` returns the characters,
  not a binding.
- **Pre-feature check (asked for at the ruling):** the same. At `3256aac` the
  example is `r = user_input()` plus an update loop doing `input_text()` /
  `print(r())` — reprint, not evaluate. The migration preserved the behaviour
  exactly.
- **Why it is a concern anyway:** evaluating Lua and printing a result is what
  the **console** does, and until the two fixes of 2026-07-31 (a refused
  widget after a project stop, and a project widget that was never painted at all)
  a project's input surface was visually indistinguishable from the console —
  same input line, no signal. An author testing `repl` could reasonably
  believe it evaluated, having been typing at the console. Both causes are
  fixed, so the modes now look different; the name still promises a
  read-**eval**-print loop the example does not provide.
- **Options:** (a) make it evaluate — the project env already exposes `eval`,
  so it is one line in `on_text_entered`; (b) keep the echo and rename the
  example (`echo`); (c) keep both, documented as-is (today's state).
- **Revisit:** AFTER the PR merges, not during its review (owner,
  2026-08-03). Deferred deliberately to keep the PR's scope to the
  stakeholders' ask, and to leave them room to contest the suggested fix —
  a glitch may have had a reason nobody here can see.

### A widget shown from a key can receive that key's own echo

- **Status:** answered by a **documented project idiom**, not by a framework
  mechanism (owner, 2026-08-03) — `../../input_api.md`, *"Worked example: the trigger key
  echoes into the widget it showed"*, pinned by `tests/input/input_widget_control_spec.lua`, group
  *"the documented echo guard"*, and used by `src/examples/turtle`. A
  framework fix was implemented and then reverted (2026-08-01) because its
  design had never been ruled. What remains open is whether the framework
  should ever take this over; the entry stays for that question.
- **Where:** `src/controller/controller.lua` (the `keypressed` / `textinput` /
  `keyreleased` gateways) and `src/controller/userInputController.lua` (the
  show path and the three widget handlers).
- **State:** LÖVE delivers a `keypressed` **and** a `textinput` for one
  physical key and guarantees nothing about their order. A project that shows
  the widget from a key therefore races its own trigger: measured — show on
  `keypressed('i')`, and the `textinput('i')` of the same press lands in the
  field, so the widget is shown already containing `i`. Showing on
  `keyreleased` (what `examples/turtle` does) is safe only because the echo
  usually arrives first; with the `textinput` delivered last it fails
  identically.
- **Why a project cannot fix it for itself:** it would have to consume a
  `textinput` whose text it cannot derive from the key name (`space` → `" "`,
  `shift+i` → `"I"`, anything an IME emits), and every project that opens a
  widget from a key would re-implement it.
- **Options:** (a) seal the widget for the rest of the event batch that
  opened it, released at the start of `love.update` — order-independent and
  needs no key→text mapping, but it also swallows an unrelated key typed
  within the same frame and assumes the stock run loop is the only pump;
  (b) match the trigger key's echo specifically — narrower, but needs the
  key→text mapping (a) avoids; (c) arm only on `keypressed`, leaving
  open-on-`keyreleased` projects racing; (d) no framework change, and the API
  documents an idiom projects follow instead — the workable one being a
  **paired shortcut**: register the trigger on both channels, where
  `shortcuts.keypressed[combo]` opens and `shortcuts.textinput[combo]`
  swallows the echo and unregisters itself, re-armed by whatever closes the
  widget. Verified in both delivery orders. Its limit: the re-arm has no
  single home (Escape clears without hiding, and there is no close callback).
  *(It was also confined to **bare** combos, by `T-COMBO-CASE`; that half is
  gone — dispatch lower-cases the trigger, so a `shift+i` registration now
  matches the `"I"` echo. A modified trigger additionally needs the modifier
  still held when the echo lands, which `BUG-01-04` did not test.)*
- **Revisit:** a design pass on the run loop's event-batch guarantees — the
  choice between (a)–(d) turns on what the framework is willing to promise
  about batch boundaries, which is a design question, not a bug fix.

### Combo triggers are key-name-only; positional bindings have no vocabulary

- **Where:** `src/controller/controller.lua`, `combo_string` — a combo's
  trigger is the LÖVE **key name**, which is layout-dependent, and the
  scancode is discarded at the gateway (`set_love_keypressed`:
  `local function keypressed(k, _, isr)`), so it reaches neither the routes
  nor the dispatch chain.
- **State:** compy has both audiences and serves only one. *Mnemonic*
  bindings — `ctrl+s` for save, `examples/turtle`'s `i` for input — want the
  key name, because the user's keycap says S. *Positional* bindings — a
  game's WASD — want the scancode, because on AZERTY `w` bound by name lands
  under the player's little finger. LÖVE exposes both for exactly this
  reason; the input API exposes only the first.
- **Why it stands (owner ruling, 2026-08-03):** not now, and **never as a
  swap** — a swap fixes one audience by breaking the other. No layout
  complaint exists in the record; this is a hypothesis about non-QWERTY
  users, not a report from one. Any future answer is **additive**: a second
  registration vocabulary (`shortcuts.scancode.*`, or an `sc:` prefix inside
  the combo string), never a change to what an existing combo means.
- **Also note it cannot help the textinput channel at all:**
  `love.textinput(text)` carries no scancode — one string, the character
  produced after layout, modifiers and IME. So scancodes cannot unify the
  keyboard and text channels; they would widen the gap between them.
- **Cost, if it is ever taken:** threading the scancode from the gateway
  through `forward_*` and the routes to the chain, and a scancode-keyed held
  set — `combo_string` builds its modifier prefixes from key names, so a
  scancode combo would otherwise be a hybrid (modifiers by name, trigger by
  position).
- **Revisit:** when a project needs layout-independent positional keys.

### A keyboard-hooks-only project does not count as interactive

- **Where:** `src/controller/controller.lua`, `user_is_blocking()` /
  `user_is_interactive()`, consulted by `ConsoleController:run_project` after
  the project's top-level code runs.
- **State:** the route is kept when the project replaced `love.update` or
  `love.draw` (blocking), or when it has a widget or a pointer handler
  (interactive). Keyboard hooks are neither. So a project whose only
  interaction surface is `love.keypressed`/`keyreleased`/`textinput` — no
  draw, no update, no widget, no pointer — hands the keyboard back to the
  console, and the hooks the framework captured for it (D-HOOKS-SEEDED) can
  never fire. `examples/keyboard` is *not* an instance: it defines
  `love.update` and `love.draw`, so it is blocking and keeps the route.
- **Why it stands:** hypothetical. No such project exists in the tree, and one
  would be invisible by construction — its only outputs would be sound or
  console text.
- **Revisit:** if a keyboard-only project appears, or when ruling (a)'s
  "interaction surface" definition is next revisited; the fix would be to
  count seeded hooks alongside the widget and pointer tests.

### `gui` is supportable as a modifier, and deliberately not supported

- **Not a defect, and not deferred work.** `gui` (super / cmd / win) is outside
  the modifier set by decision (`../decisions/input.md`, **D-THREE-MODS**), which
  carries the rationale: never requested, added only for symmetry with the
  table-driven builder D-ASK-THE-DEVICE dissolves. This entry exists so the option is
  discoverable from the debt side; the decision is the authority.
- **What it costs today:** nothing observable. No shipped project or example
  registers a `gui` combo. `gui+s` is refused at registration (it names two
  triggers, D-COMBO-SHAPE) and `lgui` is bindable as an ordinary trigger.
- **What re-adding takes:** a `gui()` accessor beside `ctrl()`/`alt()`/`shift()`
  in `src/util/key.lua`, the pair restored to `mod_triples` and the fold table,
  and the precedence list extended. Bounded and additive.
- **Revisit: when a requirement asks for it** — not for symmetry, which is what
  put it there the first time. Whether the answer is a modifier at all is the
  wider question in "Service keys have no special treatment" below; this entry
  states only what re-adding `gui` *as a modifier* would cost.

### Service keys have no special treatment: `capslock`, `tab`, `lgui`/`rgui`

- **Where:** `src/util/key.lua` — `Key.is_mod` recognises exactly the `ctrl`,
  `alt` and `shift` pairs, and the combo grammar (`split_combo`/`check_combo`)
  treats every other token as a trigger. Verified: **no code outside
  `src/examples/` mentions `capslock` or `tab` at all**, and `lgui`/`rgui`
  appear nowhere in the framework's own dispatch.
- **State:** these keys therefore bind and dispatch exactly like `a` or `f5`.
  Each of them is unlike an ordinary key on real hardware, in a different way:
  `capslock` carries a lock state the framework cannot query and whose release
  is not reliably delivered; `tab` is a traversal key that a UI layer may want
  to claim before a binding sees it; `lgui`/`rgui` are owned in part by the
  desktop environment, which may consume a chord before the app is told.
- **Why it stands:** nothing is broken by it, and nothing has needed it. No
  shipped project or example binds any of the three as anything but a plain
  key.
- **Why it is written down:** the framework has **no vocabulary** for this
  group — they are neither modifiers nor ordinary character keys, and the
  input model currently has only those two categories. That is the observation;
  the shape of any answer is deliberately left open.
- **Revisit: worth one review, at no scheduled point.** At least three
  directions are open and this entry favours none of them — widen the modifier
  set, keep it deliberately narrow (which is the standing position,
  `../decisions/input.md`, D-THREE-MODS), or introduce a distinct class for
  service keys with its own rules.

### The widget-handle shape test exercises a stub, not the real draw wiring

- **Where:** the `love.state.user_input` handle is asserted only for shape — that
  `love.state.user_input` is set and callable while the widget is shown
  (e.g. `tests/input/input_widget_callbacks_spec.lua`). The dedicated
  `overlay_spec.lua` that built an ad-hoc controller over a `draw`-only
  stub view was removed when the suite was re-authored; the gap below is
  what survived it, not the file.
- **State:** Guards against the handle being re-narrowed, but does not
  exercise the app's startup widget-instance wiring or the real
  draw wrapper `set_love_draw` installs in `controller.lua` — the exact path a
  past regression faulted at. Runtime spot-checks have covered that path
  manually; the automated suite has not.
- **Why it stands:** Driving that real draw wrapper from a unit
  test needs app-bootstrap wiring the input suite does not currently stand
  up.
- **Revisit:** When a change next touches the widget/dispatch wiring — add
  a test that drives the actual draw wrapper against the widget instance.

### `Esc` clears the input in place without hiding the terminal (turtle)

- **Where:** the turtle example's input surface; likely the controller's
  `cancel()` path (`userInputController.lua`).
- **State:** Pressing `Esc` empties the input buffer but leaves the
  terminal open. This is the opposite of the editor's own `Esc` behaviour
  (below), so the two surfaces disagree on what `Esc` means.
- **Why it stands:** Intent unverified; may be deliberate (clear-in-place
  to retype) or incidental.
- **Revisit:** Characterise the intended `Esc` semantics for the input
  surface and reconcile with the editor's behaviour; decide whether they
  should converge.

### Editor input buffer not cleared on Escape

- **Where:** the editor input buffer.
- **State:** After Escape in the editor, the buffer retains its content
  rather than emptying. A fix was believed to exist at one point but is not
  present in the current tree — may live elsewhere or may never have
  landed.
- **Why it stands:** Unconfirmed whether this is a regression or a
  missing fix; needs a history search before filing as a defect.
- **Revisit:** Search history for the believed fix; if genuinely absent and
  reproducible, file as a defect.

### tixy shift+click example-sequence behaviour unclear

- **Where:** the tixy example project, running.
- **State:** Shift+click is expected to advance through the built-in
  example sequence, but the intended order is not obvious from the UI and
  may not match expectations. Observed once; not reproduced or
  characterised.
- **Why it stands:** Uncharacterised; may be a UX wrinkle in the example
  rather than an input-API defect.
- **Revisit:** Investigate before the input surface is considered stable
  for project authors; characterise reproducibly, then decide defect vs.
  expected.

### Touch delivery is not black-box expressible today

- **Where:** `tests/input/input_routing_spec.lua` — the pointer
  exclusivity block carries `pending('touch reaches the active route')`.
- **State:** Both the widget's and the route's touch handlers are no-op
  TODO stubs, so touch delivery mutates no observable state anywhere; a
  delivery probe would have to spy on method names, which the suite's own
  conventions forbid.
- **Why it stands:** No observable seam exists until a touch consumer
  lands; carrying it `pending` keeps the gap visible without a mechanism
  spy.
- **Revisit:** Green the row when a real touch consumer is wired.

### maze's Lua-command path is not black-box characterizable

- **Where:** `src/examples/maze` — the project's own `ctrl_update` /
  Lua-command dispatch.
- **State:** This path is not exercised by the input contract suite
  without loading the full project; routing to the project route in
  general is covered by other tests, but maze's own command interpretation
  is not.
- **Why it stands:** Would need project-loading scaffolding the contract
  suite does not currently have.
- **Revisit:** When example-project behaviour is next characterised as a
  body of work.

### Test-fixture standup boilerplate / naming

- **Where:** `tests/helpers/input_fixture.lua` — the module-standup
  boilerplate and the `F` table name.
- **State:** Open question whether the standup should reference exact
  bootstrap lines directly or be wrapped in a named seam, and whether `F` /
  `compy_input`-style names risk confusion with the real `compy` namespace.
- **Why it stands:** Cosmetic/ergonomic; does not affect correctness or
  coverage.
- **Revisit:** If the fixture's standup grows harder to trace, or the
  naming causes real confusion, address opportunistically.

### Force-path "does not warn" coverage gap

- **Where:** the config-suppression warning test coverage
  (`tests/input/input_widget_control_spec.lua`, the `show(): activation and reset` group).
- **State:** The suite covers "a non-forced re-show while active warns
  once", but there is no explicit assertion that the sanctioned `force`
  override path warns zero times. That guarantee is the inverse of the
  kept row and is currently only implied, not directly pinned.
- **Why it stands:** Low risk; the warn-don't-swallow guarantee is still
  covered by the kept non-force row.
- **Revisit:** Restore an explicit force-path no-warn assertion if the
  reconfigure surface evolves and the boundary needs re-pinning.

### Editor sets its input-widget cursor outside the project cursor API

- **Where:** the editor sets the cursor inside its input widget via its
  own internal path; the project-facing cursor surface is
  `compy.input.get_cursor`/`set_cursor`.
- **State:** Two code paths can move the same widget cursor — the
  editor's internal one, and the project-facing API. Not a dropped
  requirement; the question is whether the editor's own cursor-setting
  should consolidate onto the public API or stay separate.
- **Why it stands:** An open consistency call with no forcing deadline.
- **Revisit:** When the cursor API surface is next touched — decide
  consolidate-vs-separate and record it.

### Per-example internals docs still describe a retired polling idiom

- **Where:** `doc/development/internals/examples/{tixy,balloons,turtle,
  valid,repl,guess,index}.md`.
- **State:** The cross-cutting input docs (`internals/user_input.md`,
  `internals/console.md`) were synced to the current `compy.input.*`
  surface, but the per-example internals docs still carry prose and code
  blocks describing the retired `r = user_input()` poll-loop idiom. Each
  needs a real per-file rewrite, not a mechanical find/replace.
- **Why it stands:** Doc drift; does not affect running code.
- **Revisit:** A follow-up documentation pass across the example docs.

### Untracked scratch examples call removed input globals

- **Where:** `src/vadexamples/{guess,repl,turtle,tixy,valid}/main.lua` (and
  their READMEs) — git-untracked, parallel to the shipped `src/examples/`
  tree.
- **State:** These still call `user_input()`/`input_text()`/`input_code()`/
  `write_to_input()`/`validated_input()`, globals that no longer exist;
  they will fail if ever run as-is.
- **Why it stands:** Not part of the shipped example set; nobody currently
  runs them.
- **Revisit:** Migrate or delete at will; not blocking anything.

### PROPOSAL: if event-sourced held state is ever needed, it belongs to the framework

- **Status:** owner's direction, 2026-08-11. **Not a commitment**, and explicitly not this
  release; recorded so that the day someone needs it, they do not each build their own.
- **The rule it follows from** (`../decisions/input.md`, D-USAGE-SHAPE.5): a project does not
  reconstruct "what is held" from `keypressed`/`keyreleased`, nor the mouse equivalent, unless it
  is a deliberate decision taken in awareness of the drift — virtual mutable state with no path
  back to the truth, wrong after a focus change or a processing hiccup, and silently so.
- **The shape, if the need is ever demonstrated.** One **event-sourced** view maintained
  centrally by the framework and **exposed for reads** to projects — so the bookkeeping, and its
  reconciliation problem, exists once rather than per project.
- **The constraint that matters most: it stays SEPARATE from the physical polling surface.** A
  reader must always know which question they are asking — *what the event stream says is held*,
  or *what the device says is held*. The two answers legitimately differ, and conflating them is
  the "two clocks" problem this feature spent its length removing (D-ASK-THE-DEVICE, *"what it
  withdraws"*). One surface answering both, or silently switching between them, would rebuild it
  under a new name.
- **What would have to be true first.** A real consumer that cannot be served by a device poll —
  which is *not* what the example corpus showed: every held-state read in it is a "right now"
  question the device answers. Until such a consumer exists, this stays a direction.

### PROPOSAL: `compy.input.keys`, a held-state surface that hides its implementation

- **Status:** owner's proposal, 2026-08-10. **Not this release** — recorded so the shape is not
  re-derived, and because it reframes a question this feature spent a long time on.
- **The shape.** A proxy table on the input surface answering *"is this key held"*:
  `compy.input.keys.h` resolves to `love.keyboard.isDown('h')`, and the foldable names —
  `keys.shift` / `keys.ctrl` / `keys.alt` — resolve to `Key.shift()` / `Key.ctrl()` /
  `Key.alt()`, so the left/right pair folds exactly as it does in a combo string. One vocabulary,
  read the same way from a handler and from `love.draw`.
- **Why it is worth having, in evidence rather than in principle.** Every input-heavy project
  re-derives this. The keyboard example built a proxy of exactly this shape **twice** — first over
  a mirror it maintained itself, then over the framework's tracked set — `maze` wrote
  `is_shift_down()` by hand, and `turtle`, `clock` and `sapper` each spell out
  `love.keyboard.isDown` or `Key.*` at their call sites. The convergence is the argument.
- **The property that matters most: it makes polling-versus-tracking an implementation detail.**
  Today it proxies straight to the device. If a mirror populated from `keypressed`/`keyreleased`
  is ever genuinely needed, it can be swapped in **behind the same surface**, transparently to
  every project — which is precisely what a bare `keys_pressed` table could not do, because the
  table *was* the contract. D-ASK-THE-DEVICE removed a model kept beside the device; this proposal
  removes the need to ever expose which one is in use.
- **Two optional extensions, later and only if a need appears:**
  - **An enumerator** — "list every key currently held". This is the one capability a device poll
    genuinely cannot provide (you can ask about a key, not for the set), and providing it centrally
    is cheaper than each project keeping its own bookkeeping to get it.
  - **`compy.states`, a writable surface** — a project registers an arbitrary state-polling
    function under a name and gets **on/off callbacks at the transitions** of that condition,
    centrally evaluated. That generalises the held-chord gap below from keys to *any* condition,
    and moves the evaluation loop out of project machinery into the framework.

    **[Owner's remark, 2026-08-10] This half is not an input mechanism and should not be scoped
    as one.** *"State-polling can be generally useful in a wider class of situations than just
    key-state queries."* The pattern it replaces — *evaluate a predicate every frame, keep a
    boolean mirroring it, and act on the moments it flips* — is what an input-heavy project
    happens to need most visibly, but nothing about it is specific to keys: a pointer entering a
    region, a value crossing a threshold, a game predicate becoming true are all the same shape,
    and each is written out by hand today with its own mirrored flag. That is why the owner named
    it **`compy.states`** rather than `compy.input.states`, and the naming should be read as the
    scoping decision it is. It also means the mirrored-flag bug class this sprint spent its
    length removing from the framework is, in projects, a *general* pattern with no vocabulary —
    the keys case is one instance of it, not the whole of it.
- **Design questions it would have to answer, named so they are not discovered late:**
  - **Name space.** `keys.shift` means the fold, but `lshift`/`rshift` are also real LÖVE key
    names — the surface must say which names are folds and which are keys, or the two collide.
  - **Silent nil.** A proxy that returns nothing for an unknown name turns a typo (`keys.shfit`)
    into "not held", with no error, in a value used directly in conditionals. A fixed key-name
    vocabulary exists, so raising on an unknown name is available and probably right.
  - **Property or call.** `keys.shift` reads as state, which is what makes it pleasant, and also
    what hides that each read is a device call.
- **Revisit:** when a project needs held-state vocabulary that today it must build for itself —
  which, on the evidence above, is most input-heavy projects. See also the entry below, whose
  on/off transition problem the `compy.states` half of this proposal is the general answer to.
- **CONDITION — this proposal carries something for another decision, and dropping it silently
  would leave that unanswered.** D-ASK-THE-DEVICE (`../decisions/input.md`) dissolved the framework's
  tracked held-key set. It was challenged on the ground that the biggest input-heavy example had
  *independently* grown a model of the same shape, which is evidence of an unmet need. The
  challenge was examined and the decision stands: what that example's model was actually reaching
  for was **edge detection** — answered by the `isrepeat` flag the API delivers, and its own fix
  reached for no held-state at all — plus **foldable held-state convenience**, which a stateless
  device poll answers and which *this proposal* is the durable answer to.
  **So if this proposal is dropped, deferred indefinitely, or replaced by something that does not
  answer the convenience half, that convergence evidence stops being addressed and D-ASK-THE-DEVICE's
  standing should be re-examined at that point.** Recorded here rather than in a review document
  because reviews are transient and this is the condition, not the argument.

### A chord that gates a state while it is held has no vocabulary

- **Where:** the shortcuts mechanism generally (`src/controller/projectInputController.lua`,
  `find_shortcut`; `src/controller/controller.lua`, `combo_string`), and
  `doc/input_api.md`, "Choosing the mechanism: transitions,
  state, and what not to build".
- **The rule this rests on, stated because the API does not state it (owner, 2026-08-10):**
  **a combo can only reliably serve an atomic transition — a one-off shot, stateless in
  itself. It must not be used to toggle a long-lived state that depends on the combo still
  being held.** The reason is mechanical, not stylistic: a combo is serialised from its
  trigger plus the modifiers held **at that instant**, so the event that would *end* the
  state may serialise differently from the one that began it, and the ending binding is
  simply missed.
- **The two ways it bites, both real:**
  - *A modifier released first.* `keypressed['alt+h']` sets a flag; the player lets go of Alt
    before `h`, so `keyreleased('h')` serialises as plain `'h'` and the `'alt+h'` binding never
    fires. **No second binding closes it** — a modifier's own release has no expressible combo
    at all (D-COMBO-SHAPE: one trigger, so `'alt+lalt'` and bare `'lalt'` both raise).
  - *An unrelated modifier pressed mid-hold.* The guide's own flag example binds bare
    `'space'` on both channels; press Space, then press Ctrl, then release Space, and the
    release serialises as `'ctrl+space'`, missing the `'space'` clearing binding. **The
    documented pattern has the defect it is documented to solve.**
  - Both leak the same way on focus loss, where no release is delivered at all.
- **What is missing, sketched (owner, 2026-08-10):** an abstraction for *"this chord is
  currently held"* — evaluated on update, with **two callbacks, on and off**, fired when the
  condition starts and stops being true. Machinery and syntax could mirror shortcuts; only the
  integration differs — instead of one callback on an event channel, a pair on a transition of
  a *condition*. It would replace held-state `if` cascades sprawling through project code, and
  the same shape serves *"Ctrl held during a drag"*, which today every project re-derives.
- **Why it stands:** **not this release.** It is new API surface, and the feature's mandate is a
  simpler and more robust input API, not a larger one. Recorded so the idea is not re-derived,
  and so the rule above is available to anyone reaching for a combo to hold a state.
- **Revisit:** when a project needs held-chord state and the honest answer is still a poll —
  which is what the keyboard example's help overlay does today, deliberately.

### sapper's modifier click path is a touch fallback, and converting it needs the platform's help (RESOLVED, 2026-09-14)

- **Resolved:** the sapper example left this repository. Sapper ships from
  <https://github.com/dsent/compy.sapper>.
- **Where:** `src/examples/sapper/main.lua` — the two guarded click hooks and `love.mousepressed`.
- **What it is.** Shift+press flags and Ctrl+press unlocks, each guarded as *this modifier and
  none of the other two*; the plain click hooks act only when nothing is held. **Its purpose is
  the timing** (author, 2026-08-10): on touch devices a single tap is often accidental and a
  double tap unreliable, so the modifier-held **press** is the dependable route to both actions.
  That rationale is not written in the code, and its absence already caused one wrong change.
- **The obvious conversion is wrong, and was made and reverted (2026-08-10).** Moving the two
  variants to `shortcuts.singleclick['shift+*']` / `['ctrl+*']` is faithful to the *shape* — a
  class key means exactly "this modifier set and no other" — and destroys the *purpose*: derived
  clicks are button 1 only, counted on release, resolved only after the double-click window, and
  **discarded if the pointer drifts**, which is the mechanism the press path exists to bypass.
- **What a correct conversion looks like, and the hole it still has.** Keep the press path as
  `shortcuts.mousepressed['shift+*']` / `['ctrl+*']` — on a channel *with* a trigger the class key
  falls back correctly, so this reproduces "any button, at press time" exactly — and **swallow the
  derived echo** with `shortcuts.singleclick['shift+*'] = fn.stop_here()`, because **consuming a
  press does not prevent the derived click**: the gateway counts clicks in its own
  `mousereleased` handler, before and regardless of anything the project consumed.
  **The residual hole:** a derived click's modifiers are sampled **at synthesis time**, after the
  double-click window — so releasing the modifier during that window makes the echo serialise
  unmodified, miss the swallow, reach the plain hook, and act a second time. On a touch device,
  where the modifier is a key held in the other hand, that is a realistic sequence.
- **THE HOLE IS ALREADY IN THE SHIPPED EXAMPLE — it is not a property of any conversion**
  (verified 2026-08-11). Shift+press flags the cell immediately; the gateway synthesises the
  single click **0.4 s later** (`controller.lua`, `click_delay`); if Shift is released inside that
  window the derived click serialises with **no modifiers**, passes the hook's own *"nothing
  held"* guard, and runs the action a second time — and because flagging **toggles**
  (`actionFlag` → `flowToggleFlag`), the second run **un-flags the cell**. **Net effect:
  shift-click appears to do nothing if the player lets go of Shift promptly.** A live,
  user-visible defect in the example as written, predating this feature entirely.
- **Ruling, 2026-08-15:** retain the fallback. The rare delayed echo is
  accepted without a project-side guard: the damage is negligible and a flag
  would add more machinery than it removes.
- **Revisit:** only if user reports show the echo is material. A platform
  change preserving the originating press's modifiers remains outside this
  feature's scope.

### Modified shortcut families need explicit fall-through policy

- **Where:** project `compy.input.shortcuts` beside ordinary hooks or captured
  `love.keypressed` / `love.textinput` handlers.
- **State:** shortcuts match one exact modifier set. A project that wants a
  shortcut family to claim every modified form must register every meaningful
  and meaningless combination; otherwise an unclaimed combination reaches its
  ordinary keyboard or text-input handling.
- **Why it stands:** the explicit registrations make every claimed combo
  visible, but example grooming has shown that redundant no-op combinations
  quickly become noise.
- **Revisit:** after embedded-example grooming. Evaluate an opt-in wrapper
  such as `compy.input.fn.if_no_modkeys(fn)` that suppresses an event whenever
  a modifier is held, against the risk of hiding a deliberately modified input.

### Examples are not onboarded onto the new input API

- **Where:** `src/examples/{maze,keyboard,turtle,clock}` — the sites listed
  below. The three detached repos (`keyboard`, `maze`, `balloons`) have
  their own remotes and no test suite; `balloons` reads no held state at
  all and appears nowhere here.
- **State:** The examples were reconciled with the removal of the tracked
  held-key set and with the guide's recommendation ladder
  (`doc/input_api.md`, "Held keys"): every read now sits at a rung that is
  correct rather than one that is gone. Several of them are still a rung
  below the one the API offers — a poll answering a question `shortcuts`
  answers directly, or a modifier test that is a combo written out. Each
  conversion below was **considered and declined during the reconciliation**
  because it is a behaviour change, a control-flow restructure, or both, in
  a repo where the only gate is running the app by hand.
- **The sites, and what each would become:**
  - `maze/main.lua:568` — `k == "escape" and not Key.shift()` inside
    `love.keypressed` is two bindings: Shift+Escape quits, bare Escape is
    ignored. The combo form moves `escape` out of `SYSTEM_KEYS` and depends
    on shortcut-before-hook ordering.
  - `maze/main.lua:514-526` — `poll_tab_progression` polls `tab` every
    frame and keeps a `tab_was_down` mirror to derive an edge;
    `shortcuts.keypressed['tab']` is the edge. It also carries the bug
    class the platform just removed: a flag mirroring a key, with nothing
    to reconcile it. The edge feeds two different actions depending on
    game state, so the restructure is not a one-liner. **A bare-key combo
    is legal** — modifiers are optional and only a bare `'*'` is refused —
    **but it narrows the trigger, and that is a behaviour change to state
    rather than discover.** The poll fires on Tab whatever else is held;
    a `'tab'` binding is an exact match on the serialised combo, so
    Ctrl+Tab and Shift+Tab serialise as `'ctrl+tab'` / `'shift+tab'`,
    miss it, and fall through to the hook. Probably an improvement here —
    a stray modified Tab should not skip a level — but it is a decision,
    not a detail.
  - `maze/macro.lua:74,89` — `macro_state.shift_held` is a held-modifier
    mirror maintained across `keypressed`/`keyreleased`, the same shape.
    **Listed by adjacency, not by the same trigger as the rest:** it reads
    no device and never touched the framework's set — the flag is set from
    the event's own key name against a static table (`SHIFT_KEYS`) — so it
    was outside the reconciliation's mandate and is here because it is the
    pattern that mandate kept meeting. It is also not a pure read: the
    release runs `finish_recording()`, so replacing the mirror with
    `Key.shift()` is not behaviour-preserving on its own.
  - `keyboard/alt.lua:203` — `k == "h" and INPUT.ctrl and INPUT.alt`
    hand-matches the combo its own comment calls "Ctrl+Alt+H". Its natural
    form is a shortcut registration; the scene's key routing is what the
    `textinput` heal rewrites, so it waits for that.
  - ~~`keyboard/help.lua:16-19`~~ — **RESOLVED 2026-08-11: the poll is
    correct and stays.** This entry previously called the flag-shortcut shape
    its top rung; the usage principles invert that. The overlay is up while a
    chord is *held*, which is continuous state, and a mirrored
    press/release pair cannot close reliably here at all — a modifier's own
    release has no bindable combo. See `doc/input_api.md`, "Choosing the
    mechanism".
  - `keyboard/input.lua:109` — `isMod` re-implements `Key.is_mod`. Not a
    held-state read, so outside the reconciliation's sweep, but the same
    duplication: it is used in `alt.lua`, `findkey.lua` and `hunt.lua`.
  - `turtle/main.lua:34` — `Key.shift()` inside `love.keypressed` guards
    `shift+r`. It remains because turtle demonstrates captured callbacks.
  - ~~`clock/main.lua:69,78`~~ — **RESOLVED 2026-08-11 by deciding not to
    convert, with the reason written into the file.** `space`,
    `shift+space` and `shift+r` name themselves like combos, but a
    shortcut matches its modifier set exactly, so a `'space'` binding
    would stop firing while any unrelated modifier is held, where the
    hook fires regardless. The narrowing is invisible in the diff that
    would introduce it and nobody asked for it.
- **Why it stands:** Deliberate scope. The reconciliation's mandate was two
  named platform changes; converting an example to the API's better shape is
  a different job, and doing both at once turns a reconciliation into a
  rewrite. Nothing here is broken — each site works as written.
- **Revisit:** This section is the work list for the example onboarding work
  that follows, which reads it entry by entry. That work is split by weight:
  the in-repo examples are a sweep, while `keyboard` and `maze` each get their
  own pass, since each holds conversions that need planning rather than
  applying. A site may be declined again with
  fuller reasoning; what it may not do is disappear silently.

### `compy.input` is built once for the application, not per project run

- **Where:** `src/controller/consoleController.lua` — `get_compy_input()` runs
  inside `prepare_project_env`, which `ConsoleController.new` calls **once**, at
  construction. Every project run therefore shares one surface and one private
  `state`. Env cloning does not separate them either: `table.clone` copies the
  surface's metatable, and that metatable closes over the same `state`.
- **Corrected 2026-08-26.** This entry previously claimed the opposite — *"the
  function that builds `compy.input` is called every time a project environment
  is prepared"* — and accepted the debt on that premise. The call graph
  contradicts it, and the wrong premise closed the question: it is what made an
  application-lifetime store look run-scoped, which is how the hidden-`configure`
  draft came to survive a project stop (fixed; see `internals/user_input.md`,
  *`configure(config)` — the live-reconfigure surface*).
- **Disposition:** Accepted, no action expected — but for a different reason than
  the one recorded before. The `show`/`hide` closures resolve the live widget at
  call time, so a build-once surface still reaches the current widget. What the
  arrangement costs is that **every store the closure owns outlives every
  project**, so anything run-scoped must live on the widget (where teardown
  reaches it) rather than in `state`. `callbacks` and `pending` both do;
  `shortcuts` and `hooks` are wiped by name at teardown instead.
- **Revisit:** if a third run-scoped store is ever added here, prefer moving the
  whole `state` to a per-run lifetime over adding a third teardown arrangement.

### Console debug hotkeys are ad-hoc `if`-navigation

- **Where:** `src/controller/controller.lua`, `set_love_keypressed` — the
  `Ctrl+Shift+<n>` / `Ctrl+Alt+d` debug toggles are a nest of `if k == …`
  branches ahead of the route forward.
- **State:** These branches are exactly the shape combos exist to replace —
  falsey-return, fall-through participants keyed on a serialised combo. They
  predate the combo mechanism and were left in place.
- **Why it stands:** Cosmetic; the branches work and run only under
  `love.DEBUG`. Not worth a behavioural change on its own.
- **Revisit:** When this handler is next touched — lift the debug toggles
  onto the combo-table mechanism (D-COMBO-TABLES), or a `toggle_debug(k)` helper.

### Per-event `set_love_*` installers are lexically isomorphic

- **Where:** `src/controller/controller.lua`, `set_default_handlers` — ten
  near-identical `Controller.set_love_<event>(CC)` calls, each backed by an
  equally near-identical `set_love_<event>` installer.
- **State:** The installers differ only by event name; the repetition invites
  a table of per-event entries driven by one iterator. Flagged inline as a
  code-hygiene concern, not a correctness one.
- **Why it stands:** The explicit form is readable and predates this note;
  collapsing it is a refactor with no behavioural payoff.
- **Revisit:** If the installer set grows or is next restructured — drive it
  from a `{ event → installer }` table.

### Discovered, de-facto behaviours pinned during the un-fork (rationale note)

The un-fork's preservation tests froze several behaviours that are **not designed
contracts** but were **discovered as existing behaviour with no mandate to alter**
— treated as de-facto standards per the implementation and pinned so they can't
be silently narrowed later (any change is a separate, owner-gated decision):

- **Non-shift Enter submits** — Ctrl+Enter and Alt+Enter submit, not only bare
  Enter (guard is `is_enter and not shift`; also consistent with
  `doc/development/decisions/input.md` D-EDIT-LIFECYCLE). Pinned for widget + console.
- **`SearchController:keypressed` returns a jump target** (`{block, line}`) up its
  caller on Enter — the same "keypress return carries a domain result" shape the
  shared widget's limit-flag return was retired for (D-EDIT-CALLBACKS). Left as
  is because `SearchController` is a different class, out of scope here.
- **The project widget's view skips the per-frame `update_view()` workaround by
  widget *identity*** (`userInputView.lua:draw`, `self.controller ~=
  love.state.user_input_controller`) — an identity check standing in for the old
  `oneshot` flag. Its survival under a console/editor re-plug remains a
  tracked future concern, out of the input API's scope.

### paint's `useCanvas(btn)` means a mouse button on one path and a click count on the other (pre-existing; RESOLVED, 2026-09-14)

**Resolved:** the paint example left this repository. The Paint that ships with
Compy is a different program, <https://github.com/dsent/compy.paint>.

`src/examples/paint/main.lua` calls `useCanvas(x, y, btn)` from two places, and `btn` means
something different in each:

- **the drag path** — `compy.input.hooks.mousemoved` polls `love.mouse.isDown(btn)` for `btn = 1, 2` and
  passes the held button through. Here `btn` is a real LÖVE mouse button.
- **the click path** — `point(x, y, btn)`, reached from `hooks.singleclick` and
  `hooks.doubleclick`. Here the number is **paint's own action selector, written as a literal
  in each binding**: `1` for the primary gesture, `2` for the secondary. The framework passes
  the two hooks `(x, y)` and nothing else — no button, no count — so nothing hands paint a `2`
  to misread. Paint picks it.

So the function reads as button-aware, and half its callers cannot supply a button.

**This is not a case of a receiver misinterpreting a value it was sent** — the question is
worth stating because the coincidence invites it. `doubleclick` does not deliver "button 2";
it delivers `(x, y)`, and paint's handler body chooses to call the secondary action `2`. Had
the framework been passing a click count into a button parameter, that would be a defect; it
never did, at the PR base or now. What is left is a latent trap: one parameter, a real LÖVE
button on the drag path and a hand-picked constant on the click path, with the two meanings
agreeing by luck (`2` = "secondary" in both readings). The
consequences a user meets: right-**drag** on the canvas paints with the background colour,
right-**click** does nothing, and double-click paints with the background colour — one effect,
two unrelated gestures, plus a third gesture that looks like it should work and does not. The
same conflation runs through `setColor`, whose `btn > 1` branch is reachable only by double
click, so "secondary colour" is bound to double-click rather than to the secondary button.

**Pre-existing, not a migration artefact.** At the PR base (`3256aac`) the drag path is
byte-identical and the click path bound `compy.singleclick` / `compy.doubleclick` with the same
hardcoded 1 and 2. This feature renamed the bindings (`compy.X` →
`compy.input.hooks.X`) and changed nothing about the meaning.

**Why it cannot simply be fixed by binding the button.** The derived clicks name no button by
ratified decision (`../decisions/input.md`, D-BUTTON-TRIGGER, "The derived clicks keep `(x, y)` and
name no button"): they are not LÖVE events and the click timer synthesises them from
left-button releases only. A project that needs to know which button produced a click binds
`mousereleased` and does its own timing — which is exactly what the framework's timer does on
the project's behalf for the left button.

**Ruled not to change paint (owner, 2026-08-07):** the example never intended a secondary-button
gesture, secondary-button availability is not uniform across environments, and mapping the
secondary action onto a double-click may well be deliberate. Recorded because the parameter's
double meaning is a trap for the next person to edit this example, not because the behaviour is
wrong today.

**Recommendation, for whenever paint is next opened.** Nothing here is urgent — the example
works, and this is about how easy it is to keep working.

1. **Name the two layers.** `1` and `2` appear as bare literals in the two click bindings and
   again as branch conditions in `setColor` and `useCanvas`, so the meaning lives in the
   reader's head rather than in the code. `local FOREGROUND, BACKGROUND = 1, 2` — or better, a
   value that cannot be confused with a button at all, such as the strings `'fg'` / `'bg'` —
   makes each site say what it does. This is the cheap half and it removes most of the risk on
   its own.
2. **Stop using a button number as the layer identifier.** Even named, `btn` is fragile
   precisely because one of its two call paths really is a LÖVE button: a future edit that
   passes a genuine `3` (middle click) or that reads `btn` as a button on the click path will
   be wrong in a way nothing catches. Splitting the parameter — the drag path translating the
   held button into a layer before calling — keeps the button at the edge, where it belongs.
3. **A modifier may be the better metaphor for "background".** Ctrl-draw or Alt-draw is a
   conventional secondary-action gesture, it reads the same on a trackpad and on hardware with
   no reliable second button, and the input API expresses it directly:
   `shortcuts.mousepressed['ctrl+mouse1']` is a ctrl-click and `shortcuts.mousemoved['ctrl+*']`
   a ctrl-drag (`../decisions/input.md`, D-BUTTON-TRIGGER). That would also let double-click go back
   to meaning something double-click-shaped, instead of standing in for a button paint cannot
   observe.

Points 1 and 3 are independent: naming the layers is worth doing even if the gesture never
changes.

### A modifier accessor answers truthy/falsy, not a boolean

- **Where:** `src/util/key.lua` — `ctrl`/`alt`/`shift` return
  `love.keyboard.isDown(...)` straight through, and are annotated
  `@return boolean`. Real LÖVE honours that; the annotation is **not enforced**
  for anything that replaces `isDown`.
- **The one known offender is fixed (2026-08-16).** Harmony's lock-mode patch
  used to fall off its own end for an unheld key, returning **no value** rather
  than `false`, and Lua adjusts that to `nil` at a call site. It now returns a
  boolean on every path (`src/harmony/init.lua`, `patch_isDown`), on the ground
  that a mock matches the signature of the thing it mocks. What remains is the
  general exposure below, not a live instance.
- **State:** harmless to every `if Key.ctrl() then` in the tree, since `nil` and
  `false` are both falsy. It bites the moment a device read is **compared**
  rather than tested: `Key.ctrl() == false` is `false` under harmony, and
  `Key.ctrl()` spliced as a call's last argument contributes **no argument at
  all**. The live exposure is the second, at six call sites that pass a modifier
  read as a trailing argument (`editorController.lua:466,470,772,776`,
  `searchController.lua:101,105`), none of which is affected today because the
  callee only tests the value for truthiness. The comparison form was observed
  once, in the gate's `only_mods` helper, which normalised with `not not`; that
  helper no longer exists (D-RESERVE-TABLE replaced the predicate cascade with a
  combo-string table), so **no site in the tree compares a modifier read today**.
- **Why it stands:** nothing is wrong under a real device, no patcher offends
  today, and no caller compares. Changing the accessors is a small edit with a
  wide blast radius — every caller's return type would become guaranteed, which
  is desirable but wants its own pass and its own tests.
- **Shape, if it is answered:** normalise inside `Key` — `return not not
  love.keyboard.isDown(...)` in each of the three accessors — so the
  `@return boolean` annotation becomes true for every consumer, and no future
  caller has to remember `not not` to compare safely.
- **Revisit:** when `Key`'s accessors are next touched, or the first time a site
  compares a modifier read rather than testing it.

### Console and editor route handlers bind by hand-written modifier tests

- **Where:** `editorController.lua` (~33 tests), `searchController.lua` (5) and
  `consoleController.lua` (4) — `if Key.ctrl() and not Key.shift() and not
  Key.alt() and Key.is_enter(k)`, and the same shape for Escape, paste, scroll
  and the debug toggles. Six further reads are **not** this debt: `_scroll('up',
  Key.ctrl())` passes a held modifier as continuous state, which D-USAGE-SHAPE
  rules correct.
- **State:** these are combos written the long way, at the one layer the feature
  did not convert. Two costs, and the second is the live one:
  - **Nothing can list them.** A combo table is enumerable — that is why the
    input guide can print what the platform reserves. A cascade of `if`s can
    only be read.
  - **Each test claims every modifier it does not name.** The editor's `load()`
    tests Ctrl and Shift but not Alt, so **Alt+Escape loads the selection**; the
    console's `if Key.ctrl() then if k == "l"` makes **Ctrl+Shift+L and
    Ctrl+Alt+L clear the output**. This is exactly the tolerance D-EXACT-RESERVE
    outlawed for the pre-dispatch gate, still present one layer down — and the
    same handlers write the exact form (`not Key.shift() and not Key.alt()`)
    elsewhere, so the inconsistency is within a single file.
- **Why it stands:** no project competes for these keys — the console owns the
  route precisely when no project runs — so nothing is broken today, and
  D-EXACT-RESERVE's scope clause deliberately left this layer out. It is soft debt:
  a consistency and legibility cost, not a defect.
- **Shape, if it is answered:** register these as combo tables on the
  controllers, the way a project registers its own. That is the console/editor
  adoption D-ROUTE-OWNS defers, and it subsumes the debug-toggle entry above.
- **Revisit:** with the console/editor migration, or the first time one of these
  handlers has to state what it claims — a tolerant test is invisible until a
  chord that extends it is wanted.

### A gesture that tolerates a modifier costs one registration per variant

- **Where:** `compy.input.shortcuts` and the combo grammar (`src/util/key.lua`,
  `split_combo`/`check_combo`). A combo is its modifier set **exactly**
  (D-COMBO-SHAPE), and the `'*'` class key is a class of one modifier set too —
  `'alt+*'` does not match `alt+shift+key`.
- **State:** a project that wants *"Ctrl+Alt+Up, and I do not care whether
  Shift is also down"* must register `ctrl+alt+up` **and**
  `ctrl+alt+shift+up`. `examples/keyboard` needs six such tolerant gestures
  and pays **twelve** registrations for them (`input.lua`,
  `register_reserved`). Nothing is broken by this and every binding is
  explicit, which is the model's virtue.
- **Why it is written down (2026-08-12):** the cost is not the typing, it is
  that *a missing variant is silent and looks exactly like the code being
  right*. Converting this one example's hand-written modifier tests to combos
  dropped **six** gestures; four were caught by one cold review, the fifth by
  a second, and the sixth by a third — each time after a fix for the previous
  one had been written by someone who had just read the rule and the bindings
  together. That is three independent reviews to converge on one file's
  twelve lines, and the register should say so before the next project
  migrates.
- **Shape, if it is ever answered:** a tolerance marker in the combo grammar
  (something like `'ctrl+alt+shift?+up'`), or a registration helper that
  expands one gesture into its variants. **Neither is proposed here** — the
  explicitness of the current model is a deliberate property and a tolerance
  syntax trades it away.
- **Revisit:** when a second project hits it, or when the input guide gains
  its reserved-combo section (P10) and has to explain the double binding
  anyway.

## RETIRED

### T-LEAVE-KEYS-LOSES-BLOCK — the editor's whole-editor exits do not write an open changed block (PAID, 2026-09-30)

**PAID 2026-09-30:** the five editor exits — `Ctrl+Shift+S`, `Ctrl+T`, and the gate's `Ctrl+Q`,
`Ctrl+Shift+R` and `Ctrl+Alt+R` — ask `Shift+Esc`'s discard question before they drop a changed open
block (`EditorController:ask_to_leave`, `T-EXITS-BYPASS-GUARD`). `Ctrl+Esc` exits the IDE from any
state and does not ask. The pinned *"(w/o confirmation)"*
cases flipped to *"asks before it drops a changed block"*. What follows is the entry as it stood.

**RULED AND MOVED TO `BACKLOG`, 2026-09-07** (owner, at `OP-04`): *"ship both, document the
defect."* The loss ships knowingly. It left `ACTIVE` because an `ACTIVE` slug is a commitment to fix
before the PR and the owner ruled the opposite — **and because the ruling closed `OP-04`, the row
that pointed at it**, which would have left it as exactly the visible gap `agents/rules/ledgers.md`
§5 describes. **The release obligation it carried is discharged**, not dropped: the defect is named
in `../decisions/input.md`, `D-EDITOR-KEYS` statement 6 and in the shipping guide's reservation
section, and the guarded exit is pinned by four tests. What remains here is the record. The
architectural half is `T-EXITS-BYPASS-GUARD` below.

- **Where:** `src/controller/editorController.lua`, `EditorController:_leave_keys` — `k == "s"` with
  Shift and not Alt calls `self.console:finish_edit()`.
- **The loss is at `finish_edit`, not at the chord, and there are THREE entrances** (found
  2026-09-07, session79, by an AST call-hierarchy query the three preceding sessions could not run —
  `lua-lsp` was dead. `mcp__lua-lsp__references` on `finish_edit`; `grep` for the name finds the
  same three, so this is confirmable without the LSP now that it is written down):
  1. **`Ctrl+Shift+S`** — `EditorController:_leave_keys` (`editorController.lua:72-76`). The chord
     this entry was opened for, and the one `OP-04` discusses.
  2. **`Ctrl+T`** — `reserved_quickswitch` (`controller.lua:807-822`), the leave-the-editor-and-run
     door. In `app_state == 'editor'` **and** `is_normal_mode()`, it calls `finish_edit()`, stores
     the returned state and runs the project. `is_normal(m)` is `m == 'nav' or m == 'edit'`
     (`editorController.lua:216-218`), so **`edit` — the mode in which a block is open and being
     changed — is included.** Same unwritten block, then a project run on top of it.
  3. **`Shift+Escape` in `nav` mode with an empty widget** — `_normal_mode_keys`' `discard()`
     (`editorController.lua:1347-1355`) → `close_buffer()` → `finish_edit()` when fewer than two
     buffers are open (`:203-212`). **This one reaches `finish_edit` but does NOT lose a block —
     corrected 2026-09-07 in this entry's own session, on the owner's question**; the first
     statement of it here claimed *"emptying a block that had content is the change that is then not
     written"*, and that is wrong. See the guard analysis below. It is listed because a fix sited at
     `finish_edit` has to account for it as a caller, not because it is a defect.
- **Doors 1 and 2 lose data; door 3 does not, and the difference is what each one checks before it
  leaves.**
  - **Door 1 has no mode guard at all.** `_leave_keys` is called under `if Key.ctrl()` in
    `keypressed` (`editorController.lua:1545-1553`), *before* the mode dispatch below it, so
    `Ctrl+Shift+S` fires in `edit` mode with a dirty loaded block.
  - **Door 2's guard admits the dangerous mode.** `is_normal_mode()` is `nav or edit`
    (`:216-218`), and `edit` is where a block is open and modified.
  - **Door 3's guard excludes it, and the reason needs no route inventory.** `discard()` branches:
    `is_empty and self.mode == 'nav'` → `close_buffer()`; **everything else → `discard_edit()`**,
    which is #45's confirming guard. `is_empty` is the **widget's** (`input:is_empty()`, read once
    at the top of `_normal_mode_keys`), and **an unwritten change exists only as text in the
    widget** — the block holds what was last written, which is what `discard_edit` compares the
    draft against. So the branch that reaches `finish_edit` runs **only with an empty widget, and
    an empty widget has nothing unwritten to lose.** That is true however the mode was reached, and
    it stays true if another route into `nav` is ever added.
  - **The route inventory was tried and is abandoned — do not rebuild it.** Three successive
    wordings here argued this from *which routes reach `nav` from `edit`*, and all three were wrong
    on a different site: first *"`leave_edit()` is the only `edit → nav` route"* (`leave(dir)`'s
    clean branch inlines the same three lines), then an enumeration of all six `set_mode('nav')`
    sites that dismissed `:117`, `open()`, as unreachable from `edit` — **it is reachable**, via
    `Ctrl+J` → `follow_require` → `console:edit` → `open`, and unlike the routes that enumeration
    accepted it clears neither the loaded block nor the input. The conclusion was right every time
    and the argument was not, which is the signal that route-counting is the wrong shape of
    argument for it. The statement above replaces it and depends on no inventory.
  - **That mis-read is a real defect on its own path**, and it is recorded where it belongs rather
    than here: `T-EXITS-BYPASS-GUARD`, *a THIRD bypass*. It loses the **draft** at `leave_edit`,
    not an open block at `finish_edit`, so it **adds no door to this entry** — it is why the
    inventory was retired, not a fourth entrance.
  **The data-loss surface is therefore two doors, not three, and both predate #45.**
- **Door 2 and three project-boundary doors ask first (2026-09-30).** `Ctrl+Q`, `Ctrl+Shift+R` and
  `Ctrl+Alt+R` reach `ConsoleController:stop_project_run` before the editor sees their key, and the
  stop closes an open editor through `finish_edit`, so its buffers cannot outlive their project.
  With a changed block open, these three and `Ctrl+T` ask `Shift+Esc`'s discard question first
  (`EditorController:ask_to_leave`, `T-EXITS-BYPASS-GUARD`), so none of them drops the block
  unasked. A reorder in progress is still dropped, as `Escape` would. Door 1 asks the same way.
- **What #45 did about this class, measured: it built the guard and did not wire the exits to it**
  (2026-09-07, owner question — *"#45 did not fix it but did what instead?"*). `git diff af9a5782
  f4cf338c -- src/controller/consoleController.lua | grep finish_edit` is **empty**, and
  `save_state()` is byte-identical across the import (`:216` before, `:289` after). What #45 added
  is the entire acceptance-and-confirmation discipline **inside `EditorController`**, none of which
  exists at `af9a5782`: `accept_block` (validate → size-check → `record_write` → `save`, with a
  refusal path that keeps the block open because *"a failed write must not read as accepted"*),
  `discard_edit` (compares the draft against the original and, when they differ, sets
  `pending_confirm = 'discard'` and asks *"discard the changes? Confirm [Enter] / Cancel [Esc]"*),
  `leave_edit` (the clean exit), `_confirm`, `refuse`, `record_write`, `_reject_oversized`.
  **So the editor already knows how to protect a dirty block, and the two whole-editor exits never
  ask it** — while `discard_edit`, the key #45 itself owns, does. `finish_edit` is console-level, predates the feature and predates #45, and
  its name promises a finish it does not perform: it stores the clipboard and drops the buffers.
- **All three entrances exist at #45's own tip, and both losing doors are open there, before our
  import** (2026-09-07, owner question —
  *"were these doors left open at the tip of #45 before it was imported into our branch?"*).
  Measured at `f4cf338c`, which is `dev + #45`:
  - **Door 1, `Ctrl+Shift+S`** — `controller.lua:592-601`, application-level under
    `app_state == 'editor'`, with #45's own comment beside it (*"bare Ctrl+S is reserved for the
    checkpoint (rework spec 2.6); saving is automatic, leaving is Shift+Esc"*) → `CC:finish_edit()`.
  - **Door 2, `Ctrl+T`** — `controller.lua:562-583`, unchanged from the base.
  - **Door 3, `Shift+Escape`** — `editorController.lua:1317-1322` → `close_buffer()` →
    `finish_edit()` (`:173-182`).
  - **`finish_edit` itself** — `consoleController.lua:978-991`, identical to ours line for line.
  **So we imported three open doors and invented none.** What is ours is the *layer*: doors 1 and 2
  were re-expressed as `RESERVED` entries, and door 1 moved to route level.
- **Door 3 is #45's own wiring, and #45 guarded it.** At `af9a5782` (dev, pre-#45) `close_buffer`
  already existed with the same `finish_edit()` call (`editorController.lua:122-130`) but **nothing
  called it** — `grep -c close_buffer` returns 1, the definition alone. **#45 gave the dead sink a
  key**, its own spec-2.3 `discard()` path — **and routed every case that could lose something to
  `discard_edit()` instead**, sending only the empty-and-nav case to the sink. *(An earlier
  statement in this entry read that #45 opened an unguarded entrance beside its own guard. That was
  wrong and is withdrawn: the entrance is guarded, and #45's handling of the key it added is
  correct.)* **The transferable point survives and is narrower:** #45 fixed the class **at the
  block level**, everywhere it owns the key, and left the two **whole-editor** exits — which it did
  not author — calling `finish_edit` as before.
- **The two losing doors, by key and full guard chain at `f4cf338c`** (2026-09-07, owner question —
  *"which keys they are wired to at the tip of #45?"*). Both are application-level `Ctrl` chords in
  `controller.lua`; **neither passes through `EditorController`**, which is why neither can reach a
  guard that lives inside it. There is **no `_leave_keys` at their tip** — that method is ours.
  - **`Ctrl+Shift+S`** — `project_state_change()`: `Key.ctrl()` → `k == "s"` →
    `app_state == 'editor'` → `Key.shift()` → `CC:finish_edit()`.
  - **`Ctrl+T`** — `quickswitch()`: `Key.ctrl() and not Key.alt() and k == 't'` →
    `app_state == 'editor'` → `CC.editor:is_normal_mode()` → `CC:finish_edit()` →
    `CC:run_project()`.
- **#45's own comment sits on door 1 and names a different key as the exit:** *"bare Ctrl+S is
  reserved for the checkpoint (rework spec 2.6); saving is automatic, **leaving is Shift+Esc**"*.
  And Shift+Esc is guarded twice: a dirty block goes to `discard_edit()`'s confirmation, and only
  after `leave_edit()` has cleared it does a second press reach `close_buffer()` → `finish_edit()`.
  **The editor cannot be left with unwritten changes via the key #45 documents as leaving** — the
  two doors that lose the block are the ones that comment implicitly excludes, which matches its
  author's account of the chord as *inherited and absent from the editor spec*.
- **One parity divergence of ours, recorded here because it was not written down anywhere.** Their
  door 1 has **no Alt guard**; our `_leave_keys` is `k == "s" and Key.shift() and not Key.alt()`.
  So **`Ctrl+Alt+Shift+S` leaves the editor at `f4cf338c` and does nothing on this branch.** Ours is
  the narrower binding — defensible, and still a deviation from *"exact behaviour #45 ships"*
  introduced by the re-homing rather than ruled. It is not covered by the tests
  (`input_global_shortcuts_spec.lua` presses `lctrl`/`lshift`/`s` only).
- **This settles the parity half of the owner's standing ruling** (*"ship exactly what #45 ships;
  if its destructive behaviour, escalate"*): at #45's tip both losing doors lose the block, so
  **shipping them is exact parity**, and any acceptance step we add is a deliberate divergence from
  #45 rather than a correction toward it. The escalation half was `OP-04`'s, and it ruled on
  2026-09-07: **ship both exits, documented** — so no acceptance step is taken.
- **Consequence: the fix is a routing question, not a policy question.** Nothing here needs new
  data-loss policy invented — `discard_edit`'s confirm is the policy, authored by #45 and consistent
  with @dsent's stated direction. What is missing is that `finish_edit` does not go through it.
  **The real cost is that the guard is modal and the exits are synchronous:** `pending_confirm` is
  consumed on the *next* `keypressed` (`editorController.lua:1518-1530`), while
  `reserved_quickswitch` runs `finish_edit()` and `run_project()` in one call. Confirming before
  leaving means those callers can no longer assume the editor is gone when the call returns. That
  was the actual design work, and `OP-04` weighed it on 2026-09-07 and declined to take it: both
  exits ship as a documented defect. **The architectural half has its own
  entry** — `T-EXITS-BYPASS-GUARD` (`BACKLOG`), opened 2026-09-07 by owner directive; this entry
  stays the record of the specific chord and of what our re-homing adopted.
- **`Ctrl+T`'s editor arm is NOT ours — it is at the PR base**, and this matters because the entry
  argues the opposite for the chord. `git show 3256aac:src/controller/controller.lua` carries
  `quickswitch()` at `:530-548` with the same three steps (`finish_edit` → store state →
  `run_project`) under the same `is_normal_mode()` guard. This branch moved it into the `RESERVED`
  table — which does not exist at the base (`grep -c RESERVED` → 0) — and preserved the behaviour.
  So the re-homing-is-adopting argument below applies to **two** bindings, while the
  we-introduced-the-defect argument applies to **neither**: both doors predate us.
- **Consequence for the fix, and it is the reason this bullet is here rather than in a session
  note.** An acceptance step at the **chord** leaves door 2 open, and door 2 is the worse one — it
  loses the block *and* starts a project run, so the user's next screen is not the editor. An
  acceptance step at **`finish_edit`** closes all three at one site. That is a smaller change in
  lines and a larger one in blast radius, since `finish_edit` is a pre-existing path with a
  pre-existing caller; **the choice was `OP-04`'s to make, and on 2026-09-07 it made neither** —
  both exits ship. The shape is stated here so that whoever does fix it starts from the site
  comparison rather than redoing it.
- **What the path does, verified rather than assumed.** `ConsoleController:finish_edit()` calls
  `self.editor:save_state()` then `self.editor:close()`; `EditorController:close()` runs
  `self.input:clear()`, replaces `self.model.buffers` with a fresh `Dequeue()` and empties
  `self.view.buffers`. **There is no acceptance step for an open, changed block anywhere on that
  path** — `save_state()` stores the clipboard, not the buffer. So a user editing a block who
  presses `Ctrl+Shift+S` loses that block's changes silently.
- **Attested by the author of PR #45**, 2026-09-06, about the same chord on *his* layer: it *"goes
  past the acceptance gate — an open changed block is not written"*, and he calls the binding
  inherited, absent from the editor spec, and something he will raise with @dsent separately.
  **The attestation was given in Russian and is recorded in English**, summarised rather than
  translated: the wording above is ours, the claims are his. The contract it belongs to is
  `../decisions/input.md`, `D-EDITOR-KEYS`.
- **Provenance: ours, and that is the point.** The binding is upstream's
  (`git show af9a5782:src/controller/controller.lua`, the `k == "s"` block — `Key.shift()` →
  `CC:finish_edit()`), and it carried the defect there. **This branch re-supplied it at route
  level** during `MERGE-01-05` — `_leave_keys` is a rename and relocation of our own `_save_keys` —
  **without checking what the path it calls actually does.** Re-homing a binding is adopting it.
- **Why it is not simply upstream's to fix.** On their layer the chord is one they are questioning;
  on ours it is one we deliberately re-expressed at a new layer while resolving a merge conflict,
  and the argument recorded for that placement was about *which layer owns the reservation*, never
  about what the call loses. Both can be true: they may retire the chord, and we would still have
  shipped it.
- **Reachability:** any editor session with an open, modified block. Not hypothetical — it is the
  ordinary way a user might try to leave.
- **Interaction with the direction of travel.** @dsent's stated redesign collapses the exit
  combinations and requires **confirmation for anything that can lose data**, so this path is
  contrary to where the product is going as well as to what it does today.
- **Found:** 2026-09-06, by `OP-03`, following Vadim1987's attestation to our own copy of the
  chord. **Nothing in our suite covers it** — the re-pin that touched this area asserted which
  function fires, not what the file ends up containing.
- **Behavioural parity with #45 is ruled, and it is already met** (owner, 2026-09-06): *"we need to
  ship it with exact behavior #45 ships it. If its destructive behaviour, escalate."* Both halves
  resolved the same day. **Parity holds** — the divergence is which layer owns the chord, not what
  the user gets: theirs is application-level guarded by `app_state == 'editor'`, ours is route-level
  under `Key.ctrl()` ahead of mode dispatch, and both reach every editor mode and the same
  `finish_edit()`. Measured, not assumed: `grep -n "reserved_stop_run\|RESERVED" src/controller/
  controller.lua` shows bare `ctrl+s` mapped to the stop-run reservation, which no-ops outside a
  run, and `ctrl+shift+s` absent from that table on our side entirely. **So there is no behaviour to
  change.** And the escalation condition **fires**, because the attested behaviour on the other layer
  is destructive too.
- **Roadmap: nothing open — the row that carried this closed.** `OP-04` was the escalation, and the
  owner ruled it on 2026-09-07: *"ship both, document the defect."* **The ruling's persistent home
  is `../decisions/input.md`, `D-EDITOR-KEYS` statement 6**, with the shipping guide's reservation
  section beside it — cited that way on purpose, because a `wip/` row id stops resolving when the
  feature's working tree is deleted and this entry outlives it. *(The escalation was a discussion
  with the owner rather than a message upstream, which is why it never belonged to
  `MERGE-01-07`/`-08`.)*

### T-EXITS-BYPASS-GUARD — the editor's discard guard cannot be reached from the two keys that leave the editor (PAID, 2026-09-30)

**PAID 2026-09-30.** `EditorController:ask_to_leave` is the editor-side step this entry
recommends: `Ctrl+Shift+S`, and the gate's `Ctrl+T`, `Ctrl+Q`, `Ctrl+Shift+R` and `Ctrl+Alt+R`,
call it before they leave, and with a changed block open it asks `discard_edit`'s question and
takes the exit on confirmation. Both *"(w/o confirmation)"* cases below flipped to *"asks before it
drops a changed block"*. What follows is the entry as it stood.

**Opened 2026-09-07 by owner directive at `OP-04`** — *"record the debt on these two keys, probably
generalized to need of re-architecturing or reimplementing the guard so that they could use it
too."* This is the **general** entry; `T-LEAVE-KEYS-LOSES-BLOCK` remains the record of the specific
chord and of what our re-homing adopted.

- **The two keys, with full guard chains** (ours, at HEAD): **`Ctrl+Shift+S`** →
  `EditorController:_leave_keys` → `console:finish_edit()`, under `if Key.ctrl()` **ahead of the
  mode dispatch**, so it fires in `edit`; and **`Ctrl+T`** → `reserved_quickswitch`
  (`controller.lua`) → `finish_edit()` → `run_project()`, guarded by `is_normal_mode()`, which is
  `nav or edit`. Both reach `ConsoleController:finish_edit()`, which calls `save_state()` — the
  **clipboard** — and `close()`, which drops `model.buffers`. No acceptance, no confirmation.
- **The guard exists, works, and is out of reach.** `EditorController:discard_edit` compares the
  draft against the original and, when they differ, sets `pending_confirm = 'discard'` and asks
  *"discard the changes? Confirm [Enter] / Cancel [Esc]"*. `accept_block` writes with a refusal path
  that keeps the block open when the write fails. **Both are methods on `EditorController`**, and
  both exits bypass them — **by two different routes, which this bullet used to collapse into one**
  (corrected 2026-09-09, `EDKEYS-01-01`). `Ctrl+T`'s reservation fires in `controller.lua` **before
  the key enters the editor at all**. `Ctrl+Shift+S` *does* enter it — `_leave_keys` is a method on
  `EditorController` (the bullet above says so) — but it runs under `if Key.ctrl()` **ahead of the
  mode dispatch** and calls the console directly, so `discard()` inside `_normal_mode_keys` is never
  reached. Same outcome, and only the first is a layering problem.

- **The loss is pinned as of 2026-09-09, and a fix must flip two cases** (owner ruling at
  `EDKEYS-01`): `tests/input/input_editor_keys_spec.lua`, *"Ctrl+Shift+S leaves (w/o
  confirmation)"* and *"Ctrl+T leaves and runs (w/o confirmation)"*. They assert that the open
  changed block reaches no write on the way out — the behaviour the release knowingly ships
  (`../decisions/input.md`, `D-EDITOR-KEYS` statement 6). **The `(w/o confirmation)` marker is what
  keeps a green test from reading as the specification**, and it is why the earlier position — leave
  the two unpinned, because a passing test would fix the loss in place — was withdrawn: unpinned,
  they sat outside the regression net that guards the route around them.
- **This is the architectural half, and it is why the entry is general.** The mismatch is not a
  missing `if`: the guard is **modal and deferred** — `pending_confirm` is consumed on the *next*
  `keypressed` (`editorController.lua`) — while the exits are **synchronous**;
  `reserved_quickswitch` calls `finish_edit()` and `run_project()` in one breath. Routing the exits
  through the guard means **the callers can no longer assume the editor is gone when the call
  returns**, which is a contract change at three call sites rather than a patch at one.
- **Direction, recommended and NOT committed** (the same shape `T-EDITOR-SEAM-DEFAULT-OPEN` uses):
  give the editor a *may I leave?* step that the exits must pass — either `finish_edit` returning a
  refusal that its callers honour, or an editor-side `request_leave(on_granted)` that runs the
  existing confirmation and completes the exit on confirm. Either way the **policy stays where #45
  put it** and only the reachability changes. Deciding between them is design work, not a sweep.
- **Provenance: neither key is ours, and neither is #45's.** Both are at the PR base; `Ctrl+T`'s
  editor arm is byte-identical across the import, and #45 changed the `Ctrl+S` block only to
  **remove bare Ctrl+S**, leaving the `Shift` leave untouched. **What #45 did do is fix this class
  at the block level** — `discard_edit`, `accept_block`, `leave_edit` — and route its own
  `Shift+Esc` correctly through it. **The exits it did not author are the gap**, and its author has
  called the chord inherited and absent from the editor spec.
- **What ours adds is layer, not defect:** `Ctrl+Shift+S` was re-expressed at route level as
  `_leave_keys` and `Ctrl+T` became a `RESERVED` entry. Re-homing a binding is adopting it, which
  is the argument `T-LEAVE-KEYS-LOSES-BLOCK` makes and this entry inherits.
- **PAID 2026-09-30: `Ctrl+J` leaves the draft with its own file.** `follow_require` parks the
  draft on the outgoing buffer, `open()` gives the required file an empty input with no message,
  and `pop_buffer` brings the draft back, in its mode, when `Shift+Esc` returns to the file. No draft
  meets `Shift+Esc` in `nav` any more. The analysis below is the bypass as found.
- **A THIRD bypass, and it does not need an exit at all** (found 2026-09-07 by the S79 delivery
  review, verified independently by the parent before being recorded here). **`Ctrl+J` is not mode
  gated.** In `navigate()`'s tail (`editorController.lua:1485-1489`) it runs in **`edit`** as well
  as `nav`: `follow_require()` → `console:edit(...)` → `EditorController:open(...)` →
  `set_mode('nav')` — and **`open()` clears neither the loaded block nor the input** (`:114-117`).
  So the widget arrives in `nav` **still holding the draft**. A following **`Shift+Esc`** then finds
  `is_empty` false, falls through to `discard_edit()`, meets its **`if self.mode ~= 'edit' then
  return self:leave_edit()`** early return (`:581-584`) and **destroys the draft with no
  confirmation.**
  - **It is a guard bypass rather than a fourth door:** nothing here reaches `finish_edit` and the
    editor is not left. The loss is the **draft**, and the mechanism is that the guard tests
    **`mode`** as a proxy for *is there something to lose*, which `Ctrl+J` breaks by moving the mode
    out from under a live draft.
  - **Provenance: inherited, and the two halves come from different places.** `follow_require` is at
    the PR base and at every revision since (`git show 3256aac:src/controller/editorController.lua
    | grep -c follow_require` → 2, same at `af9a5782` and `f4cf338c`); `discard_edit`'s early return
    is **#45's own**, part of the guard it built. **The combination is reachable at #45's tip**, so
    **parity is untouched and the `OP-04` ruling stands unchanged.**
  - **What it does change is the reach of two sentences written the same day**, and they are now
    narrower than the code: `../decisions/input.md`, `D-EDITOR-KEYS` statement 6 says **two** exits,
    and the shipping guide calls `Shift+Esc` *"the only one that asks before discarding"*. Both are
    true **of the exits**; neither covers this path. Marked at both sites rather than rewritten,
    because **widening a ruled statement is the owner's call, not a correction**.
  - **The category question was put to the owner and RULED, 2026-09-07:** *"I do not know if other
    fragile modes exist or not. but we certainly are not spinning-off to fixing #45 work, we have
    own purpose."* The question itself stands exactly as asked — a guard keyed on `mode` is only as
    good as the invariant *mode changes imply the draft was dealt with*, and `open()` breaks that
    invariant without touching the guard, so **whether other mode moves leave a live draft is open
    and deliberately unmeasured.** The ruling is **not** that the answer is *no*; it is that
    **finding it out is not this feature's work.** The guard is #45's, both halves of this path
    predate this branch, and an inventory of mode moves would be a spin-off into another author's
    subsystem. The entry is the record and stays `BACKLOG`; the *Direction* bullet above remains a
    recommendation to whoever owns the editor, not a commitment of ours.
- **`Ctrl+T` contradicts a RATIFIED decision, and the decision does not name it** (found 2026-09-07,
  while checking the deprecation ruling). `../decisions/input.md`, `D-EDITOR-KEYS`, statement 2:
  *"**Leaving and discarding are always `Shift+Esc`.** There is no second way out that the contract
  recognises, **which is what makes an unrecognised one worth finding rather than preserving**."*
  Its key table named `Shift+Esc`, bare `Escape`, `Ctrl+S` and `Ctrl+Shift+S`, and **`Ctrl+T`
  appeared nowhere in the entry** — **fixed the same day**: the owner ruled the amendment and
  `Ctrl+T` is now in the table with a new statement 6 beside it. What follows is why it mattered — and it is a second way out, from `edit` mode, that loses the block and
  then starts a project run. So the contract's own test applies to it by the contract's own words.
  **Amending `D-EDITOR-KEYS` is owner-gated, and the owner ruled it hours later** — the gap this
  bullet recorded is closed, and the bullet is kept because it is why the amendment happened.
  Related but not the same as `T-KEYS-UNPINNED`, which is about rows the suite does not pin — this
  is a row the contract does not have.
- **Reachability:** any editor session with an open, modified block — the ordinary state of editing.
- **Coverage:** the guarded exit is now pinned — `tests/editor/editor_spec.lua`, *"leaving through
  Shift+Esc (2.3)"*, four cases, added 2026-09-07 by owner directive. **The two unguarded exits are
  deliberately unpinned**: a passing test over them would fix the loss in place.
- **Why `BACKLOG` rather than `ACTIVE`, and this is the assistant's placement, not a ruling.** An
  `ACTIVE` slug is a commitment to fix before the PR, and the fix is a contract change across three
  call sites in a pre-existing path. Shipping both doors **is exact parity with #45**, which the
  owner's standing ruling asks for; the escalation half was taken at `OP-04` on 2026-09-07 and
  ruled *ship both, documented*.
  **If the owner rules the re-architecture into the release, this entry moves to `ACTIVE` and needs
  a roadmap row** (`agents/rules/ledgers.md` §5).

### T-GUIDE-LIFECYCLE-IDIOM — the guide teaches the flags but not the shape of a program's configuration (PAID, 2026-09-09)

**PAID 2026-09-09 in session87:** `doc/input_api.md` updated to clarify that `configure` and `show` are simply two ways to set persisting lifecycle flags. The section `Setting the lifecycle flags` was moved ahead of `Asking one question` to establish the configuration pattern before diving into specific prompt examples, and the flags introduction under `show(config)` explicitly states that flags persist and can be set via `configure` or `show`.

### T-RELEASE-LEAVES-POINTER — `release_keyboard_route` unbinds the dispatcher it leaves the pointer channels pointing at (RESOLVED, 2026-09-09)


**RESOLVED 2026-09-09, by the fix this entry preferred:** the release reinstalls `_console_channels`
— the keyboard rest **and all seven pointer channels** — so it returns exactly the set
`occupy_input` takes. The two derived click slots are still emptied, the console not using them, so
all twelve bindable channels are accounted for. No nil guard was added: the entry was right that it
would only have hidden the defect.

**Its reachability claim was WRONG, and the breaking test is what found it.** This entry said a
project raising in its top-level code strands the channels. It does not — `set_user_handlers`, and
with it `occupy_input`, runs only on `run_user_code`'s **ok branch**, so a run that raises never
occupied anything and the narrow release had nothing to get wrong. **The reachable shape is a run
that SUCCEEDED followed by a later one that raised**, and the case written from this entry passed
until that first run was put in front of it. Recorded because the measurement that opened the entry
was made by calling the two functions directly rather than by driving the path, which is exactly how
a reachability claim goes wrong.

- **Where:** `src/controller/controller.lua`, `release_keyboard_route`; the channel lists
  `_keyboard_rest`, `_pointer`, `_derived`; `ProjectInputController:_dispatch`.
- **What is wrong.** `occupy_input` binds **every** `_bindable` channel — keyboard, text, the seven
  pointer channels and the two derived clicks — to the project dispatcher.
  `release_keyboard_route` then calls `project_input:deactivate()` (which sets `compy_input = nil`)
  but reinstalls only `keypressed` plus `_keyboard_rest` (`keyreleased`, `textinput`) and empties
  the two `_derived` slots. **The seven `_pointer` channels are left bound to the dispatcher it
  just emptied**, and `_dispatch` reads `self.compy_input.shortcuts` with no nil guard.
- **Measured 2026-09-07**, occupying and then releasing on a real controller: `love.mousemoved`
  is still bound after the release, `project_input.compy_input` is `nil`, and firing it yields
  *"attempt to index field 'compy_input' (a nil value)"* at `projectInputController.lua:155`.
  Contained by `with_canvas_and_errors`, so it reports rather than crashes — **once per mouse
  movement**.
- **Reachability today is narrow but real:** the function has **one** call site, `run_project`'s
  **failed-run** branch. So a project that raises in its top-level code leaves an app where moving
  the mouse logs an error per frame until something calls `set_default_handlers`.
- **Ours.** The `release_keyboard_route` call site is new in the route-lifecycle rework
  (`1.0.0-rc20260712`, AC-27/28) — see *"Input-only / pointer-only projects stay live in
  `project_open`"*, which records the same provenance. The keyboard-only shape is a leftover of the
  keyboard-only release that `D-ONE-LIFETIME` deleted: the function kept the name and the narrow
  channel list after the asymmetry it served was withdrawn.
- **Fix shape:** either reinstall every channel (at which point it is `set_default_handlers` and
  the narrow function should go), or give `_dispatch` the nil guard its callers' lifetime implies.
  **Prefer the first** — a route that owns ten channels and returns three is the defect, and the
  nil guard would only hide it.
- **Found:** 2026-09-07, while answering an owner question about whether a project could
  de-occupy the input route at its non-blocking exit. The question made the function's one caller
  worth reading, and the gap is why *"is there a function for this"* has to be answered *"yes, and
  it is incomplete."*
- **Roadmap:** **needs a row and does not have one** — same standing as
  `T-CONSOLE-SURFACE-INTERFERES` below. Placement is the owner's.

### T-SIMPLE-SURFACE — the simple API is decided and nothing implements it (RESOLVED, 2026-09-09)


**RESOLVED by `SIMPLE-01`.** Four names ship — `compy.ask`, `compy.on_answer`, `compy.on_key` and
`compy.unask` — as plain fields on the namespace, over the same widget the precise API drives. The
three things this entry said it must not get wrong were all held: the stubs **read** the namespace
slots at fire time (through the live project env, which is also what keeps them correct across env
clones), `ask` **disarms what it arms**, and no second widget, state or event path exists. Its three
dependencies had all landed first, which is why the ordering was a dependency rather than a
preference. Five owner rulings amended the decision while it was built — see
`../decisions/input.md`, `D-SIMPLE-SURFACE`, whose status block carries them.

- **What is owed:** `compy.ask`, `compy.on_answer` **and `compy.on_key`** on the `compy` namespace,
  per `../decisions/input.md`, `D-SIMPLE-SURFACE` (owner rulings, 2026-09-07). `ask` seats content,
  settings and the one-shot flags on the widget the precise API drives, and arms stubs into the
  precise callbacks; `on_answer(text)` is *answered* and `on_answer(nil)` is *abandoned*.
- **`on_key` is the third name and it is not a report — its RETURN VALUE decides consumption.**
  Truthy claims the key and the widget never sees it; falsey lets it through to editing. It fires
  for neither bare modifiers nor keys that will arrive as text, delivers OS repeats rather than
  filtering them, and carries a **combo string**. **The tier is the open implementation choice**:
  shortcuts is recommended (separate tier, no collision, one registration per modifier class);
  hooks costs one registration and takes the project's `keypressed` slot, and if it is chosen the
  memoize / chain / reinstall design on the decision applies — **with the guard that restoration
  happens only if the installed hook is still `ask`'s own**, since `D-HOOKS-SEEDED` forbids
  resurrection.
- **What exists today:** nothing. `grep -n "ask\|on_answer" src/controller/consoleController.lua`
  over `get_compy_namespace` returns no member of either name; the namespace carries `terminal`,
  `audio`, `graphics`, `fonts`, plus the intercepted `input` and `before_exit`.
- **Why it is debt rather than only a plan:** the decision is ratified, so the corpus describes a
  surface the tree does not have — the same shape as `T-LIFECYCLE-FLAGS` and `T-ONE-PAYLOAD`, and
  filed for the same reason: a plan lives in a working tree that is deleted at release.
- **It depends on three other entries and cannot land before them.** `T-LIFECYCLE-FLAGS` supplies
  the four flags `ask` seats; the same entry carries **dispose-then-notify**, without which a
  re-ask from inside a callback is closed by the flow that called it; and `T-SHOW-DESTROYS` is what
  lets a re-ask keep content. Ordering is not a preference here — built first, `ask` would ship the
  defect the ordering ruling removes.
- **Three things it must not get wrong**, each already argued on the decision: the stubs **read** the
  namespace slots rather than capturing them; `ask` **disarms** what it arms; and the wrapper adds
  no second widget, state or event path.
- **The one uncovered path is known:** a project calling `compy.input.hide()` itself leaves the
  stubs armed, and there is no close callback to hang removal on.
- **Found:** 2026-09-07, filed the day the decision was taken.
- **Roadmap:** `SIMPLE-01`.

### T-ONE-PAYLOAD — one payload shape is ruled and the code still carries two (RESOLVED, 2026-09-09)


**RESOLVED by `PAYLOAD-01`.** All five content-bearing callbacks receive the same joined string;
`validator` and `highlighter` keep the lines. The ruling has its own decision entry now —
`../decisions/input.md`, `D-ONE-PAYLOAD` — which **retires `D-PAYLOAD-SPLIT`** rather than
amending it, on the precedent of `D-AUTO-HIDE` → `D-LIFECYCLE-FLAGS` in this same release.
**The risky half turned out to be unreachable in this tree**: the sweep re-derived the consumers
rather than trusting the superseded entry's list, and *not one* in-tree consumer reads the payload
of any of the four lifecycle callbacks — every example declares its callback with no parameter. The
off-repo `serial` API is the whole migration, as the ruling assumed when it was taken.

- **What is owed:** every callback that can see the widget's content receives the **same plain
  string** — `on_text_entered`, `after_submit`, `before_submit`, `before_cancel`, `after_cancel` —
  while `validator` and `highlighter` keep the line list. Per `../decisions/input.md`,
  `D-PAYLOAD-SPLIT`, which this ruling **supersedes** (owner, 2026-09-06: *"let it be — same payload
  where reachable, plaintext"*).
- **What the code does today**, verified rather than assumed: `on_text_entered` receives a string
  (`string.unlines(lines)`), `after_submit` receives the **line list**, and `before_submit`,
  `before_cancel` and `after_cancel` receive **no argument at all** — so a veto cannot look at what
  it is vetoing.
- **Why it is debt rather than a plan:** the decision is ruled and the corpus will describe a shape
  the tree does not have. Same class as `T-LIFECYCLE-FLAGS`, filed for the same reason: a ruling
  that lives only in the working tree's roadmap dies with it.
- **Two halves, and they are not equally risky.** Giving the draft to the three callbacks that
  receive nothing is **purely additive** — a callback that ignores its argument loses nothing.
  Changing `after_submit` from lines to a string is **breaking on a documented callback**, and it
  breaks *silently* where a consumer indexes: `("abc")[1]` is `nil` in Lua, not an error. The
  reverse migration is already documented on the superseded decision, which moved the same
  boundary in the other direction and named every in-tree site it touched — read it before
  sweeping, the site list is the same list.
- **The off-repo consumer migrates a second time.** The `serial` API took the split as its
  foundation, on an owner attestation about a surface not in this repository and therefore not
  checkable from here. The ruling was taken with that cost stated.
- **Found:** 2026-09-06, by the holistic pass over the stakeholders' proposal block, and filed the
  day the ruling was given.
- **Roadmap:** `PAYLOAD-01`.

### T-EXAMPLES-PREDATE-THE-FLAGS — five shipped examples lose their only widget to one Escape (RESOLVED, 2026-09-09)

**RESOLVED the day it was opened, and NOT by fixing five files.** The owner ruled the default
itself: `hide_on_cancel` is no longer seated on the project widget, so Escape destroys nothing
unless a project asks — `../decisions/input.md`, `D-LIFECYCLE-FLAGS`, statement 3, *"the
least-destructive basis"*, which this entry is the measured evidence for. The five examples were
then corrected to the new defaults: `turtle` and `tixy` configure the one flag each needs before
their first show, and `guess`, `repl`, `valid` and `balloons` dropped an `after_submit` clear the
seated `clear_on_submit` already does. Four comments that stated superseded defaults as fact were
corrected with them.

**What is NOT closed by this, and it is recorded rather than left in the entry's shadow:**
`maze`'s wanted submit outcome was never established — it is the one widget-driving example whose
need the sweep did not measure, and it is in a separate repository. It cannot be *stranded* (it
re-opens through `set_prompt`), so it is a question about content and not about reachability. It
is carried on `ACC-02`'s roadmap row, the sprint that runs the `maze` smoke list.

- **Where:** `src/examples/{guess,tixy,repl,valid}/`, in-tree, and `src/examples/balloons/`
  (separate remote, own PR). Each calls `compy.input.show` **exactly once**, at load.
- **What is wrong.** `FLAGS-01` gave the project widget `clear_on_submit` + `hide_on_cancel` as its
  seated cells, so **Escape now hides the widget and keeps the draft** where it used to clear the
  draft and leave the widget standing. None of these five has a re-show path — no hook, no
  shortcut, no `is_shown` branch — so a single Escape ends the program's only input surface for
  the rest of the run. `guess` cannot be guessed at, `repl` and `valid` cannot be typed into,
  `tixy`'s code strip is gone, and `balloons`'s terminal stops accepting commands.
- **Two of the five are also wrong on the other verb.** `clear_on_submit` means submit now empties
  the widget: `tixy`'s comment says *"the just-submitted body is already sitting there ... editing
  continues in place for free"*, which is exactly what stopped being true, and its `after_cancel`
  restore now writes into a hidden widget. `guess`'s comment says *"Cancel's own default (clear +
  stay shown) already re-arms the widget"* — both halves of that parenthesis inverted.
- **Three are merely redundant, not broken:** `repl`, `valid` and `balloons` clear from
  `after_submit`, which the seated `clear_on_submit` now does first. Harmless, and it is the tell
  that these files were written against the old defaults.
- **Measured 2026-09-09**, by reading every `show` call and every re-show path in `src/examples/`:
  only `turtle` (re-shows from its `keyreleased` hook on `i`, and seats `hide_on_submit`
  explicitly) and `maze` (`set_prompt` re-opens when `is_shown()` is false) survive an Escape.
- **Ours, and it is a deviation from pre-feature functionality** — the behaviour these files were
  written against is the behaviour this branch shipped until 2026-09-09. It is the class
  `agents/validation.md` names *"something that worked before and would not after, whether or not
  anyone noticed it working"*.
- **Nothing would have caught it.** `guess`, `tixy`, `repl` and `valid` are on **no** smoke list;
  the five device lists are `keyboard`, `maze` + `draw`, `balloons`, `sapper`, `turtle` plus
  `sine`. `balloons` is on one, and *"its PR's only gate is this pass"*.
- **Fix shape, and the choice is the owner's because it is a question about the default, not about
  five files.** Either (a) each example seats what it needs — `hide_on_cancel = false` on the five,
  which is five one-line edits and leaves the default alone; or (b) the project widget's seated
  cancel cell is itself reconsidered, since every in-tree consumer written before the flags wanted
  *clear + stay* and none wanted *hide + keep*. **(a) is the smaller change and (b) is the question
  the five files are evidence for.**
- **Found:** 2026-09-09, by `PAYLOAD-01`'s consumer sweep — which was looking for callbacks that
  index their payload and found consumers written against a different sprint's defaults instead.
- **Roadmap:** **needs a row and does not have one.** Placement and release scope are the owner's;
  it is filed ACTIVE because the examples ship with the PR and one of them gates another PR.

### T-SHOW-DESTROYS — activation still clears the content the ruling says it must leave alone (RESOLVED, 2026-09-09)

**PAID the same day `FLAGS-01` unblocked it** (owner: *"take it now as own step"*). `reset_content`
is now `if cfg.text ~= nil then set_text(cfg.text)` and nothing else, so `text` given is the content
and `text` omitted leaves it alone.

**The ruling settled the two edges this entry did not reach.** Owner, 2026-09-09: *"the only way
activation destroys should be when show is called with `force: true` and non-nil text … text given
changes the content, text omitted does not. Force is orthogonal — it determines whether `show()` is
allowed to run on already shown widget (it already does that)."* So **`force` gained no content
meaning**, and **`text = false` reads as absent** and keeps the draft — which reverses a behaviour
the 2026-09-01 boundary lift introduced by accident, pinned and documented as *"opens empty"*. The
explicit fresh start is `text = ''`.

**The three side effects this entry flagged each got a case**, in
`tests/input/input_widget_control_spec.lua`: the selection, the custom status and the history index
survive a bare re-show. That was the entry's own reason for calling a one-line change a wide one,
and it was right. Suite 1147 → 1152: five added, four replaced in place.

- **What is owed:** `show` stops destroying. `../decisions/input.md`, `D-CFG-BOUNDARY` statement 1
  as amended 2026-09-07 — `text` given is the content, **`text` absent leaves the content alone**.
  Owner ruling: *"we do not need to hardcode any implicit destructive behavior into `show`."*
- **What the code does today:** `reset_content` (`src/controller/userInputController.lua`) is
  `if cfg.text == nil then self.model:clear_input() else self.model:set_text(cfg.text) end`, and it
  runs first on the activation path. So a bare `show()` empties the field, which is the one line
  standing between the flags and the stakeholders' re-show request.
- **Why it is one line of code and not a small change.** `clear_input()` also drops the selection,
  the custom status and the history index — *"absent means empty" is the contract, not a default
  value passed through*, as the function's own comment says. Removing the call leaves those three
  seated across a re-show, which is **the intent** (the widget comes back as it was) but is a wider
  behaviour change than the text alone, and each of the three deserves a case.
- **It is bound to the flags work, not independent of it.** Until the lifecycle flags exist, taking
  the clear out of activation leaves the project widget with **no** way to empty itself on submit —
  today's `show()`-clears is doing that job by accident for any project that re-shows. Landing this
  first would be a regression with a good reason, which is worse than either.
- **A case pins the old rule and migrates with this:** *"a fresh activation with no text is
  empty"*. It is cited by name in `../decisions/input.md` under `D-ROUTE-LIFETIME`.
- **Found:** 2026-09-07, when the ruling that requires it was given.
- **Roadmap:** `FLAGS-01`, with `PROP-01-06` as the row that asked for it.

### T-LIFECYCLE-FLAGS — `D-LIFECYCLE-FLAGS` is decided and not implemented (RESOLVED, 2026-09-09)

**PAID by `FLAGS-01`, 2026-09-09.** The four flags are on the widget, accepted at `show` and
`configure`, `false` unsets, persistent until replaced, all four off for the class; each owner
seats its own through `UserInputController:seat_lifecycle()` — the console `clear_on_cancel`, the
project widget `clear_on_submit` and `hide_on_cancel`, the editor none. `auto_hide` is gone from
the surface, the types, the guide, the CHANGELOG and the turtle example, with no alias. Disposal
runs before the verb's callbacks on both verbs. Suite 1139 → 1147.

**One thing this entry flagged as unruled stayed unruled and is NOT paid here:** activation still
clears (`reset_content`), so the re-show half of the ruling is open — `T-SHOW-DESTROYS`, which
names this sprint as what unblocks it rather than as what closes it.


- **What is owed:** the four flags `clear_on_submit` / `hide_on_submit` / `clear_on_cancel` /
  `hide_on_cancel`, per `../decisions/input.md`, `D-LIFECYCLE-FLAGS` (owner ruling, 2026-09-06).
  They supersede `auto_hide`, and **the alias is not carried** — ruled 2026-09-06, on the owner's
  *"lets assume not yet"* rather than on the confirmation the decision's removal trigger names.
  `hide_on_submit` ships as the only name. The assumption is safe on the same arithmetic that made
  the compatibility argument weak in the first place: no released consumer can write a key that no
  release ever contained. It reverts to an alias if the `serial` API's author says otherwise.
- **Why it is debt rather than a plan:** the decision is **ratified and the code does not implement
  it**, so the corpus now describes a surface the tree does not have. That gap is exactly what this
  register is for, and leaving it only on the roadmap would put a shipped-API claim in a document
  that dies with the feature's working tree.
- **The shape of what is owed may still move, and that is not drift** (owner, 2026-09-06). The
  decision was derived from **two proposal bullets read on the spot**, and the holistic pass over the
  whole proposal block now runs **before** the sprint that implements it. So this entry's *scope*
  below is the decision as written, and the pass may widen it, narrow it, or change the cell count.
  **What is not in question is that the obligation exists**: the corpus describes lifecycle
  outcomes as settings, and the code hardwires one of them.
- **Scope, as the decision fixes it:** four settings on `D-CFG-BOUNDARY`'s existing terms (accepted
  at `show` and `configure`, `false` unsets, persistent until replaced); **all four defaulting off**,
  with each owner seating its own on its own instance; the clear keeping `model:cancel()`'s
  remember-then-clear semantics; and callbacks staying purely **additive**, which is why the
  destruction is a flag and not a default callback.
- **It carries the fix for two other entries**, and that is the reason it is one sprint rather than
  three: `T-NO-CALLBACKS-IS-NOT-A-NOOP` (the hardwired cancel step becomes flag-driven) and
  `T-NAV-ESCAPE` (the editor goes inert with no editor-side change).
- **Acceptance criteria are on the decision, not here** — six of them, and the first is the owner's:
  **the editor's Escape must match #45's expectations**, i.e. bare Escape inert in navigation and in
  editing, per its author's attested routing contract.
- **The defaults are now RULED and they are the stakeholders' (owner, 2026-09-07):** *"@dsent
  requests for behaviours are authoritative, we support them via defaults."* The project widget
  seats **`clear_on_submit` on, `hide_on_cancel` on, `clear_on_cancel` off** — submit consumes the
  content, cancel preserves it and takes the widget down. **This inverts today's shipped pairing on
  both verbs**, so the sprint owes a guide edit, a `CHANGELOG` line and a justification row, and it
  owes a test asserting what the widget **contains** after each verb: the pinned cases assert
  callback *order* and stay green straight through this change. *(Prior state: the defaults were the
  proposals sprint's to rule, and the decision existed so that ruling would be a choice among four
  booleans rather than a redesign. It was.)*
- **The scope grew by the same ruling.** The four flags are also the answer to the **re-show**
  proposal, not just to the two lifecycle ones: with destruction flag-driven at the verbs,
  activation no longer needs to clear. **That last part is unruled** — activation clears today
  (`reset_content`), which is `D-CFG-BOUNDARY` statement 1 — and the sprint must not assume it.
- **Found:** 2026-09-06 — filed at the moment the decision was taken, which is the point.
- **Roadmap:** `FLAGS-01`.

### T-NO-CALLBACKS-IS-NOT-A-NOOP — the accommodation `D-EDIT-LIFECYCLE` promises for host widgets does not work (RESOLVED, 2026-09-09)

**PAID by `FLAGS-01-02`, 2026-09-09**, and the fix is not the one the entry's own claim implies.
The hardwired `model:cancel()` is gone from `cancel_flow`; what a verb leaves behind is now the
instance's flags, so **a widget that seats nothing does nothing** — which is the accommodation the
decision promised, expressed as seating rather than as callback absence.

**The ratified sentence was corrected rather than fulfilled.** *"The console sets no lifecycle
callbacks so its flows are no-ops"* is still not what the console is: it sets no callbacks and
**does** seat `clear_on_cancel`, so its Escape still clears, deliberately and by its own request.
`../decisions/input.md`, `D-EDIT-LIFECYCLE`, *"One path for every instance"*, now says that, and
`D-LIFECYCLE-FLAGS` statement 6 — which predicted the sentence would *become true* — says why it
did not.


- **The claim.** `../decisions/input.md`, `D-EDIT-LIFECYCLE`, *"One path for every instance"*:
  *"A context that must not run the flows arranges it at its own layer: the editor consumes
  Enter/Escape upstream through `block_input()`, **the console sets no lifecycle callbacks so its
  flows are no-ops**, and the project widget sets them for real."*
- **The second half is false, for cancel.** `run_callback` is
  `local cb = self.callbacks[name]; if cb then return cb(...) end` — a **nil** callback returns nil,
  which is falsey, so it **cannot veto**. `cancel_flow` then runs `self.model:cancel()`, which is
  **hardwired past the callbacks** and clears the content. And `default_callbacks()` sets only
  `on_limit_reached`, `after_submit` and `after_cancel` — **`before_submit` and `before_cancel` are
  absent**. So "sets no lifecycle callbacks" produces a cancel that **still clears**.
- **Consequences, both observable.** The console clears its input line on Escape (inherited
  behaviour — upstream's console arm also cancelled — so not a regression, but it is not the
  no-op the decision describes). And the editor had **no protection at all** from this mechanism;
  it was covered only by the *other* accommodation in the same sentence, `block_input()`, which is
  the one held in another feature's file and which `MERGE-01-05` invalidated (`T-NAV-ESCAPE`,
  `T-EDITOR-SEAM-DEFAULT-OPEN`).
- **Why this is the foundational entry and the others are downstream of it.** The widget-as-agent /
  widget-as-component duality would have been harmless if the ratified accommodation worked as
  written: a host would set no callbacks and get an inert lifecycle. **The design anticipated the
  hazard and specified a defence that does not function**, so every host was relying on the one
  remaining defence without anyone noticing it was the only one.
- **The mechanism that DOES work already exists and is ratified.** Both `before_submit`
  (`userInputController.lua`, `submit_flow`) and `before_cancel` (`cancel_flow`) **do veto** when
  set to a function returning truthy. They are simply not defaulted, and no host sets them.
- **Reachability:** every host-owned widget — the console's, the editor's, and the editor's search
  strip. Not projects: a project setting no callbacks *should* get the documented clear-on-Escape,
  and does.
- **Provenance: ours.**
- **This is a DEFECT, not a design question** (owner ruling, 2026-09-06). *"We already decided it
  must be inert — we just did not respect it."* No new decision is owed: `D-EDIT-LIFECYCLE` states
  the intent and the code fails to honour it, so what is owed is a fix.
- **The fix shape, as ruled.** The **hardwired cancel step is replaced by conditional actions
  driven by flags**: `cancel_flow` becomes `before_cancel` veto → the outcomes its instance's flags
  select → `after_cancel`, with the flags of `../decisions/input.md`, `D-LIFECYCLE-FLAGS`. Two
  consequences fall straight out and are the test of the fix:
  - **the editor becomes inert with no editor-side change at all** — it seats no flags, so nothing
    runs, which is exactly its author's attested contract for bare Escape; and
  - **the console keeps its Escape** by seating `clear_on_cancel` on its own instance, not by the
    widget destroying unconditionally.
- **Not to be fixed by a narrower change.** A `before_cancel` veto on the editor's instance would
  also stop the symptom, and it was the route this session first proposed. It is rejected: it
  leaves the false sentence in the decision, leaves every other host on the same broken defence,
  and treats a veto as a suppression switch.
- **Found:** 2026-09-06, by the owner asking why the editor cannot simply hook `before_cancel`.
  Checking whether it could is what showed that the documented alternative never did.
- **Roadmap:** `FLAGS-01-02`, inside the sprint that implements `D-LIFECYCLE-FLAGS`. Sibling
  entry: `T-LIFECYCLE-FLAGS`.

### T-NAV-ESCAPE — bare Escape in the editor's navigation mode now runs the widget's cancel (RESOLVED, 2026-09-09)

**PAID by `FLAGS-01`, 2026-09-09, with no editor-side change**, exactly as the 2026-09-07 ruling
said it would be: the editor's widget seats no lifecycle flags, so the fall-through runs a cancel
that does nothing. **The two cases this entry named as the ones that invert did invert, and nothing
else went red** — navigation in `tests/input/input_widget_callbacks_spec.lua` now asserts the flow
is reached and destroys nothing, and editing in `tests/input/input_editor_keys_spec.lua` asserts
the open block survives, which is the breaking test for the data loss.

**The documentation line it was owed is written** (`FLAGS-01-04`): `../internals/user_input.md`,
under the cancel flow — the editor claims the key nowhere, the widget gets it and starts a cancel
that is deliberately empty. `../decisions/input.md`, `D-EDITOR-KEYS` statement 1 records the same
thing as the contract being honoured for the first time.


**RULED 2026-09-07 — THE QUESTION DISSOLVES, and it was already neutralised by a decision taken for
other reasons** (owner, at `MERGE-01-07`): *"we neutralized defect by planning to make editorial
widget non-destructive (no hide, no clear) on its own 'cancel'. therefore, the problem dissolves —
whether editor claims Escape for something else is its own business."*

**What this settles.** The entry was written as a product question — *should the editor claim bare
Escape?* — and the answer is that **it does not matter to us.** With `D-LIFECYCLE-FLAGS`, the
editor's widget seats no `clear_on_cancel` and no `hide_on_cancel`, so the fall-through runs a cancel
that **does nothing**. The key reaching the widget stops being a loss the moment the widget's cancel
is inert, and what the editor does with Escape becomes the editor's own business rather than a
contract we have to negotiate.

**This is not a new commitment.** `FLAGS-01` already builds the four flags and already lists this
entry among what it closes; nothing is added to the release by this ruling. What changes is the
*reason* the entry closes — inert-by-default, not a claim negotiated with the editor — and that the
ruling **forecloses the other branch**: we do not ask the editor to claim the key, and we do not
re-litigate `D-EDIT-LIFECYCLE`'s consume-upstream sentence as if the fix depended on it.

**One documentation line is owed and is scheduled on `FLAGS-01-04`** (owner: *"worth a line in the
documentation"*): *if the editor does not claim Escape, the widget gets it and runs its own cancel,
which is purposefully configured to do nothing.* It is not written here because the flags are
**decided and not implemented**, and the guide describes shipped behaviour.

- **Where:** `src/controller/editorController.lua`, the navigation-mode key handling, meeting
  `src/controller/userInputController.lua`'s `cancel_flow`. **Both modes are pinned as of
  2026-09-09 (`EDKEYS-01`), and `FLAGS-01` inverts exactly these two cases:** navigation in
  `tests/input/input_widget_callbacks_spec.lua`, *"editor Escape falls through to the widget"* →
  *"is not claimed by the editor in navigation"* (whose sibling case pins the `Shift+Esc` half of
  the same seam), and **editing** in `tests/input/input_editor_keys_spec.lua`, *"clears the open
  block, losing the edit"*. Both carry a `FLIP:` comment naming `../decisions/input.md`,
  `D-LIFECYCLE-FLAGS`; a case going red anywhere else is a regression, not this fix landing.
- **What changed, and it is a behaviour change this branch did not choose.** Before the import,
  bare Escape in the editor meant *load the selected line into the input*, and the editor
  **consumed** it (`block_input()`), so the widget's `cancel_flow` never ran there. Upstream PR
  #45 moved the load onto **Enter and typing** (its spec 2.2) and gave the discard/leave to
  **Shift+Esc** (2.3). Bare Escape is now claimed by nothing in navigation, so it falls through
  to the widget and runs `before_cancel` → clear → `after_cancel`.
- **Why it is registered rather than absorbed.** Two reasons, and the second is the one that
  matters. First, `MERGE-01-05`'s own rule: a cascade beyond the four known conflicts is filed
  with a planned step rather than absorbed silently. Second, **the corpus asserts the opposite in
  prose**: `../decisions/input.md`'s `D-EDIT-LIFECYCLE` explains the design through *"the editor
  consumes Enter/Escape upstream through `block_input()`"*, which is now true of Enter and of
  Shift+Esc but **not** of bare Escape. A reader meeting that sentence will predict the wrong
  behaviour.
- **Why it may nevertheless be right.** It is `D-CHAIN-OF-3` behaving exactly as designed — a key
  no participant claims falls through to the next one — and what it produces is Escape clearing
  the editor's input line, which is what Escape does everywhere else in this API. **The question
  is not whether the mechanism is sound; it is whether the editor should claim the key.** That is
  a product question about someone else's subsystem, which is why it is not answered here.
- **Reachability: every Escape press in the editor, and the entry's own name under-scopes it.**
  In **navigation** it is harmless, as first recorded — the input line is empty, so the clear has
  nothing to clear. **In EDIT mode it is data loss, and that was never recorded**: `_normal_mode_keys`
  serves both modes and `discard()` requires Shift, so bare Escape is unclaimed in edit too, falls
  through, and `cancel_flow` empties **the block the user opened**. Probed 2026-09-06 — open a block
  with Enter, the widget holds `first line`; press bare Escape, the widget holds nothing and the mode
  is still `edit`. **This is the primary editing path, not a corner**, and it makes the entry
  release-blocking rather than latent. The slug is kept for citation stability
  (`agents/rules/roadmap.md`, the renumber-vs-rename test); **read it as *bare Escape in the editor*,
  both modes.**
- **The product owner's stated intent points the other way, and it was found rather than assumed**
  (2026-09-05, owner's prompt). `../../input_api.md`'s proposals block, ***"#### 4. Escape hides,
  and does not clear"***, is **@dsent's** — the edge's author — and it says two things that bear
  directly on this entry:
  - ***"Clearing on Escape is the P1 data-loss hazard"***. The merged behaviour here **is**
    clearing on Escape, in the one surface that proposal exempts.
  - ***"The always-shown console and editor widgets keep their own Escape."*** The editor's widget
    is `always_shown`, and what it has now is **not** its own Escape — it is the generic widget
    cancel, reached because nothing upstream claims the key in navigation.
  **And #45's own design agrees in shape:** it gave the discard to `Shift+Esc` and made it *ask
  when the block is changed*. Both authors are careful about destructive Escape; the fall-through
  is careful about nothing. **That is evidence for *the editor should claim the key*, and it is
  the strongest input available to the ruling** — but it is still a ruling, because a proposal is
  not ratified and `PROP-01` is the row that decides what the release absorbs.
- **Provenance: the merge.** Neither side has this behaviour alone — #45's cancel never runs on the
  editor route, and our branch's editor consumed the key. It exists only in the union, which is the
  merge-risk class the plan for `MERGE-01` registered as `R11` and stated as *"they changed a line
  we moved"* — high impact, invisible to both the merge and the suite, because neither side is
  wrong alone.
- **AMENDED 2026-09-06 (session76): upstream had an explicit guard against exactly this, and our
  own Phase R replaced it with an expectation.** The first statement of this entry said *"#45 has no
  `cancel_flow`"*. That is imprecise in the way that matters. Upstream **does** cancel on Escape,
  and it **excludes the editor route by a conditional in the same function**:
  `git show f4cf338c:src/controller/userInputController.lua` — `keypressed` branches on
  `if love.state.app_state == 'editor' then … else … cancel() … end`, and the editor arm **omits
  `cancel()` deliberately**. Upstream `dev` has the identical shape (`af9a5782`, same file). **Our
  branch deleted that branch**: commit `affc9320` (2026-07-21), Phase R, *"the app_state un-fork,
  option E"* — its own message reads *"userInputController.lua: delete the
  `love.state.app_state == 'editor'` branch; keypressed runs one uniform path"* and, in the same
  commit, *"editorController.lua: consume Enter/Escape upstream via `block_input()`"*.
  **The guard was not removed; it was moved out of the widget and into the other controller** — and
  that controller belongs to a subsystem this branch does not own and upstream was actively
  reworking. The live comment states the new arrangement in terms
  (`src/controller/userInputController.lua`, the submit/cancel-flow block: *"Editor/console callers
  that must not run these consume the key upstream (editor) or set no callbacks (console no-op)"*).
  **So this is not only two designs meeting at an unowned seam.** A route exclusion that upstream
  expressed as a conditional, this branch re-expressed as a cross-controller expectation; #45 then
  changed that controller, the expectation stopped holding, and **nothing failed, because an
  expectation cannot fail** — which is why the behaviour arrived silently and was found by an
  unrelated spec. **It also means a third option exists** beside *ship it* and *the editor claims
  the key*: restore the exclusion on the widget side, where upstream kept it. Whether that is
  right is a design ruling — `D-CHAIN-OF-3` and option E both argue against a route test inside the
  widget — but it must be **on the table**, and it was not.
- **Found:** 2026-09-05, by a spec of ours failing during the import and being read rather than
  re-pinned on sight. The re-pin asserts the new behaviour in both directions — bare Escape
  cancels, Shift+Esc does not reach the widget — so whichever way the question is answered, the
  answer has a test that will move.
- **Roadmap:** `FLAGS-01-04` — the one documentation line still owed. `MERGE-01-07`, which ruled
  the question, **closed 2026-09-07**: the flags make the editor's widget inert on its own cancel,
  so whether the editor claims Escape is its own business.

### T-ALWAYS-SHOWN-UNRATIFIED — an internal method this feature added, absent from both ledgers (RATIFIED, 2026-09-09)

**RULED 2026-09-09 — the guarantee STAYS, and this entry is paid by ratification rather than by
deletion.** The owner reversed their own 2026-09-06 ruling: *"we keep `always_shown` guarantee
exactly because pre-feature there was no chance that persistent widgets will receive stray `hide()`
(or any `hide()`) … and now we need explicit guard in persistent widgets that blocks hiding."* The
construct is now ratified at `../decisions/input.md`, `D-WIDGET-AT-BOOT`, which is what this entry
asked for: its complaint was that the method sat in **no ledger**, not that it was wrong.

**What the reversal changes in the argument below.** The *"guards a call path that does not exist"*
finding is right on the facts and wrong as a reason to delete. Unreachability is what the guard is
**for**: pre-feature no such path could exist at all, because there was no `hide()` and no
shownness, and code is the only place that impossibility can live now that both exist. **The rename
falls with it** — the name claims a guarantee the code does make — and so does `show()` returning
`self`, which rode along as an independent convenience and is nobody's ruled work on its own. **The
one actionable half left is the word *"chrome"***, which this entry's own text uses; it moves to the
documentation sweep with `T-CHROME-UNRATIFIED`.

- **Where:** `src/controller/userInputController.lua`, `always_shown()` and the `self.always` field
  it sets; call sites at `editorController.lua:17` and `:21` and `consoleController.lua:44`.
- **It is ours.** `git show af9a5782:src/controller/userInputController.lua | grep -n always` →
  nothing; same against `f4cf338c`. Neither upstream `dev` nor PR #45 has it.
- **It is in neither ledger and in no shipped document.**
  `grep -n always_shown doc/development/decisions/input.md` → no hits;
  `grep -n always_shown doc/input_api.md` → no hits. `D-WIDGET-AT-BOOT` ratifies that the console's,
  the editor's and the search strip's widgets are **boot-provisioned**, which is the reason the
  method exists — it does **not** ratify the method or the refusal it installs.
- **The method does two things and only one of them is load-bearing.**
  - `shown = true` at construction **is** load-bearing, and it follows from a ratified change:
    updev's `UserInputController` had no shownness at all (`grep -n "shown"` over
    `af9a5782:src/controller/userInputController.lua` → nothing), and this feature made shownness an
    internal flag by owner ruling 2026-07-20. Host chrome has to start visible without a `show()`.
  - `always = true`, which makes `hide()` **decline** (`:375-376`), **guards a call path that does
    not exist.** All three reachable hide paths target the **project's** widget:
    `consoleController.lua:184` (`love.state.user_input_controller`, run teardown),
    `consoleController.lua:902` (`api_hide`, i.e. `compy.input.hide()`), and `submit_flow`'s
    `if self.auto_hide then self:hide() end`, where `auto_hide` is set only through `configure` —
    the project surface. Nothing can reach the console's or the editor's instance to hide it.
- **Why it is filed rather than fixed.** The guard is defensive code against a caller that would
  have to be written first, and deleting it is a behaviour-neutral simplification **today** that
  stops being neutral the moment anything gains a route to those instances. That is a judgement
  about how much defensiveness this release wants, which is the owner's, not a defect to sweep.
- **Why it matters beyond itself, and this is the reason it is an entry:** an unratified construct
  invisible to both ledgers **gets cited as precedent**. It happened in this session — `OP-03`
  proposed a sibling method partly on the strength of *"it follows the existing idiom"*, which is
  circular when the idiom was never ratified. **The replanning checklist's *unratified terminology*
  item is exactly this, and it fired against our own reasoning rather than against a document.**
- **Found:** 2026-09-06 by the owner, asking what the method is for given that the widget does not
  auto-hide by default. The answer is that it is not about `auto_hide` at all — and that the half
  that is about `hide()` is unreachable.
- **SUPERSEDED 2026-09-09 by the ruling above — RULED 2026-09-06: the guarantee goes.** The owner, on being offered ratify / delete the dead
  half / park it: *"I do not think we need either 'chrome' term or `always_shown` guarantee."* So
  `always` and `hide()`'s refusal are **deleted**, and what remains is the construction-time
  `shown = true` that host surfaces genuinely need. The deletion is behaviour-neutral on the
  measurement above — **re-run it before relying on it**, since it is a claim about what can reach
  those instances and the import moved that code.
- **SUPERSEDED with it — the name outlives its promise, so it is renamed with the deletion.** Once nothing is *always*
  anything, `always_shown()` claims a guarantee the code no longer makes, and a name that
  over-promises is how this construct got cited as precedent in the first place.
- **`show()` cannot simply take its place, and this was checked rather than assumed** (2026-09-06).
  The owner proposed riding the existing method — *"can we just make `show()` returning `self`?
  More elegant form, rides existing method, without 'always' promise"* — and the substitution does
  not hold: `always_shown()` sets an instance flag only, while `show()` additionally claims
  `love.state.user_input`, the **single global handle** the draw loop paints from each frame
  (`open_widget` in `src/controller/userInputController.lua`; the draw gate is
  `src/controller/controller.lua`). Three host surfaces are constructed at boot — the console line,
  the editor's input strip, the editor's search strip — so each calling `show()` would overwrite
  that one slot, last construction winning, and a project's widget would then find it occupied.
  **Making `show()` return `self`** was carried as an independent convenience; what it cannot do is
  replace the construction-time marker. **It is not scheduled** — it left with the sprint.
- **Roadmap:** none. `SHOWN-01` was closed by the reversal; the only row of it that survives is the
  word, at `DOC-01-03`.

### T-KEYS-UNPINNED — `D-EDITOR-KEYS` is ratified and its coverage is unmeasured (RESOLVED, 2026-09-09)

- **Decision:** `../decisions/input.md`, `D-EDITOR-KEYS` — the editor's key contract, retrofitted
  2026-09-06 from the product owner's authorization and the rework author's attestation.
- **What is owed: the check first, the tests second.** Ratifying a behaviour does not test it, and
  nobody has asked which of the contract's four rows the suite actually pins. This entry deliberately
  does **not** claim the coverage is missing — it claims it is **unknown**, and that a decision whose
  coverage is unknown is an obligation rather than a fact.
- **The shape of it, from a survey rather than the measurement** (2026-09-06). Two commands, named
  separately because they cover different files and an entry that prints one command for four bullets
  invites the reader to check the wrong thing:
  `grep -rn "S-escape\|'escape'\|C-s\|C-S-s" tests/ --include=*.lua` for the Escape rows, and
  `grep -n "ctrl+shift+s\|ctrl+s" tests/input/input_global_shortcuts_spec.lua` for the two chords,
  whose spec spells them as combo **strings** rather than as keystroke names and so does not answer
  the first command at all. The survey is what makes the entry worth opening; it is not the answer,
  and the row that closes this is the one allowed to state results:
  - **`Shift+Esc` is heavily exercised** — **17** sites in `../../../tests/editor/editor_spec.lua`
    (`grep -c "S-escape"`), which
    arrived with the import, plus one of ours pinning that it does **not** reach the widget.
  - **Bare Escape's four states** — error, confirmation dialog, block reorder, search — are the rows
    nobody has walked. `editor_spec.lua` presses bare `escape` in four places; whether those are
    those four states, and whether any case pins **silence in navigation and editing**, is exactly
    the unmeasured part.
  - **Our suite currently pins the contract's opposite**, and this is the finding that gives the
    entry its urgency: `../../../tests/input/input_widget_callbacks_spec.lua`, *"editor Escape falls
    through to the widget"* → *"is not claimed by the editor in navigation"* asserts that the
    widget's `cancel` **did** run. Under `D-EDITOR-KEYS` row 1 it must not. That case is a correct
    pin of today's defect and becomes a wrong one the moment the defect is paid, so it moves with the
    fix rather than after it.
  - **`Ctrl+S` and `Ctrl+Shift+S`** have a pinned pair in
    `../../../tests/input/input_global_shortcuts_spec.lua`, whose comments already state the
    contract's third and fourth rows in prose.
- **Why it is a defect and not a chore.** The contract's own history is the argument: the exclusion
  upstream expressed in code, this branch re-expressed as a cross-controller **expectation**, #45
  then changed that controller, and nothing failed — *because an expectation cannot fail*. A ratified
  contract with no case behind it is the same construction with a ledger entry in front of it.
- **Reachability:** every editor key press the contract names. Whether anything is **currently**
  misbehaving beyond `T-NAV-ESCAPE` is unknown, which is the entry.
- **Found:** 2026-09-06, as the direct consequence of writing `D-EDITOR-KEYS` — the owner's ruling
  named this defect at the moment the decision was commissioned, rather than waiting for a review to
  find it.
- **Roadmap:** `EDKEYS-01`.

**RESOLVED 2026-09-09 (`EDKEYS-01`).** The measurement ran first, as this entry asked, and the gaps
it found were closed in the same sprint.

- **The survey above was right about the shape and one of its numbers has moved.** `Shift+Esc` is
  **21** sites in `../../../tests/editor/editor_spec.lua`, not 17 — session79 added the four
  *"leaving through Shift+Esc (2.3)"* cases on 2026-09-07, the day after this survey was written.
  17 + 4 = 21, so the difference is that sprint and not drift.
- **The answer, row by row.** `Shift+Esc`: pinned at two layers. Bare Escape's four states: three
  were already pinned by the imported spec — an error message, a confirmation dialog, search — and
  are **cited rather than duplicated**; the **block reorder** was pressed as setup with nothing
  asserted, and now has a case. `Ctrl+S` and `Ctrl+Shift+S`: pinned, and the cases assert what their
  comments claim.
- **The wrong pin this entry predicted is real and is deliberately kept green**, annotated in place:
  `../../../tests/input/input_widget_callbacks_spec.lua`, *"is not claimed by the editor in
  navigation"*. Its **editing** twin — the same code path, and the half that costs a user something
  — is new: `../../../tests/input/input_editor_keys_spec.lua`, *"clears the open block, losing the
  edit"*. Both carry a `FLIP:` comment naming `D-LIFECYCLE-FLAGS`, so `FLAGS-01` knows exactly which
  cases invert and anything else going red is a regression.
- **Three findings the walk produced did not belong to it** and were ruled by the owner on
  2026-09-09: two wording defects in `D-EDITOR-KEYS` itself (`Ctrl+S` *"never reaches the editor
  controller"* is mechanically false while the behaviour is right; `Ctrl+Shift+S` is called
  application-level and lives in `EditorController:_leave_keys`), and the `Shift+Esc` row's
  *"leave, and discard"* being false in the four states that claim bare Escape regardless of
  modifiers. All three are corrected on the decision.
- **Suite:** 1135 → 1139, four added, none removed, none replaced in place.

### T-CONSOLE-SURFACE-INTERFERES — the console got a `compy.input` of its own, and it reaches into the running project's widget (RESOLVED, 2026-09-08)

**RULED 2026-09-07** (owner, in conversation, on being shown the cross-talk): *"they absolutely
should not interfere."* So this is a commitment, not an observation.

- **Where:** `src/controller/consoleController.lua` — `get_compy_input` (the surface builder),
  `widget_store` (the per-access resolver), and the two call sites that build the namespaces,
  `prepare_env` (console) and `prepare_project_env` (project).
- **What is wrong.** One builder is called twice, so console and project each get their **own**
  surface object — but **both resolve the widget from the same global slot**,
  `love.state.user_input_controller`. The widget half is therefore shared while the dispatch half
  is not. Measured 2026-09-07 on a real `ConsoleController`: `console.compy.input ~=
  project.compy.input` (distinct objects), and `console.compy.input.hide()` **hides the widget the
  project surface sees**. `callbacks` is worse than a method call — `widget_store` resolves it to
  the live widget's own table, so a write through the console surface lands on the **project's**
  callbacks.
- **Why it matters more now than when it was written.** The per-instance lifecycle flags land on
  the **widget** (`../decisions/input.md`, `D-LIFECYCLE-FLAGS`), so a `configure` through the
  console surface would rewrite a running project's flags. `show` contends with the shown-flag
  repeat refusal on top of that.
- **The dispatch half is dead, and silently.** Nothing walks the console surface's `shortcuts` or
  `hooks` — the console route runs its own narrow dispatch, not the chain (see
  `D-ROUTE-OWNS — console/editor convergence onto the shared chain is unimplemented`, `BACKLOG`).
  So `compy.input.hooks.keypressed = f` typed at the prompt is **accepted, stored and never
  fires**. Both halves fail without a word: one reaches too far, the other not at all.
- **Provenance: the surface is OURS, and its presence on the console namespace is a side effect.**
  At the PR base (`3256aac`) the compy namespace is `{ terminal, audio, graphics, fonts }` — no
  `input` member at all — and the input verb that did exist, `input_text`, was published as
  `compy_namespace.text_input` **only on the project namespace** (`:594`, `:628`). The
  two-namespace split is inherited; giving the console an input surface is not. The feature
  replaced `text_input` with a surface built by one shared function called from both prep sites,
  and the console silently gained one nobody wired.
- **Direction, and the code already anticipates it.** `build_widget_api(get_widget,
  get_active_flag, state)` is parameterised on its resolvers on purpose — its own comment says
  *"any adopter — not only the project widget — gets the same ergonomics over ITS OWN widget by
  supplying its own resolvers."* The blocker is one level up: `get_compy_input` and `widget_store`
  close over the global slot instead of taking a resolver. **Three shapes, and the choice is the
  owner's:** (a) **remove** the `input` member from the console namespace, restoring the base's
  asymmetry — cheapest, and it cannot interfere with what it does not have; (b) **parameterise the
  resolvers and give the console its own widget instance**, which fixes the interference and is
  also step one of the convergence; (c) leave it and document — **ruled out by the ruling above**.
- **Reachability:** any prompt reachable while a project's widget exists. Note that the ordinary
  prompt cannot be typed at while a non-blocking project holds the route, so today the reachable
  paths are `inspect` and anything that evaluates console-env code — but the widget outlives the
  run's top-level code, so the window is the whole of `project_open`.
- **Coverage:** none. No spec asserts that the two surfaces are independent; the identities above
  were measured in a scratch spec that was deleted rather than kept, because pinning the current
  shared behaviour would pin the defect.
- **RULED 2026-09-08 — paid by option (a), in this release, by deletion.** The owner: *"we need to …
  explicitly prevent building `compy.input` in console env because input API is not yet ready to run
  out of project sandbox."* So the `input` member is removed from the **console** namespace and the
  PR base's asymmetry returns. **Both halves die with the surface**: nothing can reach a project's
  widget through a surface that does not exist, and there are no undispatched tables when there are
  no tables.
  - **Measured before ruling:** nothing in `src/` reads a console-environment `compy.input` (zero
    hits) and no test touches the console namespace (zero hits).
  - **The base's shape is the precedent, NOT the mechanism.** At `3256aac` the shared builder
    returned `{ terminal, audio, graphics, fonts }` and the project prep site *added* `text_input`
    afterwards — but that namespace carried **no metatable**. Today `input` is not a field: it is an
    upvalue served by `__index`, and `__newindex` **raises unconditionally** on the key, so
    `compy_namespace.input = …` at the project prep site would raise.
    **Parameterise the builder instead** — `get_compy_namespace(terminal, with_input)` — leaving
    `__index` to answer `nil` for `input` in the console environment.
    *(Corrected 2026-09-08 by the S82 delivery review, which caught the two clauses conflicting.)*
  - **Keep `__newindex`'s raise on `input` in both namespaces**, so `compy.input = x` at the prompt
    still fails loudly rather than quietly creating a fake.
  - **It defers a ruling rather than satisfying it.** *"`compy.input` must work in the console
    environment"* is still owed — see the BACKLOG stub and `../wip/input-in-console/`.
  - **Documentation obligation.** `LEDGER-02` removes this from the CHANGELOG and from
    `PR-01-02`, so without a line in `internals/` the asymmetry ships unstated — and
    `internals/console.md` still describes `main_env` as carrying the full API including `compy`.
    One line when it lands: **the console environment's `compy` has no `input` member, by ruling,
    and assignment to it still raises.**
  - **`LEDGER-02` applies at release time:** the member is ours, was introduced and paid inside this
    branch, and so never existed for the outer world — no CHANGELOG line, no `PR-01-02` row.
- **Roadmap:** `BUG-03-02`, added 2026-09-08, ahead of the slice cut.
- **RESOLVED 2026-09-08, `BUG-03-02`.** The builder takes a parameter —
  `get_compy_namespace(terminal, with_input)` — and only `prepare_project_env` passes `true`. The
  `__newindex` raise on `input` is untouched in both namespaces, so a console-side assignment still
  fails loudly. Two cases in `tests/input/input_events_spec.lua`'s *"the mutable/immutable
  boundary"*: the console environment has no surface and refuses the assignment, and the project
  environment still has one. Documented at `../internals/console.md`, *"Three Environments"*.

### T-ROUTE-EATS-UNCONSUMED — the project route consumes what nobody consumed, so a run-and-print project leaves the console deaf (RESOLVED, 2026-09-08)

**RULED 2026-09-07** (owner, on being shown the base comparison): *"to recover dispatching
regression (now really biting on the print-and-pass projects) we need to implement default
passthrough mode which was already discussed — unconsumed events go back to console dispatcher —
and whether they are consumed is defined by project widget's 'shown' status not by what it does or
does not do with events (mechanism is in place — we just need to start interpreting return
values)."* So this is a commitment, not an observation.

**RELEASE SCOPE, ruled 2026-09-08. Roadmap: `BUG-03-01`, ahead of `ACC-02` and the slice cut** —
placement **confirmed** by the owner the same day, along with the sprint running **first** of what
remains. The owner, on the
measured bite: *"we need to enable fallthrough into console."* It ships **without** the console
capability the same conversation deferred — this is a repair, not a step toward that feature.

- **Where:** `src/controller/controller.lua` — `occupy_input`, `set_handlers`, the `_bindable`
  list; `src/controller/consoleController.lua` — `run_user_code`, `run_project`. The accepted
  consequence is `../decisions/input.md`, `D-ONE-LIFETIME`, *"Consequence, accepted"*.
- **What happens today.** `occupy_input` binds **every** `_bindable` channel to the project
  dispatcher, and its own comment says why: *"It installs even with no project handlers: an
  unhandled event must stop in the project route, never reach the hidden console."* Since
  `D-ONE-LIFETIME` deleted the success-path release, the route is held for the whole of
  `project_open`. So a project whose entire body is `print('help')` returns, keeps the route, and
  the console prompt below it takes nothing: the dispatcher finds no shortcut, no hook, and a
  widget that is not shown, and the event dies in the route. Recorded as measured fact in
  *"Input-only / pointer-only projects stay live in `project_open`"* (`RETIRED`), whose closing
  bullet states that **every** non-blocking project keeps the route, interactive or not.
- **What the base did.** At the PR base (`3256aac`) `set_handlers` bound a channel only through
  `hook_if_differs` — `if orig and new and orig ~= new then love[key] = ...`. A project that
  defines no handler binds nothing, so `love.keypressed` stayed the console's, and the gateway's
  `love.handlers.keypressed` fell through to it whenever no widget was published. **A
  run-and-print project left the console typeable.**
- **The premise, and where it fails.** `D-ONE-LIFETIME` accepts the new behaviour on the ground
  that *"A non-blocking project with no interaction surface keeps the keyboard until it stops,
  where it previously handed it back at `'project_open'`. That is the pre-feature behaviour."*
  The first clause is right and the justification is not: pre-feature, a project **with no
  interaction surface** never took the keyboard in the first place, so there was nothing to hand
  back. The claim holds for a project that hooks something; it fails for exactly the class that
  hooks nothing — which is the class the sentence is about.
- **Which shipped examples actually suffer — measured 2026-09-08, and it is a short list.** The
  class is *non-blocking run, no widget shown, no consuming hook*:
  - **`sine` — the whole list.** Thirty lines, pure top-level `love.graphics` drawing, no hooks at
    all, no widget. It draws, returns, and the prompt below it is dead until the project is stopped.
    At the base it was typeable the moment the run returned. **This is the clearest instance of the
    regression in the tree.**
  - **`sapper` is deliberately NOT counted** (owner, 2026-09-08): *"sapper not included, it never
    expected console input to be working."* It is click-driven and draws through the terminal, so
    its console strip is painted and inert — that appearance is the separate BACKLOG entry
    *"The console's prompt is drawn under a project that never takes over `love.draw`"*, which this
    repair happens to pay.
  - **`guess`, `repl` and `valid` do not suffer**: each shows a widget for the whole run, so the
    route's consumption is intended and nothing changes for them.
  - **The nine blocking examples do not suffer**: `balloons`, `clock`, `colors`, `keyboard`, `life`,
    `paint`, `pong`, `tixy`, `turtle` all take over `love.draw`, so the gate is shut and behaviour is
    unchanged. `maze` likewise (its entry is `maze_main.lua`, and it draws).
  - **No shipped example is `update`-without-`draw`**, which is the only shape that both blocks and
    passes the gate. The one known project of that shape is the other fork's serial terminal.
- **Blast radius:** every project that hooks no keyboard channel and does not stop itself. The
  cosmetic half of this was already ruled once and separately — *"The console's prompt is drawn
  under a project that never takes over `love.draw`"* (`BACKLOG`, ruled to keep 2026-08-07) — and
  that entry treats the route belonging to the project as a **premise**. It is the consequence of
  a decision taken later, not a given.
- **Related, and not the same thing:** `stop()` from a project's own top-level code does not free
  the route either, because `run_user_code` calls `set_user_handlers` **after** `pcall(f)` and
  unconditionally on success, re-occupying on the way out. That is an ordering defect and is
  independent of this one — fixing it makes *"print then stop"* work while leaving plain
  *"print"* deaf.
- **Coverage:** none. No spec asserts what the console can receive after a non-blocking run
  returns.
- **Why it surfaces now:** it is R6 of `../wip/77-new-input-api/validation/notes/S80-console-input-mode-spec.md`
  — *"a run-and-print project must leave the console usable"* — which the spec states as a
  requirement without knowing it names a change from the base.
- **Found:** 2026-09-07, verifying that spec's §3.8 against the PR base. Nothing here was measured
  by re-running the base; it is read at `3256aac` and at HEAD, and both readings are cited by
  function name above.
- **Fix shape, per the ruling: the route already computes the answer and drops it.**
  `ProjectInputController._dispatch` returns the walk's verdict, and `dispatch`'s own comment
  states the rule the owner named — *"the walk reports consumed iff a consumer fired or the widget
  was shown."* But `occupy_input` binds `love[k] = with_canvas_and_errors(CC, function(...) return
  pic[k](pic, ...) end)` and LÖVE discards a handler's return, so the verdict dies at the top.
  `Controller._defaults[event]` already holds the console's handler for every channel the console
  installs, so an unconsumed event has a ready destination.
  - **Ten against twelve.** The console installs **ten** channels; the project route binds
    **twelve** — `ProjectInputController.EVENTS` adds `singleclick` and `doubleclick`. Those two have
    no console default **by design**, so a falsey verdict there falls through to nothing, and that
    path **must not raise**.
  - **The gate's reader does not exist yet.** `hook_draw` is a *function*; the flag it sets,
    `user_draw`, is a **file-local upvalue** (`controller.lua:31`) whose only public reader is
    `Controller.user_is_blocking()` — which ORs it with `user_update` and would shut the gate on
    exactly the class this repair serves. ~~**An accessor for `user_draw` alone is part of the
    work.**~~ **No accessor was built and none was needed** — see the RESOLVED bullet below. The
    sentence before it stands and is why the gate is not `user_is_blocking()`.
  - **Four breaking tests**, all expressible on the existing fixture, which stands up a real
    `ConsoleController` over real `love.handlers`: (1) a project that hooks nothing — a key reaches
    the console; (2) a project that hooks `love.draw` — it does not; (3) a hook returning truthy
    still consumes; (4) a hook returning **falsey** on a channel it hooked — the boundary the other
    three do not touch, and the one `T-SEEDED-HOOK-FALLS-THROUGH` governs.
  - *(This bullet was hoisted out of the deferred workspace's spec on 2026-09-08, per the S82
    delivery review: release work must be executable from release-side documents.)*
- **What the gate deliberately does NOT restore, and it is the answer to *"is this exact base
  parity?"*** At the base there was no draw gate: binding was per channel, so a project that took
  over `love.draw` and defined no keyboard handler left `love.keypressed` with the console —
  **you could type into a prompt you could not see.** The gate keeps that closed. It is not a
  regression to keep it closed: today the route eats the event anyway, so this is a base-era
  behaviour our branch already ended, and the repair declines to bring it back.
  - **Measured over the corpus: no member.** Every example that takes over `love.draw` either hooks
    a keyboard channel or shows a widget that stays shown, and a shown widget consumes before the
    gate is ever consulted (`projectInputController.lua:141-144`). `tixy` and `balloons` are both
    excluded on that second test — `balloons/terminal.lua:35` shows once and never hides, the
    *"activate once and stay open"* idiom its own comment names.
    *(Corrected 2026-09-08 by the S82 delivery review. The first version of this bullet claimed
    `balloons` as the one member, from a survey that grepped `main.lua` alone and so missed a
    twelve-file project's `show`. The narrowing is real; **it has no reproducible member here.**)*
  - So with `T-SEEDED-HOOK-FALLS-THROUGH` wrapped, the repair is **exact base parity per channel**,
    and the one deliberate narrowing costs nothing observable in the shipped corpus. Both halves
    belong in the same documentation line.
- **The gate this needs.** Falling through unconditionally would type into a prompt that is not on
  screen whenever the project owns `love.draw`. The honest predicate is *"the console is actually on
  screen"* — the flag `hook_draw` sets. **`user_is_blocking()` cannot serve as its reader**: it
  returns `user_update or user_draw`, so it would also shut the gate on a project that hooks only
  `update`. See the `Fix shape` bullet.
- **`sapper` is the instructive case.** It draws through the terminal and binds only derived clicks,
  so today its console strip *"reads as an available prompt while it is not one"* (`BACKLOG`, *"The
  console's prompt is drawn under a project that never takes over `love.draw`"*). The fall-through
  makes it one, which pays that entry rather than colliding with it — and the owner has ruled it out
  of the sufferers list all the same.

> **SUPERSEDED 2026-09-08, kept for its reasoning only.** This bullet previously carried a second
> corpus measurement — *"twelve tracked examples: six hook a keyboard channel and all six take over
> `love.draw` … the shipped corpus changes behaviour in zero cases"*. The keyboard-and-draw half
> still holds (`clock`, `colors`, `life`, `maze`, `pong`, `turtle`), but the corpus is **fifteen**,
> the examples hooking no keyboard channel are **nine**, and *"zero cases"* is false the moment
> `sine` gets a live prompt back. **The measurement above this line is the one to use.**

- **RESOLVED 2026-09-08, `BUG-03-01`** (`a4ef4640`). `occupy_input` spends the walk's verdict instead
  of discarding it: on falsey it calls `Controller._defaults[event]`, gated on `user_draw` and on the
  channel having a console default. Six cases in a new
  `tests/input/input_console_fallthrough_spec.lua`; two existing cases that pinned the reverse are
  re-pinned in place. Documented at `../internals/event_dispatch_layers.md`, *"What becomes of an
  event nobody consumed"* — including the base-parity answer and the one deliberate narrowing — and
  in `../internals/user_input.md`'s chain block.
- **`LEDGER-02` applies at release time:** this was introduced and paid inside this branch — the
  route began consuming everything when `D-ONE-LIFETIME` deleted the success-path release, and the
  fall-through pays it before the release — so **it never existed for the outer world: no CHANGELOG
  line and no `PR-01-02` row.** Stated here because those steps read the ledger, not a session
  report, and *"a regression from the PR base"* otherwise reads as outer-world visible.
- **One thing this entry asked for was not built, and the entry was wrong to ask.** *"An accessor for
  `user_draw` alone is part of the work"* assumed the gate would be read from outside
  `controller.lua`. It is read inside it, where the flag is a file-local upvalue, so no accessor
  exists and none is needed; adding a public reader nobody calls would have been surface for nothing.
  The `user_is_blocking()` half of the finding stands and is why the gate is not that function.

### T-SEEDED-HOOK-FALLS-THROUGH — a legacy `love.*` handler folded onto the chain gets a consume convention it was never written against (RESOLVED, 2026-09-08)

**RULED 2026-09-08** (owner, on being shown that the fall-through goes past base parity on hooked
channels): *"we can restore parity by wrapping legacy `love.` hook into fn.stop_here — which would
match the project expectation that occupying what it thinks is the whole channel leaves no silent
receivers. if dev installs a hook into `compy.input.hooks` they are presumed to know the
fallthrough-by-return convention … it guarantees exact compatibility with love conventions
(hijacking the hook from love.surface consumes, i.e. blocks propagation)."*

- **Where:** `src/controller/projectInputController.lua`, `seed_hooks` — and it is only reachable
  once `T-ROUTE-EATS-UNCONSUMED`'s fall-through lands, because until then no verdict is read.
- **What is wrong.** `D-HOOKS-SEEDED` folds a project's own `love.keypressed`/`love.mousepressed`/…
  into the hook tier, where `D-CHAIN-OF-3` reads the return value: **truthy consumes, falsey falls
  through**. A legacy handler was written under LÖVE's convention, where assigning `love.keypressed`
  means owning the channel and there is no propagation to opt out of. So once the fall-through
  reads verdicts, a legacy handler's **incidental** return value starts deciding whether the console
  also sees the event — a semantics nobody authored, and one that differs per handler by accident.
- **Against the PR base.** At `3256aac` a project that defined `love.keypressed` **displaced** the
  console's, so the console saw nothing on that channel regardless of any return. Wrapping restores
  that exactly, while a channel the project never defined still falls through — which is also
  exactly the base, since binding there was per channel.
- **Fix shape, per the ruling.** Wrap at the seam that already distinguishes the two authoring
  conventions: `seed_hooks` seeds **only where the project set no explicit hook**, so a wrapper
  applied there lands on legacy handlers alone and never on a `compy.input.hooks` assignment. The
  wrapper calls the handler and returns truthy.
- **It is a statement about the chain, so it owes a ledger line, not only code.** *A seeded legacy
  handler consumes unconditionally; an explicitly registered hook follows the truthy convention.*
  That refines `D-HOOKS-SEEDED` and is an exception to `D-CHAIN-OF-3` worth naming rather than
  leaving in a wrapper.
- **Coverage:** none, and none is possible before the fall-through lands.
- **Roadmap:** `BUG-03-03`, **ruled 2026-09-08**. It is small — a wrapper, one test, one ledger
  line — and the recommendation was to fold it into `BUG-03-01`, since the deviation it removes
  exists **only if the fall-through ships without it**. The owner ruled it a **visible row** instead.
  The constraint the fold was buying is therefore carried on the row: `-03` lands **inside**
  `BUG-03`, so the release never holds `-01` with `-03` outstanding.
- **Found:** 2026-09-08, when the fall-through's divergence from base was being written up as
  documentation; the owner replaced the documentation with a fix.

- **RESOLVED 2026-09-08, `BUG-03-03`** (`628001b1`). `seed_hooks` wraps what it seeds; the wrapper
  calls the handler and returns truthy, so it reaches legacy handlers alone and never a
  `compy.input.hooks` assignment. `../decisions/input.md`, `D-HOOKS-SEEDED` carries the amendment
  and the named exception to `D-CHAIN-OF-3`; `doc/input_api.md` states the rule for a project author
  at four sites; `internals/user_input.md`'s chain block says it inline.
- **`LEDGER-02` applies at release time:** the convention refines a chain that is this branch's own,
  so it never existed for the outer world — no CHANGELOG line, no `PR-01-02` row. What a project
  author needs is in `doc/input_api.md`, not in a migration note.
- **What the fix cost, and it was not foreseen on this entry.** The wrapper sits at the hook tier, so
  a seeded handler now also shields the **project's own widget**. `turtle` relied on the opposite and
  would have taken text it could never submit. Ruled by the owner on sight — *"Do wrap and update
  turtle … Programs using legacy love. hooks were not aware of widget anyway"* — and `turtle`
  migrated to `compy.input.hooks` in the same commit. Measured by walking every `.lua` in all fifteen
  example directories: **three** combine a captured handler with a widget — `turtle`, `tixy` and
  `maze` — and only `turtle` was a defect. *(This bullet first said two, missing `tixy`'s
  `mousepressed`; corrected the same evening.)* All three were migrated, along with `sapper`, the one
  non-blocking example with a captured handler; four examples keep the legacy spelling on purpose.
  Per-example blast radius:
  `../wip/77-new-input-api/validation/notes/S83-legacy-handler-blast-radius.md`.
- **Coverage:** `tests/input/input_events_spec.lua`, *"a falsey handler textinput still shields the
  widget"* (replacing the case that pinned the reverse), and
  `tests/input/input_console_fallthrough_spec.lua`, *"a seeded legacy handler shields the console
  too"*.

### The simple API's control-key half — DEFERRAL REVERSED, 2026-09-07 (same day it was taken)

- **Why it is here rather than in `BACKLOG`:** the entry existed to hold a deferral and the question
  the deferral was waiting on. **Both are discharged.** The requester answered — *"The scenario is,
  essentially, the editor. The API should make it easy to implement something like the built-in
  editor"* — and the answer made the design cheap rather than open: a callback whose **return value**
  decides consumption needs no new precise-surface callback, no key list, and no new chain position.
  **`compy.on_key` ships**; see `../decisions/input.md`, `D-SIMPLE-SURFACE` statement 7, and
  `T-SIMPLE-SURFACE` for the obligation.
- **What the question bought, recorded because the framing is the reusable part.** It was
  deliberately **not** definitional — *"what is a control key"* invites another summary — and asked
  instead for **one concrete scenario, start to finish**. The scenario settled three things the noun
  never would: that a report must **not** terminate the question, that modifier-accompanied keys are
  not the whole set, and — the part no reading had covered — that the editor decides **per key**
  whether its own widget sees the key at all.
- **The three implementation shapes weighed while it was open are superseded**, and the reason is
  worth keeping: all three were **reports**, and a report cannot express consumption. The ninth
  precise-surface callback they were competing to justify is **not taken**.
- **What the answer raised instead is a seam this release has already declined** — the editor's
  pass-through default, `T-EDITOR-SEAM-DEFAULT-OPEN`. It now carries the strongest argument for a
  future release that exists, because the requester's own acceptance test names it.

### T-LOVE-IS-A-HANDLER — the corpus called `love.*` functions "callbacks", which the ledger's own vocabulary reserves for ours (RESOLVED, 2026-09-05)

- **Where:** eight sites, re-derived rather than cited — the command is

  ```
  git grep -nE '`?love\.[a-z*]+`?[^.]{0,40}callback|callback[^.]{0,30}`?love\.[a-z*]+' \
    -- doc/ ':!doc/development/wip/' src/ tests/
  ```

  At 2026-09-05: `internals/project_sandbox_env.md:49` (the **T1 row is titled
  *"callbacks"***) and `:109`; `conventions/input_adoption.md:86`
  (*"a captured `love.*` callback"*); `projectInputController.lua:177`;
  `input_nfr_mechanism_spec.lua:147` and `:149` (**one of them a test
  description**, so it is read in suite output); `input_routing_spec.lua:153`;
  `project_open_liveness_spec.lua:59`.
- **State: a live contradiction of a ruling this feature made.**
  `../decisions/input.md`, *"Vocabulary — hook, callback, handler"*, splits the
  three words by **who owns the name**: a **hook** is keyed by a LÖVE event name,
  a **callback** by a Compy-chosen name, and a **handler** is *"exactly what LÖVE
  means by it: the function occupying `love.<event>`"*, with *"Compy adds no
  second sense"*. So `love.keypressed` is a **handler**, and once a project's is
  captured it runs as a **hook** (`D-HOOKS-SEEDED`). Calling it a callback
  collides with `compy.input.callbacks`, which is the one thing the three-word
  split exists to prevent.
- **Why it survived the vocabulary sweep.** `FIX-02-09`'s word list was
  widget/prompt/field/overlay/area/draft. `hook`/`callback`/`handler` was
  **ruled** in the decisions ledger and never **swept** in the corpus — a ruling
  without a sweep is exactly the shape that leaves a document contradicting the
  decision it is downstream of.
- **Not a rename, in two of the eight.** `project_sandbox_env.md`'s T1 row is
  *titled* "callbacks" and lists `love.draw`/`love.update`/`love.keypressed` as
  its members, so the fix is the row's framing, not a word in a sentence. LÖVE's
  own documentation calls these callbacks, so wherever the corpus is speaking
  **as LÖVE** the sweep says *handler (LÖVE's "callback")* rather than
  overwriting the platform's word — the same authorship seam `FIX-02-28` settled
  for the nested repos.
- **Found:** 2026-09-05, from an owner question about whether the hook/callback
  clash was fully resolved. It was ruled; it was not swept.
- **Release scope:** in. The corpus is agent-read, and a word that means two
  things in the same subsystem is wrong *input*, which is `FIX-02 (c)`'s whole
  argument for running first.
- **Roadmap:** `FIX-02-29`.
- **Resolution, 2026-09-05: all eight, and two of them were not word swaps.**
  `project_sandbox_env.md`'s **T1 row is retitled *handlers*** and carries the
  seam in place — *(LÖVE calls these "callbacks"; here the word is the widget's)* —
  because that document is describing LÖVE's own surface and overwriting the
  platform's word would be the mistake `FIX-02-28` ruled against for another
  author's repository. `input_nfr_mechanism_spec.lua`'s pair became ***slot***
  rather than *handler*: the sentence is *"no project handler remains wired in any
  `love.*` …"*, and *handler* twice in one clause names two different things. The
  other six are direct. Re-run the command above to confirm; the surviving hits are
  the seam itself, this entry, and the convention that describes the defect.


### T-HELD-SET-GHOST — `D-COMBO-TABLES` still described the held-key set, and `D-ASK-THE-DEVICE` vouched for it (RESOLVED, 2026-09-05)

- **Where:** `../decisions/input.md`, `D-COMBO-TABLES`, the first of two bullets
  contrasting the representations: *"the **held-key set** keeps precise
  left/right names (`lctrl` ≠ `rctrl`)"* — present tense, in a live decision.
- **State: a false claim, not a stale wording.** `D-ASK-THE-DEVICE` withdrew the
  whole held-key-set arc — *"`compy.input.keys_pressed` and
  `Controller.keys_pressed` are **dissolved from all occurrences**, production and
  test"* — and `git grep -n 'keys_pressed' -- src/ tests/` returns **zero**. There
  is no held-key set to be one half of a contrast.
- **The sharper half: the ledger certifies the false paragraph.**
  `D-ASK-THE-DEVICE`'s own preamble says *"D-COMBO-TABLES, D-COMBO-SHAPE,
  D-LOVE-ARGS and D-BUTTON-TRIGGER … **stand unchanged** — only the source the
  matcher reads from changes."* That is true of the serialisation rule and false
  of this bullet, so **a reader who cross-checks the two entries gets
  confirmation instead of a contradiction** — the same failure mode as the
  `D-CHAIN-OF-3` claim session73 found, where a statement was right about one
  route and false about the other.
- **Size: two sentences.** The contrast collapses rather than needing a
  replacement: the device is the source, and folding left/right is a property of
  **serialisation**, which the surviving bullet already states.
- **Found:** 2026-09-05, verifying `FIX-02-07`'s `:418` marker before acting on
  it. The marker asks for something else entirely and does not mention this —
  **a marker is a defect report, and reading the block it points at is how the
  defect it did not report gets found.**
- **Release scope:** in. A live decision asserting a dissolved structure is
  exactly what `DEC-01`'s ledger work exists to prevent shipping.
- **Roadmap:** `FIX-02-07`, with the `:418` disposition.
- **Resolution, 2026-09-05:** the two-representation contrast is **collapsed**, not
  re-worded. The surviving sentence says the folded form is the only representation
  a consumer meets, that modifier state is read from the device at match time, and
  that the left/right names survive nowhere but inside the fold table that produces
  the generic name (`util/key.lua`, `mod_triples` — verified, not assumed).
  `D-ASK-THE-DEVICE`'s *"D-COMBO-TABLES stands unchanged"* is **true as written**
  once the bullet is gone, so that entry needed no edit — which is the tell that the
  bullet, not the certification, was the defect.


### ~~`D-CHAIN-OF-3` contradicts itself about the widget's hidden-check~~ — RETIRED 2026-09-04, paid the day it was filed

- **What it was:** three statements about one mechanism inside four paragraphs of
  `../decisions/input.md`'s `D-CHAIN-OF-3`. Two matched
  `projectInputController.lua`'s `dispatch` (*"hidden → the widget is skipped"*, and
  *"the widget's own test is `is_shown()`"*); one did not — *"the terminal widget is
  **always invoked**… there is **no external 'is it shown?' wrapper**"*.
- **Resolution: rewritten to the shipped shape, with the rationale it had been
  missing** (owner, 2026-09-04). The decision now says **why** the chain answers for
  the widget rather than merely that it does: the other two components are
  passthrough filters whose return value *is* their answer, while the widget is a
  **stateful machine that reports outcomes asynchronously through its callbacks**, so
  there is no moment at which it could return *"I consumed this"*. It therefore either
  swallows the event or is not in the walk, and the dispatching layer decides which.
  The chain's own return is kept and documented as deliberate — nothing reads it
  today, it costs nothing, and it keeps chains stackable — with the explicit note that
  **no generic machinery was built for a speculative need**.
- **The true half of the old claim survives, correctly scoped:** the widget's internal
  `if not self.shown` no-op does exist and is load-bearing on the **console** route,
  which calls `input:keypressed(k)` unconditionally. The old paragraph was right about
  that route and wrong about the one the decision is about.
- **Found by verifying a marker instead of executing it.** The marker had the
  contradiction right and the sides backwards — it called the false statement *"proper
  approach"* and the true one *"supposedly stale"* — so acting on it as written would
  have deleted the accurate sentence. That is the argument for the disposition rule:
  a marker is a defect **report**, and a report is checked before it is believed.
- **No code changed and no test moved**; the suite pins the observable behaviour from
  both routes and it was never in question.

### `internals/examples/turtle.md` documented the pre-`auto_hide` turtle, sample code included (RESOLVED, 2026-09-03)

- **Where:** `../internals/examples/turtle.md` — the summary line (`:15`), the Lua **code sample**
  (`:22`ff), the *"Re-arm"* paragraph (`:44`), the echo-guard paragraph (`:48`) and the first
  points-of-attention bullet (`:58`).
- **State:** all five described the close as the **callback's** — `after_submit` calling
  `compy.input.hide()`, with a `show` carrying no `auto_hide`. `FEAT-02` moved the example onto
  `auto_hide` (`main.lua`: `auto_hide = true` in the `show`, `after_submit = arm_echo_guard`), and
  the document was not migrated with it. **The code sample is the serious half** — prose can be read
  around, a sample is copied.
- **Why it matters beyond accuracy:** the sample taught the shape the feature *replaced*, in the
  document a troubleshooter opens when the example misbehaves, and it would have been read during a
  device pass as the intended behaviour.
- **Found 2026-09-03**, checking whether *"one-shot"* was live vocabulary after the owner corrected
  the term: *"one-shot widget is autohiding widget now, because behaviour itself is repetitive."*
  The grep for the retired word landed on a retired **mechanism**.
- **Resolution.** All five corrected against `main.lua`, with the mode stated where it was implied:
  `auto_hide` closes on **every** submit until something passes `auto_hide = false`, so *"one-shot"*
  is the wrong word for it — the point `D-AUTO-HIDE` already makes (*"`oneshot` names a single
  occurrence while this is a standing mode"*). The genuinely one-shot thing in that file, the
  self-unregistering `textinput` shortcut, keeps the word and now says why it earns it.
- **Deliberately not done here, and since PAID:** the file's remaining vocabulary drift
  (*"the prompt"* for the widget, two live `field` uses) was left for `FIX-02-09`, which carries
  the fifth-name ruling; only the false mechanism was taken at the time. **`FIX-02-09` executed it
  2026-09-04 (session73)** — the file now says the widget is shown and hidden, and the `field` uses
  are gone. Recorded here rather than only in the roadmap because this bullet is what a reader of
  this entry would otherwise still treat as outstanding.
- **Provenance: introduced in this branch.** The document is `#77`'s own, and so is `auto_hide`.

### The CHANGELOG missed a removal that is expressed as a deletion, not an absence (RESOLVED, 2026-09-03)

- **Where:** `../../../CHANGELOG.md`, `CURRENT_SCOPE` → `Removed`, and
  `../../input_api.md`'s closing paragraph under *"Migration from the legacy globals"*.
- **State:** four evaluator objects — `InputEvalText`, `InputEvalLua`, `ValidatedTextEval`,
  `LuaEditorEval` — were **reachable from project code at the PR base** and are not now. Never
  documented as API: a project environment starts as `table.clone(getfenv())`, so the framework's
  own globals came along with it (the class `general.md` holds as `T-NAMESPACE-CLONE`). This
  feature **withholds them deliberately** (`consoleController.lua`, the
  `project_env[name] = nil` loop with its stated reason) and exports `LuaHighlighter`,
  `LuaSyntaxValidator` and `LineValidators` instead, which were reachable the same accidental way
  at base and are now intentional. So a project's reach changed in both directions and the
  changelog recorded neither.
- **Why the sweep that was looking for exactly this missed it — two reasons, and the second is the
  one worth carrying.** `FIX-02-17` found the sixth removed global by **differencing `project_env`'s
  assignment keys** at `3256aac` against HEAD. **(a) Structural:** that difference is blind to a
  removal expressed as a *deletion* — `project_env[name] = nil` is not an assignment of a name, it
  is the unmaking of one, and appears on neither side. *A set difference finds what is absent; it
  does not find what is actively removed.* **(b) Mine, found by the peer review 2026-09-03:** the
  grep was `project_env\.[a-z_]+`, **case-sensitive and lowercase-only**, so it also hid the three
  *additions* — `LuaHighlighter`, `LuaSyntaxValidator`, `LineValidators` — and **those are the
  evaluator replacements**. Three new evaluator-shaped exports showing up in the difference would
  have asked *"replacing what?"*, which is the question that leads straight to the withheld four.
  **The method would have worked; a character class dropped a third of its input without saying
  so.** The published figure was *23 → 17*; the true shape is **23 → 20**, six removed and three
  added.
- **Found by executing, not by reading** (2026-09-03). The owner asked whether `eval`/`result` were
  ever really exported. A scratch spec printed the project environment: `eval` a function (the Lua
  evaluator, unrelated to the widget, exported at base and today), `result` **nil** — never a name
  at all — and the four evaluator objects **nil**, while `pre_env` still carried them. The gap
  between those two tables is what pointed at the withholding loop.
- **Resolution.** A `Removed` bullet in the CHANGELOG at user-facing altitude, saying they were
  never API but were *there*, and naming the three exported replacements. The guide's closing
  paragraph said *"are not project API. Do not place them in `show` or `configure` tables"* — advice
  about a key that does not exist, phrased as though the objects were still to hand; it now says
  they are not in the environment and names what is.
- **Provenance: the removal is this branch's; the reachability was pre-existing.** Mixed in
  `ledgers.md` §3's sense, and stated to the half that shipped: a project at base could reach them.

### The guide and the CHANGELOG carried a migration from an `eval` key no project could write (RESOLVED, 2026-09-03)

- **Where:** `../../input_api.md`, *"Migration from the legacy globals"* (two rows) and
  `../../../CHANGELOG.md`, the closed-config-table bullet (*"the retired `eval` and `result`
  keys"*).
- **State:** neither was ever a key of `compy.input.show` or `configure`. **No commit made one** —
  `git log -S"'eval'"` and `-S"'result'"` over `consoleController.lua` are both empty — and at the
  PR base the evaluator was chosen by *which global you called* (`input(InputEvalLua, prompt,
  init)`), never passed in: no example writes `eval =`, and the config table a project could reach
  did not exist yet. The names are **internal**, from the pre-feature implementation and the design
  discussion — the evaluator object, and `input_ref` passed as *"the `result`"* in the feature's
  design-phase decision notes — restated in two project-facing documents as though they had been
  project keys. A migration row for a shape nobody could have written is worse than silence: it
  tells a reader they may have used it.
- **Owner's question is what settled it** (2026-09-03): *"I do not think it was used and not sure
  where it came from. Can we check if it was in the original requirements or grew spontaneously?"*
  **It grew spontaneously.** The feature's frozen design specification — ratified before
  implementation, and part of the working tree that does not ship — names `validator` /
  `highlighter` as the project-facing configuration and never an `eval` key, and its own migration
  table maps `input_text(prompt, init)` to `validator`, not to an evaluator.
- **Resolution.** Both rows dropped from the guide; the clause dropped from the CHANGELOG. The
  raise itself is unaffected and undocumented on purpose — the config table is **closed**, so `eval`
  raises like any other unknown key, without being advertised as a retired one.
- **What was checked and correctly stays:** the `| result = ... |` row in the same table. `result`
  is not a config key either, but it *was* project-visible — `user_input()` and `input_text()`
  returned `input_ref` and a project polled it (`turtle/main.lua:51` at base, `r =
  input_text("TURTLE")`). That row migrates from something real, and the entry above it is exactly
  the reason to check each row rather than sweep the table. The caution paragraph naming the
  evaluator globals stays too: those are real globals, and the row above it mentions
  `LuaHighlighter`, so a porting reader can plausibly reach for one.
- **Provenance: introduced in this branch.** Both documents are the branch's own — there is no
  `CHANGELOG.md` and no `doc/input_api.md` at `3256aac`.

### A project cannot read the widget's content except at submit (RESOLVED, 2026-09-03)

**Filed as `T-CONTENT-READ`.** Everything down to **Resolution** is the filing as written.

- **Where:** the `compy.input` surface — `consoleController.lua`, `build_widget_api`. It exposes
  `show`, `hide`, `is_shown`, `get_cursor`, `set_cursor`, `set_text`, `clear` and `configure`, and
  **no reader**. Content reaches project code only through `on_text_entered` and `after_submit`,
  both inside `UserInputController:submit_flow` (`userInputController.lua`); `cancel_flow` delivers
  nothing.
- **What is owed:** `compy.input.get_text()`, read-only, symmetrical with `get_cursor` — `nil`
  while hidden rather than a warning, because a read of *"nothing to report"* is not a refused
  mutation, the rule `get_cursor` already follows (`../internals/user_input.md`, *"Cursor
  manipulation and \"reset\""*). It is an **addition to the public surface**, so it owes its guide
  entry and a CHANGELOG line with the function itself, and `doc/input_api.md`'s `hide()` section
  currently discloses the gap and stops being true when this lands.
- **Why it is an entry:** a **self-describing gap in a shipped surface** — no decision produced it,
  and the decision it bears on (`../decisions/input.md`, **D-CFG-BOUNDARY**) rests on it being
  small. That ruling retired the ratified requirement that content survive `hide` → `show`, on the
  ground that a project which ever needs it can keep the content itself. **That fallback covers the
  cursor and not the text:** `get_cursor()` exists, so the caret round-trips and the content does
  not. The ruling's own evidence is unaffected — the two `hide()` call sites in the tree
  (`maze_main.lua:126`, `draw_main.lua:233`) both abandon the widget for a menu and *want* the
  clearing — so the gap is in the fallback offered as consolation, not in the decision.
- **Why ACTIVE, and it was BACKLOG until 2026-09-03.** Filed 2026-09-02 as *"PROPOSAL: a read-only
  content getter — the half of the save-it-yourself fallback that does not exist"*, unslugged and
  explicitly not a commitment, on the reasoning that no consumer had asked. The delivery
  revalidation then found the guide instructing an author to *"keep it yourself"* — advice the
  surface does not permit — and escalated whether the release closes the gap or documents it. **The
  owner ruled it release scope** (2026-09-03): *"write it as active technical debt to be resolved
  before release; disclose the gap but mark it as defect fixable with getter until ruled
  otherwise."* So the disclosure in the guide stands as the interim state and this is the fix.
- **The consumer is not the hide/show case** (owner, 2026-09-02). Today a project learns the
  content only at **submit** — that one moment is the entire read surface. A getter is what it
  needs to read at a moment of *its own* choosing: **on a timeout** (take whatever has been typed
  when the clock runs out), or **from a process the project launched itself**, e.g. off a hotkey,
  that wants the current text without making the user submit first. That is a more ordinary shape
  than restoring a draft across a hide, and sizing this from the hide/show framing under-prices it.
- **And explicitly not the alternative.** Restoring preservation across `hide` → `show` is a
  content-**lifetime** rule that every call seating content would have to agree with; a getter is
  one function that adds no rule. This is paid as the getter.
- **It is a class, not an instance — three earlier mentions, none of them an entry.** The absence is
  cited as a *supporting fact* inside `set_text`'s list branch does not split embedded newlines
  (*"nothing could read it back … so there is no set/get round-trip"*), inside the `oneshot` →
  `auto_hide` entry (*"nothing could read that draft back first"*, an entry `LEDGER-02` is scheduled
  to vacuum), and in the roadmap's `BUG-02-01` row. Three unrelated routes reached the same missing
  function and each treated it as background.
- **Roadmap:** `FEAT-03`.

- **Resolution.** `compy.input.get_text()` shipped the same day it was filed, `FEAT-03`. Five
  breaking tests first, each seen to fail with *"attempt to call field 'get_text' (a nil value)"*;
  suite 1050 → **1055**. It answers **one string** with `\n` between lines — `on_text_entered`'s
  spelling, and the one `set_text` takes back unchanged, so it round-trips without naming a type the
  guide does not have and hands a project no internal object (`after_submit`'s `InputText` was the
  alternative and was declined for that reason). `''` when the widget is shown and empty, `nil` while
  hidden, silently: the pair lets a project tell *nothing typed* from *nothing to report*. Documented
  in `../../input_api.md` (the surface list, *"Live changes"*, and the `hide()` section, which now
  carries the worked save-and-restore example instead of advice a project could not follow) and in
  `../internals/user_input.md`; `Added` line in `CHANGELOG.md`. **The three restatements of the
  absence were swept with it** — `../decisions/input.md`'s `D-CFG-BOUNDARY`, which now describes the
  whole fallback rather than half of one, this file's `set_text` list-branch entry, and the
  roadmap's `BUG-02-01` cell; the two register sites are past-tensed rather than deleted, because
  each was true when its argument was made.

  **Owner, 2026-09-03:** the ship was premature — the ruling of
  record was *"write it as active technical debt"*, and the function landed
  the same sitting. It stayed in the surface as **experimental** and **liable
  to be withdrawn** unless something needed it; `doc/input_api.md` *"Live
  changes"* and the CHANGELOG `Added` line said so. Not reopened as ACTIVE: the
  code was there, the contract was not.

  **The condition was met and the qualifier is retracted (owner, 2026-09-03;
  executed at `DOC-01-07`, 2026-09-04).** The proposal block committed into
  `doc/input_api.md` asks for exactly this read — *"marked 'experimental until
  somebody need it' which now happens"* — so `get_text()` is now an ordinary
  part of the surface and the guide and CHANGELOG no longer hedge it. **This
  paragraph is past-tensed rather than deleted**: it records a ruling that was
  true when it was made, and a reader meeting the retraction should be able to
  see what it retracted.

### The class diagrams show a model field that no longer exists (RESOLVED, 2026-09-02 — and the premise was half wrong)

**Filed as `T-MERMAID-MODEL`.** Everything down to **Resolution** is the filing as written.

- **Where:** `../mermaid/input.md`, `../mermaid/editor.md`, `../mermaid/classes.md` — the
  `InputModel` / `UserInputModel` class blocks.
- **State:** all three list `oneshot: boolean` as a model field. It is **gone**: at the PR base
  it was a constructor argument (`UserInputModel.new(cfg, eval, oneshot, custom_label)`)
  distinguishing the project's transient widget from the console's permanent one, and this feature
  removed it — `new(cfg, eval, custom_label)` today. The `auto_hide` key that replaced the
  *capability* lives on the **controller**, not the model, so the diagrams do not merely use an
  old name; they show a field on the wrong class. `custom_label`, a live field, is missing from
  the same blocks.
- **Why it stands:** the diagrams were never re-checked against the model after the input work.
  The drift is presumed wider than the one field — nobody has walked them — so the row is
  *verify all three against the current classes*, not *delete one line*.
- **Reader risk:** a diagram is what someone opens **before** reading code, and it carries no
  hedge. A field shown there reads as current in a way a stale sentence does not.
- **Resolution — `FIX-02-24`. The diagrams are marked historical, not corrected.**
  Was `T-MERMAID-MODEL`. Owner's call: *"if it's not the live doc and never was, maybe we should
  not update it, just mark (historical)?"* `doc/mermaid/README.md` carries the reasoning and each
  of the seven files got a one-line banner. No diagram content was rewritten.
- **The premise this entry was filed on does not survive the check.** It reads *"the model lost
  that constructor argument in this feature"* and *"the diagrams show a field on the wrong class
  rather than an old name"*. `InputModel` — the class carrying `oneshot` in `classes.md` and
  `input.md` — **did not exist at the PR base `3256aac` either**, together with
  `InterpreterModel`, `InterpreterController`, `InputController`, `InputView`, `InterpreterView`,
  `EvalBase` and `EditorInterpreter`. The diagrams are `aldum`'s — four added 2024-07-29 and
  three (`eval.md`, `input.md`, `scratch.md`) on 2024-12-18 as *"unfinished docs"* — and last
  meaningfully updated 2025-01-13. They were stale a year before this feature began.
- **Exactly one line of 32 class blocks was ours**, and it is deleted: `editor.md`'s `oneshot` on
  `UserInputModel`, a live class whose field did exist at base. A historical marker excuses
  inherited drift, not drift you caused. `custom_label`'s absence, `evaluator: EvalBase` and the
  `wrapped_error`/`error` conflation were each checked against base and are identical there.
- **Evidence:** a field-by-field audit of all seven files, 32 class blocks, run
  2026-09-02 for the diagram row. It also found the source-annotation drift now recorded in `general.md`, and that `eval.md`'s
  section headed *"Current"* describes a hierarchy never built while its *"Planned refactor"*
  section is closer to what shipped — which is the argument for keeping these files intact:
  they are the record of intent, and a correction pass would have deleted it.

### The guide never says a project's own keys stay live while the widget is shown (RESOLVED, 2026-09-02)

**Filed as `T-GUARD-LIVE`.** Everything down to **Resolution** is the filing as written.

- **Where:** `../input_api.md` — the `is_shown` paragraph, and *"Why the
  widget sits at tier 3"*.
- **State:** the guide documents the **mechanism** (three consumers, tried in
  order, the shown widget always consumes at tier 3) and one **case** —
  guarding the trigger key so a later press does not re-show the widget. It
  never states the consequence that falls out of the two: while the widget is
  shown, a project's *unrelated* keys are still live, because tier 2 runs
  above it. An unguarded native handler acts on the keys the user is typing —
  a space toggles a mode, a capital `R` moves the world — and the event still
  reaches the widget, so nothing looks wrong from either side. **The remedy —
  an early return on `is_shown()` covering the whole handler — is never named
  either**, though the suite pins it as the idiom
  (`tests/input/input_widget_control_spec.lua`, *"the guard the ruling asks an
  example to write"*).
- **What is NOT missing, corrected 2026-08-30:** an earlier variant of this entry
  claimed the guide never says a framework reservation is beyond a project's
  reach. It does — *"Combos the framework keeps"* says a reservation is
  answered before the project's route exists and cannot be overridden, and
  tables `ctrl+pause` with the rest. The entry is narrower than first written:
  what is missing is the *consequence for a shown widget*, not the
  reservation rule.
- **Why it stands:** `turtle` shipped unguarded for months (`T-TURTLE-DUP`),
  and a reader of the guide alone would not have known to write the guard that
  fixed it.
- **Resolution — `FIX-02-23`, and it is prose.** Was `T-GUARD-LIVE`.
  `../input_api.md`'s `is_shown` paragraph now states the consequence (hooks sit
  above the widget, so an unguarded handler acts on the user's typing while the
  widget is shown), names the remedy (an early return on `is_shown()` covering
  the **whole** handler), and distinguishes it from the narrow guard on the key
  that shows the widget — two guards, two jobs.
- **The reassurance is pointed at rather than restated**, as this entry's own
  2026-08-30 correction asked: *"Combos the framework keeps"* already says a
  reservation is answered before the project's route exists.
- **One mechanism error was caught while writing this and is worth keeping.** The
  first variant said the platform's combos survive a blanket guard because they
  never reach the project's handler. It is the other way round: a reservation
  **acts and passes the key on**, never consuming, so what survives the guard is
  the platform's action and not the project's binding. The guide uses
  `ctrl+escape` as the example because it is the one reservation marked
  *"always"* rather than development-only.

### The set of accepted config keys has no single home (RESOLVED, 2026-09-02)

**Filed as `T-KEYSET-SPLIT`.** Everything down to **Resolution** is the filing as
written, present tense and all — *"No such test exists"* was true when it was
written and is the record of why the work was scheduled. The Resolution bullets
are what happened.

- **Where:** `consoleController.lua` decides what `show` / `configure` **accept**
  (`CALLBACK_KEYS`, `WIDGET_KEYS`, and the `CONFIGURE_KEYS` / `SHOW_KEYS` sets
  built from them); `userInputController.lua` decides what they **apply**
  (`CONFIG_CALLBACKS` and the named branches at the top of `configure_core`).
  Nothing ties the two sides together.
- **State — one real duplication and one weaker coupling, and they are not the
  same defect.** `CALLBACK_KEYS` and `CONFIG_CALLBACKS` are two lists holding
  the same four strings — `validator`, `on_text_entered`, `on_limit_reached`,
  `highlighter` — maintained separately, each for its own job: the first backs
  the sticky `state.callbacks` store the surface merges from
  (`merge_callback_keys`), the second assigns onto the widget's own
  `self.callbacks`. `WIDGET_KEYS` against `configure_core` is **membership
  duplication, not list duplication**: `prompt` and `auto_hide` reach
  *different destinations* (`model.custom_label`, `self.auto_hide`), so there is
  no list to share — only the fact that both calls take them.
- **Why it matters: the failure is silent and one-directional.** A key added to
  the accept side alone is taken by the surface and ignored by the widget, with
  no raise and no warning — the config table is strictly validated against a set
  that does not know what the widget implements. That is a drift source, and it
  is the same family as `FIX-02-08`/`-09`: one fact stated twice, with nothing
  reconciling the statements.
- **It has already drifted in the way that counts** (2026-08-31). Not the
  values, which have never diverged, but the *shape*: `FEAT-02` had to add an
  entry on each side for `auto_hide`, and the entry that should have caught it
  said only *"revisit when either list changes"* — a trigger that fires only if
  someone remembers to look.
- **The fix is a test, not a refactor** — deliberately, and the refactor is
  named here as the thing not being done. Unifying the lists means one module
  importing the other's across the surface/widget boundary the architecture
  keeps separate, which is a larger change than the defect and reads worse on
  review than the duplication does. Instead: **assert that every key the surface
  accepts is a key the widget applies.** No such test exists — each key is
  covered behaviourally and individually, and nothing asserts the *set* is
  closed. A few lines, no behaviour change, and it turns an invisible coupling
  into an executable one.
- **Resolution — `FIX-02-25`, and it is a test.** Was `T-KEYSET-SPLIT`.
  `tests/input/input_config_key_agreement_spec.lua` **reads the real accepted
  set out of the surface** — `show` → `api_show` → `SHOW_KEYS`, and the
  `configure` equivalent, by upvalue and by name — and requires every member
  to carry a proof there that the key reaches the widget. A third hand-written
  copy of the list was rejected for the reason this entry exists: it cannot
  fail on a key it does not know about, which is the whole defect.
- **Mutation-tested in both directions.** Adding `'ghost'` to `WIDGET_KEYS`
  with no `configure_core` branch fails both cases naming the key; renaming
  `SHOW_KEYS` fails with *"upvalue SHOW_KEYS is gone; fix this reader"*
  instead of silently checking an empty set. That second one is why the reader
  asserts rather than returning nil.
- **No production defect was found.** The two sides agree today, so nothing was
  changed: the row allowed for a divergence and there is none. What is fixed is
  that the next divergence cannot be silent.
- **The refactor named here is still not done, deliberately** — unifying the
  lists remains the larger change this entry rejected.

### A citation edit left half a sentence asserting the opposite of the statement it cites (RESOLVED, 2026-09-02)

- **Where:** `tests/input/input_widget_callbacks_spec.lua`, the `auto_hide` block's
  raise case.
- **The defect:** `d0f4e66c` re-pointed *"D-AUTO-HIDE, ruled edge 4 -- the one REVERSED
  from the entry's own recommendation"* onto the numbered statement, and stopped at the
  clause boundary. What stood afterwards was *"statement 5 -- the widget survives a
  raise; entry's own recommendation."* — a fragment reading as a claim that statement 5
  **is** the entry's recommendation, when the entry's recommendation was the opposite
  and its reversal is exactly the churn `D-AUTO-HIDE`'s rewrite retired. Silent: the
  comment is prose, the case passes either way.
- **Resolution:** the fragment removed and the block rewrapped; two neighbouring blocks
  left ragged by the same substitution were rewrapped with it, wording untouched.
- **The rule it fails is one the same session wrote:** *prove a mechanical edit, do not
  eyeball it.* The 68 reflowed comment blocks were proved word-for-word; these thirteen
  citation edits were read. **A substitution that shortens a sentence must be read to the
  end of the sentence**, not to the end of the token it replaced.

- **Where:** `../../input_api.md`, *"The input widget — showing it and changing it"*.
- **The defect:** *"To close it after a submit, make that choice explicit"* followed by
  `after_submit = hide`, with *"Or pass `auto_hide` and let `show` do it"* trailing it. Nothing
  false — but `FEAT-01`/`FEAT-02` made `auto_hide` the recommended form, and a reader following the
  guide's own ordering writes the superseded idiom. **A recommendation drifts by staying still
  while the surface moves**, which is why no grep for a wrong statement would have found it.
- **Resolution:** the paragraph leads with `auto_hide` and keeps the hand-written form as what the
  key *does* — it is still the anchor the *"Asking one question"* section uses to predict the
  edges, so it could not simply be deleted.
- **Found by the owner reading the guide**, not by any planned row: `FEAT-01-05` and `FEAT-02-04`
  each documented the new key and neither re-read what the old idiom's own paragraph now implied.
  **Adding a surface does not re-rank the advice around it** — worth carrying into `DOC-01`.

### The deviation justifications live only in the PR description — NOT DEBT, the premise was false (2026-09-01)

- **Was `T-DEVIATION-WHY`**, filed and refuted the same day.
- **The claim:** the PR description's *"Ratified deviations"* table holds six technical
  justifications that die with the feature's working tree, while the decisions they belong to
  argue why today's shape is right and never say what it replaced.
- **The second half is false, and it was checkable.** Every one of the five outstanding
  arguments is already in its own decision, in more depth than the table's one-sentence cell:
  `D-ROUTE-LIFETIME` marks itself SUPERSEDED IN PART, quotes the superseded claim verbatim and
  records the base check that killed it; `D-NO-LOG-NOISE` has a *"What this settles"* naming the
  design's proposed debug log and a *"Why the log is declined"*; `D-HOOKS-SEEDED` argues the
  one-time seed against a precedence rule by name; `D-EDIT-LIFECYCLE` argues the framework tier was
  covering a leak; `D-ONE-LIFETIME` already carried the base-check provenance. The table
  **summarises** the ledger; it is not a unique home for anything.
- **And the first half wanted the wrong thing anyway** (owner, 2026-09-01): *"we do not make
  archaeology"* — `../../../agents/rules/ledgers.md`, *"What a decision records about its own
  past"*. Lifting more reversal narration in is the opposite of what the corpus needs; the real
  work is `T-ARGUES-INTERIM`, which takes it out.
- **Why it is recorded rather than deleted:** a defect refuted at its premise gets re-filed by the
  next reader who notices the same surface. The surface is real — a reviewer's table and a ledger
  do overlap — and the reason it is not a defect is the part worth keeping.
- **Cost of the error:** one paragraph written into `D-ONE-LIFETIME` (`e9a3501a`) and removed
  again (`cd1264da`), and a roadmap row filed and withdrawn.

### The callable config keys are unchecked (WONTFIX by owner ruling, 2026-09-01 — the premise was wrong)

- **Resolution: `wontfix`, by owner ruling, and the entry's framing was wrong
  before its facts were.** *"I'd just not enroll too much input checking
  ceremony beyond necessary. its edu project, not space rocket navigation."*
- **What the entry got wrong:** it read the checked pair as *one class closed
  one key at a time* — `BUG-01-08` for `cursor`, `BUG-02-02` for `text`, "still
  open on the remaining keys". That is patch archaeology, and it is not what
  happened. **`text` and `cursor` are the user's content; every other key is
  project-owned**, and that line is ratified as **D-CFG-BOUNDARY**, *"the
  configuration boundary: the user's content is `show`'s alone"* — the same
  split that decides which keys `configure` may touch and which reset on each
  `show`. The boundary checks the content class **completely**. There is no
  half-closed class.
- **And the two classes deserve different treatment, which is the owner's
  argument:** *"pass wrong text and you confuse the user, pass wrong validator
  and you confuse yourself."* A bad `text` reaches a person who did not write
  it and cannot fix it, so it is refused at the door. A bad `validator` reaches
  the project author, in their own code, and the raise names `validator` — the
  very key they set. That is self-diagnosing, which is why *loud and late* is
  an acceptable answer here and *silent* was not.
- **Facts, kept because they are still true:** `show{validator = 42}` raises
  `attempt to call local 'validator' (a number value)` at submit
  (`userInputController.lua:417`, and the same for `cb` at `:437`); the same
  holds for `highlighter`, `on_text_entered` and `on_limit_reached`;
  `prompt = 42` is assigned to `custom_label` unchecked and flows into the draw
  path where the annotation promises `string?`. Nothing in-tree passes a
  non-callable and every shipped example passes functions.
- **No guide sentence either.** Documenting *"these keys are not checked"*
  would be the same ceremony in prose, and it would teach a distinction the
  reader does not need: the guide already frames content and configuration as
  different things.
- **Provenance:** `#77`'s own surface. Found by the second cold peer review of
  `BUG-02-02`, 2026-09-01; re-raised as a delivery question by the
  revalidation that followed, the same day, and ruled the same day.

### Six line citations into `userInputModel.lua` were stale on arrival (RESOLVED, 2026-09-01)

- **Resolution:** all six replaced with **function names**, which do not
  drift — `UserInputModel:insert_text_line`, `:line_feed`, `:set_cursor`,
  `:_set_text_line`, `:history_back` and `:history_fwd`, plus the Ctrl+D site
  named as the `modify` handler inside `_normal_mode_keys`.
- **What was wrong, and the mechanism** (corrected in the pass that filed it —
  the first version of this entry named the wrong cause and the wrong count):
  commit `e3484987` **trimmed the `set_text` doc comment from six lines to
  three** at `:157`, its own finding F7. Everything below moved **up by 3**,
  and the citations it wrote or carried in that same commit were numbered
  against the pre-trim file. Affected: `:224`, `:263`, `:546`, `:196-198` in
  two entries, and `:475`/`:487` in a third (the `set_text` caller
  enumeration). The real lines are `221`, `260`, `543`, `193-195`, `472` and
  `484`. None ever resolved; they pointed a reader at `end`, at a blank line,
  at `--- @private`, and at `self:clear_input()` in place of the history
  restore it claimed to cite.
- **Why it was worth fixing rather than filing:** a citation that does not
  resolve *reads as authoritative* — the standing objection in
  `agents/validation.md`, *"Comment References"*. And the rule was already
  ours: this same file's `set_cursor_pos` line citation had been replaced with
  a function name **one day earlier**, giving this reason verbatim.
- **A line citation is not verified by reading a range around it.** `:475` was
  first checked by printing `472..478`, seeing `set_text` in the output, and
  calling it correct; it is `end`, and `set_text` is at `472`. Resolve the
  exact line or resolve nothing.
- **Scope checked, not assumed:** the corpus's citations into
  `editorController.lua` (`:336`, `:602`, and the census's `:590-604`,
  `:628-633`) and `userInputController.lua:316` resolve, being in files that
  commit did not touch. The wider population is **not** clean — see `general.md`,
  *"Line citations across the persistent corpus are unverified, and a fifth of
  the checkable ones do not resolve"*.
- **Provenance: ours**, 2026-09-01, all six traceable to one commit. Found by
  the delivery revalidation that followed and fixed on the owner's go.

### The programmatic-cursor census omitted the one writer on a hot path (RESOLVED, 2026-09-01)

- **Resolution:** `internals/user_input.md`, *"Cursor access exists at three
  layers"*, now carries the field-writers as a **second, explicitly separate
  population** — `_update_cursor`, `_advance_cursor`, `insert_text_line` — with
  the note that the last runs on every Shift+Enter and on Ctrl+D, and a
  cross-reference to *"`_update_cursor` measures the column on the wrong line"*.
  The census's own parenthesis was widened from *"an arrow/Home/End keypress"*
  to *"a cursor-movement keypress"*, which is what it always meant.
- **What was wrong:** the census said four programmatic call sites and
  `insert_text_line` was not among them, though it writes `self.cursor.l`
  unvalidated and its exclusion was not covered by the parenthesis. The corpus
  answered *"what moves the cursor?"* two ways, 90 lines apart in two files.
- **Why it was worth fixing rather than filing:** the census exists **because a
  sweep consults it instead of re-deriving** — the argument its previous
  correction was made on (`ba09edcc`, which added `_apply_eval`
  after a sweep had missed it). It then missed a second site the same way, and
  that site is the only cursor writer live on ordinary editing. The two lists
  are now stated as different kinds — *callers of the cursor API* against
  *writers of the field* — because conflating them is what let a site fall
  between them.
- **Provenance: ours.** The census paragraph is `#77`'s writing; the omitted
  fact came from `#77`'s own second cold peer review, 2026-09-01, and was
  recorded in this register without anyone returning to the census. Found by
  the delivery revalidation the same day and fixed on the owner's go.

### `set_text` answered a malformed content element three different ways (RESOLVED, 2026-09-01)

- **Resolution:** fixed at `BUG-02-02` — the step the owner added to `BUG-02`'s
  scope on the ground that *"it's our own interim defect which this feature
  introduced, and it does not go into release"*. `checked_text` sits beside
  `checked_cursor` at the project boundary (`consoleController.lua`) and refuses
  any `text` that is not a string or a list of strings, raising
  `compy.input.set_text: text must be a string or a list of line strings` — or
  the same message under `compy.input.show` — at the same level-4 depth. The
  surface's `set_text` was lifted into an `api_set_text` for that depth rule, as
  `api_set_cursor` already was.
- **The three behaviours it replaced**, all silent or unhelpful, none announced:
  `{'a', 42}` **silently dropped** the number, `{42}` **wiped the content** to
  `{''}`, and `{'a', true}` raised `bad argument #1 to 'len'` from inside
  `sanitize_utf8` — naming a function the project author never called.
- **Provenance, and why it was fixed rather than filed.** The raw raise is
  pre-existing; **the drop and the wipe were this feature's own**, introduced
  hours earlier the same day by `BUG-02-01`'s fix, when `string.lines` began
  type-checking elements that `InputText` had previously stored as-is. An
  interim regression that never reached a release is not debt to weigh — it is
  work to finish, which is the owner's ruling above.
- **The rule it settles is D-CONTENT-NORM's boundary: normalise representation,
  refuse structure.** A string against a list, an embedded newline, an invalid
  byte — one value spelled differently, and normalised silently. A number,
  boolean or table where a line belongs is not text at all. Coercing it would be
  tolerance producing a lie: the contract is documented and closed, so a value
  outside it can only be a mistake, and rendering `42` as a visible line hides
  that behind content which looks deliberate. **Corrected 2026-09-01 by the
  second cold review:** this entry first argued from `{'a', 42}` matching
  `UserInputModel:insert_text_line(text, li)`'s arguments, and cited
  `pong/main.lua:104` as a project converting numbers itself. Both are wrong —
  `insert_text_line` is a model method a sandboxed project can neither see nor
  call, and that `pong` line calls pong's **own** `set_text(name, str)`
  (`:95`), a `gfx.newText` wrapper unrelated to `compy.input`. **No in-tree
  project passes a number to `compy.input.set_text` in either direction**, and
  saying that plainly is stronger than either citation was.
- **Precedent followed, not invented:** `BUG-01-08` settled this class for
  `cursor` — a malformed value on the public surface earns one message naming
  the call and the expected shape, never a raw Lua error from inside the
  framework and never a silent repair.
- **Where:** `src/controller/consoleController.lua` (`checked_text`,
  `api_set_text`, `api_show`, `is_line_list`),
  `tests/input/input_cursor_text_spec.lua` (*"refuses a non-string element"*),
  `../../input_api.md` (*"Live changes"*), `../decisions/input.md` (D-CONTENT-NORM).
- **The first fix was incomplete, and the second cold review caught it**
  (2026-09-01). `checked_text` walked the list with `ipairs`, which stops at the
  first hole and never sees a non-integer key, so `{[1]='a', [3]=42}` was
  accepted and dropped the number, and `{foo = 42}` was accepted and wiped the
  content — **both silent symptoms, one spelling further out**, through `show`
  as well as `set_text`. A hole is not exotic: a `pairs` loop over a sparse
  source builds one in a line of ordinary project code. `is_line_list` now
  counts every key and requires `1..n` to be strings, which is what *"a list of
  line strings"* implies and what an `ipairs` prefix-test never checked.
- **`normalized_lines` deliberately keeps its `ipairs` walk.** The boundary
  refuses structure and the model normalises representation (D-CONTENT-NORM); the
  only callers reaching the model without passing the boundary are
  framework-internal (editor, history) and pass dense lists. Duplicating the
  validation into the model would blur that split.
- **A second behaviour changed with the lift and was not noticed at the time:**
  `show{text = false}` went from *"the previous content survives"* to *"the
  field opens empty"*, because `checked_text` normalises falsy to `nil` and
  `reset_content` branches on `cfg.text == nil`. The new behaviour is the
  correct one — D-CFG-BOUNDARY statement 1 makes an absent `text` an empty field
  and statement 3 makes `false` the uniform unset — so a second defect closed
  by accident. It is now documented in `../../input_api.md` and pinned by a
  test, having shipped as neither.

### `set_text`'s list branch does not split embedded newlines (RESOLVED, 2026-09-01)

- **Resolution:** fixed at `BUG-02-01`. The `type(text) == 'table'` branch hands
  its sanitised list to `string.lines`, which is polymorphic over
  `string | string[]` and delegates a list to `string.split_array` — so each
  element splits and empty elements are preserved. `set_text("a\nb")`,
  `set_text({"a\nb"})` and `set_text({"a","b"})` now produce the same two lines
  and the same cursor. One call; the two branches converge on the function the
  string branch already used instead of stating the rule twice.
- **Never slugged, and correctly so.** A slug is the commitment to fix and is
  earned when an entry becomes `ACTIVE`; this one was ruled and fixed in the
  same session, so it went `BACKLOG` → `RETIRED` without passing through.
- **The rule behind it is the owner's** (2026-09-01) and is now ratified as
  **D-CONTENT-NORM**, `../decisions/input.md`. It is the same rule the UTF-8
  sanitisation on this path already served: **the cursor addresses content as
  `(line, column)`, so content that is not normalised makes that address
  ambiguous.** Invalid bytes leave a column's *length* undefined; a newline
  inside a line leaves its *position* undefined — the caret could sit past a
  line terminator. Neither normalisation is a convenience, and they are now
  symmetric across both spellings. Written up in
  `../internals/user_input.md`, *"Multiline input"*, and stated for a project
  author in `../../input_api.md`, *"Live changes"*.
- **The two branches are now one path preceded by a normalisation step** (owner,
  2026-09-01), which is D-CONTENT-NORM's structural half: per-spelling branches
  that each decide what to normalise are what let UTF-8 and newlines drift onto
  different rules in the first place. `normalized_lines` returns the lines,
  `set_text` stores them, and there is one place left where either could drift.
- **The defect it closed:** the two branches of one function disagreed about
  what a newline means. `set_text({"a\nb"})` yielded **one** line holding a raw
  newline, which the model counted as an ordinary character — three characters
  long, caret positions `1..4`.
- **What was observable, established at the weighing** — more than the entry
  first claimed. The content round-trips through `string.unlines`, so
  `on_text_entered` could not tell the two apart; but `after_submit` receives
  the line list itself (D-PAYLOAD-SPLIT's payload split), so the spellings handed a
  project `{"a","b"}` versus `{"a\nb"}`. The validator runs per line and would
  have measured the concatenation and named the wrong line. And the rendering —
  recorded as *"needs a display"* — was read out of the draw code instead: both
  paths reach `gfx.print`, which honours the newline, and they corrupt it
  **differently**. `ViewUtils.write_line` draws the tail one row down at `x = 0`
  over its neighbour while the model still believes it drew one row, so the
  cursor, the visible window and the scroll arithmetic all disagree with the
  screen; the highlighted path prints character by character at explicit
  coordinates, so the newline draws nothing and reads as a blank column. Not
  display-verified — read from the draw code, which is why it was fixed rather
  than left described.
- **Why it was still narrow:** no in-tree caller could reach it. The three
  **project-facing** ones (`maze/core_editor.lua`, `tixy/main.lua` twice) pass
  either a raw string or `string.lines(…)`, and `string.lines` never emits an
  element containing a newline. **The enumeration was incomplete as first
  written** (cold peer review, 2026-09-01): the model's `set_text` is also
  called from `editorController.lua:336` and `:602`, from
  `UserInputModel:history_back` and `:history_fwd` (history restore) and from
  `userInputController.lua:316` (`show`'s `cfg.text`). All five were checked and the conclusion survives — `pprint`
  returns `string.lines(src)`, and buffer lines and history entries are already
  split — but "all three" would have let a reader think they did not exist. Nor could a user: `add_text` splits, and the paste path pre-joins
  with `string.unlines` at the controller before the model sees it. A project
  had to hand-build such a list, and **nothing could read it back** — the
  `compy.input` surface had no content getter when this landed, so there was
  no set/get round-trip the normalisation could break. (`get_text` arrived
  2026-09-03 and answers the normalised content, so the round-trip that exists
  now agrees with what this fix established rather than contradicting it.)
- **Provenance: pre-existing.** At the PR base `3256aac` the table branch is
  `InputText(text)` — no split, no sanitise. This feature fixed the *string*
  half (`T-MULTILINE-STR`) and thereby made the two halves visibly disagree; it
  did not introduce the branch. Two refinements found at the weighing: the
  per-element sanitise pass **is** ours, so the branch carrying the split is
  code this feature wrote, and the asymmetry — UTF-8 on both spellings,
  newlines on one — was its own choice rather than an inheritance. Found by the
  cold peer review of the fix that exposed it.
- **Where:** `src/model/input/userInputModel.lua` (`set_text`),
  `tests/input/user_input_model_spec.lua` (*"embedded newlines"*, three cases),
  `tests/input/input_cursor_text_spec.lua` (the surface case, beside its string
  twin), `../../input_api.md`, `../internals/user_input.md`, `../../../CHANGELOG.md`.

### `set_text`'s two branches disagreed about the cursor, and the call was dead (RESOLVED, 2026-09-01)

- **Resolution:** fixed at `BUG-02-01`, in the same unit as the entry above and
  on the owner's direction — *"either discard or cursor movement should be
  deleted, and in either case both paths should be unified"*. The call is
  **deleted** and the two branches are now **one path preceded by a
  normalisation step** (`normalized_lines`). Ratified as **D-CONTENT-NORM**,
  `../decisions/input.md`, closing section.
- **Registered here rather than left in a session track** (owner, 2026-09-01):
  a finding parked in a track dies with the session, so it goes in the ledger
  even when it is fixed the same day.
- **The defect:** `UserInputModel:set_text`'s string branch called
  `_update_cursor(true)` when `keep_cursor` was falsy; the list branch never
  did. The call was **inert on this path**, so the asymmetry was invisible:
  `_update_cursor` sets `cursor.c` from the line at the *old* cursor index in
  the *new* text and `cursor.l` to `#t` — a column from one line and a line
  from another, incoherent by construction — and `set_text` then runs
  `init_visible`, which replaces the whole `VisibleContent`, and `jump_end`,
  which overwrites both cursor fields with coherent ones. Every effect,
  including the visible-range move `text_change`'s `_follow_cursor` makes from
  it, is discarded before the call returns to its caller.
- **It never worked.** The commit that introduced the call (`472c6bba`, the
  transitional UserInput triplet) already ended `set_text` with an
  unconditional `jump_end()`. There is no revision in which it had an effect,
  which is why the branch lacking it behaved identically and the disagreement
  survived unnoticed. Shape copied from `_set_text_line`, where the call **is**
  live, into a function that already seated the cursor.
- **Mutation-tested before deletion, not reasoned about only:** five cases
  chosen to expose it — shorter replacement with the caret parked past the new
  end, longer replacement, and a 20-line buffer collapsing to one line, each in
  both spellings — produce byte-identical cursor and visible-range snapshots
  with the call and without it, and the suite is green either way. The
  **behaviour** is now pinned by tests (*"both land at the end of shorter
  content"*); **the deletion is not, and cannot be** — an inert call is
  indistinguishable from its absence, so restoring it leaves the suite fully
  green. Reintroduction is not test-detectable, which is worth knowing before
  anyone reads those tests as a guard against it (cold peer review, 2026-09-01).
- **`_update_cursor` itself stays, and only the `set_text` call site was
  deleted. Corrected 2026-09-01, same day:** this entry first said
  `_set_text_line` and `clear_input` "both call it live", which is wrong about
  the first. `_set_text_line` guards the call with `if not keep_cursor`, and
  **all seven of its callers pass `true`** — so that call is unreachable, and
  `clear_input` is the only reachable one. The correction matters because the
  claim would tell a later reader that path is exercised when nothing exercises
  it. What the function owes beyond that is its own entry, below.
- **Provenance: pre-existing**, inherited from the transitional triplet and
  present at the PR base in the same shape.
- **Where:** `src/model/input/userInputModel.lua` (`set_text`,
  `normalized_lines`), `tests/input/user_input_model_spec.lua`
  (*"embedded newlines"*).

### T-MAZE-NEUTRALIZE — `maze` neutralises two hook sites by clearing a flag, not by the widget guard (NOT DEBT, 2026-08-31)

- **Resolution: `wontfix`, by owner ruling — and the entry's premise was wrong.**
  The row opened by weighing rather than by fixing, and the weighing found
  nothing to weigh. No code changed in `maze`.
- **`ctrl_pressed` is maze's control-mode slot, not a neutralisation idiom.**
  `controls.lua` defines the modes and each one assigns it — `keys()` sets
  `handle_key`, `plan()` sets `plan_key` with a matching `ctrl_update`. Clearing
  it says *no control mode is active*, which is a statement about the game.
- **The contrast the entry drew inverts.** It read `core_editor.lua` as the file
  doing it the other way; `arm_editor` there is itself `ctrl_pressed = nil`. And
  that file's `is_shown` call is a **show-vs-configure** branch — *is there a
  field to reconfigure?* — not a double-handling guard, which is a different
  shape from `turtle`'s whole-handler early return.
- **Double-handling is prevented on the paths that occur — but by level
  ordering, not by structure.** The weighing first claimed "by construction";
  the sprint's peer review falsified that and it is corrected here. The hook
  fires while the widget is shown, finds `SYSTEM_KEYS[k]` nil — that table is
  only ever populated by member name — and `ctrl_pressed` nil, so the keystroke
  reaches the widget alone. **But `jump_level` → `start_level` → `cur_controls()`
  re-arms `ctrl_pressed` and hides nothing** (`compy.input.hide()` appears only
  in the two menu exits), so a jump from an editor level to a `controls = keys`
  level would leave both live. **Reported in maze's own `ISSUES.md`, not fixed** —
  it is that repo's defect and that repo's readers need to find it, where this
  ledger is ephemeral to them.
- **The shape is the one the guide advises** (owner, 2026-08-31): read the
  hardware early and turn the result into a deterministic variable the rest of
  the logic runs on — `../../input_api.md`, *"Perform hardware polling before
  complex processing"*. The only thing to say against it is that the variable
  is named after the keyboard where its role is mode selection (`special_mode`
  would say it) — **semantics and taste, explicitly not fixed**, in another
  repo's working code.
- **Where:** nothing changed. The decision not to rename was weighed when the
  fix landed and is recorded with it.

### T-BALLOON-LABEL — balloons keeps a shadow copy of the widget's label, re-pushed every cycle (RESOLVED, 2026-08-31)

- **Resolution:** fixed at `BUG-01-07`, in the **balloons repo** (a separate
  repo with its own remote, which opens its own PR alongside the platform one).
  `ui_messages.hint` and `ui_draw_hint` are gone; `ui_set_hint` writes straight
  through to the widget, with a comment carrying the reason the indirection
  existed.
- **Why it could go:** the copy had **no second reader** — it was written and
  read only inside the `ui_set_hint` → `ui_draw_hint` pair, so collapsing them
  loses no state. It existed because in the legacy era the label died with each
  `input_text()` call; with label stickiness ratified the widget owns the label
  and a prompt persists until replaced.
- **Three fossils went with it:** the `-- NOTE: won't work if there was no real
  input` comment (it described the flush-dependent redraw), `terminal_write`'s
  never-read `flushed` parameter, and the second argument passed to
  `ui_set_hint`, which takes one. The unused `SPLASH_HINT_START` seed went too;
  the constant stays, because the splash screen reads it directly.
- **Not runtime-verified:** balloons has no suite and needs a display. Desk-
  checked and parses; the manual smoke pass is where it is exercised.
- **A second defect was found here, raised, and then fixed on the owner's
  ruling.** `ui_draw_status` read `ui_messages.results`, which nothing ever sets
  — `ui_status_finalize` writes `ui_messages.result`, singular. It was reported
  rather than filed (`agents/development.md`: report non-blocking debt), and the
  owner ruled: *fix it if it is clearly a typo, delete it if it is clearly dead
  code.* It is the second, so the branch was **deleted** in the balloons repo.
- **Why deleting was right and repairing was not.** The two names are a
  self-consistent *pair* — `ui_status_reset` cleared `results`, `ui_draw_status`
  read it — so "repair the typo to `result`" would have changed nothing during
  play (`ui_status_finalize` sets the result immediately before the state
  becomes finished, where the splash renders instead of the status bar) and
  would have been a **regression across games** (`result` is never cleared, so
  game two's status bar would show game one's stats). Ask what the repaired code
  would *do* before repairing.

### T-CURSOR-BYTES — `set_cursor` clamps by byte offset; the boundary event measures characters (RESOLVED, 2026-08-31)

- **Resolution:** fixed at `BUG-01-05`. All three byte-bounded cursor clamps
  now count characters with `string.ulen`.
- **It was not an undecided design call.** The unit was already decided
  everywhere else: `jump_end`, `jump_line_end`, `is_at_limit`,
  `_update_cursor`, `cursor_left`/`right`, `cursor_vertical_move`, the
  mouse-to-cursor translation and the view's pixel math all count characters.
  Three clamps were the outlier, so the fix was to make them agree, not to pick
  a winner between two equal conventions.
- **The defect it closed:** on the six-character, twelve-byte `'привет'`,
  `compy.input.set_cursor(1, 10)` was accepted — the byte bound allows 13 —
  leaving the caret four positions past the end of the line and reporting 10
  back from `get_cursor()`.
- **Provenance, and it is mixed.** `UserInputModel:move_cursor`'s bound is
  PRE-EXISTING and unchanged at the PR base `3256aac`; its 18 internal callers
  all pass character values, so the gap was inert. `set_cursor_pos` and
  `_clamp_cursor_pos` are OURS — absent at base — and were written to copy the
  byte convention deliberately. They are what made the gap externally
  reachable. All three were fixed, because leaving the outlier would make our
  two differ from the function they were written to match.
- **The bound only narrows** (`ulen` ≤ `#`), and internal callers pass
  character values, so nothing that passed before is refused now.
- **Where:** `model/input/userInputModel.lua` (`move_cursor`,
  `_clamp_cursor_pos`), `controller/userInputController.lua`
  (`set_cursor_pos`), `tests/input/input_cursor_text_spec.lua`,
  `../../input_api.md` (*"Live changes"* — which had contradicted itself,
  calling `col` a caret position between characters and then ranging it over
  `1 .. #line + 1`).

### T-COMBO-CASE — `combo_string` does not normalise the case of a textinput token (RESOLVED, 2026-08-31)

- **Resolution:** fixed at `BUG-01-04`. `combo_string` (`controller.lua`) now
  lower-cases the trigger, so dispatch emits what registration stores.
  D-COMBO-TABLES already ratified the rule — "a project can register `['Ctrl+S']`
  and still match" — this only makes the dispatch half implement it.
- **The defect it closed:** registration canonicalises the whole combo
  (`key.lua`, `combo:lower()` inside `split_combo`), dispatch did not, so
  `shortcuts.textinput['Shift+I']` was stored as `shift+i` while typing `I`
  looked up `shift+I`. The slot was **unreachable**, not awkward: writable,
  never fireable, silent. `normalize_combo`'s own docstring asserted the
  agreement that did not hold.
- **Narrow by construction:** only textinput delivers a cased trigger.
  `keypressed`/`keyreleased` carry LÖVE key constants, already lower, and the
  reservation tables have no textinput channel; `'*'` lower-cases to itself.
- **It was OURS.** At the PR base `3256aac` `src/util/key.lua` is 53 lines with
  no combo machinery and `controller.lua` has neither `combo_string` nor
  `RESERVED`. This feature introduced **both halves** of the asymmetry — it is
  not inherited drift, which is the opposite of `T-MULTILINE-STR` above.
- **The limitation it makes explicit:** a shortcut cannot tell `I` from `i`.
  That was already true of every registration and is now true of dispatch;
  a project needing the distinction reads the character in `hooks.textinput`.
  Written down in `../../input_api.md`, *"Event hooks and shortcuts — when to
  use which"*.
- **Where:** `controller/controller.lua` (`combo_string`),
  `tests/input/input_combo_serialisation_spec.lua`,
  `tests/input/input_events_spec.lua`, `../../input_api.md`.

### T-MULTILINE-STR — `set_text` silently ignores a multi-line *string* (RESOLVED, 2026-08-31)

- **Resolution:** fixed at `BUG-01-09`. The string branch of
  `UserInputModel:set_text` now splits with `string.lines` and hands every line
  to `InputText`, which is where the table branch already handed its list. A
  single-line string yields a one-element list, so that path is unchanged.
  **The table branch did not itself split** — fixing this half is what made the
  two visibly disagree, and that is the entry above,
  *"`set_text`'s list branch does not split embedded newlines"*.
- **The defect it closed:** `self.entered` was assigned only when the string
  held one line, so a string with a newline matched no branch, nothing was
  written, and the previous session's content survived into the new one — with
  no warn and no raise. Reachable from `show{text = …}` and the live
  `compy.input.set_text`. **Corrected 2026-08-31** by the sprint's peer review:
  the fix commit's message also named `configure{text = …}`, which in fact
  **raises** — `text` is in `SHOW_ONLY_KEYS` (`consoleController.lua`) — and
  named `apply_config`, which no longer exists; the path is `api_show` →
  `open_widget` → `reset_content`. Both are wrong in the commit message, which
  cannot be amended, so the correction lives here, where the PR description
  will read it.
- **It was PRE-EXISTING, not ours.** The `#string.lines(text) == 1` guard is at
  the PR base `3256aac` in the same shape. What this feature added is the
  documented shape (`../../input_api.md`, *"The input widget — showing it and
  changing it"*: "a string or list of line strings") and the project-facing
  surface that reaches it — which is why it was fixed here rather than left
  described.
- **Where:** `model/input/userInputModel.lua` (`set_text`),
  `tests/input/input_widget_control_spec.lua`,
  `tests/input/input_cursor_text_spec.lua`, `../../../CHANGELOG.md` (*"Fixed"*).

### T-ONESHOT-SCOPE — the `show`-only `oneshot` becomes `auto_hide`, a widget property (RESOLVED, 2026-08-30)

- **Resolution:** built at `FEAT-02` on the owner's ruling, the same day the edge it
  amends was made. The key is **`auto_hide`**, it left `SHOW_ONLY_KEYS` for
  `configure_core`, and `show` and `configure` both set it, set-if-given, with
  `false` as the unset. It **persists until replaced**, like `validator`: it
  configures a *type of behaviour*, not one show/hide cycle, so it needs no
  clearing rule and no category of its own. No reader was added — a query earns
  its place when the framework can change the value, and nothing but the project
  writes this one.
- **The defect it closed:** disarming used to require `show{force}`, a full
  re-setup that clears the user's draft — and nothing could read that draft back
  first (no text getter on the surface; a project's `love` is a sandboxed clone,
  D-ONE-STATE-ASK). `configure{auto_hide = false}` now disarms without touching it.
- **What it did NOT fix, deliberately:** a follow-up `show{force}` from inside the
  submit chain is still closed by the submit in progress unless it passes
  `auto_hide = false`. Owning the close by the submit that armed it needs a
  generation token, judged not worth the state; the guide carries the idiom.
- **Where:** `consoleController.lua` (`SHOW_ONLY_KEYS`, `WIDGET_KEYS`),
  `userInputController.lua` (`configure_core`, `submit_flow`), `../input_api.md`
  (*"Asking one question"*), `../internals/user_input.md`, D-AUTO-HIDE,
  `../../CHANGELOG.md`.

### T-ONESHOT — `oneshot` is ruled in and nothing implements it (RESOLVED, 2026-08-30)

- **Resolution:** built at `FEAT-01-02` after `FEAT-01-01` ratified the edges —
  three as first recommended, one **reversed**: it closes on a *clean*
  submit only, because the error boundary the recommendation stood on wraps the
  route rather than the submit chain. `show{ oneshot = true }` seats the flag at
  activation and `submit_flow` spends it after `after_submit`; `configure{oneshot}`
  raises as a `show`-only key. Documented at `FEAT-01-05`, including the dismissal
  asymmetry Escape leaves standing.
- **Where:** `userInputController.lua` (`open_widget`, `submit_flow`),
  `consoleController.lua` (`SHOW_ONLY_KEYS`), `../input_api.md`
  (*"Asking one question"*), D-AUTO-HIDE.
- **Read the paragraph above as history, not as behaviour** (2026-08-30, the same
  day): `T-ONESHOT-SCOPE` and `FEAT-02` replaced that shape. The key is
  **`auto_hide`**, it is project-owned and settable at `configure`, and it
  **persists until set to `false`** rather than being spent by its own `show`.

### T-PLAINTEXT-ENTERED — the two submit callbacks receive identical payloads (RESOLVED, 2026-08-30)

- **Resolution:** built at `FEAT-01-04` per D-PAYLOAD-SPLIT — `on_text_entered`
  receives the joined string, `after_submit` the line list, and that difference is
  what tells them apart. This also closed **`FIX-02-01`**, which asked whether the
  two were one callback set two ways; the answer needed the write-up as much as
  the ruling, so `FEAT-01-06` carries the *recommended, not enforced* convention.
- **The migration was not uniform, which the entry originally missed.** `unlines`
  is idempotent over a string, so the four consumers that joined kept working
  untouched and were rewired at `FEAT-01-07` for clarity alone; the three that
  indexed (`turtle`, `valid`, `guess`) broke **silently** and migrated with the
  framework.
- **Where:** `userInputController.lua` (submit flow), `../input_api.md`,
  `CHANGELOG.md` (`Changed`, leading with the migration), D-PAYLOAD-SPLIT.

### T-TURTLE-DUP — `turtle` double-handles its own keys (RESOLVED, 2026-08-28)

- **Resolution:** `if compy.input.is_shown() then return end` guard added to `love.keypressed` in `src/examples/turtle/main.lua` to match `love.keyreleased` and prevent double-handling when prompt is open.
- **Where:** `src/examples/turtle/main.lua`.

### `wrap` guards the `xpcall` arity hazard on the platform, not the capability (RESOLVED, 2026-08-28)

- **Resolution:** the branch is gone rather than re-guarded. `wrap` now
  closes the arguments over a nullary function and calls
  `xpcall(fn, on_error)`, which asks nothing of the runtime — so there is no
  platform test left to disagree with the capability. Was `T-XPCALL-GUARD`.
- **Where it was:** `src/controller/controller.lua`, `wrap` — the `_G.web`
  branch, whose `pcall` side was correct for the Web build and unreachable
  for `busted` on PUC Lua 5.1, which is not the Web build. There the route
  was entered with nil arguments: **107 failures**, all under
  `tests/input/`, on a suite green on LuaJIT.
- **Not introduced by this feature.** `master` carries the same guarded
  `xpcall`, reached through `error_wrapper`/`set_handlers`, so on PUC 5.1 an
  adopted `love.keypressed`/`textinput`/`keyreleased` and `love.update`'s
  `dt` already arrived nil. The feature inherited the defect, widened it to
  every shortcut, hook and the widget, and supplied the first tests that
  could see it. The fix is therefore cumulative against the last release,
  not a repair of this branch's own regression — which is how `CHANGELOG.md`
  states it.
- **Guarded by:** `input_route_lifecycle_spec.lua`, "the boundary carries
  arguments on any runtime" — two cases driving a real keystroke with the
  global `xpcall` swapped for PUC 5.1's arity.

### The `show`/`configure` content-ownership boundary was not built (RESOLVED, 2026-08-27)

- **Resolution:** built as sprint `ARC-02`, the implementing pass D-CFG-BOUNDARY's
  own text named as not yet landed. `configure` refuses `text`/`cursor` as
  `show`-only keys, the hidden-`configure` stash is gone with `state.pending`
  entirely, and a forced `show` with no `text` clears. Was `T-CFG-BOUNDARY`.
- **Where it was:** `consoleController.lua` (`PER_SHOW_KEYS`, `check_keys`,
  `stash_hidden_configure`) and `userInputController.lua` (`re_show`).
- **Note:** the two behaviour changes against stakeholder-seen text — the
  clearing forced `show`, and the dropped stash — are recorded in D-CFG-BOUNDARY,
  which is the deviation record for them.

### A highlighter could not be turned off — `false` already did it, unratified (RESOLVED, 2026-08-27)

- **Resolution:** ratified rather than built. D-CFG-BOUNDARY, statement 3 makes
  `false` the uniform unset for every project-owned field, and
  `doc/input_api.md` documents it with the `computed or false` idiom. No code
  changed: every consumer already tested truthiness, so a stored `false`
  always took the absent branch. `prompt`'s two spellings are documented
  beside it — `''` is an empty label, `false` restores the default.
  Was `T-HL-UNSET`.
- **Where it was:** `userInputController.lua`, the shared config path.

### `show{force = true}` applied some keys, dropped one, deferred another (RESOLVED, 2026-08-27)

- **Resolution:** dissolved rather than patched, as the row predicted. A
  forced `show` now takes the ordinary activation path, so there is no
  separate `force` path left to have its own behaviour for a key.
  Was `T-FORCE-PARTIAL`.
- **Where it was:** `userInputController.lua`, `re_show` — deleted.

### `show{cursor = {}}` raised a raw Lua error from inside the framework (RESOLVED, 2026-08-27)

- **Resolution:** `checked_cursor` at the project boundary refuses a malformed
  pair with a framework message naming the shape, on both public paths
  (`show`'s config key and `compy.input.set_cursor`). Out-of-range numbers are
  untouched and still clamp, which is the distinction the guide promises.
  `cursor = false` is the uniform unset rather than an error.
  Was `T-CURSOR-SHAPE`.
- **Where it was:** `userInputController.lua`, `set_cursor_pos` — reached with
  nil or a non-table and dying inside `math.min`.

### The highlighter had two homes, and one of them lagged (RESOLVED, 2026-08-27)

- **Resolution:** one home, per the owner's ruling. The widget's `callbacks`
  slot is the source of truth and the evaluator RESOLVES it
  (`UserInputController:bind_highlighter`) rather than holding a copy, so a
  direct assignment and a `show`/`configure` key are the same write by
  construction. Resolution rather than a forwarding closure, because the model
  branches on the truth of `ev.highlighter` and it must stay nil when unset or
  the validation-colouring fallback stops running. Bound only where the
  evaluator is the widget's own — console and editor share theirs and it
  carries a language highlighter. The drift it replaces is written up in
  `internals/user_input.md`, "One home for the highlighter".
  Was `T-HL-TWO-HOMES`.
- **Where it was:** the widget's `callbacks` table and `model.evaluator`, with
  only the shared config path copying between them.


### `wrap`'s error handler is called with the wrong arity, so project raises vanish (RESOLVED, 2026-08-03)

- **Resolution:** `wrap` binds CC in a closure used by both branches
  (`2554d2e3`), so a raise anywhere in project code now reaches
  `user_error_handler` and suspends the run. Three rows pin it — pointer,
  `love.update`, and a keyboard hook as the control that the other two are not
  asserting something impossible. Owner ruling: a certainly-wrong behaviour is
  not preserved on the grounds that changing it was never approved, even
  though it is pre-feature.
- **Where it was:** `src/controller/controller.lua`, `wrap` — the non-web
  branch was
  `return xpcall(f, user_error_handler, ...)`. `xpcall` invokes a message
  handler with exactly **one** argument (the error), but the signature is
  `user_error_handler(CC, msg)`. So `CC` binds to the error string, `msg` is
  nil, and `'user error: ' .. msg` raises *inside* the message handler, where
  `xpcall` swallows it. Nothing reaches `suspend_run`.
- **Measured effect** (probe run 2026-08-03, asserting the handler executed
  before the raise): a raise in a project's **pointer handler** or in its
  **`love.update`** runs the handler, then vanishes — no error window, no
  console line, `app_state` still `'running'`. A raise in a **keyboard hook**
  suspends correctly, because that path goes through `chain_native`, which
  binds CC in a closure (`xpcall(fn, function(m) user_error_handler(CC, m)
  end, ...)`) and gets the arity right.
- **`_G.web` is falsy on the desktop build, so the broken branch was the live
  one.** The web branch passed both arguments and never had the arity
  problem. Its own flaw — returning bare `r` where the other branch returned
  `xpcall`'s `ok, res...` tuple, so the `@return` annotation described only
  one of them — was fixed alongside the wrapper collapse (`f1dc6aee`).
- **Why the web branch exists at all, established 2026-08-03:** it is not a
  stylistic duplicate. `xpcall(f, h, ...)` forwarding arguments to `f` is a
  LuaJIT / Lua 5.2 extension; PUC Lua 5.1 takes exactly two arguments and
  drops the rest, so on that runtime every handler would be invoked with nil
  for all of its parameters. `pcall(f, ...)` forwards on both. Measured here:
  LuaJIT gives `1, 2`; 5.1 semantics give `nil, nil`. The branch is therefore
  **load-bearing and must not be collapsed away** — a warning to that effect
  now sits on it in code.
- **Reach at the time:** `wrap` had three call sites — `wrapped_native`
  (pointer handlers), the loader, and the project `update` wrapper — plus
  `CC:wrap_handler`, which took `wrap` as its error handler, for the compy
  click handlers. All of those except the loader and the update wrapper have
  since been replaced by `guarded`.
- **Pre-feature, verified:** `wrap` and `user_error_handler` are
  byte-identical at the PR base `3256aac`. The input API neither introduced
  nor worsened this; it only made the contrast visible, because the keyboard
  chain's own wrapper does it correctly.
- **Consequence for the docs:** "A raise from project top-level and from a
  handler surface differently" (below) describes the handler path as
  reaching the error window. That holds for keyboard hooks only.
- **Kept as a closed entry** because two things in it are still live
  knowledge: why the web branch exists (above), and the fact that this
  subsystem's error path had a defect no test could see for the length of the
  feature — the argument for the Web-coverage entry that opens this section.

### `compy.before_exit` is absent from the persistent API docs (RESOLVED, 2026-08-03)

- **Resolution:** documented as `doc/input_api.md`, "Stop hook —
  `compy.before_exit`" (owner ruled 2026-08-03), covering signature, ignored
  return, timing before framework teardown, which stop paths fire it, that a
  raise is **not** one of them, and the reset. Every clause is pinned in
  `tests/input/input_route_lifecycle_spec.lua`; the not-fired-on-raise claim
  was mutation-checked rather than read.
- **What it was:** a public, project-settable lifecycle slot whose only
  specification lived in the feature's ephemeral working tree, which is
  scheduled for deletion — while the PR is meant to be reviewable from
  `doc/input_api.md` plus the description alone. The entry above also depends
  on that contract being findable.

### Future input unification (RESOLVED, 2026-08-03)

- **Resolution:** done, and in the direction this entry doubted. Every
  channel — keyboard, text, pointer, and the derived singleclick/doubleclick
  events — routes through one chain with one error boundary and one lifetime
  (`../decisions/input.md`, D-ONE-LIFETIME). The derived clicks did fold into
  hooks: `compy.singleclick` is gone and `compy.input.hooks.singleclick`
  replaces it.
- **Where this entry was wrong, worth keeping:** it recorded the asymmetry as
  predating the input API. It did not. At the PR base every event installed
  through one path and none was released before stop; the split was
  introduced by this feature (D-ROUTE-LIFETIME, amended). The entry then reasoned
  from the false premise to "folding clicks into hooks would falsely imply" a
  shared contract — when a shared contract was in fact the pre-existing state.
- **What genuinely remains unproven** and is recorded separately: pointer
  combos, and whether a shown widget should consume clicks within its bounds.
  See "Pointer delivery is an unstructured broadcast" below.

### Project-handler wrapping: dedup the guard, drop the misleading `keyboard_` name (RESOLVED, 2026-08-03)

- **Resolution:** the two builders became one — one wrapper, one guard, used by
  the keyboard participants and the pointer path alike. The guard exists once.
  `wrapped_native` / `keyboard_native` / `chain_native` are gone, and with them
  the `native` label and the keyboard-specific name on a function that was never
  keyboard-specific.
- **The names moved after this was written, and this bullet asserted the old ones
  in the present tense until 2026-09-03.** As of today: the guard is
  `project_handler(userlove, key)`, which answers the project's own handler or
  nothing; `project_handlers` seeds them; `occupy_input` (formerly
  `occupy_keyboard`) activates the route and wraps it **once** in
  `with_canvas_and_errors`, rather than wrapping per participant, so
  `chain_project_handler` no longer exists at all; and the pointer path is
  `mark_pointer_liveness`, which **installs nothing** — it only marks the project
  live. The resolution stands; only its vocabulary had rotted.
- **What made the collapse possible:** the split was justified by return
  policy — `CC:wrap_handler` discards the return by construction, and a chain
  participant's return is its consume signal. That was never a real
  constraint: a returning wrapper is usable where the return is ignored,
  which is exactly what a pointer handler installed on `love.*` does. The
  genuine obstacle was that the two paths had *different error handling*, one
  of which was broken — see the arity entry above, fixed first so the
  collapse could be behaviour-preserving rather than a fix in disguise.
- `CC:wrap_handler` survived this step for the compy single/double click
  handlers, then went with them when the clicks became ordinary events
  (D-ONE-LIFETIME). Nothing wraps project code any other way now: `guarded`
  (`controller.lua`), applied where a route is entered, is the only one.
- **Verified behaviour-preserving:** suite 911/0/0/3 across the change, and
  the pointer path now propagates a return value that both `love.handlers`
  and the poll loop discard.
- **What it was:** two builders adapting a project's own `love.*` handlers —
  `wrapped_native` (via `CC:wrap_handler`, return discarded, installed
  straight onto `love.*` by what was then `hook_pointer`, today
  `mark_pointer_liveness`) and `keyboard_native` (via `chain_native`, return
  propagated, seeded as `hooks[event]` by what was then `occupy_keyboard`,
  today `occupy_input`) — carrying the **identical** guard
  (`orig and new and orig ~= new`) and differing only in the wrapper they
  called. `keyboard_native` was misnamed: nothing about it was
  keyboard-specific. Deferred out of the D5 vocabulary rename (2026-07-21)
  on the reasoning that renaming under a mechanical sweep would either bless
  the smell with fresh names or smuggle a behaviour-touching refactor into a
  rename commit — which is why it waited for a pass of its own.

### `love.handlers.userinput` is dead code (RESOLVED, 2026-08-07)

Deleted, with the local `clear_user_input` that existed only to feed it. Both
`love.event.push('userinput')` sites were present at the PR base
(`3256aac:userInputModel.lua`) and were removed by this feature, leaving the
consumer installed — the same shape as `wrap_handler`. Kept as a resolved entry
because the pattern recurs: when a producer goes, grep for its consumer.

### Input-only / pointer-only projects stay live in `project_open` (RESOLVED, ruling a)

- **Where:** `consoleController.lua`'s `run_project`; and in `controller.lua`,
  `user_is_interactive`, the module-local `user_pointer` flag,
  `mark_pointer_liveness` (which sets it — named `hook_pointer` when this was
  written), `set_default_handlers` (which resets it) and `love.quit`. **Named,
  not cited by line, deliberately:** every line number this bullet carried had
  drifted by 2026-09-03, which is the class `general.md` already holds — a
  function name moves once and greps out, a line number rots silently.
- **State (old, broken behaviour):** A non-blocking project (no
  `update`/`draw` hooked) always dropped to `'project_open'` with
  the project route unconditionally released
  (`release_keyboard_route`). For a project whose entire UI was
  the input widget (`examples/guess`) or a pointer handler
  (`examples/sapper`), this meant (1) submit was dead — typing
  still reached the widget but Enter never fired, because
  submit/cancel (then a non-overridable framework tier, since
  retired — D-CHAIN-OF-3) lives in the *project*
  route, which `project_open` disconnected — and (2) Ctrl+Esc quit the whole
  app instead of returning to the console, because `love.quit`
  only stopped-to-console while `app_state == 'running'`.
- **Confirmed pre-existing:** this was verified byte-identical on
  `master` (pre-`0022004`) — not an input-API regression. The
  `release_keyboard_route` call site is new in 1.0.0-rc20260712
  (route-lifecycle rework, AC-27/28), but the lifecycle split it
  slots into predates the feature.
- **Resolution:** owner ruled (a) — an input-only / pointer-only
  project is "live" without hooking `update`/`draw`. New
  predicate `Controller.user_is_interactive()` returns
  `love.state.user_input ~= nil or user_pointer`, where the
  module-local `user_pointer` flag is set in `mark_pointer_liveness` when
  a project installs any pointer/click handler and reset in
  `set_default_handlers`. `run_project` now releases the keyboard
  route only when `not user_is_interactive()` — an interactive
  non-blocking project keeps the project route, so submit/cancel
  keep working (`app_state` still becomes `'project_open'`
  either way, since quickswitch relies on that). `love.quit` now
  stops-to-console for `app_state == 'running'` OR
  (`'project_open'` AND `user_is_interactive()`); an idle console
  (`'project_open'`, nothing interactive) still lets the app
  quit.
- **The carried-forward limitation this entry recorded is GONE, and the
  bullet was stale from 2026-08-03 to 2026-09-07.** It read: *"a non-blocking
  project with no interaction surface at all still gets
  `release_keyboard_route` — the keyboard goes back to the console."*
  **That has not been true since `D-ONE-LIFETIME` amended `D-ROUTE-LIFETIME`**
  and deleted the `'running' → 'project_open'` release outright. At HEAD
  `release_keyboard_route` has **one** call site — `run_project`'s **failed-run**
  branch — and the success branch releases nothing regardless of
  `user_is_interactive()`. So **every** non-blocking project keeps the route in
  `'project_open'`, interactive or not, and an idle one is reached only through
  `love.quit`'s fall-through (the app quits rather than handing the keyboard
  back). Corrected 2026-09-07 while answering an owner question about the
  on-demand widget; the resolution above stands, only its trailing limitation
  was overtaken.

### `compy.keys_pressed` is not exposed to projects (RESOLVED, 2026-08-03)

- **Where:** the project-facing `compy` namespace (`consoleController.lua`,
  the function that assembles it) exposes `terminal`, `audio`, `graphics`,
  `fonts`, `input`, and a `before_exit` slot — no `keys_pressed`. Held-key
  access exists framework-side (`Controller.keys_pressed`, the `held_keys()`
  read-only pressed-keys view) and via the per-event callback argument, but a project cannot poll
  currently-held keys from inside its own `update()`.
- **Why it stands:** Open design question — expose a read-only held-key view
  to projects, or treat callback-arg access as the sanctioned shape and amend
  the documented contract to say so explicitly.
- **A real consumer now exists, and it rules out the second option**
  (2026-08-03): the `keyboard` example maintains its own `INPUT.held` /
  `INPUT.shift` mirror and reads it **during draw**, to decide whether to
  render shifted key labels. A per-event argument cannot serve a per-frame
  renderer, so callback-arg access alone is insufficient for any project that
  *renders* held state rather than reacting to it.
- **Resolution:** owner ruled to expose it — `compy.input.keys_pressed`, the
  same read-only view the chain handed participants, resolved per access so it
  could not go stale. (That ruling had a decision of its own; it was withdrawn
  whole with the rest of the held-key arc and the entry is gone — see the
  supersession below.) Placed on
  `compy.input` rather than at the top of `compy`: it is input state, and the
  input guide is where a reader looks for it.
- **Resolution superseded** (`../decisions/input.md`, D-ASK-THE-DEVICE): the view is
  dissolved and no held-key surface is exposed. **The need this entry recorded
  is still met, by a different answer** — the renderer that ruled out
  callback-arg access asks the device instead (`love.keyboard.isDown`), which a
  per-frame draw can do as freely as a handler can. The entry stays RESOLVED;
  only what resolves it has changed.

### Shortcuts key-repeat semantics are shipped unsettled (RESOLVED, 2026-08-03)

- **Where:** `src/controller/projectInputController.lua`, `:keypressed` —
  `isrepeat` is threaded through to `hooks[event]` dispatch only; `shortcuts`
  fire on every OS key-repeat with no `isrepeat` gate.
- **Why it stands:** Whether shortcuts dispatch should also gate on
  `isrepeat` (fire once per physical press) or intentionally fire on every
  repeat is an open behavioural call, shipped open by design.
- **The first real consumer wants once-per-press** (2026-08-03): `keyboard`'s
  reserved chords (`shift+escape`, `ctrl+alt+up`/`down`) are now shortcuts,
  and each wraps itself in a `if not isr then … end` gate — otherwise holding
  `ctrl+alt+up` ramps the notch every frame. The flag *is* delivered to
  shortcuts, so the workaround is three lines; the question is whether every
  consumer should have to write them.
- **Resolution:** owner ruled that dispatch keeps firing on every repeat and a
  binding opts out for itself — `compy.input.fn.ignore_repeat(fn)`
  (`../decisions/input.md`, D-IGNORE-REPEAT), with `fn.stop_here` alongside it
  when the binding also claims the key (D-STOP-AND-SIDE). Filtering inside the shortcut tier
  was rejected for two reasons: it suppresses with no way to recover a
  hold-to-act binding, and it would leave the same hand-written check in
  `hooks.keypressed`, where commands are equally idiomatically bound. The
  wrapper has one signature and composes across all three tiers.

### No public `is_active()`-shaped visibility query (RESOLVED, 2026-07-31)

- **Where:** the `compy.input` project surface (`consoleController.lua`) had
  no `is_shown`/`is_active`/`is_visible`, though an internal
  `UserInputController:is_shown()` existed.
- **State (old), and worse than this entry recorded:** the entry said example
  projects read `love.state.user_input` directly, as if that were a working
  workaround. **It is not.** A project's `love` is a sandboxed deep clone
  (`../internals/project_sandbox_env.md`), so `love.state.user_input` read
  from inside a project is always `nil` — the framework writes the real
  global, the project sees its copy. `examples/maze/main.lua:497` guards a
  re-show with exactly that read: dead code that never fires, which is why
  maze re-shows the widget on every tick.
- **Resolution:** owner ruled to expose it —
  `compy.input.is_shown()` (`../decisions/input.md`, D-ONE-STATE-ASK), returning
  the widget's own flag so it cannot drift from the one the dispatch walk
  reads. Used by `examples/turtle` for its open-only-if-closed guard.

### On the console route, a hidden widget's input falls to the console line (RESOLVED, 2026-08-03)

- **Resolution:** settled by construction — the console route no longer has a
  widget step at all. The three `forward_*` functions that implemented it were
  deleted, so every keyboard/text event on that route goes to `CC:keypressed` /
  `CC:textinput` (the console line, or the editor fork), hidden widget or
  shown. D-ROUTE-OWNS's "widget visibility is never a routing condition" now
  holds on both routes. The two routes still read differently — the project
  route ends an unclaimed event in the chain, the console route ends it in its
  own input surface — but that is each route's own terminal, not two answers
  to one question.
- **The rows that pinned it are re-sited, not deleted** (2026-08-03). They had
  gone vacuous: with no widget step on the console route, a *shown* widget
  would have satisfied them there too. On the project route a hidden widget is
  a real decision — the walk skips it and reports not-consumed — so they now
  discriminate on the widget's own text, with a third row as the control that
  the same keystroke edits a shown widget. The `#disputable` tag is gone: the
  question it marked is answered, not merely pinned.
- **Where it was:** `src/controller/controller.lua` — `forward_keypressed` /
  `forward_textinput` / `forward_keyreleased` handed the event to the widget
  only while `love.state.user_input` was set, which `hide()` clears; the
  console-route defaults then fell back to `CC:keypressed` / `CC:textinput`.
- **Why it stands:** The general principle — *input the widget declined
  should have no effect* — was ruled for the **project** route only:
  D-ROUTE-LIFETIME ("Changed baseline behaviour", `../decisions/input.md`) gives
  a running project's route every keyboard/text event, so an event no
  shortcut, hook, or shown widget takes simply ends there, instead of
  accumulating in the console behind the project's screen. The **console**
  route kept the old shape, and it is not obviously wrong there: the console
  line is that route's own input surface, so "the widget is hidden, type into
  the terminal" is arguably the correct reading, not a leak. What is unruled
  is whether the two routes should read the same way.
- **Reachability:** No leak path through a *running* project is known today
  — the running case is D-ROUTE-LIFETIME's, and the `project_open` case is
  narrowed by ruling (a) above (`user_is_interactive`), which keeps the
  project route for any project with a widget or a pointer handler. The
  open question is therefore a contract question first: two routes, two
  answers to the same question, only one of them written down.
- **Revisit:** At the next ruling pass over route symmetry — either sanction
  the console fallback explicitly in the contract doc, or give the console
  route the project route's "declined means no effect" shape.

### A bare `*` shortcut is legal, and ruled that it should not be (RESOLVED, 2026-08-03)

- **Resolution:** `check_combo` (`src/util/key.lua`) now raises on a `*`
  trigger with no modifiers, naming the alternative in the message ("for every
  key, use `compy.input.hooks`"). D-COMBO-SHAPE and `doc/input_api.md` carry the
  rule, and two rows pin it — the raise, and the control that `shift+*` is
  still accepted, so the check cannot pass by rejecting classes generally.
- **What it was (measured 2026-08-03):** `shortcuts.keypressed['*']`
  registered without raising and caught every **unmodified** key — `q` fired
  it, `ctrl+s` did not, that belonging to the `ctrl+*` class. Coherent with
  D-COMBO-SHAPE (a class is its modifier set exactly, and the empty set is a
  class), but undocumented, untested, and a second spelling for what a hook
  already expresses.
- The entry was kept here rather than in `../decisions/input.md` while it was
  unimplemented, deliberately: a ratified entry describing behaviour the code
  lacks is the exact error this phase spent a session undoing.
- Corrected while closing: the earlier claim that the multi-trigger raise
  "settles whether a bare `*` is legal" was wrong. It permitted it.

### A multi-trigger combo is silently truncated at registration (RESOLVED, 2026-08-03)

- **Where:** `src/util/key.lua`, `normalize_combo` / `split_combo` — the
  trigger is "the last non-modifier token wins", with no complaint about the
  earlier ones.
- **State (measured 2026-08-03):** `ctrl+a+b` is stored as `ctrl+b`, and
  `a+b+*` is stored as **`*`** — a string an author wrote to mean the
  narrowest possible binding registers the widest possible one. Nothing warns.
  The grammar is *modifiers plus exactly one trigger*: `combo_string` prepends
  only the four modifier classes, so a held non-modifier key never enters the
  combo string at all (measured: `a` and `b` held, `b` pressed → `ctrl+alt+b`,
  no trace of `a`). Multi-key chords are outside the grammar; a project that
  wants "a and b held together" asks the device for the second key inside the
  hook or shortcut that handles the first (`doc/input_api.md`, "Choosing the
  mechanism"). Reconstructing it from a pair of flag-setting shortcuts is
  **not** the answer — that shape is now named as an antipattern there.
- **Resolution:** registration now **raises** on a combo naming more than one
  trigger, or none (`../decisions/input.md`, D-COMBO-SHAPE) — the same treatment
  `show`/`configure` give an unrecognised key. `a+b+*` no longer registers the
  widest possible binding; it is refused with the legal shape in the message.

### A combo table cannot express a modifier-class rule (RESOLVED, 2026-08-03)

- **Where:** `compy.input.shortcuts[event]` (`../decisions/input.md`,
  D-COMBO-TABLES) — `Key.new_handler_table`, an exact canonical lookup keyed by
  one full combo string.
- **State:** every binding names one combo, and dispatch is one exact lookup
  of `combo_string`'s output. A project that wants "**every** `alt+x` is a
  chord, swallow it whatever `x` is" has no sanctioned way to say so; it needs
  an entry per key, or it keeps that rule in a hook and tests the modifiers by
  hand. Found by the `keyboard` migration (2026-08-03), which moved its three
  named chords to shortcuts and kept `appChord` — its Alt-class rule — as a
  hook for exactly this reason.
- **The table is not sealed, though** (measured 2026-08-03):
  `Key.new_handler_table` sets no `__metatable`, so a project can reach the
  metatable and add an `__index`, and dispatch's plain lookup then consults it
  on a miss — a working wildcard, in three lines. It is undocumented, it would
  break the moment the table is sealed, and a reader would take it for a bug.
  Recorded because it shows the mechanism exists, **not** as an idiom.
- **A wildcard would have to answer more than it looks:** precedence against
  an exact binding, whether the matched trigger is passed to the handler, and
  the modifier's own press — holding Alt and pressing nothing else dispatches
  the combo **`alt+lalt`**, since `combo_string` prepends the held modifier to
  a trigger that *is* that modifier. A naive `^alt%+` pattern matches it.
- **Resolution:** owner ruled a sanctioned form — a trailing `*` binds the
  modifier class (`../decisions/input.md`, D-COMBO-SHAPE). `alt+*` is every Alt
  chord; exact bindings win, the class is consulted only on a miss, and it
  never matches the modifier's own press. The three questions above are
  answered by it: precedence is exact-first; the trigger is already the
  handler's first argument; and a class does not match when the trigger is
  itself a modifier. The unsealed-metatable route above is superseded — do
  not use it.
- **Still true, and now documented rather than implicit:** the class form is
  about a *modifier* class. Combos of ordinary keys (`a+b`) remain outside the
  grammar by design, since including held non-modifiers would make every
  binding conditional on nothing else being held. That case is a hook that
  asks the device for the rest of the chord (`doc/input_api.md`, "Choosing the
  mechanism").

### Combo-string dispatch allocates a table per call — RESOLVED 2026-08-16

- **Where:** `src/controller/controller.lua` — `combo_string` built a `parts`
  table and `table.concat`ed it on every call, on the per-keystroke dispatch
  path.
- **Resolved** (`737d8316`): it now accumulates the string directly, so no table
  is allocated. A reused module-level buffer was the other candidate and was
  **declined** — it trades the allocation for shared mutable state in a function
  that would then have to never be called re-entrantly.
- **What remains, and it is smaller:** `find_shortcut`
  (`src/controller/projectInputController.lua`) calls `combo_string` **twice** on
  a miss — once for the exact combo, once for the `'*'` class — so one event can
  ask the device six times instead of three. Reusing the first walk needs either
  a parameter on `combo_string`, cached state, or a second copy of D-COMBO-TABLES's
  precedence logic; all three were judged worse than the cost.
- **Revisit:** with the `'*'`-class lookup, if combo dispatch ever lands
  somewhere genuinely hot.

### `F.reset()` test helper exceeds the 14-line function-body limit (RESOLVED, 2026-07-31)

- **Where:** `tests/helpers/input_fixture.lua`, `F.reset()`.
- **State (old):** Around 18 code lines — native-slot restores plus several
  state-clearing assignments — against the project's 14-line function-body
  hard limit.
- **Resolution:** The native-slot restores the entry names are gone: the
  helper delegates to production teardown (`CC:stop_project_run()`) and clears
  only what production does not own. Nine code lines as of the widget-shown
  fix, which removed the last compensating assignment (`widget.shown = false`).
  Nothing to extract. **Re-counted 2026-09-03 at `FIX-02-05`: eleven**, not
  nine — the helper has grown three restores since (`love.update(1.0)`, and
  `clear()` on the editor's input and the widget). Still under the 14-line
  limit, so the resolution holds; the figure had drifted, which is the one
  numeric drift the verification pass found across 56 entries.

### `submit()`'s deliver-then-hide ordering forced example-side deferral of any reshow (RESOLVED by the input-API redesign)

- **Where:** `src/controller/userInputController.lua` — was `submit()` (calls
  `deliver(self, text)` then unconditionally `hide()`s); now `submit_flow`.
- **Old state:** `on_text_entered` fired while the widget was still active, and
  a trailing `hide()` ran right after (auto-close). A project wanting to "reshow with
  the same text on invalid input" could not call `compy.input.show{...}`
  synchronously from inside its own callback — a re-entry guard
  suppressed it, then `hide()` wiped it. One example project worked around
  this by deferring the reshow a frame.
- **Resolution:** Auto-close on submit is gone (D-EDIT-LIFECYCLE):
  `after_submit` DEFAULTS to a
  no-op and the widget stays shown. A rejected validator locks the field with the
  rejected text still showing — there is nothing to reshow, so the one-frame
  deferral workaround this entry described no longer has a reason to exist.
- **Revisit:** None needed; carried here as resolved history, not deleted.

### `_generic_callback` re-resolves the callback precedence on every event (RESOLVED by the input-API redesign)

- **Where:** was `src/controller/projectInputController.lua`, `_generic_callback` — computed
  `compy_input[chan] or natives[event]` per dispatched event, then branched
  on whether a callback existed.
- **Old state:** The precedence (explicit `on_*` wins, else captured native, else
  noop) was fixed at `activate` but re-resolved on every dispatched event
  instead of once.
- **Resolution:** `_generic_callback` is gone. D-HOOKS-SEEDED
  replaced the two-store precedence rule with one table (`hooks[event]`), seeded once at
  `activate` (`seed_hooks`, `projectInputController.lua:43-49`) — there is
  no per-event resolution left to memoise; `dispatch` (`:74-86`) just reads
  `hooks[event]` directly.
- **Revisit:** None needed; carried here as resolved history, not deleted.

### Pointer delivery is an unstructured broadcast, not a chain (RESOLVED, 2026-08-03)

- **Resolution:** pointer joined the existing chain rather than getting a
  mirror of it (`../decisions/input.md`, D-ONE-LIFETIME). The gateway's pointer
  entries no longer deliver to the widget themselves; they hand the event to
  the active route like every other channel, and the widget is the chain's
  terminal. A pointer hook consumes on a truthy return, so a shown widget
  *can* now be starved of a click aimed past it — the capability this entry
  asked about.
- **What made it cheap in the end:** the owner's ruling that the
  keyboard/pointer split was self-inflicted rather than inherited (D-ROUTE-LIFETIME,
  amended). The consume contract itself cost nothing: measured across
  `life`, `sapper`, `tixy`, `paint` and `pong`, no project pointer handler
  returns a value, and the return was discarded in any case. So this was never
  the "two symmetrically mirrored chains" it was estimated as — one chain
  already existed and pointer simply entered it.
- **Still open, deliberately:** whether a shown widget should consume clicks
  **within its bounds** automatically. Nothing does bounds checks today; the
  chain gives a project the means to decide, which is a different answer from
  the framework deciding for it.
- **Also still open:** a pointer *combo* vocabulary (a modifier-only shortcut
  such as `ctrl` plus a button). Pointer has no shortcuts tier and enters the
  walk at the hook tier; D-ONE-LIFETIME records the question as not-decided.

### `UserInputController:keypressed` forked on `love.state.app_state == 'editor'` (RESOLVED — the `app_state` fork was removed, 2026-07-21)

- **Where:** was `src/controller/userInputController.lua:keypressed`, an
  `if love.state.app_state == 'editor' then … else … end` branch.
- **Old state:** A reusable input widget read global app-mode to change its own
  behaviour — both the editing keymap (order + Ctrl+D `modify`) and whether its
  Enter/Escape submit/cancel ran. Flagged by the owner (2026-07-20) as an
  abstraction leak: the widget could not be reasoned about — or migrated onto the
  new API by the editor later — without knowing it was "the editor." See
  `doc/development/decisions/input.md` D-EDIT-LIFECYCLE.
- **Resolution:** The branch is deleted; `keypressed` runs one uniform path. The
  two real differences moved to honest homes: (1) `modify` (Ctrl+D) is a
  per-instance `allow_duplicate_line` constructor flag, set only by the editor's input,
  mirroring `disable_selection`; (2) the editor consumes Enter/Escape **upstream**
  (`block_input()` in `EditorController:_normal_mode_keys`' `submit()`/`load()`),
  so the widget's uniform `submit_flow`/`cancel_flow` never runs for the keys the
  editor owns. No instance reads global mode. Suite green
  (`tests/input/input_widget_callbacks_spec.lua`, the `the same lifecycle on every route` group).
- **Revisit:** `allow_duplicate_line` is a one-off flag; the widget owning its own
  **combo table** (Ctrl+D and the lifecycle keys as registered combos an editor or
  project extends) is the better end-state the owner named — deferred with the
  console/editor migration (D-ROUTE-OWNS), not this pass. The former inline question
  at `:724` is retired (its concern is resolved
  in shape; the combo-table refinement is what remains).

### Comment wip-citation cleanup (RESOLVED, 2026-07-30)

Comments citing the feature's ephemeral wip tree instead of a canonical doc, in violation of
the `doc/development/conventions/code.md` "Comment References" rule. This entry recorded the
residue as two `src/controller/` comments; a pre-PR revalidation found **thirteen** comment
blocks across seven tracked files, four of them shipped examples under `src/examples/`.

All are rehomed: the controller comments to the `decisions/input.md` decisions they already
cited alongside the wip path, the examples to `doc/input_api.md`, "Submit lifecycle". Kept as
a resolved entry rather than deleted, because the undercount is the lesson — a debt row's
stated scope is a claim like any other, and this one was never re-measured after the tree
moved under it.

### An `update_prompt` endpoint was asked for and declined; `configure` already is one

- **Where:** `src/examples/balloons/terminal.lua` — an in-file remark asks the API to expose an
  *"update-prompt"* endpoint so a game can write its own welcome message when its mode switches.
- **Declined, 2026-08-11 (owner).** It is sugar over `compy.input.configure{ prompt = … }`, and a
  second path to a decorative change costs the surface's orthogonality, which is not ideal
  already. *At best it is a pattern to recommend, not a function to add.*
- **And the project already has it**, which is the part worth recording: `terminal_write(msg)` in
  that same file is one line over one `configure` call, exposed to the game as `write`. So the
  recommended shape is not hypothetical — it exists, in the example that asked for the endpoint.
- **The remark's other half — "three functions juggling each other" — is not the win it looks.**
  Two of the three are load-bearing: the handler slot is late-bound because `ui.lua` requires this
  file, and so activates the session, before `main.lua`'s router exists. Inlining the third
  (`deliver`, which joins submitted lines into the one string the game's handlers take) saves a
  function and costs the comment explaining why the join happens. Left alone deliberately.

### `userlove` does not convey its semantics (CLOSED — ruled to keep, 2026-08-03)

- **Ruling:** the name stays. Owner, 2026-08-03: *"I'd not rename userlove,
  its nice and makes no harm itself."* The rename was the last item of the
  deferred naming cluster; the rest of that cluster resolved by deletion
  rather than renaming (see the entries above).
- **What the reader needs instead, and now has in the code comment:**
  `userlove` is *a table indexed by love-event name holding the project's
  handlers*. Both callers pass one — `set_user_handlers` the sandboxed `love`
  table, `restore_user_handlers` the saved `Controller._userhandlers`. That
  second caller is why the once-proposed `project_love` was dropped: it would
  have been true at only one of the two entry points.
- **Kept as a closed entry rather than deleted** because the wrong candidate
  is the useful part of the record: anyone re-proposing `project_love` should
  find the reason it was refused.
- **Note (2026-08-03):** this entry used to also cover `forward_keypressed` /
  `forward_keyreleased` / `forward_textinput`. Those were **deleted, not
  renamed** — they implemented the console route's widget gate, which
  D-ROUTE-OWNS rules out ("widget visibility is state on the widget, never a
  routing condition"), and which was unreachable once the failed-run teardown
  was fixed. Its description here was also wrong on fact: it routed to the
  console route's active *widget*, not to "the currently-active keyboard
  route".

### The console's prompt is drawn under a project that never takes over `love.draw` (DISPUTABLE, ruled to keep 2026-08-07)

`ConsoleView:draw` paints the console's own input strip whenever the screen mode is not
`editor` (`src/view/consoleView.lua`, `drawConsole`). A project that replaces `love.draw`
never reaches that path — the gateway's draw wrapper calls the project's own draw instead
(`src/controller/controller.lua`, `set_love_update`). A project that draws **through the
console terminal** and defines no `love.draw` of its own does reach it, so the console's
prompt stays on screen for the whole run, inert: the input route belongs to the project, so
anything typed at that strip goes to the project, not to the prompt it appears to offer.

The sapper example, since removed from this repository, was the case in hand — it rendered the
minefield as terminal output and bound only the derived clicks, so the strip sat under the game
field for the entire session.
Surfaced by the owner's smoke test as *"any chance to not show inactive console input at the
bottom?"*.

**Ruled to keep as-is (owner, 2026-08-07):** the console's drawing logic is not to be
conditioned on what a project happens to draw, for the cosmetic benefit of one pen-and-paper
example. The gate would have to distinguish "a project owns the input route" from "the console
is interactive again" — `inspect` being the second — which puts project-lifecycle knowledge
into a view whose job is to paint the console.

**Cost of leaving it:** the strip reads as an available prompt while it is not one. **Cost of
fixing it:** a state test in the view, invisible to the suite — the input fixture stubs the
`view.view` module wholesale, so `ConsoleView:draw` is not exercised by any row, and the fix
would be verifiable only by a human smoke test. Revisit if a project owner asks.
