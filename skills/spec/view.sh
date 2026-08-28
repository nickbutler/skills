#!/usr/bin/env bash
# Browse a specs/ folder: features, scenarios, changes, decisions, git history.
# Read-only — it never writes to the spec set.
# Usage: view.sh [specs-dir] [--port N] [--no-open]
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$here/references/viewer.py" "$@"
