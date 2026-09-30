---
description: Cross-cutting technical debt outside the input subsystem
status: active
audience: developer
authored: llm
reviewed: none
---

# General

Debt not tied to one subsystem — load-order/aliasing assumptions and shared-utility
semantics.

Three sections below, in release-scope order — not severity, not intent:
**ACTIVE** must be resolved before this release ships. **BACKLOG** is real and
acknowledged, but deliberately deferred past this release. **RETIRED** is
paid, or turned out not to be debt.

---

## ACTIVE

> **The three `T-PR-*` epics below are the release tail as trade-offs** (owner,
> 2026-09-09). The plan changed: the PR is assembled and submitted **now**, and
> the work that the roadmap scheduled before it — the corpus passes, the human
> review, the device and example integration — is **owed after submission and
> before the release actually ships**, which is why it is `ACTIVE` and not
> `BACKLOG`. Each epic **names its constituent work under it** rather than
> spawning a row apiece; where a piece already has its own `ACTIVE` slug the
> epic **references it and the original stands** (owner ruling, same day). The
> roadmap work-ids named inside are provenance — a fact about what was
> scheduled — not pointers to a working-tree file.

### T-PR-CORPUS — the shipped prose/code corpus is not finalized: readability, proof-reading and ledger hygiene are unpaid

- **What is owed, by piece:**
  - **The documentation compaction sweep** — one deliberate pass over the
    stabilised prose corpus (`DOC-01`), cutting hard on comments/changelog/guides
    and carefully on the ledgers, which have no backend
    (`agents/rules/ledgers.md`, *"Compaction cuts a ledger more carefully"*).
  - **The readability review, then the proof-read** — in that order (`DOC-01-08`
    then `DOC-01-09`): readability restructures the text a proof-read would
    otherwise check twice.
  - **The `agents/` lift into the corpus** (`DOC-01-10`) — it writes prose in, so
    it runs first of the closing passes.
  - **The ephemeral- and retired-id citation sweep** (`FIX-03`) and the
    **remaining vocabulary/process work** (`FIX-02 (b)`) — nothing left in either
    changes what a device pass can observe, which is why they trail the surface.
  - **The sprint-id control sweep** (`DOC-01-06`) — a control step run late, with
    the normal expectation of 0–2 mechanical leftovers; it is the paying pass for
    **`T-EPHEMERAL-IDS`** (persistent ledgers citing sprint ids that only resolve
    inside the working tree). See that entry; it stands.
  - **The decisions ledger's interim-past vacuum** (`DEC-02`) — the paying work
    for **`T-ARGUES-INTERIM`**. See that entry; it stands.
  - **The debt register's never-shipped-outside-the-branch vacuum** (`LEDGER-02`)
    — the paying work for **`T-NEVER-SHIPPED`**. See that entry; it stands.
  - **The 64-column comment limit** remainder — **`T-OVER-64`**, a hard rule in
    `agents/rules.md` that must not reach the PR; the comment gate before the
    slice cut carries the length check. See that entry; it stands.
- **The trade-off being recorded:** the PR ships prose that has had a
  stabilisation-era cleanup but not the single final compaction, and ledgers that
  still carry interim archaeology and branch-only tombstones. This is a
  legibility debt, not a correctness one — nothing here changes behaviour — and
  it is real *input* debt for every later agent pass, because an uneven corpus is
  wrong input to inference, not merely unclear prose (the argument that moved
  `FIX-02 (c)` ahead of the merge).
- **Why it is `ACTIVE`, not `BACKLOG`:** `T-OVER-64` alone forbids `BACKLOG` — a
  hard rule cannot be deferred past the release — and the corpus a stakeholder
  reads must be finalised before the release, only not before the PR opens for
  review.
- **Provenance: ours** (the passes are our own upkeep; `T-OVER-64`'s six lines
  are partly the branch's rename and partly one pre-existing offender).
- **Revisit:** between PR submission and release — the compaction pass first,
  then the `agents/` lift, the control sweep, and the two-pass docs review, with
  the ledger vacuums (`DEC-02`/`LEDGER-02`) and `FIX-03`/`FIX-02 (b)` folded into
  the same window. The four referenced slugs retire when their piece is paid.

### T-PR-REVIEW — the PR has had no human code review, and no cold read of the whole assembled change

- **What is owed, by piece:**
  - **A human code review** of the submitted PR — the reason the PR is shipped
    ASAP is to put it in front of one; that review has not happened.
  - **`ACC-03` — the cold read of the *whole* PR**: code changes, tests and prose
    together, followed by the slice-readiness pass. It runs **after the slice
    cut** by owner ruling (2026-09-04), because it reads everything that ships and
    nothing follows it but opening the PR.
- **The trade-off being recorded:** the change is submitted before any reader
  other than its authors — human or cold-agent — has read it end to end. Defects
  either surfaces are expected and are fixed before the release ships; a review
  that finds nothing is still owed until it has run.
- **Why it is `ACTIVE`, not `BACKLOG`:** an unreviewed release is not a deferred
  nicety — the review is a gate the release passes through, not past.
- **Provenance:** operational need (a claim is verified before it ships;
  `agents/rules/ledgers.md` §4 names this exempt from citing a decision).
- **Revisit:** once the PR is open — the human review on the reviewer's schedule,
  `ACC-03` after the slice cut. Both feed fixes back into the tree before release.

### T-PR-DEVICE-EX — the shipped surface has never had end-to-end testing on the device, and the external examples are integrated against an earlier API, not re-fitted to it

- **What is owed, by piece:**
  - **`ACC-02` — device validation on real hardware, and it is more than a smoke**
    (owner, 2026-09-09). The roadmap row names it *"smoke on real hardware"*, and
    that undersells what is actually owed: **the prior device runs were against
    interim versions of the surface that have since moved significantly** — the
    #45 import, the lifecycle flags, the non-destructive activation, the single
    payload, the positional `compy.ask` and the whole simple surface all landed
    after them. So what the release owes is **thorough end-to-end testing on the
    device**, not a light pass over a surface a previous run already covered —
    there is no previous run of *this* surface. It remains the last thing that can
    find a *runtime* defect, which is why everything after it is cheap to redo.
  - **Re-fitting the already-integrated examples to the shipped API** — this is
    **not integration from scratch** (owner, 2026-09-09): *some* external examples
    were integrated onto the new input API in an earlier pass, but against a
    version of the surface that has since moved (positional `compy.ask`, the
    lifecycle flags, the non-destructive activation, the single payload, the
    simple surface). Each such example needs re-fitting to the surface as it now
    stands, with adjustments that **may be trivial or may be substantial — which
    is not yet known per example**. What remains to be integrated fresh, if any,
    is the tail of the same work.
  - **`PREX` — each external example repository opens its own PR** against its own
    remote (`keyboard`, `maze`, `balloons`, and the scope **may be wider**), read
    against the platform build it targets, so it runs **after the platform PR**.
    This includes **`T-DRIFT-KEYBOARD`** (the `keyboard` example one commit behind
    its renamed upstream), which retires when that repository's PR is opened. See
    that entry; it stands.
  - **The standing design-level item** *"Examples are not onboarded onto the new
    input API"* (`BACKLOG`, `input.md`) is the same work seen from the API side;
    the re-fit is where it is exercised end to end.
- **The named risk (owner, 2026-09-09):** device testing and the example re-fit
  **may surface defects, and they may land on either side** — a platform-side fix
  to this branch, or an example-side fix in the example's own repository. Neither
  is scheduled work today; both are expected outcomes of running the passes, and
  the fixes ship in whichever tree owns them. Because the device has never run
  *this* surface end to end, the yield here is genuinely unknown — it is not the
  low-yield confirmation a re-smoke of unchanged behaviour would be.
- **Post-release upstream edge:** `MERGE-01-06`, the platform upstream
  reconciliation remainder, is deliberately **after the release** and is named
  here so it is not lost; it is the one piece of this neighbourhood that is not a
  pre-release obligation.
- **The trade-off being recorded:** the PR ships a surface validated only by the
  test suite (`busted`, 1174/0/0/9) and **never exercised end to end on the
  constrained device it targets in the form it now takes** — the device runs on
  record predate the surface's significant moves. The example projects that
  demonstrate the API sit on an earlier version of it, not yet re-fitted to the
  shipped surface nor re-validated against it.
- **Why it is `ACTIVE`, not `BACKLOG`:** end-to-end device testing is the last
  runtime gate and a release cannot ship without it; the example PRs are
  release-adjacent preparation the release coordinates, not work deferred past it.
- **Provenance:** operational need (`ACC-02` validates what ships on the device;
  the example PRs are obvious pre-release preparation — both exempt from citing a
  decision).
- **Revisit:** `ACC-02` before the release once the tree stops moving; `PREX`
  after the platform PR. Defects surfaced by either are fixed before release,
  wherever they land.

### T-DRIFT-KEYBOARD — the keyboard example is one commit behind its upstream, and its upstream was renamed

- **Where:** the `keyboard` example repository. Upstream is **one commit ahead** (`96d6629`,
  2026-08-20): it adds `.compy/build`, 32 lines, **no source file touched**, following the
  packaging convention the `maze` repository set — one source tree emitting two shipped projects,
  `keyboard/` and `k/`, so a beginner can reach the typing game without typing eight letters.
- **State:** merges **clean** — verified, not assumed.
- **Blast radius: packaging only.** Nothing it adds is read by this feature's work, and nothing
  this feature changed is read by it.
- **What it costs:** one merge, no decisions — **and this was checked rather than assumed**
  (2026-09-03), because *"merges clean"* and *"costs nothing"* are different claims. The script
  copies `*.lua` plus `README.md` from a flat source tree. Our branch is **37 commits ahead** in
  that repository and its file set is **identical to upstream's** apart from the script itself:
  every commit changed the contents of an existing file, and none added a file or a subdirectory.
  So the script emits our tree correctly, and the cost really is one merge.
- **The sibling repository is the fragile one, and it is worth knowing before anything is added
  there.** `maze` set this convention first, but **its build script enumerates its sources by
  name** rather than globbing — three explicit lists, one per emitted program. A file added to
  that repository and not added to the list is **silently absent from the shipped project**. Our
  `maze` work adds no file (its tree differs from upstream's only by a repository-local
  `ISSUES.md`, which is correctly not emitted), so nothing is dropped today. The hazard is for the
  next person, and it is theirs, not this feature's.
- **A second finding, free:** the upstream repository has been **renamed** (`keyboard` →
  `compy.keyboard`). The old remote URL still resolves by redirect, so nothing is broken today and
  it will keep working until it does not. Worth correcting when that repository's pull request is
  opened.
- **Provenance: not ours.**
- **Revisit:** before that repository's pull request is opened — **and that is now where it is
  scheduled** (owner, 2026-09-04). The release's own reconciliation dropped it: the commit is
  packaging this feature neither reads nor changes, so taking it is preparation for that
  repository's pull request rather than release work. It is paid **after the platform PR**, with the
  remote rename above, and this entry retires there.

### T-GFX-GLOBAL — `gfx` implicit global in `controller.lua`

> **Contested, and scheduled: `FIX-02-15` (*"this register carries an entry that is
> not debt"*).** The owner's position, 2026-09-04: *"it's not a defect, but
> convention -- `gfx` is alias for `love.graphics`, `sfx` is alias for
> `compy.audio`."* Recorded on the entry rather than left as a review marker,
> because it is the disposition `FIX-02-15` will act on.

- **Where:** `src/controller/controller.lua` — `set_love_update` / `set_love_draw` (and
  other drawing call sites in the same file) use `gfx`, a free variable not set in the file
  or any of its requires; it must exist at call time (set by the app's load sequence).
- **State:** Works because of load order, not because the file declares its dependency.
- **Why it stands:** Long-standing wiring assumption; changing it risks the load sequence
  for no behavioural gain.
- **Revisit:** When the controller's load/aliasing is next reworked — prefer a module-top
  `local gfx = love.graphics` per the standard-aliases convention.

### T-ARGUES-INTERIM — the decisions ledger argues with an interim past that never shipped

- **Where:** `doc/development/decisions/input.md`, throughout the live entries — not the `RETIRED`
  section, which is already empty.
- **The rule it fails:** `../../../agents/rules/ledgers.md`, *"What a decision records about its
  own past"* — what was not in a released version is considered never to have existed, except what
  stakeholders explicitly ratified. Prose re-litigating an interim version of our own ruling
  describes a system nobody ran.
- **Two measured instances, and they are the two shapes:**
  - **A whole section arguing with a withdrawn rationale.** `D-ROUTE-LIFETIME` carries *"Why the
    original rationale was withdrawn"* — ten lines quoting a justification that never reached a
    release and refuting it point by point. The mid-run release it describes was introduced and
    removed inside this branch.
  - **A name that lived a fortnight.** `oneshot` was ruled and overruled within a day and never
    released. **PAID for this instance, 2026-09-01** (`d0f4e66c`): `D-AUTO-HIDE` was 132 lines with
    24 of churn and is 77 stated as one decision, on the owner's framing that replacing `oneshot`
    with `auto_hide` is a single decision from a stakeholder's perspective. The name survives four
    times, deliberately — the developer who asked for the flag asked for it by that name. **Eleven
    citations moved with it**, six naming *"the Amendment"* and four *"ruled edge N"*: prose that
    argues with itself teaches the code to cite it that way, which is what makes the class
    expensive rather than merely untidy.
- **A third measured instance, found 2026-09-03 by the citation-hygiene pass and left for this
  goal:** `D-HOOKS-SEEDED`'s chain-participation rationale closes on *"the resurrection-on-nil behaviour was **never asked
  for**; it was an artifact of two separate storage locations being resolved late"*
  (`decisions/input.md`, the paragraph before *Consequence, accepted*). It is the first shape at
  one-sentence scale — a defence against an alternative that existed only between two interim
  storage layouts inside this branch. The list of unasked alternatives that stood beside it is
  already gone; this clause outlived it.
  **Qualified by the owner, 2026-09-05, and the qualification splits the sentence:** *"'never asked
  for' is not always archaeology — in this exact form it could also be a legit fact about lack of
  demand."* So the clause is **two claims, and only one of them is this entry's**. *"Never asked
  for"* is a statement about **demand**, which is provenance a reader cannot re-derive and which
  the ledger rules keep; *"an artifact of two separate storage layouts being resolved late"* is the
  archaeology — it describes an interim implementation nobody ran. **`DEC-02` cuts the second half
  and keeps the first**, and this is the entry's worked example that the class cannot be swept by
  matching a phrase.
- **Not a mechanical sweep, and this is the whole difficulty.** Two things sit inside the same
  paragraphs and must survive: **pre-feature baseline facts**, which are provenance telling a
  reviewer the release *restored* behaviour rather than changing it, and **anything stakeholders
  ratified**. `D-ROUTE-LIFETIME`'s section is the worked example of both — the base check inside it
  (`set_default_handlers` called from exactly two sites at `3256aac`; the `running → project_open`
  transition released nothing) is exactly what must be kept while the argument around it goes.
- **The qualifier is `interim, overwritten`, not `self-arguing`** (owner correction, 2026-09-01).
  An entry weighing a live alternative, or amending another entry still in force, is the ledger
  doing its job. The test is whether a reader would plausibly propose the alternative again.
- ~~**The `REMARK` that raised it stays until this is paid, deliberately** (owner, 2026-09-01)~~ —
  **SUPERSEDED 2026-09-04 (owner), and the marker is gone** (`d5e4f230`). It was
  `decisions/input.md`'s *"clean up self-arguing with past decisions that were then reshaped
  before release"*, carried on `D-ROUTE-LIFETIME` with its own note claiming exemption from any
  marker sweep. The owner overrode both the note and the prompt that repeated it: **the concern's
  durable home is this entry**, so the marker was removable under `FIX-02-07`'s branch 3
  (registered-and-planned) immediately, rather than at `DEC-02`. The rule behind the original
  instruction is unchanged — *a marker goes when the defect it names has a durable home, not when
  a sweep reaches it* — and what moved is only the finding that the home already existed.
  **No pass owes this marker anything; do not go looking for it.**
- **Scope question ANSWERED, and it moved to its own goal** (owner, 2026-09-01): *"I would vacuum
  debt on the same principle — introduced-then-paid never existed for the outer world."* So the
  debt register's `RETIRED` section is in scope for the principle but **not for this entry**, which
  stays on `decisions/*`. `T-NEVER-SHIPPED` carries it, because the register needs a base check per
  entry where the decisions ledger needed a reading — different work, different pass. `T-ONESHOT`
  and `T-ONESHOT-SCOPE` go there.
- **Revisit:** `DEC-02`.

### T-NEVER-SHIPPED — the register keeps entries for defects that never existed outside the branch

- **Where:** `input.md`'s `RETIRED` section and this file's — **61 entries, 53 + 8, counted
  2026-09-03**; the pass walked a 56-entry snapshot — see `T-RETIRED-UNVER`'s resolution for the
  five outside it (51 the day before, 47 the day before that; the section grows every time a sprint
  pays into it, and it grew twice *during* `FIX-02-05` itself). **Do not trust this number either —
  count it when the row opens.** The figure is here to size the row, not to be cited.
- **The rule it fails:** `../../../agents/rules/ledgers.md` §3 — what a branch introduced and paid
  before release never existed for anyone outside it, so its entry records our own working process
  rather than the product's history. A **pre-existing** defect the branch fixed is the opposite: it
  shipped, users met it, and the entry is the evidence behind a changelog line.
- **The classification is already scheduled, and this reuses it rather than re-deriving it.**
  `FIX-02-05` tested every retired entry against the PR base to verify its resolution claim —
  **the same check answers *did this exist at the base?*** One pass, one classification, **two
  consumers**: `CHG-01-03` takes the pre-existing half into the changelog, and this goal takes the
  other half out of the register. Nothing new is enumerated, which is why this is a step and not a
  survey. **The pass ran 2026-09-03** and its verdict — entry by entry, with the command behind
  each — is **39 introduced-in-branch, 9 pre-existing, 5 mixed, 3 cannot-tell** over 56 entries.
  This row's input therefore exists; **take it, do not re-derive it.** The three cannot-tells are the `maze`/`balloons` entries, whose repos have no comparable
  base commit — **leave them in the register**, since the rule vacuums what is known to be ours and
  not what is merely unproven.
- **Sized on `FIX-02-05`'s classification, not on the 2026-09-01 measurement.** That figure
  (47, then patched to 51, then to 56 in *Where*) is superseded. Take the classification above:
  **39 introduced-in-branch · 9 pre-existing · 5 mixed · 3 cannot-tell** over the walked 56;
  five more sit outside that snapshot and are dispositioned in `T-RETIRED-UNVER`'s resolution —
  all `INTRODUCED-IN-BRANCH`, and not close. Do not re-derive either half.
- **Three entries were retired *after* that classification ran, and the pass is told not to
  re-derive — so they are classified here** (2026-09-05, S74 delivery review F7).
  `T-LOVE-IS-A-HANDLER`, `T-HELD-SET-GHOST` and the struck *"`D-CHAIN-OF-3` contradicts itself"*
  entry landed on 2026-09-04/05, all three **INTRODUCED-IN-BRANCH** and not close — each was a
  defect this branch's own prose created and paid the same week. **A fourth followed the same
  day: `T-DRIFT-PR45`, retired by `MERGE-01-05`, and it is `NOT OURS`** — upstream work by
  another author, the debt being the distance to it. Re-counted at 2026-09-05, and **count both files by section rather than by line number**:
  `awk '/^## RETIRED/{p=1;next} p&&/^### /' technical_debt/input.md | wc -l` → **56**, plus the
  same over `technical_debt/general.md` → **9** = **65**, against the **61** in *Where*.
  **The `awk 'NR>1472'` form this entry used to print is wrong and was never right** — it
  hardcodes where `## RETIRED` sat on the day it was written, and any entry added to `ACTIVE`
  above it silently pulls `ACTIVE` rows into the count (it returns **58** today). Caught by this
  session's peer review; the figure was right, the printed way of getting it was not. **The durable half of this fix: any entry retired after this date
  is classified by the session that retires it**, so the gap does not reopen every time the
  register is paid into.
- **Mixed provenance is a third category and it keeps the entry.** `BUG-01-05` is the worked
  example — a pre-existing byte bound that our own wrappers made externally reachable by copying its
  convention deliberately. The pre-existing half shipped and is the outer world's; the half this
  branch introduced is not. **Rewrite to the first half; do not delete, and do not keep both.**
- **Two entries are known to go already:** `T-ONESHOT` and `T-ONESHOT-SCOPE`, which record a key
  ruled and overruled inside a day and never released — the same arc `D-AUTO-HIDE` was rewritten to
  drop (`d0f4e66c`). They are the scope question `T-ARGUES-INTERIM` left open, and this answers it.
- **Their provenance was raised and ruled, for these two entries only** (owner, 2026-09-02). The
  capability was **asked for from outside the input work** — the `serial` API's author — and §2 keeps
  a ruling that came from outside, so the sweep was checked against that before it runs. **They still
  go.** The owner's ground: the question those entries would answer is *"why is `oneshot` gone and
  what replaces it"*, and **that is a decisions question**, answered by `D-AUTO-HIDE` — which names
  the outside request and names `oneshot` deliberately, for the developer who will grep it. It is
  **not debt, because the contradiction did not exist at the base**: at `3256aac` there was
  `oneshot` and nothing replacing it, so *"ruled in and nothing implements it"* is a state this
  branch created and closed. Swept from the register; **stands in the decisions ledger and, as the
  capability, in `CHANGELOG.md`** (`CURRENT_SCOPE`, *Added*, which describes `auto_hide` at
  user-facing altitude and correctly never mentions `oneshot` — no project could write it).
  **Ruled for this instance; §3's test is unchanged and stays the base check.**
- **Two members carry ephemeral path citations, and their disposition rides on this sweep**
  (2026-09-03). This file's two renumber entries — *"A renumber shipped its crosswalk without the
  sweep, and five citations resolved to the wrong pass"* and *"The `FIX-02` renumber's own citations
  were never swept"* — name the feature's roadmap, its plan and three of its review documents in
  their **Where** and **Resolution** fields, six citations in all. The citation-hygiene pass left
  them there deliberately: in these two entries the working-tree file **is the defect's location**,
  not a reference, so there is nothing canonical to repoint at and rewriting them would destroy the
  entry. Both are introduced-in-branch by this entry's own test. **If this sweep archives them the
  citations leave with them; if it keeps either, that entry owes the repoint before the PR.**
- **Revisit:** `LEDGER-02`.

### T-EPHEMERAL-IDS — the persistent ledgers cite sprint ids that only resolve inside the working tree

- **Where — a snapshot, and it moves under its own sweep.** Measured 2026-09-03 at
  `d90b3fd6`: **118 matches**, of which **2 are `conventions/docs.md`'s own illustrations of the
  rule** and the remaining **116 are citations** — `technical_debt/input.md` (52), this file (40),
  `decisions/input.md` (12), `smoke_checklists.md` (10), and one each in
  `internals/user_input.md` and `internals/examples/turtle.md`. Heaviest: `BUG-02-01` (12),
  `FEAT-02` (11), `FIX-02-05` (9).
- **How to re-derive it, because the first derivation of this entry was wrong by its method:**
  `git grep -oE '\b(ACC|ARC|LEDGER|FEAT|BUG|FIX|CHG|DEC|OP|REC|MERGE|PR)-0[0-9](-[0-9]{2})?\b'
  -- doc/ ':!doc/development/wip/'`. The figures first filed here (119, and *"eleven apiece"* for
  three ids) came from a hand-listed set of directories rather than the corpus rule, and were
  taken **before** the same session's own path sweep edited four of these files. **Both errors are
  the same error**: a count derived from a narrower subject than the one it claims, then quoted
  after the subject moved. Re-derive when the row opens; do not cite these numbers.
- **Why it matters:** the ids resolve **only** in the tree that names them, and that tree is
  deleted or kept whole by an owner ruling at assembly time. If it goes, every one of these
  reads as a live pointer to a sprint the reader cannot find — and it is the failure mode the
  line-citation entry above calls worse than dangling, because it **greps clean**.
- **Distinct from two rows that look like it.** The retired-id sweep takes citations of ids that
  are already dead; these are all **live and correct today**. And the ephemeral-**path** rule
  this shares its logic with never covered bare ids, which is why the count reached three figures
  without a single pass flagging it.
- **The sibling path class is closed, and its pattern is recorded here because its first two
  derivations were both short.** The citation-hygiene pass fixed 14 paths on 2026-09-03 and handed
  six to `LEDGER-02` (see `T-NEVER-SHIPPED`); a delivery review then found **two more it had never
  matched**, both naming the frozen `design/` tree, and both are fixed. The pattern that covers the
  whole class — relative forms included, which is how the first derivation undercounted —
  is `git grep -nE '(wip/77|77-new-input-api|design/|validation/|implementation/|pr-slices|pr-assembly|sessions/session|ROADMAP\.md|plan\.md)' -- doc/ ':!doc/development/wip/'`,
  and it should return only the six handed to `LEDGER-02` plus this file's own illustrations. Run
  it beside this entry's own command; **a path citation does not have to spell the path**, and the
  one sub-tree most likely to be cited by name is the one the phase treats as authoritative.
- **The path class REGREW after it was declared closed, and the regrowth is now PAID** (2026-09-06).
  Measured before the fix: the pattern above returned **17**, not the eight it predicts — **seven**
  lines carrying the six `LEDGER-02` holds (six citations do not occupy six lines, which is where
  *"eight"* came from), **four** lines of this entry's own prose about the rule, and **six new live
  citations** written after the 2026-09-03 sweep by three separate sessions: `../decisions/input.md`
  (`D-LIFECYCLE-FLAGS`), `input.md` (`T-LEAVE-KEYS-LOSES-BLOCK`, `T-CTRL-S-UNCLAIMED` ×2,
  `T-NAV-ESCAPE`) and this file (`T-PR45-ASK-UPSTREAM`). **All six are gone**, and the owner's
  ruling the same day is why: **a persistent ledger never cites `wip/`; only the reverse direction
  is allowed** (`agents/rules/ledgers.md` §8). None of the six was deleted — each entry now
  **states the evidence it used to point at**: the attestation and who gave it, the sorted-line
  proof behind *"the reshape changed no executable content"*, `REC-01`'s measurement as a dated
  fact, and `R11` as a named risk class rather than a file.
- **What is left under the pattern is not citation, and must not be swept as if it were.** Two
  kinds: this entry's own illustrations, which have to spell the paths they forbid; and the
  `LEDGER-02` holds, which are **RESOLVED** entries whose *"Where"* records the location of a defect
  that has been fixed. Nobody is being sent to read those paths — they are the subject, not a
  pointer — and §3 vacuums entries introduced and paid inside the branch to the archive anyway, so
  they leave with their paths rather than being rewritten. **`DOC-01-06` should expect to find
  nothing to rewrite here and something to move.**
- **The lesson is the one the entry already argued and did not apply to itself** — a class stays
  closed only while something re-runs its command, and between 2026-09-03 and 2026-09-06 three
  sessions cited freely because the ledger said the class was shut. *(The first draft of this
  amendment reported **15**, which was true when measured and false when committed, because its own
  prose spells two of the paths. Found by that session's peer review, not by its author — precisely
  the failure this entry warns about two bullets above, committed inside the correction to it.)*
- **Provenance: ours, entirely.** The ids are this branch's own vocabulary; at the PR base
  `3256aac` neither the ledgers nor the ids exist.
- **Found:** 2026-09-03, re-deriving the citation-hygiene rows — which had been sized at ~12
  sites and were measuring paths only.
- **A pre-PR gate over this class was proposed 2026-09-03** — the sibling path rule had no
  mechanical check and the class reached three figures under it, so the command above would sit
  beside the marker gate and the class could not regrow between the sweep and the release.
  **RULED 2026-09-04, and the ruling merged the gate into the sweep rather than adding a second
  instrument.** The sweep runs **after the compaction pass, first of the three rows that close the
  corpus work** — only the two docs-review passes stand between it and the slice cut, and neither
  introduces sprint ids —
  as a **control step whose expected result is nothing to do** — so there is no interval left
  between it and the release for the class to regrow in, and the check the gate asked for is the
  step itself. A step that expects zero and finds three is a check; a sweep that expects a hundred
  is a cleanup, and cleanups get skipped when they look done.
- **Why late is right, and it is not a cost argument** (owner, 2026-09-04). Most of these
  citations *are* the troubleshooting trail while the prose is still being worked: sampled, they
  are development history at the level of *"built at X"*, *"deleted at Y"*, *"Roadmap: Z, done"*,
  and **compaction eliminates them by eliminating what they annotate**. Sweeping early destroys
  live evidence to satisfy a rule about readers who do not exist yet.
- **What the control step should expect to find — stated structurally, because a total here is
  not merely stale but self-invalidating.** Run the command above. **The overwhelming majority of
  hits are in the three ledgers `DEC-02`, `LEDGER-02` and `DOC-01` rewrite** —
  `technical_debt/input.md`, this file, and `decisions/input.md` — and those citations **leave
  with the entries that carry them**, so they are not the control step's work. Measured across
  three re-derivations on 2026-09-04 the ledger share held at **~90%**.
  **The residue is what the control step is actually for, and it is small, named and stable:**
  `smoke_checklists.md` (ten — one structural defect, see below), `internals/user_input.md` (one),
  `internals/examples/turtle.md` (one). Two in `conventions/docs.md` are the rule's own
  illustrations and are exempt. **A control run finding dozens means an earlier pass did not
  run**, and that is the whole check.
- **No total is recorded here on purpose — this entry is inside its own measurement.** On
  2026-09-04 the figure was written three times and was wrong twice within the hour, each time by
  the same mechanism: **describing this class requires naming sprint ids, so every edit to this
  entry emits more of what it counts.** 123 became 126 when the finding below was written in
  (`DEC-02`, `LEDGER-02`, `ACC-02-01`, `ACC-02-05`, `FIX-02-09` — three of them new here), and 126
  became 131 when *that* was corrected. **The total is not a citable quantity for this class; the
  command is, and the file-level shares are.** This is the bullet above's *"measured over set A,
  stated over a superset"* arriving by a route it did not cover — the subject moves **because**
  the measurement is written down. *(First figure caught by the S72 peer review, which re-ran the
  command instead of trusting the number beside it; the second by re-running it after the fix.)*
- **The residue was not narration — `smoke_checklists.md` was *keyed* by sprint ids. PAID
  2026-09-04 (session73, at `FIX-02-09` as scheduled).** Its device-pass table used
  `ACC-02-01` … `ACC-02-05` as the **row identifiers of the checklist**, with the renumber
  narrated two lines below it. **Compaction could not have cleared this**: there was nothing
  verbose to compact, the id *was* the structure, and it survived into an operational document
  that ships. That is `agents/rules/roadmap.md` §2's renumber-vs-rename test arriving in a
  checklist. **The rows are now keyed by the list's own name** — `balloons`, `keyboard`,
  `maze` + `draw`, `sapper`, `turtle` — with a plain 1–5 left in the `step` column for reading
  order, and the file states that a result is reported by name and commit. The renumber
  narration went with the ids it explained. *(Found 2026-09-04 by sampling five citations to
  test what they say — the sampling the ruling above came out of; paid the same week by the row
  that opened the file first, which is what scheduling it there was for.)*
- **What that leaves for the control step, re-derived after the payment rather than adjusted
  by arithmetic.** Running this entry's own command over the corpus now leaves
  `smoke_checklists.md` with **three** hits, all `FEAT-02` in prose, plus one each in
  `internals/user_input.md` and `internals/examples/turtle.md`, plus `conventions/docs.md`'s
  own illustrations of the rule, which are exempt. **Every remaining hit outside the ledgers is
  narration, which is the class compaction does clear** — the structural member is gone, and it
  was the only one.
- **Slugged, and scheduled late on purpose** (owner ruling, 2026-09-03). The rule landed
  immediately (`conventions/docs.md`, *Rules*) so the prose written from here on does not add to
  the pile; the **sweep runs after the two ledger-vacuuming passes**, because a vacuumed entry
  takes its ids out with it and a sweep run first sweeps prose that is about to leave.

### T-OVER-64 — six comment lines exceed the 64-column limit, deliberately, until the comment compaction pass

- **Where:** `consoleController.lua:181`, `userInputController.lua:442, :745`,
  `input_widget_callbacks_spec.lua:538, :762, :805` — 65 to 70 characters.
  Re-derive rather than trusting these citations, which drift:
  `git grep -n 'D-EDIT-LIFECYCLE' -- src/ tests/` and measure.
- **State: an accepted deviation, not an oversight** (owner, 2026-09-05).
  Renaming `D-NO-FW-TIER` to `D-EDIT-LIFECYCLE` on 2026-09-05 added four
  characters to every comment carrying the id, and six lines crossed. The
  owner declined a reflow at rename time: *"no need to reflow for length —
  better do reflowing once, later at prose compaction step."* One of the six
  (`:805`) was **already** over the limit before the rename and is not this
  branch's doing.
- **Why deferring is the cheaper order:** a reflow re-wraps a comment block,
  and `agents/rules/commenting.md` schedules comment compaction as its own
  substep near the end, taken **once**, over stabilised material. Reflowing
  now means reflowing the same blocks twice, and the second pass would be the
  one that has to be right.
- **Revisit:** the comment sweep that precedes slice regeneration
  (`agents/validation.md`, *"Comment gate before slice regeneration"*). It is
  already the pass that opens these files, and the limit is checkable
  mechanically once it does — **that gate now carries the length check as well
  as the marker check**, and `PR-01-01` cites this slug as a predecessor
  obligation, so the pass meets the entry instead of chancing on it.
  **This must not reach the PR** — the limit is a hard rule in
  `agents/rules.md`, and what is deferred here is when it is paid, never
  whether. **ACTIVE, not BACKLOG** (corrected 2026-09-05): BACKLOG means
  *deferred past this release*, which contradicts the sentence above it.

## BACKLOG

### The branch is 15 commits behind the platform's experimental line, beyond the editor rework — 11 changes

- **Where:** the platform repo's edge line (`5a52cba2`, 2026-09-03). It is **71 commits** ahead of
  the line this branch develops against; **52 of those are the editor rework** covered by
  `T-DRIFT-PR45`, and **15 are this entry**. *(Not 16 — the filesystem durability API is already an
  ancestor of our head. Derive with*
  `git rev-list --count --no-merges HEAD..<edge> ^<rework>`*, subtracting both, and re-derive when
  this is taken.)*
- **By content it is 11, not 15, and counting by hash is what overstated it.** The two lines
  cherry-pick between each other, so the same change exists on both with different hashes.
  `git cherry` compares patch-ids instead: **four of the fifteen are already ours** — the editor's
  checkpoint filesystem info, the extended-palette termcolor fix, the terminal repaint gate and
  black's own bright slot. **Three of the remaining eleven are alternate versions of colour work we
  already carry**, which is why the colours example collides as an add/add rather than applying.
  *"Commits in A not in B"* answers a question about hashes; the question meant here is *"changes
  in A not in B"*, and `git cherry HEAD <edge>` is the command for it.
- **What is in the 15:** the 64-slot colour palette and the terminal-colour fixes that follow it,
  a colours example, the editor checkpoint's filesystem info, packaging changes (zip instead of
  7-zip, release signing), a Lua 5.1 test-runner launcher, the Android exit path, a terminal
  repaint gate, the per-character input render-cost fix that is its own open upstream pull
  request, and a storage-fallback label at the prompt.
- **Analysed by essence, not only by conflict** (2026-09-03), because *"does it merge"* and *"does
  it still do what it did"* are different questions. **Three findings, in descending order:**
  - **The Android exit path is silently lossy against our tree.** It reroutes every full exit
    through a request that `love.quit` consumes and answers by returning to the launcher first —
    including the **Ctrl+Escape** handler, which is one of the lines this branch **moved** into
    the privileged reservation table. A project's typed `quit()` takes the change cleanly; the
    reservation does not conflict with it and keeps calling `love.event.quit()` directly, which
    never raises the request. **The defect is in the line that does not conflict**, so resolving
    the visible hunk correctly still ships it — and it fails only on a device, where no headless
    suite can see it. One line fixes it: the reservation calls the request instead.
  - **The prompt label widens from a string to a string or a `{ text, tone }` table**, and this
    feature's public `prompt` key writes exactly that field. Verified: with the label passed
    correctly, the widened form works through our constructor. So the question is whether the
    guide **admits** it, refuses it, or stays silent — a surface decision, not a break.
  - **Two draw-path changes cannot be cleared here at all** — the per-character render-cost fix
    (which deletes lines from the very function this branch also edited) and the terminal's
    dirty-flag repaint gate. Their failure mode is a stale or mis-drawn frame, and this container
    has no display. **They belong on the device pass, and are named rather than cleared.**
  - Everything else is additive or outside this subsystem. The palette is new slots plus two
    things to check once: black gains its own bright slot, which changes an existing symbolic
    combination, and an out-of-range index now raises where it was tolerated.
- **What it costs:** measured by **building the whole stack and running it** — the branch, the
  editor rework, then this line: **1108 passing / 22 failing, and the 22 are the same 22 the
  editor rework already owed.** This line adds **no new failure**. Its own two casualties were
  positional call sites assuming the constructor shape the rework changed, mechanical and fixed in
  place. What needs hands: the console model, an **add/add on the colours example** (the same file
  by two routes, 245 lines against 247), `.gitignore`, the one-line exit routing, and one surface
  decision.
- **Provenance: not ours.**
- **Deferred by decision, not by neglect** (2026-09-03): this release ships on the editor rework;
  the rest of the edge follows afterwards.

### The persistent corpus cites the rule chain, and the rule chain does not ship

- **Where:** 19 citations of `agents/…` from documents that survive the working tree, measured
  before this entry was written — `technical_debt/general.md` (9), `decisions/input.md` (5),
  `technical_debt/input.md` (4), `technical_debt/README.md` (1). The command below also returns
  this entry's own command and `conventions/docs.md`'s statement of the rule, which are
  illustrations and not citations, the same exemption the ephemeral-id rule's examples get.
  Both spellings occur, bare (`agents/rules/ledgers.md`) and
  relative (`../../../agents/rules/ledgers.md`), so **the relative form is where a bare-path grep
  undercounts** — the same trap the ephemeral-path sweep fell into twice.
  **Re-derive:** `git grep -nE 'agents/' -- doc/ CHANGELOG.md ':!doc/development/wip/'`. Do not
  cite this count; it is here to size the entry.
- **Why it is debt now and was not yesterday, and why the entry is not simply "19 sites".** The
  owner ruled on 2026-09-03 that `agents/` is not in the persistent corpus — *"a working surface
  that is not promoted upstream"* — and then **refined it the same day**: the tree **splits**.
  *"Generic rules like commenting and code guides and doc formatting may survive; workflow and
  pointers and operational limitations (git rules) should not — they are local to my work."* So a
  citation into `agents/` is a defect **only if its target is on the local side of that split**,
  and the split does not run along file boundaries everywhere (`rules.md` is a code guide **and**
  carries the commit conventions).
- **The citations, by target, measured at `1299ed2b` before this entry was written:**

  | target | sites | survives? |
  |---|---|---|
  | `agents/rules/ledgers.md` | 9 | **owner call** — it governs the three ledgers, and the ledgers ship |
  | `agents/rules.md` | 4 | **likely** — a code guide, except its commit-convention half |
  | `agents/validation.md` | 3 | **no** — a boot pointer for this phase; these are confirmed defects |
  | `agents/rules/roadmap.md` | 2 | **owner call** — plan shape, and the plan is `wip/` |
  | `agents/development.md` | 1 | **no** — workflow; confirmed defect |

  **Four are defects under the ruling as it stands; eleven wait on two calls.**
- **The heaviest shape is the one that matters most.** Most of these are the debt register's own
  *"The rule it fails: `agents/rules/ledgers.md` §3"* lines — the sentence a reader needs to
  understand why an entry exists. They are not decorative pointers, so the repair is the
  `FR-n` treatment rather than deletion: **name the rule and state what it says**. That repair is
  also **immune to the split**: a citation that states the rule survives its target either way,
  which is an argument for doing it to all of them rather than waiting on the two calls.
- **Provenance: ours.** Neither the rule chain in this shape nor these registers exist at the PR
  base `3256aac`.
- **Found:** 2026-09-03, immediately after the ruling that created the class.
- **The same two calls decide `Set 2` of the slice cut, and that is the third standing question
  this entry now holds** (moved here 2026-09-05, S74 delivery review F4). `PR-01-01` cuts
  `agents/` as **Set 2** — `git ls-files agents/ | wc -l` → **15 files** — and the 2026-09-03
  ruling makes that a *scope* decision rather than a routing rule: the same split that decides
  whether a citation into `agents/rules/ledgers.md` is a defect decides whether that file is in
  the slice. **One answer settles all three.** The questions travelled in session prompts' *"Left
  open"* from session70 and stopped propagating at session74, which is the failure
  `T-EPHEMERAL-IDS` names; they are recorded here because a prompt chain breaks and a ledger does
  not. `PR-01-01` cross-references this entry.
- **They do not gate `MERGE-01-05`** (answered 2026-09-05, the conditional the owner set on the
  watch). The import touches `src/`, `tests/`, `doc/EDITOR.md` and `README.md`;
  `git diff --name-only af9a5782 f4cf338c -- agents/` → **empty**. The slice cut runs after the
  closing block, long after the import, and nothing in the merge makes the scope call harder.
- **ANSWERED, and the answer replaced the question (owner, 2026-09-06).** All three standing
  questions are settled at once, and not by picking a side of the split: *"Actually we have code
  conventions in docs. Before slicing lets run a separate DOC step to see if anything else
  permanently useful is under `agents/`, lift it into persistent docs, than omit `agents/` and
  `AGENTS.md`, `CLAUDE.md` from release."* So **nothing under `agents/` ships** — not
  `agents/rules/ledgers.md`, not `agents/rules.md`, not `AGENTS.md` or `CLAUDE.md` — and the
  material that deserves to outlive this feature is **lifted into `doc/` as prose** beforehand.
  **The table above is therefore superseded as a routing question**: every one of the **nineteen** sites the table lists
  is a citation into a file the release will not contain, which is the *worse* half of the class
  rather than the milder one, because such a citation reads as authoritative and resolves to
  nothing. The repair the entry already named is the one that applies, now to all of them: **state
  what the rule says instead of pointing at where it lives.**
- **Now slugged: `DOC-01-10`.** The call the entry was waiting for has been made, so the commitment
  follows it. That row runs immediately before the slice cut and owns all three parts — the read for
  what is worth rescuing, the lift, and the omission — and it also makes `PR-01-01`'s `Set 2`
  question moot rather than answered.
- **Re-derive the two counts rather than quoting the table above**, which was measured at
  `1299ed2b`: `git grep -o "rules/ledgers.md" -- doc/ ':!doc/development/wip/' | wc -l` → **12**
  at 2026-09-05, and `git grep -n "rules/roadmap.md" -- doc/ ':!doc/development/wip/'` → **4**,
  all in this file. Both moved since the table was written; the table sizes the entry, the
  commands answer it.

### `@field` annotations disagree with their own constructors in at least three files

- **Where:** `src/model/editor/bufferModel.lua:125` — `@field replace_selected_text function`
  names a method that was never implemented (the real one is `replace_content`, called from
  `editorController.lua`). `src/view/editor/bufferView.lua:31` — `@field buffers
  Dequeue<BufferModel>` is never assigned or read; the runtime field is singular `self.buffer`.
  `src/view/editor/visibleStructuredContent.lua:19` — `@field size_max integer` is declared on
  the class but only ever exists nested at `self.opts.size_max`.
- **Why it is one entry and not three:** three independent files, the same defect shape, found by
  one pass that was looking for something else. That is the signature of a class rather than a
  set of typos, and the likely mechanism is visible in the third instance — a constructor
  refactored to take an options table without the annotations following it.
- **Why it matters more than a stale diagram:** an `@field` is read by the language server, so a
  wrong one is offered as a completion and type-checked against. It misleads a reader, an editor
  and an agent, and unlike a diagram it sits in the file being changed.
- **Provenance: NOT ours, and identical at the PR base `3256aac`** — all three annotations are
  byte-for-byte the same there. This is the platform author's code and the entry is recorded, not
  claimed: the standing practice is to measure against the base first and not to refactor another
  author's subsystem on the way past.
- **Also seen, same pass:** `love.state.app_state` takes the value `'snapshot'`
  (`consoleController.lua`), which is real, current, pre-existing, and absent from the `AppState`
  alias in `types.lua` **and** from both FSM diagrams. Same category — a declaration that does
  not match the code.
- **Found:** 2026-09-02, by the `doc/mermaid/` audit commissioned for `FIX-02-24`, out of that
  audit's scope and seen in passing. The audit was looking at diagrams; these are in the source it
  checked them against.
- **Not slugged** — pre-existing, not this release's to pay, and an upstream conversation rather
  than a branch task.

### Line citations across the persistent corpus are unverified, and a fifth of the checkable ones do not resolve

- **Where:** every `doc/` file outside `wip/` that cites source by line —
  `technical_debt/input.md` (24), `internals/user_input.md` (19),
  `internals/event_dispatch_layers.md` (17), `internals/project_sandbox_env.md` (6),
  `internals/editor.md` (4), `tests.md` (3), this file (2), `internals/console.md` (2),
  `internals/examples/repl.md` (1), `drawing_system.md` (1). 77 distinct `file.lua:N` references.
- **State, measured 2026-09-01:** 62 resolve to a basename unique under `src/`; the other 15 name
  files that exist in several repos (`main.lua`, `input.lua`, …) and were not checked at all.
  **Of the 62, fourteen — 23% — land on a blank line or a bare `end`.** That is a floor, not the
  count: a drifted citation can also land on plausible code, which is how
  `userInputModel.lua:487` passed as a history-restore `set_text` while pointing at
  `self:clear_input()`.
- **Why it matters:** this is `T-DEC-NUMBERED`'s sibling. A citation by a coordinate that moves
  **resolves to the wrong thing instead of dangling**, so it reads as authoritative and greps
  clean — the argument `agents/rules/roadmap.md` §2 makes for ids in code, and
  `agents/validation.md`'s *"Comment References"* makes for section names. Line numbers are the
  same hazard with no mitigation at all: nothing in the workspace can tell you one has drifted.
- **How it happens is ordinary, not careless:** the six corrected under
  `input.md`'s *"Six line citations into `userInputModel.lua` were stale on arrival"* were written
  in the very commit that shifted them, by a session that had verified each one before its own
  unrelated edit moved the file. No sweep catches that; only not citing lines does.
- **A worked instance of the worse mode, found 2026-09-02 at `FIX-02-06`:**
  `internals/event_dispatch_layers.md`'s Layer-2 section cites `controller.lua` by line about a
  dozen times and **every one checked was wrong by roughly 110 lines** — `:854-860`, offered as
  `set_default_handlers`'s internals, lands in the profiler helpers; `:234-297` and `:974-982` name
  the wrong functions; `main.lua:389-390` and `consoleController.lua:1033`/`:1130` land in
  unrelated code. None of them dangles. All of them read as authoritative, which is this entry's
  point made in one document. The three that carried a claim being corrected were replaced with
  symbol names; the rest were left, because they are this entry's work and not that row's.
- **The fix is the one the corpus keeps re-deriving:** cite the **function or section name**.
  Where a line is genuinely the point, cite the name and quote the line's text so a reader can
  grep it. Sizing is real work — 77 references, and the 15 example-repo ones need the repo
  identified before they can even be checked.
- **Provenance: mixed and mostly ours.** The corpus is `#77`'s own creation (at
  `wip77/20260826/mergebase`, `doc/development/` holds five entries), but the practice of citing
  by line predates the feature and is not confined to it.
- **Not slugged** — no commitment to fix before release; that is an owner call. If taken it is a
  `FIX` row, and it belongs beside `FIX-03`, which runs late for the same reason: a citation
  sweep run while the tree still moves is run twice.

### The conventions the examples demonstrate carry no test coverage

- **Where:** `src/examples/` and the nested example repos. No example anywhere
  in this codebase has spec coverage; the suite exercises the framework and
  never an example.
- **State:** the gap has teeth because the examples are not only samples — the
  guide points at them and projects copy them, so a convention that rots in an
  example rots in every project derived from it. `T-TURTLE-DUP` is the worked
  case: `turtle` double-handled its own keys for months while the suite stayed
  green, and its fix is likewise pinned by nothing. **End-to-end testing of
  examples is overkill and is not what is owed here** (owner, 2026-08-30).
  What may be worth pinning is the narrow set of conventions the examples
  *share* and the documentation *relies on* — the `is_shown` guard on a native
  handler, the one-shot echo guard on a trigger key, `after_submit` hiding the
  widget once per command — each of which is a documented promise today with no
  test behind it at the point a project author would copy it.
- **Why it stands:** deliberately deferred past this release (owner,
  2026-08-30). Building it means a test genre this codebase does not have —
  driving an example's own `love.*` handlers through the framework's dispatch
  — and inventing that genre inside a defect row is how a defect row becomes a
  project. The framework side of each convention *is* already covered; what is
  missing is the example side.
- **Revisit:** when an example convention next breaks silently, or when the
  examples are next reworked as a set. **No roadmap row points here on
  purpose** — it is out of release scope, and a row would claim otherwise.

### The test suite passes only in declaration order

- **Where:** the whole suite, not one file. `busted tests` is green; `busted tests --shuffle`
  fails 29–55 rows per run, varying with the shuffle. Concentrated in `input model spec`
  (~23 rows), `Editor #editor` (~10) and a few `Dequeue` rows, but the set is not stable
  between runs.
- **State:** pre-dates any current feature work. Checked against the PR base `3256aac`,
  before the input-API branch existed: **674/0/0/0 ordered, 29–48 failures shuffled** — the
  same condition at a third the suite size. So rows leak state into their successors
  somewhere below the per-file boundary busted insulates (`insulate` restores `_G` and
  `package.loaded` per spec file, not mutations to a required module's own tables).
- **Why it stands:** every run anyone makes — local, CI, `busted tests` — is in declaration
  order, so it costs nothing today. Finding the leaks is a suite-wide investigation across
  subsystems that no single feature owns, and it would be started for a property nothing
  currently depends on.
- **Revisit:** before enabling `--shuffle`, test sharding, or any parallel runner in CI —
  each of those turns this from dormant into a source of false failures. Also worth a pass
  whenever a subsystem's fixtures are next reworked, since the leaks are fixture-shaped.

### The console's terminal self-test is unreachable

- **Where:** `src/controller/consoleController.lua` — `terminal_test`'s opening guard,
  `love.state.app_state ~= 'ready' or love.state.app_state ~= 'project_open'`. A state
  cannot be both, so the disjunction holds for every value and the function always returns
  before its body.
- **State:** the whole feature is dormant. `Ctrl+Alt+T` in DEBUG does nothing;
  `util/test_terminal.lua` is never called, so `love.state.testing` is never set and its
  readers — the `'running'` / `'waiting'` branches in `ConsoleController:keypressed` and
  `src/view/input/statusline.lua` — cannot fire. Present at the PR base `3256aac`, so it
  pre-dates the input-API branch and no current work touches it. The intent reads as `and`.
- **Why it stands:** a developer-facing self-test with no caller in normal use; nothing
  observable regressed when it stopped running, which is why it went unnoticed. Fixing the
  operator re-animates a display path nobody has exercised in months — worth doing
  deliberately, with a look at the output it paints, rather than as a drive-by.
- **Revisit:** when the console's debug affordances or the terminal widget are next worked
  on. Fix is one operator; the work is confirming the revived path still renders sensibly.

### `string.split_array`'s type guard never fires

- **Where:** `src/util/string/string.lua:241` —
  `if not type(str_arr) == 'table' then return {} end`.
- **State:** operator precedence makes this `(not type(str_arr)) == 'table'`,
  which is `false == 'table'`, i.e. **always false**. The guard never returns
  early, so a non-table argument reaches `ipairs(str_arr)` and raises there
  instead of being handled. The intended form is `type(str_arr) ~= 'table'`.
- **Why it matters beyond the typo:** `string.lines` delegates every list to
  this function, and `UserInputModel:set_text` delegates to `string.lines`, so
  the guard sits on the input widget's content path. It is **latent, not live** —
  every current caller passes a table — which is why this is BACKLOG.
- **Provenance: pre-existing**, another author's utility module. Found by the
  cold peer review of `BUG-02-01`, 2026-09-01, while checking how a non-string
  element is handled.
- **Not slugged**, and **no size refactor implied** — the fix is the two
  characters that make the guard mean what it says.

### `table.protect(love.handlers)` is a no-op on the passed table

- **Where:** `src/controller/controller.lua` — end of `setup_callback_handlers`.
- **State:** `table.protect` returns a read-only proxy but does not mutate the original
  table; the call's return value is unused, so `love.handlers` is not actually protected.
- **Why it stands:** No observed breakage, and the proxy-vs-mutate semantics are a broader
  `util/table` question.
- **Revisit:** If/when read-only enforcement on `love.handlers` is actually wanted — either
  consume the returned proxy or change `table.protect`'s semantics.

### The imported editor rework changes three view files that nothing on this branch can smoke

- **Where:** `src/view/editor/bufferView.lua` (+46/−1), `src/view/input/userInputView.lua`
  (+10) and `src/view/input/statusline.lua` (−1) — the drawing changes that arrived with the
  editor rework imported at `21eb7f53`. Re-derive with
  `git diff --stat af9a5782 f4cf338c -- src/view/` → **3 files, +55/−2**
  (`af9a5782` is the base the rework was taken against, `f4cf338c` its head).
  Second half of the same gap: `doc/development/smoke_checklists.md` has **no step that
  enters the platform's own editor**. `grep -in editor doc/development/smoke_checklists.md`
  returns hits that are all the maze project's *editor level* — a game level whose widget is
  the project's, not the platform editor's buffer view.
- **State:** the suite runs headless against `mock_love`, with no display, so a drawing
  change can neither fail it nor pass it. `busted tests` green at 1123 / 0 / 0 / 10 is
  silent about all three files: a stale, clipped or mis-drawn frame is invisible to every
  automated check this repository has. Nothing here is a known defect — the point is that
  *known* is not available, in either direction, until a human looks at a screen.
- **Why it stands:** the rework's surface is its author's to smoke, and this branch imported
  it rather than wrote it. Writing checklist steps for it means stating what those frames
  are *supposed* to look like, which is the rework author's product knowledge and not ours;
  inventing our own expectations would smoke our guesses rather than their design.
- **Revisit:** when the device smoke passes are next run on real hardware — that is the only
  instrument that can clear this, and the pass should meet it as a decision (run an editor
  section, or record that the imported surface ships unsmoked and by whose call). Also
  revisit if this branch itself edits any of the three files, which would make the residual
  ours rather than the rework author's.

## RETIRED

### Editor submit raises when no buffer is open (RESOLVED, 2026-09-30)

- **Where:** `src/view/editor/editorView.lua` `get_current_buffer` — `local bm =
  ctrl:get_active_buffer()` is indexed unguarded on the next line.
  `EditorController:get_active_buffer` is `self.model.buffers:first()`, which answers
  **nil** when the buffer list is empty. Two more call sites index the same nil the same
  way: `get_active_buffer_id` and `_generate_status`.
- **State:** reproduced deterministically, not observed once. The harmony scenario
  `editor.open-close` — `project("create")`, `edit()`, then **Ctrl+Shift+S** — raises
  `editorView.lua:70: attempt to index local 'bm' (a nil value)` through
  `editorController.submit` ← `_normal_mode_keys` ← `keypressed`. The buffer list is empty
  at the moment the key is handled; **why** it is empty right after `edit()` on a freshly
  created project is *not* diagnosed here.
- **Not a feature regression:** the full scenario suite was run against two trees — with and
  without the input feature's in-flight widget-lifetime change — and produced the same error,
  at the same line, once each, in logs of identical length. It predates that work.
- **Why it is filed and not fixed:** it is outside the input subsystem and outside the
  feature that found it; fixing it means deciding what submit *should* do with no buffer
  (no-op, or refuse earlier), which is an editor design call.
- **No test covers it.** `busted tests` is green, so the suite never submits without a
  buffer — the gap is what let a deterministic raise sit unnoticed in a scenario that runs
  every time the harmony suite does.
- **Revisit:** when the editor's buffer lifecycle is next touched. A guard in
  `get_current_buffer` alone would only move the nil one frame later; the three call sites
  and the "what does submit mean here" question go together.
- **Resolution.** The buffer list was empty because the key that emptied it was still being
  handled. `Ctrl+Shift+S` closed the editor in `_leave_keys` (`finish_edit` drops the buffers),
  and `EditorController:keypressed` then passed the same `s` to the mode's handler, whose
  `submit` asks for the current buffer on every key. Any press of the chord in navigation or
  editing raised; `edit()` on a fresh project was incidental. `keypressed` now returns once
  `_leave_keys` has left. `Shift+Esc` on the last buffer closed the editor the same way, and
  under `DEBUG` the `love.debug` block after it indexed the missing buffer on every key; it now
  asks for the buffer on `F5` alone. The three indexers stay unguarded: no key reaches them
  once the editor has closed. `tests/input/input_editor_keys_spec.lua` drives both exits through
  the real `finish_edit`, and pins that the chord's key reaches no mode handler after it.

### T-PR45-ASK-UPSTREAM — two contradictions inside PR #45, to put to its author (RESOLVED, 2026-09-06)

**RESOLVED WITHOUT BEING ASKED — nothing goes to #45's author (owner, 2026-09-06).** The hold below
was released by `OP-03`'s judgement the same day, and the owner then closed the entry on an answer
already in hand: *"I provided complete answer from author already."* Both questions are settled by
his attestation, and neither is settled the way this entry predicted:

- **Question 2 is answered and the entry's own reading is overturned.** `Ctrl+Shift+S` is
  **inherited cruft that predates the editor spec and nobody owns** — not a deliberate retirement.
  The entry argued from the force-push's shape that dropping the documentation row was more likely
  intentional; it was neither intentional nor accidental in the way either side guessed. He is
  raising the chord's gate bypass **with @dsent himself**, so the follow-up is his, not ours.
- **Question 1 is moot rather than answered.** He describes `Ctrl+S` as reserved and intercepted at
  the **application** level, never reaching the editor controller, and says **nothing about a
  checkpoint** — so the *"reserved for the checkpoint"* comment remains unsupported by its own
  author's account of the code. **The question changes owner**: it is a product decision @dsent has
  already stated a direction on, and its implementation belongs to the rework rather than to this
  release. `MERGE-01-08` is ruled without it.

**What we asked for and did not get is worth recording:** confirmation of the comment. What we got
instead is the routing contract we did not have, which is the more valuable thing and which
`D-EDITOR-KEYS` now carries.

*Prior state —* **HELD — DO NOT ASK YET** (owner, 2026-09-06, withdrawing the date the morning it
came due): *"I am not asking Vadim until I fully understand the merge impact, its reasons and
possible mitigation."* **`OP-03` releases this entry**; until then it is a filed question, not a
pending message. The reason is on the entry itself, below, as `A3`: **#45's comments and tables lag its
own behaviour as a habit**, so asking from a half-understood premise is how the last false premise
got into this corpus. *Original framing: ask on the morning of 2026-09-06 (owner, 2026-09-05).* This entry exists to be a reminder with
its evidence attached, so the questions are asked from facts rather than from memory. **#45 is
Vadim1987's** — 7 of its 9 commits, including the one that created both contradictions
(`5125d360`, 2026-07-11, *"explicit nav/edit modes and the key semantics of the rework spec"*).
`git log af9a5782..f4cf338c --format="%an" | sort | uniq -c` → 7 Vadim1987, 2 dsent.

**Question 1 — bare Ctrl+S: is the comment wrong, or the binding?** `controller.lua`'s editor
branch says *"bare Ctrl+S is reserved for the checkpoint (rework spec 2.6)"*, but the checkpoint is
**`Ctrl+K`** (`checkpoint_key()` returns early unless `k == 'k'`) and #45's own `doc/EDITOR.md`
gives `Ctrl+S` exactly one row, ***"Stop project"***. **The comment has been wrong since the first
push** — `git show 16eb33d7:src/controller/controller.lua` at `:592` is byte-identical, so this is
not force-push collateral. *What we need to know:* was freeing the key deliberate, and if so, is
anything meant to claim it? **We had `close_buffer` there and gave it up on the strength of that
comment** (`technical_debt/input.md`, `T-CTRL-S-UNCLAIMED`; `MERGE-01-08`).

**Question 2 — `Ctrl+Shift+S` is now bound and undocumented.** Old #45's `doc/EDITOR.md:79` carried
*"Leave editor (close all buffers) — `Ctrl+Shift+S`"*. **The force-push dropped that row and kept
the binding** (`Key.shift()` → `CC:finish_edit()`, unchanged). *What we need to know:* is the
spelling being retired, or did the row fall out during the reshape? **This is not idle** — it is
the key our `EditorController:_leave_keys` supplies, so we are either matching them or holding open
a door they mean to close.

- **Evidence that Q2 is likely accidental:** **the edge still documents it.**
  `git show 5a52cba2:doc/EDITOR.md` line 79 carries the row, and
  `git diff --name-only 16eb33d7 5a52cba2 -- doc/EDITOR.md` is **empty** — the edge inherited old
  #45's file untouched. So the de-documentation exists **only** in the force-pushed head, and it is
  newer than anything on dsent's integration line. **The edge's `controller.lua` carries the
  identical Ctrl+S block**, comment included, so on the edge the same contradiction sits beside a
  doc that still documents the other half.
- **Neither question is ours to answer**, and neither is a defect in our tree: our behaviour is
  green and pinned either way. What is at stake is a **reason of record** and a **key we conceded**.
- **Provenance: not ours.** Upstream work by another author.
- **`A3` — the pattern behind both questions, and the reason for the hold.** Old #45's keymap
  tables were **stale against old #45's own code** (they showed `Alt+Home` for *"jump to line
  start"* while `userInputController.lua:687` already read *"bare Home/End are line-scoped"*), and
  the force-push corrected the tables while changing **no executable content at all**. So Q1 and Q2
  are instances of **one habit — documentation and comments lagging behaviour** — rather than two
  accidents, and **that is what has to be established before either question is worth asking.**
- **How the habit was established, since the claim carries this entry:** each source file's
  non-comment lines were sorted before and after #45's force-push and compared. The two sets are
  identical — the push rewrote two documentation tables and changed **no executable content**. So
  the tables were stale against their own code, and correcting them is what the push was for.
- **Roadmap:** `MERGE-01-09`, closed by this resolution rather than executed. **The entry's own
  retirement condition is what fired** — *"retire this entry when the answers land, and record them
  on `T-CTRL-S-UNCLAIMED`"* — with the one twist that the answers landed **without the questions
  being sent**. The `Ctrl+S` half is recorded on `T-CTRL-S-UNCLAIMED`, which is where the decision it
  feeds lives; the `Ctrl+Shift+S` half is on `T-LEAVE-KEYS-LOSES-BLOCK` and `OP-04`, because what it
  turned into is a data-loss question rather than a documentation one.

### T-DRIFT-PR45 — this branch does not sit on the editor rework it will ship beside (RESOLVED, 2026-09-05)

- **Where:** the platform repo. Our branch and the upstream editor-rework pull request
  (*"Editor rework: explicit modes, line navigation, durable accepts, undo/redo"*, head
  `16eb33d7`) share a base of 2026-07-09 and have diverged since. The rework is **52 commits, 20
  files, +3018/−377** across `src/` and `tests/`; **11 of those files are ones this branch also
  changed**.
- **State:** the two are **compatible, and this is measured rather than argued.** A trial merge in
  a throwaway clone, resolved and run, gives **1100 passing / 22 failing** where this branch alone
  gives 1055/0 and the rework alone gives 753/0. **No failure is in the `compy.input` surface** —
  the public API, the routing grid, the hooks and shortcuts tables, the widget's configuration and
  every non-editor lifecycle case pass unchanged.
- **Blast radius — the editor route's key semantics, and nothing wider.** The rework introduces
  explicit navigation/editing submodes, so typing no longer inserts by default; it rewrites Enter
  handling around block accept; it redefines Escape; and it reassigns the Ctrl+S family. Six of
  this branch's specs pin the behaviour it replaces. Five of those are **re-pins** — the rework is
  entitled to change them — and exactly one is a genuine two-answers-one-key conflict: **bare
  Ctrl+S in the editor**, which closes the buffer here and is reserved for the rework's checkpoint
  there.
- **What it costs, itemised:** one **integration point** — the rework reaches into the framework's
  power-shortcut block, which this branch restructured into a privileged reservation table, so its
  editor reservations become entries in that table; one **mechanical signature merge** on the input
  model's constructor, which both sides changed; one **key-meaning decision** (bare Ctrl+S); one
  resolution of the editor controller, whose rewrite is a superset of our edits there; and **five
  spec re-pins**. It also **forces a repeat of the on-device pass** for anything that types in the
  editor, because the keys move.
- **Settled by measurement, not preference:** `set_text` was rewritten by both sides. Keeping ours
  and adding the rework's one-line history reset gives 1100/22; taking theirs gives 1094/28, the six
  extra being this branch's own content contracts. **Keep ours.** The two test harnesses are also
  **not interchangeable** — adopting the rework's `tests/mock.lua` wholesale adds 145 errors here
  and fixes none of its own failures.
- **Provenance: not ours.** Upstream work by another author, on its own timeline.
- **Revisit: it is release work, not deferred debt.** The decision of record (2026-09-03) is to
  build on the rework so the two ship together.

**Resolution (`MERGE-01-05`, 2026-09-05).** The import landed and the tree is **green at
1123 / 0 / 0 / 10**. Every itemised cost above was paid, and three of the entry's own figures
were wrong by the time it was executed — which is the transferable part, not the outcome:

- **The head it names is gone.** `16eb33d7` was force-pushed away; 52 commits became **9 on top
  of `dev`**, and the content moved with them (4 files, +317/−327). The **four conflicts and the
  resolution table survived unchanged**, so the entry's analysis held even though its
  measurements did not.
- **"1100 passing / 22 failing" was an artifact of the trial's probes**, which took one side
  wholesale in two files. Resolving those two deliberately gave **6** failures, and all six
  closed: one was a mechanics break in *their* spec (a widget that is never shown takes no
  keys), and five were ours to re-pin.
- **"Five spec re-pins" and "one integration point" were both off.** The re-pins were five, but
  one of them turned out to be a **behaviour change rather than a renaming** and is now
  `T-NAV-ESCAPE`. And there was **no integration point at all**: the rework's editor
  reservations did *not* need to enter our `RESERVED` table — expressing them there contradicts
  `D-EXACT-RESERVE`'s own scope, and the correct resolution leaves `controller.lua`
  **byte-identical to its pre-merge state**.
- **The key-meaning decision was taken as filed**: bare Ctrl+S is the rework's, ours no longer
  closes the buffer, leaving is `Shift+Esc` and `Ctrl+Shift+S`.

**Provenance for `LEDGER-02`: NOT OURS** — upstream work by another author, and the debt was the
distance to it. Classified here per `T-NEVER-SHIPPED`'s rule that an entry retired after
2026-09-05 is classified by the session that retires it.


### The register's resolved entries claim resolution that was never verified (RESOLVED, 2026-09-03)

**Filed as `T-RETIRED-UNVER`.** Everything down to **Resolution** is the filing as written.

- **Where:** `input.md`'s `RETIRED` section — 21 entries carrying a `RESOLVED` marker **when this
  was written; the section holds 46 today and the whole of it is this row's scope** (`T-NEVER-SHIPPED`
  takes the same pass). Re-derive before executing.
- **What is owed:** the 2026-08-27 restructuring sorted them on their **headings**. Not one was
  tested against the PR base to confirm the claim. A register whose retired section is unaudited
  is a register that quietly forgets things it never finished.
- **Why it is an entry:** an **obvious operational need**, and the register's own upkeep is debt
  like any other (`agents/rules/ledgers.md` §4). Expected yield is unknown, which is the reason
  to run it rather than to skip it.
- **Roadmap:** `FIX-02-05`.
- **Resolution.** **56 entries walked**, 2026-09-03 — and the section held **59 by the time that
  was written**, which the peer review caught and this bullet now states. The walk's snapshot was
  `input.md` 50 + `general.md` 6, taken when the pass began; **three more were retired while it ran,
  all of them by this same session**, so the sweep could not have seen them and the *"every retired
  entry"* claim was already an overstatement when made. The three, with their resolutions, which
  need no re-derivation because this session performed them: the **`eval`-key migration** entry
  (rows dropped from the guide, clause dropped from the CHANGELOG), **`T-VERSION-NUM`** (owner ruled
  the version question; the break note landed and all three markers are gone), and **this entry
  itself**, which the row retires — walking itself is not a check. **Two more have retired since**
  (the deletion-invisible removal, and `turtle.md`'s pre-`auto_hide` mechanism), so the section
  stands at **61** at the time of writing, with **five** entries outside the walked set. **All five
  are `INTRODUCED-IN-BRANCH` and the check is not close:** every one is about `CHANGELOG.md`,
  `doc/input_api.md`, this register, or `auto_hide` — three of those four do not exist at
  `3256aac` at all, and `auto_hide` is this feature's.
- **The lesson is about verification passes generally, not about this count.** A pass whose subject
  **grows while it runs** must state *the snapshot it walked*, not *the section* — otherwise its
  completeness claim decays the moment the next entry lands, and the pass's own author is usually
  the one landing it. Two questions per entry, run as one pass: does the resolution claim hold at
  HEAD, and did the subject exist at the PR base `3256aac`. Evidence was recorded per entry, with the command
  behind every answer.
- **No resolution claim failed.** Twelve rest on something not independently re-derived — a suite
  run, a mutation example, a call graph deeper than a grep reaches — and each is named there
  rather than counted as verified. **One numeric drift** was found and corrected
  in place: `F.reset()`'s entry said nine code lines; it is eleven, still under the limit.
- **The classification, which is the half `LEDGER-02` and `CHG-01-03` consume:**
  **39 introduced-in-branch · 9 pre-existing · 5 mixed · 3 cannot-tell.** The proportion is not
  padding — the *subject* of most entries (`compy.input`, `doc/input_api.md`, the combo grammar, the
  decisions ledger, the whole `wip/` tree) is itself absent at base, so a defect in it could not
  have been met from outside. `compy.input` returns **zero** hits at `3256aac`.
- **The three cannot-tells are structural, not gaps:** their subjects live in `src/examples/maze`
  and `balloons`, untracked sibling repositories with their own histories, so there is no comparable
  base commit to check against. Their resolution claims hold; only the provenance question is
  unanswerable by this method.
- **Nine were spot-verified by the parent directly at base**, the pre-existing set being the
  consequential direction — a false *pre-existing* invents a changelog line for something nobody
  met, a false *introduced* deletes the evidence of a real fix. All nine confirmed:
  `set_text`'s `n_added == 1` guard and its unsplit table branch, the string branch's lone
  `_update_cursor(true)`, `xpcall(f, user_error_handler, ...)` and the `_G.web` branch in `wrap`,
  `handlers.userinput` with its two push sites, `love.state.app_state == 'editor'` in
  `UserInputController:keypressed`, `userlove`, and the `love.draw` swap.
- **Roadmap:** `FIX-02-05`, done.


### The changelog's version number has never been settled against the scale of the change (RESOLVED, 2026-09-03)

**Filed as `T-VERSION-NUM`.** Everything down to **Resolution** is the filing as written.

- **Where:** `CHANGELOG.md`, and three independent askers — the file's own `REMARK:`,
  `doc/development/internals/user_input.md:470`, and
  `doc/development/conventions/../internals/project_sandbox_env.md:71`.
- **What is owed:** the tree calls itself `1.0.0-rc`, and the input work removed four public
  globals with no shim. Whether an rc number is honest against a break of that size was never
  ruled. Three places ask; none answers.
- **Why it is an entry:** an **obvious operational need** — a version number is the first thing
  an upgrader reads, and it is not settleable after the release it labels.
- **Roadmap:** `CHG-01-04` is the task. The rest of `CHG-01` was done by the ledger
  restructuring (2026-08-27); this part was not.
- **Resolution — ruled by the owner, 2026-09-03: keep `1.0.0-rc`, and announce the break in
  prose.** *"1.0.0-rc + explicit break note."* `CURRENT_SCOPE` now opens with a note naming both
  breaks — the removed globals, and `on_text_entered`'s payload, *"the quiet one, because a callback
  that indexed the old payload keeps running and starts reading `nil`"* — and saying why the number
  does not move: nothing before 1.0.0 promises a stable surface, so the announcement belongs in the
  file an upgrader reads rather than in a digit. **All three askers are answered and all three
  markers are gone**: the CHANGELOG's own marker above its H1, and the two that asked for a
  concrete availability reference — `internals/user_input.md` (the editor-migration paragraph now
  says *"the input API (1.0.0-rc20260712)"*) and `internals/project_sandbox_env.md`
  (`compy.before_exit` *"exists and is wired since 1.0.0-rc20260712"*).
- **One correction to the filing, found on the way** (`FIX-02-17`, 2026-09-03): it says the work
  removed **four** public globals. It removed **five** — `input_text`, `input_code`,
  `validated_input`, `user_input`, `write_to_input` — plus the debug-only `astv_input`, and the
  count disagreed three ways across the corpus (this entry said four, `CHANGELOG.md` said five,
  `doc/development/tests.md` said six). Established by differencing `project_env`'s assignment keys
  at `3256aac` against HEAD, and the CHANGELOG now names all six. **The ruling is unaffected** — it
  was made against a break of that size either way.
- **Roadmap:** `CHG-01-04`, done.


### A renumber shipped its crosswalk without the sweep, and five citations resolved to the wrong pass (RESOLVED, 2026-09-02)

- **Where:** `ROADMAP.md` (two citations at `:1416` and `:1425`, found by the cold
  revalidation after the first sweep reported clean) and the feature's working tree —
  `validation/plan.md` (the duplicated `ACC-02` table, the coverage-gap heading and its
  instruction), `validation/outcomes/BUG-01-03-turtle-fix-peer-review.md`,
  `validation/reviews/FEAT-02-delivery-revalidation.md`.
- **The scope error, recorded because it is the reusable half:** the first sweep was scoped
  to `validation/` and `implementation/` on the assumption that the renumbering pass had
  cleaned the document it was performed in. **It had not**, and the roadmap is the one file
  guaranteed to cite every id. **A renumber's sweep starts in the document that was
  renumbered.**
- **The defect:** the 2026-09-02 acceptance split renumbered the smoke passes. `ACC-02-04`
  had been `maze` + `draw` and became `sapper`, so *"add rows for Track 2 before running
  `ACC-02-04`"* — a **standing instruction** about an unexercised upstream mechanic — came to
  name a different repo's pass. Nothing dangled and no grep complained, which is
  `../../../agents/rules/roadmap.md` §5's second failure mode: *a citation that still
  resolves, to a heading that no longer means what it did.*
- **The rule it fails is §2's own cheap branch:** *"renumbering is cheap. Ids live in a
  handful of planning documents; **sweep them**, ship the crosswalk, done."* The crosswalk
  shipped; the sweep did not. The blast radius had been measured as *"no `ACC` id appears in
  `src/` or `tests/`"* — true, and the wrong question, because **planning ids are cited from
  plans** (`ledgers.md` §3 says so of debt slugs for the same reason).
- **Resolution:** ids updated in the live documents; dated records keep their text with a
  bracketed note. `plan.md`'s duplicate row table is **deleted rather than renumbered** — it
  was a second copy of the schedule, which `roadmap.md` §1 forbids, and it is what let seven
  ids drift at once. The plan keeps the *why* the roadmap does not carry, and the roadmap's
  `maze` row now cites the Track-2 obligation that lived only in the plan.

### The `FIX-02` renumber's own citations were never swept (RESOLVED, 2026-09-02)

- **Where:** `wip/77-new-input-api/ROADMAP.md` — `:49`, `:1181`, `:1388`, `:1435`, `:1437`.
- **The defect:** an earlier `FIX-02` renumber (*"was 20, then 19 — the old `05` and `14`
  merged into `06`"*) left five citations naming **`FIX-02-01`** to mean the **remark**
  row, which is now `FIX-02-07`. `FIX-02-01` exists and is a different row — the two
  submit callbacks — and it is closed ✅, so every one of them resolved silently to the
  wrong thing. `roadmap.md` §5's second failure mode, and **pre-existing**: none of it was
  introduced by the 2026-09-02 splits.
- **The one with teeth:** `:1435` is a **parked question whose trigger had already fired
  on the wrong row** — *"the 14 remarks: ruled individually, or swept? · when `FIX-02-01`
  starts"*. The triage ran, answered it, and corrected the count to 37; the question sat
  open against a closed row that never had anything to do with it. `:1437`'s trigger
  (`FIX-02-21`) was likewise closed and answered.
- **Resolution:** the four citations repointed to `FIX-02-07`, the two parked questions
  marked ANSWERED with what answered them. **There is no `FIX-02` crosswalk** — that
  renumber shipped without one — so the sense was resolved from the rows' own cells, which
  is what §2 says a crosswalk exists to spare you.
- **Found by** a cold revalidation, 2026-09-02, not by the `ACC-` sweep one sprint over that was
  looking at the same file.

### `ledgers.md` still called unruled the question it had just ruled (RESOLVED, 2026-09-02)

- **Where:** `../../../agents/rules/ledgers.md` §6, closing paragraph.
- **The defect:** *"**Where** vacuumed entries go — dropped outright, or moved to an archive —
  remains unruled."* `cbd88b00` ruled it that morning, at §2 *"Vacuuming is a move, not a
  deletion"*, and left the older sentence standing. A live rule file gave opposite
  instructions in two places to whoever runs `DEC-02` or `LEDGER-02` next.
- **Resolution:** the paragraph now points at §2 and keeps the part that was §6's own — that
  the archive is a **record and not a second ledger**, which is the failure mode §6 exists to
  guard against.
- **The class, since a rule file is where it is most expensive:** an addition that answers an
  open question must **close the question where it was left open**. Searching for the question
  is how you find the sentence that will contradict you.

### The crosswalk pointed at a section deleted two hours after it was written (RESOLVED, 2026-09-02)

- **Where:** `../decisions/input.md`, the crosswalk's Decision 16 row and its closing
  paragraph.
- **The defect:** the row said *"What it ruled, and why the ruling fell, is in
  `D-ONE-LIFETIME`, **"what it reverses"**"*. That section was added at `e9a3501a` and removed
  at `cd1264da` when the owner refuted its premise — **two hours after the crosswalk cited
  it**. The prose forty lines above the table meanwhile said the entry *"left nothing
  behind"*, so the file contradicted itself. A second, smaller error sat in the closing
  paragraph: *"the seven that map to nothing are archived"*, where six are — Decision 19
  never existed to archive.
- **Resolution:** the row states the supersession and nothing more; the closing paragraph
  counts six and names the seventh.
- **Why the removal pass did not catch it.** `agents/validation.md`'s rule — *when you rename
  or remove a heading, grep `src/` and `tests/` for citations* — names **code**, and this was a
  doc citing a doc. `cd1264da`'s own message concluded *"Nothing is lost"*.
- **The sweep that does catch it, and it is cheap:** resolve every `*"section"*` citation in
  `src/`, `tests/` and the persistent corpus against the set of **headings plus bold lead-ins**
  — this corpus names sections both ways, and headings alone produce about forty false
  positives. Run over the whole corpus it returned exactly one real orphan: this one.

### The decisions ledger is cited by number — PAID by the conversion to names (2026-09-01)

- **Was `T-DEC-NUMBERED`.**
- **What was owed:** the conversion from numbers to mnemonic names. Under numbering a missed
  citation after any renumber still resolves — **to the wrong decision** — and reads as
  authoritative; under names it dangles visibly and greps out.
- **Paid by `DEC-01`.** 31 decisions carry a `D-` slug declared first in the heading, and
  `Decisions? [0-9]+` returns zero across `src/`, `tests/`, the persistent corpus and `agents/`.
  The crosswalk from every number the ledger ever issued is an appendix to the ledger itself, so
  it outlives the feature's working tree.
- **Sized at 165 citations across 18 files; it was 554 across 36**, and the gap was not drift.
  Three forms were invisible to the pattern the sizing used: **18 line-broken citations** with the
  number on the next line, 11 plural mentions, and **8 bare back-references** — a decision cited by
  number with no `Decision` word anywhere near it, all of them in a sentence unpacking a plural.
  `DEC-01-01` made every mention one greppable token before anything was rewritten, which is what
  the spec's sentinel gate was for and where the owner moved the burden when the sentinels were
  dropped.
- **It also discharged the tombstone condition.** `ledgers.md` §2 keeps retired entries *while the
  ledger is numbered*; six were vacuumed once that stopped being true, and the rule now says so.

### T-NAMESPACE-CLONE — a live platform table in a namespace travels to the project as a copy — PAID by a written practice

- **Where:** the project environment's construction — a deep clone taken before the run
  (`../internals/project_sandbox_env.md`) — and every namespace that hands a project a
  platform table.
- **What was owed:** the pattern written down. A live table placed in a namespace as a
  plain field is *copied* into the project's clone, so the program assigns its handlers
  into the copy while the dispatcher reads the original, and **neither side raises** —
  nothing is nil, nothing is logged, the handlers simply never run. It cost an hour of
  on-device debugging to find. `compy.input` already dodged it by holding the surface
  up-value behind `__index`, and `serial` was later built the same way per its author,
  assignment to the table itself included (that surface is not in this repository); what was missing was the rule stated once, where the next person
  to add a namespace field would meet it.
- **Paid by:** `../conventions/architecture_principles.md`, *"A Namespace Hands Out Live
  Tables by Reference, Never by Value"*. It is filed as a **suggested practice rather than
  a decision** (owner, 2026-08-30) on two grounds: the rule is generic — it binds any
  subsystem handing a project a live table, not the input surface — and a table that is
  genuinely a snapshot may be passed by value quite correctly, so the right instrument is
  a practice with a question attached (*does anyone write to this after the run starts?*),
  not a ruling. `decisions/input.md` D-FROZEN-SHELL carries the one-line pointer to it, which
  is where `serial`'s author suggested the note belonged; D-ONE-STATE-ASK records the same
  hazard met from the other direction (`love.state.user_input` read inside a project is
  always `nil`).
- **Retired 2026-08-30.** Nothing outstanding: the obligation was documentation, and the
  code already implements the pattern in both places it applies.
