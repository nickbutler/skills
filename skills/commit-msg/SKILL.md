---
name: commit-msg
description: Generate a git commit message from the current staged/unstaged changes and deliver it the way the user chose for this session — written to the repo's NEXT_COMMITMSG file (worktree-aware), shown in the chat only, or used to create the commit. Use when the user types /commit-msg or asks you to generate a commit message, draft a commit, or write a commit suggestion. Accepts an optional scope, which prefixes the subject line: `/commit-msg auth` gives `auth: add JWT refresh`.
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git add:*), Bash(git commit:*), Bash(git rev-parse:*), Bash(git config:*), AskUserQuestion, Read, Write
---

# Commit Message Generator

Generate a focused commit message from current git state and deliver it one of three ways: written to the repo's `NEXT_COMMITMSG` file so it pre-populates the user's next manual commit, shown in the chat only, or used to create the commit. Only the last of those commits, and only because the user chose it.

## Delivery mode (ask once per session)

The mode is a **session-wide** choice, decided on the first run of this skill in the session and recorded in a state file. The state file — not conversation memory — is the source of truth, so the choice survives context compaction.

**State file:** `<scratchpad>/commit-msg-mode`, where `<scratchpad>` is the session scratchpad directory named in the system prompt. That path is session-specific and re-injected every turn, so it is still available after a compaction. Contents are a single word: `write`, `chat`, or `commit`.

**Repo setting:** `git config --local commit-msg.mode`, holding `commit` when the user chose to auto-commit in every session of this repo. It lives in the repo's `.git/config` — never committed, shared by all worktrees of the repo.

1. **Read the state file** with `Read`. A missing file (error or empty) means the mode has not been chosen yet — that is expected on the first run, not a failure.
2. **If it holds `write`, `chat`, or `commit`** — use that mode silently. Do not ask, do not mention the file.
3. **If it is missing, check the repo setting** — `git config --local --get commit-msg.mode`. If it prints `commit`, write `commit` to the state file and use it silently. Anything else (no output, non-zero exit) means not set.
4. **If neither is set** — ask with `AskUserQuestion`:
   - question: "Where should commit messages go this session?"
   - header: "Delivery"
   - options:
     - `Write to NEXT_COMMITMSG` (recommended — pre-populates the next `git commit` buffer) → `write`
     - `Show in chat only` (no files touched) → `chat`
     - `Create the commit` (I commit the staged changes with the message) → `commit`

   For `write` or `chat`, immediately `Write` the answer to the state file, before drafting anything.

   For `commit`, ask a follow-up with `AskUserQuestion` before drafting:
   - question: "Keep committing automatically after this one?"
   - header: "Auto-commit"
   - options:
     - `Rest of this session` (recommended) → `Write` `commit` to the state file
     - `Every session in this repo` → `Write` `commit` to the state file **and** run `git config --local commit-msg.mode commit`
     - `Just this once` → write nothing; commit this run only, and the next run asks the delivery question again
5. **Single-run override** — if the user says so in the invocation (e.g. `/commit-msg just show me`), honour it for that run and leave the state file and repo setting untouched.
6. **Changing the default** — if the user asks to switch modes for the rest of the session, overwrite the state file with the new value. If they ask to stop auto-committing in this repo, also run `git config --local --unset commit-msg.mode`.

Choosing `commit` is the user's authorization to commit — for this run, the session, or every session in this repo, per the follow-up answer. That is what satisfies "never commit without being asked". Nothing else in this skill authorizes a commit.

**Resolve the target path first** (`write` mode only)**.** Do not hardcode `.git/NEXT_COMMITMSG` — that breaks in worktrees, where the per-worktree git dir lives at `.git/worktrees/<name>/`. Run `git rev-parse --git-path NEXT_COMMITMSG` and write to whatever path it returns; in a worktree this resolves to the worktree's own git dir, in the main repo it resolves to `.git/NEXT_COMMITMSG`.

## Steps

0. **Settle the delivery mode** — read the state file, then the repo setting; only ask if neither is set, and record the answer straight away. See above.

1. **Gather git state** — run all in parallel:
   - `git status` (to see staged vs unstaged files)
   - `git diff HEAD` (full diff of staged and unstaged changes)
   - `git log --oneline -10` (recent history to match tone and style)
   - `git rev-parse --git-path NEXT_COMMITMSG` (`write` mode only — the exact path to write to, worktree-aware)

   **If any files are staged, the message must describe only the staged changes.** Use `git diff --cached` as the source of truth and ignore unstaged changes when drafting. Only fall back to the full working tree (`git diff HEAD`) when nothing is staged.

2. **Draft the commit message** — follow these rules:
   - First line: imperative mood, ≤72 chars, no trailing period, no scope prefix unless an argument was passed to the skill
   - If an argument was passed (e.g. `/commit-msg auth`), prefix the subject with `scope: ` (e.g. `auth: add JWT refresh logic`)
   - Optional body: separate from subject with a blank line; explain *why*, not *what*; wrap at 72 chars
   - No `Co-Authored-By` or other trailers — the user adds those manually if wanted
   - Match the capitalization and style of recent commits in the log

3. **Deliver per the session mode:**
   - `write` — write to the path from step 1, no further prompting:
     ```
     <subject line>

     <optional body>
     ```
   - `chat` — write nothing; skip to step 4.
   - `commit` — run `git commit` with the drafted message. Commit **only what is already staged**; never `git add` files the user did not stage. If nothing is staged, say so and stop rather than staging on their behalf. Report the resulting commit's short SHA.

4. **Confirm** — show the message in a code block. `write`: say it's been written and they can commit via `git commit`, which reads it into the buffer. `chat`: just show the message. `commit`: report the commit SHA and which files went in.

## Notes

- If there are no staged or unstaged changes, report that immediately and stop.
- If the diff is large (many files or many hunks), summarize the intent rather than listing every file — keep the subject line crisp.
- Never add `Co-Authored-By: Claude` or any AI attribution trailers unless the user explicitly asks.
- This skill commits **only** in `commit` mode. In `write` and `chat` mode it never runs `git commit`, no matter how obvious committing seems.
- In `commit` mode, never amend, never force, never push — one plain `git commit` of the already-staged changes.
- Asking about delivery mode more than once per session is a bug (except after `Just this once`). Read the state file and repo setting before you decide you need to ask — "I don't remember asking" is not evidence the file is missing.
- Only `commit` is ever stored in the repo setting; `write` and `chat` stay per-session.
- If the system prompt names no scratchpad directory, still honour the repo setting; otherwise fall back to asking each run rather than inventing a path or writing state into the working tree.
