#!/usr/bin/env bash
# Tests for the viewer's rendering: markdown, Gherkin and in-app link rewriting.
# Drives the real page in headless Chrome and asserts on the rendered DOM.
# Skips (exit 0) when no Chrome is available.
# Usage: render.test.sh
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
chrome=""
for c in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
         "$(command -v google-chrome || true)" "$(command -v chromium || true)"; do
  [ -n "$c" ] && [ -x "$c" ] && chrome="$c" && break
done
[ -n "$chrome" ] || { echo "skip: no Chrome/Chromium — rendering not checked"; exit 0; }

pass=0; fail=0
tmp="$(mktemp -d)"
trap 'kill %1 2>/dev/null; wait %1 2>/dev/null; rm -rf "$tmp"' EXIT

# --- fixture: the markdown shapes the spec templates actually produce -------
repo="$tmp/repo"
mkdir -p "$repo/specs/features" "$repo/specs/ADR"
cd "$repo"
git init -q . && git config user.email t@t && git config user.name T
git config commit.gpgsign false

cat > specs/features/resolution.md <<'EOF'
# Feature: Column resolution

**Status**: passing

> Backing tests: `tests/test_matcher.py` (ladder ordering, confidence,
> thresholds), `tests/test_transform.py` (plan execution).

## User story

As a **data operator**, I want **columns matched automatically**, so that **files resolve**.

## Acceptance criteria

See [`resolution.feature`](./resolution.feature) and [alias learning](features/alias.md).

## Technical notes

- **Implementation locations**: `src/matcher.py` (ladder,
  rapidfuzz scoring, threshold), `src/plan.py`
- **Relevant principles / constraints**: deterministic before AI — the
  agent is a later rung, never consulted when the ladder resolves.
EOF
cat > specs/features/resolution.feature <<'EOF'
Feature: Column resolution

  Background:
    Given a loaded schema

  @draft
  Scenario: Exact name match resolves silently
    Given a target column "amount"
    When the source is analysed
    Then "amount" resolves with method "exact"

  Scenario Outline: Fuzzy threshold
    When the score is <score>
    Then it resolves <verdict>

    Examples:
      | score | verdict |
      | 0.95  | yes     |
EOF
cat > specs/features/alias.md <<'EOF'
# Feature: Alias learning

**Status**: draft
EOF
printf 'Feature: Alias learning\n\n  @draft\n  Scenario: Learns\n    Given an alias\n' > specs/features/alias.feature
mkdir -p specs/ADR
cat > specs/ADR/INDEX.md <<'EOF'
| Record | Status | Summary |
|---|---|---|
| [2026-01-01-ladder-order](2026-01-01-ladder-order.md) | accepted | Exact before fuzzy |
EOF
printf '# Ladder order\n\n**Status**: accepted · **Date**: 2026-01-01 · **Affects**: resolution\n' \
  > specs/ADR/2026-01-01-ladder-order.md

cat > specs/INDEX.md <<'EOF'
# Specs

| Feature | Status | Description |
|---|---|---|
| [resolution](features/resolution.md) | passing | Matching ladder |
| [alias](features/alias.md) | draft | Learned aliases |
EOF
git add -A && git commit -qm "Add specs"

port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
"$here/view.sh" "$repo/specs" --port "$port" --no-open >"$tmp/server.log" 2>&1 &
for _ in $(seq 1 60); do
  curl -fsS "http://127.0.0.1:$port/api/validate" >/dev/null 2>&1 && break
  perl -e 'select undef,undef,undef,0.25'
done

dom="$tmp/dom.html"
"$chrome" --headless --disable-gpu --virtual-time-budget=6000 \
  --dump-dom "http://127.0.0.1:$port/#/feature/resolution" > "$dom" 2>/dev/null

# check <name> <python-expr over `d` (the dumped DOM text)>
check() {
  if python3 -c '
import re, sys
d = open(sys.argv[1]).read()
main = d[d.find("<main"):d.find("</main>")]
sys.exit(0 if ('"$2"') else 1)
' "$dom" 2>/dev/null; then
    pass=$((pass+1)); printf 'ok   %s\n' "$1"
  else
    fail=$((fail+1)); printf 'FAIL %s\n     %s\n' "$1" "$2"
  fi
}

# --- the page rendered at all ----------------------------------------------
check "feature page rendered"        '"Column resolution" in main'
check "scenarios section present"    '"Exact name match resolves silently" in main'

# --- the title is not printed twice ----------------------------------------
check "exactly one h1"               'main.count("<h1") == 1'
check "no repeated heading text"     'main.count("Column resolution") <= 2'
check "status line not duplicated"   '"<strong>Status</strong>" not in main'

# --- markdown blocks --------------------------------------------------------
check "blockquote is one block"      'main.count("<blockquote>") == 1'
check "blockquote lines joined"      're.search(r"ladder ordering.*?thresholds", main, re.S) is not None'
check "wrapped list item stays one"  're.search(r"<li>(?:(?!</li>).)*rapidfuzz scoring", main, re.S) is not None'
check "second bullet also joined"    're.search(r"<li>(?:(?!</li>).)*never consulted", main, re.S) is not None'
check "two bullets, not four"        'main.count("<li>") == 2'

# --- link rewriting ---------------------------------------------------------
check "sibling .feature link routed" '"#/feature/resolution" in main'
check "features/ link routed"        '"#/feature/alias" in main'
check "no raw .md href left"         '".md\"" not in main'

# --- gherkin ----------------------------------------------------------------
check "step keywords classed"        '"k Given" in main and "k When" in main and "k Then" in main'
check "draft scenario flagged"       '"is-draft" in main'
check "examples table rendered"      '"<table>" in main and "verdict" in main'
check "outline keyword shown"        '"Scenario Outline" in main'
check "background named once"        'main.count("Background") == 1'

# --- history ----------------------------------------------------------------
check "history rendered"             '"Add specs" in main'
check "commits deep-link"            '"#/feature/resolution/" in main'

# --- a commit's diff, opened by deep link -----------------------------------
"$chrome" --headless --disable-gpu --virtual-time-budget=6000 \
  --dump-dom "http://127.0.0.1:$port/#/feature/resolution/$(git -C "$repo" rev-parse --short HEAD)" \
  > "$tmp/diff.html" 2>/dev/null
dom="$tmp/diff.html"
check "diff pane rendered"           '"class=\"diff\"" in main'
check "added lines marked"           '"class=\"p\"" in main'
check "selected commit highlighted"  '"commit on" in main'
check "feature still rendered"       '"Exact name match" in main'

# --- feature pair side by side ----------------------------------------------
check "pair is split into columns"   '"class=\"split\"" in main'
check "markdown is the left column"  're.search("col md.*?User story", main, re.S) is not None'
check "gherkin is the right column"  're.search("col bdd.*?Exact name match", main, re.S) is not None'
check "markdown precedes gherkin"    'main.find("col md") < main.find("col bdd")'
check "history spans full width"     'main.find("col bdd") < main.find("History")'

# --- headings are colour-coded by section -----------------------------------
check "known section is classed"     '"sec-user-story" in main'
check "second section is classed"    '"sec-technical-notes" in main'
check "every heading gets sec"       'main.count("class=\"sec") >= 3'

# --- the sidebar ------------------------------------------------------------
side="$tmp/side.html"
"$chrome" --headless --disable-gpu --virtual-time-budget=6000 \
  --dump-dom "http://127.0.0.1:$port/#/" > "$side" 2>/dev/null
dom="$side"
check_side() {
  if python3 -c '
import re, sys
d = open(sys.argv[1]).read()
main = d[d.find("<nav"):d.find("</nav>")]
sys.exit(0 if ('"$2"') else 1)
' "$dom" 2>/dev/null; then
    pass=$((pass+1)); printf 'ok   %s\n' "$1"
  else
    fail=$((fail+1)); printf 'FAIL %s\n     %s\n' "$1" "$2"
  fi
}
check_side "ADR listed by name"      '"ladder-order" in main'
check_side "ADR shows its status"    '">accepted<" in main'
check_side "no raw status in nav"    '"Affects" not in main'
check_side "decision state classed"  '"adr-accepted" in main'

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
