# Journal — 2026-06-27

## WP Pro Max Site Editor Command — Planning

### What changed
- Created implementation plan `plans/2026-06-27-site-editor-command/` with 7 phases.
- Derived plan from approved brainstorm report `plans/reports/260627-1713-site-editor-brainstorm.md`.
- Added TDD structure to every phase: schema fixture, helper syntax/behavior tests, command smoke tests, skill fixture tests, and end-to-end integration test.
- Updated plan frontmatter and dependencies after cross-plan scan.

### Key decisions
- `/wp-pro-max:site-editor` runs **outside** the main pipeline for this iteration; `commands/build.md` is not modified.
- Three child skills with canonical stage ids: `section-redesign`, `content-enrichment`, `pre-conversion-qa`.
- All edits target `.wp-pro-max/optimized/` only; `source/` stays read-only; backups go to `.wp-pro-max/optimized-backup/` with latest-5 retention.
- `--redesign` applies to all optimized pages by default; `--page <path>` narrows scope.
- Generated content is marked `data-wp-pro-max="draft"` and requires `--approve` to finalize.
- Pre-conversion QA is **advisory**: `--quick` by default, `--thorough` opt-in; results warn but do not block `theme-conversion`.
- Schema gets a new optional top-level `siteEditor` object; no new required fields, preserving backward compatibility.
- Coordinate schema edits with pending WooCommerce catalog plan (`commerce` block) since both touch `schemas/wp-build.schema.json`.

### Validation
- Red-team review performed: added mitigations for chaos-monkey usage, AI-skeptic revert needs, performance, schema collisions, and future pipeline integration.
- Validation interview clarified: all-pages default, advisory QA, draft+approve workflow, latest-5 backups.
- Whole-plan consistency sweep completed; no unresolved contradictions.
- `claude plugin validate .` passed.

### Risks / follow-ups
- Implementation of `html-section-lib.sh` needs an on-demand `cheerio` install strategy; Playwright/Chromium only for `--thorough`.
- Brief parser for `--from-brief` must be lenient; document supported format in skill reference.
- Future iteration may wire `site-editor` stages into the `build` orchestrator; skills already record `wpbuild_progress` to make that trivial.
