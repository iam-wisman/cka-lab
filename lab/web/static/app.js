/* CKA lab console: front end. Plain JS, no build step.
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
  background: "#0c0d0b", foreground: "#dedbd1", cursor: "#e8c547", cursorAccent: "#0c0d0b",
  selectionBackground: "#e8c54750",
  black: "#1f201d", red: "#e8695d", green: "#7fc797", yellow: "#e3c057", blue: "#82aee0",
  magenta: "#c79be0", cyan: "#6cc4c0", white: "#d6d3c9",
  brightBlack: "#5d5b54", brightRed: "#f2877c", brightGreen: "#9edcb1", brightYellow: "#f0d36f",
  brightBlue: "#a3c6f0", brightMagenta: "#dab6ee", brightCyan: "#8fd8d4", brightWhite: "#f4f1e8",
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
    await Promise.all(["400", "700"].map(w => document.fonts.load(`${w} ${this.size}px "Commit Mono"`))).catch(() => {});
    let list = await api("/terms");
    if (!list.length) list = [await api("/terms", { method: "POST", body: {} })];
    for (const t of list) this.add(t);
    this.activate(this.tabs[0]);
  },

  add({ sid, title }) {
    const el = h("div", { class: "xt hidden" });
    this.host.append(el);
    const term = new Terminal({
      fontFamily: '"Commit Mono", ui-monospace, monospace', fontSize: this.size, lineHeight: 1.18,
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

  renderBar() {
    if (!this.bar) return;
    this.bar.replaceChildren(
      ...this.tabs.map(t => h("div", { class: "term-tab" + (t === this.active ? " on" : ""), onclick: () => this.activate(t) },
        h("span", {}, t.title),
        h("button", { title: "Close this shell", onclick: e => { e.stopPropagation(); this.close(t); } }, "×"))),
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

// --- chrome ------------------------------------------------------------------------------------

function theme(next) {
  const order = ["auto", "light", "dark"];
  let t = store.get("theme", "auto");
  if (next) { t = order[(order.indexOf(t) + 1) % 3]; store.set("theme", t); }
  if (t === "auto") document.documentElement.removeAttribute("data-theme");
  else document.documentElement.setAttribute("data-theme", t);
  const b = $("#theme-btn");
  if (b) {
    b.replaceChildren({ auto: "◐", light: "○", dark: "●" }[t], h("span", { class: "label" }, ` ${t}`));
    b.title = `Theme: ${t} (click to change)`;
  }
}

function renderTop() {
  const top = h("header", { class: "top" },
    h("a", { class: "brand", href: "#/", title: "Overview" }, h("i"), h("span", { class: "brand-text" }, "cka", h("b", {}, " / "), "lab")),
    h("nav", { class: "nav" },
      h("a", { href: "#/", "data-r": "labs" }, "Labs"),
      h("a", { href: "#/exams", "data-r": "exams" }, "Exams"),
      h("a", { href: "#/cluster", "data-r": "cluster" }, "Cluster")),
    h("span", { class: "spacer" }),
    h("div", { class: "tools" },
      h("span", { id: "job-slot" }),
      h("a", { class: "pill", id: "health", href: "#/cluster", title: "Kubernetes nodes Ready" }, h("span", { class: "dot" }), h("span", { class: "label" }, "cluster")),
      h("button", { class: "btn quiet sm mono", id: "theme-btn", onclick: () => theme(true) }),
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
  const btn = h("button", { class: "btn solid", type: "submit" }, "Open the console");
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
    h("a", { class: "brand", href: "#/" }, h("i"), "cka", h("b", {}, "/"), "lab"),
    h("h1", {}, "Jump host console"),
    h("p", {}, "Labs, mock exams and a shell on the jump host, in the browser. Sign in with the student password."),
    h("label", { for: "pw" }, "Password"), pw, btn, err);
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
    else location.hash = "#/";
  } catch (e) {
    if (e.status === 401) return;
    main.replaceChildren(h("div", { class: "page" }, h("div", { class: "wrap" },
      h("div", { class: "empty" }, h("b", {}, "Couldn't load this page. "), e.message))));
  }
}

// --- overview --------------------------------------------------------------------------------------

function scoreCell(lab) {
  if (lab.best == null) return lab.started_at ? h("span", { class: "tag" }, "started") : h("span", { class: "muted mono" }, "—");
  const r = lab.result || {};
  const pct = Math.round(lab.best * 100);
  return h("div", { class: "score" + (lab.best === 1 ? " full" : "") },
    h("span", { class: "track" }, h("i", { style: { width: `${pct}%` } })),
    lab.best === 1 ? "passed" : `${r.pass ?? "?"}/${r.total ?? "?"}`);
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
  const next = labs.find(l => !labPassed(l));

  let filter = store.get("labFilter", "all");
  const tbody = h("tbody");
  const filters = h("div", { class: "filters" });
  const drawRows = () => {
    filters.replaceChildren(...[["all", "All"], ["todo", "Not passed"], ...DOMAINS.map(d => [d.key, d.short || d.name])].map(([k, label]) =>
      h("button", { class: filter === k ? "on" : "", onclick: () => { filter = k; store.set("labFilter", k); drawRows(); } }, label)));
    const shown = labs.filter(l => filter === "all" || (filter === "todo" ? !labPassed(l) : domainOf(l.domain).key === filter));
    tbody.replaceChildren(...shown.map(l => h("tr", { class: "row" + (labPassed(l) ? " done" : ""), onclick: () => { location.hash = `#/lab/${l.id}`; } },
      h("td", { class: "num" }, l.num),
      h("td", {}, h("a", { class: "t", href: `#/lab/${l.id}`, style: { textDecoration: "none" } }, l.title),
        h("div", { class: "cur" }, l.curriculum.join(" · "))),
      h("td", { class: "dom" }, shortDomain(l.domain)),
      h("td", { class: "min" }, l.minutes ? `${l.minutes}m` : ""),
      h("td", { class: "st" }, scoreCell(l)),
      h("td", { class: "go" }, "→"))));
    if (!shown.length) tbody.append(h("tr", {}, h("td", { colspan: 6, class: "muted" }, "Nothing here.")));
  };
  drawRows();

  const examsSection = h("section", { id: "exams" },
    h("div", { class: "section-head" }, h("h2", {}, "Mock exams"), h("span", { class: "grow" }),
      h("span", { class: "muted", style: { fontSize: "13px" } }, "120 minutes · weighted tasks · pass at 66 %")),
    h("div", { class: "exam-rows" }, data.exams.map(e => {
      const running = e.deadline && !e.submitted_at && e.deadline * 1000 > Date.now();
      return h("a", { class: "exam-row", href: `#/exam/${e.n}` },
        h("div", { class: "n" }, e.n),
        h("div", {},
          h("h3", {}, e.title.replace(/^CKA /, "")),
          h("div", { class: "meta" }, `${e.tasks} tasks · ${e.minutes} min`),
          h("div", { class: "hist" },
            running ? h("span", { class: "tag mark" }, "in progress") : null,
            e.history.length ? e.history.slice(-5).map(x => h("span", { class: "tag " + (x.passed ? "pass" : "fail") }, `${x.score}%`))
              : !running && h("span", { class: "muted", style: { fontSize: "13px" } }, "Not attempted"))));
    })));

  main.replaceChildren(h("div", { class: "page" }, h("div", { class: "wrap" },
    h("section", { class: "masthead" },
      h("div", {},
        h("h1", {}, "Kubernetes administration, from bare metal up."),
        h("p", {}, "31 labs in curriculum order, then two timed mock exams. Everything runs on your HA cluster.")),
      h("div", {}, h("div", { class: "stat-label" }, "Labs passed"),
        h("div", { class: "stat" }, passed, h("small", {}, ` / ${labs.length}`)),
        h("div", { class: "stat-note" }, `${labs.filter(l => l.started_at && !labPassed(l)).length} in progress`)),
      h("div", {}, h("div", { class: "stat-label" }, "Curriculum covered"),
        h("div", { class: "stat" }, coverage, h("small", {}, " %")),
        h("div", { class: "stat-note" }, "weighted by exam domain")),
      h("div", {}, h("div", { class: "stat-label" }, "Best mock exam"),
        h("div", { class: "stat" }, examBest < 0 ? "—" : examBest, examBest < 0 ? "" : h("small", {}, " %")),
        h("div", { class: "stat-note" }, examBest < 0 ? "not attempted yet" : examBest >= 66 ? "above the pass mark" : "below the 66 % pass mark"))),
    h("div", { class: "domains" }, perDomain.map(d => h("div", { class: "domain-seg", style: { flexGrow: d.weight }, title: `${d.name}: ${d.weight}% of the exam` },
      h("div", { class: "track" }, h("div", { class: "fill", style: { width: `${Math.round(d.frac * 100)}%` } })),
      h("div", { class: "cap" }, h("span", {}, d.short || d.name), h("span", {}, `${d.weight}% · ${d.done}/${d.labs.length} labs`))))),
    next ? h("div", { class: "next" },
      h("div", { class: "what" }, h("span", { class: "muted" }, next.started_at ? "Pick up where you left off: " : "Next up: "),
        h("b", {}, `Lab ${next.num}`), ` · ${next.title}`),
      h("a", { class: "btn solid", href: `#/lab/${next.id}` }, next.started_at ? "Resume" : "Open lab")) : null,
    h("section", { id: "labs" },
      h("div", { class: "section-head" }, h("h2", {}, "Labs"), h("span", { class: "grow" }), filters),
      h("table", { class: "ledger" }, tbody)),
    examsSection)));
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
  const byNum = Object.fromEntries((S.overview?.labs || []).map(l => [l.num, l]));
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
      loadOverview().catch(() => {});
      if (info.action === "lab-check") {
        const r = lab.result;
        if (r) toast(r.pass === r.total ? `Lab ${lab.num}: all ${r.total} checks pass` : `Lab ${lab.num}: ${r.pass}/${r.total} checks pass`);
        select("results");
      } else { drawFacts(); drawTabs(); }
    },
  });

  const busy = () => !!S.jobs.current;
  const startBtn = h("button", { class: "btn", onclick: () => Jobs.start("lab-start", lab.id) }, "Start");
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
      h("a", { href: `#/lab/${byNum[n]?.id || n}`, class: "mono", style: { color: byNum[n] && !labPassed(byNum[n]) ? "var(--warn)" : "" }, title: byNum[n] && !labPassed(byNum[n]) ? "not passed yet" : "passed" }, `lab ${n}`)])));
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
      h("div", { class: "eyebrow" }, h("a", { href: "#/" }, "← labs"), h("span", {}, "/"), h("span", {}, `lab ${lab.num}`), h("span", {}, "·"), h("span", {}, shortDomain(lab.domain))),
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
  let marks = { deadline: exam.deadline, flags: [], seen: [] };
  try {
    const r = await api(`/notes/${flagsKey}`);
    if (r.value && r.value.deadline === exam.deadline) marks = r.value;
  } catch { /* fresh */ }
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
    await api(`/exams/${n}/submit`, { method: "POST" }).catch(() => {});
    Jobs.start("exam-check", String(n));
  };

  let autoSubmitted = false;
  const tick = () => {
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
      h("div", { class: "eyebrow" }, h("a", { href: "#/exams" }, "← exams"), h("span", {}, "/"), h("span", {}, `mock exam ${n}`)),
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
  S.view = () => drawer.dispose();
}

function viewExamBriefing(main, exam) {
  const n = exam.n;
  const snapBox = h("input", { type: "checkbox", id: "snap", checked: true });
  const startBtn = h("button", { class: "btn solid" }, "Start the exam");
  const drawer = jobDrawer({ filter: j => j.target === String(n) || j.target === `before-exam${n}` });
  drawer.style.marginTop = "16px";
  startBtn.onclick = async () => {
    const ok = await dialog({
      title: `Start mock exam ${n}?`,
      body: [p("Setting up the tasks takes a few minutes; some of them break the cluster on purpose. The 120-minute clock starts when setup finishes."),
        snapBox.checked ? p("First the cluster is snapshotted as ", code(`before-exam${n}`), ", which stops the nodes for about three minutes.") : null],
      confirm: "Start",
    });
    if (!ok) return;
    startBtn.disabled = true;
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
    h("div", { class: "eyebrow" }, h("a", { href: "#/exams" }, "← exams"), h("span", {}, "/"), h("span", {}, `mock exam ${n}`)),
    h("h1", { class: "page-title" }, exam.title.replace(/^CKA /, "")),
    h("div", { class: "briefing" },
      h("div", {}, renderMarkdown(exam.readme)),
      h("aside", { class: "side" },
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

function viewExamResults(main, exam) {
  const n = exam.n;
  const r = exam.result;
  const rows = [];
  for (const t of exam.task_list) {
    const f = t.result && t.result.total ? t.result.pass / t.result.total : 0;
    const detail = h("tr", { class: "hidden" }, h("td", { colspan: 6 }, resultsView(t.result)));
    rows.push(h("tr", { class: "clickable", onclick: () => detail.classList.toggle("hidden") },
      h("td", { class: "n" }, t.id.slice(0, 2)),
      h("td", {}, t.title),
      h("td", { class: "muted" }, shortDomain(t.domain)),
      h("td", { class: "n" }, t.result ? `${t.result.pass}/${t.result.total}` : "—"),
      h("td", { class: "n" }, `${t.weight}%`),
      h("td", { class: "n", style: { color: f === 1 ? "var(--pass)" : f === 0 ? "var(--fail)" : "" } }, `${(t.weight * f).toFixed(1)}%`)), detail);
  }
  const drawer = jobDrawer({ filter: j => j.target === String(n), onEnd: () => route() });
  const busy = () => !!S.jobs.current;
  main.replaceChildren(h("div", { class: "page" }, h("div", { class: "wrap" },
    h("div", { class: "eyebrow" }, h("a", { href: "#/exams" }, "← exams"), h("span", {}, "/"), h("span", {}, `mock exam ${n}`)),
    h("section", { class: "masthead", style: { marginTop: "14px" } },
      h("div", {}, h("h1", {}, r ? (r.passed ? "Passed." : "Not this time.") : "Graded."),
        h("p", {}, r ? `Pass mark ${r.pass_mark}%. Graded ${ago(r.at)}. Click a task to see which checks failed.` : "")),
      h("div", {}, h("div", { class: "stat-label" }, "Score"), h("div", { class: "stat", style: { color: r && r.passed ? "var(--pass)" : "var(--fail)" } }, r ? r.score : "—", h("small", {}, " %"))),
      h("div", {}, h("div", { class: "stat-label" }, "Tasks fully solved"), h("div", { class: "stat" },
        exam.task_list.filter(t => t.result && t.result.pass === t.result.total).length, h("small", {}, ` / ${exam.task_list.length}`))),
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
    h("table", { class: "result-table" },
      h("thead", {}, h("tr", {}, h("th", {}, "#"), h("th", {}, "Task"), h("th", {}, "Domain"), h("th", { style: { textAlign: "right" } }, "Checks"), h("th", { style: { textAlign: "right" } }, "Weight"), h("th", { style: { textAlign: "right" } }, "Earned"))),
      h("tbody", {}, rows)),
    drawer)));
  S.view = () => drawer.dispose();
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
      h("td", { class: "m" }, s.complete ? `all ${s.vms.length}` : h("span", { style: { color: "var(--warn)" } }, `${s.vms.length}/${r.vm_count}`)),
      h("td", { style: { textAlign: "right", whiteSpace: "nowrap" } },
        s.name === "base" ? null : h("button", { class: "btn sm quiet", disabled: busy, onclick: () => deleteSnap(s.name) }, "Delete"), " ",
        h("button", { class: "btn sm danger", disabled: busy || !s.complete, onclick: () => resetTo(s.name) }, "Reset to this")))));
    if (!r.snapshots.length) snaps.append(h("tr", {}, h("td", { colspan: 4, class: "muted" }, "No snapshots.")));
  };

  const resetTo = async name => {
    const ok = await dialog({
      title: `Reset everything to "${name}"?`,
      body: [p("Every lab VM, including the jump host, rolls back. All work since that snapshot is lost: cluster state, files, lab progress and open shells."),
        p("This page disconnects and reconnects by itself in a minute or two."),
        p("Type the snapshot name to confirm.")],
      confirm: "Reset", danger: true, typed: name,
    });
    if (!ok) return;
    const j = await Jobs.start("reset", name);
    if (j) waitForReturn(`Rolling back to ${name}`);
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
      body: [p("The five Kubernetes nodes and the NFS server shut down so etcd is captured consistently across all three members, then start again. Allow about three minutes."),
        p("An existing snapshot with this name is replaced.")],
      confirm: "Take snapshot",
    });
    if (ok && await Jobs.start("snapshot", name)) nameField.value = "";
  };

  const drawJobs = () => jobsList.replaceChildren(...(S.jobs.recent || []).slice(0, 8).map(j => h("div", { class: "check " + (j.code === 0 ? "ok" : j.ended ? "no" : "") },
    h("span", { class: "v" }, j.ended == null ? "…" : j.code === 0 ? "OK" : `E${j.code}`),
    h("span", {}, h("a", { href: "#/cluster", class: "mono", onclick: e => { e.preventDefault(); showJobDialog(j); } }, j.label), h("span", { class: "muted" }, ` · ${ago(j.started)}`)))));

  main.replaceChildren(h("div", { class: "page" }, h("div", { class: "wrap" },
    h("div", { class: "section-head", style: { marginTop: 0 } }, h("h2", {}, "Machines"), h("span", { class: "grow" }),
      h("span", { class: "muted", style: { fontSize: "13px" } }, "Proxmox power state and Kubernetes node status, refreshed every 10 s")),
    h("table", { class: "rack" },
      h("thead", {}, h("tr", {}, ["VM", "ID", "Address", "Size", "Power", "Kubernetes"].map(t => h("th", {}, t)))), rack),
    h("div", { class: "section-head" }, h("h2", {}, "Snapshots")),
    h("div", { class: "callout" }, h("b", {}, "Snapshots are your undo button. "),
      "Take one before any lab that changes nodes or the control plane (01–08, 27, 28 and the mock exams). ",
      h("span", { class: "mono" }, "base"), " is bare Ubuntu: resetting to it starts the whole course over."),
    snapNote,
    h("table", { class: "rack" },
      h("thead", {}, h("tr", {}, ["Name", "Taken", "VMs", ""].map(t => h("th", {}, t)))), snaps),
    h("div", { class: "inline-form" }, nameField, takeBtn),
    drawer,
    h("div", { class: "section-head" }, h("h2", {}, "Recent jobs")),
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
  theme();
  const h0 = await fetch("/api/health", { cache: "no-store" }).then(r => r.json()).catch(() => ({ authed: false }));
  if (!h0.authed) { showLogin(); return; }
  $("#app").replaceChildren(renderTop(), h("main", { id: "main", style: { flex: "1", display: "flex", flexDirection: "column", minHeight: "0" } }));
  theme();
  await Jobs.sync();
  pollCluster();
  if (!S.polling) S.polling = setInterval(pollCluster, 20000);
  route();
}

window.addEventListener("hashchange", route);
window.addEventListener("resize", () => Terms.fit());
boot();
