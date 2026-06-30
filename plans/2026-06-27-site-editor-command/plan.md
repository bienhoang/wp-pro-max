---
title: "WP Pro Max Site Editor Command"
description: "Add /wp-pro-max:site-editor with section-redesign, content-enrichment, and pre-conversion-qa child skills operating on the optimized HTML copy before theme conversion."
status: done
priority: P2
branch: "main"
tags: [command, skill, site-editor, html-redesign, content-enrichment, pre-conversion-qa, tdd]
blockedBy: []
blocks: []
created: "2026-06-27T11:24:24.367Z"
createdBy: "ck:plan"
source: skill
---

# WP Pro Max Site Editor Command

## Overview

Add a new top-level command `/wp-pro-max:site-editor` and three child skills that let users redesign sections, add/enrich pages and copy, and run lightweight UI/UX QA **on the optimized HTML copy** (`.wp-pro-max/optimized/`) before paying the cost of WordPress `theme-conversion`. The command runs outside the main pipeline but remains manifest-driven: every change writes to `wp-build.json`, source HTML stays read-only, and re-running is idempotent.

This plan was generated from the approved brainstorm report at `plans/reports/260627-1713-site-editor-brainstorm.md`.

## Boundaries & Scope Decisions

| In scope | Out of scope (deferred) |
|----------|------------------------|
| `/wp-pro-max:site-editor` command with `--redesign`, `--add-pages`, `--enrich`, `--check`, `--preview`, `--all`, `--revert` | Modifying `commands/build.md` orchestrator in this iteration |
| Three child skills: `section-redesign`, `content-enrichment`, `pre-conversion-qa` | Media / image generation |
| Shared helper scripts for HTML section ops, preview, and pre-conversion QA checks | Deploy or post-conversion QA (still handled by `wp-qa`) |
| Schema additions to `wp-build.schema.json` for `siteEditor.*` | WooCommerce / commerce-aware redesign |
| Backup/rollback of optimized copy | Theme-level changes after `theme-conversion` |
| Tests-first structure in every phase (TDD) | Full automated test harness beyond script syntax + sample-site behavioral checks |

**Source contract:** `source/` and `assets/` are read-only. All edits target `.wp-pro-max/optimized/` only. Backups go to `.wp-pro-max/optimized-backup/`.

## Phases

| Phase | Name | Status | Priority | Dependencies |
|-------|------|--------|----------|--------------|
| 1 | [Schema & Contract](./phase-01-schema-contract.md) | done | P1 | — |
| 2 | [Shared Helpers](./phase-02-shared-helpers.md) | done | P1 | 1 |
| 3 | [Command Authoring](./phase-03-command-authoring.md) | done | P1 | 1, 2 |
| 4 | [Section Redesign Skill](./phase-04-section-redesign-skill.md) | done | P1 | 1, 2 |
| 5 | [Content Enrichment Skill](./phase-05-content-enrichment-skill.md) | done | P1 | 1, 2 |
| 6 | [Pre-Conversion QA Skill](./phase-06-pre-conversion-qa-skill.md) | done | P1 | 1, 2 |
| 7 | [Integration Tests & Docs](./phase-07-integration-tests-docs.md) | done | P2 | 3–6 |

## Architecture

```
source/                         # read-only
  │
  ▼
html-optimization  ──►  .wp-pro-max/optimized/   # working copy
  │
  ▼
/wp-pro-max:site-editor
  ├── /wp-pro-max:section-redesign
  ├── /wp-pro-max:content-enrichment
  └── /wp-pro-max:pre-conversion-qa
  │
  ▼
theme-conversion  ──►  wp-qa  ──►  ship
```

The command is a thin coordinator: it resolves the manifest, ensures `optimization.outputDir` exists, and dispatches to the relevant child skill. Each child skill owns one stage id (`section-redesign`, `content-enrichment`, `pre-conversion-qa`) and writes its own subtree under `siteEditor.*` in `wp-build.json`.

## Cross-Plan Dependencies

- **WooCommerce Catalog Build Extension** (`plans/2026-06-26-woocommerce-catalog-build-extension/`) is pending and also modifies `schemas/wp-build.schema.json` (adds `commerce` block). There is no logical/data dependency between `commerce` and `siteEditor`, but both touch the same schema file. Coordinate merges; the two new top-level blocks are independent.
- **wp-pagespeed skill** (`plans/2026-06-27-wp-pagespeed-skill/`) is pending but is a standalone skill with no shared files; no dependency.

## TDD Approach

Because `--tdd` was requested, every phase begins with a failing or placeholder test/spec before the implementation is written:

1. **Schema phase:** write a small manifest fixture with `siteEditor.*` and assert it validates against `schemas/wp-build.schema.json` using `ajv`/`jq` before the schema is changed.
2. **Helper phase:** write script-level tests (syntax checks + sample HTML fixtures) before the scripts exist.
3. **Command phase:** define expected subcommand parsing behavior and a dry-run smoke test.
4. **Skill phases:** define sample-site fixtures and expected manifest/HTML diffs before authoring the SKILL.md files.
5. **Integration phase:** compose the above into an end-to-end sample-site run.

No new CI runner is introduced; tests are shell/Node one-liners that can be run manually and later adopted by a harness.

## Key Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| AI edits corrupt optimized HTML | Backup before edit; lightweight HTML validity check after each edit; provide `--revert`. |
| Generated copy mismatches brand voice | Mark AI-generated blocks with `data-wp-pro-max="draft"`; require `--approve` to finalize. |
| Pre-conversion QA is slow | Default `--quick` (static a11y + validity); `--thorough` opt-in for Playwright responsive checks. |
| `optimize --force` overwrites redesign work | Compare `optimization.outputDir` mtime against `siteEditor.lastModified`; warn if newer. |
| Drift from pipeline conventions | Reuse `manifest-lib.sh` helpers, record progress for each child stage, and keep SKILL.md files ≤ ~200 lines. |

## Red-Team Review

Reviewed from five adversarial angles. Findings are folded into phase mitigations below.

| Persona | Finding | Mitigation |
|---------|---------|------------|
| **Chaos-monkey user** | Runs `site-editor` before `optimize`, or with missing `wp-build.json`, or `--force` repeatedly. | Dependency guard in command and every skill; explicit error messages; versioned backups so repeated `--force` does not destroy the only backup. |
| **AI skeptic** | Wants to know exactly what changed and how to revert AI edits. | Every change recorded in `siteEditor.*.appliedChanges[]` / `changes[]`; generated blocks marked `data-wp-pro-max="draft"`; command supports `--revert` to restore from the last backup. |
| **Performance hawk** | Pre-conversion QA must not slow iteration; Playwright install is heavy. | Default `--quick` mode is parser-only; `--thorough` is opt-in; Playwright/Chromium installed on first `--thorough` run only. |
| **Schema purist** | `siteEditor` block could break existing manifests or collide with pending `commerce` block. | `siteEditor` is optional and additive; no new top-level `required` entries; hand-edits to `wp-build.schema.json` target only the new block. |
| **Pipeline integrator** | Site-editor is a one-off outside the pipeline; future work will want it wired into `build`. | Each skill uses canonical stage ids and `wpbuild_progress` so later orchestrator integration is trivial; command file is documented as outside the pipeline for now. |

## Success Metrics

- `/wp-pro-max:site-editor --redesign` modifies sections in `.wp-pro-max/optimized/` and records changes in `wp-build.json`.
- `/wp-pro-max:site-editor --add-pages` creates new HTML files and updates `analysis.pages[]`.
- `/wp-pro-max:site-editor --check` reports a11y/responsive/brand issues and sets `.siteEditor.preConversionQa.passed` (advisory; does not block conversion).
- `/wp-pro-max:site-editor --preview` opens the working copy in the default browser.
- `/wp-pro-max:site-editor --revert` restores the optimized copy from the last backup.
- Re-running any skill is idempotent and leaves the manifest consistent.
- `source/` is never modified.
