#!/usr/bin/env bash
# Structural validation for a specs/ folder produced by the spec skill.
# Deterministic checks only — no model in the loop.
# Usage: validate.sh [specs-dir]   (default: ./specs)
set -uo pipefail
exec python3 - "${1:-specs}" <<'PY'
import re, sys, pathlib

root = pathlib.Path(sys.argv[1])
errors, warnings, notes = [], [], []
E, W, N = errors.append, warnings.append, notes.append

if not root.is_dir():
    print(f"FAIL: no such directory: {root}")
    sys.exit(1)

STATUSES = ("in progress", "deferred", "failing", "passing", "draft", "ready")
# a status may carry a trailing note ("passing — sweeper scenarios still @draft");
# only the leading token is checked and compared.
STATUS_RE = re.compile(r"(" + "|".join(STATUSES) + r")\b")
ARCHIVED_RE = re.compile(r"(archived|" + "|".join(STATUSES) + r")\b")
STEP_KW = ("Given ", "When ", "Then ", "And ", "But ", "* ")
rel = lambda p: str(p.relative_to(root))

def status_token(text, archived=False):
    m = (ARCHIVED_RE if archived else STATUS_RE).match(text.strip())
    return m.group(1) if m else None

def status_of(md):
    m = re.search(r"^\*\*Status\*\*:\s*(.+?)\s*$", md.read_text(), re.M)
    return m.group(1) if m else None

# --- features and archived: .md / .feature pairing, status lines ------------
features = {}
for sub in ("features", "archived"):
    d = root / sub
    if not d.is_dir():
        continue
    for md in sorted(d.glob("*.md")):
        ft = md.with_suffix(".feature")
        if not ft.exists():
            E(f"{rel(md)} has no matching {ft.name}")
        st = status_of(md)
        if st is None:
            E(f"{rel(md)} has no **Status**: line")
        elif status_token(st, sub == "archived") is None:
            E(f"{rel(md)} has unknown status {st!r} (expected one of: {', '.join(sorted(STATUSES))})")
        if sub == "features":
            features[md.stem] = status_token(st) if st else None
    for ft in sorted(d.glob("*.feature")):
        if not ft.with_suffix(".md").exists():
            E(f"{rel(ft)} has no matching {ft.stem}.md")

# --- INDEX.md agrees with features/ ----------------------------------------
index = root / "INDEX.md"
if not index.exists():
    E("INDEX.md is missing")
else:
    listed = {}
    for line in index.read_text().splitlines():
        m = re.match(r"^\|\s*\[[^\]]*\]\(features/([^)]+)\.md\)\s*\|\s*([^|]*?)\s*\|", line)
        if m:
            listed[m.group(1)] = m.group(2)
    for slug in features:
        if slug not in listed:
            E(f"features/{slug}.md is not listed in INDEX.md")
    for slug, st in listed.items():
        if slug not in features:
            E(f"INDEX.md lists {slug} but features/{slug}.md does not exist")
        elif features[slug] and status_token(st) != features[slug]:
            E(f"INDEX.md says {slug} is {st!r}, features/{slug}.md says {features[slug]!r}")

# --- Gherkin structure ------------------------------------------------------
SCENARIO = re.compile(r"^\s*(Scenario|Scenario Outline|Example)\s*:\s*(.*)$")
draft_scenarios, used_steps = 0, []          # used_steps: (file, scenario, text, is_draft)

for ft in sorted((root / "features").glob("*.feature")) if (root / "features").is_dir() else []:
    lines = ft.read_text().splitlines()
    if not any(re.match(r"^\s*Feature\s*:", l) for l in lines):
        E(f"{rel(ft)} has no Feature: line")
    scenarios, tags, cur, docstring = [], [], None, None
    for line in lines:
        s = line.strip()
        if docstring is not None:
            if s.startswith(docstring):
                docstring = None
            continue
        if s.startswith(('"""', "```")):
            docstring = s[:3]
            continue
        if not s or s.startswith("#"):
            continue
        if s.startswith("@"):
            tags += s.split()
            continue
        m = SCENARIO.match(line)
        if m:
            cur = {"name": m.group(2).strip() or "(unnamed)", "draft": "@draft" in tags, "steps": []}
            scenarios.append(cur)
            tags = []
            continue
        if re.match(r"^\s*(Feature|Rule)\s*:", line):
            cur, tags = None, []
            continue
        if re.match(r"^\s*(Background|Examples)\s*:", line):
            if s.startswith("Background:"):
                cur = {"name": "Background", "draft": False, "steps": [], "background": True}
                scenarios.append(cur)
            tags = []
            continue
        if s.startswith("|"):
            continue
        if cur is None:          # Feature narrative ("As a... I want... So that...")
            continue
        if not s.startswith(STEP_KW):
            E(f"{rel(ft)}: line is not a Gherkin step: {s!r}")
            continue
        if cur is not None:
            kw, _, text = s.partition(" ")
            cur["steps"].append(text.strip())
    if not [sc for sc in scenarios if not sc.get("background")]:
        E(f"{rel(ft)} has no scenarios")
    # a Background cannot carry a @draft tag, so it rides on the file being all-draft
    real = [sc for sc in scenarios if not sc.get("background")]
    if real and all(sc["draft"] for sc in real):
        for sc in scenarios:
            sc["draft"] = True
    for sc in scenarios:
        if not sc["steps"]:
            E(f"{rel(ft)}: scenario {sc['name']!r} has no steps")
        if sc["draft"] and not sc.get("background"):
            draft_scenarios += 1
        for text in sc["steps"]:
            used_steps.append((rel(ft), sc["name"], text, sc["draft"]))

# --- steps exist in the step library (skipped when there isn't one) ---------
step_dirs = [d for d in (root / "step_definitions", root.parent / "step_definitions",
                         root / "features" / "step_definitions", root.parent / "tests" / "steps")
             if d.is_dir()]
if not step_dirs:
    N("no step_definitions/ found — step coverage not checked")
else:
    DECL = re.compile(r"""@?(?:given|when|then|step|and|but)\s*\(\s*(?:[\w.]+\(\s*)?[rufb]*(['"])(.+?)\1""",
                      re.I | re.S)
    patterns = []
    for d in step_dirs:
        for f in d.rglob("*"):
            if f.is_file() and f.suffix in (".py", ".js", ".ts", ".rb", ".java", ".kt"):
                for _, pat in DECL.findall(f.read_text(errors="replace")):
                    placeholder = ".*".join(re.escape(x) for x in re.split(r"\{[^}]*\}", pat))
                    patterns.append(re.compile(placeholder + r"\Z"))
                    try:
                        patterns.append(re.compile(pat.lstrip("^").rstrip("$") + r"\Z"))
                    except re.error:
                        pass
    for file, scenario, text, is_draft in used_steps:
        if is_draft or any(p.match(text) for p in patterns):
            continue
        E(f"{file}: scenario {scenario!r} uses an undefined step and is not @draft: {text!r}")

# --- ADR records ------------------------------------------------------------
adr = root / "ADR"
if adr.is_dir():
    adr_index = adr / "INDEX.md"
    on_disk = {f.stem for f in adr.glob("*.md") if f.name != "INDEX.md"}
    for slug in sorted(on_disk):
        if not re.match(r"^\d{4}-\d{2}-\d{2}-.+", slug):
            E(f"ADR/{slug}.md is not named <YYYY-MM-DD>-<slug>.md")
    if not adr_index.exists():
        E("ADR/INDEX.md is missing")
    else:
        listed = set(re.findall(r"^\|\s*\[[^\]]*\]\(([^)]+)\.md\)", adr_index.read_text(), re.M))
        for slug in sorted(on_disk - listed):
            E(f"ADR/{slug}.md is not listed in ADR/INDEX.md")
        for slug in sorted(listed - on_disk):
            E(f"ADR/INDEX.md lists {slug} but ADR/{slug}.md does not exist")

# --- changes ----------------------------------------------------------------
changes = root / "changes"
open_changes = archived_changes = 0
if changes.is_dir():
    for ch in sorted(list(changes.glob("*.md")) + list((changes / "archive").glob("*.md"))):
        archived = ch.parent.name == "archive"
        archived_changes += archived
        open_changes += not archived
        body = ch.read_text()
        tasks = re.findall(r"^\s*-\s*\[( |x|X)\]\s*(.+?)\s*$", body, re.M)
        if not tasks:
            E(f"{rel(ch)} has no task checklist")
        for mark, task in tasks:
            if archived and mark == " ":
                E(f"{rel(ch)} is archived but task {task!r} is still open")
        for target in re.findall(r"\]\((?:\.\./)?features/([^)]+)\.md\)", body):
            if target not in features:
                E(f"{rel(ch)} references features/{target}.md, which does not exist")

# --- report -----------------------------------------------------------------
for e in errors:
    print(f"FAIL: {e}")
for w in warnings:
    print(f"warn: {w}")
for n in notes:
    print(f"note: {n}")
by_status = {}
for st in features.values():
    by_status[st or "no status"] = by_status.get(st or "no status", 0) + 1
summary = (f"{len(features)} features ("
           + ", ".join(f"{n} {s}" for s, n in sorted(by_status.items())) + ")"
           + f", {draft_scenarios} draft scenarios")
if changes.is_dir():
    summary += f", {open_changes} open changes, {archived_changes} archived"
print(("FAIL: " if errors else "ok: ") + summary)
sys.exit(1 if errors else 0)
PY
