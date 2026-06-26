# WP Pro Max — System Architecture

**Status:** Draft v0.1 · 2026-06-26

## Overview

`wp-pro-max` is a Claude Code **plugin** packaging Skills + Agents + Commands +
shared scripts that orchestrate a manifest-driven pipeline: static HTML →
production WordPress.

```
source HTML / brief
        │
        ▼
┌──────────────────────────────────────────────────────────────┐
│  ORCHESTRATOR  (/wp-pro-max:build)                             │
│  reads/writes  wp-build.json  (shared manifest, in target proj)│
└──────────────────────────────────────────────────────────────┘
   │analyze │optimize│ model │ tokens │convert│plugins│scaffold│seed │qa│ship
   ▼        ▼        ▼       ▼        ▼       ▼       ▼        ▼     ▼  ▼
 [skills, each reads manifest → does work → updates manifest + emits artifacts]
        │                                   │              │
        ▼ delegates code/data/deploy work   ▼              ▼
   wp-theme-developer   wp-data-engineer   wp-deployer   (agents)
        │                                   │
        ▼                                   ▼
   wp-env (Docker WordPress)  ◀── WP-CLI / DB ──▶  host / VPS
```

## Plugin layout

```
wp-pro-max/
├── .claude-plugin/
│   ├── plugin.json              # manifest (name, version, author…)
│   └── marketplace.json         # single-plugin marketplace for install
├── commands/
│   ├── build.md                 # /wp-pro-max:build — full pipeline orchestrator
│   ├── status.md                # /wp-pro-max:status — show manifest + progress
│   ├── env.md                   # /wp-pro-max:env — provision/manage theme wp-env
│   ├── init.md                  # /wp-pro-max:init — project scaffolder
│   └── plugin.md                # /wp-pro-max:plugin — standalone plugin builder
├── skills/                      # one skill per stage (model-invocable)
│   ├── html-analysis/
│   ├── html-optimization/
│   ├── content-modeling/        # (B)
│   ├── design-tokens/           # (C)
│   ├── theme-conversion/        # adaptive: references/{classic-acf,block-fse,page-builder}.md
│   ├── plugin-selection/
│   ├── wp-scaffold/
│   ├── content-seeding/
│   ├── plugin-data-seeding/
│   ├── wp-env-setup/            # (A)
│   ├── wp-qa/                   # (D)
│   ├── wp-seo/                  # (E)
│   ├── wp-security/             # (F)
│   ├── wp-ship/
│   └── wp-plugin-dev/           # standalone plugin builder
├── agents/
│   ├── wp-theme-developer.md    # writes theme PHP / template parts / theme.json
│   ├── wp-data-engineer.md      # WP-CLI seeding + safe DB ops
│   ├── wp-deployer.md           # backup, migrate, URL search-replace, ship
│   └── wp-plugin-developer.md   # standalone plugin PHP/features
├── scripts/                     # reusable, called via ${CLAUDE_PLUGIN_ROOT}
│   ├── manifest-core.sh         # shared manifest helpers
│   ├── manifest-lib.sh          # wp-build.json wrappers
│   ├── plugin-manifest-lib.sh   # wp-plugin.json wrappers
│   ├── wp-env-bootstrap.sh
│   ├── plugin-env-bootstrap.sh  # plugin-local wp-env
│   ├── plugin-scaffold.sh       # plugin skeleton + feature generators
│   ├── plugin-package.sh        # allowlisted .zip builder
│   ├── seed-helpers.sh          # idempotent create-if-missing helpers
│   ├── extract-tokens.mjs       # HTML/CSS → design tokens JSON
│   ├── visual-diff.mjs          # Playwright pixel diff (WP vs source)
│   └── migrate-urls.sh          # wp search-replace wrapper
├── schemas/
│   ├── wp-build.schema.json     # pipeline manifest schema
│   └── wp-plugin.schema.json    # plugin manifest schema
└── references/                  # shared knowledge (WP-CLI, ACF JSON, deploy runbook)
```

## Project layout (`/wp-pro-max:init`)

The recommended starting structure separates inputs from the generated WordPress
project:

```
my-site/
├── requirements/      # brief.md — consumed by analyze/model
├── source/            # static HTML/CSS/JS — consumed by analyze + optimize
├── assets/            # images, fonts, downloads — consumed by optimize + convert
├── design/            # brand docs, tokens — consumed by tokens
├── mockups/           # screenshots / design files (reference)
├── wp/                # WordPress project root (manifest, theme, wp-env)
│   └── wp-build.json  # pipeline manifest
├── .gitignore
└── README.md
```

- `/wp-pro-max:init <name>` scaffolds this tree and writes `wp/wp-build.json`
  with candidate `source.*` paths relative to `wp/`.
- `/wp-pro-max:build` auto-descends into `wp/` when the manifest is in `wp/` but
  not in the current directory.
- `html-analysis` auto-detects `source.type` when init leaves it unset:
  `html-files` if `source.htmlPaths` contain HTML, otherwise `brief` if
  `requirements/brief.md` is non-empty.

## The manifest — `wp-build.json`

Single source of truth written to the **target** project root. Carries:

- `source`: paths/URL of input HTML, asset dirs, requirements brief.
- `strategy`: `classic-acf | block-fse | page-builder`.
- `analysis`: detected pages, components, repeated patterns, asset inventory.
- `contentModel`: CPTs, taxonomies, ACF field groups, menus.
- `designTokens`: colors, fonts, spacing, breakpoints.
- `plugins`: selected slugs + rationale + `.wp-env.json` pins.
- `theme`: name, generated files, template map.
- `seed`: content + plugin-data scripts, run status (idempotency keys).
- `urls`: local (`localhost:8888`) ↔ production for search-replace.
- `deploy`: target type (ssh/ai1wm), host config ref, last deploy.
- `progress`: per-stage status (pending/done/failed) → enables resume.

## Execution model

- **Skills** are auto-invocable and own one stage each; they consult the manifest,
  call shared scripts, and delegate heavy code/data/deploy work to **agents**.
- **Orchestrator command** runs stages in order with user gates (full mode) and
  records progress so a run can resume from any stage.
- **wp-env** provides reproducible WordPress; all WP-CLI runs go through
  `wp-env run cli wp …`. Theme/plugin mounted via `.wp-env.json` `mappings`.
- **Standalone plugin builder** (`/wp-pro-max:plugin`) is a separate, opt-in
  capability. It uses `wp-plugin.json`, its own `plugin-scaffold.sh`, and a
  plugin-local `.wp-env.json`. It no-ops inside a theme build to avoid colliding
  with `wp-scaffold`.
- **Ship** path: backup → `wp db export` → `wp search-replace` (URL migration) →
  rsync wp-content / or All-in-One WP Migration → smoke test → record rollback point.

## Adaptive conversion

`theme-conversion` selects a backend reference by `strategy`:
- **classic-acf** — PHP templates + `get_template_part` + ACF field groups (JSON).
- **block-fse** — `theme.json` from design tokens + block templates/patterns.
- **page-builder** — Elementor/Bricks templates; data stored as `_elementor_data` postmeta JSON.

## Cross-cutting

- **Idempotency:** seed helpers check existence (post/menu/option/term) before create.
- **Safety:** DB writes prefer WP-CLI; raw `wp db query` only with dry-run/search-replace guards.
- **Reuse:** `wp-seo` delegates to the installed `claude-seo` plugin where present.
