---
phase: 4
title: "Document"
status: done
priority: P3
dependencies: [3]
---

# Phase 4: Document

## Overview

Update project-level documentation so the new skill and reference are discoverable and the codebase summary stays accurate.

## Requirements

- **Functional**: README, codebase-summary, and roadmap reflect the new `wp-classic` skill and `classic-acf` reference.
- **Non-functional**: Keep docs concise; do not duplicate the skill content.

## Related Code Files

- **Modify**: `README.md`, `docs/codebase-summary.md`, `docs/project-roadmap.md`
- **Create**: none (the challenge report already exists at `plans/reports/xia-wp-classic-challenge.md`)

## Implementation Steps

1. **Update `README.md`**:
   - Increment skill count from 17 → 18.
   - Add `wp-classic` to the skills list under Components.
2. **Update `docs/codebase-summary.md`**:
   - Add a row for `wp-classic` in the skills table (or note it as a stack-reference skill).
   - List `references/classic-acf.md` in the references section.
3. **Update `docs/project-roadmap.md`**:
   - Mark the classic theme strategy reference as completed/delivered, or add it under the appropriate phase.
4. **Archive/label the challenge report**:
   - Ensure `plans/reports/xia-wp-classic-challenge.md` remains available for audit.
5. **Add a short `plans/2026-06-28-wp-classic-port/ROLLBACK.md`** (optional but recommended) summarizing how to revert the changes.

## Success Criteria

- [x] `README.md` lists 18 skills and includes `wp-classic`.
- [x] `docs/codebase-summary.md` references `wp-classic` and `references/classic-acf.md`.
- [x] `docs/project-roadmap.md` reflects the completed work.
- [x] Rollback instructions exist (in plan or standalone file).
