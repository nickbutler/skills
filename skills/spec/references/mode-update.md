# Mode: update

*Loaded by the `spec` skill once the mode is settled. `SKILL.md`'s shared sections — output structure, core disciplines, statuses, validation — still apply; this file only covers what is particular to update. Paths below are relative to the skill's own directory, not to this file.*

Reconcile an existing spec set with the current state of the codebase. Detect drift, surface deprecations, identify uncovered code.

## When to use

- A `specs/` folder already exists from a previous run or sync
- Refreshing specs after a period of development
- Detecting spec drift or staleness

## When NOT to use

- No `specs/` folder exists → use **infer** (or **create** if no code either)
- Rewriting specs from scratch → use **infer** with explicit instruction to overwrite

## Additional principles

**Specs are lightly human-edited.** Assume human curation has occurred since last sync. Preserve human edits wherever the underlying behaviour hasn't changed.

**Behaviour change drives spec change.** A refactor that preserves behaviour should not trigger a scenario update.

**Surface, don't decide.** When intent is ambiguous (intentional removal or accidental regression?), prompt the user rather than guessing.

**Never silently delete.** Removed features get archived to `specs/archived/`, not deleted.

**Changes reviewed via git.** Apply changes directly to files. The user reviews via `git diff specs/` and commits, amends, or reverts as they choose.

## Change detection (in preference order)

1. **Git-based**: `git log -- specs/ | head -1` to find the last commit touching `specs/`, then diff from there to `HEAD`
2. **Fallback**: compare file modification times between `specs/` and source directories

Report the detection method used. This appears in `SYNC_REPORT.md`.

## Categorisation

For every spec feature, assign one of:
- **Unchanged** — referenced code has not changed
- **Drift candidate** — code changed in a way that may affect behaviour
- **Refactor only** — code changed but behaviour appears preserved
- **Deprecated candidate** — referenced code no longer exists

For new or significantly-changed code with no matching feature: **Uncovered**

For `GAPS.md` entries: **Resolved**, **Still open**, or **Obsolete**

For `@draft` scenarios: **Ready** (steps now exist — remove tag), **Still pending** (steps not yet implemented — leave tag), or **Obsolete** (scenario removed)

**Stop. Report the categorisation summary (numbers only). Confirm scope before applying changes.**

## Applying changes

In order:
- **Refactor-only**: update technical notes (paths, type names) without touching scenarios
- **Drift candidates**: update unambiguous changes; prompt the user on ambiguous ones
- **Uncovered**: create feature files using `references/templates/feature.md.template`; apply confirmed-only rule
- **Deprecated**: move to `specs/archived/<feature-slug>.md` with deprecation header (date, last commit, reason if known — prompt if unknown)
- **Resolved gaps**: move content into the relevant spec file; add a brief "resolved" note in `GAPS.md`
- **Ready `@draft` scenarios**: remove the `@draft` tag
- **Obsolete entries**: remove with a one-line note in a history section if one exists

## Update cross-cutting files

- `INDEX.md`: add candidate features if new uncovered areas suggest them; recalculate progress counts
- `ARCHITECTURE.md`: update when structural changes are detected — new modules, changed boundaries, revised abstractions; do not touch if the changes are behaviour-only
- `DATA_MODEL.md`: update when entities are added, removed, or their fields/types change; if `DATA_MODEL.md` doesn't exist but the codebase now has meaningful persistent data, propose creating it
- `ADR/`: add new records for structural choices made since the last sync; never rewrite existing records; keep `ADR/INDEX.md` in sync. A legacy `DESIGN_DECISIONS.md`, or any other convention drift, is **upgrade**'s job — say so and move on rather than migrating mid-sync
- `GAPS.md`: open and newly-discovered gaps only
- `changes/`: for each in-flight change, tick tasks the code shows are done; if every task is complete and the scenarios are green, propose archiving it. A change whose features have all drifted away from it is stale — surface it, don't quietly delete it

## Finalise

Run `validate.sh specs` and fix anything it flags. Write `specs/SYNC_REPORT.md` using `references/templates/sync-report.md.template`.

Report: total files changed, clarifications requested and resolved, items deferred, pointer to `SYNC_REPORT.md`, suggestion to review via `git diff specs/`.

## When to prompt the user

Bundle clarification questions when possible. Ask (don't guess) when:
- A behaviour change could be intentional contract change or accidental regression
- A feature appears removed but might have been renamed
- Multiple plausible mappings exist between new code and existing features

---
