---
phase: 6
title: "Document"
status: done
priority: P3
dependencies: [5]
---

# Phase 6: Document

## Overview

Update project documentation and provide rollback instructions.

## Requirements

- **Functional**: README, codebase summary, and roadmap reflect the new capabilities.
- **Non-functional**: Keep docs concise; avoid duplicating skill content.

## Related Code Files

- **Modify**: `README.md`, `docs/codebase-summary.md`, `docs/project-roadmap.md`
- **Create**: `plans/2026-06-28-port-wp-kit-extras/ROLLBACK.md` (recommended)

## Implementation Steps

1. **Update `README.md`**:
   - Increment skill count from 17 → 20 (adds `wp-performance-backend`, `figma-bridge`, `wp-a11y`).
   - Add new skills to the Components list.
   - Add new agents (`a11y-checker`, `figma-analyzer`) and commands (`a11y-audit`, `figma`, `component`) to the Components section.
2. **Update `docs/codebase-summary.md`**:
   - Add rows for the new skills, agents, and commands.
   - Note that `figma-bridge` is optional/on-demand.
3. **Update `docs/project-roadmap.md`**:
   - Mark Figma bridge, a11y audit, and backend performance as delivered/completed.
4. **Create `ROLLBACK.md`** inside the plan directory:
   - List exact files to delete.
   - List small reversible edits to `README.md`, `docs/codebase-summary.md`, `docs/project-roadmap.md`.
5. **Cross-check with `2026-06-28-wp-classic-port` plan**:
   - If both plans modify `README.md` and `docs/codebase-summary.md`, coordinate counts and ordering to avoid merge conflicts.

## Success Criteria

- [x] `README.md` accurately reflects new skills, agents, and commands.
- [x] `docs/codebase-summary.md` includes the new artifacts.
- [x] `docs/project-roadmap.md` shows the work as completed.
- [x] `ROLLBACK.md` exists with clear revert steps.
