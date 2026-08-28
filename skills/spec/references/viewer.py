"""Read-only HTTP viewer for a specs/ folder.

Serves the parse from specset.py as JSON and a small single-page app over it.
No write endpoints: the server holds no state and never touches the spec set,
so it is safe to leave running while you edit or switch branches.
"""
import json
import re
import sys
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote

sys.path.insert(0, str(Path(__file__).parent))
import specset

ASSETS = Path(__file__).parent / "viewer"
SAFE_SLUG = re.compile(r"^[A-Za-z0-9._-]+$")
SAFE_REF = re.compile(r"^[A-Za-z0-9._~^/-]+$")
MIME = {".html": "text/html", ".css": "text/css", ".js": "application/javascript"}


def safe(slug, pattern=SAFE_SLUG):
    slug = unquote(slug)
    return slug if pattern.match(slug) and ".." not in slug else None


def feature_row(f, index_row):
    parsed = f["parsed"] or {"scenarios": [], "draft_count": 0, "name": ""}
    real = [s for s in parsed["scenarios"] if not s["background"]]
    return {
        "slug": f["slug"],
        "title": parsed["name"] or f["slug"],
        "status": f["status"],
        "raw_status": f["raw_status"],
        "description": (index_row or {}).get("description", ""),
        "scenarios": len(real),
        "draft": parsed["draft_count"],
        "steps": sum(len(s["steps"]) for s in parsed["scenarios"]),
        "orphan": f["md"] is None or f["feature"] is None,
    }


def change_row(c):
    return {
        "slug": c["slug"], "title": c["title"], "archived": c["archived"],
        "status": c["status"], "features": c["features"], "adrs": c["adrs"],
        "done": sum(1 for t in c["tasks"] if t["done"]), "total": len(c["tasks"]),
    }


class Handler(BaseHTTPRequestHandler):
    root = None
    protocol_version = "HTTP/1.1"

    def log_message(self, *_):
        pass

    # --- plumbing ----------------------------------------------------------
    def send(self, body, ctype="application/json", code=200):
        raw = body if isinstance(body, bytes) else body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(raw)

    def json(self, obj, code=200):
        self.send(json.dumps(obj, default=str), code=code)

    def missing(self, what="not found"):
        self.json({"error": what}, code=404)

    def do_GET(self):
        path = self.path.split("?")[0]
        parts = [p for p in path.split("/") if p]
        try:
            if not parts:
                return self.asset("app.html")
            if len(parts) == 1 and parts[0] in ("app.css", "app.js"):
                return self.asset(parts[0])
            if parts[0] == "api":
                return self.api(parts[1:])
        except Exception as exc:                      # a broken spec set must not 500 the app
            return self.json({"error": str(exc)}, code=500)
        self.missing()

    def asset(self, name):
        f = ASSETS / name
        if not f.exists():
            return self.missing()
        self.send(f.read_bytes(), MIME.get(f.suffix, "text/plain"))

    # --- api ---------------------------------------------------------------
    def api(self, parts):
        if not parts:
            return self.missing()
        route, rest = parts[0], parts[1:]
        spec = specset.load(self.root)

        if route == "spec" and not rest:
            errors, notes, summary = specset.validate(spec)
            progress = {}
            for f in spec["features"].values():
                key = f["status"] or "no status"
                progress[key] = progress.get(key, 0) + 1
            return self.json({
                "name": self.root.parent.name,
                "root": str(self.root),
                "features": [feature_row(f, spec["index"].get(slug))
                             for slug, f in sorted(spec["features"].items())],
                "archived": [feature_row(f, None) for _, f in sorted(spec["archived"].items())],
                "changes": [change_row(c) for c in spec["changes"]],
                "adrs": [{"slug": a["slug"], "status": a["status"],
                          "raw_status": a["raw_status"],
                          "description": spec["adr_index"].get(a["slug"], {}).get("description", "")}
                         for a in spec["adrs"].values()],
                "gaps": spec["gaps"],
                "progress": progress,
                "validation": {"ok": not errors, "errors": errors, "notes": notes,
                               "summary": summary},
            })

        if route == "validate" and not rest:
            errors, notes, summary = specset.validate(spec)
            return self.json({"ok": not errors, "errors": errors, "notes": notes,
                              "summary": summary})

        if route == "feature" and len(rest) == 1:
            slug = safe(rest[0])
            f = spec["features"].get(slug) or spec["archived"].get(slug) if slug else None
            if not f:
                return self.missing(f"no feature {rest[0]!r}")
            return self.json({
                "slug": f["slug"],
                "status": f["status"],
                "raw_status": f["raw_status"],
                "markdown": f["md"].read_text() if f["md"] else "",
                "parsed": f["parsed"],
                "gherkin": f["feature"].read_text() if f["feature"] else "",
                "changes": [change_row(c) for c in spec["changes"] if slug in c["features"]],
            })

        if route == "history" and len(rest) == 1:
            slug = safe(rest[0])
            f = (spec["features"].get(slug) or spec["archived"].get(slug)) if slug else None
            if not f:
                return self.missing()
            paths = [str(p.relative_to(self.root)) for p in (f["md"], f["feature"]) if p]
            return self.json({"slug": slug, "commits": specset.history(self.root, paths)})

        if route == "diff" and len(rest) == 2:
            ref, slug = safe(rest[0], SAFE_REF), safe(rest[1])
            f = (spec["features"].get(slug) or spec["archived"].get(slug)) if slug else None
            if not f or not ref or not specset.git(self.root, "rev-parse", "--verify", f"{ref}^{{commit}}"):
                return self.missing()
            paths = [str(p.relative_to(self.root)) for p in (f["md"], f["feature"]) if p]
            return self.json({"ref": ref, "slug": slug,
                              "diff": specset.git(self.root, "show", "--format=%s%n%n%an, %aI%n",
                                                  ref, "--", *paths)})

        if route == "change" and len(rest) == 1:
            slug = safe(rest[0])
            c = next((c for c in spec["changes"] if c["slug"] == slug), None)
            if not c:
                return self.missing()
            return self.json({**change_row(c), "tasks": c["tasks"], "body": c["body"]})

        if route == "adr" and len(rest) == 1:
            slug = safe(rest[0])
            a = spec["adrs"].get(slug) if slug else None
            if not a:
                return self.missing()
            return self.json({"slug": a["slug"], "status": a["status"],
                              "raw_status": a["raw_status"], "body": a["body"]})

        if route == "gaps" and not rest:
            gaps = self.root / "GAPS.md"
            return self.json({"body": gaps.read_text() if gaps.exists() else ""})

        if route == "doc" and len(rest) == 1:
            name = {"architecture": "ARCHITECTURE.md", "data-model": "DATA_MODEL.md",
                    "index": "INDEX.md", "sync-report": "SYNC_REPORT.md"}.get(rest[0])
            f = self.root / name if name else None
            if not f or not f.exists():
                return self.missing()
            return self.json({"name": name, "body": f.read_text()})

        return self.missing()


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    flags = [a for a in argv[1:] if a.startswith("--")]
    root = Path(args[0] if args else "specs").resolve()
    port = 0
    for f in flags:
        if f.startswith("--port"):
            port = int(f.split("=")[1]) if "=" in f else int(argv[argv.index(f) + 1])
    if not root.is_dir():
        print(f"no such directory: {root}", file=sys.stderr)
        return 1

    Handler.root = root
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    url = f"http://127.0.0.1:{server.server_port}/"
    print(f"spec viewer for {root} → {url}   (ctrl-c to stop)")
    if "--no-open" not in flags:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
