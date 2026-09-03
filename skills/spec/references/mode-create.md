# Mode: create

*Loaded by the `spec` skill once the mode is settled. `SKILL.md`'s shared sections — output structure, core disciplines, statuses, validation — still apply; this file only covers what is particular to create. Paths below are relative to the skill's own directory, not to this file.*

Design a spec set from a planning conversation, before any code exists. Specs here are **prescriptive** (defining intent) rather than descriptive (observing behaviour).

## When to use

- Planning a new project or feature before writing code
- The design discussion is in this conversation and should be captured as structured specs
- Neither code nor a `specs/` folder exists yet

## When NOT to use

- Code already exists → use **infer**
- `specs/` already exists → use **update**

## Additional principles

**Vocabulary first.** Establish domain language before writing scenarios. The terms defined here become the terms used in code — consistency from spec to implementation prevents drift before it starts.

**Open questions are first-class.** Design gaps are decisions deferred, not failures. Track them as open `ADR/` records with enough context that they can be answered when implementation begins. Papering over uncertainty produces specs that mislead.

**MVP scope explicit.** Distinguish what's in scope for the first iteration from what's a later phase.

**Scenarios are implementation-agnostic.** Write acceptance criteria at the behaviour level. Save implementation hints for `Technical notes`; don't over-specify approach in Gherkin.

## GAPS.md in create mode

Gaps here are spec-level ambiguities — the design discussion wasn't specific enough to write a complete scenario. Unlike infer mode, there's no code to inspect; these require further design work. Use "What was discussed" in place of "Where you looked".

## Workflow

### 0. Cold-start interview (skip if context already exists)

If the skill is invoked with no prior conversation — empty chat, blank project directory, or a bare `/spec create` with no description — do not attempt to synthesise; there is nothing to synthesise yet. Instead, conduct a short structured interview.

Ask questions **one at a time**, in this order. Use earlier answers to skip questions that are already answered. Stop as soon as all must-have questions are resolved — do not ask nice-to-have questions if the picture is already clear enough to draft.

**Must-have (always ask if unanswered):**

1. *"What does it do, and who is it for?"* — the one-sentence pitch
2. *"Who are the different types of users?"* — distinct actors; may be implicit in the answer to 1
3. *"What are the 3–5 core things users need to be able to do?"* — jobs to be done
4. *"What's essential for the first version, and what can wait?"* — MVP boundary

**Strongly useful (ask if still unclear after the above):**

5. *"What is explicitly out of scope?"* — prevents the feature list from expanding unboundedly
6. *"What platform or interface?"* — web app, mobile, CLI, API, or combination

**Nice to have (ask only if relevant and not yet answered):**

7. *"Are there existing systems this needs to integrate with or replace?"*
8. *"Any hard constraints — compliance, performance, specific tech stack?"*

Keep questions short and conversational. Do not present them as a numbered list to the user — ask naturally, one at a time, and acknowledge each answer before asking the next. Once the must-haves are covered, proceed to step 1.

### 1. Elicitation summary

Synthesise from the conversation (or interview answers from step 0):

- **Product/feature**: what it does and for whom (one sentence)
- **Actors**: who uses the system and in what roles
- **Core goals**: outcomes actors are trying to achieve (3–6 items)
- **Constraints**: technical, legal, timeline, or product constraints explicitly mentioned
- **Non-functional requirements**: only what was stated
- **Domain vocabulary**: key terms and their definitions as used in the discussion
- **Scope signals**: anything explicitly said to be in or out of scope

Flag any category with insufficient signal — those become initial open records in `ADR/`.

Also identify from the conversation:
- **Design principles**: any "how we build" rules stated or implied — architectural patterns, coding philosophy, team norms
- **Constraints**: hard limits mentioned — technical, legal, operational, or organisational

If neither has been stated, ask before proceeding to feature enumeration. These shape how every feature is described and what belongs in Technical notes — they cannot be retrofitted cleanly once features are written.

**Stop. Let the user correct or extend the elicitation summary before proceeding.**

### 2. Feature enumeration

Draft the full feature list — each with a one-line user-facing description, the actor, and an MVP / later-phase label. This is the complete map of the system, not a shortlist.

**Stop. Confirm the feature list before scaffolding or writing any feature files.**

### 3. Scaffold

Create directory structure and stub files: `INDEX.md` (stub), `ARCHITECTURE.md` (stub — sections present, content TBD), `ADR/` (INDEX.md plus a record for each decision and open question surfaced so far), `GAPS.md` (empty structure), and `features/` (empty).

If the project has entities, records, or structured data that will be persisted or shared across features, also create `DATA_MODEL.md` (stub). If it is not obvious from the conversation, ask: *"Does this project have a data model — entities or records that need defining?"*

**Stop. Confirm structure before populating.**

### 4. First feature

Generate one feature file in full, with these adaptations:
- `Technical notes` → populate what's known; use `TBD: <question>` for undecided implementation details; each TBD should also appear as an open record in `ADR/`
- `Relevant principles / constraints` → identify which entries from `ARCHITECTURE.md` shape this feature's implementation; if ARCHITECTURE.md is not yet populated, note what principles apply based on the discussion so far
- `Notes on confirmation` → rename to `Notes on scope`; flag scenarios that are inferred from discussion (not explicitly stated), edge cases not discussed, or contingent on an open decision

**Stop. Get explicit feedback before applying the format to remaining features.**

### 5. Remaining features → Finalise → Report

Generate remaining features. Complete `INDEX.md`. Run `validate.sh specs` and fix what it flags. Populate `ARCHITECTURE.md` with the cross-cutting design that emerged from the discussion — key abstractions, module boundaries, and the structural choices that span multiple features. Write an `ADR/` record for each choice and open question from the session and complete `ADR/INDEX.md`. Report: file tree, domain vocabulary established, count of open decisions, count of spec gaps, count of `@draft` scenarios needing step implementation, recommended next step.

---
