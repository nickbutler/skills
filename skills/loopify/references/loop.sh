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

# One loop per repository. Two loops on one queue is double spend, and the
# label claim only protects against a race it can see.
exec 9>"$LOGS/.lock"
flock -n 9 || {
  echo "another loop already holds $LOGS/.lock" >&2
  exit 1
}

# The oldest open issue with $1 that no run has already claimed.
queue() {
  gh issue list --repo "$REPO" --state open --label "$1" --json number,labels --jq '
    [ .[] | select(any(.labels[].name; . == "agent:speccing" or . == "agent:building") | not) ]
    | sort_by(.number) | first | .number // empty'
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
  if timeout "$TIMEOUT" claude -p "/work" \
    --permission-mode acceptEdits \
    --output-format json >"$log"; then

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
        --body "A run finished without claiming this — usually a tool it was not permitted to use. Log: \`$log\`. Check \`permission_denials\` in it before trying again." \
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
