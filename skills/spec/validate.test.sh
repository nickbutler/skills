#!/usr/bin/env bash
# Tests for validate.sh. Each case builds a fixture spec set in a temp dir,
# mutates one thing, and asserts the exit code and message.
# Usage: validate.test.sh
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
validate="$here/validate.sh"
pass=0; fail=0

# A minimal spec set that must validate clean.
mk_valid() {
  local d="$1"
  mkdir -p "$d/features" "$d/ADR"
  cat > "$d/features/login.md" <<'EOF'
# Login

**Status**: draft
EOF
  cat > "$d/features/login.feature" <<'EOF'
Feature: Login

  Scenario: User signs in
    Given I navigate to /login
    When I click the Sign in button
    Then I should see "Welcome"
EOF
  cat > "$d/INDEX.md" <<'EOF'
# Specs

| Feature | Status | Description |
|---|---|---|
| [login](features/login.md) | draft | Signing in |
EOF
  cat > "$d/ADR/INDEX.md" <<'EOF'
| Record | Status | Description |
|---|---|---|
| [2026-01-01-use-sqlite](2026-01-01-use-sqlite.md) | accepted | Storage choice |
EOF
  cat > "$d/ADR/2026-01-01-use-sqlite.md" <<'EOF'
# Use SQLite

**Status**: accepted
EOF
}

# check <name> <expected-exit> <expected-substring-or-""> <mutator-fn>
check() {
  local name="$1" want="$2" needle="$3" mutate="$4"
  local d; d="$(mktemp -d)"
  mk_valid "$d/specs"
  "$mutate" "$d"
  local out; out="$("$validate" "$d/specs" 2>&1)"; local got=$?
  local ok=1
  [ "$got" = "$want" ] || ok=0
  [ -z "$needle" ] || grep -qi -- "$needle" <<<"$out" || ok=0
  if [ "$ok" = 1 ]; then
    pass=$((pass+1)); printf 'ok   %s\n' "$name"
  else
    fail=$((fail+1))
    printf 'FAIL %s (exit %s, want %s)\n' "$name" "$got" "$want"
    [ -n "$needle" ] && printf '     wanted output matching: %s\n' "$needle"
    sed 's/^/     | /' <<<"$out"
  fi
  rm -rf "$d"
}

noop() { :; }

# --- pairing ---------------------------------------------------------------
rm_feature()   { rm "$1/specs/features/login.feature"; }
rm_md()        { rm "$1/specs/features/login.md"; }

# --- status ----------------------------------------------------------------
bad_status()   { sed -i.bak 's/\*\*Status\*\*: draft/**Status**: wibble/' "$1/specs/features/login.md"; }
no_status()    { printf '# Login\n' > "$1/specs/features/login.md"; }
mixed_status() {
  no_status "$1"
  printf '# Logout\n\n**Status**: passing\n' > "$1/specs/features/logout.md"
  printf 'Feature: Logout\n\n  Scenario: User signs out\n    Given I navigate to /logout\n' > "$1/specs/features/logout.feature"
  printf '| [logout](features/logout.md) | passing | Signing out |\n' >> "$1/specs/INDEX.md"
}

# a trailing note after the status token is allowed; the token still isn't
annotated_status()  { sed -i.bak 's/\*\*Status\*\*: draft/**Status**: draft — pending review/' "$1/specs/features/login.md"; }
annotated_index()   { annotated_status "$1"; sed -i.bak 's/| draft | Signing in/| draft † | Signing in/' "$1/specs/INDEX.md"; }
annotated_bad()     { sed -i.bak 's/\*\*Status\*\*: draft/**Status**: wibble — pending review/' "$1/specs/features/login.md"; }

# --- INDEX -----------------------------------------------------------------
index_missing_row() { grep -v '^| \[login\]' "$1/specs/INDEX.md" > "$1/t" && mv "$1/t" "$1/specs/INDEX.md"; }
index_phantom_row() { printf '| [ghost](features/ghost.md) | draft | Not real |\n' >> "$1/specs/INDEX.md"; }
index_status_drift(){ sed -i.bak 's/| draft | Signing in/| passing | Signing in/' "$1/specs/INDEX.md"; }

# --- Gherkin ---------------------------------------------------------------
no_scenario()  { printf 'Feature: Login\n' > "$1/specs/features/login.feature"; }
no_feature_kw(){ printf '  Scenario: User signs in\n    Given I navigate to /login\n' > "$1/specs/features/login.feature"; }
bad_step_kw()  { sed -i.bak 's/^    When I click/    Whne I click/' "$1/specs/features/login.feature"; }
empty_scenario(){ printf 'Feature: Login\n\n  Scenario: Nothing happens\n\n  Scenario: User signs in\n    Given I navigate to /login\n' > "$1/specs/features/login.feature"; }

# --- legal Gherkin that isn't a step --------------------------------------
narrative() {
  printf 'Feature: Login\n  As a returning user\n  I want to sign in\n  So that I see my dashboard\n\n  Scenario: User signs in\n    Given I navigate to /login\n    Then I should see "Welcome"\n' \
    > "$1/specs/features/login.feature"
}
docstring_mermaid() {
  cat > "$1/specs/features/login.feature" <<'EOF'
Feature: Login

  Scenario: User signs in
    Given the diagram source
      """
      sequenceDiagram
      participant A
      A->>+B: go
      """
    Then I should see "Welcome"
EOF
}
outline_table() {
  cat > "$1/specs/features/login.feature" <<'EOF'
Feature: Login

  Background:
    Given I navigate to /login

  Scenario Outline: Bad credentials
    When I fill in Password with <password>
    Then I should see an error <message>

    Examples:
      | password | message        |
      | ""       | Required       |
      | short    | Too short      |
EOF
}

# --- steps vs step_definitions --------------------------------------------
with_steps() {
  mkdir -p "$1/step_definitions"
  cat > "$1/step_definitions/web.py" <<'EOF'
@given(parsers.parse("I navigate to {url}"))
def _nav(url): ...

@when(parsers.parse("I click the {text} button"))
def _click(text): ...

@then(parsers.parse('I should see "{text}"'))
def _see(text): ...
EOF
}
undefined_step_untagged() {
  with_steps "$1"
  printf 'Feature: Login\n\n  Scenario: User signs in\n    Given I hum a little tune\n    Then I should see "Welcome"\n' \
    > "$1/specs/features/login.feature"
}
# Gherkin has no way to tag a Background, so it is only exempt when the whole
# file is draft.
undefined_background_live() {
  with_steps "$1"
  printf 'Feature: Login\n\n  Background:\n    Given I hum a little tune\n\n  Scenario: User signs in\n    Then I should see "Welcome"\n' \
    > "$1/specs/features/login.feature"
}
undefined_background_draft() {
  with_steps "$1"
  printf 'Feature: Login\n\n  Background:\n    Given I hum a little tune\n\n  @draft\n  Scenario: User signs in\n    Then I should see "Welcome"\n' \
    > "$1/specs/features/login.feature"
}
undefined_step_tagged() {
  with_steps "$1"
  printf 'Feature: Login\n\n  @draft\n  Scenario: User signs in\n    Given I hum a little tune\n    Then I should see "Welcome"\n' \
    > "$1/specs/features/login.feature"
}
defined_steps_only() { with_steps "$1"; }

# `archived` is a status only inside archived/
mk_archived() {
  mkdir -p "$1/specs/archived"
  printf '# Old Thing\n\n**Status**: %s\n' "$2" > "$1/specs/archived/old-thing.md"
  printf 'Feature: Old Thing\n\n  Scenario: It worked\n    Given I navigate to /old\n' > "$1/specs/archived/old-thing.feature"
}
archived_status_ok()   { mk_archived "$1" "archived (was draft)"; }
archived_live_status() { mk_archived "$1" "passing"; }
live_archived_status() { sed -i.bak 's/\*\*Status\*\*: draft/**Status**: archived/' "$1/specs/features/login.md"; }

# a description cell may itself contain a pipe (inline code, alternatives)
piped_desc() {
  sed -i.bak 's/| draft | Signing in |/| draft | `mode: sso | password` per tenant |/' "$1/specs/INDEX.md"
}
piped_adr_desc() {
  sed -i.bak 's/| accepted | Storage choice |/| accepted | `sqlite | postgres` — sqlite wins |/' "$1/specs/ADR/INDEX.md"
}

# --- quality: a scenario must assert something ------------------------------
set_status() {   # set_status <dir> <status>
  sed -i.bak "s/\*\*Status\*\*: draft/**Status**: $2/" "$1/specs/features/login.md"
  sed -i.bak "s/| draft |/| $2 |/" "$1/specs/INDEX.md"
}
no_assertion()   {
  printf 'Feature: Login\n\n  Scenario: User signs in\n    Given I navigate to /login\n    When I click the Sign in button\n' \
    > "$1/specs/features/login.feature"
}
background_only_given() {
  printf 'Feature: Login\n\n  Background:\n    Given I navigate to /login\n\n  Scenario: User signs in\n    When I click the Sign in button\n    Then I should see "Welcome"\n' \
    > "$1/specs/features/login.feature"
}

# --- quality: no unresolved markers once the code is claimed to run ---------
marker_when_passing() { set_status "$1" passing; printf '\n- **Implementation locations**: TBD (no code yet)\n' >> "$1/specs/features/login.md"; }
marker_when_ready()   { set_status "$1" ready;   printf '\n- **Implementation locations**: TBD (no code yet)\n' >> "$1/specs/features/login.md"; }
marker_when_draft()   { printf '\n- **Implementation locations**: TBD (no code yet)\n' >> "$1/specs/features/login.md"; }

# --- quality: locators must be visible text, never selectors ----------------
css_locator()   { sed -i.bak 's|When I click the Sign in button|When I click "css=.btn-primary"|' "$1/specs/features/login.feature"; }
xpath_locator() { sed -i.bak 's|When I click the Sign in button|When I click //div[@id="go"]|' "$1/specs/features/login.feature"; }

# --- quality: a claimed feature cannot be entirely unreviewed ---------------
all_draft_with_steps() {
  with_steps "$1"
  set_status "$1" ready
  printf 'Feature: Login\n\n  @draft\n  Scenario: User signs in\n    Given I navigate to /login\n    Then I should see "Welcome"\n' \
    > "$1/specs/features/login.feature"
}
all_draft_no_steps() {
  set_status "$1" ready
  printf 'Feature: Login\n\n  @draft\n  Scenario: User signs in\n    Given I navigate to /login\n    Then I should see "Welcome"\n' \
    > "$1/specs/features/login.feature"
}
some_draft_with_steps() {
  with_steps "$1"
  set_status "$1" ready
  printf 'Feature: Login\n\n  @draft\n  Scenario: A\n    Given I navigate to /login\n    Then I should see "Welcome"\n\n  Scenario: B\n    Given I navigate to /login\n    Then I should see "Welcome"\n' \
    > "$1/specs/features/login.feature"
}

# --- ADR -------------------------------------------------------------------
adr_orphan_file() { printf '# Use Redis\n\n**Status**: accepted\n' > "$1/specs/ADR/2026-02-02-use-redis.md"; }
adr_phantom_row() { printf '| [2026-03-03-use-kafka](2026-03-03-use-kafka.md) | accepted | Queues |\n' >> "$1/specs/ADR/INDEX.md"; }
adr_bad_name()    { printf '# Notes\n' > "$1/specs/ADR/thoughts.md"; }

# --- changes ---------------------------------------------------------------
mk_change() {
  mkdir -p "$1/specs/changes"
  cat > "$1/specs/changes/add-sso.md" <<'EOF'
# Change: Add SSO

**Status**: in progress

## Why
Users want one login.

## Features touched
- [login](../features/login.md) — modified

## Tasks
- [ ] 1.1 Wire the provider
- [x] 1.2 Add the button
EOF
}
change_ok()            { mk_change "$1"; }
change_bad_feature()   { mk_change "$1"; sed -i.bak 's|../features/login.md|../features/nope.md|' "$1/specs/changes/add-sso.md"; }
change_no_tasks()      { mk_change "$1"; sed -i.bak '/^- \[/d' "$1/specs/changes/add-sso.md"; }
archive_change()       {
  mkdir -p "$1/specs/changes/archive"
  mv "$1/specs/changes/add-sso.md" "$1/specs/changes/archive/2026-01-05-add-sso.md"
}
# an archived change with an open task is a lie about what shipped
change_archived()      { mk_change "$1"; sed -i.bak 's/- \[ \]/- [x]/' "$1/specs/changes/add-sso.md"; archive_change "$1"; }
change_arch_unticked() { mk_change "$1"; archive_change "$1"; }

# --- draft accounting ------------------------------------------------------
two_drafts() {
  printf 'Feature: Login\n\n  @draft\n  Scenario: A\n    Given I navigate to /login\n    Then I should see "A"\n\n  @draft\n  Scenario: B\n    Given I navigate to /login\n    Then I should see "B"\n' \
    > "$1/specs/features/login.feature"
}

# --- missing tree ----------------------------------------------------------
no_specs_dir() { rm -rf "$1/specs"; }

check "valid tree passes"                 0 "ok"                       noop
check "missing .feature fails"            1 "login.feature"            rm_feature
check "missing .md fails"                 1 "login.md"                 rm_md
check "unknown status fails"              1 "wibble"                   bad_status
check "absent status line fails"          1 "status"                   no_status
check "absent status still summarises"    1 "2 features"                mixed_status
check "feature narrative allowed"         0 "ok"                        narrative
check "docstring content allowed"         0 "ok"                        docstring_mermaid
check "outline table and background ok"   0 "ok"                        outline_table
check "pipe in INDEX description ok"      0 "ok"                        piped_desc
check "pipe in ADR description ok"        0 "ok"                        piped_adr_desc
check "annotated status passes"           0 "ok"                        annotated_status
check "annotated status both sides ok"    0 "ok"                        annotated_index
check "annotated unknown status fails"    1 "wibble"                     annotated_bad
check "feature absent from INDEX fails"   1 "INDEX"                    index_missing_row
check "INDEX row without file fails"      1 "ghost"                    index_phantom_row
check "INDEX status drift fails"          1 "passing"                  index_status_drift
check "feature with no scenario fails"    1 "scenario"                 no_scenario
check "file with no Feature: fails"       1 "Feature:"                 no_feature_kw
check "bad step keyword fails"            1 "Whne"                     bad_step_kw
check "scenario with no steps fails"      1 "Nothing happens"          empty_scenario
check "defined steps pass"                0 "ok"                       defined_steps_only
check "undefined step untagged fails"     1 "hum a little tune"        undefined_step_untagged
check "undefined step tagged passes"      0 "ok"                       undefined_step_tagged
check "undefined Background step fails"   1 "hum a little tune"        undefined_background_live
check "Background in all-draft file ok"   0 "ok"                        undefined_background_draft
check "archived status in archived/ ok"   0 "ok"                        archived_status_ok
check "live status in archived/ ok"       0 "ok"                        archived_live_status
check "archived status in features/ fails" 1 "archived"                  live_archived_status
check "scenario with no Then fails"       1 "assert"                     no_assertion
check "Background needs no Then"          0 "ok"                         background_only_given
check "TBD in a passing feature fails"    1 "TBD"                        marker_when_passing
check "TBD in a ready feature is fine"    0 "ok"                         marker_when_ready
check "TBD in a draft feature is fine"    0 "ok"                         marker_when_draft
check "css selector in a step fails"      1 "css="                       css_locator
check "xpath in a step fails"             1 "xpath\|//div"                xpath_locator
check "all-draft claimed feature fails"   1 "draft"                      all_draft_with_steps
check "all-draft ok with no step library" 0 "ok"                         all_draft_no_steps
check "partly-draft claimed is fine"      0 "ok"                         some_draft_with_steps
check "ADR file not in ADR INDEX fails"   1 "use-redis"                adr_orphan_file
check "ADR INDEX row without file fails"  1 "use-kafka"                adr_phantom_row
check "undated ADR filename fails"        1 "thoughts.md"              adr_bad_name
check "well-formed change passes"         0 "ok"                       change_ok
check "change to absent feature fails"    1 "nope.md"                  change_bad_feature
check "change with no tasks fails"        1 "task"                     change_no_tasks
check "archived change passes"            0 "ok"                       change_archived
check "archived open task fails"          1 "1.1"                      change_arch_unticked
check "reports draft scenario count"      0 "2 draft"                  two_drafts
check "missing specs dir fails"           1 "no such"                  no_specs_dir

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
