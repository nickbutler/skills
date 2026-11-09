#!/usr/bin/env bash
# Tests for `make spec.zip` — builds in a throwaway copy of the repo, then
# asserts on what the archive holds.
# Usage: zip.test.sh
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
pass=0; fail=0
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

has()  { if grep -qxF "$2" <<<"$listing"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }
hasnt(){ if grep -qE "$2" <<<"$listing"; then fail=$((fail+1)); echo "FAIL: $1"; else pass=$((pass+1)); fi; }

# --- fixture: a repo copy with junk to exclude and a previous build ----------
repo="$tmp/repo"
mkdir -p "$repo/skills"
cp "$root/Makefile" "$repo/"
cp -R "$here" "$repo/skills/spec"
mkdir -p "$repo/skills/spec/references/__pycache__"
touch "$repo/skills/spec/references/__pycache__/specset.pyc" "$repo/skills/spec/.DS_Store"
(cd "$repo" && touch stale.txt && zip -q spec.zip stale.txt && rm stale.txt)

make -C "$repo" spec.zip >/dev/null || { echo "FAIL: make spec.zip exited non-zero"; exit 1; }
listing="$(unzip -Z1 "$repo/spec.zip")"

# --- contents ----------------------------------------------------------------
has "SKILL.md sits under one top-level folder" "spec/SKILL.md"
has "ships the validator"                      "spec/validate.sh"
has "ships the viewer"                         "spec/view.sh"
has "ships the references"                     "spec/references/mode-create.md"

# --- exclusions --------------------------------------------------------------
hasnt "no bytecode"              '__pycache__|\.pyc$'
hasnt "no test scripts"          '\.test\.sh$'
hasnt "no Finder metadata"       '\.DS_Store$'
hasnt "previous build is gone"   'stale\.txt'

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
