// Screenshots of the web console for the README, taken with headless Chrome over
// the DevTools protocol (no npm packages needed; Node 22+ for the built-in WebSocket).
//
//   CONSOLE_URL=http://localhost:8080 CONSOLE_PASSWORD=... node tools/web-screenshots.mjs [outdir]
//
// CONSOLE_URL is usually an SSH tunnel to the jump host. Shots are 1440x900 at 2x.

import { spawn } from "node:child_process";
import { mkdtempSync, writeFileSync, mkdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const BASE = process.env.CONSOLE_URL || "http://localhost:8080";
const PASSWORD = process.env.CONSOLE_PASSWORD;
const OUT = process.argv[2] || "docs/web";
const CHROME = process.env.CHROME || "google-chrome-stable";
if (!PASSWORD) { console.error("set CONSOLE_PASSWORD"); process.exit(2); }

const SHOTS = [
  { file: "overview.png", hash: "#/", theme: "dark" },
  // Typed into the shell at the capture width, so the replayed history doesn't wrap oddly.
  { file: "lab.png", hash: "#/lab/08", theme: "dark",
    type: `clear; for n in cp1 cp2 cp3 worker1 worker2; do ssh $n 'echo "$(hostname): $(nproc) vCPU, $(free -g | awk "/Mem/{print \\$2}") GiB, kernel $(uname -r)"' </dev/null; done; lab list | head -5` },
  { file: "results.png", hash: "#/lab/01/results", theme: "dark" },
  { file: "exam.png", hash: "#/exam/1/review", theme: "light" },
  { file: "cluster.png", hash: "#/cluster", theme: "light" },
];

const profile = mkdtempSync(join(tmpdir(), "cka-shots-"));
const chrome = spawn(CHROME, ["--headless=new", "--remote-debugging-port=9333", `--user-data-dir=${profile}`,
  "--hide-scrollbars", "--no-first-run", "about:blank"], { stdio: "ignore" });
const sleep = ms => new Promise(r => setTimeout(r, ms));

try {
  let target;
  for (let i = 0; i < 50 && !target; i++) {
    await sleep(200);
    target = await fetch("http://127.0.0.1:9333/json/list").then(r => r.json()).then(l => l.find(t => t.type === "page")).catch(() => null);
  }
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise(r => ws.addEventListener("open", r, { once: true }));
  let seq = 0;
  const pending = new Map();
  ws.addEventListener("message", e => {
    const m = JSON.parse(e.data);
    if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
  });
  const send = (method, params = {}) => new Promise((resolve, reject) => {
    const id = ++seq;
    pending.set(id, m => (m.error ? reject(new Error(`${method}: ${m.error.message}`)) : resolve(m.result)));
    ws.send(JSON.stringify({ id, method, params }));
  });
  const js = expr => send("Runtime.evaluate", { expression: expr, awaitPromise: true, returnByValue: true });

  await send("Page.enable");
  await send("Emulation.setDeviceMetricsOverride", { width: 1440, height: 900, deviceScaleFactor: 2, mobile: false });
  await send("Page.navigate", { url: BASE + "/" });
  await sleep(1500);
  await js(`fetch("/api/login", {method: "POST", headers: {"Content-Type": "application/json"}, body: JSON.stringify({password: ${JSON.stringify(PASSWORD)}})}).then(r => r.status)`);

  mkdirSync(OUT, { recursive: true });
  for (const shot of SHOTS) {
    await js(`localStorage.setItem("cka.theme", ${JSON.stringify(JSON.stringify(shot.theme))})`);
    await send("Page.navigate", { url: BASE + "/" + shot.hash });
    await sleep(500);
    await js("location.reload()");
    await sleep(4500);  // fonts, API calls, terminal replay
    if (shot.type) {
      await js(`Terms.paste(${JSON.stringify(shot.type)}); Terms.send(Terms.active, {t: "i", d: "\\r"})`);
      await sleep(5000);
    }
    const { data } = await send("Page.captureScreenshot", { format: "png" });
    writeFileSync(join(OUT, shot.file), Buffer.from(data, "base64"));
    console.log("wrote", join(OUT, shot.file));
  }
  ws.close();
} finally {
  chrome.kill();
  await sleep(300);
  rmSync(profile, { recursive: true, force: true });
}
