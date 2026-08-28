#!/usr/bin/env bash
# Structural validation for a specs/ folder produced by the spec skill.
# Deterministic checks only — no model in the loop.
# Usage: validate.sh [specs-dir]   (default: ./specs)
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$here/references/specset.py" validate "${1:-specs}"
