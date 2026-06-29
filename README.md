# WP Pro Max

A Claude Code **plugin** (kit of skills + agents + commands) that turns static
HTML — or a requirements brief — into a **production WordPress site**, fast and
accurately. It drives a resumable, idempotent pipeline:

```
analyze HTML → optimize → model content → extract design tokens → convert theme
(adaptive) → select plugins → scaffold code → seed content → seed plugin data →
i18n → SEO → security → QA → ship → handoff
```

## Why

Building WordPress from a design is normally manual: cutting templates, picking
plugins, registering fields, seeding data, migrating to a host. WP Pro Max
automates each step and keeps a single source of truth (`wp-build.json`) so any
stage can be re-run safely or resumed.

## Key ideas

- **Manifest-driven** — every stage reads/writes `wp-build.json`; runs are
  resumable + idempotent. Schema: `schemas/wp-build.schema.json`.
- **Adaptive theme conversion** — one analysis, three backends:
  Classic PHP + ACF, Block theme (FSE / `theme.json`), or Page Builder
  (Elementor / Bricks).
- **wp-env first** — all build/seed/QA runs against reproducible Docker WordPress;
  WP-CLI via `wp-env run cli wp …`.
- **Safety** — idempotent seeding (check-before-create), guarded DB writes
  (dry-run first), QA gate before ship, backup + rollback on every deploy.

## Install

```bash
# from this repo (local marketplace)
/plugin marketplace add /path/to/wp-pro-max
/plugin install wp-pro-max@wp-pro-max-marketplace

# or test without installing
claude --plugin-dir /path/to/wp-pro-max
```

Validate the plugin: `claude plugin validate .`

## Prerequisites

- Docker (for wp-env), Node.js ≥ 20, `@wordpress/env` (`npx wp-env`)
- `jq` (manifest helpers)
- Playwright for the QA stage (`npx playwright install chromium`)
- SSH + WP-CLI on the deploy target (ship stage)

## Usage

```bash
# Scaffold a new project, then build
/wp-pro-max:init my-site
cd my-site && /wp-pro-max:build

# Full pipeline from a folder of HTML
/wp-pro-max:build ./examples/sample-site

# Pick a theme strategy explicitly
/wp-pro-max:build ./examples/sample-site --strategy block-fse

# Resume / run a sub-range
/wp-pro-max:build --from qa
/wp-pro-max:build --from convert --to scaffold

# Inspect progress
/wp-pro-max:status

# Manage the local WordPress
/wp-pro-max:env start
/wp-pro-max:env cli plugin list

# Build a standalone plugin from scratch (opt-in)
/wp-pro-max:plugin new acme-widgets
cd acme-widgets && /wp-pro-max:plugin add cpt
/wp-pro-max:plugin add settings
/wp-pro-max:plugin lint
/wp-pro-max:plugin test
/wp-pro-max:plugin package
```

Skills are also auto-invoked by name when relevant (`wp-pro-max:html-analysis`,
`wp-pro-max:theme-conversion`, `wp-pro-max:wp-ship`, …).

## Plugin development

`/wp-pro-max:plugin` is a standalone, opt-in plugin builder that mirrors the
kit's theme-side conventions. It scaffolds a brand-new OOP plugin from
`wp-plugin.json`, adds secure feature generators (CPT, taxonomy, settings, REST,
shortcode, Gutenberg block), and wires a full dev loop:

```bash
/wp-pro-max:plugin new acme-widgets
/wp-pro-max:plugin add cpt
/wp-pro-max:plugin add rest
/wp-pro-max:plugin add block Hero
/wp-pro-max:plugin lint
/wp-pro-max:plugin test
/wp-pro-max:plugin package
```

It is intentionally separate from the HTML→site pipeline. The skill no-ops
inside a theme build (`wp-build.json` present, `wp-plugin.json` absent) to avoid
colliding with `wp-scaffold`.

## Components

**Commands** — `build` (orchestrator), `status`, `env`, `init`, `plugin`.

**Skills (19)** — `html-analysis`, `html-optimization`, `accessibility`,
`content-modeling`, `design-tokens`, `theme-conversion`, `plugin-selection`,
`wp-scaffold`, `wp-env-setup`, `content-seeding`, `plugin-data-seeding`,
`wp-i18n` (vi/en/ja), `wp-seo`, `wp-security`, `wp-qa`, `wp-ship`,
`wp-handoff`, `wp-plugin-dev`, `wp-classic`.

**Agents (4)** — `wp-theme-developer`, `wp-data-engineer`, `wp-deployer`,
`wp-plugin-developer`.

**Scripts** — `manifest-core.sh`, `manifest-lib.sh`, `plugin-manifest-lib.sh`,
`extract-tokens.mjs`, `wp-env-bootstrap.sh`, `plugin-env-bootstrap.sh`,
`plugin-scaffold.sh`, `plugin-package.sh`, `seed-helpers.sh`, `visual-diff.mjs`,
`migrate-urls.sh`.

## Docs

- `docs/project-overview-pdr.md` — product requirements
- `docs/system-architecture.md` — architecture + manifest design
- `docs/tech-stack.md` — stack + prerequisites
- `docs/codebase-summary.md` — component map
- `docs/project-roadmap.md` — status + next steps
- `references/manifest-contract.md` — stage contract (read before authoring skills)
- `references/wp-cli-cheatsheet.md` — WP-CLI reference

## License

This project is released under the MIT License, except for the
`skills/accessibility/` directory, which adapts conventions from
[alessioarzenton/claude-code-wp-toolkit](https://github.com/alessioarzenton/claude-code-wp-toolkit)
(GPL-3.0) and is also provided under MIT for this project. See `LICENSE`.
