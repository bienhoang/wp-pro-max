# WP Pro Max — Product Development Requirements (PDR)

**Status:** Draft v0.1 · 2026-06-26
**Type:** Claude Code Plugin (distributable kit)

## 1. Problem

Building a WordPress site from a static HTML design is slow and error-prone:
hand-cutting templates, picking plugins by trial, registering custom fields,
seeding content/plugin data, and migrating to a host. Each step is manual and
hard to reproduce.

## 2. Goal

A Claude Code **plugin** (`wp-pro-max`) that drives an end-to-end, resumable
pipeline turning static HTML (or a requirements brief) into a production
WordPress site — quickly and accurately.

## 3. Users

- Agency/freelance WP developers converting designs → live sites.
- Claude Code users who want a one-command WordPress build pipeline.

## 4. Pipeline (stages)

Core (requested):
1. **Analyze HTML** — structure, components, repeated patterns, asset inventory, IA.
2. **Optimize HTML** — clean/dedupe markup+CSS, image plan, a11y fixes.
3. **Convert → WP theme** — *adaptive*: Classic PHP+ACF / Block (FSE) / Page Builder.
4. **Select plugins** — recommend per requirements; pin into `.wp-env.json`.
5. **Scaffold WP code** — functions.php, template parts, CPT/taxonomy/ACF registration.
6. **Seed content data** — pages/posts/menus/media/options via WP-CLI (idempotent).
7. **Seed plugin data** — ACF / Elementor / forms via CLI or safe DB access.
8. **Ship** — deploy to host/VPS (backup → DB export → URL search-replace → sync).

Recommended additions (proposed — confirm scope):
- **A. wp-env setup** — provision local Docker WordPress (required enabler).
- **B. Content modeling** — derive CPTs/taxonomies/ACF groups from HTML (bridges 1→3→6).
- **C. Design-token extraction** — colors/fonts/spacing → `theme.json` / CSS vars (bridges 2→3).
- **D. QA / visual regression** — render WP vs original HTML (Playwright), responsive, links, a11y, Core Web Vitals.
- **E. SEO & metadata** — meta tags, schema.org, sitemap, redirects (reuse `claude-seo`).
- **F. Security hardening** — wp-config hardening, perms, secrets, plugin vuln scan.
- **G. i18n / multilingual** — translation-ready theme (.pot), Polylang/WPML data; locales **vi / en / ja**.
- **H. Handoff & maintenance** *(optional)* — client docs, update/backup strategy.

## 5. Key design decisions

- **Manifest-driven:** a `wp-build.json` in the target project holds shared state
  (source paths, theme strategy, plugin list, content model, URLs, deploy target).
  Each stage reads/writes it → pipeline is **resumable + idempotent**.
- **Adaptive theme strategy:** one analysis feeds three conversion backends.
- **wp-env first:** all build/seed/QA happens against reproducible Docker WP.
- **Idempotent seeding:** every seed step checks-before-create; safe re-runs.
- **Kit ≠ output:** the plugin is the tooling; output is a standalone WP project.

## 6. Success criteria

- `/wp-pro-max:build ./source` produces a working theme + seeded content in wp-env.
- Re-running any stage is safe (no duplicate content).
- Visual diff vs source HTML within agreed tolerance.
- One command ships to a configured host/VPS with correct URL migration.

## 7. Non-goals (v1)

- Visual page-builder GUI editing inside Claude.
- WordPress multisite networks.
- Managed-host control-panel APIs beyond SSH/WP-CLI/migration plugins.

## 8. Open questions

- Which recommended stages (A–H) ship in v1? (scope gate)
- Default theme strategy when source is ambiguous? (proposed: Classic PHP+ACF)
- Preferred default deploy target? (SSH+WP-CLI vs All-in-One WP Migration)
