# Mode: upgrade

*Loaded by the `spec` skill once the mode is settled. `SKILL.md`'s shared sections — output structure, core disciplines, statuses, validation — still apply; this file only covers what is particular to upgrade. Paths below are relative to the skill's own directory, not to this file.*

Bring a spec set written against an older version of this skill up to the current conventions. The specs are not wrong about the system — they are wrong about the format.

## When to use

- `validate.sh` fails on a set nobody has changed, because the checks are newer than the specs
- The set predates `changes/`, the `ADR/` folder, dated record filenames, or the `DATA_MODEL.md` split
- A spec set inherited from another project or another agent's conventions

## When NOT to use

- The code moved and the specs did not → **update**
- The set is conformant and you want new work specced → **change**
- There is no `specs/` folder → **infer**

## Additional principles

**`validate.sh` is the worklist.** There is no version marker in a spec set and there should not be one — a stamp says what a folder claims to be, the files say what it is. Read the files. Every finding is either mechanical or a question; nothing else is in scope.

**Mechanical means derivable, not merely tedious.** A fix is mechanical only when the correct result is already determined by something in the repo — the feature file, git history, the template. Everything else is a question for the user, however obvious it looks.

**Format only.** Upgrade never changes what a spec says. If a scenario is wrong about the system, that is an update, and it is out of scope here — note it and move on.

**Idempotent.** Running upgrade on an already-current set changes nothing and says so. Never rewrite a file that is already conformant, so `git diff specs/` shows exactly what moved.

## The two piles

Sort every finding before touching anything.

**Mechanical** — apply directly:

| Finding | Fix |
|---|---|
| `INDEX.md` status disagrees with the feature file | The feature file wins; `INDEX.md` is a view of it. Rewrite the row |
| Feature missing from `INDEX.md` | Add the row, status from the file, description from the feature's one-line summary if it has one, blank if not |
| `INDEX.md` row for a file that does not exist | Remove it, and note the slug in the report in case it was a rename |
| ADR filename without a date prefix | Rename to `<YYYY-MM-DD>-<slug>.md`, date from `git log --diff-filter=A` on that file; today only if git has nothing |
| ADR on disk missing from `ADR/INDEX.md` | Add the row, status and description from the record |
| Legacy `DESIGN_DECISIONS.md` | Split into one `ADR/` record per entry, dated from the entry or from git history, then delete the file |
| Numbered feature slugs (`01-login.md`) | Rename the pair to `kebab-case`, update every link that points at them |
| `archived/` feature with a live status | Set `archived (was <status>)` |
| Missing `GAPS.md` or `ADR/INDEX.md` | Create from the template, empty |

**Questions** — do not guess, and bundle them by kind rather than asking per file:

| Finding | Ask |
|---|---|
| Feature with no `**Status**:` line | What is true of these? Offer the evidence you can see — whether the referenced code exists, whether tests cover it |
| `passing`/`failing` feature still carrying `TBD` | Is the status optimistic, or is the note stale? |
| Scenario with no `Then` | What was this meant to assert? A scenario nobody can answer for is a `GAPS.md` entry, not a guess |
| `.feature` with no `.md`, or the reverse | Was the missing half never written, or deleted? |
| Every scenario `@draft` on a claimed feature | Has the phrasing been reviewed, or is the status ahead of itself? |
| Locator by selector | Rewrite to visible text — needs the user, who knows what the element says |

Conventions `validate.sh` cannot see, and so worth checking by eye: whether `ARCHITECTURE.md` exists and still describes the current structure, whether a `DATA_MODEL.md` is warranted, and whether feature files carry the template's sections.

## Workflow

### 1. Inventory

Run `validate.sh specs`. Read `INDEX.md` and one or two feature files to see which conventions the set already follows. Sort every finding into the two piles above.

Report: how many mechanical fixes, how many questions grouped by kind, and which conventions are absent entirely. Name anything you found that looks like *behaviour* drift rather than format, and say it is out of scope for this mode.

**Stop. Confirm the plan — and confirm the split, because a fix in the wrong pile is a guess wearing a fact's clothes.**

### 2. Mechanical pass

Apply the mechanical fixes. Touch nothing already conformant. Re-run `validate.sh specs`: the count should drop to exactly the question pile.

**Stop. The user reviews with `git diff specs/`.**

### 3. Questions

Work the question pile, bundled by kind — all the missing statuses in one exchange, all the stale `TBD`s in the next. Apply each answer as it arrives. Anything the user cannot answer now becomes a `GAPS.md` entry rather than a guess or a silent edit.

### 4. Finalise

Run `validate.sh specs` and report: what was mechanical, what was answered, what is left and why, and any behaviour drift you spotted along the way with a recommendation to run `update` next. A set that still fails after an upgrade is fine as long as every remaining failure is recorded in `GAPS.md` with a reason.

---
