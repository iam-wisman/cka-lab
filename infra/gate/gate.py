#!/usr/bin/env python3
"""helmyard-gate: the one piece of HelmYard that stays on.

A tiny page in an LXC container on Proxmox (infra/gate/install-gate.sh). Everything
else (the jump host with the console, the cluster VMs) can be off: the console shuts
it all down after a while without use, and this page starts it again.

  Start            boots the jump host; the cluster VMs start when a lab needs them
  Start + cluster  boots the jump host and the cluster VMs together
  Shut down        shuts the cluster VMs, then the jump host, down cleanly

Python standard library only. Configuration from the environment (/etc/helmyard-gate.env):
  PVE_URL, PVE_NODE, PVE_TOKEN   a Proxmox API token that may only see and power the lab VMs
  JUMP_VMID, NODE_VMIDS          the jump host, and the cluster VMs (space separated)
  CONSOLE_URL                    the console on the jump host, e.g. https://192.168.8.160/
  PASSWORD_HASH                  pbkdf2_sha256$<iterations>$<salt hex>$<hash hex> (the student password)
  PORT, CERT, KEY                listen port, TLS certificate and key (omit both for plain HTTP)
"""

import hashlib
import hmac
import http.server
import json
import os
import secrets
import ssl
import threading
import time
import urllib.parse
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
ENV = os.environ
JUMP = int(ENV.get("JUMP_VMID", "200"))
NODES = [int(x) for x in ENV.get("NODE_VMIDS", "201 202 203 204 205 206").split()]
SESSIONS: dict = {}
FAILED: dict = {}
LOCK = threading.Lock()
INSECURE = ssl.create_default_context()
INSECURE.check_hostname = False
INSECURE.verify_mode = ssl.CERT_NONE   # Proxmox's and the console's own certificates; LAN only


def pve(method: str, path: str, data: dict | None = None):
    body = urllib.parse.urlencode(data or {}).encode() if method == "POST" else None
    req = urllib.request.Request(f"{ENV['PVE_URL']}/api2/json/nodes/{ENV['PVE_NODE']}/qemu{path}", data=body, method=method,
                                 headers={"Authorization": f"PVEAPIToken={ENV['PVE_TOKEN']}"})
    with urllib.request.urlopen(req, context=INSECURE, timeout=8) as r:
        return json.load(r)["data"]


def status() -> dict:
    try:
        vms = {v["vmid"]: v.get("status") for v in pve("GET", "")}
        err = None
    except Exception as e:  # Proxmox unreachable or token wrong
        vms, err = {}, str(e)
    console = False
    if vms.get(JUMP) == "running" and ENV.get("CONSOLE_URL"):
        try:
            with urllib.request.urlopen(ENV["CONSOLE_URL"].rstrip("/") + "/api/health", context=INSECURE, timeout=2) as r:
                console = r.status == 200
        except Exception:
            pass
    return {"jump": vms.get(JUMP), "nodes": [vms.get(n) for n in NODES], "console": console,
            "console_url": ENV.get("CONSOLE_URL"), "error": err}


def start(with_cluster: bool):
    for vmid in [JUMP] + (NODES if with_cluster else []):
        try:
            if pve("GET", f"/{vmid}/status/current").get("status") != "running":
                pve("POST", f"/{vmid}/status/start")
        except Exception:
            pass


def stop():
    """Cluster VMs first, in parallel; then the jump host once they're down."""
    def run():
        for vmid in NODES:
            try:
                pve("POST", f"/{vmid}/status/shutdown", {"timeout": 180, "forceStop": 1})
            except Exception:
                pass
        for _ in range(100):
            try:
                if all(pve("GET", f"/{v}/status/current").get("status") != "running" for v in NODES):
                    break
            except Exception:
                pass
            time.sleep(3)
        try:
            pve("POST", f"/{JUMP}/status/shutdown", {"timeout": 180, "forceStop": 1})
        except Exception:
            pass
    threading.Thread(target=run, daemon=True).start()


def check_password(pw: str) -> bool:
    try:
        algo, iters, salt, want = ENV["PASSWORD_HASH"].split("$")
    except (KeyError, ValueError):
        return False
    got = hashlib.pbkdf2_hmac("sha256", pw.encode(), bytes.fromhex(salt), int(iters))
    return algo == "pbkdf2_sha256" and hmac.compare_digest(got.hex(), want)


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "helmyard-gate"
    sys_version = ""

    def log_message(self, *args):
        pass

    def send(self, code: int, body: bytes, ctype: str, extra: dict | None = None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Content-Security-Policy", "default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; img-src 'self' data:; frame-ancestors 'none'")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def json(self, code: int, obj, extra=None):
        self.send(code, json.dumps(obj).encode(), "application/json", extra)

    def authed(self) -> bool:
        for part in self.headers.get("Cookie", "").split(";"):
            k, _, v = part.strip().partition("=")
            if k == "gate" and SESSIONS.get(v, 0) > time.time():
                return True
        return False

    def do_GET(self):
        if self.path == "/":
            return self.send(200, (HERE / "index.html").read_bytes(), "text/html; charset=utf-8")
        if self.path in ("/mascot.png", "/favicon.svg"):
            f = HERE / self.path.lstrip("/")
            return self.send(200, f.read_bytes(), "image/png" if f.suffix == ".png" else "image/svg+xml")
        if self.path == "/api/status":
            if not self.authed():
                return self.json(401, {"error": "log in first"})
            return self.json(200, status())
        self.send(404, b"not found", "text/plain")

    def do_POST(self):
        origin = self.headers.get("Origin")
        if self.headers.get("X-Gate") != "1" or (origin and origin.split("://", 1)[-1] != self.headers.get("Host")):
            return self.json(403, {"error": "refused"})
        n = min(int(self.headers.get("Content-Length") or 0), 4096)
        try:
            body = json.loads(self.rfile.read(n) or b"{}")
        except ValueError:
            body = {}
        if self.path == "/api/login":
            ip = self.client_address[0]
            with LOCK:
                count, first = FAILED.get(ip, [0, time.time()])
                if count >= 8 and time.time() - first < 300:
                    return self.json(429, {"error": "too many attempts; wait five minutes"})
            if not check_password(str(body.get("password", ""))):
                time.sleep(1)
                with LOCK:
                    FAILED[ip] = [count + 1, first if time.time() - first < 300 else time.time()]
                return self.json(401, {"error": "wrong password"})
            FAILED.pop(ip, None)
            tok = secrets.token_urlsafe(32)
            SESSIONS[tok] = time.time() + 12 * 3600
            secure = "; Secure" if ENV.get("CERT") else ""
            return self.json(200, {"ok": True}, {"Set-Cookie": f"gate={tok}; HttpOnly; SameSite=Strict; Path=/{secure}"})
        if not self.authed():
            return self.json(401, {"error": "log in first"})
        if self.path == "/api/start":
            start(bool(body.get("cluster")))
            return self.json(200, {"ok": True})
        if self.path == "/api/stop":
            stop()
            return self.json(200, {"ok": True})
        self.json(404, {"error": "not found"})


def main():
    srv = http.server.ThreadingHTTPServer(("0.0.0.0", int(ENV.get("PORT", "443"))), Handler)
    if ENV.get("CERT"):
        ctx = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
        ctx.minimum_version = ssl.TLSVersion.TLSv1_2
        ctx.load_cert_chain(ENV["CERT"], ENV["KEY"])
        srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
