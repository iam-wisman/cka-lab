#!/usr/bin/env python3
"""lab-web: HelmYard (Kubernetes Playgrounds), the browser console for the lab.

Runs on the jump host as `student` (systemd unit lab-web.service) and serves:

  - the labs and mock exams, rendered from the same task.md files `lab show` prints
  - terminals: real login shells on the jump host, in the browser (xterm.js).
    Sessions live in this process, so a page reload reattaches instead of
    killing your shell.
  - jobs: the existing `lab` commands (start, check, cleanup, exam, snapshot,
    reset), run one at a time with their output streamed to the page
  - cluster status: VM power state from Proxmox, node status from Kubernetes
  - what you're working on (a lab, drill, exam or the playground) and how far its
    setup is, kept on disk, so it shows wherever you look and survives a reload
  - power: the cluster VMs are started by the lab commands that need them, and
    everything (cluster, then this jump host) shuts down after IDLE minutes without
    use. The gate on Proxmox (infra/gate) starts it all again.

Everything the web console does, the `lab` CLI can do too; this file adds no
grading or setup logic of its own.

Configuration comes from the environment (/etc/cka-lab/web.env):
  WEB_PASSWORD_HASH  pbkdf2_sha256$<iterations>$<salt hex>$<hash hex>
  WEB_PORT           default 443
  WEB_CERT, WEB_KEY  TLS certificate and key (omit both for plain HTTP, e.g. local dev)
"""

import asyncio
import datetime
import base64
import fcntl
import hashlib
import hmac
import json
import os
import pty
import re
import secrets
import shlex
import signal
import ssl
import struct
import termios
import time
import urllib.request
from pathlib import Path

from aiohttp import WSMsgType, web

LAB_HOME = Path(os.environ.get("LAB_HOME", "/opt/cka-lab"))
LAB_STATE = Path(os.environ.get("LAB_STATE", Path.home() / ".cka-lab"))
LAB_SOLUTIONS = Path(os.environ.get("LAB_SOLUTIONS", "/opt/cka-lab-solutions"))
LAB_BIN = os.environ.get("LAB_BIN", "/usr/local/bin/lab")
STATIC = Path(__file__).resolve().parent / "static"
WEB_STATE = LAB_STATE / "web"
JUMP_SNAPS = Path("/var/lib/cka-lab/snapshots")   # the jump host's lab state per snapshot (lab bin)
PVE_ENV = Path("/etc/cka-lab/pve.env")
LAB_ENV = Path("/etc/cka-lab/lab.env")

EXAM_MINUTES = 120
EXAM_PASS = 66
SESSION_TTL = 12 * 3600
TERM_BUFFER = 256 * 1024          # scrollback replayed when a browser reattaches
MAX_TERMS = 8

ID_RE = re.compile(r"^[0-9]{2}-[a-z0-9-]+$")
SNAP_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_-]{1,39}$")
KEY_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")


# --- lab content ------------------------------------------------------------------

def read_meta(path: Path) -> dict:
    """meta files are bash assignments: KEY="value" (one per line)."""
    meta = {}
    try:
        for line in path.read_text().splitlines():
            m = re.match(r'^([A-Z_]+)=(.*)$', line.strip())
            if m:
                v = m.group(2).strip()
                if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
                    v = v[1:-1]
                meta[m.group(1)] = v
    except FileNotFoundError:
        pass
    return meta


def read_json(path: Path):
    try:
        return json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def read_jsonl(path: Path) -> list:
    out = []
    try:
        for line in path.read_text().splitlines():
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    except FileNotFoundError:
        pass
    return out


def lab_dirs() -> list:
    return sorted(d for d in (LAB_HOME / "labs").iterdir() if d.is_dir() and ID_RE.match(d.name))


def find_lab(lab_id: str) -> Path:
    for d in lab_dirs():
        if d.name == lab_id or d.name.split("-", 1)[0] == lab_id:
            return d
    raise web.HTTPNotFound(text="no such lab")


def lab_params(grade_id: str) -> dict:
    """This attempt's randomised values (lab bin draw_params), or {} before the lab is started."""
    out = {}
    try:
        for line in (LAB_STATE / "params" / f"{grade_id}.env").read_text().splitlines():
            k, sep, v = line.partition("=")
            if sep and re.fullmatch(r"[A-Z_][A-Z0-9_]*", k):
                out[k] = (shlex.split(v) or [""])[0]
    except (FileNotFoundError, ValueError):
        pass
    return out


def render_params(md: str, values: dict, has_spec: bool) -> str:
    """{{KEY}} -> the value; before the lab is started, a visible placeholder."""
    def sub(m):
        k = m.group(1)
        return values[k] if k in values else (f"‹{k.lower()}›" if has_spec else m.group(0))
    return re.sub(r"\{\{([A-Z_][A-Z0-9_]*)\}\}", sub, md)


def lab_summary(d: Path, history: list) -> dict:
    meta = read_meta(d / "meta")
    started = d.name
    started_file = LAB_STATE / "started" / started
    attempts = [h for h in history if h.get("id") == d.name]
    return {
        "id": d.name,
        "num": d.name.split("-", 1)[0],
        "title": meta.get("TITLE", d.name),
        "domain": meta.get("DOMAIN", ""),
        "curriculum": [c.strip() for c in meta.get("CURRICULUM", "").split(";") if c.strip()],
        "needs": [n for n in meta.get("NEEDS", "").split() if n],
        "minutes": int(meta["TIME"]) if meta.get("TIME", "").isdigit() else None,
        "phases": [p for p in meta.get("PHASES", "").split() if p],
        "has_setup": (d / "setup.sh").exists(),
        "has_cleanup": (d / "cleanup.sh").exists(),
        "has_solution": (LAB_SOLUTIONS / "labs" / d.name / "solution.md").exists(),
        "started_at": started_file.read_text().strip() if started_file.exists() else None,
        "provisioned": (LAB_STATE / "provisioned" / d.name).exists(),
        "result": read_json(LAB_STATE / "results" / f"{d.name}.json"),
        "best": max((a["pass"] / a["total"] for a in attempts if a.get("total")), default=None),
        "attempts": len(attempts),
    }


def exam_dirs() -> list:
    base = LAB_HOME / "exams"
    return sorted((d for d in base.iterdir() if d.is_dir() and d.name.isdigit()), key=lambda d: int(d.name)) if base.exists() else []


def find_exam(n: str) -> Path:
    d = LAB_HOME / "exams" / n
    if not n.isdigit() or not d.is_dir():
        raise web.HTTPNotFound(text="no such exam")
    return d


def exam_state(n: str) -> dict:
    st = LAB_STATE / f"exam-{n}"
    deadline = None
    try:
        deadline = int((st / "deadline").read_text().strip())
    except (FileNotFoundError, ValueError):
        pass
    web_state = read_json(WEB_STATE / f"exam-{n}.json") or {}
    # A web-state file from an earlier sitting doesn't apply to a new deadline.
    if web_state.get("deadline") != deadline:
        web_state = {}
    return {
        "deadline": deadline,
        "submitted_at": web_state.get("submitted_at"),
        "result": read_json(LAB_STATE / "results" / f"exam{n}.json") if deadline else None,
        "history": [h for h in read_jsonl(LAB_STATE / "exam-history.jsonl") if str(h.get("exam")) == n],
    }


def exam_summary(d: Path) -> dict:
    readme = (d / "README.md").read_text()
    title = next((l[2:].strip() for l in readme.splitlines() if l.startswith("# ")), f"Mock exam {d.name}")
    tasks = sorted(t for t in (d / "tasks").iterdir() if t.is_dir())
    return {"n": d.name, "title": title, "tasks": len(tasks), "minutes": EXAM_MINUTES,
            "pass_mark": EXAM_PASS, "needs": read_meta(d / "meta").get("NEEDS", "").split(),
            **exam_state(d.name)}


# --- speed drills ---------------------------------------------------------------------

def drill_dirs() -> list:
    base = LAB_HOME / "drills"
    return sorted(d for d in base.iterdir() if d.is_dir() and ID_RE.match(d.name)) if base.exists() else []


def find_drill(drill_id: str) -> Path:
    for d in drill_dirs():
        if d.name == drill_id or d.name.split("-", 1)[0] == drill_id:
            return d
    raise web.HTTPNotFound(text="no such drill")


def drill_summary(d: Path, history: list) -> dict:
    meta = read_meta(d / "meta")
    gid = f"drill-{d.name}"
    runs = [h for h in history if h.get("id") == gid]
    passes = [h["seconds"] for h in runs if h.get("total") and h.get("pass") == h.get("total")]
    start = LAB_STATE / "drills" / f"{gid}.start"
    budget = int(meta["SECONDS"]) if meta.get("SECONDS", "").isdigit() else None
    return {
        "id": d.name, "num": d.name.split("-", 1)[0], "title": meta.get("TITLE", d.name),
        "domain": meta.get("DOMAIN", ""), "seconds": budget,
        "needs": [n for n in meta.get("NEEDS", "").split() if n],
        "best": min(passes) if passes else None, "attempts": len(runs),
        "inside": sum(1 for s in passes if budget and s <= budget),
        "last": runs[-1] if runs else None,
        "started": int(start.read_text().strip() or 0) if start.exists() else None,
    }


async def api_drills(request):
    history = read_jsonl(LAB_STATE / "drill-history.jsonl")
    return web.json_response({"drills": [drill_summary(d, history) for d in drill_dirs()], "now": int(time.time())})


async def api_drill(request):
    d = find_drill(request.match_info["id"])
    history = read_jsonl(LAB_STATE / "drill-history.jsonl")
    out = drill_summary(d, history)
    gid = f"drill-{d.name}"
    out["markdown"] = render_params((d / "task.md").read_text(), lab_params(gid), True)
    out["result"] = read_json(LAB_STATE / "results" / f"{gid}.json") if out["started"] else None
    out["history"] = [h for h in history if h.get("id") == gid][-20:]
    out["now"] = int(time.time())
    return web.json_response(out)


# --- Kubestronaut tracks and the quiz engine (KCNA, KCSA) -----------------------------------
#
# lab/tracks.json describes the five certifications. Multiple-choice tracks draw from
# question banks in the private solutions repo (questions/<track>/*.json), so answers
# never reach the public repo, and the browser only gets them after a sitting is handed
# in. A sitting is a file under WEB_STATE/quiz: the question order, each question's
# option shuffle, the answers so far, the deadline.

TRACKS_FILE = LAB_HOME / "tracks.json"
QUIZ_DIR = LAB_SOLUTIONS / "questions"
QUIZ_STATE = WEB_STATE / "quiz"
SID_RE = re.compile(r"^[0-9a-f]{12}$")
QUIZ_TIME_FACTOR = 0.8   # mock exams get 20% less time than the real one: harder on purpose


def tracks() -> list:
    try:
        return json.loads(TRACKS_FILE.read_text())["tracks"]
    except (FileNotFoundError, KeyError, ValueError):
        return []


def find_track(track_id: str) -> dict:
    for t in tracks():
        if t["id"] == track_id:
            return t
    raise web.HTTPNotFound(text="no such track")


def question_bank(track_id: str) -> list:
    out = []
    for f in sorted((QUIZ_DIR / track_id).glob("*.json")) if (QUIZ_DIR / track_id).is_dir() else []:
        try:
            out += json.loads(f.read_text())
        except ValueError:
            continue
    return [q for q in out if q.get("id") and q.get("options") and q.get("answer")]


def quiz_history(track_id: str) -> list:
    return [h for h in read_jsonl(LAB_STATE / "quiz-history.jsonl") if h.get("track") == track_id]


async def api_tracks(request):
    history = read_jsonl(LAB_STATE / "history.jsonl")
    out = []
    for t in tracks():
        t = dict(t)
        if t["kind"] == "quiz":
            bank = question_bank(t["id"])
            hist = quiz_history(t["id"])
            exams = [h["score"] for h in hist if h.get("mode") == "exam"]
            t.update(bank=len(bank), sittings=len(hist), best_exam=max(exams) if exams else None,
                     by_domain={d["key"]: sum(1 for q in bank if q.get("domain") == d["key"]) for d in t["domains"]})
        else:
            root = LAB_HOME / t.get("root", ".")
            labs = sorted(d for d in (root / "labs").iterdir() if d.is_dir() and ID_RE.match(d.name)) if (root / "labs").is_dir() else []
            passed = sum(1 for d in labs if any(h.get("id") == d.name and h.get("total") and h["pass"] == h["total"] for h in history))
            t.update(labs=len(labs), labs_passed=passed,
                     exams=len([d for d in (root / "exams").iterdir() if d.is_dir()]) if (root / "exams").is_dir() else 0,
                     drills=len([d for d in (root / "drills").iterdir() if d.is_dir()]) if (root / "drills").is_dir() else 0)
        out.append(t)
    return web.json_response({"tracks": out})


def sitting_path(sid: str) -> Path:
    if not SID_RE.match(sid):
        raise web.HTTPNotFound(text="no such sitting")
    return QUIZ_STATE / f"{sid}.json"


def load_sitting(sid: str) -> dict:
    try:
        return json.loads(sitting_path(sid).read_text())
    except FileNotFoundError:
        raise web.HTTPNotFound(text="no such sitting")


def save_sitting(st: dict):
    QUIZ_STATE.mkdir(parents=True, exist_ok=True)
    tmp = QUIZ_STATE / f".{st['sid']}.tmp"
    tmp.write_text(json.dumps(st))
    tmp.replace(sitting_path(st["sid"]))


def sitting_view(st: dict) -> dict:
    """What the browser may see: answers and explanations only once it's handed in."""
    bank = {q["id"]: q for q in question_bank(st["track"])}
    done = st.get("submitted_at") is not None
    items = []
    for it in st["items"]:
        q = bank.get(it["qid"])
        if not q:
            continue
        perm = it["perm"]                     # display position -> original option index
        view = {"qid": q["id"], "domain": q.get("domain"), "multi": len(q["answer"]) > 1 or q.get("type") == "multi",
                "stem": q["stem"], "options": [q["options"][i] for i in perm],
                "chosen": st["answers"].get(q["id"], []), "flagged": q["id"] in st.get("flags", [])}
        if done:
            view.update(correct=[perm.index(i) for i in q["answer"]], explain=q.get("explain", ""), refs=q.get("refs", []),
                        right=sorted(perm[i] for i in st["answers"].get(q["id"], [])) == sorted(q["answer"]))
        items.append(view)
    return {k: st.get(k) for k in ("sid", "track", "mode", "domain", "created", "deadline", "submitted_at", "result")} | \
        {"items": items, "now": int(time.time())}


async def api_quiz_start(request):
    t = find_track(request.match_info["track"])
    if t["kind"] != "quiz":
        raise web.HTTPBadRequest(text="not a multiple-choice track")
    body = await request.json() if request.can_read_body else {}
    mode = "exam" if body.get("mode") == "exam" else "practice"
    bank = question_bank(t["id"])
    rng = secrets.SystemRandom()
    if mode == "exam":
        # Like the real exam: questions spread over the domains by weight.
        want = int(t.get("questions", 60))
        picked = []
        for d in t["domains"]:
            pool = [q for q in bank if q.get("domain") == d["key"]]
            picked += rng.sample(pool, min(len(pool), round(want * d["weight"] / 100)))
        rng.shuffle(picked)
        deadline = int(time.time() + t["minutes"] * 60 * QUIZ_TIME_FACTOR * len(picked) / max(1, want))
        domain = None
    else:
        domain = body.get("domain") or None
        pool = [q for q in bank if domain is None or q.get("domain") == domain]
        picked = rng.sample(pool, min(len(pool), max(1, min(int(body.get("count") or 10), 60))))
        deadline = None
    if not picked:
        raise web.HTTPConflict(text="no questions installed for this track yet")
    items = []
    for q in picked:
        perm = list(range(len(q["options"])))
        if not q.get("keep_order"):
            rng.shuffle(perm)
        items.append({"qid": q["id"], "perm": perm})
    st = {"sid": secrets.token_hex(6), "track": t["id"], "mode": mode, "domain": domain, "created": int(time.time()),
          "deadline": deadline, "items": items, "answers": {}, "flags": [], "submitted_at": None, "result": None}
    save_sitting(st)
    return web.json_response(sitting_view(st))


async def api_quiz_sitting(request):
    return web.json_response(sitting_view(load_sitting(request.match_info["sid"])))


async def api_quiz_answer(request):
    st = load_sitting(request.match_info["sid"])
    if st.get("submitted_at"):
        raise web.HTTPConflict(text="already handed in")
    if st.get("deadline") and time.time() > st["deadline"] + 5:
        raise web.HTTPConflict(text="time is up")
    body = await request.json()
    qid = str(body.get("qid", ""))
    it = next((i for i in st["items"] if i["qid"] == qid), None)
    if not it:
        raise web.HTTPBadRequest(text="not in this sitting")
    if "choice" in body:
        st["answers"][qid] = sorted({int(c) for c in body["choice"] if 0 <= int(c) < len(it["perm"])})
    if "flag" in body:
        flags = set(st.get("flags", []))
        (flags.add if body["flag"] else flags.discard)(qid)
        st["flags"] = sorted(flags)
    save_sitting(st)
    return web.json_response({"ok": True})


async def api_quiz_submit(request):
    st = load_sitting(request.match_info["sid"])
    if not st.get("submitted_at"):
        t = find_track(st["track"])
        bank = {q["id"]: q for q in question_bank(st["track"])}
        per: dict = {}
        right = 0
        for it in st["items"]:
            q = bank.get(it["qid"])
            if not q:
                continue
            ok = sorted(it["perm"][i] for i in st["answers"].get(q["id"], [])) == sorted(q["answer"])
            right += ok
            c = per.setdefault(q.get("domain", "?"), [0, 0])
            c[0] += ok
            c[1] += 1
        total = len(st["items"])
        score = round(right * 100 / total) if total else 0
        st["submitted_at"] = int(time.time())
        st["result"] = {"correct": right, "total": total, "score": score, "pass_mark": t["pass"],
                        "passed": score >= t["pass"], "domains": per,
                        "seconds": st["submitted_at"] - st["created"]}
        save_sitting(st)
        LAB_STATE.mkdir(parents=True, exist_ok=True)
        with open(LAB_STATE / "quiz-history.jsonl", "a") as f:
            f.write(json.dumps({"track": st["track"], "mode": st["mode"], "domain": st["domain"], "sid": st["sid"],
                                "at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")} | st["result"]) + "\n")
    return web.json_response(sitting_view(st))


async def api_quiz_history(request):
    t = find_track(request.match_info["track"])
    return web.json_response({"history": quiz_history(t["id"])[-50:]})


# --- auth ---------------------------------------------------------------------------

SESSIONS: dict = {}            # token -> expiry
FAILED: dict = {}              # remote ip -> [count, first failure time]


def verify_password(password: str) -> bool:
    spec = os.environ.get("WEB_PASSWORD_HASH", "")
    try:
        algo, iters, salt, want = spec.split("$")
        assert algo == "pbkdf2_sha256"
    except (ValueError, AssertionError):
        return False
    got = hashlib.pbkdf2_hmac("sha256", password.encode(), bytes.fromhex(salt), int(iters))
    return hmac.compare_digest(got.hex(), want)


def authed(request) -> bool:
    tok = request.cookies.get("labweb")
    exp = SESSIONS.get(tok or "")
    if not exp or exp < time.time():
        SESSIONS.pop(tok or "", None)
        return False
    SESSIONS[tok] = time.time() + SESSION_TTL
    return True


def same_origin(request) -> bool:
    origin = request.headers.get("Origin")
    if origin is None:
        return True
    return origin.split("://", 1)[-1] == request.host


@web.middleware
async def security(request, handler):
    path = request.path
    if path.startswith("/api/") and path not in ("/api/login", "/api/health"):
        if not authed(request):
            raise web.HTTPUnauthorized(text="log in first")
        if request.method not in ("GET", "HEAD") and request.headers.get("X-Lab") != "1":
            raise web.HTTPForbidden(text="missing X-Lab header")
        if not same_origin(request):
            raise web.HTTPForbidden(text="cross-origin request refused")
        if not (request.method == "GET" and (path in PASSIVE or path.endswith("/stream") or path.endswith("/ws"))):
            touch()
    resp = await handler(request)
    resp.headers.setdefault("X-Content-Type-Options", "nosniff")
    resp.headers.setdefault("Referrer-Policy", "no-referrer")
    # WEB_DEV=1 (local development only) allows same-origin framing, for previewing layouts.
    frames = "'self'" if os.environ.get("WEB_DEV") else "'none'"
    if not os.environ.get("WEB_DEV"):
        resp.headers.setdefault("X-Frame-Options", "DENY")
    resp.headers.setdefault(
        "Content-Security-Policy",
        "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; "
        f"img-src 'self' data:; font-src 'self'; connect-src 'self' wss://{request.host} ws://{request.host}; "
        f"frame-ancestors {frames}; base-uri 'none'; form-action 'self'")
    if path.startswith("/api/"):
        resp.headers.setdefault("Cache-Control", "no-store")
    elif path.startswith("/static/"):
        # Revalidate every time (cheap on a LAN): an update is never hidden by a stale copy.
        resp.headers.setdefault("Cache-Control", "no-cache")
    return resp


async def login(request):
    ip = request.remote or "?"
    count, first = FAILED.get(ip, [0, time.time()])
    if count >= 8 and time.time() - first < 300:
        raise web.HTTPTooManyRequests(text="too many attempts; wait five minutes")
    body = await request.json()
    if not same_origin(request) or not verify_password(str(body.get("password", ""))):
        await asyncio.sleep(1)
        FAILED[ip] = [count + 1, first if time.time() - first < 300 else time.time()]
        raise web.HTTPUnauthorized(text="wrong password")
    FAILED.pop(ip, None)
    tok = secrets.token_urlsafe(32)
    SESSIONS[tok] = time.time() + SESSION_TTL
    resp = web.json_response({"ok": True})
    resp.set_cookie("labweb", tok, httponly=True, secure=request.secure, samesite="Strict", path="/")
    return resp


async def logout(request):
    SESSIONS.pop(request.cookies.get("labweb", ""), None)
    resp = web.json_response({"ok": True})
    resp.del_cookie("labweb", path="/")
    return resp


async def health(request):
    return web.json_response({"ok": True, "authed": authed(request)})


# --- labs and exams API -----------------------------------------------------------------

def activity(history: list, exams: list, days: int = 14) -> list:
    """Gradings per day (lab checks and mock exams) for the last `days` days, oldest first."""
    today = datetime.date.today()
    counts = {today - datetime.timedelta(days=i): 0 for i in range(days)}
    for h in history + exams:
        try:
            day = datetime.datetime.fromisoformat(str(h.get("at", "")).replace("Z", "+00:00")).astimezone().date()
        except ValueError:
            continue
        if day in counts:
            counts[day] += 1
    return [{"day": d.isoformat(), "n": counts[d]} for d in sorted(counts)]


async def api_overview(request):
    history = read_jsonl(LAB_STATE / "history.jsonl")
    return web.json_response({
        "activity": activity(history, read_jsonl(LAB_STATE / "exam-history.jsonl")),
        "labs": [lab_summary(d, history) for d in lab_dirs()],
        "exams": [exam_summary(d) for d in exam_dirs()],
        "solutions": LAB_SOLUTIONS.exists(),
        "can_spin_up": (LAB_SOLUTIONS / "labs").is_dir(),
        # Presets saved as live snapshots by an earlier spin-up: restored in under a minute.
        "playground_cached": {p: (JUMP_SNAPS / f"pg-{p}.tgz").exists() for p in ("core", "full")},
        "last_reset": int((LAB_STATE / "last-reset").read_text().strip() or 0) if (LAB_STATE / "last-reset").exists() else 0,
    })


async def api_lab(request):
    d = find_lab(request.match_info["id"])
    history = read_jsonl(LAB_STATE / "history.jsonl")
    out = lab_summary(d, history)
    out["markdown"] = render_params((d / "task.md").read_text(), lab_params(d.name), (d / "params").exists())
    out["randomised"] = (d / "params").exists()
    out["history"] = [h for h in history if h.get("id") == d.name][-30:]
    return web.json_response(out)


async def api_solution(request):
    d = find_lab(request.match_info["id"])
    f = LAB_SOLUTIONS / "labs" / d.name / "solution.md"
    if not f.exists():
        raise web.HTTPNotFound(text="no solution installed for this lab")
    return web.json_response({"markdown": render_params(f.read_text(), lab_params(d.name), (d / "params").exists())})


async def api_exam(request):
    d = find_exam(request.match_info["n"])
    n = d.name
    tasks = []
    for t in sorted(t for t in (d / "tasks").iterdir() if t.is_dir()):
        meta = read_meta(t / "meta")
        tasks.append({
            "id": t.name,
            "title": meta.get("TITLE", t.name),
            "domain": meta.get("DOMAIN", ""),
            "weight": int(meta.get("WEIGHT", "0") or 0),
            "context": f"e{n}-t{int(t.name[:2])}",   # made by `lab exam <n> start`
            "markdown": (t / "task.md").read_text(),
            "result": read_json(LAB_STATE / "results" / f"exam{n}-{t.name}.json"),
        })
    out = exam_summary(d)
    out.update({"readme": (d / "README.md").read_text(), "task_list": tasks, "now": int(time.time())})
    return web.json_response(out)


async def api_exam_submit(request):
    """Mark the current sitting as handed in (the grade itself is a job)."""
    n = find_exam(request.match_info["n"]).name
    st = exam_state(n)
    if not st["deadline"]:
        raise web.HTTPConflict(text="exam not started")
    WEB_STATE.mkdir(parents=True, exist_ok=True)
    (WEB_STATE / f"exam-{n}.json").write_text(json.dumps({"deadline": st["deadline"], "submitted_at": int(time.time())}))
    return web.json_response({"ok": True})


# Small per-user documents: lab notes, the exam notepad, exam flags.
async def api_get_note(request):
    key = request.match_info["key"]
    if not KEY_RE.match(key):
        raise web.HTTPBadRequest()
    return web.json_response(read_json(WEB_STATE / "notes" / f"{key}.json") or {"value": None})


async def api_put_note(request):
    key = request.match_info["key"]
    raw = await request.read()
    if not KEY_RE.match(key) or len(raw) > 64 * 1024:
        raise web.HTTPBadRequest()
    value = json.loads(raw).get("value")
    (WEB_STATE / "notes").mkdir(parents=True, exist_ok=True)
    tmp = WEB_STATE / "notes" / f".{key}.tmp"
    tmp.write_text(json.dumps({"value": value, "at": int(time.time())}))
    tmp.replace(WEB_STATE / "notes" / f"{key}.json")
    return web.json_response({"ok": True})


# --- jobs: `lab` commands with streamed output -------------------------------------------

ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
JOBS_DIR = WEB_STATE / "jobs"


class Job:
    def __init__(self, jid, action, target, argv, label, subject=None):
        self.id, self.action, self.target, self.argv, self.label = jid, action, target, argv, label
        self.subject = subject          # {"kind", "id", "title"} of what this job prepares, or None
        self.chunks: list = []
        self.started = time.time()
        self.ended = None
        self.code = None
        self.cond = asyncio.Condition()

    def progress(self) -> str:
        """The last line the command printed: what it's doing right now."""
        tail = ANSI_RE.sub("", "".join(self.chunks[-40:])).replace("\r", "\n")
        lines = [l.strip() for l in tail.splitlines() if l.strip()]
        return lines[-1][:160] if lines else ""

    def info(self):
        return {"id": self.id, "action": self.action, "target": self.target, "label": self.label,
                "started": self.started, "ended": self.ended, "code": self.code, "subject": self.subject,
                "progress": self.progress()}

    def save(self):
        """Keep finished jobs on disk, so their output survives a restart of the console."""
        try:
            JOBS_DIR.mkdir(parents=True, exist_ok=True)
            (JOBS_DIR / f"{self.id}.log").write_text("".join(self.chunks))
            (JOBS_DIR / f"{self.id}.json").write_text(json.dumps(self.info() | {"argv": self.argv}))
            for old in sorted(JOBS_DIR.glob("*.json"), key=lambda f: f.stat().st_mtime)[:-30]:
                old.unlink(missing_ok=True)
                old.with_suffix(".log").unlink(missing_ok=True)
        except OSError:
            pass


def load_jobs():
    """Finished jobs from earlier runs of the console; a job cut off by a restart shows as such."""
    for f in sorted(JOBS_DIR.glob("*.json"), key=lambda f: f.stat().st_mtime)[-20:] if JOBS_DIR.exists() else []:
        try:
            d = json.loads(f.read_text())
            j = Job(d["id"], d["action"], d["target"], d.get("argv", []), d["label"], d.get("subject"))
            j.started, j.ended, j.code = d["started"], d.get("ended") or d["started"], d.get("code", -1)
            j.chunks = [f.with_suffix(".log").read_text()] if f.with_suffix(".log").exists() else []
            JOBS[j.id] = j
        except (OSError, ValueError, KeyError):
            continue


JOBS: dict = {}
CURRENT: dict = {"job": None}


# --- what you're working on ----------------------------------------------------------------
#
# One thing at a time, as the cluster is shared: a lab, a drill, a mock exam or the
# playground. Its phase: preparing (setup running), ready, failed (setup failed) or
# interrupted (the console restarted mid-setup). Kept in a file, so it outlives the tab.

ACTIVITY_FILE = WEB_STATE / "activity.json"


def activity_get():
    return read_json(ACTIVITY_FILE)


def activity_set(a):
    WEB_STATE.mkdir(parents=True, exist_ok=True)
    if a is None:
        ACTIVITY_FILE.unlink(missing_ok=True)
        return
    a["updated"] = int(time.time())
    tmp = WEB_STATE / ".activity.tmp"
    tmp.write_text(json.dumps(a))
    tmp.replace(ACTIVITY_FILE)


def job_subject(action: str, target: str):
    """What a start-like job sets up, for the activity record. None for every other job."""
    if action in ("lab-start", "lab-up"):
        d = find_lab(target)
        return {"kind": "lab", "id": d.name, "num": d.name[:2], "title": read_meta(d / "meta").get("TITLE", d.name)}
    if action == "drill-start":
        d = find_drill(target)
        return {"kind": "drill", "id": d.name, "num": d.name[:2], "title": read_meta(d / "meta").get("TITLE", d.name)}
    if action in ("exam-start", "exam-prep", "exam-begin"):
        return {"kind": "exam", "id": target, "num": target, "title": f"Mock exam {target}"}
    if action == "playground":
        return {"kind": "playground", "id": target, "num": "", "title": f"Playground ({target})"}
    return None


def same_subject(a, kind: str, target: str) -> bool:
    return bool(a) and a.get("kind") == kind and target in (a.get("id"), a.get("num"))


def job_finished(job):
    """Move the activity on when a job ends."""
    a = activity_get()
    if job.subject:
        if a and a.get("job") == job.id:
            if job.code == 0:
                a.update(phase="ready" if job.action != "exam-prep" else "prepared", ready_at=int(time.time()), error=None)
            else:
                a.update(phase="failed", error=job.progress())
            activity_set(a)
        return
    kind = job.action.split("-", 1)[0]
    if job.code == 0 and job.action in ("lab-cleanup", "drill-cleanup", "exam-cleanup") and same_subject(a, kind, job.target):
        activity_set(None)
    elif job.code == 0 and job.action == "reset" and a:
        activity_set(None)          # the cluster went back to a snapshot: what was set up is gone


def job_argv(action: str, target: str, arg: str):
    """Whitelist: every job maps to a fixed `lab` command line. Returns (argv, stdin, label)."""
    if action.startswith("lab-"):
        d = find_lab(target)
        lab_id = d.name
        if action in ("lab-start", "lab-up"):
            verb = action[4:]
            phases = read_meta(d / "meta").get("PHASES", "").split()
            if arg and arg not in phases:
                raise web.HTTPBadRequest(text="unknown phase")
            return [LAB_BIN, verb, lab_id] + ([arg] if arg else []), None, f"lab {verb} {lab_id} {arg}".strip()
        if action == "lab-check":
            return [LAB_BIN, "check", lab_id], None, f"lab check {lab_id}"
        if action == "lab-cleanup":
            return [LAB_BIN, "cleanup", lab_id, "--yes"], None, f"lab cleanup {lab_id}"
    if action.startswith("exam-"):
        n = find_exam(target).name
        sub = action[5:]
        if sub in ("start", "check", "prep"):
            return [LAB_BIN, "exam", n, sub], None, f"lab exam {n} {sub}"
        if sub == "cleanup":
            return [LAB_BIN, "exam", n, "cleanup", "--yes"], None, f"lab exam {n} cleanup"
        if sub == "begin":
            snap = ["--snapshot"] if arg == "snapshot" else []
            return [LAB_BIN, "exam", n, "begin"] + snap, None, f"lab exam {n} begin {' '.join(snap)}".strip()
    if action.startswith("drill-"):
        drill_id = find_drill(target).name
        sub = action[6:]
        if sub == "start":
            return [LAB_BIN, "drill", drill_id], None, f"lab drill {drill_id}"
        if sub in ("check", "cleanup"):
            return [LAB_BIN, "drill", sub, drill_id], None, f"lab drill {sub} {drill_id}"
    if action == "playground":
        if target not in ("core", "full"):
            raise web.HTTPBadRequest(text="unknown playground")
        return [LAB_BIN, "playground", target], None, f"lab playground {target}"
    if action == "power":
        if target not in ("on", "off", "shutdown"):
            raise web.HTTPBadRequest(text="unknown power action")
        return [LAB_BIN, "power", target], None, f"lab power {target}"
    if action in ("snapshot", "reset", "snapshot-delete"):
        if not SNAP_RE.match(target):
            raise web.HTTPBadRequest(text="invalid snapshot name")
        if action == "snapshot":
            return [LAB_BIN, "snapshot", target], None, f"lab snapshot {target}"
        if action == "snapshot-delete":
            if target == "base":
                raise web.HTTPBadRequest(text="base can't be deleted")
            return [LAB_BIN, "snapshots", "delete", target], None, f"lab snapshots delete {target}"
        return [LAB_BIN, "reset", target], b"y\n", f"lab reset {target}"
    raise web.HTTPBadRequest(text="unknown action")


async def run_job(job: Job, stdin: bytes | None):
    env = dict(os.environ, TERM="xterm-256color")
    env.pop("WEB_PASSWORD_HASH", None)
    try:
        proc = await asyncio.create_subprocess_exec(
            *job.argv, stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT, env=env, cwd=str(Path.home()), start_new_session=True)
        proc.stdin.write(stdin or b"")
        proc.stdin.close()
        while True:
            data = await proc.stdout.read(4096)
            if not data:
                break
            async with job.cond:
                job.chunks.append(data.decode("utf-8", "replace"))
                job.cond.notify_all()
        job.code = await proc.wait()
    except Exception as e:  # pragma: no cover - surfaced to the page
        job.chunks.append(f"\n[lab-web] could not run the job: {e}\n")
        job.code = -1
    async with job.cond:
        job.ended = time.time()
        job.cond.notify_all()
    if CURRENT["job"] is job:
        CURRENT["job"] = None
    try:
        job_finished(job)
    except Exception:  # pragma: no cover - never let bookkeeping break the job runner
        pass
    job.save()
    touch()


async def api_start_job(request):
    body = await request.json()
    action, target, arg = str(body.get("action", "")), str(body.get("target", "")), str(body.get("arg", ""))
    if CURRENT["job"] is not None:
        raise web.HTTPConflict(text=f"'{CURRENT['job'].label}' is still running")
    argv, stdin, label = job_argv(action, target, arg)
    job = Job(secrets.token_hex(6), action, target, argv, label, job_subject(action, target))
    JOBS[job.id] = job
    if job.subject:
        activity_set(dict(job.subject, phase="preparing", job=job.id, since=int(time.time()), arg=arg or None))
    elif action.endswith("-check") and same_subject(activity_get(), action.split("-", 1)[0], target):
        a = activity_get()
        a["checked_at"] = int(time.time())
        activity_set(a)
    for old in sorted(JOBS.values(), key=lambda j: j.started)[:-20]:
        JOBS.pop(old.id, None)
    CURRENT["job"] = job
    asyncio.create_task(run_job(job, stdin))
    return web.json_response(job.info())


async def api_jobs(request):
    cur = CURRENT["job"]
    recent = sorted(JOBS.values(), key=lambda j: j.started, reverse=True)[:10]
    return web.json_response({"current": cur.info() if cur else None, "recent": [j.info() for j in recent]})


async def api_job_stream(request):
    """Server-sent events: everything printed so far, then live output, then 'end'."""
    job = JOBS.get(request.match_info["jid"])
    if not job:
        raise web.HTTPNotFound(text="no such job")
    resp = web.StreamResponse(headers={"Content-Type": "text/event-stream", "Cache-Control": "no-store",
                                       "X-Accel-Buffering": "no"})
    await resp.prepare(request)
    sent = 0
    try:
        while True:
            async with job.cond:
                while sent == len(job.chunks) and job.ended is None:
                    try:
                        await asyncio.wait_for(job.cond.wait(), 15)
                    except asyncio.TimeoutError:
                        break
                chunks, sent, ended = job.chunks[sent:], len(job.chunks), job.ended
            if chunks:
                await resp.write(f"event: out\ndata: {json.dumps(''.join(chunks))}\n\n".encode())
            else:
                await resp.write(b": keepalive\n\n")
            if ended is not None and sent == len(job.chunks):
                await resp.write(f"event: end\ndata: {json.dumps(job.info())}\n\n".encode())
                break
    except (ConnectionResetError, asyncio.CancelledError):
        pass
    return resp


# --- cluster status: Proxmox power state + Kubernetes nodes --------------------------------

def env_file(path: Path) -> dict:
    out = {}
    try:
        for line in path.read_text().splitlines():
            m = re.match(r'^([A-Z_]+)=(.*)$', line.strip())
            if m:
                out[m.group(1)] = m.group(2).strip().strip('"')
    except (FileNotFoundError, PermissionError):
        pass
    return out


def lab_vms() -> list:
    vms = []  # LAB_VMS is a multi-line string: one "name vmid ip cores mem disk extra role" row per VM
    try:
        text = LAB_ENV.read_text()
        block = text.split('LAB_VMS="', 1)[1].split('"', 1)[0]
        for line in block.splitlines():
            f = line.split()
            if len(f) >= 8 and not f[0].startswith("#"):
                vms.append({"name": f[0], "vmid": int(f[1]), "ip": f[2], "cores": int(f[3]),
                            "mem_mb": int(f[4]), "role": f[7]})
    except (FileNotFoundError, IndexError, ValueError):
        pass
    return vms


def pve_get(path: str):
    env = env_file(PVE_ENV)
    if not env.get("PVE_TOKEN"):
        return None
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE  # Proxmox's self-signed certificate; the lab CLI uses curl -k too
    req = urllib.request.Request(f"{env['PVE_URL']}/api2/json/nodes/{env['PVE_NODE']}/qemu{path}",
                                 headers={"Authorization": f"PVEAPIToken={env['PVE_TOKEN']}"})
    with urllib.request.urlopen(req, context=ctx, timeout=6) as r:
        return json.load(r)["data"]


CLUSTER_CACHE: dict = {"at": 0, "data": None, "kubeconfig_tried": 0}


async def run(argv, timeout=20, stdin=None):
    proc = await asyncio.create_subprocess_exec(*argv, stdin=asyncio.subprocess.PIPE,
                                                stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
    try:
        out, _ = await asyncio.wait_for(proc.communicate(stdin), timeout)
    except asyncio.TimeoutError:
        proc.kill()
        return 124, b""
    return proc.returncode, out


async def k8s_nodes():
    kubectl = str(LAB_HOME / "bin" / "kubectl")
    kubeconfig = LAB_STATE / "grader.kubeconfig"
    argv = [kubectl, "--kubeconfig", str(kubeconfig), "--request-timeout=4s", "get", "nodes", "-o", "json"]
    code, out = await run(argv, 8) if kubeconfig.exists() else (1, b"")
    if code != 0 and time.time() - CLUSTER_CACHE["kubeconfig_tried"] > 60:
        # Same helper the graders use: fetch admin.conf from a control plane.
        CLUSTER_CACHE["kubeconfig_tried"] = time.time()
        await run(["bash", "-c", f"source {LAB_HOME}/lib/common.sh && grader_kubeconfig"], 30)
        code, out = await run(argv, 8) if kubeconfig.exists() else (1, b"")
    if code != 0:
        return None
    nodes = []
    for n in json.loads(out).get("items", []):
        conds = {c["type"]: c["status"] for c in n.get("status", {}).get("conditions", [])}
        labels = n["metadata"].get("labels", {})
        nodes.append({
            "name": n["metadata"]["name"],
            "ready": conds.get("Ready") == "True",
            "roles": sorted(k.split("/", 1)[1] for k in labels if k.startswith("node-role.kubernetes.io/")),
            "version": n.get("status", {}).get("nodeInfo", {}).get("kubeletVersion"),
            "unschedulable": bool(n.get("spec", {}).get("unschedulable")),
        })
    return nodes


async def api_cluster(request):
    if CLUSTER_CACHE["data"] and time.time() - CLUSTER_CACHE["at"] < 10 and not request.query.get("fresh"):
        return web.json_response(CLUSTER_CACHE["data"])
    loop = asyncio.get_running_loop()
    vms = lab_vms()
    try:
        power = await loop.run_in_executor(None, pve_get, "")
        by_id = {p["vmid"]: p for p in (power or [])}
    except Exception:
        by_id, power = {}, None
    for vm in vms:
        p = by_id.get(vm["vmid"])
        vm["status"] = p.get("status") if p else None
        vm["uptime"] = p.get("uptime") if p else None
    nodes = await k8s_nodes()
    data = {"vms": vms, "nodes": nodes, "pve": power is not None, "at": int(time.time())}
    CLUSTER_CACHE.update(at=time.time(), data=data)
    return web.json_response(data)


async def api_snapshots(request):
    loop = asyncio.get_running_loop()
    vms = lab_vms()
    snaps: dict = {}
    try:
        for vm in vms:
            for s in await loop.run_in_executor(None, pve_get, f"/{vm['vmid']}/snapshot") or []:
                if s.get("name") == "current":
                    continue
                e = snaps.setdefault(s["name"], {"name": s["name"], "vms": [], "time": s.get("snaptime"),
                                                 "description": s.get("description", "").strip()})
                e["vms"].append(vm["name"])
                e["time"] = max(e["time"] or 0, s.get("snaptime") or 0)
    except Exception as e:
        return web.json_response({"error": f"Proxmox API: {e}", "snapshots": []})
    # Newer snapshots cover the node VMs, plus the jump host's lab state saved as a file
    # (lab reset leaves the jump VM running); older ones include the jump VM itself.
    nodes = [vm["name"] for vm in vms if vm["role"] != "jump"]
    for f in JUMP_SNAPS.glob("*.tgz"):
        e = snaps.get(f.stem)
        if e is not None:
            e["jump_state"] = True
    out = sorted(snaps.values(), key=lambda s: s["time"] or 0)
    for s in out:
        s.setdefault("jump_state", False)
        s["complete"] = all(n in s["vms"] for n in nodes) and (s["jump_state"] or len(s["vms"]) == len(vms))
    return web.json_response({"snapshots": out, "vm_count": len(vms)})


# --- power: idle shutdown ------------------------------------------------------------------
#
# Nothing has to run all the time. After IDLE minutes with no one using the console
# (no clicks or keys in it, no typing in a terminal, no job running, no mock exam on
# the clock), the cluster VMs and then this jump host shut down. The gate on Proxmox
# starts them again. The browser warns five minutes ahead and "Stay on" resets it.

POWER_FILE = WEB_STATE / "power.json"
IDLE_DEFAULT = int(os.environ.get("IDLE_MINUTES", "30"))
IDLE: dict = {"last": time.time(), "shutting_down": False}
PASSIVE = ("/api/state", "/api/cluster", "/api/jobs", "/api/health", "/api/snapshots")


def touch():
    IDLE["last"] = time.time()


def power_settings() -> dict:
    p = read_json(POWER_FILE) or {}
    return {"idle_minutes": int(p.get("idle_minutes", IDLE_DEFAULT)), "awake_until": int(p.get("awake_until", 0))}


def exam_running() -> bool:
    now = time.time()
    for d in exam_dirs():
        st = exam_state(d.name)
        if st["deadline"] and not st["submitted_at"] and st["deadline"] > now:
            return True
    return False


def idle_left():
    """Seconds until the idle shutdown, or None while something keeps HelmYard on."""
    ps = power_settings()
    if ps["idle_minutes"] <= 0 or CURRENT["job"] is not None or ps["awake_until"] > time.time() or exam_running():
        return None
    return max(0, int(IDLE["last"] + ps["idle_minutes"] * 60 - time.time()))


async def idle_reaper(app):
    async def loop():
        while True:
            await asyncio.sleep(30)
            try:
                left = idle_left()
                if left == 0 and not IDLE["shutting_down"] and env_file(PVE_ENV).get("PVE_TOKEN"):
                    IDLE["shutting_down"] = True
                    argv, stdin, label = job_argv("power", "shutdown", "")
                    job = Job(secrets.token_hex(6), "power", "shutdown", argv, f"{label} (idle {power_settings()['idle_minutes']} min)")
                    JOBS[job.id] = job
                    CURRENT["job"] = job
                    asyncio.create_task(run_job(job, stdin))
            except Exception:  # pragma: no cover
                pass
    app["reaper"] = asyncio.create_task(loop())


async def api_power(request):
    if request.method == "PUT":
        body = await request.json()
        ps = power_settings()
        if "idle_minutes" in body:
            ps["idle_minutes"] = max(0, min(24 * 60, int(body["idle_minutes"])))
        if "awake_hours" in body:   # keep HelmYard on for a while (0 clears it)
            h = max(0, min(24, float(body["awake_hours"])))
            ps["awake_until"] = int(time.time() + h * 3600) if h else 0
        WEB_STATE.mkdir(parents=True, exist_ok=True)
        POWER_FILE.write_text(json.dumps(ps))
        touch()
    return web.json_response(power_settings() | {"idle_left": idle_left(), "can_power": bool(env_file(PVE_ENV).get("PVE_TOKEN"))})


async def api_ping(request):
    touch()
    IDLE["shutting_down"] = False
    return web.json_response({"idle_left": idle_left()})


async def api_state(request):
    """Everything the page header needs, cheap enough to poll every few seconds."""
    cur = CURRENT["job"]
    c = CLUSTER_CACHE.get("data") or {}
    vms = [v for v in c.get("vms", []) if v.get("role") == "node"]
    return web.json_response({
        "now": int(time.time()),
        "job": cur.info() if cur else None,
        "activity": activity_get(),
        "power": power_settings() | {"idle_left": idle_left(), "shutting_down": IDLE["shutting_down"],
                                     "gate_url": os.environ.get("GATE_URL") or None,
                                     "nodes_running": sum(1 for v in vms if v.get("status") == "running"),
                                     "nodes": len(vms), "known": bool(c.get("pve"))},
        "exam_running": exam_running(),
    })


# --- terminals ---------------------------------------------------------------------------

class Terminal:
    def __init__(self, sid: str, title: str):
        self.sid, self.title = sid, title
        self.buffer = bytearray()
        self.clients: set = set()
        self.created = time.time()
        env = {k: v for k, v in os.environ.items() if not k.startswith(("WEB_", "INVOCATION_", "JOURNAL_"))}
        env.update(TERM="xterm-256color", COLORTERM="truecolor", LANG=env.get("LANG", "C.UTF-8"),
                   SHELL="/bin/bash", LAB_WEB="1")
        self.pid, self.fd = pty.fork()
        if self.pid == 0:  # child
            # Python ignores SIGPIPE and the shell would inherit that: `cmd | head` would then
            # print "Broken pipe" errors and `yes | head` would never end. Restore the defaults.
            for sig in (signal.SIGPIPE, signal.SIGXFSZ, signal.SIGINT, signal.SIGQUIT, signal.SIGTERM):
                signal.signal(sig, signal.SIG_DFL)
            os.chdir(str(Path.home()))
            os.execvpe("bash", ["bash", "-l"], env)
        flags = fcntl.fcntl(self.fd, fcntl.F_GETFL)
        fcntl.fcntl(self.fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)
        asyncio.get_running_loop().add_reader(self.fd, self._readable)

    def _readable(self):
        try:
            data = os.read(self.fd, 65536)
        except (BlockingIOError, InterruptedError):
            return
        except OSError:
            data = b""
        if not data:
            self.close()
            return
        self.buffer += data
        if len(self.buffer) > TERM_BUFFER:
            del self.buffer[: len(self.buffer) - TERM_BUFFER]
        for ws in list(self.clients):
            asyncio.ensure_future(self._send(ws, data))

    @staticmethod
    async def _send(ws, data):
        try:
            await ws.send_bytes(data)
        except Exception:
            pass

    def write(self, data: bytes):
        try:
            os.write(self.fd, data)
        except OSError:
            pass

    def resize(self, cols: int, rows: int):
        try:
            fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        except OSError:
            pass

    def close(self):
        if TERMS.pop(self.sid, None) is None:
            return
        try:
            asyncio.get_running_loop().remove_reader(self.fd)
        except Exception:
            pass
        try:
            os.kill(self.pid, signal.SIGHUP)
        except ProcessLookupError:
            pass
        try:
            os.close(self.fd)
        except OSError:
            pass
        asyncio.get_running_loop().call_later(3, reap, self.pid)
        for ws in list(self.clients):
            asyncio.ensure_future(ws.close(code=4000, message=b"shell exited"))


TERMS: dict = {}


def reap(pid: int):
    """Collect an exited shell. Only our own PIDs: asyncio reaps its job subprocesses itself."""
    try:
        if os.waitpid(pid, os.WNOHANG)[0] == 0:
            os.kill(pid, signal.SIGKILL)
            asyncio.get_running_loop().call_later(1, reap, pid)
    except (ChildProcessError, ProcessLookupError):
        pass


async def api_terms(request):
    return web.json_response([{"sid": t.sid, "title": t.title, "created": t.created, "clients": len(t.clients)}
                              for t in sorted(TERMS.values(), key=lambda t: t.created)])


async def api_new_term(request):
    if len(TERMS) >= MAX_TERMS:
        raise web.HTTPConflict(text=f"at most {MAX_TERMS} terminals; close one first")
    body = await request.json() if request.can_read_body else {}
    n = 1
    while any(t.title == f"shell {n}" for t in TERMS.values()):
        n += 1
    title = str(body.get("title") or f"shell {n}")[:24]
    t = Terminal(secrets.token_hex(6), title)
    TERMS[t.sid] = t
    return web.json_response({"sid": t.sid, "title": t.title})


async def api_rename_term(request):
    t = TERMS.get(request.match_info["sid"])
    if not t:
        raise web.HTTPNotFound(text="no such terminal")
    body = await request.json()
    title = " ".join("".join(c for c in str(body.get("title", "")) if c.isprintable()).split())[:24].rstrip()
    if not title:
        raise web.HTTPBadRequest(text="empty title")
    t.title = title
    return web.json_response({"sid": t.sid, "title": t.title})


async def api_close_term(request):
    t = TERMS.get(request.match_info["sid"])
    if t:
        t.close()
    return web.json_response({"ok": True})


async def term_ws(request):
    t = TERMS.get(request.match_info["sid"])
    if not t:
        raise web.HTTPNotFound(text="no such terminal")
    ws = web.WebSocketResponse(heartbeat=25, max_msg_size=1 << 20)
    await ws.prepare(request)
    if t.buffer:
        await ws.send_bytes(bytes(t.buffer))
    t.clients.add(ws)
    try:
        async for msg in ws:
            if msg.type == WSMsgType.TEXT:
                try:
                    m = json.loads(msg.data)
                except json.JSONDecodeError:
                    continue
                if m.get("t") == "i":
                    t.write(str(m.get("d", "")).encode())
                    touch()
                elif m.get("t") == "r":
                    t.resize(max(10, min(500, int(m.get("c", 80)))), max(4, min(300, int(m.get("r", 24)))))
            elif msg.type == WSMsgType.BINARY:
                t.write(msg.data)
                touch()
    finally:
        t.clients.discard(ws)
    return ws


# --- static files --------------------------------------------------------------------------

async def index(request):
    resp = web.FileResponse(STATIC / "index.html")
    resp.headers["Cache-Control"] = "no-cache"
    return resp


def make_app() -> web.Application:
    app = web.Application(middlewares=[security], client_max_size=256 * 1024)
    r = app.router
    r.add_get("/", index)
    r.add_post("/api/login", login)
    r.add_post("/api/logout", logout)
    r.add_get("/api/health", health)
    r.add_get("/api/overview", api_overview)
    r.add_get("/api/labs/{id}", api_lab)
    r.add_get("/api/labs/{id}/solution", api_solution)
    r.add_get("/api/exams/{n}", api_exam)
    r.add_post("/api/exams/{n}/submit", api_exam_submit)
    r.add_get("/api/notes/{key}", api_get_note)
    r.add_put("/api/notes/{key}", api_put_note)
    r.add_get("/api/tracks", api_tracks)
    r.add_post("/api/quiz/{track}/start", api_quiz_start)
    r.add_get("/api/quiz/{track}/history", api_quiz_history)
    r.add_get("/api/quiz/sittings/{sid}", api_quiz_sitting)
    r.add_put("/api/quiz/sittings/{sid}/answer", api_quiz_answer)
    r.add_post("/api/quiz/sittings/{sid}/submit", api_quiz_submit)
    r.add_get("/api/drills", api_drills)
    r.add_get("/api/drills/{id}", api_drill)
    r.add_get("/api/state", api_state)
    r.add_get("/api/power", api_power)
    r.add_put("/api/power", api_power)
    r.add_post("/api/ping", api_ping)
    r.add_get("/api/jobs", api_jobs)
    r.add_post("/api/jobs", api_start_job)
    r.add_get("/api/jobs/{jid}/stream", api_job_stream)
    r.add_get("/api/cluster", api_cluster)
    r.add_get("/api/snapshots", api_snapshots)
    r.add_get("/api/terms", api_terms)
    r.add_post("/api/terms", api_new_term)
    r.add_patch("/api/terms/{sid}", api_rename_term)
    r.add_delete("/api/terms/{sid}", api_close_term)
    r.add_get("/api/terms/{sid}/ws", term_ws)
    r.add_static("/static/", STATIC, append_version=False)
    app.on_startup.append(idle_reaper)
    return app


def main():
    if not os.environ.get("WEB_PASSWORD_HASH"):
        raise SystemExit("WEB_PASSWORD_HASH is not set (see /etc/cka-lab/web.env)")
    WEB_STATE.mkdir(parents=True, exist_ok=True)
    load_jobs()
    a = activity_get()
    if a and a.get("phase") == "preparing":   # its job died with the previous run of the console
        a.update(phase="interrupted", error="The console restarted while this was being set up. Start it again.")
        activity_set(a)
    ctx = None
    if os.environ.get("WEB_CERT"):
        ctx = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
        ctx.minimum_version = ssl.TLSVersion.TLSv1_2
        ctx.load_cert_chain(os.environ["WEB_CERT"], os.environ["WEB_KEY"])
    web.run_app(make_app(), host=os.environ.get("WEB_HOST", "0.0.0.0"),
                port=int(os.environ.get("WEB_PORT", "443")), ssl_context=ctx, access_log=None,
                print=lambda *_: None)


if __name__ == "__main__":
    main()
