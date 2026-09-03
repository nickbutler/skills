---
name: spec
description: Use when the user wants to spec out what to build, propose a change to an already-specced system, document an existing system as specs or user stories, or reconcile specs that have drifted from code, or bring an older spec set up to the current conventions. Triggers include "spec out", "let's plan what we're building", "spec this change", "what would it take to add X", "document what we have", "create a specs folder", "sync the specs", "what's drifted", "my specs are on an old version", "validate is failing everywhere", or an explicit /spec create|infer|change|update|upgrade. Maintains a specs/ folder of features with Gherkin BDD acceptance criteria, checked by validate.sh and browsable via view.sh; mode is auto-detected when not named.
---

# Spec

Generate and maintain a structured spec set: a flat list of feature files with Gherkin BDD acceptance criteria and supporting artefacts.

## Mode dispatch

| Command | When to use | Workflow |
|---|---|---|
| `/spec create` | No code yet — design a spec from a conversation or planning discussion | `references/mode-create.md` |
| `/spec infer` | Code exists, no `specs/` folder — reverse-engineer specs from the codebase | `references/mode-infer.md` |
| `/spec change` | `specs/` folder exists — propose a specific change to build, as a reviewable spec delta plus tasks | `references/mode-change.md` |
| `/spec update` | `specs/` folder exists — reconcile specs with code that has already changed | `references/mode-update.md` |
| `/spec upgrade` | `specs/` folder was written against an older version of this skill — reconcile it with the current conventions | `references/mode-upgrade.md` |

**Auto-detect when no mode is given:**
1. No `specs/`, no codebase → **create**
2. No `specs/`, but a codebase exists → **infer**
3. `specs/` exists, and the user is proposing new work ("add", "build", "change", "what would it take to…") → **change**
4. `specs/` exists, and the user is reconciling with code already written ("sync", "what's drifted", "we've been building") → **update**
5. `specs/` exists, and the complaint is about the spec set's own shape ("validate is failing everywhere", "this was made before changes/ existed", "my specs are on an old version") → **upgrade**
6. Ambiguous (e.g. `specs/` exists but user says "start fresh") → ask

**update vs upgrade**: update reconciles the specs with the *code*; upgrade reconciles them with *this skill*. A feature whose behaviour changed is an update. A feature that is fine but sits in a spec set predating `changes/`, dated ADR filenames or the quality checks is an upgrade. Doing an update on a set that needs upgrading buries real drift under formatting noise.

**change vs update** is the distinction to get right: **change** runs *before* the code, and the spec delta is the thing being agreed; **update** runs *after* the code, and the spec is catching up to reality. If code has already been written for the work in question, it is an update, not a change.

**Once the mode is settled, read its workflow file and follow it.** The rest of this file is what every mode shares — structure, disciplines, statuses, validation. It is not enough on its own: each mode has its own checkpoints, its own principles, and its own definition of what may be written down. Do not improvise a workflow from the shared sections.

---

## Shared: output structure

```
specs/
├── INDEX.md                          # flat feature list with status
├── ARCHITECTURE.md                   # cross-cutting technical design (current state)
├── DATA_MODEL.md                     # [optional] entity definitions, fields, types, persistence
├── ADR/                              # decision records — one file per decision
│   ├── INDEX.md                      # record list with status and description
│   └── <YYYY-MM-DD>-<decision-slug>.md
├── GAPS.md                           # items needing clarification
├── SYNC_REPORT.md                    # [update mode only] report for the current sync run
├── features/
│   ├── <feature-slug>.md             # user story, context, technical notes, status
│   └── <feature-slug>.feature        # executable Gherkin (pytest-bdd / Cucumber)
├── changes/                          # [change mode] in-flight work
│   ├── <change-slug>.md              # why, scope, features touched, tasks
│   └── archive/
│       └── <YYYY-MM-DD>-<change-slug>.md
└── archived/                         # [update/change mode] deprecated features
    ├── <feature-slug>.md
    └── <feature-slug>.feature
```

**`ARCHITECTURE.md`** documents the current technical design: design principles, constraints, key abstractions, system boundaries, and module structure. It describes *what is true now* and is updated when the structure changes.

**`DATA_MODEL.md`** is optional — create it when the project has persistent or structured data worth specifying. It holds the concrete detail: entity definitions, field names, types, validation rules, and persistence notes. `ARCHITECTURE.md` keeps the conceptual domain overview; `DATA_MODEL.md` is where an implementer goes to understand the actual shape of the data.

**`ADR/`** is the decision log: *why* the architecture looks the way it does. One record per file, named `<YYYY-MM-DD>-<decision-slug>.md` (date decided; date raised for open questions) so records sort chronologically. Each record captures the decision made, the alternatives considered, and the constraints that drove the choice; unresolved questions are records with status `open`. Rejected approaches get records too (status `rejected`) — negative memory, so future sessions don't re-propose them. Consult existing records, including rejected ones, before proposing any architectural change. `ADR/INDEX.md` lists every record with status and a one-line description, like the main `INDEX.md`. Records are append-only — revise by adding a new record that supersedes the old one, not by rewriting it. Keep `ADR/INDEX.md` in sync whenever records are added or their status changes.

**`changes/`** holds one file per in-flight change. A change file records *why* work is being done, what it touches, and the task list — never the requirements themselves. The requirements live in `features/`, edited in place on a branch; the delta is `git diff specs/`. Keeping requirement text out of the change file is the whole point: a second copy of a requirement is a second thing that can drift. Completed changes move to `changes/archive/<YYYY-MM-DD>-<change-slug>.md`.

Each feature is a pair of files with the same slug. The `.md` carries the human-readable context; the `.feature` carries the executable Gherkin. They are always created and archived together.

Use `kebab-case` slugs derived from names, not numbers.

## Shared: core disciplines

**Stop at checkpoints.** Each mode has natural decision points. Stop at each and confirm before proceeding. Compounding a wrong assumption across many files is expensive; a one-sentence confirmation is cheap.

**Existing step library is canonical.** When `step_definitions/` exists, use its steps verbatim. Never modify the step library directly. When a scenario requires a step that doesn't exist, write the natural Gherkin phrase and tag the scenario `@draft` — a signal that the step needs implementing before the scenario can run.

**No invention.** Never add behaviour, features, or requirements that weren't confirmed (infer/update) or explicitly discussed (create/change). Speculation goes to `GAPS.md` or an open `ADR/` record.

## Shared: step definitions handling

Read `step_definitions/` thoroughly before writing Gherkin. Use existing steps verbatim where possible. Write idiomatic, readable scenarios — don't contort phrasing to fit the library at the cost of clarity.

When a scenario requires a step that doesn't exist, write the natural Gherkin phrase and tag the scenario `@draft`. The user removes `@draft` when they have reviewed the scenario and are satisfied the step phrasing is correct and ready to implement. Never accumulate `@draft` tags silently — call them out in the report so the user knows what needs sign-off.

### Two-layer step model

Steps live at one of two levels. Keep them separate — do not mix levels within a scenario.

**Layer 1 — Interactions**: single primitive actions from the project's vocabulary (`references/step-vocabulary.md`). Used in feature files that document a task directly.

**Layer 2 — Tasks**: named compositions of interactions representing a meaningful user action. Task steps appear as `Given` preconditions in higher-level feature files. Their implementations call interaction-layer steps.

```gherkin
# Layer 1 feature — documents "add to cart" in primitives
Scenario: Add a product to the cart
  Given I navigate to /products/widget
  When I click the Add to Cart button
  Then I should see "1 item in cart"

# Layer 2 feature — references "add to cart" as a precondition
Scenario: Complete a purchase
  Given I have added "Widget" to my cart
  When I click the Checkout button
  Then I should be on /order-confirmation
```

**Background vs. task step — decision rule:**
- Same interaction sequence appears as a precondition in **2+ scenarios across different feature files** → define a task step
- Sequence only repeats within one feature file → use `Background:`
- Never create a task step solely to avoid writing primitives once — only to eliminate duplication across features

**Task step naming:**
- Use state/past-tense language: `I have {done X}`, `a {thing} exists`, `{X} has been set up`
- Interaction steps use present-action language: `I click`, `I fill in`, `I navigate`
- The tense difference makes the layer immediately visible when reading a scenario

**Proposing new steps:**
- Interaction steps must come from the project's established primitive vocabulary. If the project's domain is not covered by the reference vocabularies below, establish a new primitive family before writing any feature files — document it in `GAPS.md` and get confirmation before use. Do not invent one-off interaction steps inside scenarios.
- Task steps only when the cross-feature duplication condition above is met; note which feature files they consolidate
- Do not propose a task step that wraps a single interaction — that is just renaming a primitive
- Any scenario using an unimplemented or unconfirmed step gets tagged `@draft`

### Primitive vocabulary (Layer 1)

The primitive vocabulary is domain-dependent. **Read `references/step-vocabulary.md` before writing any scenario** — it holds the two reference vocabularies this skill ships, **browser** and **CLI**, and the rules for parameterising them. Use whichever fits the project's interface; a single project may use both.

When the project's domain fits neither (a mobile app, a message-queue consumer, an API-only service), establish a new primitive family in `GAPS.md` and get confirmation before writing any feature files. Never invent a one-off interaction step inside a scenario.

## Shared: progress tracking

Each feature file carries a `**Status**:` line below its title. Statuses flow in one direction — do not move backwards without a note explaining why.

| Status | Meaning |
|---|---|
| `draft` | Spec written; needs review before implementation begins |
| `ready` | Spec approved; awaiting implementation |
| `in progress` | Implementation underway; scenarios not yet passing |
| `passing` | All acceptance scenarios green |
| `failing` | Scenarios were passing; now failing (regression) |
| `deferred` | Intentionally postponed; not counted in progress |

**INDEX.md** maintains a features table with a Status column — the single place to see all features and their status at a glance. `deferred` features are excluded from progress counts.

Change files carry their own `**Status**:` — `proposed` (written, not yet agreed), `in progress` (tasks agreed, being built), `complete` (archived). These are the change's lifecycle, not a feature's.

**Updating statuses:**
- `create` and `infer` modes: all new features start at `draft`
- `change` mode: features the change touches move to `ready` when the delta is agreed, then track implementation as it lands
- `update` mode: when code evidence confirms a feature is implemented and tests are present, propose advancing to `in progress` or `passing`; when referenced code disappears, flag as `failing` and prompt the user
- Status changes outside `update` mode are manual — the user edits the feature file and INDEX.md directly
- After any status change, recalculate the INDEX.md progress counts

## Shared: validation

`validate.sh` ships beside this file. It checks the structural invariants of a spec set deterministically — no model in the loop, so it cannot be talked into a pass.

```sh
<skill-dir>/validate.sh [specs-dir]     # default: ./specs — exits non-zero on any FAIL
```

`<skill-dir>` is the directory holding this `SKILL.md`; in Claude Code that is `${CLAUDE_SKILL_DIR}`. The scripts take the spec set as an argument and hold no state, so they run from any working directory and need nothing installed in the project.

It checks:

- every `features/*.md` has a matching `.feature`, and vice versa
- every feature `.md` carries a valid `**Status**:` (a trailing note after the status token is allowed; `archived` is a status only inside `archived/`)
- `INDEX.md` lists exactly the features on disk, with matching statuses — the single most common drift
- each `.feature` has a `Feature:` line, at least one scenario, and no scenario without steps
- every non-blank line inside a scenario is a Gherkin step (typos like `Whne` are caught; narrative blocks, tables, docstrings and comments are not)
- every step resolves against `step_definitions/` unless its scenario is tagged `@draft` — a `Background` cannot carry a tag, so it is exempt only when every scenario in the file is `@draft`. Skipped entirely when no step library exists.
- `ADR/` filenames are dated, and `ADR/INDEX.md` lists exactly the records on disk
- each `changes/*.md` has a task checklist and links only to features that exist; an archived change has no open tasks

It also enforces four rules this skill states but which used to rely on being obeyed:

- **a scenario asserts something** — no `Then` step means the scenario passes vacuously. A `Background` is exempt; it is setup, not a conclusion
- **no unresolved markers once the code has run** — `TBD`, `TODO`, `FIXME` or `NEEDS CLARIFICATION` in a feature marked `passing` or `failing`. A `ready` feature may still say `TBD (no code yet)`; that is honest. A `passing` one saying it is a contradiction
- **locators are visible text** — `css=`, `xpath=` or `//tag[` in step text, which the browser vocabulary forbids. Deliberately narrow: a source path like `src/app.py` is legitimate subject matter for a tool that reads source trees, and matching those produces nothing but false positives
- **a claimed feature is not entirely unreviewed** — `ready`, `passing` or `failing` while every scenario is still `@draft`. Only checked when the project has a step library; without one, `@draft` means "nothing runs this" rather than "nobody has read this"

**Run it at the end of every mode, before reporting.** A `FAIL` is a real inconsistency in the spec set — fix the spec, never loosen the check. The summary line (feature counts by status, `@draft` scenario count) is the raw material for the report, so read its output rather than recounting by hand.

What it deliberately does not check: whether a scenario is *correct*, whether a feature is worth having, or whether the spec matches the code. Those need judgement — that is what the modes and their checkpoints are for.

## Shared: viewing

`view.sh` ships beside this file. It serves the spec set as a browsable site and opens it.

```sh
<skill-dir>/view.sh [specs-dir] [--port N] [--no-open]     # default: ./specs, ctrl-c to stop
```

It is **read-only** — no write endpoints, no state, nothing touched in the working tree — so it is safe to leave running while you edit, rebase or switch branches. Refresh to see the current files; there is no build step and no cache.

What it gives you that reading the files does not:

- **The set at a glance** — every feature as a card with its status, description and scenario counts, over a progress bar of the whole set by status
- **Gherkin rendered as Gherkin** — scenarios as cards, keywords coloured, `@draft` called out, outline `Examples:` and step tables as real tables
- **Cross-links followed** — a feature shows the changes that touch it; links between spec files navigate in-app rather than downloading a `.md`
- **Decisions by state** — accepted, rejected and open records are coloured apart, so an open question never reads as settled
- **Git history per feature** — the commits that touched either half of the pair, and the diff for any of them. `#/feature/<slug>/<sha>` is a shareable link straight to one
- **Validation inline** — the same findings `validate.sh` prints, with the failure count in the header

Reach for it when reviewing a spec set you did not write, when a status looks wrong and you want the commit that changed it, or when showing the specs to someone who will not read a folder of markdown. It renders the spec set as it is — it will not tell you whether the specs are true.

## Shared: reference files

Everything below `references/` is read just-in-time — when you are about to do the thing it covers, and not before. Do not load them upfront.

| File | Read it when |
|---|---|
| `mode-<mode>.md` | the mode is settled — this is the workflow, and it is mandatory |
| `step-vocabulary.md` | before writing any scenario |
| `templates/*.template` | you are about to generate that particular file |

The templates:

| Template | Used by |
|---|---|
| `index.md.template` | all modes |
| `architecture.md.template` | all modes |
| `data-model.md.template` | all modes — when the project has persistent or structured data |
| `adr.md.template` | all modes — one decision record |
| `adr-index.md.template` | all modes |
| `feature.md.template` | all modes — human-readable context |
| `feature.feature.template` | all modes — executable Gherkin |
| `change.md.template` | change mode |
| `gaps.md.template` | all modes |
| `sync-report.md.template` | update mode |

---

## Override flags (all modes)

- **"Generate all features in one pass"** — after confirming the feature list, generate all features without stopping between them; still stop after the first feature for format review
- **"Include inferred behaviour, tag inline"** — (infer/update) switch to Confirmed/Inferred/Gap inline tagging instead of separate GAPS.md
- **"Mechanical only"** — (upgrade) apply the derivable fixes and stop, leaving every question for a later pass
- **"No change file"** — (change) apply the spec delta on a branch without writing `changes/<slug>.md`; the diff is the whole record. Loses the why and the task list — only for a change small enough to review in one sitting
- **"Skip step definition verification"** — write idiomatic Gherkin without checking against the library; still record proposed steps
