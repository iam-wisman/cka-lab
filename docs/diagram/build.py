#!/usr/bin/env python3
"""Build docs/architecture.svg from the icons in docs/diagram/icons.

Every icon is inlined as a nested <svg> (ids prefixed per instance so their
gradients/clips can't collide), so the result is one self-contained file that
GitHub renders without fetching anything.

    python3 docs/diagram/build.py
"""
import os, re, itertools

HERE = os.path.dirname(os.path.abspath(__file__))
ICONS = os.path.join(HERE, "icons")
OUT = os.path.join(HERE, "..", "architecture.svg")

# Brand colours for monochrome logos (Simple Icons ship them black).
TINT = {"proxmox": "#E57000", "ubuntu": "#E95420", "containerd": "#575757"}

_seq = itertools.count()

def icon(name, x, y, size, h=None):
    """Inline icons/<name>.svg at (x, y), fitted into size x h (default square)."""
    raw = open(os.path.join(ICONS, name + ".svg"), encoding="utf-8").read()
    raw = re.sub(r"<\?xml.*?\?>|<!DOCTYPE.*?>|<!--.*?-->", "", raw, flags=re.S)
    # Editor metadata (Inkscape/Sodipodi/RDF) is invisible and its namespaces
    # aren't declared once the icon is inlined: drop it.
    raw = re.sub(r"<metadata\b.*?</metadata>", "", raw, flags=re.S)
    raw = re.sub(r"<(sodipodi|inkscape):[\w-]+\b[^>]*/>", "", raw, flags=re.S)
    raw = re.sub(r"<(sodipodi|inkscape):([\w-]+)\b.*?</\1:\2>", "", raw, flags=re.S)
    raw = re.sub(r'\s(?:inkscape|sodipodi|rdf|cc|dc|xmlns:\w+):[\w-]+="[^"]*"', "", raw)
    raw = re.sub(r'\sxmlns:\w+="[^"]*"', "", raw)
    m = re.search(r"<svg\b([^>]*)>(.*)</svg>", raw, re.S)
    attrs, body = m.group(1), m.group(2)
    vb = re.search(r'viewBox="([^"]+)"', attrs)
    if vb:
        viewbox = vb.group(1)
    else:
        w = float(re.search(r'width="([\d.]+)', attrs).group(1))
        hh = float(re.search(r'height="([\d.]+)', attrs).group(1))
        viewbox = f"0 0 {w} {hh}"
    p = f"i{next(_seq)}-"
    ids = set(re.findall(r'\bid="([^"]+)"', body))
    for i in sorted(ids, key=len, reverse=True):
        body = re.sub(rf'\bid="{re.escape(i)}"', f'id="{p}{i}"', body)
        body = re.sub(rf"url\(#{re.escape(i)}\)", f"url(#{p}{i})", body)
        body = re.sub(rf'href="#{re.escape(i)}"', f'href="#{p}{i}"', body)
    # class-based <style> blocks would leak across icons: scope them by prefixing classes
    classes = set(re.findall(r'class="([^"]+)"', body))
    for c in classes:
        for cc in c.split():
            body = re.sub(rf"\.{re.escape(cc)}\b(?=[^\w-])", f".{p}{cc}", body)
    body = re.sub(r'class="([^"]+)"', lambda mm: 'class="' + " ".join(p + c for c in mm.group(1).split()) + '"', body)
    fill = f' fill="{TINT[name]}"' if name in TINT else ""
    return (f'<svg x="{x}" y="{y}" width="{size}" height="{h or size}" viewBox="{viewbox}"'
            f' preserveAspectRatio="xMidYMid meet"{fill}>{body}</svg>')

def text(x, y, s, size=13, weight=400, color="#1f2937", anchor="start", family=None, extra=""):
    fam = family or "Inter, 'Segoe UI', Helvetica, Arial, sans-serif"
    s = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    return (f'<text x="{x}" y="{y}" font-family="{fam}" font-size="{size}" font-weight="{weight}"'
            f' fill="{color}" text-anchor="{anchor}"{extra}>{s}</text>')

MONO = "'JetBrains Mono', 'SFMono-Regular', Menlo, Consolas, monospace"

def box(x, y, w, h, fill="#ffffff", stroke="#d0d7de", r=12, dash=None, sw=1.5, shadow=False):
    d = f' stroke-dasharray="{dash}"' if dash else ""
    f = ' filter="url(#shadow)"' if shadow else ""
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"{d}{f}/>'

def pill(x, y, label, color="#326ce5", w=None, fg="#ffffff", size=11):
    w = w or (len(label) * 6.6 + 18)
    return (box(x, y, w, 20, fill=color, stroke=color, r=10, sw=1)
            + text(x + w / 2, y + 14, label, size=size, weight=600, color=fg, anchor="middle")), w

def line(x1, y1, x2, y2, color="#326ce5", w=2, dash=None, arrow=True):
    d = f' stroke-dasharray="{dash}"' if dash else ""
    a = ' marker-end="url(#arrow)"' if arrow else ""
    return f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" stroke-width="{w}"{d}{a}/>'

def path(d, color="#326ce5", w=2, dash=None, arrow=True):
    ds = f' stroke-dasharray="{dash}"' if dash else ""
    a = ' marker-end="url(#arrow)"' if arrow else ""
    return f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{w}"{ds}{a}/>'

W, H = 1480, 980
K8S_BLUE, INK, MUTED = "#326ce5", "#1f2937", "#57606a"
out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" role="img" aria-labelledby="title desc">',
       '<title id="title">CKA lab architecture</title>',
       '<desc id="desc">A Proxmox host running a jump host on the home LAN and an isolated network with three '
       'stacked control-plane nodes, two workers and an NFS server, plus the cluster add-ons installed in the labs.</desc>',
       f'''<defs>
  <filter id="shadow" x="-5%" y="-5%" width="110%" height="120%"><feDropShadow dx="0" dy="2" stdDeviation="3" flood-color="#0f172a" flood-opacity="0.10"/></filter>
  <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="{K8S_BLUE}"/></marker>
  <marker id="arrow-grey" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#8c959f"/></marker>
  <marker id="arrow-orange" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#E57000"/></marker>
</defs>''',
       box(0, 0, W, H, fill="#f6f8fa", stroke="#f6f8fa", r=18)]

# ---- title -------------------------------------------------------------------
out.append(icon("kubernetes", 40, 30, 46))
out.append(text(98, 56, "CKA Lab: highly available Kubernetes v1.35 on Proxmox", 24, 700, INK))
out.append(text(98, 80, "kubeadm · 3 stacked control planes · 2 workers · isolated lab network · auto-graded labs", 14, 400, MUTED))

# ---- laptop ------------------------------------------------------------------
out.append(box(40, 130, 200, 120, shadow=True))
out.append('<g fill="none" stroke="#57606a" stroke-width="3" stroke-linejoin="round">'
           '<rect x="102" y="150" width="76" height="48" rx="4"/><path d="M90 208 h100 l-8 10 h-84 z"/></g>')
out.append(text(140, 236, "Your laptop", 14, 600, INK, "middle"))

# ---- Proxmox host ------------------------------------------------------------
PX, PY, PW, PH = 290, 110, 1150, 820
out.append(box(PX, PY, PW, PH, fill="#ffffff", stroke="#E57000", r=16, sw=2, shadow=True))
out.append(icon("proxmox", PX + 20, PY + 16, 30))
out.append(text(PX + 60, PY + 38, "Proxmox VE host", 17, 700, INK))
out.append(text(PX + PW - 20, PY + 38, "local-lvm thin pool · cloud-init · per-VM snapshots", 12, 400, MUTED, "end"))

# vmbr0 band (LAN) with the jump host
out.append(box(PX + 20, PY + 60, 300, PH - 80, fill="#fff8f2", stroke="#f0c7a0", r=12, dash="6 4"))
out.append(text(PX + 36, PY + 84, "vmbr0 · home LAN", 13, 700, "#9a4a00"))
out.append(text(PX + 36, PY + 101, "only the jump host is attached", 11, 400, "#9a4a00"))

JX, JY, JW, JH = PX + 40, PY + 125, 260, 372
out.append(box(JX, JY, JW, JH, shadow=True))
out.append(icon("ubuntu", JX + 16, JY + 16, 28))
out.append(text(JX + 54, JY + 36, "jump", 17, 700, INK))
out.append(text(JX + JW - 16, JY + 36, "VM 200", 11, 500, MUTED, "end"))
out.append(text(JX + 16, JY + 62, "LAN (DHCP) + 10.10.10.10", 12, 400, MUTED, family=MONO))
rows = [("HAProxy", "k8s-api.cka.lab:6443 → cp1-3", "#106ba3"),
        ("dnsmasq", "DNS for *.cka.lab, corp.internal", "#6f42c1"),
        ("NAT gateway", "lab network → internet", "#1a7f37"),
        ("lab CLI", "start · check · cleanup · exam", K8S_BLUE),
        ("graders", "own kubectl, helm-free", "#57606a")]
for i, (k, v, c) in enumerate(rows):
    yy = JY + 92 + i * 50
    out.append(box(JX + 14, yy, JW - 28, 40, fill="#f6f8fa", stroke="#e5e7eb", r=8, sw=1))
    out.append(f'<rect x="{JX + 14}" y="{yy}" width="5" height="40" rx="2" fill="{c}"/>')
    out.append(text(JX + 28, yy + 17, k, 13, 700, INK))
    out.append(text(JX + 28, yy + 33, v, 11, 400, MUTED))
out.append(text(JX + JW / 2, JY + JH - 14, "ssh <node> · sudo, like the exam", 11, 500, MUTED, "middle"))

# Proxmox API token
out.append(box(JX, JY + JH + 30, JW, 74, fill="#fffaf5", stroke="#f0c7a0", r=10))
out.append(icon("proxmox", JX + 14, JY + JH + 46, 22))
out.append(text(JX + 46, JY + JH + 56, "Scoped API token", 13, 700, INK))
out.append(text(JX + 46, JY + JH + 74, "VM.Snapshot · Rollback · PowerMgmt", 11, 400, MUTED))
out.append(text(JX + 46, JY + JH + 90, "lab snapshot / lab reset, lab VMs only", 11, 400, MUTED))
out.append(line(JX + JW / 2, JY + JH, JX + JW / 2, JY + JH + 28, "#E57000", 2, "4 3", arrow=False).replace('/>', ' marker-end="url(#arrow-orange)"/>'))

# laptop → jump
out.append(path(f"M240 190 C 300 190, {JX - 40} {JY + 60}, {JX - 2} {JY + 60}", K8S_BLUE, 2.5))
out.append(text(140, 276, "ssh -i ~/.ssh/cka-lab student@jump", 11, 600, K8S_BLUE, "middle", family=MONO))

# vmbr1 band (isolated)
LX, LY, LW, LH = PX + 345, PY + 60, PW - 365, PH - 80
out.append(box(LX, LY, LW, LH, fill="#f3f7ff", stroke="#b6cdf7", r=12, dash="6 4"))
out.append(text(LX + 16, LY + 24, "vmbr1 · isolated lab network 10.10.10.0/24", 13, 700, "#1d4ed8"))
out.append(text(LX + LW - 16, LY + 24, "no uplink: everything leaves through jump", 11, 400, "#1d4ed8", "end"))

# control planes
CW, CH, CY = 238, 228, LY + 78
cps = [("cp1", ".11", "zone-a", "VM 201"), ("cp2", ".12", "zone-b", "VM 202"), ("cp3", ".13", "zone-c", "VM 203")]
cx0 = LX + 18
for i, (n, ip, z, vm) in enumerate(cps):
    x = cx0 + i * (CW + 22)
    out.append(box(x, CY, CW, CH, shadow=True))
    out.append(icon("k8s-control-plane", x + 12, CY + 12, 46))
    out.append(text(x + 66, CY + 34, n, 17, 700, INK))
    out.append(text(x + 66, CY + 52, f"10.10.10{ip} · {z}", 11, 400, MUTED, family=MONO))
    out.append(text(x + CW - 12, CY + 30, vm, 11, 500, MUTED, "end"))
    for j, ic in enumerate(["k8s-api", "k8s-etcd", "k8s-sched", "k8s-c-m"]):
        out.append(icon(ic, x + 14 + j * 54, CY + 72, 46))
    out.append(text(x + CW / 2, CY + 140, "static pods · stacked etcd member", 11, 500, MUTED, "middle"))
    out.append(box(x + 14, CY + 154, CW - 28, 58, fill="#f6f8fa", stroke="#e5e7eb", r=8, sw=1))
    out.append(icon("k8s-kubelet", x + 22, CY + 160, 46))
    out.append(icon("containerd", x + 82, CY + 168, 20, 30))
    out.append(text(x + 110, CY + 180, "kubelet · containerd", 11, 600, INK))
    out.append(text(x + 110, CY + 196, "taint: control-plane", 11, 400, MUTED))

# etcd quorum ribbon
ey = CY + CH + 14
out.append(box(cx0, ey, 3 * CW + 44, 32, fill="#e8f0fe", stroke="#b6cdf7", r=16, sw=1))
out.append(icon("etcd", cx0 + 12, ey + 4, 24))
out.append(text(cx0 + 44, ey + 21, "etcd raft cluster · 3 members · quorum 2 · survives the loss of any one control plane", 12, 600, "#1d4ed8"))

# HAProxy → control planes: one bus above the three API servers
bus_y = LY + 52
hy = JY + 92 + 20                      # middle of the HAProxy row
xs = [cx0 + i * (CW + 22) + CW / 2 for i in range(3)]
out.append(path(f"M{JX + JW - 14} {hy} H {LX - 14} V {bus_y} H {xs[-1]}", K8S_BLUE, 2.2, arrow=False))
for x in xs:
    out.append(line(x, bus_y, x, CY - 3, K8S_BLUE, 2.2))
    out.append(f'<circle cx="{x}" cy="{bus_y}" r="3.5" fill="{K8S_BLUE}"/>')
out.append(text(xs[0] + 14, bus_y - 8, "k8s-api.cka.lab:6443 · TLS passthrough · health check GET /readyz", 11, 600, K8S_BLUE))

# workers
WY = ey + 52
WW, WH = 250, 196
for i, (n, ip, z, vm) in enumerate([("worker1", ".21", "zone-a", "VM 204"), ("worker2", ".22", "zone-b", "VM 205")]):
    x = cx0 + i * (WW + 22)
    out.append(box(x, WY, WW, WH, shadow=True))
    out.append(icon("k8s-node", x + 12, WY + 12, 46))
    out.append(text(x + 66, WY + 34, n, 17, 700, INK))
    out.append(text(x + 66, WY + 52, f"10.10.10{ip} · {z}", 11, 400, MUTED, family=MONO))
    out.append(text(x + WW - 12, WY + 30, vm, 11, 500, MUTED, "end"))
    for j, ic in enumerate(["k8s-kubelet", "k8s-k-proxy", "k8s-pod", "k8s-svc"]):
        out.append(icon(ic, x + 14 + j * 56, WY + 74, 48))
    out.append(text(x + 14, WY + 150, "kube-proxy nftables · Calico", 11, 500, MUTED))
    out.append(text(x + 14, WY + 170, "workloads and their Services", 11, 400, MUTED))

# nfs
NX = cx0 + 2 * (WW + 22)
NW = LX + LW - 18 - NX
out.append(box(NX, WY, NW, WH, shadow=True))
out.append(icon("ubuntu", NX + 14, WY + 16, 26))
out.append(text(NX + 48, WY + 34, "nfs", 17, 700, INK))
out.append(text(NX + 48, WY + 52, "10.10.10.30", 11, 400, MUTED, family=MONO))
out.append(text(NX + NW - 12, WY + 30, "VM 206", 11, 500, MUTED, "end"))
out.append('<g transform="translate(%d,%d)">' % (NX + 18, WY + 74) +
           '<ellipse cx="22" cy="6" rx="22" ry="6" fill="#d0d7de"/><rect x="0" y="6" width="44" height="34" fill="#d0d7de"/>'
           '<ellipse cx="22" cy="40" rx="22" ry="6" fill="#afb8c1"/><ellipse cx="22" cy="6" rx="22" ry="6" fill="#eaeef2" stroke="#afb8c1"/></g>')
out.append(icon("k8s-pv", NX + 74, WY + 70, 48))
out.append(text(NX + 14, WY + 150, "raw 60 GB disk → XFS", 11, 500, MUTED))
out.append(text(NX + 14, WY + 170, "NFS 4.1 → CSI volumes", 11, 400, MUTED))

# ---- add-ons -----------------------------------------------------------------
AY = WY + WH + 26
AH = LY + LH - AY - 14
out.append(box(cx0, AY, LW - 36, AH, fill="#ffffff", stroke="#d0d7de", r=10))
out.append(text(cx0 + 16, AY + 24, "Cluster add-ons you install during the labs", 13, 700, INK))
addons = [("calico", "Calico", "CNI · VXLAN"), ("helm", "Helm", "charts"), ("metallb", "MetalLB", "L2 · .200–.220"),
          ("traefik", "Traefik", "Ingress · .201"), ("envoy", "Envoy Gateway", "Gateway API · .202"),
          ("cert-manager", "cert-manager", "CKA root CA"), ("k8s-pv", "csi-driver-nfs", "default SC"),
          ("k8s-hpa", "metrics-server", "kubectl top · HPA")]
step = (LW - 36 - 32) / len(addons)
for i, (ic, name, sub) in enumerate(addons):
    x = cx0 + 16 + i * step
    out.append(icon(ic, x + step / 2 - 24, AY + 40, 48))
    out.append(text(x + step / 2, AY + 106, name, 12, 700, INK, "middle"))
    out.append(text(x + step / 2, AY + 122, sub, 10.5, 400, MUTED, "middle"))

# ---- footer ------------------------------------------------------------------
foot = "cluster domain cka.local · pods 172.16.0.0/16 · services 10.112.0.0/16 · v1.34.12 → v1.35.9 (lab 07)"
out.append(text(PX + PW / 2, H - 22, foot, 12, 500, MUTED, "middle", family=MONO))
out.append(text(40, H - 22, "Icons: Kubernetes community (Apache-2.0), CNCF artwork, Simple Icons (CC0)", 10, 400, "#8c959f"))
out.append("</svg>")

open(OUT, "w", encoding="utf-8").write("\n".join(out) + "\n")
print(f"wrote {os.path.relpath(OUT)} ({os.path.getsize(OUT) // 1024} KiB)")
