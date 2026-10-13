#!/usr/bin/env python3
"""Compare the versions the labs pin (tools/versions.json) with the latest upstream
releases, and the curriculum each track follows with the newest one CNCF publishes
(github.com/cncf/curriculum). Prints a table; exits 1 with --strict when anything
is behind. Set GITHUB_TOKEN to avoid the API's low anonymous rate limit."""
import json, os, re, sys, urllib.request

here = os.path.dirname(os.path.abspath(__file__))
cfg = json.load(open(os.path.join(here, "versions.json")))


def get(url, raw=False):
    req = urllib.request.Request(url, headers={"User-Agent": "cka-lab-version-check", "Accept": "application/vnd.github+json"})
    if "api.github.com" in url and os.environ.get("GITHUB_TOKEN"):
        req.add_header("Authorization", f"Bearer {os.environ['GITHUB_TOKEN']}")
    with urllib.request.urlopen(req, timeout=20) as r:
        body = r.read().decode()
    return body if raw else json.loads(body)


def vtuple(v):
    return tuple(int(x) for x in re.findall(r"\d+", v)[:3])


def stable(tags, major=None):
    out = [t for t in tags if re.fullmatch(r"v?\d+\.\d+\.\d+", t)]
    if major is not None:
        out = [t for t in out if vtuple(t)[0] == major]
    return max(out, key=vtuple).lstrip("v") if out else None


def latest(c):
    kind, _, arg = c["source"].partition(":")
    if kind == "k8s-minor":
        return get(f"https://dl.k8s.io/release/stable-{arg}.txt", raw=True).strip().lstrip("v")
    if kind == "k8s-stable":
        return get("https://dl.k8s.io/release/stable.txt", raw=True).strip().lstrip("v")
    if kind == "github":
        rel = get(f"https://api.github.com/repos/{arg}/releases?per_page=100")
        return stable([r["tag_name"] for r in rel if not r.get("prerelease") and not r.get("draft")], c.get("major"))
    if kind == "github-tag":
        repo, prefix = arg.split(":", 1)
        rel = get(f"https://api.github.com/repos/{repo}/releases?per_page=100")
        return stable([r["tag_name"][len(prefix):] for r in rel if r["tag_name"].startswith(prefix) and not r.get("prerelease")])
    raise ValueError(kind)


behind = 0
rows = []
for c in cfg["components"]:
    try:
        new = latest(c)
    except Exception as e:  # network or API trouble: report it, don't stop
        rows.append((c["name"], c["pinned"], "?", f"lookup failed: {e}"))
        continue
    n = 2 if c.get("compare") == "minor" else 3
    p, l = vtuple(c["pinned"])[:n], vtuple(new or "0")[:n]
    if new is None:
        state = "no release found"
    elif l > p:
        state = "NEWER MINOR" if l[:2] > p[:2] else "newer patch"
        behind += 1
    else:
        state = "current"
    rows.append((c["name"], c["pinned"], new or "?", state))

try:
    files = [f["name"] for f in get("https://api.github.com/repos/cncf/curriculum/contents/")]
except Exception as e:
    files = []
    rows.append(("CNCF curricula", "", "?", f"lookup failed: {e}"))
for track, pinned in cfg["curricula"].items():
    found = sorted((m.group(1) for f in files if (m := re.match(rf"{track}[_ ]Curriculum[_ ]?v?(\d+\.\d+)", f))), key=vtuple)
    if not found:
        if any(re.match(rf"{track}[_ ]Curriculum\.pdf$", f) for f in files):
            rows.append((f"{track} curriculum", pinned or "-", "unversioned", "not started" if pinned is None else "check the PDF for changes"))
        elif files:
            rows.append((f"{track} curriculum", pinned or "-", "?", "not found in cncf/curriculum"))
        continue
    state = "not started" if pinned is None else ("NEWER CURRICULUM" if vtuple(found[-1]) > vtuple(pinned) else "current")
    if pinned and state != "current":
        behind += 1
    rows.append((f"{track} curriculum", pinned or "-", found[-1], state))

w = [max(len(str(r[i])) for r in rows + [("COMPONENT", "PINNED", "LATEST", "STATE")]) for i in range(4)]
for r in [("COMPONENT", "PINNED", "LATEST", "STATE")] + rows:
    print("  ".join(str(x).ljust(w[i]) for i, x in enumerate(r)))
print(f"\n{behind} behind upstream")
sys.exit(1 if behind and "--strict" in sys.argv else 0)
