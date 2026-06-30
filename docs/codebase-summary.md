# Codebase Summary

`wp-pro-max` — Claude Code plugin. HTML → production WordPress pipeline.

## Layout

```
.claude-plugin/      plugin.json + marketplace.json (install manifests)
commands/            build.md (orchestrator), site-editor.md, status.md, env.md, init.md (project scaffolder), plugin.md (standalone plugin builder), a11y-audit.md, audit.md, figma.md, component.md
skills/              24 skills (each SKILL.md + references/)
agents/              wp-theme-developer, wp-data-engineer, wp-deployer, wp-plugin-developer, a11y-checker, figma-analyzer
scripts/             shared bash/node helpers
schemas/             wp-build.schema.json + wp-plugin.schema.json (manifest contracts)
references/          manifest-contract.md, wp-cli-cheatsheet.md, classic-acf.md
examples/sample-site small HTML site to run the pipeline against
docs/                this folder
plans/               implementation plan + phases
```

## Skills → stage ids

| Skill | Stage | Reads → Writes |
|-------|-------|----------------|
| html-analysis | `analyze` | source → analysis |
| html-optimization | `optimize` | analysis → optimization |
| accessibility | `a11y` | guidance / audit → checklist + known issues |
| content-modeling | `model` | analysis → contentModel |
| design-tokens | `tokens` | source CSS → designTokens |
| theme-conversion | `convert` | analysis/model/tokens/strategy → theme |
| plugin-selection | `plugins` | requirements/analysis → plugins[] + .wp-env.json |
| wp-scaffold | `scaffold` | contentModel → theme.files (CPT/tax/ACF) |
| wp-env-setup | `env` | manifest → .wp-env.json, wp-env start |
| content-seeding | `seed-content` | contentModel/pages → seed.contentScript |
| plugin-data-seeding | `seed-plugin-data` | strategy/plugins → seed.pluginDataScript |
| wp-i18n | `i18n` | i18n.* → POT + Polylang/WPML (vi/en/ja) |
| wp-seo | `seo` | → seo.* (delegates to claude-seo) |
| wp-security | `security` | → security.* (hardening + vuln scan) |
| wp-qa | `qa` | analysis/urls → qa.* (gates ship) |
| wp-audit | `audit` | theme/plugin + wp-env → audit.* report |
| wp-ship | `ship` | deploy/urls → remote site + rollbackPoint |
| wp-handoff | `handoff` | full manifest → client docs package |
| section-redesign | `section-redesign` | optimized HTML → redesigned HTML |
| content-enrichment | `content-enrichment` | optimized HTML + brief → new/enriched pages |
| pre-conversion-qa | `pre-conversion-qa` | optimized HTML → siteEditor.preConversionQa |
| wp-classic | — | stack reference for `classic-acf` strategy |
| wp-performance-backend | — | backend performance diagnosis and optimization (TTFB, DB queries, cache, cron, HTTP) |
| wp-a11y | — | WCAG 2.2 AA rule reference used by `a11y-checker` |
| wp-plugin-dev | — | opt-in standalone plugin builder (`/wp-pro-max:plugin`) |
| wp-plugin-development | — | always-active plugin guidance (lifecycle, security, data storage, checklist) |
| figma-bridge | — | optional Figma-to-code workflow using project design tokens |

## Scripts

| Script | Role | Invocation |
|--------|------|------------|
| manifest-core.sh | generic manifest read/write helpers | sourced by manifest-lib.sh / plugin-manifest-lib.sh |
| manifest-lib.sh | read/write/progress on wp-build.json | source OR `bash … <cmd>` |
| plugin-manifest-lib.sh | read/write/progress on wp-plugin.json | source OR `bash … <cmd>` |
| plugin-scaffold.sh | scaffold a plugin + add feature classes | `bash … new` / `bash … add <feature>` |
| plugin-env-bootstrap.sh | plugin-local .wp-env.json + wp-env start | `bash …` |
| plugin-package.sh | allowlisted .zip builder | `bash …` |
| seed-helpers.sh | idempotent create-if-missing WP-CLI | source OR `bash … <fn>` |
| extract-tokens.mjs | HTML/CSS → design tokens JSON | `node extract-tokens.mjs <glob…>` |
| wp-env-bootstrap.sh | render .wp-env.json + wp-env start | `bash …` |
| visual-diff.mjs | Playwright pixel diff WP vs source | `node visual-diff.mjs --source … --target …` |
| html-section-lib.sh | HTML section find/replace/insert/remove/reorder | sourced |
| html-preview.sh | open HTML in default browser | `bash html-preview.sh <file>` |
| pre-qa-a11y.mjs | static a11y scan | `node pre-qa-a11y.mjs <html>…` |
| pre-qa-html-validity.mjs | static HTML validity scan | `node pre-qa-html-validity.mjs <html>…` |
| pre-qa-brand.mjs | design-token consistency check | `node pre-qa-brand.mjs <html>… --tokens <file>` |
| pre-qa-responsive.mjs | Playwright responsive check | `node pre-qa-responsive.mjs <html>…` |
| content-enrichment.mjs | add pages / approve drafts | `node content-enrichment.mjs <manifest> --add-pages …` |
| site-editor-lib.sh | argument parsing for site-editor command | sourced |
| wp-audit-lib.sh | argument parsing + wp-env detection for audit | sourced |
| audit-static.sh | static code-style/a11y/security scanner for wp-audit | `bash … <root> <theme> <scope> <outdir>` |
| audit-live.sh | live performance/security/a11y probes for wp-audit | `bash … <local-url> <scope> <work-dir>` |
| audit-aggregate.sh | aggregate per-category findings into reports | `bash … --work-dir … --mode … --scope …` |
| migrate-urls.sh | guarded `wp search-replace` wrapper | `bash …` / `… --apply` |
| validate-port.sh | frontmatter, link, and placeholder checks for ported skills/agents/commands | `bash scripts/validate-port.sh [file…]` |

Both sourced libs (`manifest-lib.sh`, `seed-helpers.sh`) are **zsh- and
bash-safe**: no source-time `set -e`, no zsh-reserved `status` var, shell-aware
runner/array handling, and robust executed-vs-sourced detection.

## The manifests

- **`wp-build.json`** — single source of truth for the HTML→site pipeline.
  Stages read inputs, do work, write outputs, and record `progress.<stage>.status`.
  Full shape in `schemas/wp-build.schema.json`; contract in
  `references/manifest-contract.md`.
- **`wp-plugin.json`** — single source of truth for a standalone plugin build.
  Drives `plugin-scaffold.sh`, the plugin-local wp-env, and packaging. Shared
  manifest helpers live in `scripts/manifest-core.sh`; thin wrappers live in
  `manifest-lib.sh` and `plugin-manifest-lib.sh`.

## Flow

`/wp-pro-max:build <source>` → init manifest → env → analyze → optimize →
**optional `/wp-pro-max:site-editor`** → model → tokens → convert → plugins →
scaffold → seed-content → seed-plugin-data → i18n → seo → security → qa (gate) →
ship → handoff. Heavy work delegated to the 3 agents.
