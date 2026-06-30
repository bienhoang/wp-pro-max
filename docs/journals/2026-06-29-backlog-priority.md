# Backlog Audit — Unimplemented Plans & Cook Priority

**Date:** 2026-06-29  
**Lens:** Dependency order (user-selected)  
**Scope:** All plan folders under `plans/`

## Completed Plans (3)

| Plan | Status | Commit / Evidence |
|------|--------|-------------------|
| `20260626-wp-pro-max-kit` | done | v0.1 foundation; `README.md`, `commands/`, `skills/`, `schemas/wp-build.schema.json` |
| `20260626-wp-plugin-dev` | done | `17cc563` — standalone plugin builder skill + scripts |
| `2026-06-26-wp-pro-max-init-command` | done | `f685d26` — `/wp-pro-max:init` project scaffolder |

## Pending Plans (7)

| # | Plan | Phases | Risk | Schema/File Touchpoints |
|---|------|--------|------|-------------------------|
| 1 | `2026-06-27-site-editor-command` | 7 | Medium | `schemas/wp-build.schema.json` (`siteEditor.*`); `.wp-pro-max/optimized/` |
| 2 | `2026-06-26-woocommerce-catalog-build-extension` | 7 | High | `schemas/wp-build.schema.json` (`commerce.*`); html-analysis, plugin-selection, theme-conversion, content-seeding, wp-qa |
| 3 | `2026-06-28-wp-classic-port` | 4 | Medium-High | `skills/wp-classic/`; `references/classic-acf.md`; `theme-conversion`, `wp-scaffold`, `agents/wp-theme-developer.md` |
| 4 | `2026-06-28-accessibility-skill-port` | 4 | Low-Medium | `skills/accessibility/`; `html-optimization`, `wp-qa`, `wp-handoff` |
| 5 | `2026-06-28-wp-plugin-development-port` | 5 | Low-Medium | `skills/wp-plugin-development/`; `wp-plugin-dev`, `wp-plugin-developer`, `README.md` |
| 6 | `2026-06-27-wp-pagespeed-skill` | 4 | Low | `skills/wp-pagespeed/` only; no shared files |
| 7 | `2026-06-28-port-wp-kit-extras` | 6 | Medium-High | `skills/wp-performance-backend/`, `agents/a11y-checker.md`, `commands/a11y-audit.md`, `skills/figma-bridge/`, `agents/figma-analyzer.md`, `commands/figma.md`, `commands/component.md`; `README.md`, `docs/codebase-summary.md` |

## Dependency-Based Cook Order

### Tier 1 — Schema foundation (serialize, one at a time)
1. **`site-editor-command`** — Adds `siteEditor.*` schema block upstream of theme conversion; no logical dependency on commerce. Cook first so the optimization→conversion boundary is stable before adding commerce logic.
2. **`woocommerce-catalog-build-extension`** — Adds `commerce.*` schema block and cross-cuts multiple pipeline stages. Cook after site-editor to avoid schema-file merge contention.

### Tier 2 — Reference/convention foundation
3. **`wp-classic-port`** — Provides `references/classic-acf.md` consumed by `theme-conversion` and `wp-scaffold`. Benefits from stable conversion/scaffold layers.

### Tier 3 — Skill guidance updates (additive docs)
4. **`accessibility-skill-port`** — Consolidates WCAG guidance and updates consumer skills. No schema/runtime changes.
5. **`wp-plugin-development-port`** — Adds always-active plugin guidance and cross-references `wp-plugin-dev`. No schema/runtime changes.

### Tier 4 — Standalone skill
6. **`wp-pagespeed-skill`** — Fully standalone; can be cooked anytime, but deferred to Tier 4 so higher-touch foundation work lands first.

### Tier 5 — Large multi-feature port
7. **`port-wp-kit-extras`** — Biggest scope (3 skills + 2 agents + 3 commands); documentation overlap with `wp-classic-port`. Cook last, after README/docs baseline is settled.

## Key Risks to Watch

- **Schema collision:** `site-editor-command` and `woocommerce-catalog-build-extension` both edit `wp-build.schema.json`. Do not cook in parallel.
- **Doc merge conflicts:** `wp-classic-port` and `port-wp-kit-extras` both touch `README.md` / `docs/codebase-summary.md`. Finish wp-classic docs before starting wp-kit-extras docs.
- **Test harness gap:** No test infrastructure exists yet. Several pending plans (notably WooCommerce) require building the mock-WP-CLI harness as a deliverable.

## Notes

- All pending plans are tagged **P2**, so plan metadata alone does not differentiate order.
- Git working tree is clean except for untracked `CLAUDE.md`.
- Only branch is `main`; no in-flight feature branches.
