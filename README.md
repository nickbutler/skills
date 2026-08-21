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
| `spec` | Maintains a `specs/` folder of features with Gherkin BDD acceptance criteria; creates, infers from code, or reconciles drift. |
| `web-deck` | Builds a presentation as a bespoke single-file web app — stepped scrollytelling canvas, markdown content layer, print-to-PDF. |

## Layout

```
skills/<name>/SKILL.md        # required — YAML frontmatter (name, description) + instructions
skills/<name>/references/     # optional — templates and reference material
skills/<name>/*.sh            # optional — scripts the skill runs
```

One skill per directory, named the same as its `name:` frontmatter field. That layout is what
makes `--skill <name>` resolve.

## Local development

These are symlinked into `~/.agents/skills/` (and fanned out to agents that don't read it) by
[`dots`][dots], which keeps this repo fresh at `$SKILLS_PATH`. Edits land in git immediately —
no reinstall step.

[spec]: https://agentskills.io
[dots]: https://github.com/nickbutler/dots
