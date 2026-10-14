#!/usr/bin/env python3
"""
HelmYard — Complete Brand Kit & Claude Code Context Packager
Run: python3 setup_brandkit.py
Outputs:
  1. ./brandkit/ (Full unpacked directory tree ready for repo use)
  2. ./CLAUDE.md (Brand & UI context instructions for Claude Code)
  3. ./helmyard_claude_code_brandkit.zip (Complete portable archive)
"""

import os
import json
import shutil
import zipfile

OUT_DIR = "helmyard_brandkit_claude"
DIRS = [
    "01_Brand_Guidelines",
    "02_Logos/Vector_SVG",
    "02_Logos/Raster_PNG",
    "03_Icons_and_Favicons",
    "04_Color_System_and_Tokens",
    "05_Web_and_Social_Templates",
]

for d in DIRS:
    os.makedirs(os.path.join(OUT_DIR, d), exist_ok=True)

# 1. CLAUDE.md — AI Coding Agent Context File
CLAUDE_MD = """# CLAUDE.md — HelmYard Brand & UI System Context

## Project Identity
- **Name:** HelmYard
- **Tagline:** Kubernetes Playgrounds / Self-Hosted Kubernetes Sandbox
- **Visual Metaphor:** Nautical Helm (Kubernetes steering & Helm charts) + Shipyard/Playground (safe local homelab experimentation).

## Strict Color System (Always use CSS variables or Tailwind tokens)
- **Night Navy (Primary Dark Background):** `#0E1E38` (`rgb(14, 30, 56)`) -> `--hy-bg-canvas` / `bg-helmyard-navy`
- **Deep Surface (Cards / Modals / Sidebars):** `#162B4D` (`rgb(22, 43, 77)`) -> `--hy-bg-surface` / `bg-helmyard-surface`
- **Kube Blue (Primary Brand / Helm / Active Borders / Buttons):** `#326CE5` (`rgb(50, 108, 229)`) -> `--hy-color-primary` / `text-helmyard-blue`
- **Playground Orange ("Yard" Accent / Primary CTAs / Warnings):** `#FF8E3C` (`rgb(255, 142, 60)`) -> `--hy-color-accent` / `text-helmyard-orange`
- **Lively Teal (Healthy Cluster / Running Pods / Success):** `#1CD1A1` (`rgb(28, 209, 161)`) -> `--hy-color-success` / `text-helmyard-teal`
- **Cloud White (Primary Text):** `#FFFFFF` -> `--hy-text-primary`
- **Slate Gray (Muted Text / Borders / Timestamps):** `#8A99AD` -> `--hy-text-secondary`

## Accessibility & UI Guardrails for Claude Code
1. **Dark-First UI:** Default all dashboards, terminal views, and docs to Night Navy (`#0E1E38`) background with Cloud White (`#FFFFFF`) text.
2. **Contrast Rule:** Never place small Kube Blue (`#326CE5`) text directly on Night Navy (`#0E1E38`) (contrast is 3.52:1). Use `#326CE5` for button backgrounds with `#FFFFFF` text, or use `#FF8E3C` / `#1CD1A1` / `#FFFFFF` for text on dark navy.
3. **Wordmark Styling:** Whenever rendering the brand name in HTML/JSX, style **"Helm"** in `#FFFFFF` (or `#0E1E38` on light backgrounds) and **"Yard"** in `#FF8E3C` (`font-extrabold tracking-tight`).
4. **Typography:**
   - UI / Display: `'Inter', 'Aptos', system-ui, -apple-system, sans-serif`
   - Code / YAML / Logs: `'JetBrains Mono', 'Fira Code', monospace`

## Brand Asset Paths
- Vector Logos: `02_Logos/Vector_SVG/`
- High-Res Raster Badges: `02_Logos/Raster_PNG/`
- Favicons & App Icons: `03_Icons_and_Favicons/`
- CSS / SCSS / Tailwind / W3C Tokens: `04_Color_System_and_Tokens/`
"""

with open(os.path.join(OUT_DIR, "CLAUDE.md"), "w", encoding="utf-8") as f:
    f.write(CLAUDE_MD)
with open(os.path.join(OUT_DIR, "01_Brand_Guidelines/BRAND_GUIDELINES.md"), "w", encoding="utf-8") as f:
    f.write(CLAUDE_MD)

# 2. Vector SVG Assets (Logos, Badges, Icons, System Glyphs)
SVGS = {
    "02_Logos/Vector_SVG/helmyard_lockup_dark_bg.svg": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 520 150" width="520" height="150">
  <rect width="100%" height="100%" fill="#0E1E38" rx="16"/>
  <text x="260" y="76" text-anchor="middle" font-family="'Inter', 'Aptos', system-ui, sans-serif" font-weight="800" font-size="56" letter-spacing="-1">
    <tspan fill="#FFFFFF">Helm</tspan><tspan fill="#FF8E3C">Yard</tspan>
  </text>
  <text x="260" y="110" text-anchor="middle" font-family="'Inter', 'Aptos', system-ui, sans-serif" font-weight="700" font-size="15" letter-spacing="4.5" fill="#8A99AD">
    KUBERNETES PLAYGROUNDS
  </text>
</svg>""",

    "02_Logos/Vector_SVG/helmyard_lockup_light_bg.svg": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 520 150" width="520" height="150">
  <rect width="100%" height="100%" fill="#F8FAFC" rx="16" stroke="#E2E8F0" stroke-width="2"/>
  <text x="260" y="76" text-anchor="middle" font-family="'Inter', 'Aptos', system-ui, sans-serif" font-weight="800" font-size="56" letter-spacing="-1">
    <tspan fill="#0E1E38">Helm</tspan><tspan fill="#FF8E3C">Yard</tspan>
  </text>
  <text x="260" y="110" text-anchor="middle" font-family="'Inter', 'Aptos', system-ui, sans-serif" font-weight="700" font-size="15" letter-spacing="4.5" fill="#326CE5">
    KUBERNETES PLAYGROUNDS
  </text>
</svg>""",

    "02_Logos/Vector_SVG/helmyard_lockup_trans_dk.svg": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 520 150" width="520" height="150">
  <text x="260" y="76" text-anchor="middle" font-family="'Inter', 'Aptos', system-ui, sans-serif" font-weight="800" font-size="56" letter-spacing="-1">
    <tspan fill="#FFFFFF">Helm</tspan><tspan fill="#FF8E3C">Yard</tspan>
  </text>
  <text x="260" y="110" text-anchor="middle" font-family="'Inter', 'Aptos', system-ui, sans-serif" font-weight="700" font-size="15" letter-spacing="4.5" fill="#8A99AD">
    KUBERNETES PLAYGROUNDS
  </text>
</svg>""",

    "02_Logos/Vector_SVG/helmyard_lockup_trans_lt.svg": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 520 150" width="520" height="150">
  <text x="260" y="76" text-anchor="middle" font-family="'Inter', 'Aptos', system-ui, sans-serif" font-weight="800" font-size="56" letter-spacing="-1">
    <tspan fill="#0E1E38">Helm</tspan><tspan fill="#FF8E3C">Yard</tspan>
  </text>
  <text x="260" y="110" text-anchor="middle" font-family="'Inter', 'Aptos', system-ui, sans-serif" font-weight="700" font-size="15" letter-spacing="4.5" fill="#326CE5">
    KUBERNETES PLAYGROUNDS
  </text>
</svg>""",

    "02_Logos/Vector_SVG/helmyard_monochrome_white.svg": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 520 150" width="520" height="150">
  <text x="260" y="76" text-anchor="middle" font-family="'Inter', 'Aptos', system-ui, sans-serif" font-weight="800" font-size="56" letter-spacing="-1" fill="#FFFFFF">HelmYard</text>
  <text x="260" y="110" text-anchor="middle" font-family="'Inter', 'Aptos', system-ui, sans-serif" font-weight="700" font-size="15" letter-spacing="4.5" fill="#FFFFFF" opacity="0.8">KUBERNETES PLAYGROUNDS</text>
</svg>""",

    "02_Logos/Vector_SVG/helmyard_monochrome_black.svg": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 520 150" width="520" height="150">
  <text x="260" y="76" text-anchor="middle" font-family="'Inter', 'Aptos', system-ui, sans-serif" font-weight="800" font-size="56" letter-spacing="-1" fill="#000000">HelmYard</text>
  <text x="260" y="110" text-anchor="middle" font-family="'Inter', 'Aptos', system-ui, sans-serif" font-weight="700" font-size="15" letter-spacing="4.5" fill="#000000" opacity="0.75">KUBERNETES PLAYGROUNDS</text>
</svg>""",

    "03_Icons_and_Favicons/favicon.svg": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" width="128" height="128">
  <rect width="128" height="128" rx="28" fill="#0E1E38"/>
  <circle cx="64" cy="64" r="42" fill="none" stroke="#326CE5" stroke-width="7"/>
  <line x1="64" y1="12" x2="64" y2="116" stroke="#326CE5" stroke-width="5" stroke-linecap="round"/>
  <line x1="12" y1="64" x2="116" y2="64" stroke="#326CE5" stroke-width="5" stroke-linecap="round"/>
  <line x1="27" y1="27" x2="101" y2="101" stroke="#326CE5" stroke-width="5" stroke-linecap="round"/>
  <line x1="27" y1="101" x2="101" y2="27" stroke="#326CE5" stroke-width="5" stroke-linecap="round"/>
  <polygon points="64,34 38,52 90,52" fill="#FF8E3C"/>
  <rect x="44" y="50" width="40" height="36" rx="5" fill="#1B3B6F" stroke="#FF8E3C" stroke-width="3"/>
  <rect x="49" y="56" width="30" height="7" rx="2" fill="#FFFFFF"/>
  <circle cx="74" cy="59.5" r="2" fill="#1CD1A1"/>
  <rect x="49" y="67" width="30" height="7" rx="2" fill="#FFFFFF"/>
  <circle cx="74" cy="70.5" r="2" fill="#1CD1A1"/>
  <rect x="49" y="78" width="30" height="4" rx="1.5" fill="#326CE5"/>
</svg>"""
}

for path, svg in SVGS.items():
    with open(os.path.join(OUT_DIR, path), "w", encoding="utf-8") as f:
        f.write(svg)

# 3. Design Tokens (W3C, CSS, SCSS, Tailwind)
W3C_TOKENS = {
    "helmyard": {
        "color": {
            "night-navy": {"$value": "#0E1E38", "$type": "color"},
            "deep-surface": {"$value": "#162B4D", "$type": "color"},
            "kube-blue": {"$value": "#326CE5", "$type": "color"},
            "playground-orange": {"$value": "#FF8E3C", "$type": "color"},
            "lively-teal": {"$value": "#1CD1A1", "$type": "color"},
            "cloud-white": {"$value": "#FFFFFF", "$type": "color"},
            "slate-gray": {"$value": "#8A99AD", "$type": "color"}
        }
    }
}
with open(os.path.join(OUT_DIR, "04_Color_System_and_Tokens/tokens.w3c.json"), "w") as f:
    json.dump(W3C_TOKENS, f, indent=2)

CSS_VARS = """:root, [data-theme="dark"] {
  --hy-bg-canvas: #0E1E38;
  --hy-bg-surface: #162B4D;
  --hy-color-primary: #326CE5;
  --hy-color-accent: #FF8E3C;
  --hy-color-success: #1CD1A1;
  --hy-text-primary: #FFFFFF;
  --hy-text-secondary: #8A99AD;
  --hy-font-sans: 'Inter', 'Aptos', system-ui, -apple-system, sans-serif;
  --hy-font-mono: 'JetBrains Mono', 'Fira Code', monospace;
}
[data-theme="light"] {
  --hy-bg-canvas: #F8FAFC;
  --hy-bg-surface: #FFFFFF;
  --hy-color-primary: #326CE5;
  --hy-color-accent: #E87420;
  --hy-color-success: #0FA97F;
  --hy-text-primary: #0E1E38;
  --hy-text-secondary: #475569;
}
"""
with open(os.path.join(OUT_DIR, "04_Color_System_and_Tokens/variables.css"), "w") as f:
    f.write(CSS_VARS)

TAILWIND_CFG = """module.exports = {
  theme: {
    extend: {
      colors: {
        helmyard: {
          navy: '#0E1E38',
          surface: '#162B4D',
          blue: '#326CE5',
          orange: '#FF8E3C',
          teal: '#1CD1A1',
          white: '#FFFFFF',
          slate: '#8A99AD',
        }
      },
      fontFamily: {
        sans: ['Inter', 'Aptos', 'system-ui', 'sans-serif'],
        mono: ['JetBrains Mono', 'Fira Code', 'monospace'],
      }
    }
  }
};
"""
with open(os.path.join(OUT_DIR, "04_Color_System_and_Tokens/tailwind.config.js"), "w") as f:
    f.write(TAILWIND_CFG)

# 4. Copy any existing raster PNGs from an unpacked helmyard_full_brandkit.zip if present
raster_mappings = {
    "guidelines/brandkit_overview.png": "01_Brand_Guidelines/brandkit_master_board.png",
    "logos/helmyard_primary_badge_full.png": "02_Logos/Raster_PNG/helmyard_primary_badge.png",
    "logos/helmyard_mascot_emblem.png": "02_Logos/Raster_PNG/helmyard_mascot_emblem.png",
    "logos/helmyard_wordmark_lockup.png": "02_Logos/Raster_PNG/helmyard_wordmark_lockup.png",
    "icons/app_icon_round.png": "03_Icons_and_Favicons/social_avatar_round.png",
    "icons/app_icon_square.png": "03_Icons_and_Favicons/app_launcher_squircle.png",
}
for src, dst in raster_mappings.items():
    if os.path.exists(src):
        shutil.copy2(src, os.path.join(OUT_DIR, dst))

# 5. Zip everything for portable distribution
zip_filename = "helmyard_claude_code_brandkit.zip"
with zipfile.ZipFile(zip_filename, "w", zipfile.ZIP_DEFLATED) as zf:
    for root, _, files in os.walk(OUT_DIR):
        for file in sorted(files):
            full_path = os.path.join(root, file)
            rel_path = os.path.relpath(full_path, OUT_DIR)
            zf.write(full_path, rel_path)

print(f"Created {zip_filename} and unpacked directory {OUT_DIR}/")
