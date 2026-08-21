#!/usr/bin/env bash
#
# Poll the queue in shell; spend tokens only when there is work.
#
# The check is a `gh` call and costs nothing, so it can run often. A run is a
# single `claude -p`, which does one stage and exits by itself — print mode is
# non-interactive and returns when the turn completes. Nothing is kept alive
# between runs, so a wedged session cannot poison the next one.
#
#   ./loop.sh                 from anywhere inside the checkout
#   REPO=owner/name ./loop.sh  to override the repo it watches
#
set -euo pipefail

# Work from the repository root whatever directory this was started in: the paths
# below are relative to it, and so are the worktrees.
cd "$(git rev-parse --show-toplevel)" || exit 1

# `gh` already knows the repo from the remotes, so asking for it again is one more
# thing to get wrong. The override exists for the case of several remotes, where
# there is a real choice to make.
REPO="${REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)}"
if [ -z "$REPO" ]; then
  echo "cannot work out which repository this is — run it inside one, or set REPO=owner/name" >&2
  exit 1
fi
IDLE="${IDLE:-300}"          # seconds between polls when the queue is empty
SETTLE="${SETTLE:-15}"       # pause after a run, before looking again
TIMEOUT="${TIMEOUT:-30m}"    # a run that hangs must not block the queue forever
LOGS="${LOGS:-.agent/logs}"

mkdir -p "$LOGS"

# Preflight the permissions before the first tick. A non-interactive run cannot be
# granted anything at a prompt, so a missing or malformed rule does not ask — it
# denies, the run exits clean having done nothing, and the queue check has to
# rescue the issue. All of that is avoidable here, at no cost, before anything
# starts. Set SKIP_PREFLIGHT=1 if the grants live somewhere this cannot see.
if [ -z "${SKIP_PREFLIGHT:-}" ]; then
  settings=$(ls .claude/settings.json .claude/settings.local.json 2>/dev/null || true)

  if [ -z "$settings" ]; then
    echo "no .claude/settings.json — every tool call in a print-mode run will be denied." >&2
    echo "grant at least: \"Bash(gh:*)\", \"Bash(git:*)\", and the project's own commands." >&2
    exit 1
  fi

  # `Bash(gh :*)` — a space before the colon — parses, matches nothing, and fails
  # exactly like a missing rule. Worth naming, because it is invisible by eye.
  if grep -qE '"Bash\([^)"]* :\*\)"' $settings; then
    echo "a permission rule has a space before its colon, so it matches nothing:" >&2
    grep -nE '"Bash\([^)"]* :\*\)"' $settings >&2
    echo "write it as Bash(gh:*), not Bash(gh :*)." >&2
    exit 1
  fi

  for needs in gh git; do
    grep -qE "\"Bash\"|\"Bash\($needs:" $settings || {
      echo "$settings does not grant $needs — a run will be denied and do nothing." >&2
      echo "add \"Bash($needs:*)\" to permissions.allow." >&2
      exit 1
    }
  done
fi

# One loop per repository: two loops on one queue is double spend, and the label
# claim only protects against a race it can see.
#
# `mkdir` rather than flock, which macOS does not ship, or shlock, which does not
# reclaim a lock left by a killed process. A directory is created atomically on
# every POSIX system, and the pid inside it says whether the holder is still
# alive — so a `kill -9` costs the next run one liveness check, not a wedged
# queue and a hand-deleted file.
LOCK="$LOGS/.lock"
held() { [ -f "$LOCK/pid" ] && kill -0 "$(cat "$LOCK/pid" 2>/dev/null)" 2>/dev/null; }

if ! mkdir "$LOCK" 2>/dev/null; then
  if held; then
    echo "another loop holds $LOCK (pid $(cat "$LOCK/pid"))" >&2
    exit 1
  fi
  echo "clearing a lock left by pid $(cat "$LOCK/pid" 2>/dev/null || echo '?')" >&2
  rm -rf "$LOCK"
  mkdir "$LOCK" 2>/dev/null || { echo "lost the race for $LOCK" >&2; exit 1; }
fi
echo $$ >"$LOCK/pid"
trap 'rm -rf "$LOCK"' EXIT INT TERM

# `timeout` is GNU, so it is missing on a stock mac and named `gtimeout` under
# homebrew coreutils. A missing one is not fatal — it only means a wedged run
# blocks the queue until someone notices — but it must be said out loud.
CAP=()
if command -v timeout >/dev/null 2>&1; then
  CAP=(timeout "$TIMEOUT")
elif command -v gtimeout >/dev/null 2>&1; then
  CAP=(gtimeout "$TIMEOUT")
else
  echo "no timeout(1) on PATH — a wedged run will not be cut off" >&2
fi

# The oldest open issue with $1 that no run has already claimed.
queue() {
  gh issue list --repo "$REPO" --state open --label "$1" --json number,labels --jq '
    [ .[] | select(any(.labels[].name; . == "agent:speccing" or . == "agent:building") | not) ]
    | sort_by(.number) | first | .number // empty'
}

# `--output-format json` says nothing until the run ends, which for a build is
# eight silent minutes. `stream-json` emits an event per step instead; this turns
# those into one readable line each, while `tee` keeps the raw stream for the log.
# Never exits early or non-zero: it is downstream of the run, and a narrator that
# dies would take the run with it.
narrate() {
  if ! command -v python3 >/dev/null 2>&1; then
    cat >/dev/null
    return 0
  fi
  python3 -c '
import sys, json

def short(v):
    return " ".join(str(v).split())[:96]

for line in sys.stdin:
    try:
        event = json.loads(line)
    except Exception:
        continue
    try:
        kind = event.get("type")
        if kind == "assistant":
            for block in event.get("message", {}).get("content", []):
                if block.get("type") == "tool_use":
                    args = block.get("input", {}) or {}
                    detail = args.get("command") or args.get("file_path") or args.get("pattern") or ""
                    print("   .", block.get("name"), short(detail), flush=True)
                elif block.get("type") == "text" and block.get("text", "").strip():
                    print("    ", short(block["text"]), flush=True)
        elif kind == "result":
            print("   =", event.get("subtype"), str(event.get("num_turns")), "turns",
                  "$" + str(round(event.get("total_cost_usd") or 0, 2)), flush=True)
    except Exception:
        continue
' 2>/dev/null || cat >/dev/null
}

echo "watching $REPO — build before approved, ${IDLE}s when idle"

while :; do
  # Finish before starting: the build queue outranks the spec queue.
  issue="$(queue build || true)"
  [ -z "$issue" ] && issue="$(queue approved || true)"

  if [ -z "$issue" ]; then
    sleep "$IDLE"
    continue
  fi

  log="$LOGS/$(date +%Y%m%d-%H%M%S)-issue-$issue.json"
  echo "issue #$issue — starting, logging to $log"

  # The command works out which stage this is; the poll above only decides
  # whether it is worth waking anything at all.
  if "${CAP[@]}" claude -p "/work" \
    --permission-mode acceptEdits \
    --output-format stream-json --verbose |
    tee "$log" | narrate; then

    # Exiting zero is not evidence of work. A run blocked on a permission it
    # cannot be granted non-interactively reports success, having done nothing —
    # and the issue is still sitting in the queue with its trigger label on. Left
    # alone, the next poll picks up the same issue and buys the same nothing,
    # forever. Judge the run by whether the queue moved, not by its exit code.
    if [ "$(gh issue view "$issue" --repo "$REPO" --json labels \
      --jq 'any(.labels[].name; . == "approved" or . == "build")')" = "true" ]; then
      echo "issue #$issue — exited clean but the label never moved; blocking it" >&2
      gh issue edit "$issue" --repo "$REPO" \
        --remove-label approved --remove-label build \
        --add-label agent:blocked >/dev/null 2>&1 || true
      gh issue comment "$issue" --repo "$REPO" \
        --body "A run finished without claiming this — usually a tool it was not permitted to use. Log: \`$log\` (newline-delimited events; the last line holds \`permission_denials\`)." \
        >/dev/null 2>&1 || true
    else
      echo "issue #$issue — finished"
    fi

  else
    rc=$?
    echo "issue #$issue — run exited $rc, see $log" >&2

    # Hand the issue back from out here too. A run killed by the timeout never
    # reaches its own failure path, and a claim label nothing clears is worse
    # than a failure: the queue skips claimed issues, so it would be stuck and
    # invisible while the loop idles past it every few minutes. These calls are
    # no-ops when the run already blocked it itself.
    gh issue edit "$issue" --repo "$REPO" \
      --remove-label agent:speccing --remove-label agent:building \
      --add-label agent:blocked >/dev/null 2>&1 || true
    gh issue comment "$issue" --repo "$REPO" \
      --body "Run exited $rc without handing this back — log: \`$log\`. Re-add \`approved\` or \`build\` to try again." \
      >/dev/null 2>&1 || true

    # No retry. The block takes it off the queue until a human puts it back; a
    # retrying loop spends the same tokens on the same failure until morning.
  fi

  sleep "$SETTLE"
done
