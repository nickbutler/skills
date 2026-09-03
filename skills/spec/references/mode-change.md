# Mode: change

*Loaded by the `spec` skill once the mode is settled. `SKILL.md`'s shared sections — output structure, core disciplines, statuses, validation — still apply; this file only covers what is particular to change. Paths below are relative to the skill's own directory, not to this file.*

Propose a specific piece of work against an existing spec set, as a reviewable delta plus an implementation checklist. Specs here are **prescriptive** — like create mode, but bounded by a system that already exists.

## When to use

- A `specs/` folder exists and the user wants to build something new or alter existing behaviour
- The question is "what would it take to add X" and the answer should be reviewable before code
- A change spans several features and needs its scope agreed in one place

## When NOT to use

- No `specs/` folder → **create** or **infer** first; there is nothing to delta against
- The code has already been written → **update**; the spec is catching up, not leading
- A one-line correction to a spec that is simply wrong → just edit it, no change file

## Additional principles

**The feature files are the delta.** Edit `features/` in place on a branch. Never restate a requirement in the change file — it is a manifest, not a spec. Two copies of a requirement is exactly the drift this skill exists to prevent.

**One change, one branch, one file.** If the work needs two independent reviews, it is two changes. A change file that touches half the feature set is a roadmap, not a change — split it.

**Scope is a boundary, not a wish list.** The `Out` section is load-bearing. Anything discovered mid-change that falls outside it goes to `GAPS.md` or a follow-up change, not into this one.

**Decisions become ADRs, not prose.** An architectural choice made during a change gets an `ADR/` record, linked from the change file. Consult existing records — including `rejected` ones — before proposing an approach, and record a new rejection when one is turned down. The change file archives; the ADR does not.

**Tasks derive from the spec delta.** Each task traces to something the diff changed. If a task has no corresponding spec change, either the spec is incomplete or the task is scope creep — find out which.

## Workflow

### 1. Locate

Read `INDEX.md`, then `ARCHITECTURE.md`, `ADR/INDEX.md` (and any record that looks relevant, including rejected ones), and the feature files the change plausibly touches. Identify:

- which existing features change behaviour, and how
- which features are new
- whether anything becomes obsolete
- which existing decisions constrain the approach, and whether this change contradicts one

Create the branch. Everything from here is reviewable as a diff.

Report the affected-feature list and any decision that constrains the approach.

**Stop. Confirm the blast radius before writing anything.**

### 2. Proposal

Write `specs/changes/<change-slug>.md` from `references/templates/change.md.template` — Why, Scope (in *and* out), Features touched, Decisions. **Leave Tasks empty**; tasks derive from the spec delta and the delta does not exist yet.

Where the change makes an architectural choice, write the `ADR/` record now and link it. Where the choice is genuinely open, write the record with status `open` and say in the change file that the delta depends on it.

**Stop. Agree why and how big before touching a single feature file.**

### 3. Spec delta

Edit `features/` in place:

- **Modified features**: change the scenarios that change behaviour. Leave untouched scenarios alone — a scenario that still holds should not show up in the diff. Update Technical notes only where they are now wrong.
- **New features**: full `.md` + `.feature` pair from the templates, status `ready`. Add to `INDEX.md`.
- **Removed features**: move the pair to `archived/` with a deprecation header naming this change. Remove the `INDEX.md` row.

Tag `@draft` on any scenario needing a step that doesn't exist yet — the same rule as every other mode.

Set status to `ready` on everything the change touches, and run `validate.sh specs`.

**Stop. The user reviews the delta with `git diff specs/`. This is the review that matters — the whole point of the mode is that it happens before implementation.**

### 4. Tasks

Derive the implementation checklist from the delta. Each task is a unit a reviewer could verify on its own; number them `<group>.<n>`. Order them so the suite can go green in stages rather than all at the end.

Where the project follows TDD, the scenarios *are* the failing tests — task 1 is normally implementing the `@draft` steps so they can run red.

Write them into the change file, set its status to `in progress`, and re-run `validate.sh specs`.

**Stop. Confirm the task list before implementing.**

### 5. Implement

Implementation may happen in this session or elsewhere. Whoever does it:

- ticks tasks as they land
- moves touched features `ready` → `in progress` → `passing` as their scenarios go green, keeping `INDEX.md` in step
- removes `@draft` tags as the steps behind them are implemented

Do not tick a task or advance a status on the strength of code that has not been run. `passing` means the scenarios were executed and were green.

### 6. Archive

When every task is ticked and every touched feature's scenarios are green:

- move the change file to `changes/archive/<YYYY-MM-DD>-<change-slug>.md`, status `complete` (date completed)
- confirm every touched feature is `passing` (or `deferred`, with a note), and `INDEX.md` agrees
- recalculate the `INDEX.md` progress counts
- run `validate.sh specs` — it will fail if the archived change still has an open task, or if `INDEX.md` has fallen out of step

Report: features added / modified / archived, `@draft` scenarios still outstanding, ADR records written, and the `validate.sh` summary line.

---
