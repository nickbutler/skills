#!/usr/bin/env bash
# Tests for view.sh — starts the real server against a fixture spec set in a
# real git repo, then asserts on what it serves.
# Usage: view.test.sh
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
pass=0; fail=0
tmp="$(mktemp -d)"
trap 'kill %1 2>/dev/null; wait %1 2>/dev/null; rm -rf "$tmp"' EXIT

# --- fixture: a spec set with two commits of history ------------------------
repo="$tmp/repo"
mkdir -p "$repo/specs/features" "$repo/specs/ADR" "$repo/specs/changes/archive"
cd "$repo"
git init -q . && git config user.email t@t && git config user.name T
git config commit.gpgsign false   # the fixture must not depend on the user's signing setup

cat > specs/features/login.md <<'EOF'
# Feature: Login

**Status**: draft

## User story

As a **returning user**, I want **to sign in**, so that **I see my dashboard**.
EOF
cat > specs/features/login.feature <<'EOF'
Feature: Login
  As a returning user
  I want to sign in

  Background:
    Given I navigate to /login

  @draft @slow
  Scenario: User signs in
    When I click the Sign in button
    Then I should see "Welcome"

  Scenario Outline: Bad credentials
    When I fill in Password with <password>
    Then I should see an error <message>

    Examples:
      | password | message  |
      | ""       | Required |
EOF
cat > specs/INDEX.md <<'EOF'
# Specs

| Feature | Status | Description |
|---|---|---|
| [login](features/login.md) | draft | Signing in |
EOF
cat > specs/ADR/INDEX.md <<'EOF'
| Record | Status | Description |
|---|---|---|
| [2026-01-01-use-sqlite](2026-01-01-use-sqlite.md) | accepted | Storage choice |
EOF
printf '# Use SQLite\n\n**Status**: accepted · **Date**: 2026-01-01 · **Affects**: login\n\nBecause it is one file.\n' > specs/ADR/2026-01-01-use-sqlite.md
cat > specs/changes/add-sso.md <<'EOF'
# Change: Add SSO

**Status**: in progress

## Features touched
- [login](../features/login.md) — modified

## Tasks
- [x] 1.1 Wire the provider
- [ ] 1.2 Add the button
EOF
git add -A && git commit -qm "Add the login spec"
printf '\n## Context\n\nSecond commit.\n' >> specs/features/login.md
git add -A && git commit -qm "Note the login context"

# a second change, in flight on its own branch, claiming the same feature
git checkout -q -b feat/2fa
cat > specs/changes/add-2fa.md <<'EOF'
# Change: Add two-factor

## Features touched
- [login](../features/login.md) — modified

## Tasks
- [ ] 1.1 Send the code
EOF
git add -A && git commit -qm "Propose 2FA"
git checkout -q -

# --- start the server -------------------------------------------------------
port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
"$here/view.sh" "$repo/specs" --port "$port" --no-open >"$tmp/server.log" 2>&1 &
for _ in $(seq 1 60); do
  curl -fsS "http://127.0.0.1:$port/api/validate" >/dev/null 2>&1 && break
  perl -e 'select undef,undef,undef,0.25'
done

base="http://127.0.0.1:$port"

# ok <name> <url> <python-expr over `d` (parsed json) or `t` (raw text)>
ok() {
  local name="$1" url="$2" expr="$3"
  local body; body="$(curl -fsS "$base$url" 2>&1)"
  if python3 -c '
import json,sys
t = sys.stdin.read()
try: d = json.loads(t)
except Exception: d = None
sys.exit(0 if ('"$expr"') else 1)
' <<<"$body" 2>/dev/null; then
    pass=$((pass+1)); printf 'ok   %s\n' "$name"
  else
    fail=$((fail+1)); printf 'FAIL %s\n     %s\n     %s\n' "$name" "$expr" "${body:0:400}"
  fi
}

# status <name> <url> <expected-code>
status() {
  local name="$1" code
  code="$(curl -s -o /dev/null -w '%{http_code}' "$base$2")"
  if [ "$code" = "$3" ]; then
    pass=$((pass+1)); printf 'ok   %s\n' "$name"
  else
    fail=$((fail+1)); printf 'FAIL %s (HTTP %s, want %s)\n' "$name" "$code" "$3"
  fi
}

# --- the app shell ----------------------------------------------------------
status "GET / serves the app"            "/"          200
ok     "app shell has a title"           "/"          '"<title>" in t'
status "app.css is served"               "/app.css"   200
status "app.js is served"                "/app.js"    200

# --- spec index -------------------------------------------------------------
ok "index lists the feature"        "/api/spec" 'd["features"][0]["slug"] == "login"'
ok "index carries status"           "/api/spec" 'd["features"][0]["status"] == "draft"'
ok "index counts scenarios"         "/api/spec" 'd["features"][0]["scenarios"] == 2'
ok "index counts draft scenarios"   "/api/spec" 'd["features"][0]["draft"] == 1'
ok "index carries the description"  "/api/spec" 'd["features"][0]["description"] == "Signing in"'
ok "index summarises progress"      "/api/spec" 'd["progress"]["draft"] == 1'
ok "index lists changes"            "/api/spec" 'd["changes"][0]["slug"] == "add-sso"'
ok "change task counts"             "/api/spec" 'd["changes"][0]["done"] == 1 and d["changes"][0]["total"] == 2'
ok "index lists ADRs"               "/api/spec" 'd["adrs"][0]["slug"] == "2026-01-01-use-sqlite"'
ok "ADR status is a token"          "/api/spec" 'd["adrs"][0]["status"] == "accepted"'
ok "ADR keeps the whole line"       "/api/spec" '"Affects" in d["adrs"][0]["raw_status"]'

# --- changes in flight on other branches ------------------------------------
ok "in flight lists other branches" "/api/spec" 'any(c["branch"] == "feat/2fa" for c in d["inflight"])'
ok "in flight carries the slug"     "/api/spec" 'any(c["slug"] == "add-2fa" for c in d["inflight"])'
ok "in flight names its features"   "/api/spec" 'any(c["features"] == ["login"] for c in d["inflight"])'
ok "current branch marked current"  "/api/spec" 'any(c["current"] and c["slug"] == "add-sso" for c in d["inflight"])'
ok "collision surfaces as a warning" "/api/validate" 'any("feat/2fa" in w for w in d["notes"] + d.get("warnings", []))'

ok "a branch change is readable"    "/api/change/add-2fa?branch=feat/2fa" '"Send the code" in d["body"]'
ok "branch change knows its branch" "/api/change/add-2fa?branch=feat/2fa" 'd["branch"] == "feat/2fa"'
status "branch change needs a branch" "/api/change/add-2fa" 404
status "unknown branch is 404"        "/api/change/add-2fa?branch=feat/nope" 404

# --- one feature ------------------------------------------------------------
ok "feature returns markdown"    "/api/feature/login" '"returning user" in d["markdown"]'
ok "feature name parsed"         "/api/feature/login" 'd["parsed"]["name"] == "Login"'
ok "narrative captured"          "/api/feature/login" 'd["parsed"]["narrative"][0].startswith("As a")'
ok "background is a scenario"    "/api/feature/login" 'd["parsed"]["scenarios"][0]["background"] is True'
ok "step keyword split out"      "/api/feature/login" 'd["parsed"]["scenarios"][1]["steps"][0]["keyword"] == "When"'
ok "step text split out"         "/api/feature/login" 'd["parsed"]["scenarios"][1]["steps"][0]["text"] == "I click the Sign in button"'
ok "tags preserved"              "/api/feature/login" '"@slow" in d["parsed"]["scenarios"][1]["tags"]'
ok "draft flagged"               "/api/feature/login" 'd["parsed"]["scenarios"][1]["draft"] is True'
ok "outline examples parsed"     "/api/feature/login" 'd["parsed"]["scenarios"][2]["examples"][0] == ["password", "message"]'
ok "changes touching it linked"  "/api/feature/login" 'd["changes"][0]["slug"] == "add-sso"'
status "unknown feature is 404"  "/api/feature/nope" 404

# --- git history ------------------------------------------------------------
ok "history has both commits"    "/api/history/login" 'len(d["commits"]) == 2'
ok "history is newest first"     "/api/history/login" 'd["commits"][0]["subject"] == "Note the login context"'
ok "history carries author"      "/api/history/login" 'd["commits"][0]["author"] == "T"'
ok "history carries a date"      "/api/history/login" 'd["commits"][0]["date"].startswith("20")'
ok "diff for a commit"           "/api/diff/HEAD/login" '"Second commit." in d["diff"]'
status "unknown sha is 404"      "/api/diff/nosuchsha/login" 404

# --- changes and ADRs -------------------------------------------------------
ok "change body served"       "/api/change/add-sso" '"Wire the provider" in d["body"]'
ok "change tasks parsed"      "/api/change/add-sso" 'd["tasks"][0]["done"] is True and d["tasks"][1]["done"] is False'
ok "ADR body served"          "/api/adr/2026-01-01-use-sqlite" '"one file" in d["body"]'
status "unknown ADR is 404"   "/api/adr/nope" 404

# --- validation -------------------------------------------------------------
ok "validate reports ok"      "/api/validate" 'd["ok"] is True'
ok "validate has a summary"   "/api/validate" '"1 features" in d["summary"]'

# --- safety -----------------------------------------------------------------
status "traversal is refused"     "/api/feature/..%2f..%2f..%2fetc%2fpasswd" 404
status "unknown route is 404"     "/api/nope" 404

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
