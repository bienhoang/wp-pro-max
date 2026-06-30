# WP Pro Max

A Claude Code **plugin** (kit of skills + agents + commands) that turns static
HTML — or a requirements brief — into a **production WordPress site**, fast and
accurately. It drives a resumable, idempotent pipeline:

| Step | Description | Agent | Skill |
|------|-------------|-------|-------|
| Analyze HTML | Detect page roles, components, asset inventory, IA, and recommend a theme strategy. | — | `html-analysis` |
| Optimize | Clean, dedupe, and semanticize markup/CSS; plan image optimization without mutating originals. | — | `html-optimization` |
| Model content | Turn repeated structures into CPTs, taxonomies, field groups, and menu trees. | `wp-theme-developer` | `content-modeling` |
| Extract design tokens | Derive color, typography, spacing, and breakpoint tokens for `theme.json` / CSS. | `wp-theme-developer` | `design-tokens` |
| Convert theme (adaptive) | Build a classic ACF, block FSE, or page-builder theme from the analyzed source. | `wp-theme-developer` | `theme-conversion` |
| Select plugins | Pick the minimal plugin set and pin slugs into `.wp-env.json`. | — | `plugin-selection` |
| Scaffold code | Wire `functions.php`, registrations, ACF JSON/block bindings, menus, assets, image sizes. | `wp-theme-developer` | `wp-scaffold` |
| Seed content | Create pages/posts, import media, build menus, and set the front page from optimized HTML. | `wp-data-engineer` | `content-seeding` |
| Seed plugin data | Fill ACF values, builder postmeta, and form configuration after content exists. | `wp-data-engineer` | `plugin-data-seeding` |
| i18n | Make the theme translation-ready (`.pot`) and configure multilingual content (vi/en/ja). | `wp-theme-developer`, `wp-data-engineer` | `wp-i18n` |
| SEO | Set meta titles/descriptions, Open Graph, schema, canonicals, robots, and sitemap. | `wp-theme-developer` | `wp-seo` |
| Security | Harden WordPress and scan core/plugins/themes/secrets for vulnerabilities. | `wp-deployer` | `wp-security` |
| QA | Gate ship with visual diff, responsive checks, broken-link crawl, a11y, and Core Web Vitals. | `wp-theme-developer` | `wp-qa` |
| Ship | Backup, push theme/wp-content, migrate DB, URL search-replace, smoke-test, and record rollback. | `wp-deployer` | `wp-ship` |
| Handoff | Generate client handbook, credentials template, maintenance runbook, and update strategy. | `wp-deployer` | `wp-handoff` |

_Agents are spawned for heavy authoring; stages marked `—` are executed directly by their skill._

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
  WP-CLI via `wpx` (`scripts/wpx.sh`): a fast `docker exec` into the live
  container, with a transparent `wp-env run cli wp` fallback.
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

# Run a best-practice audit on the active theme/plugin
/wp-pro-max:audit
/wp-pro-max:audit --scope all
/wp-pro-max:audit --live
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

Plugin work is also guided by the always-active `wp-plugin-development` skill,
which supplies lifecycle, security, data storage, and checklist references for
any custom plugin code.

## Components

### Commands

| Command | Description |
|---------|-------------|
| `wp-pro-max` | Natural-language router — describe what you want and dispatch to the right command, skill, or agent. |
| `build` | Run the full WP Pro Max pipeline — static HTML (or a brief) to a production WordPress site. |
| `audit` | Run a best-practice audit (a11y, security, performance, code-style) on the active theme/plugin. |
| `status` | Show the WP Pro Max build manifest and per-stage progress for the current project. |
| `env` | Provision or manage the local wp-env WordPress environment for the current build. |
| `init` | Scaffold a target WordPress project directory (inputs + `wp/` + starter `wp-build.json`). |
| `plugin` | Build a standalone WordPress plugin from scratch — scaffold, add features, lint, test, and package. |
| `a11y-audit` | WCAG 2.2 AA accessibility audit on a specific theme file or the entire active theme. |
| `figma` | Analyze a Figma node and extract design specs mapped to the project's design tokens. |
| `component` | Create a new UI component from a Figma design or component name. |
| `site-editor` | Edit the optimized HTML copy before conversion: redesign, add/enrich pages, pre-conversion QA. |

### Skills (24)

| Skill | Description |
|-------|-------------|
| `html-analysis` | Analyze static HTML/CSS/JS (or URL/brief) and recommend a theme strategy. |
| `html-optimization` | Clean, dedupe, and semanticize markup/CSS; plan image optimization. |
| `accessibility` | Accessibility audit and remediation guide; produces checklist + known issues. |
| `wp-a11y` | Condensed WCAG 2.2 AA rule reference used by the `a11y-checker` agent. |
| `content-modeling` | Derive CPTs, taxonomies, field groups, and menus from analyzed HTML. |
| `design-tokens` | Extract color, typography, spacing, and breakpoint tokens from source CSS. |
| `theme-conversion` | Convert analyzed HTML into a classic ACF, block FSE, or page-builder theme. |
| `plugin-selection` | Select the minimal plugin set and pin slugs into `.wp-env.json`. |
| `wp-scaffold` | Wire `functions.php`, registrations, ACF JSON/block bindings, menus, assets. |
| `wp-env-setup` | Provision the local Docker WordPress environment (`wp-env`). |
| `content-seeding` | Seed pages, posts, media, menus, and front-page settings from optimized HTML. |
| `plugin-data-seeding` | Seed ACF values, builder postmeta, and form config after content exists. |
| `wp-i18n` | Make the theme translation-ready (`.pot`) and configure multilingual data (vi/en/ja). |
| `wp-seo` | Apply meta, Open Graph, schema, canonicals, robots, and sitemap. |
| `wp-security` | Harden WordPress and scan core/plugins/themes/secrets for vulnerabilities. |
| `wp-qa` | Quality gate: visual diff, responsive checks, broken links, a11y, Core Web Vitals. |
| `wp-audit` | Best-practice audit (a11y, security, performance, code-style) with static + live probes. |
| `wp-ship` | Ship the local wp-env build to a production host/VPS with backup + rollback. |
| `wp-handoff` | Generate client handbook, credentials template, maintenance runbook, update strategy. |
| `wp-plugin-dev` | Scaffold and build a standalone plugin (`new`, `add`, `lint`, `test`, `package`). |
| `wp-plugin-development` | Always-active guidance for secure, maintainable plugin development. |
| `wp-classic` | Conventions and reference for classic PHP + ACF themes. |
| `wp-performance-backend` | Diagnose and optimize backend performance (TTFB, queries, cache, cron, HTTP). |
| `figma-bridge` | Translate Figma designs into WordPress code using project design tokens. |

### Agents

| Agent | Description |
|-------|-------------|
| `wp-theme-developer` | Expert WordPress theme developer (PHP templates, `theme.json`, ACF, block patterns). |
| `wp-data-engineer` | Expert WordPress data engineer — authors the idempotent seed JSON payload (the skill runs the batch inline via `wp eval-file`), WP-CLI, safe DB ops. |
| `wp-deployer` | Expert WordPress deployment/migration engineer (ship, search-replace, rollback). |
| `wp-plugin-developer` | Expert WordPress plugin developer (secure, WPCS-compliant standalone plugins). |
| `a11y-checker` | Scans theme templates and CSS for WCAG 2.2 AA accessibility issues. |
| `figma-analyzer` | Analyzes Figma designs and extracts specs mapped to project design tokens. |

**Scripts** — `manifest-core.sh`, `manifest-lib.sh`, `plugin-manifest-lib.sh`,
`extract-tokens.mjs`, `wp-env-bootstrap.sh`, `plugin-env-bootstrap.sh`,
`plugin-scaffold.sh`, `plugin-package.sh`, the seed batch engine
(`seed-batch-runtime.php`, `seed-batch-run.sh`, `wp-cli-runner.sh`),
`seed-helpers.sh` (deprecated shim), `visual-diff.mjs`, `migrate-urls.sh`,
`audit-aggregate.sh`, `wp-pro-max-router-lib.sh`.

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
