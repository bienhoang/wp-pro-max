---
title: "WP Pro Max Site Editor Brainstorm Report"
date: "2026-06-27"
category: "brainstorm-report"
tags: ["wp-pro-max", "site-editor", "html-redesign", "content-enrichment", "pre-conversion-qa"]
status: "approved"
---

# WP Pro Max Site Editor — Brainstorm Report

## Summary

Add a new `/wp-pro-max:site-editor` command plus three child skills (`section-redesign`, `content-enrichment`, `pre-conversion-qa`) that let users redesign sections, add pages/content, and validate UI/UX **on the optimized HTML copy** before `theme-conversion`. The command runs outside the main pipeline but is manifest-driven: every change is recorded in `wp-build.json` and the working copy stays inside `.wp-pro-max/optimized/`.

## Problem Statement

`wp-pro-max` converts static HTML into WordPress through a fixed pipeline:
`analyze → optimize → model → tokens → convert → seed → qa → ship`.

The pipeline assumes the source HTML is already acceptable. In practice users often need to:

- Redesign or reorder sections.
- Add new pages or enrich existing copy.
- Validate UI/UX (a11y, responsive, brand consistency) before paying the cost of WordPress conversion.

Currently none of these tasks has a dedicated stage. Users must edit HTML manually or fix issues after conversion, which breaks the manifest-driven, idempotent workflow.

## Requirements Captured

| Requirement | Detail |
|-------------|--------|
| **Expected output** | New command `/wp-pro-max:site-editor` invoking three child skills: `section-redesign`, `content-enrichment`, `pre-conversion-qa`. |
| **Where edits happen** | On `.wp-pro-max/optimized/` working copy only; `source/` stays read-only. |
| **Scope** | Redesign sections, add pages/content, pre-conversion UI/UX check. No deploy, no media generation, no source mutation. |
| **Input for content** | `requirements/brief.md` + user prompts in chat. |
| **Preview** | Open optimized HTML directly in browser. |
| **Integration** | Pre-conversion QA is a separate skill; final QA still runs via existing `wp-qa` after conversion. |
| **Manifest contract** | Every change writes to `wp-build.json`; skills obey idempotency/resume conventions. |

## Approaches Evaluated

### Option A — Single monolithic skill

One new skill `site-editor` runs after `optimize` and does everything in one shot.

| Pros | Cons |
|------|------|
| Single entry point, easy to discover. | Violates single-responsibility; skill becomes large. |
| Less files to maintain initially. | Hard to test, re-run, or reuse individual capabilities. |
| | Difficult to extend later. |

**Verdict:** Rejected. Does not match wp-pro-max's stage-per-convention pattern.

### Option B — Command + three focused skills (selected)

`/wp-pro-max:site-editor` is a command wrapper around three independent skills:

- `section-redesign` — manipulate sections in optimized HTML.
- `content-enrichment` — add pages and enrich copy from brief + prompts.
- `pre-conversion-qa` — lightweight checks on optimized HTML.

| Pros | Cons |
|------|------|
| Clear separation of concerns. | More files than monolith. |
| Each skill can be invoked directly or reused in pipeline later. | Command must coordinate ordering and dependencies. |
| Easier to test and iterate. | |
| Matches existing skill/stage conventions. | |

**Verdict:** Approved.

### Option C — Extend existing skills only

Add modes to `html-optimization`, `content-modeling`, and `wp-qa` instead of creating new skills.

| Pros | Cons |
|------|------|
| No new top-level artifacts. | Blurs responsibility of existing stages. |
| Reuses current conventions. | `html-optimization` becomes a redesign tool, not just cleanup. |
| | Harder to run iteratively outside the pipeline. |

**Verdict:** Rejected. Would pollute existing stage contracts.

## Final Recommended Solution

### Architecture

```
source/                         # read-only
  │
  ▼
html-optimization
  │
  ▼
.wp-pro-max/optimized/          # working copy
  │
  ▼
/wp-pro-max:site-editor
  ├── /wp-pro-max:section-redesign
  ├── /wp-pro-max:content-enrichment
  └── /wp-pro-max:pre-conversion-qa
  │
  ▼
theme-conversion (existing pipeline)
```

### Command interface (`commands/site-editor.md`)

```bash
/wp-pro-max:site-editor --redesign "<instructions>"
/wp-pro-max:site-editor --add-pages "<page-list>" [--from-brief]
/wp-pro-max:site-editor --enrich "<instructions>"
/wp-pro-max:site-editor --check
/wp-pro-max:site-editor --preview
/wp-pro-max:site-editor --all    # redesign + enrich + check
```

Interactive mode when no flag: list detected pages/sections and prompt user.

### Skill: `section-redesign`

- **Reads**: `.analysis.pages[].sections[]`, `.optimization.outputDir`, `.designTokens`, user prompt.
- **Writes**:
  - Modified HTML in `.wp-pro-max/optimized/`.
  - `.redesign.appliedChanges[]` in `wp-build.json`.
  - Updated `.analysis.pages[].sections[]` when sections are added/removed.
- **Capabilities**: add, remove, reorder, rewrite markup/CSS, reuse components from `analysis.components[]`.
- **Safety**: backup old optimized copy to `.wp-pro-max/optimized-backup/` before edits; validate HTML after each change.

### Skill: `content-enrichment`

- **Reads**: `.source.briefPath`, `.analysis.pages[]`, `.contentModel`, user prompt.
- **Writes**:
  - New HTML files in `.wp-pro-max/optimized/`.
  - Updated `.analysis.pages[]` and `.contentModel.menus[]`.
  - `.contentEnrichment.addedPages[]` and `.contentEnrichment.changes[]`.
- **Capabilities**: add pages from brief, enrich headings/alt text/metadata, generate placeholder copy.
- **Safety**: never overwrite existing files without `--force`; mark generated copy for review.

### Skill: `pre-conversion-qa`

- **Reads**: `.optimization.outputDir`, `.analysis.pages[]`, `.designTokens`.
- **Writes**: `.preConversionQa.{a11y,responsive,brandConsistency,passed}`.
- **Checks**:
  - a11y: alt, headings, landmarks, contrast (axe-core or fallback checklist).
  - responsive: render 375/768/1280 via Playwright, detect overflow/horizontal scroll.
  - brand consistency: colors/fonts against `.designTokens`.
- **Modes**: `--quick` for basic a11y only; `--thorough` for full checks.

### Schema additions (`schemas/wp-build.schema.json`)

Add top-level objects:

```json
{
  "redesign": {
    "appliedChanges": { "type": "array", "items": { "type": "object" } },
    "backupDir": { "type": "string" }
  },
  "contentEnrichment": {
    "addedPages": { "type": "array", "items": { "type": "object" } },
    "changes": { "type": "array", "items": { "type": "object" } }
  },
  "preConversionQa": {
    "passed": { "type": "boolean" },
    "a11y": { "type": "object" },
    "responsive": { "type": "object" },
    "brandConsistency": { "type": "object" }
  }
}
```

### Shared scripts to add

| Script | Purpose |
|--------|---------|
| `scripts/html-section-lib.sh` | Parse/insert/reorder HTML sections. |
| `scripts/html-preview.sh` | Open optimized HTML in default browser (macOS `open`). |
| `scripts/pre-qa-a11y.mjs` | axe-core scan on static HTML. |
| `scripts/pre-qa-responsive.mjs` | Playwright viewport rendering checks. |

### Files touched

- **Create**: `commands/site-editor.md`, `skills/section-redesign/SKILL.md`, `skills/content-enrichment/SKILL.md`, `skills/pre-conversion-qa/SKILL.md`, shared scripts above.
- **Modify**: `schemas/wp-build.schema.json`.
- **Not modified**: `commands/build.md` (command runs outside main pipeline for this iteration).

## Implementation Considerations

1. **Dependency guard**: `site-editor` must refuse to run if `optimize` has not produced `.wp-pro-max/optimized/`.
2. **Idempotency**: each skill checks existing state before re-applying changes; re-running should be safe.
3. **Backup/rollback**: keep backups of optimized HTML so users can revert redesign attempts.
4. **HTML validation**: run `node --check` or a lightweight HTML validator after AI edits to catch malformed markup.
5. **Progress tracking**: use `wpbuild_progress` helpers even though these skills are outside the main pipeline, so future integration is trivial.
6. **Playwright dependency**: `pre-conversion-qa` should install Chromium on demand, matching `wp-qa` behavior.

## Risks & Mitigation

| Risk | Mitigation |
|------|------------|
| AI edits corrupt HTML. | Backup before edit; validate HTML after edit; allow `--revert`. |
| Generated copy does not match brand voice. | Mark generated content as draft; require user review. |
| Pre-conversion QA is slow. | Default `--quick` mode; `--thorough` opt-in. |
| Running `optimize --force` overwrites redesign work. | Track optimization generation ID; warn if optimized copy is newer than redesign backup. |
| Command drifts from main pipeline conventions. | Write all outputs to `wp-build.json`; reuse `manifest-lib.sh` helpers. |

## Success Metrics & Validation Criteria

- `/wp-pro-max:site-editor --redesign` produces expected section changes in `.wp-pro-max/optimized/`.
- `/wp-pro-max:site-editor --add-pages` creates new HTML files and updates `analysis.pages[]`.
- `/wp-pro-max:site-editor --check` reports a11y/responsive/brand issues and sets `.preConversionQa.passed`.
- `/wp-pro-max:site-editor --preview` opens the working copy in the default browser.
- Re-running any skill is idempotent and manifest is consistent.
- Source HTML in `source/` remains untouched.

## Next Steps

1. Create implementation plan with `/ck:plan`.
2. Author `commands/site-editor.md` and the three `SKILL.md` files.
3. Update `schemas/wp-build.schema.json`.
4. Implement shared helper scripts.
5. Test against `examples/sample-site`:
   - redesign a section,
   - add a page from `requirements/brief.md`,
   - run pre-conversion QA,
   - continue pipeline through `theme-conversion` and `wp-qa`.

## Dependencies

- `html-optimization` must be stable and produce `.wp-pro-max/optimized/`.
- `wp-qa` remains the final gate after conversion.
- Playwright/Chromium for responsive checks.
- `manifest-lib.sh` helpers for `wp-build.json` read/write.
