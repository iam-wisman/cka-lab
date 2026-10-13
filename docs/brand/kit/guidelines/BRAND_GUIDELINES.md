# HelmYard — Brand Kit & Identity Guidelines

**Tagline:** _Kubernetes Playgrounds / Self-Hosted Kubernetes Sandbox_

---

## 1. Brand Concept & Story

- **Helm:** The nautical helm (steering wheel) referencing Kubernetes orchestration and direct steering of workloads, paired with the Helm package manager ecosystem.
- **Yard:** A shipyard (where components are built and tested) and a playground/backyard (safe sandbox environment for trial, error, and experimentation).

---

## 2. Color Palette

| Name                  | Hex       | RGB             | Description                                        |
| :-------------------- | :-------- | :-------------- | :------------------------------------------------- |
| **Night Navy**        | `#0E1E38` | `14, 30, 56`    | Core dark canvas / terminal background             |
| **Kube Blue**         | `#326CE5` | `50, 108, 229`  | Helm steering wheel, key UI buttons, links         |
| **Playground Orange** | `#FF8E3C` | `255, 142, 60`  | Accent brand highlight ('Yard'), playful CTAs      |
| **Lively Teal**       | `#1CD1A1` | `28, 209, 161`  | Healthy cluster states, cluster pods, green checks |
| **Cloud White**       | `#FFFFFF` | `255, 255, 255` | Primary text and bright glyphs                     |
| **Slate Gray**        | `#8A99AD` | `138, 153, 173` | Secondary labels, subheadings, muted borders       |

---

## 3. Typography Recommendations

- **Primary Display / UI Font:** Inter, Aptos, or SF Pro Display (Bold / ExtraBold for **Helm** and **Yard**).
- **Technical / Code Font:** JetBrains Mono or Fira Code for manifests, pods, and terminal logs.

---

## 4. Asset Directory Map

- `/logos/`
  - `helmyard_primary_badge_full.png` — Full high-res illustration logo badge
  - `helmyard_mascot_emblem.png` — Central helm & homelab server icon
  - `helmyard_wordmark_lockup.png` — Extracted horizontal logo lockup
  - `helmyard_wordmark.svg` — Scalable vector logo lockup (dark background)
  - `helmyard_wordmark_transparent.svg` — Transparent vector logo lockup
- `/icons/`
  - `app_icon_square.png` — Square app / dashboard icon
  - `app_icon_round.png` — Circular avatar for GitHub, Discord, Twitter/X
  - `favicon.svg` — Scalable vector favicon for web dashboards
- `/palettes/`
  - `colors.json` — Machine-readable color definitions for config scripts
  - `brand_tokens.css` — Ready-to-import CSS variables
- `/guidelines/`
  - `brandkit_overview.png` — Complete master brandkit visual board
  - `BRAND_GUIDELINES.md` — This identity reference guide
