# Plan — WP Pro Max Kit

**Slug:** 20260626-wp-pro-max-kit · **Status:** COMPLETE (v0.1, all phases) · **Mode:** bootstrap --full

## Objective

Build the `wp-pro-max` Claude Code plugin: a manifest-driven pipeline converting
static HTML → production WordPress. See `docs/system-architecture.md`.

## Phases

| # | Phase | Deliverables | Depends |
|---|-------|--------------|---------|
| 01 | Foundation | plugin.json, marketplace.json, `wp-build.schema.json`, shared scripts/references skeleton | — |
| 02 | Intake & analysis | skills: html-analysis, html-optimization, content-modeling, design-tokens; `extract-tokens.mjs` | 01 |
| 03 | Convert & scaffold | skills: theme-conversion (3 backends), plugin-selection, wp-scaffold, wp-env-setup; agent: wp-theme-developer; `wp-env-bootstrap.sh` | 02 |
| 04 | Data seeding | skills: content-seeding, plugin-data-seeding; agent: wp-data-engineer; `seed-helpers.sh` | 03 |
| 05 | Quality gates | skills: wp-qa, wp-seo, wp-security; `visual-diff.mjs` | 03 |
| 06 | Ship | skill: wp-ship; agent: wp-deployer; `migrate-urls.sh` | 04 |
| 07 | Orchestration & docs | commands: build, status, env; README; codebase-summary; e2e demo on sample HTML | 02–06 |
| 08 | i18n & handoff | skills: wp-i18n (vi/en/ja), wp-handoff | 04 |

## Acceptance criteria

- `claude plugin validate .` passes; skills namespace as `wp-pro-max:*`.
- Each stage skill reads + updates `wp-build.json`; reruns are idempotent.
- `/wp-pro-max:build ./sample-html` produces a working wp-env theme + seeded content.
- Visual diff vs sample HTML within tolerance; QA + security checklists pass.
- Docs in `./docs`; phase statuses tracked here.

## Scope (approved)

Full pipeline + all recommended additions A–H from PDR §4.
i18n (G) covers **Vietnamese + English + Japanese (vi/en/ja)**.

## Phase files

- `phase-01-foundation.md` … `phase-08-optional.md` (created on approval).
