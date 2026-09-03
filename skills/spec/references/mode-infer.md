# Mode: infer

*Loaded by the `spec` skill once the mode is settled. `SKILL.md`'s shared sections — output structure, core disciplines, statuses, validation — still apply; this file only covers what is particular to infer. Paths below are relative to the skill's own directory, not to this file.*

Reverse-engineer a structured spec set from an existing codebase and its documentation. Specs here are **descriptive** (observing confirmed behaviour).

## When to use

- Code exists but no `specs/` folder
- Generating specs, user stories, or Gherkin scenarios from existing source code
- Setting up a BDD spec structure for a working system

## When NOT to use

- No code exists yet → use **create**
- `specs/` already exists → use **update**

## Additional principles

**Confirmed-only.** Only include behaviour traceable to source code, existing docs, or tests. Do not infer. Do not extrapolate. Speculative content goes to `GAPS.md`.

## Confirmed vs gap — strict rules

A spec item is **confirmed** if at least one of:
1. The behaviour is implemented in source code you have read
2. The behaviour is described in `PLAN.md` or `ARCHITECTURE.md`
3. The behaviour is exercised by an existing test
4. The behaviour is enforced by a type signature, schema, or validation rule you have inspected

For UI flows, confirmation requires evidence of: the route handler, the rendering, the form/inputs, and the success/failure path. Partial evidence → GAPS.

If you find yourself writing "the system probably…" or "this most likely…" — stop. That sentence belongs in `GAPS.md`.

## Inputs to locate

Read in this order, report which are missing:

1. `PLAN.md` (or `ROADMAP.md`)
2. `ARCHITECTURE.md` (or `docs/architecture.md`)
3. `step_definitions/` (or `features/step_definitions/`, `tests/steps/`)
4. `CLAUDE.md` / `AGENTS.md`
5. The codebase itself

If both `PLAN.md` and `ARCHITECTURE.md` are missing, ask before proceeding.

## Workflow

### 1. Reconnaissance

Read input documents. Build a map of the codebase (directory listing, outline-mode reading — don't load full files speculatively). Identify major user-facing capabilities and the existing step vocabulary.

While reading, look for evidence of design principles and constraints in `CLAUDE.md`, `ARCHITECTURE.md`, `PLAN.md`, READMEs, or configuration. These may be explicit ("we use a layered architecture") or implicit (a consistent pattern across the codebase that reflects a deliberate choice).

Report: what you found, then the full feature list — each with a one-line user-facing description. Include all confirmed user-facing capabilities, not a shortlist. Include a brief section on principles and constraints identified — and explicitly flag if none were found, prompting the user to state them before features are written.

**Stop. Wait for the user to confirm the feature list and establish any missing principles / constraints.**

### 2. Scaffold

Create directory structure and stub files: `INDEX.md` (begins with a plain-English product description, 1–2 sentences, no class names or file paths), `ARCHITECTURE.md` (stub), `ADR/` (INDEX.md stub), `GAPS.md`, and `features/` (empty).

If the codebase has models, schemas, migrations, or structured data types, also create `DATA_MODEL.md` (stub — populate in step 4 from what you've read).

**Stop. Confirm structure before populating.**

### 3. First feature

Generate one feature file in full. Apply the confirmed-only rule strictly. Tag any scenario with `@draft` if it uses steps not yet in `step_definitions/`. In Technical notes, populate `Relevant principles / constraints` from `ARCHITECTURE.md` — which principles or constraints visibly shape how this feature is implemented.

**Stop. Get explicit feedback on the first feature before applying the format to the rest.**

### 4. Remaining features → Finalise → Report

Generate remaining features. Complete `INDEX.md`. Run `validate.sh specs` and fix what it flags. Populate `ARCHITECTURE.md` by synthesising from the codebase: key abstractions, module structure, system boundaries, and the major structural patterns observed. Write `ADR/` records for any structural choices that are visible in the code but whose rationale is not self-evident — status `accepted`, with the evidence as context — and complete `ADR/INDEX.md`. Report: file tree, what's covered and what's in GAPS, count of `@draft` scenarios needing step implementation, patterns or inconsistencies noticed (flag, do not fix).

---
