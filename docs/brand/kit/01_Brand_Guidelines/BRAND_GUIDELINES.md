# CLAUDE.md — HelmYard Brand & UI System Context

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
