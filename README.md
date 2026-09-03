# skills

Nick's [Agent Skills][spec] — portable `SKILL.md` capability packs that work in Claude Code,
Codex, Cursor, Gemini CLI, OpenCode and any other agent implementing the standard.

## Install

```sh
npx skills add nickbutler/skills --skill spec
npx skills add nickbutler/skills --skill spec --skill diagnosing-bugs
npx skills add nickbutler/skills --skill '*' -g          # all, global
npx skills add nickbutler/skills --skill spec -a claude-code -a codex
```

Or clone and symlink the ones you want into `~/.agents/skills/`.

## Skills

| Skill | What it does |
|-------|--------------|
| `commit-msg` | Generates a commit message from the working diff into the repo's `NEXT_COMMITMSG`, pre-populating the next manual commit. |
| `diagnosing-bugs` | No fix without root cause: build a red-capable feedback loop, rank falsifiable hypotheses, fix via failing test. |
| `loopify` | Sets up an agent loop that turns labelled issues into reviewed pull requests — label ladder, queue command, worktree isolation, PR gate. |
| `scrollytelling` | Builds a public "How it works" scrollytelling page inside an app — narrative chapters, scroll-driven animation, content-contract test. |
| `spec` | Keeps a `specs/` folder of features with executable Gherkin acceptance criteria — creates, infers from code, proposes changes, reconciles drift. Ships a validator and a browser viewer. [More below](#spec). |
| `web-deck` | Builds a presentation as a bespoke single-file web app — stepped scrollytelling canvas, markdown content layer, print-to-PDF. |

## spec

The largest of these. It keeps a `specs/` folder where each
feature is a pair — markdown for the story and context, a `.feature` file of Gherkin a BDD runner
can actually execute — with the architecture, decisions and open questions around them.

```
specs/
├── INDEX.md            # every feature and its status
├── ARCHITECTURE.md     # the current technical design
├── ADR/                # decisions, including the rejected ones
├── GAPS.md             # what nobody has answered yet
├── features/           # <slug>.md + <slug>.feature, always a pair
└── changes/            # work in flight, archived once it lands
```

Five modes, auto-detected when you don't name one:

| Mode | For |
|------|-----|
| `create` | No code yet — design the set from a planning conversation |
| `infer` | Code but no specs — reverse-engineer them, confirmed behaviour only |
| `change` | Propose work as a reviewable spec delta on a branch, plus its task list |
| `update` | The code moved and the specs did not — reconcile them |
| `upgrade` | The specs are fine, the conventions moved — bring them current |

Two scripts ship alongside, both deterministic and neither able to write to your spec set:

```sh
<skill-dir>/validate.sh specs     # exits non-zero on any FAIL
<skill-dir>/view.sh specs         # serves the set on localhost
```

`validate.sh` checks what a model shouldn't be trusted to remember: every feature is a complete
pair with a valid status, `INDEX.md` still agrees with the files, the Gherkin parses and its steps
resolve against the project's step library, ADR records are dated and indexed, and an archived
change has no open tasks. It also enforces four rules the skill used to only state — a scenario
asserts something, a `passing` feature carries no `TBD`, locators are visible text not selectors,
and a signed-off feature isn't entirely `@draft` — and warns when two changes in flight on
different branches claim the same feature.

`view.sh` serves the set as a browsable site: story and scenarios side by side, sections coloured
apart, decisions coloured by state so an open question never reads as settled, per-feature git
history with linkable diffs, every change in flight on every branch, and the validator's findings
in the header.

## Layout

```
skills/<name>/SKILL.md        # required — YAML frontmatter (name, description) + instructions
skills/<name>/references/     # optional — templates and reference material
skills/<name>/*.sh            # optional — scripts the skill runs
skills/<name>/*.test.sh       # optional — tests for those scripts, not shipped guidance
```

One skill per directory, named the same as its `name:` frontmatter field. That layout is what
makes `--skill <name>` resolve.

## Local development

These are symlinked into `~/.agents/skills/` (and fanned out to agents that don't read it) by
[`dots`][dots], which keeps this repo fresh at `$SKILLS_PATH`. Edits land in git immediately —
no reinstall step.

Where a skill ships scripts, its tests sit beside them and run on their own:

```sh
skills/spec/validate.test.sh     # the validator's rules
skills/spec/view.test.sh         # the viewer's HTTP surface
skills/spec/render.test.sh       # what the page renders, via headless Chrome (skips without it)
```

[spec]: https://agentskills.io
[dots]: https://github.com/nickbutler/dots
