# WP-Classic Port — Implementation Complete

**Date:** 2026-06-29  
**Plan:** `plans/2026-06-28-wp-classic-port/`

## What changed

Ported the `wp-classic` stack conventions into WP Pro Max as a first-class,
manifest-aware capability for the `classic-acf` theme strategy:

- `skills/wp-classic/SKILL.md` — user-invocable stack skill documenting the
  classic PHP theme conventions for WordPress 7.x.
- `references/classic-acf.md` — canonical agent reference consumed by
  `theme-conversion`, `wp-scaffold`, and `wp-theme-developer` when
  `strategy = classic-acf`.
- `skills/wp-classic/references/code-review-checklist.md` — generic WPCS,
  escaping, accessibility, and security checklist.
- `skills/wp-classic/references/component-workflow.md` — Figma-free 11-step
  component workflow with token mapping tables and memory-update guidance.
- Wired the new reference into `skills/theme-conversion/SKILL.md`,
  `skills/wp-scaffold/SKILL.md`, and `agents/wp-theme-developer.md`.
- Updated project docs: `README.md` (18 skills), `docs/codebase-summary.md`,
  `docs/project-roadmap.md` (Phase 11 marked done).
- Added `plans/2026-06-28-wp-classic-port/ROLLBACK.md`.

## Key adaptation decisions

- Replaced source `{{VAR}}` placeholders with runtime reads from
  `wp-build.json` (`project.themeSlug`, `project.textDomain`, `strategy`).
- Targeted WordPress 7.x and standard `@wordpress/env` paths instead of the
  source's Bedrock/DDEV assumptions.
- Kept root template files as the default for auto-generated themes; `templates/`
  is noted as optional for custom page templates.
- ACF Pro is assumed for `classic-acf`; the reference includes `inc/acf-blocks.php`
  registration and the `acf-json/` load/save point snippet.
- Preserved the existing `skills/theme-conversion/references/classic-acf.md` but
  added a superseded-by note pointing to the new canonical reference to avoid
  stale agent guidance.

## Verification

- `claude plugin validate .` passes.
- No `{{VAR}}` placeholders remain in new or modified files.
- `references/classic-acf.md` is 227 lines, within the ~250-line target.
- All internal relative links in the new skill and references resolve correctly.
- Code-review and final-verification agents both passed the implementation.

## Follow-ups

- Consider removing or fully aligning `skills/theme-conversion/references/classic-acf.md`
  with the canonical reference if the deprecation note proves insufficient.
- Add a live `classic-acf` end-to-end pipeline run once an example site is
  available for this strategy.
