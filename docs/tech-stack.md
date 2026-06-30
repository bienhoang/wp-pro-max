# WP Pro Max — Tech Stack

**Status:** Approved (via bootstrap clarification) · 2026-06-26

| Layer | Choice | Why |
|-------|--------|-----|
| Distribution | **Claude Code Plugin** (`.claude-plugin/` + marketplace.json) | Installable, versioned, shareable kit. Skills namespace as `wp-pro-max:*`. |
| Local WP env | **wp-env** (`@wordpress/env`, Docker) | Official, zero-config, scriptable, WP-CLI via `wp-env run cli`. |
| Theme strategy | **Adaptive**: Classic PHP+ACF / Block FSE / Page Builder | One analysis → three conversion backends. |
| Data tooling | **WP-CLI** (+ guarded `wp db query` / `search-replace`) | Idempotent content & plugin-data seeding. |
| Plugin data | ACF JSON, Elementor `_elementor_data` postmeta | Standard storage; CLI/DB seeding. |
| QA | **Playwright** (visual diff, responsive, a11y), Lighthouse/CWV | Validate WP output vs source HTML. |
| Token extraction / scripts | Node (ESM `.mjs`) + Bash | `extract-tokens.mjs`, `visual-diff.mjs`, seed/deploy shell helpers. |
| Ship | SSH + WP-CLI (`db export` + `search-replace` + rsync) / All-in-One WP Migration | URL-safe migration to host/VPS. |
| SEO | Reuse installed **`claude-seo`** plugin | Avoid reinventing audits/schema. |

## Runtime prerequisites (target machine)

- Docker (for wp-env), Node.js ≥ 20, `@wordpress/env` (`npx wp-env`).
- `wp` (WP-CLI) — used inside wp-env; optional on host.
- Playwright (installed on demand for QA stage).
- SSH access + WP-CLI on the deploy target (for ship stage).

## Conventions

- Shell/JS: kebab-case filenames; PHP: WordPress coding standards.
- All plugin scripts referenced via `${CLAUDE_PLUGIN_ROOT}`.
- Manifest: `wp-build.json` (schema in `schemas/wp-build.schema.json`).
