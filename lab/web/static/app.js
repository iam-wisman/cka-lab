/* HelmYard (Kubernetes Playgrounds) (the CKA lab web console): front end. Plain JS, no build step.
   Views: overview (#/), lab workspace (#/lab/<id>), mock exam (#/exam/<n>),
   cluster and snapshots (#/cluster). The terminal pane is created once and
   moved between workspaces so shells survive navigation. */
"use strict";

// --- helpers --------------------------------------------------------------------------

const $ = (sel, el = document) => el.querySelector(sel);
const $$ = (sel, el = document) => [...el.querySelectorAll(sel)];

function h(tag, attrs, ...kids) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v == null || v === false) continue;
    if (k.startsWith("on")) el.addEventListener(k.slice(2), v);
    else if (k === "class") el.className = v;
    else if (k === "style" && typeof v === "object") Object.assign(el.style, v);
    else el.setAttribute(k, v === true ? "" : v);
  }
  for (const kid of kids.flat(Infinity)) {
    if (kid == null || kid === false) continue;
    el.append(kid instanceof Node ? kid : document.createTextNode(String(kid)));
  }
  return el;
}

const store = {
  get(k, d) { try { const v = localStorage.getItem("cka." + k); return v == null ? d : JSON.parse(v); } catch { return d; } },
  set(k, v) { try { localStorage.setItem("cka." + k, JSON.stringify(v)); } catch { /* private mode */ } },
};

class ApiError extends Error { constructor(status, msg) { super(msg); this.status = status; } }

async function api(path, { method = "GET", body } = {}) {
  const opts = { method, headers: { "X-Lab": "1" }, credentials: "same-origin" };
  if (body !== undefined) { opts.headers["Content-Type"] = "application/json"; opts.body = JSON.stringify(body); }
  let r;
  try { r = await fetch("/api" + path, opts); }
  catch { throw new ApiError(0, "The jump host isn't answering."); }
  if (r.status === 401 && path !== "/login") { showLogin(); throw new ApiError(401, "Log in first."); }
  if (!r.ok) throw new ApiError(r.status, (await r.text()).trim() || r.statusText);
  return r.json();
}

function ago(when) {
  if (!when) return "";
  const t = typeof when === "number" ? when * 1000 : Date.parse(when);
  const s = Math.max(0, (Date.now() - t) / 1000);
  if (s < 50) return "just now";
  if (s < 3600) return `${Math.round(s / 60)} min ago`;
  if (s < 86400) return `${Math.round(s / 3600)} h ago`;
  return `${Math.round(s / 86400)} d ago`;
}

function clock(sec) {
  const neg = sec < 0; sec = Math.abs(Math.floor(sec));
  const hh = Math.floor(sec / 3600), mm = Math.floor(sec / 60) % 60, ss = sec % 60;
  return (neg ? "−" : "") + (hh ? `${hh}:${String(mm).padStart(2, "0")}` : String(mm)) + ":" + String(ss).padStart(2, "0");
}

function toast(msg, bad = false) {
  let box = $(".toasts");
  if (!box) { box = h("div", { class: "toasts" }); document.body.append(box); }
  const t = h("div", { class: "toast" + (bad ? " bad" : "") }, msg);
  box.append(t);
  setTimeout(() => t.remove(), bad ? 7000 : 3500);
}

function dialog({ title, body, confirm = "OK", cancel = "Cancel", danger = false, typed = null }) {
  return new Promise(resolve => {
    const field = typed ? h("input", { class: "field mono", placeholder: typed, autocomplete: "off", spellcheck: "false" }) : null;
    const ok = h("button", { class: "btn solid" + (danger ? " danger" : ""), disabled: !!typed }, confirm);
    const close = v => { scrim.remove(); document.removeEventListener("keydown", onKey); resolve(v); };
    const onKey = e => { if (e.key === "Escape") close(false); };
    const scrim = h("div", { class: "scrim", onmousedown: e => { if (e.target === scrim) close(false); } },
      h("div", { class: "dialog", role: "dialog", "aria-modal": "true" },
        h("h2", {}, title),
        h("div", { class: "body" }, body, field),
        h("div", { class: "foot" },
          cancel && h("button", { class: "btn", onclick: () => close(false) }, cancel), ok)));
    ok.onclick = () => close(true);
    if (field) {
      field.oninput = () => { ok.disabled = field.value !== typed; };
      field.onkeydown = e => { if (e.key === "Enter" && !ok.disabled) close(true); };
    }
    document.addEventListener("keydown", onKey);
    document.body.append(scrim);
    (field || ok).focus();
  });
}

const p = (...kids) => h("p", {}, ...kids);
const code = t => h("code", {}, t);

// --- curriculum ------------------------------------------------------------------------

const DOMAINS = [
  { key: "Trouble", name: "Troubleshooting", weight: 30 },
  { key: "Arch", name: "Cluster Architecture, Installation & Configuration", short: "Architecture", weight: 25 },
  { key: "Network", name: "Services & Networking", short: "Networking", weight: 20 },
  { key: "Workloads", name: "Workloads & Scheduling", short: "Workloads", weight: 15 },
  { key: "Storage", name: "Storage", weight: 10 },
];
const domainOf = key => DOMAINS.find(d => d.key === key || d.name === key || (key === "Troubleshooting" && d.key === "Trouble")) || { name: key, short: key, weight: 0 };
const shortDomain = key => { const d = domainOf(key); return d.short || d.name; };
const labPassed = lab => lab.best === 1;
// Grades outlive `lab reset`; the cluster doesn't. A pass counts as "in the cluster" only if
// it came after the last reset (lab up checks the cluster itself either way).
const passedSinceReset = l => !!l.result && l.result.pass === l.result.total && Date.parse(l.result.at) / 1000 > (S.overview?.last_reset || 0);
const labsByNum = () => Object.fromEntries((S.overview?.labs || []).map(l => [l.num, l]));

// The labs `needs` relies on (followed through their own needs) that aren't passed or built
// yet: what `lab up` would build. A lab that's done vouches for everything it needed.
function missingPrereqs(needs) {
  const byNum = labsByNum(), out = new Set(), seen = new Set(), queue = [...needs];
  while (queue.length) {
    const n = queue.shift();
    if (seen.has(n)) continue;
    seen.add(n);
    const l = byNum[n];
    if (!l || l.provisioned || passedSinceReset(l)) continue;
    out.add(n);
    queue.push(...l.needs);
  }
  return [...out].sort();
}

// Ask before building prerequisites; resolves true when it's fine to go ahead.
function confirmSpinUp(what, missing) {
  if (!missing.length) return Promise.resolve(true);
  const list = h("b", { class: "mono" }, missing.join(", "));
  if (!S.overview?.can_spin_up)
    return dialog({ title: `${what} builds on unfinished labs`, confirm: "Start anyway",
      body: [p("It assumes labs ", list, " are done. Spinning them up needs the reference solutions, which aren't installed on this jump host."),
        p("Do those labs first, or start anyway if you've built the same thing yourself.")] });
  return dialog({ title: `Spin up ${what.toLowerCase()}?`, confirm: "Spin up",
    body: [p("It builds on labs ", list, ", which aren't done yet."),
      p("Spin up builds them first with the reference solutions, the same way the verified lab chain does, then sets this up. Their commands run out of sight, so nothing is given away; a lab whose grader already passes is skipped."),
      p("From a bare cluster this can take half an hour or more. The output panel shows progress.")] });
}

// --- markdown ------------------------------------------------------------------------------

function renderMarkdown(md) {
  const div = h("div", { class: "md" });
  div.innerHTML = DOMPurify.sanitize(marked.parse(md, { gfm: true, breaks: false }));
  for (const a of $$("a[href]", div)) {
    if (!/^https?:/i.test(a.getAttribute("href"))) continue;
    a.target = "_blank"; a.rel = "noopener noreferrer";
    const li = a.closest("li");
    if (li && li.textContent.trim() === a.textContent.trim()) {
      try { a.append(h("span", { class: "host" }, new URL(a.href).hostname.replace(/^www\./, ""))); } catch { /* bad URL */ }
    }
  }
  for (const table of $$("table", div)) {
    const wrap = h("div", { class: "table" });
    table.replaceWith(wrap); wrap.append(table);
  }
  for (const pre of $$("pre", div)) {
    const text = pre.textContent.replace(/\n$/, "");
    const tools = h("div", { class: "code-tools" },
      h("button", { title: "Type into the active terminal (doesn't press Enter)", onclick: () => Terms.paste(text) }, "paste"),
      h("button", { onclick: e => copyText(text, e.target) }, "copy"));
    const box = h("div", { class: "code" });
    pre.replaceWith(box); box.append(pre, tools);
  }
  return div;
}

// Task files open with a metadata paragraph (domain, curriculum, time, where to work)
// that the page header already shows. Remove it; keep "Work on" / "Namespace" as facts.
function splitTaskHeader(md) {
  const m = md.match(/^# .*\n\n((?:.+\n)+?)\n/);
  if (!m || !/\*\*Domain:\*\*/.test(m[1])) return { md, extras: [] };
  const tail = m[1].replace(/\n/g, " ").split(/\*\*Suggested time:\*\*/)[1] || "";
  const extras = tail.split(" · ").slice(1).map(x => x.match(/\*\*(.+?):\*\*\s*(.*)/)).filter(Boolean)
    .filter(x => !["Start with", "Needs"].includes(x[1])).map(x => [x[1], x[2].trim()]);
  return { md: md.replace(m[1] + "\n", ""), extras };
}

function inlineMd(text) {
  const span = h("span", {});
  span.innerHTML = DOMPurify.sanitize(marked.parseInline(text));
  return span;
}

async function copyText(text, btn) {
  try { await navigator.clipboard.writeText(text); }
  catch {
    const ta = h("textarea", { style: { position: "fixed", opacity: "0" } }, text);
    document.body.append(ta); ta.select(); document.execCommand("copy"); ta.remove();
  }
  if (btn) { const old = btn.textContent; btn.textContent = "copied"; setTimeout(() => { btn.textContent = old; }, 1200); }
}

// ANSI colour codes from the lab CLI -> spans. Only SGR bold/dim and 31-34 occur.
function ansiToNodes(text) {
  const out = document.createDocumentFragment();
  let cls = new Set();
  text = text.replace(/\r(?!\n)/g, "\n").replace(/\x1b\[[0-9;?]*[A-La-ln-z]/g, "");
  for (const part of text.split(/(\x1b\[[0-9;]*m)/)) {
    const m = part.match(/^\x1b\[([0-9;]*)m$/);
    if (m) {
      for (const c of (m[1] || "0").split(";").map(Number)) {
        if (c === 0) cls = new Set();
        else if (c === 1) cls.add("a-b");
        else if (c === 2) cls.add("a-d");
        else if (c >= 30 && c <= 37) { for (const k of [...cls]) if (/^a-3/.test(k)) cls.delete(k); cls.add("a-" + c); }
        else if (c === 39) for (const k of [...cls]) if (/^a-3/.test(k)) cls.delete(k);
      }
    } else if (part) {
      out.append(cls.size ? h("span", { class: [...cls].join(" ") }, part) : document.createTextNode(part));
    }
  }
  return out;
}

// --- app state -----------------------------------------------------------------------------

const S = {
  overview: null,
  cluster: null,
  jobs: { current: null, recent: [] },
  timers: [],       // intervals owned by the current view
  view: null,       // cleanup function of the current view
};

async function loadOverview() { S.overview = await api("/overview"); return S.overview; }

function everyWhileHere(fn, ms) { const t = setInterval(fn, ms); S.timers.push(t); return t; }

// --- jobs: `lab` commands run by the server, output streamed over SSE -----------------------------

const Jobs = {
  listeners: new Set(),
  streams: new Map(),   // job id -> {text, info}

  on(fn) { this.listeners.add(fn); return () => this.listeners.delete(fn); },
  emit(ev) { for (const fn of [...this.listeners]) fn(ev); renderJobPill(); },

  async start(action, target, arg = "") {
    try {
      const info = await api("/jobs", { method: "POST", body: { action, target, arg } });
      S.jobs.current = info;
      this.follow(info);
      return info;
    } catch (e) { toast(e.message, true); return null; }
  },

  follow(info) {
    if (this.streams.has(info.id) && this.streams.get(info.id).es) return;
    const st = this.streams.get(info.id) || { text: "", info };
    this.streams.set(info.id, st);
    this.emit({ type: "start", info });
    const es = new EventSource(`/api/jobs/${info.id}/stream`);
    st.es = es; st.text = "";
    es.addEventListener("out", e => { st.text += JSON.parse(e.data); this.emit({ type: "out", info, text: JSON.parse(e.data) }); });
    es.addEventListener("end", e => {
      es.close(); st.es = null;
      st.info = JSON.parse(e.data);
      if (S.jobs.current && S.jobs.current.id === info.id) S.jobs.current = null;
      S.jobs.recent.unshift(st.info);
      this.emit({ type: "end", info: st.info });
    });
    es.onerror = () => {
      // The server went away mid-job (e.g. a reset rolled back the jump host).
      if (es.readyState === EventSource.CLOSED) { st.es = null; }
    };
  },

  // Resolves with the finished job's info.
  wait(id) {
    return new Promise(resolve => {
      const off = this.on(ev => { if (ev.type === "end" && ev.info.id === id) { off(); resolve(ev.info); } });
    });
  },

  async sync() {
    try {
      S.jobs = await api("/jobs");
      if (S.jobs.current) this.follow(S.jobs.current);
      renderJobPill();
    } catch { /* not logged in yet */ }
  },
};

// One live view of a job's output, used by the drawers.
function jobDrawer({ filter = () => true, onEnd } = {}) {
  const pre = h("pre", {});
  const state = h("span", { class: "state" });
  const label = h("span", { class: "grow" });
  const el = h("div", { class: "drawer hidden" },
    h("div", { class: "drawer-head" }, state, label,
      h("button", { title: "Collapse", onclick: () => el.classList.toggle("min") }, "▁"),
      h("button", { title: "Close", onclick: () => el.classList.add("hidden") }, "×")),
    pre);
  let shown = null;
  const show = info => {
    shown = info.id;
    const st = Jobs.streams.get(info.id);
    pre.replaceChildren(ansiToNodes(st ? st.text : ""));
    el.classList.remove("hidden", "min");
    paint(info);
  };
  const paint = info => {
    label.textContent = info.label;
    if (info.ended == null) { state.className = "state run"; state.textContent = "running"; }
    else if (info.code === 0) { state.className = "state ok"; state.textContent = "done"; }
    else { state.className = "state bad"; state.textContent = `exit ${info.code}`; }
  };
  const off = Jobs.on(ev => {
    if (ev.type === "start" && filter(ev.info)) show(ev.info);
    if (ev.info.id !== shown) return;
    if (ev.type === "out") {
      const stick = pre.scrollTop + pre.clientHeight >= pre.scrollHeight - 30;
      pre.append(ansiToNodes(ev.text));
      if (stick) pre.scrollTop = pre.scrollHeight;
    }
    if (ev.type === "end") {
      paint(ev.info);
      if (ev.info.action.endsWith("-check") && ev.info.code !== -1) el.classList.add("min");  // results are on the page
      onEnd && onEnd(ev.info);
    }
  });
  if (S.jobs.current && filter(S.jobs.current)) show(S.jobs.current);
  el.dispose = off;
  return el;
}

function renderJobPill() {
  const slot = $("#job-slot");
  if (!slot) return;
  const cur = S.jobs.current;
  slot.replaceChildren(cur ? h("span", { class: "pill job", title: "Show output", onclick: () => showJobDialog(cur) },
    h("span", { class: "bar" }), h("span", { class: "label" }, cur.label)) : "");
}

function showJobDialog(info) {
  const drawer = jobDrawer({ filter: j => j.id === info.id });
  drawer.style.maxHeight = "60vh";
  dialog({ title: info.label, body: drawer, confirm: "Close", cancel: null }).then(() => drawer.dispose());
  const st = Jobs.streams.get(info.id);
  drawer.classList.remove("hidden");
  $("pre", drawer).replaceChildren(ansiToNodes(st ? st.text : ""));
}

// --- terminals ------------------------------------------------------------------------------------

const TERM_THEME = {
  background: "#303030", foreground: "#f1f3f5", cursor: "#8fb0ff", cursorAccent: "#303030",
  selectionBackground: "#326ce580",
  black: "#403f4c", red: "#ff7b72", green: "#7ee2a8", yellow: "#f2cc60", blue: "#7aa2f7",
  magenta: "#d2a8ff", cyan: "#79d4cf", white: "#dee2e6",
  brightBlack: "#868e96", brightRed: "#ffa198", brightGreen: "#a5f0c5", brightYellow: "#f8e3a1",
  brightBlue: "#a5c0ff", brightMagenta: "#e2c5ff", brightCyan: "#c0e0de", brightWhite: "#ffffff",
};

const Terms = {
  pane: null, host: null, bar: null,
  tabs: [], active: null,
  ready: null,
  size: store.get("termFont", 14),

  build() {
    if (this.pane) return;
    this.host = h("div", { class: "term-host" });
    this.bar = h("div", { class: "term-bar" });
    this.pane = h("div", { class: "term-pane" }, this.bar, this.host);
    new ResizeObserver(() => this.fit()).observe(this.host);
  },

  mount(container) {
    this.build();
    container.append(this.pane);
    if (!this.ready) this.ready = this.init();
    requestAnimationFrame(() => this.fit());
    return this.pane;
  },

  async init() {
    await Promise.all(["400", "700"].map(w => document.fonts.load(`${w} ${this.size}px "JetBrainsMono Nerd Font Mono"`))).catch(() => {});
    let list = await api("/terms");
    if (!list.length) list = [await api("/terms", { method: "POST", body: {} })];
    for (const t of list) this.add(t);
    this.activate(this.tabs[0]);
  },

  add({ sid, title }) {
    const el = h("div", { class: "xt hidden" });
    this.host.append(el);
    const term = new Terminal({
      fontFamily: '"JetBrainsMono Nerd Font Mono", ui-monospace, monospace', fontSize: this.size, lineHeight: 1.18,
      cursorBlink: true, cursorStyle: "bar", scrollback: 5000, allowProposedApi: true,
      theme: TERM_THEME, macOptionIsMeta: true, rightClickSelectsWord: true,
    });
    const fit = new FitAddon.FitAddon();
    term.loadAddon(fit);
    term.loadAddon(new WebLinksAddon.WebLinksAddon((e, uri) => window.open(uri, "_blank", "noopener")));
    term.loadAddon(new Unicode11Addon.Unicode11Addon());
    term.unicode.activeVersion = "11";
    term.open(el);
    term.attachCustomKeyEventHandler(e => {
      if (e.type === "keydown" && e.ctrlKey && e.shiftKey && e.code === "KeyC") {
        if (term.hasSelection()) copyText(term.getSelection());
        e.preventDefault();
        return false;
      }
      if (e.ctrlKey && e.shiftKey && e.code === "KeyV") return false;  // browser paste event handles it
      return true;
    });
    const tab = { sid, title, term, fit, el, ws: null, retry: 0, dead: false, note: null };
    term.onData(d => this.send(tab, { t: "i", d }));
    term.onResize(({ cols, rows }) => this.send(tab, { t: "r", c: cols, r: rows }));
    this.tabs.push(tab);
    this.connect(tab);
    this.renderBar();
    return tab;
  },

  send(tab, msg) { if (tab.ws && tab.ws.readyState === 1) tab.ws.send(JSON.stringify(msg)); },

  connect(tab) {
    const ws = new WebSocket(`${location.protocol === "https:" ? "wss" : "ws"}://${location.host}/api/terms/${tab.sid}/ws`);
    ws.binaryType = "arraybuffer";
    tab.ws = ws;
    ws.onopen = () => {
      tab.retry = 0;
      tab.term.reset();          // the server replays recent output on connect
      this.setNote(tab, null);
      this.send(tab, { t: "r", c: tab.term.cols, r: tab.term.rows });
    };
    ws.onmessage = e => tab.term.write(new Uint8Array(e.data));
    ws.onclose = e => {
      if (tab.dead) return;
      if (e.code === 4000) { this.remove(tab, true); return; }      // the shell exited
      this.setNote(tab, "reconnecting");
      tab.retry = Math.min(tab.retry + 1, 6);
      setTimeout(async () => {
        if (tab.dead) return;
        const list = await api("/terms").catch(() => null);
        if (list && !list.some(t => t.sid === tab.sid)) { this.remove(tab, true); return; }
        this.connect(tab);
      }, 500 * 2 ** tab.retry);
    };
  },

  setNote(tab, text) {
    tab.note && tab.note.remove(); tab.note = null;
    if (text) { tab.note = h("div", { class: "term-note" }, text); tab.el.append(tab.note); }
  },

  async create() {
    try { this.activate(this.add(await api("/terms", { method: "POST", body: {} }))); }
    catch (e) { toast(e.message, true); }
  },

  async close(tab) {
    tab.dead = true;
    await api(`/terms/${tab.sid}`, { method: "DELETE" }).catch(() => {});
    this.remove(tab, false);
  },

  remove(tab, exited) {
    tab.dead = true;
    try { tab.ws && tab.ws.close(); } catch { /* already closed */ }
    tab.term.dispose(); tab.el.remove();
    this.tabs = this.tabs.filter(t => t !== tab);
    if (this.active === tab) this.active = null;
    if (!this.tabs.length) { if (exited) toast("Shell exited; opened a new one."); this.create(); }
    else { if (!this.active) this.activate(this.tabs[this.tabs.length - 1]); this.renderBar(); }
  },

  activate(tab) {
    if (!tab) return;
    this.active = tab;
    for (const t of this.tabs) t.el.classList.toggle("hidden", t !== tab);
    this.renderBar();
    requestAnimationFrame(() => { this.fit(); tab.term.focus(); });
  },

  fit() {
    const t = this.active;
    if (!t || !this.pane || !this.pane.isConnected || !this.host.clientWidth) return;
    try { t.fit.fit(); } catch { /* not visible yet */ }
  },

  zoom(delta) {
    this.size = Math.max(10, Math.min(24, this.size + delta));
    store.set("termFont", this.size);
    for (const t of this.tabs) t.term.options.fontSize = this.size;
    this.fit();
  },

  paste(text) {
    if (!this.active) { toast("No terminal open"); return; }
    this.active.term.paste(text);
    this.active.term.focus();
  },

  // Edit a tab's name in place. Enter or leaving the field saves it on the server (so it
  // survives a reload and shows in other windows); Escape cancels.
  rename(tab, label) {
    if (!label || label.querySelector("input")) return;
    const input = h("input", { class: "tab-name", value: tab.title, maxlength: 24, spellcheck: false, "aria-label": "Tab name" });
    let done = false;
    const finish = async save => {
      if (done) return;
      done = true;
      const title = input.value.trim().replace(/\s+/g, " ");
      if (save && title && title !== tab.title) {
        try { tab.title = (await api(`/terms/${tab.sid}`, { method: "PATCH", body: { title } })).title; }
        catch (e) { toast(`Couldn't rename: ${e.message}`, true); }
      }
      this.renderBar();
      tab.term.focus();
    };
    input.onkeydown = e => {
      e.stopPropagation();
      if (e.key === "Enter") { e.preventDefault(); finish(true); }
      else if (e.key === "Escape") { e.preventDefault(); finish(false); }
    };
    input.onblur = () => finish(true);
    input.onclick = e => e.stopPropagation();
    label.replaceChildren(input);
    input.focus(); input.select();
  },

  renderBar() {
    if (!this.bar) return;
    this.bar.replaceChildren(
      ...this.tabs.map(t => h("div", { class: "term-tab" + (t === this.active ? " on" : ""), onclick: () => this.activate(t) },
        h("span", { class: "name", title: "Double-click to rename", ondblclick: e => { e.stopPropagation(); this.rename(t, e.currentTarget); } }, t.title),
        h("button", { class: "ren", title: "Rename this tab", "aria-label": "Rename", onclick: e => { e.stopPropagation(); this.rename(t, e.currentTarget.previousSibling); } }, "✎"),
        h("button", { class: "x", title: "Close this shell", "aria-label": "Close", onclick: e => { e.stopPropagation(); this.close(t); } }, "×"))),
      h("button", { title: "New shell on jump", onclick: () => this.create() }, "+ new"),
      h("span", { class: "grow" }),
      h("span", { class: "hint" }, "student@jump"),
      h("button", { title: "Smaller text", onclick: () => this.zoom(-1) }, "A−"),
      h("button", { title: "Larger text", onclick: () => this.zoom(1) }, "A+"));
  },
};

// Draggable divider between the document and the terminal.
function gutter(doc, key) {
  const g = h("div", { class: "gutter", title: "Drag to resize" });
  const apply = frac => { doc.style.width = `${Math.round(frac * 1000) / 10}%`; };
  apply(store.get(key, 0.42));
  g.onpointerdown = e => {
    g.setPointerCapture(e.pointerId); g.classList.add("drag");
    const parent = doc.parentElement.getBoundingClientRect();
    g.onpointermove = ev => apply(Math.min(0.72, Math.max(0.24, (ev.clientX - parent.left) / parent.width)));
    g.onpointerup = () => {
      g.classList.remove("drag"); g.onpointermove = g.onpointerup = null;
      store.set(key, doc.getBoundingClientRect().width / parent.width);
      Terms.fit();
    };
  };
  return g;
}

// --- graphics ----------------------------------------------------------------------------------

function svgEl(markup) {
  const t = document.createElement("template");
  t.innerHTML = markup.trim();
  return t.content.firstElementChild;
}

const polar = (cx, cy, r, i, n, rot = -90) => {
  const a = (rot + (360 / n) * i) * Math.PI / 180;
  return [cx + r * Math.cos(a), cy + r * Math.sin(a)];
};

// Line icons, drawn on a 24px grid.
const ICONS = {
  lab: '<path d="M9.5 3h5M10.5 3v6.2L5.3 18a2 2 0 0 0 1.7 3h10a2 2 0 0 0 1.7-3l-5.2-8.8V3"/><path d="M7.6 14.5h8.8"/>',
  exam: '<path d="M8 21h8M12 16.5V21M7 4h10v5a5 5 0 0 1-10 0z"/><path d="M17 6h3v1.5A3.5 3.5 0 0 1 16.6 11M7 6H4v1.5A3.5 3.5 0 0 0 7.4 11"/>',
  clock: '<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>',
  search: '<circle cx="11" cy="11" r="6.5"/><path d="m20 20-4.2-4.2"/>',
  filter: '<path d="M4 5h16l-6.2 7.4V19l-3.6 2v-8.6z"/>',
  server: '<rect x="4" y="4" width="16" height="7" rx="2"/><rect x="4" y="13" width="16" height="7" rx="2"/><path d="M8 7.5h.01M8 16.5h.01"/>',
  chart: '<path d="M4 20V4M4 20h16"/><path d="m8 15 3.5-4 3 2.5L19 8"/>',
  arrow: '<path d="M5 12h14M13 6l6 6-6 6"/>',
};
const icon = name => svgEl(`<svg class="ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[name]}</svg>`);

// Readiness ring: one arc per exam domain, sized by its exam weight. Each arc's track is a
// pale tint of the domain colour, filled in full colour as that domain's labs are passed.
function domainRing(domains) {
  // Round caps stick out by half the stroke width, so each dash is drawn that much shorter.
  const c = 110, r = 92, C = 2 * Math.PI * r, gap = 7, w = 16;
  let start = 0;
  const arc = (len, color, extra = "") => `<circle cx="${c}" cy="${c}" r="${r}" fill="none" stroke="${color}" stroke-width="${w}" stroke-linecap="round" stroke-dasharray="${len.toFixed(2)} ${C}" stroke-dashoffset="${(-start - w / 2).toFixed(2)}"${extra}/>`;
  const arcs = domains.map((d, i) => {
    const seg = C * d.weight / 100, len = Math.max(0, seg - gap - w);
    const out = arc(len, `color-mix(in srgb, var(--d${i + 1}) 22%, var(--panel))`) + (d.frac > 0 ? arc(len * d.frac, `var(--d${i + 1})`) : "");
    start += seg;
    return out;
  }).join("");
  return svgEl(`<svg viewBox="0 0 220 220" role="img" aria-label="Exam readiness by domain"><g transform="rotate(-90 ${c} ${c})">${arcs}</g></svg>`);
}

// A bar per day: how often something was graded. Today is the last bar.
function activityBars(days) {
  const max = Math.max(1, ...days.map(d => d.n));
  return h("div", { class: "spark-bars", role: "img", "aria-label": "Gradings per day, last 14 days" },
    days.map((d, i) => h("i", { class: (d.n ? "on" : "") + (i === days.length - 1 ? " today" : ""),
      style: { height: `${d.n ? 25 + (d.n / max) * 75 : 22}%` }, title: `${new Date(d.day + "T12:00").toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" })}: ${d.n} graded` })));
}

// --- chrome ------------------------------------------------------------------------------------

function renderTop() {
  const top = h("header", { class: "top" },
    h("a", { class: "brand", href: "#/", title: "HelmYard: overview" }, h("img", { class: "brand-mark", src: "/static/brand/helmyard-mark-reverse.svg", alt: "" }),
      h("span", { class: "brand-text" }, h("span", { class: "brand-name" }, "Helm", h("b", {}, "Yard")), h("small", {}, "Kubernetes Playgrounds"))),
    h("nav", { class: "nav" },
      h("a", { href: "#/kubestronaut", "data-r": "kubestronaut" }, "Kubestronaut"),
      h("a", { href: "#/", "data-r": "labs" }, "Labs"),
      h("a", { href: "#/drills", "data-r": "drills" }, "Drills"),
      h("a", { href: "#/exams", "data-r": "exams" }, "Exams"),
      h("a", { href: "#/cluster", "data-r": "cluster" }, "Cluster")),
    h("span", { class: "spacer" }),
    h("div", { class: "tools" },
      h("span", { id: "job-slot" }),
      h("a", { class: "pill", id: "health", href: "#/cluster", title: "Kubernetes nodes Ready" }, h("span", { class: "dot" }), h("span", { class: "label" }, "cluster")),
      h("button", { class: "btn quiet sm", onclick: logout }, "Log out")));
  return top;
}

function markNav(route) {
  for (const a of $$(".nav a")) a.classList.toggle("on", a.dataset.r === route);
}

function renderHealth() {
  const el = $("#health");
  if (!el) return;
  const c = S.cluster;
  let cls = "", text = "checking";
  if (c) {
    if (c.nodes && c.nodes.length) {
      const ready = c.nodes.filter(n => n.ready).length;
      cls = ready === c.nodes.length ? "ok" : "bad";
      text = `${ready}/${c.nodes.length} ready`;
    } else {
      const up = c.vms.filter(v => v.status === "running").length;
      cls = "warn"; text = c.pve ? `no cluster · ${up}/${c.vms.length} VMs up` : "no cluster";
    }
  }
  el.replaceChildren(h("span", { class: "dot " + cls }), h("span", { class: "label" }, text));
  renderClusterBits();
}

// Live cluster widgets on the dashboard (if it's showing).
function renderClusterBits() {
  const c = S.cluster, strip = $("#vm-strip"), tile = $("#tile-cluster");
  if (strip && c) {
    const byName = Object.fromEntries((c.nodes || []).map(n => [n.name, n]));
    const role = vm => vm.name === "jump" ? "jump host" : vm.name === "nfs" ? "NFS server" : c.nodes && c.nodes.length ? "not joined" : "no cluster yet";
    strip.replaceChildren(
      h("div", {}, h("span", { class: "p" }, "$ "), "lab status"),
      ...c.vms.map(vm => {
        const node = byName[vm.name], st = vm.status || "unknown";
        return h("div", {}, h("span", { class: "n" }, vm.name.padEnd(9)), h("span", { class: st === "running" ? "ok" : "bad" }, st.padEnd(9)),
          node ? h("span", { class: node.ready ? "ok" : "bad" }, node.ready ? "Ready" : "NotReady", h("span", { class: "m" }, node.version ? ` ${node.version}` : ""))
            : h("span", { class: "m" }, role(vm)));
      }),
      h("div", {}, h("span", { class: "p" }, "$ "), h("span", { class: "cursor" })));
  }
  if (tile && c) {
    const nodes = c.nodes || [];
    const ready = nodes.filter(n => n.ready).length;
    const up = c.vms.filter(v => v.status === "running").length;
    tile.replaceChildren(
      h("div", { class: "label-sm" }, icon("server"), "Cluster"),
      h("div", { class: "num" }, nodes.length ? ready : "—", nodes.length ? h("small", {}, ` / ${nodes.length}`) : null),
      h("div", { class: "note" }, nodes.length ? `nodes Ready · ${nodes[0].version || ""}` : `no cluster yet · ${up}/${c.vms.length} VMs running`),
      h("div", { class: "meter" }, h("i", { style: { width: `${nodes.length ? (ready / nodes.length) * 100 : 0}%` } })));
  }
}

async function pollCluster(fresh = false) {
  try { S.cluster = await api("/cluster" + (fresh ? "?fresh=1" : "")); renderHealth(); }
  catch { /* shown elsewhere */ }
  return S.cluster;
}

async function logout() {
  await api("/logout", { method: "POST" }).catch(() => {});
  location.hash = "#/";
  location.reload();
}

// --- login ---------------------------------------------------------------------------------------

function showLogin() {
  if ($(".login")) return;
  cleanupView();
  const pw = h("input", { class: "field", type: "password", id: "pw", autocomplete: "current-password", required: true });
  const err = h("div", { class: "err" });
  const btn = h("button", { class: "btn solid", type: "submit" }, "Sign in");
  const form = h("form", {
    onsubmit: async e => {
      e.preventDefault(); btn.disabled = true; err.textContent = "";
      try {
        const r = await fetch("/api/login", { method: "POST", headers: { "Content-Type": "application/json", "X-Lab": "1" }, body: JSON.stringify({ password: pw.value }) });
        if (!r.ok) throw new Error((await r.text()) || "Login failed");
        boot();
      } catch (x) { err.textContent = x.message; btn.disabled = false; pw.select(); }
    },
  },
    h("div", { class: "login-brand" }, h("img", { src: "/static/brand/helmyard-mark.svg", alt: "" }),
      h("div", { class: "brand-name" }, "Helm", h("b", {}, "Yard")), h("div", { class: "tagline" }, "Kubernetes Playgrounds")),
    h("h1", {}, "Sign in"),
    h("p", {}, "Sign in with the student password to open the labs, the mock exams and a shell on the jump host."),
    h("label", { for: "pw" }, "Password"), pw, btn, err);
  form.classList.add("hud");
  form.querySelector("label").className = "label-sm";
  $("#app").replaceChildren(h("main", { class: "login" }, form));
  pw.focus();
}

// --- router ---------------------------------------------------------------------------------------

function cleanupView() {
  for (const t of S.timers) clearInterval(t);
  S.timers = [];
  if (S.view) { try { S.view(); } catch { /* ignore */ } }
  S.view = null;
}

async function route() {
  cleanupView();
  const parts = location.hash.replace(/^#\/?/, "").split("/").filter(Boolean);
  const main = $("#main");
  if (!main) return;
  try {
    if (!parts.length || parts[0] === "labs") { markNav("labs"); await viewOverview(main); }
    else if (parts[0] === "exams") { markNav("exams"); await viewOverview(main, "exams"); }
    else if (parts[0] === "lab") { markNav("labs"); await viewLab(main, parts[1], parts[2]); }
    else if (parts[0] === "exam") { markNav("exams"); await viewExam(main, parts[1], parts[2]); }
    else if (parts[0] === "cluster") { markNav("cluster"); await viewCluster(main); }
    else if (parts[0] === "kubestronaut") { markNav("kubestronaut"); await viewKubestronaut(main); }
    else if (parts[0] === "track") { markNav("kubestronaut"); await viewTrack(main, parts[1]); }
    else if (parts[0] === "quiz" && parts[1] === "s") { markNav("kubestronaut"); await viewSitting(main, parts[2], parts[3]); }
    else if (parts[0] === "quiz") { markNav("kubestronaut"); await viewQuizTrack(main, parts[1]); }
    else if (parts[0] === "drills") { markNav("drills"); await viewDrills(main); }
    else if (parts[0] === "drill") { markNav("drills"); await viewDrill(main, parts[1]); }
    else location.hash = "#/";
  } catch (e) {
    if (e.status === 401) return;
    main.replaceChildren(h("div", { class: "page" }, h("div", { class: "wrap" },
      h("div", { class: "empty" }, h("b", {}, "Couldn't load this page. "), e.message))));
  }
}

// --- overview --------------------------------------------------------------------------------------

// One catalogue card per lab: a header strip, the brief, and a status footer.
function labCard(l, next) {
  const i = DOMAINS.indexOf(domainOf(l.domain));
  const r = l.result;
  const state = labPassed(l) ? "passed" : r ? "graded" : l.started_at ? "started" : l.provisioned ? "built" : "new";
  const href = `#/lab/${l.id}`;
  const pct = Math.round((l.best || 0) * 100);
  return h("article", { class: `lab-card hud ${state}` },
    h("header", {}, icon("lab"), h("span", {}, shortDomain(l.domain)),
      h("i", { class: "dom", style: { background: i < 0 ? "var(--muted)" : `var(--d${i + 1})` } }),
      h("span", { class: "grow" }), l.minutes ? h("span", { class: "min" }, icon("clock"), `${l.minutes} min`) : null),
    h("div", { class: "body" },
      h("h3", {}, h("a", { href }, h("span", { class: "no" }, l.num), l.title)),
      h("p", { class: "cur" }, l.curriculum.join(" · ")),
      h("div", { class: "tags" },
        h("span", { class: "tag" }, l.id.replace(/^\d+-/, "")),
        l.phases.length ? h("span", { class: "tag" }, "breaks things") : null,
        l.needs.length ? h("span", { class: "tag" }, `needs ${l.needs.join(", ")}`) : null)),
    h("footer", {},
      h("div", { class: "prog" },
        h("span", { class: "label-sm" }, { passed: "Passed", graded: "Last check", started: "Started", built: "Status", new: "Status" }[state]),
        h("span", { class: "val" }, state === "passed" ? `all ${r ? r.total : ""} checks pass` : state === "graded" ? `${r.pass}/${r.total} checks · ${ago(r.at)}`
          : state === "started" ? ago(l.started_at) : state === "built" ? "built by spin up" : "not started"),
        h("span", { class: "bar" }, h("i", { style: { width: `${pct}%` } }))),
      h("a", { class: "btn" + (l === next ? " solid" : ""), href }, { passed: "Review", graded: "Continue", started: "Continue", built: "Start lab", new: "Start lab" }[state])));
}

async function viewOverview(main, focus) {
  const data = await loadOverview();
  const labs = data.labs;
  const passed = labs.filter(labPassed).length;
  const perDomain = DOMAINS.map(d => {
    const ls = labs.filter(l => domainOf(l.domain) === d);
    const frac = ls.length ? ls.reduce((a, l) => a + (l.best || 0), 0) / ls.length : 0;
    return { ...d, labs: ls, frac, done: ls.filter(labPassed).length };
  });
  const coverage = Math.round(perDomain.reduce((a, d) => a + d.weight * d.frac, 0));
  const examBest = Math.max(-1, ...data.exams.flatMap(e => e.history.map(x => x.score)));
  const graded = labs.filter(l => l.result);
  const checksPass = graded.reduce((a, l) => a + l.result.pass, 0), checksTotal = graded.reduce((a, l) => a + l.result.total, 0);
  const next = labs.find(l => !labPassed(l));
  const activeDays = (data.activity || []).filter(d => d.n).length;

  let filter = store.get("labFilter", "all");
  let query = "";
  const grid = h("div", { class: "lab-grid" });
  const filters = h("div", { class: "filters" });
  const search = h("input", { class: "search-input", type: "search", placeholder: "Search labs: etcd, gateway, PVC…", "aria-label": "Search labs",
    oninput: e => { query = e.target.value.trim().toLowerCase(); drawCards(); } });
  const drawCards = () => {
    filters.replaceChildren(...[["all", "All"], ["todo", "Not passed"], ...DOMAINS.map(d => [d.key, d.short || d.name])].map(([k, label]) =>
      h("button", { class: filter === k ? "on" : "", onclick: () => { filter = k; store.set("labFilter", k); drawCards(); } }, label)));
    const shown = labs.filter(l => (filter === "all" || (filter === "todo" ? !labPassed(l) : domainOf(l.domain).key === filter))
      && (!query || `${l.num} ${l.id} ${l.title} ${l.curriculum.join(" ")}`.toLowerCase().includes(query)));
    grid.replaceChildren(...shown.map(l => labCard(l, next)));
    if (!shown.length) grid.append(h("div", { class: "empty" }, "No lab matches."));
  };
  drawCards();

  const examsSection = h("section", { id: "exams" },
    h("div", { class: "section-head" }, h("h2", {}, icon("exam"), "Mock exams"),
      h("span", { class: "sub" }, "120 minutes · weighted tasks · pass mark 66 %")),
    h("div", { class: "lab-grid" }, data.exams.map(e => {
      const running = e.deadline && !e.submitted_at && e.deadline * 1000 > Date.now();
      const best = e.history.length ? Math.max(...e.history.map(x => x.score)) : null;
      return h("article", { class: "lab-card exam-card hud" + (best != null && best >= 66 ? " passed" : "") },
        h("header", {}, icon("exam"), h("span", {}, "Mock exam ", h("b", {}, e.n)), h("span", { class: "grow" }),
          h("span", { class: "min" }, icon("clock"), `${e.minutes} min`)),
        h("div", { class: "body" },
          h("h3", {}, h("a", { href: `#/exam/${e.n}` }, e.title.replace(/^CKA m/, "M").replace(/^CKA /, ""))),
          h("p", { class: "cur" }, `${e.tasks} tasks across all five exam domains, timed and weighted like the real exam.`),
          h("div", { class: "tags" },
            running ? h("span", { class: "tag mark" }, "in progress") : null,
            e.history.length ? e.history.slice(-5).map(x => h("span", { class: "tag " + (x.passed ? "pass" : "fail") }, `${x.score}%`))
              : !running && h("span", { class: "tag" }, "not attempted"))),
        h("footer", {},
          h("div", { class: "prog" }, h("span", { class: "label-sm" }, "Best score"),
            h("span", { class: "val" }, best == null ? "—" : `${best} %`),
            h("span", { class: "bar" }, h("i", { style: { width: `${best || 0}%` } }), h("b", { class: "mark", title: "pass mark" }))),
          h("a", { class: "btn" + (running ? " solid" : ""), href: `#/exam/${e.n}` }, running ? "Resume" : e.history.length ? "Retake" : "Start exam")));
    })));

  const term = h("div", { class: "term-card" },
    h("div", { class: "term-card-bar" }, h("i"), h("i"), h("i"), h("span", {}, "student@jump")),
    h("div", { class: "term-card-body", id: "vm-strip" }, h("div", {}, h("span", { class: "p" }, "$ "), "lab status")));

  main.replaceChildren(h("div", { class: "page" }, h("div", { class: "wrap" },
    h("section", { class: "hero" },
      h("div", { class: "hero-text" },
        h("div", { class: "kicker" }, "Certified Kubernetes Administrator (CKA) · Kubernetes v1.35"),
        h("h1", {}, "Hands-on practice for the CKA exam"),
        h("p", { class: "lead" }, "HelmYard is a set of ", h("b", {}, "31 labs"), " and ", h("b", {}, "two timed mock exams"),
          " that follow the CKA curriculum. You work on a seven-VM cluster that you build yourself, and every task is graded check by check. As in the exam, there are no hints."),
        h("div", { class: "cta" },
          next ? h("a", { class: "btn solid lg", href: `#/lab/${next.id}` }, next.started_at ? `Resume lab ${next.num}` : `Start lab ${next.num}`, icon("arrow"))
            : h("a", { class: "btn solid lg", href: "#/exams" }, "Take a mock exam", icon("arrow")),
          h("a", { class: "btn lg", href: "#/exams" }, "Mock exams"))),
      term),
    h("div", { class: "section-head" }, h("h2", {}, icon("chart"), "Your progress")),
    h("section", { class: "progress" },
      h("div", { class: "readiness hud" },
        h("div", { class: "card-head" }, h("div", {}, h("h3", {}, "Exam readiness"), h("p", {}, "Labs passed per exam domain, weighted like the exam")),
          h("span", { class: "chip" }, "CKA v1.35")),
        h("div", { class: "readiness-body" },
          h("div", { class: "ring" }, domainRing(perDomain),
            h("div", { class: "ring-center" }, h("b", {}, coverage, h("small", {}, "%")), h("span", {}, "ready"))),
          h("div", { class: "domains" }, perDomain.map((d, i) => h("div", { class: "domain" },
            h("div", { class: "row" }, h("span", { class: "sw", style: { background: `var(--d${i + 1})` } }), h("span", { class: "name" }, d.short || d.name),
              h("span", { class: "grow" }), h("span", { class: "n" }, `${d.done}/${d.labs.length} labs`), h("span", { class: "w" }, `${d.weight}%`)),
            h("div", { class: "track" }, h("i", { style: { width: `${Math.round(d.frac * 100)}%`, background: `var(--d${i + 1})` } }))))))),
      next ? h("div", { class: "upnext hud" },
        h("div", { class: "card-head" }, h("div", {}, h("h3", {}, next.started_at ? "Continue where you left off" : "Up next"), h("p", {}, `Lab ${next.num} of ${labs.length}`))),
        h("div", { class: "upnext-body" },
          h("div", { class: "meta" }, h("span", { class: "sw", style: { background: `var(--d${DOMAINS.indexOf(domainOf(next.domain)) + 1})` } }), shortDomain(next.domain),
            next.minutes ? [h("span", { class: "dot-sep" }, "·"), `${next.minutes} min`] : null),
          h("h4", {}, next.title),
          h("p", { class: "cur" }, next.curriculum.join(" · "))),
        h("div", { class: "upnext-actions" },
          h("a", { class: "btn solid", href: `#/lab/${next.id}` }, next.started_at ? "Continue lab" : "Start lab", icon("arrow")),
          h("a", { class: "btn quiet", href: "#labs", onclick: e => { e.preventDefault(); $("#labs").scrollIntoView({ behavior: "smooth" }); } }, "All labs")))
        : h("div", { class: "upnext hud" },
          h("div", { class: "card-head" }, h("div", {}, h("h3", {}, "All labs passed"), h("p", {}, "Time for a timed mock exam"))),
          h("div", { class: "upnext-actions" }, h("a", { class: "btn solid", href: "#/exams" }, "Mock exams", icon("arrow")))),
      h("div", { class: "kpi hud" },
        h("div", { class: "kpi-head" }, h("span", { class: "kpi-ico" }, icon("lab")), "Labs passed"),
        h("div", { class: "kpi-num" }, passed, h("small", {}, ` of ${labs.length}`)),
        h("div", { class: "cells", title: "One square per lab, coloured by domain once passed" }, labs.map(l => {
          const i = DOMAINS.indexOf(domainOf(l.domain));
          return h("i", { class: labPassed(l) ? "on" : l.best ? "part" : "", style: labPassed(l) ? { background: `var(--d${i + 1})` } : {}, title: `Lab ${l.num}: ${l.title}` });
        }))),
      h("div", { class: "kpi hud" },
        h("div", { class: "kpi-head" }, h("span", { class: "kpi-ico" }, icon("chart")), "Checks passing"),
        h("div", { class: "kpi-num" }, checksTotal ? Math.round(checksPass * 100 / checksTotal) : "—", checksTotal ? h("small", {}, "%") : null),
        h("div", { class: "kpi-note" }, checksTotal ? `${checksPass} of ${checksTotal} in ${graded.length} graded lab${graded.length === 1 ? "" : "s"}` : "No lab graded yet"),
        h("div", { class: "meter" }, h("i", { style: { width: `${checksTotal ? (checksPass / checksTotal) * 100 : 0}%` } }))),
      h("div", { class: "kpi hud" },
        h("div", { class: "kpi-head" }, h("span", { class: "kpi-ico" }, icon("exam")), "Best mock exam"),
        h("div", { class: "kpi-num", style: { color: examBest >= 66 ? "var(--pass)" : "" } }, examBest < 0 ? "—" : examBest, examBest < 0 ? null : h("small", {}, "%")),
        h("div", { class: "kpi-note" }, examBest < 0 ? "Not attempted yet" : examBest >= 66 ? "Above the 66% pass mark" : "The pass mark is 66%"),
        h("div", { class: "meter" }, h("i", { style: { width: `${Math.max(0, examBest)}%`, background: examBest >= 66 ? "var(--pass)" : "var(--k8s)" } }), h("span", { class: "mark", style: { left: "66%" }, title: "pass mark" }))),
      h("div", { class: "kpi hud" },
        h("div", { class: "kpi-head" }, h("span", { class: "kpi-ico" }, icon("clock")), "Activity"),
        h("div", { class: "kpi-num" }, activeDays, h("small", {}, ` day${activeDays === 1 ? "" : "s"}`)),
        h("div", { class: "kpi-note" }, "with a lab or exam graded, last 14 days"),
        activityBars(data.activity || []))),
    h("section", { id: "labs" },
      h("div", { class: "section-head" }, h("h2", {}, icon("lab"), "Labs"), h("span", { class: "sub" }, `${passed} of ${labs.length} passed`)),
      h("div", { class: "filterbar hud" }, h("label", { class: "search" }, icon("search"), search), h("span", { class: "fl" }, icon("filter")), filters),
      grid),
    examsSection)));
  renderClusterBits();
  if (focus === "exams") examsSection.scrollIntoView();
}

// --- lab workspace ------------------------------------------------------------------------------------

function resultsView(result, history) {
  if (!result) return h("div", { class: "empty" }, h("b", {}, "Not graded yet. "), "Press ", h("b", {}, "Check"), " (or run ", h("code", { class: "mono" }, "lab check"), " in the terminal) whenever you want feedback. It's safe to check as often as you like.");
  const full = result.pass === result.total;
  const box = h("div", {},
    h("div", { class: "results-head" },
      h("span", { class: "big" + (full ? " pass" : "") }, `${result.pass}/${result.total}`),
      h("span", { class: "muted" }, `checks passed · graded ${ago(result.at)}`)));
  if (history && history.length > 1) {
    box.append(h("div", { class: "spark", title: "Score of each check, oldest first" },
      history.map(x => h("i", { class: x.pass === x.total ? "full" : "", style: { height: `${Math.max(6, (x.pass / x.total) * 100)}%` } }))));
  }
  const checks = result.checks || result.failed.map(d => ({ section: "", desc: d, ok: false, detail: "" }));
  const list = h("div", {});
  let failedOnly = checks.length > 20 && !full && store.get("failedOnly", false);
  const draw = () => {
    const counts = {};
    for (const c of checks) { const k = c.section; counts[k] = counts[k] || [0, 0]; counts[k][1]++; if (c.ok) counts[k][0]++; }
    const els = [];
    let section = null;
    for (const c of checks) {
      if (failedOnly && c.ok) continue;
      if (c.section !== section) {
        section = c.section;
        if (section) els.push(h("div", { class: "check-section" }, section, h("span", { class: "mono", style: { marginLeft: "8px", letterSpacing: 0 } }, `${counts[section][0]}/${counts[section][1]}`)));
      }
      els.push(h("div", { class: "check " + (c.ok ? "ok" : "no") },
        h("span", { class: "v" }, c.ok ? "PASS" : "FAIL"),
        h("span", {}, c.desc, c.detail ? h("span", { class: "detail" }, c.detail) : null)));
    }
    list.replaceChildren(...els);
  };
  if (checks.length > 20 && !full) {
    const box2 = h("input", { type: "checkbox", checked: failedOnly, onchange: e => { failedOnly = e.target.checked; store.set("failedOnly", failedOnly); draw(); } });
    box.append(h("label", { class: "checkline", style: { margin: "4px 0 0" } }, box2, h("span", {}, "Only show failed checks")));
  }
  draw();
  box.append(list);
  if (!result.checks) box.append(p(h("span", { class: "muted" }, "Only failed checks are listed for this older result; check again for the full list.")));
  return box;
}

function notesEditor(key, placeholder) {
  const ta = h("textarea", { class: "notes", placeholder, spellcheck: "false" });
  const saved = h("div", { class: "saved" }, "");
  let timer = null;
  api(`/notes/${key}`).then(r => { ta.value = r.value || ""; saved.textContent = r.at ? `Saved ${ago(r.at)} · stored on the jump host` : "Stored on the jump host"; });
  ta.oninput = () => {
    clearTimeout(timer); saved.textContent = "Saving…";
    timer = setTimeout(async () => {
      try { await api(`/notes/${key}`, { method: "PUT", body: { value: ta.value } }); saved.textContent = "Saved"; }
      catch (e) { saved.textContent = `Not saved: ${e.message}`; }
    }, 600);
  };
  return h("div", {}, ta, saved);
}

async function viewLab(main, id, tabName) {
  let lab = await api(`/labs/${id}`);
  if (!S.overview) await loadOverview().catch(() => {});
  let byNum = labsByNum();
  let tab = tabName || "task";
  let solutionMd = null;
  const taskHead = splitTaskHeader(lab.markdown);

  const doc = h("section", { class: "doc" });
  const body = h("div", { class: "doc-body" });
  const tabsEl = h("div", { class: "tabs", role: "tablist" });
  const facts = h("div", { class: "facts" });
  const actions = h("div", { class: "actions" });
  const drawer = jobDrawer({
    filter: j => j.target === lab.id || j.target === lab.num,
    onEnd: async info => {
      lab = await api(`/labs/${lab.id}`);
      await loadOverview().catch(() => {});
      byNum = labsByNum();
      syncStartLabel();
      if (info.action === "lab-check") {
        const r = lab.result;
        if (r) toast(r.pass === r.total ? `Lab ${lab.num}: all ${r.total} checks pass` : `Lab ${lab.num}: ${r.pass}/${r.total} checks pass`);
        select("results");
      } else { drawFacts(); drawTabs(); }
    },
  });

  const busy = () => !!S.jobs.current;
  // Start = `lab up`: builds missing prerequisite labs first (after asking), then runs setup.
  const startBtn = h("button", { class: "btn", onclick: async () => {
    if (await confirmSpinUp(`Lab ${lab.num}`, missingPrereqs(lab.needs))) Jobs.start(S.overview?.can_spin_up ? "lab-up" : "lab-start", lab.id);
  } });
  const syncStartLabel = () => {
    const n = missingPrereqs(lab.needs).length;
    startBtn.textContent = n ? "Spin up" : "Start";
    startBtn.title = n ? `Builds the ${n} unfinished lab${n > 1 ? "s" : ""} this one needs, then starts it` : "Run this lab's setup";
  };
  syncStartLabel();
  const checkBtn = h("button", { class: "btn solid", onclick: () => Jobs.start("lab-check", lab.id) }, "Check");
  const cleanBtn = h("button", {
    class: "btn", disabled: !lab.has_cleanup,
    title: lab.has_cleanup ? "Remove what this lab left behind" : "Nothing to clean up: this lab built part of the cluster",
    onclick: async () => {
      if (await dialog({
        title: `Clean up lab ${lab.num}?`,
        body: [p("Runs the commands listed under ", h("b", {}, "Cleaning up"), " at the end of the task. Things later labs need are kept."),
          p("Only do this after ", h("b", {}, "Check"), " passes, or when you want to start over.")],
        confirm: "Clean up",
      })) Jobs.start("lab-cleanup", lab.id);
    },
  }, "Clean up");
  const phaseBtns = lab.phases.map(ph => h("button", {
    class: "btn", onclick: async () => {
      if (await dialog({ title: `Run the "${ph}" phase?`, body: p(`This is the part of lab ${lab.num} that breaks things on purpose. Do the earlier tasks first.`), confirm: `Start ${ph}`, danger: true }))
        Jobs.start("lab-start", lab.id, ph);
    },
  }, `Start: ${ph}`));
  actions.append(...[lab.has_setup || !lab.phases.length ? startBtn : null, ...phaseBtns, checkBtn, cleanBtn].filter(Boolean));
  const syncButtons = () => { for (const b of [startBtn, checkBtn, cleanBtn, ...phaseBtns]) if (b !== cleanBtn || lab.has_cleanup) b.disabled = busy(); };
  syncButtons();
  const offJobs = Jobs.on(syncButtons);

  const drawFacts = () => {
    const els = [];
    if (lab.minutes) els.push(h("span", {}, h("span", { class: "mono" }, `${lab.minutes} min`), " suggested"));
    if (lab.started_at) {
      const mins = Math.round((Date.now() - Date.parse(lab.started_at)) / 60000);
      els.push(h("span", { title: `started ${lab.started_at}` }, "started ", h("span", { class: "mono" }, mins < 120 ? `${mins} min` : ago(lab.started_at).replace(" ago", "")), " ago"));
    }
    if (lab.needs.length) els.push(h("span", {}, "needs ", lab.needs.map((n, i) => [i ? ", " : "",
      h("a", { href: `#/lab/${byNum[n]?.id || n}`, class: "mono", style: { color: byNum[n] && !labPassed(byNum[n]) && !byNum[n].provisioned ? "var(--warn)" : "" },
        title: !byNum[n] ? "" : labPassed(byNum[n]) ? "passed" : byNum[n].provisioned ? "built by spin up" : "not done yet" }, `lab ${n}`)])));
    for (const [k, v] of taskHead.extras) els.push(h("span", { class: "md-inline" }, `${k.toLowerCase()} `, inlineMd(v)));
    if (lab.result) els.push(h("span", {}, "last check ", h("span", { class: "mono" }, `${lab.result.pass}/${lab.result.total}`), ` · ${ago(lab.result.at)}`));
    facts.replaceChildren(...els);
  };

  const drawTabs = () => {
    const r = lab.result;
    const items = [["task", "Task"], ["results", "Results", r ? h("span", { class: "count " + (r.pass === r.total ? "pass" : "fail") }, `${r.pass}/${r.total}`) : null], ["notes", "Notes"]];
    if (lab.has_solution) items.push(["solution", "Solution"]);
    tabsEl.replaceChildren(...items.map(([k, label, extra]) => h("button", { class: tab === k ? "on" : "", role: "tab", onclick: () => select(k) }, label, extra)));
  };

  const select = async k => {
    if (k === "solution" && !solutionMd) {
      const ok = store.get(`sol-${lab.id}`, false) || await dialog({
        title: "Look at the solution?",
        body: [p("Struggling with a task is where most of the learning happens. In the exam you'll only have the docs."),
          p("Try the References links first. If you're still stuck, go ahead.")],
        confirm: "Show the solution", cancel: "Keep trying",
      });
      if (!ok) return;
      store.set(`sol-${lab.id}`, true);
      try { solutionMd = (await api(`/labs/${lab.id}/solution`)).markdown; } catch (e) { toast(e.message, true); return; }
    }
    tab = k;
    history.replaceState(null, "", `#/lab/${lab.id}${k === "task" ? "" : "/" + k}`);
    drawTabs();
    body.scrollTop = 0;
    if (k === "task") body.replaceChildren(renderMarkdown(taskHead.md));
    else if (k === "results") body.replaceChildren(resultsView(lab.result, lab.history));
    else if (k === "notes") body.replaceChildren(notesEditor(`lab-${lab.num}`, `Notes for lab ${lab.num}: commands that worked, gotchas, doc pages worth bookmarking…`));
    else if (k === "solution") body.replaceChildren(renderMarkdown(solutionMd));
  };

  doc.append(
    h("div", { class: "doc-head" },
      h("div", { class: "eyebrow" }, h("a", { href: "#/" }, "← labs"), h("span", {}, "/"), h("span", { class: "id" }, `lab ${lab.num}`), h("span", {}, "·"), h("span", {}, shortDomain(lab.domain))),
      h("h1", {}, lab.title), facts, actions),
    tabsEl, body, drawer);

  const ws = h("div", { class: "workspace" }, doc, gutter(doc, "docWidth"));
  main.replaceChildren(ws);
  Terms.mount(ws);
  drawFacts();
  await select(tab === "solution" && !store.get(`sol-${lab.id}`, false) ? "task" : tab);
  everyWhileHere(drawFacts, 30000);
  S.view = () => { offJobs(); drawer.dispose(); };
}

// --- mock exams ----------------------------------------------------------------------------------------

async function viewExam(main, n, mode) {
  let exam = await api(`/exams/${n}`);
  const skew = exam.now * 1000 - Date.now();
  const now = () => (Date.now() + skew) / 1000;
  const running = exam.deadline && !exam.submitted_at;
  if (mode === "review" || (!running && exam.deadline && exam.result)) {
    if (mode !== "review") return viewExamResults(main, exam);
  }
  if (!exam.deadline) return viewExamBriefing(main, exam);
  if (!running && mode !== "review") return viewExamResults(main, exam);

  // The exam workspace (running, or reviewing a graded sitting).
  const review = !running;
  const tasks = exam.task_list;
  const flagsKey = `exam-${n}-marks`;
  let marks = { deadline: exam.deadline, flags: [], seen: [], time: {} };
  try {
    const r = await api(`/notes/${flagsKey}`);
    if (r.value && r.value.deadline === exam.deadline) marks = r.value;
  } catch { /* fresh */ }
  marks.time ||= {};
  // Time on each task: counted while the task is open and this tab is visible, saved with
  // the flags, and shown against the task's share of the clock in the results.
  let shownAt = now();
  const account = () => {
    if (review) return;
    const t = tasks[idx], dt = now() - shownAt;
    shownAt = now();
    if (t && dt > 0 && dt < 3600 && document.visibilityState === "visible") marks.time[t.id] = Math.round((marks.time[t.id] || 0) + dt);
  };
  const onVis = () => { if (document.visibilityState === "visible") shownAt = now(); else { account(); saveMarks(); } };
  document.addEventListener("visibilitychange", onVis);
  const saveMarks = () => api(`/notes/${flagsKey}`, { method: "PUT", body: { value: marks } }).catch(() => {});
  let idx = Math.min(tasks.length - 1, Math.max(0, store.get(`exam-${n}-idx`, 0)));
  let tab = "q";

  const doc = h("section", { class: "doc" });
  const nav = h("div", { class: "navgrid" });
  const body = h("div", { class: "doc-body" });
  const tabsEl = h("div", { class: "tabs" });
  const clockEl = h("div", { class: "clock" });
  const drawer = jobDrawer({
    filter: j => j.target === String(n),
    onEnd: info => { if (info.action === "exam-check") { location.hash = `#/exam/${n}`; route(); } },
  });

  const frac = t => t.result && t.result.total ? t.result.pass / t.result.total : null;
  const drawNav = () => nav.replaceChildren(...tasks.map((t, i) => {
    const f = review ? frac(t) : null;
    const cls = [i === idx ? "on" : "", marks.flags.includes(t.id) ? "flag" : "", marks.seen.includes(t.id) ? "seen" : "",
      f == null ? "" : f === 1 ? "ok" : f > 0 ? "part" : "zero"].join(" ");
    return h("button", { class: cls, title: `${t.title} (${t.weight}%)`, onclick: () => go(i) }, i + 1, h("small", {}, `${t.weight}%`));
  }));
  const drawTabs = () => tabsEl.replaceChildren(
    h("button", { class: tab === "q" ? "on" : "", onclick: () => { tab = "q"; draw(); } }, `Task ${idx + 1}`),
    h("button", { class: tab === "pad" ? "on" : "", onclick: () => { tab = "pad"; draw(); } }, "Notepad"));
  const draw = () => {
    const t = tasks[idx];
    drawNav(); drawTabs();
    if (tab === "pad") { body.replaceChildren(notesEditor(`exam-${n}-notepad`, "Scratch notes, like the notepad in the real exam.")); return; }
    const flagged = marks.flags.includes(t.id);
    body.replaceChildren(...[
      // Like the real exam: every task starts by switching to its context.
      h("div", { class: "ctxbar" }, h("span", { class: "label-sm" }, "Context"), h("code", { class: "mono" }, `kubectl config use-context ${t.context}`),
        h("button", { class: "btn sm", title: "Type it into the terminal (doesn't press Enter)", onclick: () => Terms.paste(`kubectl config use-context ${t.context}`) }, "Paste")),
      renderMarkdown(t.markdown),
      review && t.result ? h("div", {}, h("div", { class: "check-section" }, "Grading"), resultsView(t.result)) : null,
      h("div", { class: "qfoot" },
        h("button", { class: "btn", disabled: idx === 0, onclick: () => go(idx - 1) }, "← Previous"),
        review ? null : h("button", { class: "btn" + (flagged ? " solid" : ""), onclick: () => toggleFlag(t) }, flagged ? "Flagged" : "Flag for review"),
        h("span", { class: "grow" }),
        h("button", { class: "btn", disabled: idx === tasks.length - 1, onclick: () => go(idx + 1) }, "Next →"))].filter(Boolean));
    body.scrollTop = 0;
  };
  const go = i => {
    account();
    idx = i; store.set(`exam-${n}-idx`, i); tab = "q";
    if (!review && !marks.seen.includes(tasks[i].id)) { marks.seen.push(tasks[i].id); saveMarks(); }
    draw();
  };
  const toggleFlag = t => {
    marks.flags = marks.flags.includes(t.id) ? marks.flags.filter(x => x !== t.id) : [...marks.flags, t.id];
    saveMarks(); draw();
  };

  const submit = async (auto = false) => {
    if (!auto) {
      const unseen = tasks.filter(t => !marks.seen.includes(t.id)).length;
      const ok = await dialog({
        title: "Hand in and grade?",
        body: [p("Every task is graded now, check by check, weighted like the real exam."),
          marks.flags.length ? p(`You flagged ${marks.flags.length} task${marks.flags.length > 1 ? "s" : ""} for review.`) : null,
          unseen ? p(`${unseen} task${unseen > 1 ? "s" : ""} not opened yet.`) : null],
        confirm: "Hand in",
      });
      if (!ok) return;
    }
    account(); await saveMarks();
    await api(`/exams/${n}/submit`, { method: "POST" }).catch(() => {});
    Jobs.start("exam-check", String(n));
  };

  let autoSubmitted = false, ticks = 0;
  const tick = () => {
    if (!review && ++ticks % 30 === 0) { account(); saveMarks(); }
    if (review) {
      const score = exam.result ? `${exam.result.score}%` : "graded";
      clockEl.replaceChildren(h("span", { class: "t" }, score), h("span", { class: "muted" }, "handed in · review"));
      return;
    }
    const left = exam.deadline - now();
    clockEl.className = "clock" + (left < 600 ? " low" : "");
    clockEl.replaceChildren(h("span", { class: "t" }, clock(left)), h("span", { class: "muted" }, left > 0 ? "left" : "over time"));
    if (left <= 0 && !autoSubmitted && !S.jobs.current) {
      autoSubmitted = true;
      toast("Time is up. Grading your exam.");
      submit(true);
    }
  };

  doc.append(
    h("div", { class: "doc-head" },
      h("div", { class: "eyebrow" }, h("a", { href: "#/exams" }, "← exams"), h("span", {}, "/"), h("span", { class: "id" }, `mock exam ${n}`)),
      h("div", { style: { display: "flex", alignItems: "center", gap: "14px", marginTop: "10px" } }, clockEl, h("span", { style: { flex: 1 } }),
        review ? h("a", { class: "btn", href: `#/exam/${n}` }, "Results")
          : h("button", { class: "btn solid", onclick: () => submit(false) }, "Hand in")),
      nav),
    tabsEl, body, drawer);
  const ws = h("div", { class: "workspace" }, doc, gutter(doc, "examDocWidth"));
  main.replaceChildren(ws);
  Terms.mount(ws);
  go(idx);
  tick();
  everyWhileHere(tick, 1000);
  S.view = () => { account(); saveMarks(); document.removeEventListener("visibilitychange", onVis); drawer.dispose(); };
}

const mins = s => s < 60 ? `${Math.round(s)}s` : `${Math.round(s / 60)}m`;

function viewExamBriefing(main, exam) {
  const n = exam.n;
  const snapBox = h("input", { type: "checkbox", id: "snap", checked: true });
  const startBtn = h("button", { class: "btn solid" }, "Start the exam");
  const drawer = jobDrawer({ filter: j => j.target === String(n) || j.target === `before-exam${n}` });
  drawer.style.marginTop = "16px";
  startBtn.onclick = async () => {
    if (!S.overview) await loadOverview().catch(() => {});
    const missing = missingPrereqs(exam.needs || []);
    if (!(await confirmSpinUp(`Mock exam ${n}`, missing))) return;
    const ok = await dialog({
      title: `Start mock exam ${n}?`,
      body: [p("Setting up the tasks takes a few minutes; some of them break the cluster on purpose. The 120-minute clock starts when setup finishes."),
        snapBox.checked ? p("First the cluster is snapshotted as ", code(`before-exam${n}`), ", which stops the nodes for about three minutes.") : null],
      confirm: "Start",
    });
    if (!ok) return;
    startBtn.disabled = true;
    if (missing.length && S.overview?.can_spin_up) {   // build what the exam assumes before the snapshot
      const j = await Jobs.start("exam-prep", String(n));
      if (!j) { startBtn.disabled = false; return; }
      if ((await Jobs.wait(j.id)).code !== 0) { toast("Spinning up the prerequisite labs failed; see the output.", true); startBtn.disabled = false; return; }
      loadOverview().catch(() => {});
    }
    if (snapBox.checked) {
      const j = await Jobs.start("snapshot", `before-exam${n}`);
      if (!j) { startBtn.disabled = false; return; }
      const done = await Jobs.wait(j.id);
      if (done.code !== 0) { toast("The snapshot failed; the exam wasn't started.", true); startBtn.disabled = false; return; }
      toast("Waiting for the nodes to come back…");
      for (let i = 0; i < 40; i++) {           // the nodes are rebooting after the snapshot
        const c = await pollCluster(true);
        if (c && c.nodes && c.nodes.length && c.nodes.every(x => x.ready)) break;
        await new Promise(r => setTimeout(r, 6000));
      }
    }
    const j = await Jobs.start("exam-start", String(n));
    if (!j) { startBtn.disabled = false; return; }
    const done = await Jobs.wait(j.id);
    if (done.code === 0) { store.set(`exam-${n}-idx`, 0); route(); }
    else { toast("Exam setup failed; see the output.", true); startBtn.disabled = false; }
  };
  const busy = () => { startBtn.disabled = !!S.jobs.current; };
  busy();
  const off = Jobs.on(busy);
  main.replaceChildren(h("div", { class: "page" }, h("div", { class: "wrap" },
    h("div", { class: "eyebrow" }, h("a", { href: "#/exams" }, "← exams"), h("span", {}, "/"), h("span", { class: "id" }, `mock exam ${n}`)),
    h("h1", { class: "page-title" }, exam.title.replace(/^CKA m/, "M").replace(/^CKA /, "")),
    h("div", { class: "briefing" },
      h("div", { class: "hud" }, renderMarkdown(exam.readme)),
      h("aside", { class: "side hud" },
        h("h3", {}, "Before you begin"),
        h("div", { class: "facts", style: { marginBottom: "10px" } },
          h("span", { class: "mono" }, `${exam.task_list.length} tasks`), h("span", { class: "mono" }, `${exam.minutes} min`), h("span", { class: "mono" }, `pass ${exam.pass_mark}%`)),
        h("label", { class: "checkline", for: "snap" }, snapBox,
          h("span", {}, "Snapshot the cluster first as ", code(`before-exam${n}`), ". Recommended: afterwards one reset undoes everything the exam broke.")),
        h("div", { class: "checkline" }, h("span", { class: "muted" }, "The exam opens in a workspace with the tasks on the left and your terminal on the right. Docs links open in new tabs, as in the real exam.")),
        startBtn,
        exam.history.length ? h("div", { style: { marginTop: "22px" } }, h("div", { class: "check-section" }, "Earlier sittings"),
          exam.history.slice().reverse().map(x => h("div", { class: "check " + (x.passed ? "ok" : "no") },
            h("span", { class: "v" }, `${x.score}%`), h("span", { class: "muted" }, new Date(x.at).toLocaleString())))) : null,
        drawer)))));
  S.view = () => { off(); drawer.dispose(); };
}

async function viewExamResults(main, exam) {
  const n = exam.n;
  const r = exam.result;
  const rows = [];
  let time = {};
  try { const m = (await api(`/notes/exam-${n}-marks`)).value; if (m && m.deadline === exam.deadline) time = m.time || {}; } catch { /* none */ }
  const spent = Object.values(time).reduce((a, b) => a + b, 0);
  for (const t of exam.task_list) {
    const f = t.result && t.result.total ? t.result.pass / t.result.total : 0;
    const detail = h("tr", { class: "hidden" }, h("td", { colspan: 7 }, resultsView(t.result)));
    // Its fair share of the clock: weight × exam length.
    const budget = t.weight / 100 * exam.minutes * 60, used = time[t.id] || 0;
    rows.push(h("tr", { class: "clickable", onclick: () => detail.classList.toggle("hidden") },
      h("td", { class: "n" }, t.id.slice(0, 2)),
      h("td", {}, t.title),
      h("td", { class: "muted" }, shortDomain(t.domain)),
      h("td", { class: "n" }, t.result ? `${t.result.pass}/${t.result.total}` : "—"),
      h("td", { class: "n" }, `${t.weight}%`),
      h("td", { class: "n", title: `Budget ${mins(budget)} (its weight's share of ${exam.minutes} min)`, style: { color: used > budget * 1.5 ? "var(--fail)" : used > budget ? "var(--warn)" : "" } },
        used ? `${mins(used)} / ${mins(budget)}` : "—"),
      h("td", { class: "n", style: { color: f === 1 ? "var(--pass)" : f === 0 ? "var(--fail)" : "" } }, `${(t.weight * f).toFixed(1)}%`)), detail);
  }
  const drawer = jobDrawer({ filter: j => j.target === String(n), onEnd: () => route() });
  const busy = () => !!S.jobs.current;
  main.replaceChildren(h("div", { class: "page" }, h("div", { class: "wrap" },
    h("div", { class: "eyebrow" }, h("a", { href: "#/exams" }, "← exams"), h("span", {}, "/"), h("span", { class: "id" }, `mock exam ${n}`)),
    h("section", { class: "masthead hud", style: { marginTop: "14px" } },
      h("div", {}, h("h1", {}, r ? (r.passed ? "Passed." : "Not this time.") : "Graded."),
        h("p", {}, r ? `Pass mark ${r.pass_mark}%. Graded ${ago(r.at)}. Click a task to see which checks failed.` : "")),
      h("div", {}, h("div", { class: "stat-label" }, "Score"), h("div", { class: "stat", style: { color: r && r.passed ? "var(--pass)" : "var(--fail)" } }, r ? r.score : "—", h("small", {}, " %"))),
      h("div", {}, h("div", { class: "stat-label" }, "Tasks fully solved"), h("div", { class: "stat" },
        exam.task_list.filter(t => t.result && t.result.pass === t.result.total).length, h("small", {}, ` / ${exam.task_list.length}`))),
      h("div", {}, h("div", { class: "stat-label" }, "Time on tasks"), h("div", { class: "stat" }, spent ? Math.round(spent / 60) : "—", spent ? h("small", {}, ` / ${exam.minutes} min`) : null)),
      h("div", {}, h("div", { class: "stat-label" }, "Sittings"), h("div", { class: "stat" }, exam.history.length))),
    h("div", { class: "actions", style: { marginTop: "20px" } },
      h("a", { class: "btn", href: `#/exam/${n}/review` }, "Review the tasks"),
      h("button", { class: "btn", disabled: busy(), onclick: () => Jobs.start("exam-check", String(n)) }, "Grade again"),
      h("button", {
        class: "btn", disabled: busy(), onclick: async () => {
          if (await dialog({ title: `Clean up mock exam ${n}?`, body: [p("Deletes the exam's namespaces and files and clears its timer, so you can sit it again."), p("Faults you didn't fix stay broken. Resetting to ", code(`before-exam${n}`), " on the Cluster page undoes everything.")], confirm: "Clean up" }))
            Jobs.start("exam-cleanup", String(n));
        },
      }, "Clean up"),
      h("a", { class: "btn", href: "#/cluster" }, `Reset to before-exam${n}…`)),
    h("div", { class: "rack-box hud", style: { marginTop: "16px" } }, h("table", { class: "result-table" },
      h("thead", {}, h("tr", {}, h("th", {}, "#"), h("th", {}, "Task"), h("th", {}, "Domain"), h("th", { style: { textAlign: "right" } }, "Checks"), h("th", { style: { textAlign: "right" } }, "Weight"), h("th", { style: { textAlign: "right" }, title: "Time spent / its share of the clock" }, "Time"), h("th", { style: { textAlign: "right" } }, "Earned"))),
      h("tbody", {}, rows))),
    drawer)));
  S.view = () => drawer.dispose();
}

// --- Kubestronaut: the five certifications -----------------------------------------------------------

const trackHref = t => t.id === "cka" ? "#/" : t.kind === "quiz" ? `#/quiz/${t.id}` : `#/track/${t.id}`;

function trackStats(t) {
  if (t.kind === "quiz") {
    const ready = t.best_exam != null ? t.best_exam : null;
    return { pct: ready || 0, line: t.bank ? `${t.bank} questions · ${t.sittings} sitting${t.sittings === 1 ? "" : "s"}` : "question bank not installed",
      big: ready == null ? "—" : `${ready}%`, sub: ready == null ? "no mock exam yet" : ready >= t.pass ? `best mock exam, above the ${t.pass}% pass mark` : `best mock exam; pass mark ${t.pass}%` };
  }
  const pct = t.labs ? Math.round(t.labs_passed * 100 / t.labs) : 0;
  return { pct, line: t.labs ? `${t.labs} labs · ${t.exams} mock exams · ${t.drills} drills` : "labs in preparation",
    big: t.labs ? `${t.labs_passed}/${t.labs}` : "—", sub: t.labs ? "labs passed" : "curriculum mapped, content coming" };
}

async function viewKubestronaut(main) {
  const { tracks } = await api("/tracks");
  const done = tracks.filter(t => trackStats(t).pct >= 100 || (t.kind === "quiz" && t.best_exam >= t.pass)).length;
  main.replaceChildren(h("div", { class: "page" }, h("div", { class: "wrap" },
    h("section", { class: "hero hero-slim" },
      h("div", { class: "hero-text" },
        h("div", { class: "kicker" }, "Kubestronaut"),
        h("h1", {}, "All five Kubernetes certifications"),
        h("p", { class: "lead" }, "Kubestronaut is the CNCF title for holding CKA, CKAD, CKS, KCNA and KCSA at the same time. Each track here follows its official curriculum, and every one is harder than the real exam: no hints, tighter clocks, fresh values on every attempt.")),
      h("div", { class: "kube-count" }, h("b", {}, done), h("span", {}, "of 5 ready"))),
    h("div", { class: "section-head" }, h("h2", {}, icon("exam"), "Tracks")),
    h("div", { class: "track-grid" }, tracks.map(t => {
      const st = trackStats(t);
      return h("article", { class: `track-card hud ${t.status}` },
        h("div", { class: "track-top" },
          h("span", { class: "badge" }, t.short),
          h("span", { class: "grow" }),
          h("span", { class: "chip" + (t.status === "ready" ? "" : " muted") }, t.status === "ready" ? (t.kind === "quiz" ? "multiple choice" : "hands-on") : t.kind === "quiz" && t.bank ? "seed bank" : "in preparation")),
        h("h3", {}, h("a", { href: trackHref(t) }, t.name)),
        h("p", { class: "cur" }, `${t.kind === "quiz" ? `${t.bank || 0} in the bank, ${t.questions} per exam` : st.line} · ${t.minutes} min exam · pass ${t.pass}%${t.curriculum !== "current" ? ` · v${t.curriculum}` : ""}`),
        h("div", { class: "track-num" }, h("b", {}, st.big), h("span", {}, st.sub)),
        h("div", { class: "meter" }, h("i", { style: { width: `${st.pct}%` } })),
        h("div", { class: "dombar", title: "Exam domains by weight" }, t.domains.map((d, i) => h("i", { style: { flex: d.weight, background: `var(--d${(i % 5) + 1})` }, title: `${d.name} · ${d.weight}%` }))),
        h("a", { class: "btn" + (t.status === "ready" || t.bank ? " solid" : ""), href: trackHref(t) }, t.id === "cka" ? "Open CKA" : t.kind === "quiz" ? "Practise" : "Roadmap", icon("arrow")));
    })))));
}

async function viewTrack(main, id) {
  const { tracks } = await api("/tracks");
  const t = tracks.find(x => x.id === id);
  if (!t) { location.hash = "#/kubestronaut"; return; }
  main.replaceChildren(h("div", { class: "page" }, h("div", { class: "wrap" },
    h("div", { class: "eyebrow" }, h("a", { href: "#/kubestronaut" }, "← Kubestronaut"), h("span", {}, "/"), h("span", { class: "id" }, t.short)),
    h("h1", { class: "page-title" }, t.name),
    h("div", { class: "callout" }, h("b", {}, "In preparation. "), `The ${t.short} labs, speed drills and mock exams are being written against curriculum v${t.curriculum}, at the same extreme difficulty as the CKA track. The domains they will cover, with their exam weights:`),
    h("div", { class: "track-domains" }, t.domains.map((d, i) => h("div", { class: "hud dom-card" },
      h("div", { class: "row" }, h("span", { class: "sw", style: { background: `var(--d${(i % 5) + 1})` } }), h("b", {}, d.name), h("span", { class: "grow" }), h("span", { class: "w" }, `${d.weight}%`)),
      h("ul", {}, (d.topics || []).map(x => h("li", {}, x)))))))));
}

// --- multiple-choice tracks (KCNA, KCSA) ----------------------------------------------------------------

async function viewQuizTrack(main, id) {
  const [{ tracks }, { history }] = await Promise.all([api("/tracks"), api(`/quiz/${id}/history`)]);
  const t = tracks.find(x => x.id === id);
  if (!t) { location.hash = "#/kubestronaut"; return; }
  const exams = history.filter(x => x.mode === "exam");
  // Per-domain accuracy over every sitting (practice and exam).
  const acc = Object.fromEntries(t.domains.map(d => [d.key, [0, 0]]));
  for (const x of history) for (const [k, [c, n]] of Object.entries(x.domains || {})) if (acc[k]) { acc[k][0] += c; acc[k][1] += n; }
  const start = async (mode, domain) => {
    try {
      const st = await api(`/quiz/${id}/start`, { method: "POST", body: { mode, domain, count: 10 } });
      location.hash = `#/quiz/s/${st.sid}`;
    } catch (e) { toast(e.message, true); }
  };
  const examMin = Math.round(t.minutes * 0.8);
  main.replaceChildren(h("div", { class: "page" }, h("div", { class: "wrap" },
    h("div", { class: "eyebrow" }, h("a", { href: "#/kubestronaut" }, "← Kubestronaut"), h("span", {}, "/"), h("span", { class: "id" }, t.short)),
    h("h1", { class: "page-title" }, t.name),
    h("section", { class: "progress" },
      h("div", { class: "readiness hud" },
        h("div", { class: "card-head" }, h("div", {}, h("h3", {}, "Accuracy by domain"), h("p", {}, "Every answered question, practice and mock exams together")), h("span", { class: "chip" }, `${t.bank} questions`)),
        h("div", { class: "domains", style: { marginTop: "16px" } }, t.domains.map((d, i) => {
          const [c, n] = acc[d.key];
          return h("div", { class: "domain" },
            h("div", { class: "row" }, h("span", { class: "sw", style: { background: `var(--d${(i % 5) + 1})` } }), h("span", { class: "name" }, d.short || d.name),
              h("span", { class: "grow" }), h("span", { class: "n" }, n ? `${Math.round(c * 100 / n)}% of ${n}` : `${t.by_domain[d.key] || 0} in bank`), h("span", { class: "w" }, `${d.weight}%`),
              h("button", { class: "btn sm", disabled: !t.by_domain[d.key], onclick: () => start("practice", d.key) }, "Practise")),
            h("div", { class: "track" }, h("i", { style: { width: `${n ? Math.round(c * 100 / n) : 0}%`, background: `var(--d${(i % 5) + 1})` } })));
        }))),
      h("div", { class: "upnext hud" },
        h("div", { class: "card-head" }, h("div", {}, h("h3", {}, "Mock exam"), h("p", {}, `${t.questions} questions, weighted like the exam`))),
        h("div", { class: "upnext-body" },
          h("p", { class: "cur" }, `${examMin} minutes: 20% less than the real exam's ${t.minutes}. Pass mark ${t.pass}%. Multi-select questions don't say how many answers are right. Explanations appear only after you hand in.`),
          h("div", { class: "track-num" }, h("b", {}, exams.length ? `${Math.max(...exams.map(x => x.score))}%` : "—"), h("span", {}, exams.length ? `best of ${exams.length}` : "not attempted"))),
        h("div", { class: "upnext-actions" },
          h("button", { class: "btn solid", disabled: !t.bank, onclick: () => start("exam") }, "Start mock exam", icon("arrow")),
          h("button", { class: "btn quiet", disabled: !t.bank, onclick: () => start("practice") }, "10 random")))),
    h("div", { class: "section-head" }, h("h2", {}, icon("chart"), "Sittings")),
    history.length ? h("div", { class: "rack-box hud" }, h("table", { class: "result-table" },
      h("thead", {}, h("tr", {}, ["When", "Mode", "Questions", "Score", ""].map(x => h("th", {}, x)))),
      h("tbody", {}, history.slice().reverse().map(x => h("tr", { class: "clickable", onclick: () => { location.hash = `#/quiz/s/${x.sid}/review`; } },
        h("td", {}, ago(x.at)), h("td", {}, x.mode === "exam" ? "Mock exam" : `Practice${x.domain ? ` · ${(t.domains.find(d => d.key === x.domain) || {}).short || x.domain}` : ""}`),
        h("td", { class: "n" }, `${x.correct}/${x.total}`),
        h("td", { class: "n", style: { color: x.passed ? "var(--pass)" : "var(--fail)" } }, `${x.score}%`),
        h("td", { class: "n" }, "Review →"))))))
      : h("div", { class: "empty" }, "No sittings yet. Start with a domain you know least."))));
}

async function viewSitting(main, sid, mode) {
  let st = await api(`/quiz/sittings/${sid}`);
  const skew = st.now * 1000 - Date.now();
  let idx = 0;
  const done = () => !!st.submitted_at;
  const body = h("div", { class: "doc-body quiz-body" });
  const nav = h("div", { class: "navgrid" });
  const clockEl = h("div", { class: "clock" });
  const save = (qid, payload) => api(`/quiz/sittings/${sid}/answer`, { method: "PUT", body: { qid, ...payload } }).catch(e => toast(e.message, true));
  const submit = async (auto = false) => {
    if (!auto) {
      const open = st.items.filter(x => !x.chosen.length).length;
      if (!(await dialog({ title: "Hand in?", body: [p("Your answers are graded now."), open ? p(`${open} question${open > 1 ? "s" : ""} unanswered.`) : null], confirm: "Hand in" }))) return;
    }
    st = await api(`/quiz/sittings/${sid}/submit`, { method: "POST" });
    draw();
  };
  const drawNav = () => nav.replaceChildren(...st.items.map((x, i) => h("button", {
    class: [i === idx ? "on" : "", x.flagged ? "flag" : "", x.chosen.length ? "seen" : "", done() ? (x.right ? "ok" : "zero") : ""].join(" "),
    onclick: () => { idx = i; draw(); } }, i + 1)));
  const drawQuestion = () => {
    const x = st.items[idx];
    const opts = x.options.map((o, i) => {
      const chosen = x.chosen.includes(i), correct = done() && x.correct.includes(i);
      const input = h("input", { type: x.multi ? "checkbox" : "radio", name: "opt", checked: chosen, disabled: done(),
        onchange: () => {
          x.chosen = x.multi ? (input.checked ? [...x.chosen, i] : x.chosen.filter(c => c !== i)).sort() : [i];
          save(x.qid, { choice: x.chosen }); drawNav();
        } });
      return h("label", { class: "opt" + (done() ? (correct ? " correct" : chosen ? " wrong" : "") : chosen ? " chosen" : "") }, input, h("span", { class: "md-inline" }, inlineMd(o)));
    });
    body.replaceChildren(...[
      h("div", { class: "qhead" }, h("span", { class: "label-sm" }, `Question ${idx + 1} of ${st.items.length}`), h("span", { class: "grow" }),
        x.multi ? h("span", { class: "chip" }, "Select all that apply") : null),
      renderMarkdown(x.stem),
      h("div", { class: "opts" }, opts),
      done() ? h("div", { class: "explain" + (x.right ? " ok" : " no") },
        h("b", {}, x.right ? "Correct. " : "Not quite. "), renderMarkdown(x.explain),
        x.refs.length ? h("div", { class: "refs" }, x.refs.map(r => h("a", { href: r, target: "_blank", rel: "noopener" }, r.replace(/^https?:\/\//, "")))) : null) : null,
      h("div", { class: "qfoot" },
        h("button", { class: "btn", disabled: idx === 0, onclick: () => { idx--; draw(); } }, "← Previous"),
        done() ? null : h("button", { class: "btn" + (x.flagged ? " solid" : ""), onclick: () => { x.flagged = !x.flagged; save(x.qid, { flag: x.flagged }); draw(); } }, x.flagged ? "Flagged" : "Flag for review"),
        h("span", { class: "grow" }),
        idx < st.items.length - 1 ? h("button", { class: "btn", onclick: () => { idx++; draw(); } }, "Next →")
          : done() ? null : h("button", { class: "btn solid", onclick: () => submit(false) }, "Hand in"))].filter(Boolean));
  };
  const drawResult = () => {
    const r = st.result;
    const t = (S.tracks || []).find(x => x.id === st.track);
    return h("div", { class: "quiz-result hud" },
      h("div", {}, h("div", { class: "stat-label" }, "Score"), h("div", { class: "stat", style: { color: r.passed ? "var(--pass)" : "var(--fail)" } }, r.score, h("small", {}, "%"))),
      h("div", {}, h("div", { class: "stat-label" }, "Correct"), h("div", { class: "stat" }, r.correct, h("small", {}, ` / ${r.total}`))),
      h("div", {}, h("div", { class: "stat-label" }, "Time"), h("div", { class: "stat" }, Math.round(r.seconds / 60), h("small", {}, " min"))),
      h("div", { class: "quiz-domains" }, Object.entries(r.domains).map(([k, [c, n]]) => h("div", { class: "domain" },
        h("div", { class: "row" }, h("span", { class: "name" }, (t && (t.domains.find(d => d.key === k) || {}).short) || k), h("span", { class: "grow" }), h("span", { class: "n" }, `${c}/${n}`)),
        h("div", { class: "track" }, h("i", { style: { width: `${Math.round(c * 100 / n)}%`, background: c / n >= (r.pass_mark / 100) ? "var(--pass)" : "var(--warn)" } }))))));
  };
  let ticks = 0;
  const tick = () => {
    if (done()) { clockEl.replaceChildren(h("span", { class: "t" }, `${st.result.score}%`), h("span", { class: "muted" }, st.result.passed ? "passed" : `needs ${st.result.pass_mark}%`)); return; }
    if (!st.deadline) { clockEl.replaceChildren(h("span", { class: "t" }, clock(((Date.now() + skew) / 1000) - st.created)), h("span", { class: "muted" }, "practice")); return; }
    const left = st.deadline - (Date.now() + skew) / 1000;
    clockEl.className = "clock" + (left < 300 ? " low" : "");
    clockEl.replaceChildren(h("span", { class: "t" }, clock(left)), h("span", { class: "muted" }, "left"));
    if (left <= 0 && !ticks++) { toast("Time is up. Handing in."); submit(true); }
  };
  const draw = () => { drawNav(); drawQuestion(); tick(); head.replaceChildren(...headParts().filter(Boolean)); };
  const head = h("div", { class: "quiz-head" });
  const headParts = () => [
    h("div", { class: "eyebrow" }, h("a", { href: `#/quiz/${st.track}` }, `← ${st.track.toUpperCase()}`), h("span", {}, "/"), h("span", { class: "id" }, st.mode === "exam" ? "mock exam" : "practice")),
    h("div", { style: { display: "flex", alignItems: "center", gap: "14px", marginTop: "12px" } }, clockEl, h("span", { style: { flex: 1 } }),
      done() ? h("a", { class: "btn", href: `#/quiz/${st.track}` }, "Done") : h("button", { class: "btn solid", onclick: () => submit(false) }, "Hand in")),
    done() ? drawResult() : null,
    nav];
  if (!S.tracks) api("/tracks").then(r => { S.tracks = r.tracks; if (done()) draw(); }).catch(() => {});
  main.replaceChildren(h("div", { class: "page" }, h("div", { class: "wrap quiz-wrap" }, head, h("section", { class: "doc hud" }, body))));
  draw();
  everyWhileHere(tick, 1000);
}

// --- speed drills ------------------------------------------------------------------------------------

const domainVar = key => { const i = DOMAINS.indexOf(domainOf(key)); return i < 0 ? "var(--muted)" : `var(--d${i + 1})`; };

async function viewDrills(main) {
  const { drills } = await api("/drills");
  const runs = drills.reduce((a, d) => a + d.attempts, 0);
  const inside = drills.filter(d => d.best != null && d.best <= d.seconds).length;
  const card = d => {
    const state = d.best == null ? "" : d.best <= d.seconds ? "passed" : "graded";
    return h("article", { class: `lab-card drill-card hud ${state}` },
      h("header", {}, icon("clock"), h("span", {}, shortDomain(d.domain)), h("i", { class: "dom", style: { background: domainVar(d.domain) } }),
        h("span", { class: "grow" }), h("span", { class: "min" }, `${clock(d.seconds)} budget`)),
      h("div", { class: "body" },
        h("h3", {}, h("a", { href: `#/drill/${d.id}` }, h("span", { class: "no" }, d.num), d.title)),
        h("div", { class: "tags" }, d.needs.length ? h("span", { class: "tag" }, `needs ${d.needs.join(", ")}`) : null,
          d.attempts ? h("span", { class: "tag" }, `${d.attempts} run${d.attempts > 1 ? "s" : ""}`) : h("span", { class: "tag" }, "not tried"))),
      h("footer", {},
        h("div", { class: "prog" }, h("span", { class: "label-sm" }, "Best time"),
          h("span", { class: "val" }, d.best == null ? "—" : `${clock(d.best)}${d.best <= d.seconds ? "" : " (over budget)"}`),
          h("span", { class: "bar" }, h("i", { style: { width: `${d.best == null ? 0 : Math.min(100, (d.seconds / d.best) * 100)}%` } }))),
        h("a", { class: "btn", href: `#/drill/${d.id}` }, d.started ? "Continue" : "Open")));
  };
  main.replaceChildren(h("div", { class: "page" }, h("div", { class: "wrap" },
    h("div", { class: "section-head", style: { marginTop: 0 } }, h("h2", {}, icon("clock"), "Speed drills"),
      h("span", { class: "sub" }, `${inside} of ${drills.length} inside the budget · ${runs} run${runs === 1 ? "" : "s"}`)),
    h("div", { class: "callout" }, h("b", {}, "One task, a tight clock. "),
      "Budgets are shorter than the real exam allows. Every start draws new names and numbers, so you can't memorise answers. The clock runs until every check passes."),
    h("div", { class: "actions", style: { margin: "0 0 18px" } },
      h("button", { class: "btn solid", onclick: () => { const d = drills[Math.floor(Math.random() * drills.length)]; location.hash = `#/drill/${d.id}`; } }, "Random drill", icon("arrow"))),
    h("div", { class: "lab-grid" }, drills.map(card)))));
}

async function viewDrill(main, id) {
  let d = await api(`/drills/${id}`);
  let skew = d.now * 1000 - Date.now();
  const doc = h("section", { class: "doc" });
  const body = h("div", { class: "doc-body" });
  const clockEl = h("div", { class: "clock" });
  const actions = h("div", { class: "actions" });
  const reload = async () => { d = await api(`/drills/${id}`); skew = d.now * 1000 - Date.now(); draw(); };
  const drawer = jobDrawer({ filter: j => j.target === d.id || j.target === d.num, onEnd: async info => {
    await reload();
    if (info.action === "drill-check" && d.result) {
      const t = d.last ? clock(d.last.seconds) : "";
      toast(d.result.pass === d.result.total ? `All checks pass in ${t}${d.last && d.last.seconds > d.seconds ? " (over budget)" : ""}` : `${d.result.pass}/${d.result.total} checks · the clock keeps running`);
    }
  } });
  const busy = () => !!S.jobs.current;
  const startBtn = h("button", { class: "btn" }, "Start");
  startBtn.onclick = async () => {
    if (d.started && !(await dialog({ title: "Start again?", body: p("This draws new values and resets the clock. The current attempt is abandoned."), confirm: "Start over" }))) return;
    Jobs.start("drill-start", d.id);
  };
  const checkBtn = h("button", { class: "btn solid", onclick: () => Jobs.start("drill-check", d.id) }, "Check");
  const cleanBtn = h("button", { class: "btn", onclick: () => Jobs.start("drill-cleanup", d.id) }, "Clean up");
  actions.append(startBtn, checkBtn, cleanBtn);
  const sync = () => { startBtn.disabled = busy(); checkBtn.disabled = busy() || !d.started; cleanBtn.disabled = busy(); };
  const offJobs = Jobs.on(sync);
  const tick = () => {
    if (!d.started) { clockEl.className = "clock"; clockEl.replaceChildren(h("span", { class: "t" }, clock(d.seconds)), h("span", { class: "muted" }, "budget")); return; }
    const done = d.result && d.result.pass === d.result.total && d.last;
    const used = done ? d.last.seconds : (Date.now() + skew) / 1000 - d.started;
    clockEl.className = "clock" + (used > d.seconds ? " low" : "");
    clockEl.replaceChildren(h("span", { class: "t" }, clock(used)), h("span", { class: "muted" }, done ? "done" : `of ${clock(d.seconds)}`));
  };
  const draw = () => {
    body.replaceChildren(...[
      d.started ? renderMarkdown(d.markdown) : h("div", { class: "empty" }, h("b", {}, "Press Start. "),
        "Setup takes a few seconds; the task appears and the clock starts as soon as it's ready."),
      d.result ? h("div", {}, h("div", { class: "check-section" }, "Last check"), resultsView(d.result)) : null,
      d.history.length ? h("div", {}, h("div", { class: "check-section" }, "Your times"),
        h("div", { class: "spark-bars drill-times" }, d.history.map(r => h("i", {
          class: r.pass === r.total ? "on" : "", title: `${clock(r.seconds)} · ${r.pass}/${r.total} · ${ago(r.at)}`,
          style: { height: `${Math.max(12, Math.min(100, (r.seconds / (d.seconds * 2)) * 100))}%`, background: r.pass === r.total ? (r.seconds <= d.seconds ? "var(--pass)" : "var(--warn)") : "var(--strip)" } })))) : null].filter(Boolean));
    sync(); tick();
  };
  doc.append(
    h("div", { class: "doc-head" },
      h("div", { class: "eyebrow" }, h("a", { href: "#/drills" }, "← drills"), h("span", {}, "/"), h("span", { class: "id" }, `drill ${d.num}`), h("span", {}, "·"), h("span", {}, shortDomain(d.domain))),
      h("h1", {}, d.title),
      h("div", { style: { display: "flex", alignItems: "center", gap: "14px", marginTop: "10px" } }, clockEl, h("span", { style: { flex: 1 } }), actions)),
    body, drawer);
  const ws = h("div", { class: "workspace" }, doc, gutter(doc, "drillDocWidth"));
  main.replaceChildren(ws);
  Terms.mount(ws);
  draw();
  everyWhileHere(tick, 1000);
  S.view = () => { offJobs(); drawer.dispose(); };
}

// --- cluster and snapshots ---------------------------------------------------------------------------------

async function viewCluster(main) {
  const rack = h("tbody");
  const snaps = h("tbody");
  const snapNote = h("div");
  const jobsList = h("div");
  const drawer = jobDrawer({ filter: j => j.action.startsWith("snapshot") || j.action === "reset", onEnd: () => { drawSnaps(); } });

  const drawRack = c => {
    if (!c) return;
    const byName = Object.fromEntries((c.nodes || []).map(x => [x.name, x]));
    rack.replaceChildren(...c.vms.map(vm => {
      const node = byName[vm.name];
      const power = vm.status == null ? h("span", { class: "state muted" }, "unknown")
        : h("span", { class: "state" }, h("span", { class: "dot " + (vm.status === "running" ? "ok" : "bad") }), vm.status);
      const k8s = vm.role !== "node" || vm.name === "nfs" ? h("span", { class: "muted" }, vm.role === "jump" ? "jump host · LB · DNS" : "NFS server")
        : node ? h("span", { class: "state" }, h("span", { class: "dot " + (node.ready ? "ok" : "bad") }), node.ready ? "Ready" : "NotReady",
          h("span", { class: "muted mono", style: { fontSize: "12.5px" } }, ` ${node.version || ""}${node.roles.length ? " · " + node.roles.join(",") : ""}${node.unschedulable ? " · cordoned" : ""}`))
          : h("span", { class: "muted" }, c.nodes ? "not joined" : "—");
      return h("tr", {},
        h("td", { class: "name" }, vm.name),
        h("td", { class: "m" }, vm.vmid),
        h("td", { class: "m" }, vm.ip),
        h("td", { class: "m" }, `${vm.cores} vCPU · ${vm.mem_mb / 1024} GB`),
        h("td", {}, power),
        h("td", {}, k8s));
    }));
  };

  const drawSnaps = async () => {
    let r;
    try { r = await api("/snapshots"); } catch (e) { snapNote.replaceChildren(h("div", { class: "callout" }, e.message)); return; }
    snapNote.replaceChildren(r.error ? h("div", { class: "callout" }, r.error) : "");
    const busy = !!S.jobs.current;
    snaps.replaceChildren(...r.snapshots.map(s => h("tr", {},
      h("td", { class: "name" }, s.name),
      h("td", { class: "m" }, s.time ? new Date(s.time * 1000).toLocaleString() : "", h("span", { class: "muted" }, s.time ? ` · ${ago(s.time)}` : "")),
      h("td", { class: "m" }, !s.complete ? h("span", { style: { color: "var(--warn)" } }, `${s.vms.length}/${r.vm_count}`)
        : s.jump_state ? h("span", { title: "Node VMs, plus the jump host's lab state saved as a file" }, `${s.vms.filter(v => v !== "jump").length} nodes + jump`) : `all ${s.vms.length}`),
      h("td", { style: { textAlign: "right", whiteSpace: "nowrap" } },
        s.name === "base" ? null : h("button", { class: "btn sm quiet", disabled: busy, onclick: () => deleteSnap(s.name) }, "Delete"), " ",
        h("button", { class: "btn sm danger", disabled: busy || !s.complete, onclick: () => resetTo(s) }, "Reset to this")))));
    if (!r.snapshots.length) snaps.append(h("tr", {}, h("td", { colspan: 4, class: "muted" }, "No snapshots.")));
  };

  const resetTo = async snap => {
    const name = snap.name;
    // Snapshots with the jump host's lab state saved as a file leave the jump VM running.
    const ok = await dialog({
      title: `Reset the cluster to "${name}"?`,
      body: snap.jump_state
        ? [p("The six node VMs roll back, and the lab files and tools on the jump host (kubeconfig, Helm, HAProxy, files in your home directory) go back to how they were. Cluster changes since that snapshot are lost."),
          p("Your grades, exam history and notes are kept, and this page stays connected."),
          p("Type the snapshot name to confirm.")]
        : [p("This snapshot is older and includes the jump host itself, so every lab VM rolls back. All work since is lost: cluster state, files, grades and open shells."),
          p("This page disconnects and reconnects by itself in a minute or two."),
          p("Type the snapshot name to confirm.")],
      confirm: "Reset", danger: true, typed: name,
    });
    if (!ok) return;
    const j = await Jobs.start("reset", name);
    if (j && !snap.jump_state) waitForReturn(`Rolling back to ${name}`);
  };

  const deleteSnap = async name => {
    if (await dialog({ title: `Delete snapshot "${name}"?`, body: p("It is removed from every lab VM and frees its space on the Proxmox host. The running cluster isn't touched."), confirm: "Delete", danger: true }))
      Jobs.start("snapshot-delete", name);
  };

  const nameField = h("input", { class: "field", placeholder: "e.g. after-05", maxlength: 40, spellcheck: "false" });
  const takeBtn = h("button", { class: "btn solid" }, "Take snapshot");
  takeBtn.onclick = async () => {
    const name = nameField.value.trim();
    if (!/^[A-Za-z][A-Za-z0-9_-]{1,39}$/.test(name) || name === "base") { toast("Use letters, digits, - and _, starting with a letter (not \"base\").", true); return; }
    const ok = await dialog({
      title: `Snapshot as "${name}"?`,
      body: [p("The five Kubernetes nodes and the NFS server shut down so etcd is captured consistently across all three members, then start again. The lab files and tools on the jump host are saved with it. Allow about three minutes."),
        p("An existing snapshot with this name is replaced.")],
      confirm: "Take snapshot",
    });
    if (ok && await Jobs.start("snapshot", name)) nameField.value = "";
  };

  const drawJobs = () => jobsList.replaceChildren(...(S.jobs.recent || []).slice(0, 8).map(j => h("div", { class: "check " + (j.code === 0 ? "ok" : j.ended ? "no" : "") },
    h("span", { class: "v" }, j.ended == null ? "…" : j.code === 0 ? "OK" : `E${j.code}`),
    h("span", {}, h("a", { href: "#/cluster", class: "mono", onclick: e => { e.preventDefault(); showJobDialog(j); } }, j.label), h("span", { class: "muted" }, ` · ${ago(j.started)}`)))));

  main.replaceChildren(h("div", { class: "page" }, h("div", { class: "wrap" },
    h("div", { class: "section-head", style: { marginTop: 0 } }, h("h2", {}, icon("server"), "Machines"), h("span", { class: "grow" }),
      h("span", { class: "muted", style: { fontSize: "13px" } }, "Proxmox power state and Kubernetes node status, refreshed every 10 s")),
    h("div", { class: "rack-box hud" }, h("table", { class: "rack" },
      h("thead", {}, h("tr", {}, ["VM", "ID", "Address", "Size", "Power", "Kubernetes"].map(t => h("th", {}, t)))), rack)),
    h("div", { class: "section-head" }, h("h2", {}, icon("clock"), "Snapshots")),
    h("div", { class: "callout" }, h("b", {}, "Snapshots are your undo button. "),
      "Take one before any lab that changes nodes or the control plane (01–08, 27, 28 and the mock exams). ",
      h("span", { class: "mono" }, "base"), " is bare Ubuntu: resetting to it starts the whole course over."),
    snapNote,
    h("div", { class: "rack-box hud" }, h("table", { class: "rack" },
      h("thead", {}, h("tr", {}, ["Name", "Taken", "VMs", ""].map(t => h("th", {}, t)))), snaps)),
    h("div", { class: "inline-form" }, nameField, takeBtn),
    drawer,
    h("div", { class: "section-head" }, h("h2", {}, icon("chart"), "Recent jobs")),
    jobsList)));

  const busy = () => { takeBtn.disabled = !!S.jobs.current; drawJobs(); };
  busy();
  const off = Jobs.on(ev => { busy(); if (ev.type !== "out") drawSnaps(); });
  drawRack(S.cluster);
  pollCluster(true).then(drawRack);
  drawSnaps();
  everyWhileHere(() => pollCluster(true).then(drawRack), 10000);
  S.view = () => { off(); drawer.dispose(); };
}

// After a reset the jump host itself rolls back: wait for this server to go away and come back.
function waitForReturn(title) {
  const el = h("div", { class: "offline" }, h("div", {},
    h("h2", {}, title),
    h("p", {}, "The jump host is rolling back with the rest of the lab. This page reloads when it's back; it usually takes one to two minutes."),
    h("div", { class: "bar" })));
  document.body.append(el);
  let wentAway = false;
  const started = Date.now();
  const poll = setInterval(async () => {
    try {
      const r = await fetch("/api/health", { cache: "no-store" });
      if (r.ok && wentAway) { clearInterval(poll); location.hash = "#/cluster"; location.reload(); }
    } catch { wentAway = true; }
    if (Date.now() - started > 8 * 60000) {
      clearInterval(poll);
      $("p", el).textContent = "Still not back after eight minutes. Check the VMs in Proxmox, or reload this page to try again.";
    }
  }, 3000);
}

// --- boot ---------------------------------------------------------------------------------------------------

async function boot() {
  const h0 = await fetch("/api/health", { cache: "no-store" }).then(r => r.json()).catch(() => ({ authed: false }));
  if (!h0.authed) { showLogin(); return; }
  $("#app").replaceChildren(renderTop(), h("main", { id: "main", style: { flex: "1", display: "flex", flexDirection: "column", minHeight: "0" } }));
  await Jobs.sync();
  pollCluster();
  if (!S.polling) S.polling = setInterval(pollCluster, 20000);
  route();
}

window.addEventListener("hashchange", route);
window.addEventListener("resize", () => Terms.fit());
boot();
