"""Reading and validating a specs/ folder produced by the spec skill.

One parser, two consumers: validate.sh checks the structural invariants,
view.sh renders the same parse in a browser. A second Gherkin parser would
drift from this one, so there isn't one.
"""
import json
import re
import pathlib
import subprocess
import sys
from pathlib import Path

STATUSES = ("in progress", "deferred", "failing", "passing", "draft", "ready")
# a status may carry a trailing note ("passing — sweeper scenarios still @draft");
# only the leading token is checked and compared.
STATUS_RE = re.compile(r"(" + "|".join(STATUSES) + r")\b")
ARCHIVED_RE = re.compile(r"(archived|" + "|".join(STATUSES) + r")\b")
# Decision records carry their own vocabulary, and often trail the status with
# other fields on the same line ("accepted · **Date**: … · **Affects**: …").
ADR_STATUSES = ("superseded", "deprecated", "accepted", "rejected", "proposed", "open")
ADR_STATUS_RE = re.compile(r"(" + "|".join(ADR_STATUSES) + r")\b", re.I)
STEP_KW = ("Given ", "When ", "Then ", "And ", "But ", "* ")
# Statuses that claim the code exists and the scenarios were run.
RAN = ("passing", "failing")
# Statuses that claim the spec has been signed off.
CLAIMED = ("ready", "passing", "failing")
MARKER_RE = re.compile(r"\b(TBD|TODO|FIXME|NEEDS CLARIFICATION)\b")
# Locator forms the browser vocabulary forbids. Deliberately narrow: source
# paths like `src/app.py` are legitimate subject matter for tools that read
# source trees, so matching those produces nothing but false positives.
LOCATOR_RE = re.compile(r"(css=|xpath=|//\w+\[)")
SCENARIO_RE = re.compile(r"^\s*(Scenario Outline|Scenario|Example)\s*:\s*(.*)$")
STATUS_LINE_RE = re.compile(r"^\*\*Status\*\*:\s*(.+?)\s*$", re.M)
STEP_DECL_RE = re.compile(
    r"""@?(?:given|when|then|step|and|but)\s*\(\s*(?:[\w.]+\(\s*)?[rufb]*(['"])(.+?)\1""",
    re.I | re.S)


def status_token(text, archived=False):
    m = (ARCHIVED_RE if archived else STATUS_RE).match(text.strip())
    return m.group(1) if m else None


def adr_status_token(text):
    m = ADR_STATUS_RE.match((text or "").strip())
    return m.group(1).lower() if m else None


def status_of(md):
    m = STATUS_LINE_RE.search(md.read_text())
    return m.group(1) if m else None


def parse_feature(path):
    """Parse a .feature file into scenarios, steps and structural issues.

    Issues are returned rather than raised — the viewer wants the parse even
    when the file is malformed, and the validator wants to report every problem
    rather than stop at the first.
    """
    lines = path.read_text().splitlines()
    out = {"name": "", "narrative": [], "scenarios": [], "issues": []}
    if not any(re.match(r"^\s*Feature\s*:", l) for l in lines):
        out["issues"].append({"kind": "no_feature_line"})

    tags, cur, docstring, in_examples = [], None, None, False
    for n, line in enumerate(lines, 1):
        s = line.strip()
        if docstring is not None:
            if s.startswith(docstring):
                docstring = None
            elif cur is not None and cur["steps"]:
                cur["steps"][-1]["doc"].append(line)
            continue
        if s.startswith(('"""', "```")):
            docstring = s[:3]
            continue
        if not s or s.startswith("#"):
            continue
        if s.startswith("@"):
            tags += s.split()
            continue
        m = SCENARIO_RE.match(line)
        if m:
            cur = {"keyword": m.group(1), "name": m.group(2).strip() or "(unnamed)",
                   "tags": tags, "draft": "@draft" in tags, "background": False,
                   "steps": [], "examples": [], "line": n}
            out["scenarios"].append(cur)
            tags, in_examples = [], False
            continue
        if re.match(r"^\s*(Feature|Rule)\s*:", line):
            if s.startswith("Feature:"):
                out["name"] = s.split(":", 1)[1].strip()
            cur, tags, in_examples = None, [], False
            continue
        if re.match(r"^\s*(Background|Examples|Scenarios)\s*:", line):
            if s.startswith("Background:"):
                cur = {"keyword": "Background", "name": "Background", "tags": [],
                       "draft": False, "background": True, "steps": [],
                       "examples": [], "line": n}
                out["scenarios"].append(cur)
                in_examples = False
            else:
                in_examples = True
            tags = []
            continue
        if s.startswith("|"):
            row = [c.strip() for c in s.strip("|").split("|")]
            if in_examples and cur is not None:
                cur["examples"].append(row)
            elif cur is not None and cur["steps"]:
                cur["steps"][-1]["table"].append(row)
            continue
        if cur is None:          # Feature narrative ("As a... I want... So that...")
            out["narrative"].append(s)
            continue
        if not s.startswith(STEP_KW):
            out["issues"].append({"kind": "bad_step", "text": s, "line": n})
            continue
        kw, _, text = s.partition(" ")
        cur["steps"].append({"keyword": kw, "text": text.strip(), "line": n,
                             "table": [], "doc": []})

    real = [sc for sc in out["scenarios"] if not sc["background"]]
    if not real:
        out["issues"].append({"kind": "no_scenarios"})
    # a Background cannot carry a @draft tag, so it rides on the file being all-draft
    if real and all(sc["draft"] for sc in real):
        for sc in out["scenarios"]:
            sc["draft"] = True
    for sc in out["scenarios"]:
        if not sc["steps"]:
            out["issues"].append({"kind": "empty_scenario", "name": sc["name"]})
    out["draft_count"] = sum(1 for sc in out["scenarios"]
                             if sc["draft"] and not sc["background"])
    return out


def index_rows(path, link_prefix):
    """Rows of a markdown table whose first cell links to <link_prefix>/<slug>.md.

    Maps slug -> {"status", "description"}; the third cell is optional.
    """
    if not path.exists():
        return {}
    # The description is whatever is left on the line: it may itself contain a
    # pipe (`apply: column | attribute`), so only the status cell is delimited.
    pattern = re.compile(r"^\|\s*\[[^\]]*\]\(" + link_prefix
                         + r"([^)]+)\.md\)\s*\|\s*([^|]*?)\s*\|(.*)$")
    rows = {}
    for line in path.read_text().splitlines():
        m = pattern.match(line)
        if m:
            rows[m.group(1)] = {"status": m.group(2),
                                "description": m.group(3).strip().rstrip("|").strip()}
    return rows


def parse_change(path):
    return parse_change_text(path.read_text(), path.stem, path.parent.name == "archive")


def parse_change_text(body, slug, archived=False):
    tasks = [{"done": mark.lower() == "x", "text": text}
             for mark, text in re.findall(r"^\s*-\s*\[( |x|X)\]\s*(.+?)\s*$", body, re.M)]
    title = next((l[2:].strip() for l in body.splitlines() if l.startswith("# ")), slug)
    return {
        "slug": slug,
        "title": title,
        "archived": archived,
        "status": (STATUS_LINE_RE.search(body).group(1) if STATUS_LINE_RE.search(body) else None),
        "tasks": tasks,
        "features": re.findall(r"\]\((?:\.\./)?features/([^)]+)\.md\)", body),
        "adrs": re.findall(r"\]\((?:\.\./)?ADR/([^)]+)\.md\)", body),
        "body": body,
    }


def step_library(root):
    """Compiled matchers for every step the project defines, or None if it has none."""
    dirs = [d for d in (root / "step_definitions", root.parent / "step_definitions",
                        root / "features" / "step_definitions", root.parent / "tests" / "steps")
            if d.is_dir()]
    if not dirs:
        return None
    patterns = []
    for d in dirs:
        for f in d.rglob("*"):
            if f.is_file() and f.suffix in (".py", ".js", ".ts", ".rb", ".java", ".kt"):
                for _, pat in STEP_DECL_RE.findall(f.read_text(errors="replace")):
                    placeholder = ".*".join(re.escape(x) for x in re.split(r"\{[^}]*\}", pat))
                    patterns.append(re.compile(placeholder + r"\Z"))
                    try:
                        patterns.append(re.compile(pat.lstrip("^").rstrip("$") + r"\Z"))
                    except re.error:
                        pass
    return patterns


def load(root):
    """Read a whole spec set. Never raises on malformed content."""
    root = Path(root)
    spec = {"root": root, "features": {}, "archived": {}, "changes": [], "adrs": {},
            "index": index_rows(root / "INDEX.md", "features/"),
            "adr_index": index_rows(root / "ADR" / "INDEX.md", ""),
            "gaps": (root / "GAPS.md").exists(),
            "steps": step_library(root)}
    for sub in ("features", "archived"):
        d = root / sub
        if not d.is_dir():
            continue
        for md in sorted(d.glob("*.md")):
            ft = md.with_suffix(".feature")
            raw = status_of(md)
            spec[sub][md.stem] = {
                "slug": md.stem,
                "md": md,
                "feature": ft if ft.exists() else None,
                "raw_status": raw,
                "status": status_token(raw, sub == "archived") if raw else None,
                "parsed": parse_feature(ft) if ft.exists() else None,
            }
        for ft in sorted(d.glob("*.feature")):
            if not ft.with_suffix(".md").exists():
                spec[sub].setdefault(ft.stem, {"slug": ft.stem, "md": None, "feature": ft,
                                               "raw_status": None, "status": None,
                                               "parsed": parse_feature(ft)})
    adr = root / "ADR"
    if adr.is_dir():
        for f in sorted(adr.glob("*.md")):
            if f.name != "INDEX.md":
                raw = status_of(f)
                spec["adrs"][f.stem] = {"slug": f.stem, "path": f, "raw_status": raw,
                                        "status": adr_status_token(raw),
                                        "body": f.read_text()}
    changes = root / "changes"
    if changes.is_dir():
        for ch in sorted(list(changes.glob("*.md")) + list((changes / "archive").glob("*.md"))):
            spec["changes"].append(parse_change(ch))
    return spec


def validate(spec):
    """Structural invariants. Returns (errors, notes, summary)."""
    root = spec["root"]
    errors, notes, warnings = [], [], []
    rel = lambda p: str(Path(p).relative_to(root))

    for sub in ("features", "archived"):
        for slug, f in spec[sub].items():
            if f["md"] is None:
                errors.append(f"{rel(f['feature'])} has no matching {slug}.md")
                continue
            if f["feature"] is None:
                errors.append(f"{rel(f['md'])} has no matching {slug}.feature")
            if f["raw_status"] is None:
                errors.append(f"{rel(f['md'])} has no **Status**: line")
            elif status_token(f["raw_status"], sub == "archived") is None:
                errors.append(f"{rel(f['md'])} has unknown status {f['raw_status']!r} "
                              f"(expected one of: {', '.join(sorted(STATUSES))})")

    if not (root / "INDEX.md").exists():
        errors.append("INDEX.md is missing")
    else:
        for slug in spec["features"]:
            if slug not in spec["index"]:
                errors.append(f"features/{slug}.md is not listed in INDEX.md")
        for slug, row in spec["index"].items():
            st = row["status"]
            if slug not in spec["features"]:
                errors.append(f"INDEX.md lists {slug} but features/{slug}.md does not exist")
            elif spec["features"][slug]["status"] and status_token(st) != spec["features"][slug]["status"]:
                errors.append(f"INDEX.md says {slug} is {st!r}, "
                              f"features/{slug}.md says {spec['features'][slug]['status']!r}")

    draft_scenarios = 0
    for slug, f in sorted(spec["features"].items()):
        if not f["parsed"]:
            continue
        name = rel(f["feature"])
        for issue in f["parsed"]["issues"]:
            if issue["kind"] == "no_feature_line":
                errors.append(f"{name} has no Feature: line")
            elif issue["kind"] == "no_scenarios":
                errors.append(f"{name} has no scenarios")
            elif issue["kind"] == "bad_step":
                errors.append(f"{name}: line is not a Gherkin step: {issue['text']!r}")
            elif issue["kind"] == "empty_scenario":
                errors.append(f"{name}: scenario {issue['name']!r} has no steps")
        draft_scenarios += f["parsed"]["draft_count"]

    if spec["steps"] is None:
        notes.append("no step_definitions/ found — step coverage not checked")
    else:
        for slug, f in sorted(spec["features"].items()):
            if not f["parsed"]:
                continue
            for sc in f["parsed"]["scenarios"]:
                if sc["draft"]:
                    continue
                for step in sc["steps"]:
                    if not any(p.match(step["text"]) for p in spec["steps"]):
                        errors.append(f"{rel(f['feature'])}: scenario {sc['name']!r} uses an "
                                      f"undefined step and is not @draft: {step['text']!r}")

    # --- quality: the rules the skill states but could not previously enforce
    for slug, f in sorted(spec["features"].items()):
        p = f["parsed"]
        if not p:
            continue
        name = rel(f["feature"])
        real = [sc for sc in p["scenarios"] if not sc["background"]]

        for sc in p["scenarios"]:
            # A Background is setup; only a scenario has to conclude something.
            if not sc["background"] and not any(st["keyword"] == "Then" for st in sc["steps"]):
                errors.append(f"{name}: scenario {sc['name']!r} asserts nothing — it has no Then step")
            for st in sc["steps"]:
                if LOCATOR_RE.search(st["text"]):
                    errors.append(f"{name}: scenario {sc['name']!r} locates by selector rather than "
                                  f"visible text: {st['text']!r}")

        # @draft means the phrasing is still unreviewed. A feature can only be
        # entirely @draft and still claim sign-off when the project has no step
        # library at all, where the tag means "nothing runs this" instead.
        if spec["steps"] is not None and f["status"] in CLAIMED and real \
                and all(sc["draft"] for sc in real):
            errors.append(f"features/{slug}.md is {f['status']} but every scenario is still @draft")

    for slug, f in sorted(spec["features"].items()):
        if f["status"] not in RAN:
            continue
        for path in (f["md"], f["feature"]):
            m = MARKER_RE.search(path.read_text()) if path else None
            if m:
                errors.append(f"{rel(path)} is {f['status']} but still carries {m.group(1)} — "
                              f"a feature whose scenarios have run cannot have unresolved notes")

    adr = root / "ADR"
    if adr.is_dir():
        on_disk = set(spec["adrs"])
        for slug in sorted(on_disk):
            if not re.match(r"^\d{4}-\d{2}-\d{2}-.+", slug):
                errors.append(f"ADR/{slug}.md is not named <YYYY-MM-DD>-<slug>.md")
        if not (adr / "INDEX.md").exists():
            errors.append("ADR/INDEX.md is missing")
        else:
            listed = set(spec["adr_index"])
            for slug in sorted(on_disk - listed):
                errors.append(f"ADR/{slug}.md is not listed in ADR/INDEX.md")
            for slug in sorted(listed - on_disk):
                errors.append(f"ADR/INDEX.md lists {slug} but ADR/{slug}.md does not exist")

    for ch in spec["changes"]:
        where = f"changes/archive/{ch['slug']}.md" if ch["archived"] else f"changes/{ch['slug']}.md"
        if not ch["tasks"]:
            errors.append(f"{where} has no task checklist")
        for task in ch["tasks"]:
            if ch["archived"] and not task["done"]:
                errors.append(f"{where} is archived but task {task['text']!r} is still open")
        for target in ch["features"]:
            if target not in spec["features"]:
                errors.append(f"{where} references features/{target}.md, which does not exist")

    claims = {}
    for c in inflight(root, spec):
        for target in c["features"]:
            claims.setdefault(target, []).append(f"changes/{c['slug']}.md on {c['branch']}")
    for target, holders in sorted(claims.items()):
        if len(holders) > 1:
            warnings.append(f"{len(holders)} changes in flight claim features/{target}.md: "
                            + ", ".join(sorted(holders)))

    by_status = {}
    for f in spec["features"].values():
        key = f["status"] or "no status"
        by_status[key] = by_status.get(key, 0) + 1
    summary = (f"{len(spec['features'])} features ("
               + ", ".join(f"{n} {s}" for s, n in sorted(by_status.items())) + ")"
               + f", {draft_scenarios} draft scenarios")
    if (root / "changes").is_dir():
        open_n = sum(1 for c in spec["changes"] if not c["archived"])
        summary += f", {open_n} open changes, {len(spec['changes']) - open_n} archived"
    return errors, notes, summary, warnings


def git(root, *args):
    """Run git in the spec set's repo. Returns '' when git isn't usable here."""
    try:
        r = subprocess.run(("git", "-C", str(root), *args),
                           capture_output=True, text=True, timeout=15)
        return r.stdout if r.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def branches(root):
    """Local branches that are not already merged into HEAD.

    A merged branch is finished work, not work in flight; without this filter
    every feature branch ever cut stays on the board forever.
    """
    out = git(root, "for-each-ref", "--format=%(refname:short)", "refs/heads/")
    live = []
    for name in out.split():
        if git(root, "rev-parse", "--abbrev-ref", "HEAD").strip() == name:
            continue
        merged = subprocess.run(("git", "-C", str(root), "merge-base",
                                 "--is-ancestor", name, "HEAD"),
                                capture_output=True)
        if merged.returncode != 0:
            live.append(name)
    return live


def inflight(root, spec):
    """Open changes across every branch, not only the one checked out.

    A change lives on its branch, so two in flight cannot see each other. Git
    can see both, and this is the only place that asks it.
    """
    here = git(root, "rev-parse", "--abbrev-ref", "HEAD").strip()
    found = [{**change_row_lite(c), "branch": here or "(no branch)", "current": True}
             for c in spec["changes"] if not c["archived"]]
    for branch in branches(root):
        listing = git(root, "ls-tree", "-r", "--name-only", branch, "--", "changes/")
        for path in listing.split():
            if not path.endswith(".md") or "/archive/" in path:
                continue
            # `<rev>:<path>` resolves from the repo root; `./` makes it resolve
            # from the specs directory, which is where ls-tree reported it.
            body = git(root, "show", f"{branch}:./{path}")
            if not body:
                continue
            found.append({**change_row_lite(parse_change_text(body, pathlib.PurePath(path).stem)),
                          "branch": branch, "current": False})
    return found


def change_row_lite(c):
    return {"slug": c["slug"], "title": c["title"], "features": c["features"],
            "done": sum(1 for t in c["tasks"] if t["done"]), "total": len(c["tasks"])}


def history(root, paths):
    """Commits touching any of `paths` (relative to root), newest first."""
    sep = "\x1f"
    follow = ["--follow"] if len(paths) == 1 else []
    out = git(root, "log", *follow, f"--format=%H{sep}%h{sep}%an{sep}%aI{sep}%s",
              "--", *paths)
    commits = []
    for line in out.splitlines():
        if line.count(sep) == 4:
            sha, short, author, date, subject = line.split(sep)
            commits.append({"sha": sha, "short": short, "author": author,
                            "date": date, "subject": subject})
    return commits


def main(argv):
    if len(argv) > 1 and argv[1] == "validate":
        root = Path(argv[2] if len(argv) > 2 else "specs")
        if not root.is_dir():
            print(f"FAIL: no such directory: {root}")
            return 1
        errors, notes, summary, warnings = validate(load(root))
        for e in errors:
            print(f"FAIL: {e}")
        for w in warnings:
            print(f"warn: {w}")
        for n in notes:
            print(f"note: {n}")
        print(("FAIL: " if errors else "ok: ") + summary)
        return 1 if errors else 0
    print("usage: specset.py validate [specs-dir]", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
