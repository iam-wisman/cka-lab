#!/usr/bin/env python3
"""HelmYard brand kit: a ship's wheel (the helm) around a small server house (the
yard), redrawn as SVG from the logo artwork so it stays sharp at any size.

  python3 docs/brand/build.py      writes the SVGs here and copies the web ones to lab/web/static/brand/

The official kit (palette, tokens, wordmarks, favicon, guidelines) is in kit/; the
favicon there is used as is.
"""
import math, os, shutil

here = os.path.dirname(os.path.abspath(__file__))
web = os.path.join(here, "..", "..", "lab", "web", "static", "brand")

# Official palette: docs/brand/kit/04_Color_System_and_Tokens/tokens.w3c.json
ORANGE, GREEN, NAVY = "#FF8E3C", "#1CD1A1", "#0E1E38"
VARIANTS = {   # wheel, wheel shade, hub, dots
    "color":   ("#326CE5", "#2554b8", "#fff7ec", ("#fff7ec", ORANGE)),
    "reverse": ("#ffffff", "#dbe6ff", "#fff7ec", ("#326ce5", ORANGE)),
}


def mark(variant, standalone=True, x=0, y=0, size=120):
    wheel, shade, hub, dots = VARIANTS[variant]
    c = 60
    pol = lambda r, a: (c + r * math.cos(math.radians(a - 90)), c + r * math.sin(math.radians(a - 90)))
    spokes = "".join('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f"/>' % (*pol(13, a), *pol(50, a)) for a in range(0, 360, 45))
    knobs = "".join('<circle cx="%.1f" cy="%.1f" r="5.2"/>' % pol(52, a) for a in range(45, 360, 45))
    ring = "".join('<circle cx="%.1f" cy="%.1f" r="1.9" fill="%s"/>' % (*pol(33, a), dots[i % 2]) for i, a in enumerate(range(22, 360, 45)))
    fx, fy = pol(52, 0)
    body = f'''<g stroke="{wheel}" stroke-width="6.5" stroke-linecap="round">{spokes}</g>
  <g fill="{wheel}">{knobs}</g>
  <path d="M{fx:.1f} {fy + 3:.1f}V{fy - 11:.1f}" stroke="{shade}" stroke-width="2.4" stroke-linecap="round"/>
  <path d="M{fx + 1:.1f} {fy - 11:.1f}l9 3.2-9 3.4z" fill="{ORANGE}"/>
  <circle cx="{c}" cy="{c}" r="33" fill="none" stroke="{wheel}" stroke-width="10"/>
  <circle cx="{c}" cy="{c}" r="33" fill="none" stroke="{shade}" stroke-width="1.2" opacity=".5"/>
  {ring}
  <circle cx="{c}" cy="{c}" r="22" fill="{hub}"/>
  <path d="M{c - 15} {c - 1}L{c} {c - 14}L{c + 15} {c - 1}" fill="none" stroke="{ORANGE}" stroke-width="4.4" stroke-linecap="round" stroke-linejoin="round"/>
  <rect x="{c - 10}" y="{c - 2}" width="20" height="16" rx="2.6" fill="#33415c"/>
  <rect x="{c - 7}" y="{c + 1}" width="14" height="4" rx="1.2" fill="#4c5d80"/>
  <rect x="{c - 7}" y="{c + 7}" width="14" height="4" rx="1.2" fill="#4c5d80"/>
  <circle cx="{c + 4.3}" cy="{c + 3}" r="1.1" fill="{GREEN}"/><circle cx="{c + 4.3}" cy="{c + 9}" r="1.1" fill="{ORANGE}"/>'''
    if standalone:
        return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="-2 -10 124 132" role="img" aria-label="HelmYard">\n  {body}\n</svg>\n'
    return f'<g transform="translate({x} {y}) scale({size / 132:.4f}) translate(2 10)">{body}</g>'


def banner():
    """The lockup on the logo's navy: mark above the HelmYard wordmark and the tagline."""
    font = "Nunito, 'Arial Rounded MT Bold', 'Open Sans', Arial, sans-serif"
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 960 390" role="img" aria-label="HelmYard: Kubernetes Playgrounds">
  <rect width="960" height="390" rx="18" fill="{NAVY}"/>
  {mark("color", False, 375, 18, 210)}
  <text x="480" y="300" text-anchor="middle" font-family="{font}" font-size="86" font-weight="800"><tspan fill="#ffffff">Helm</tspan><tspan fill="{ORANGE}">Yard</tspan></text>
  <text x="480" y="348" text-anchor="middle" font-family="{font}" font-size="26" font-weight="700" letter-spacing="4" fill="#8A99AD">KUBERNETES PLAYGROUNDS</text>
</svg>
'''


files = {"helmyard-mark.svg": mark("color"), "helmyard-mark-reverse.svg": mark("reverse"), "helmyard-banner.svg": banner()}
for name, svg in files.items():
    open(os.path.join(here, name), "w").write(svg)
os.makedirs(web, exist_ok=True)
for name in ("helmyard-mark.svg", "helmyard-mark-reverse.svg"):
    shutil.copy(os.path.join(here, name), os.path.join(web, name))
print("wrote", ", ".join(files), "and the web copies")
