---
title: "Port Accessibility Skill to WP Pro Max"
description: "Create a dedicated accessibility skill for WP Pro Max, consolidating WCAG 2.2 AA guidance and wiring it into html-optimization, wp-qa, and wp-handoff."
status: done
priority: P2
branch: "main"
tags: [skill, accessibility, a11y, port, wcag]
blockedBy: []
blocks: []
created: "2026-06-28T00:18:00.000Z"
createdBy: "ck:plan"
source: skill
---

# Plan: Port Accessibility Skill to WP Pro Max

## Source

- Repository: `alessioarzenton/claude-code-wp-toolkit`
- Ref: `main` (`9a90d123f330fa29ad887363299abc71832226c1`)
- Artifacts:
  - `core/claude/skills/community/accessibility/SKILL.md`
  - `core/claude/skills/core/accessibility/SKILL.md`
  - `core/claude/skills/core/accessibility/a11y-checklist.md`

## Goal

Create a dedicated, idiomatic `accessibility` skill for `wp-pro-max` that consolidates WCAG 2.2 AA guidance, provides a user-invocable audit/fix entry point, and is referenced by the existing `html-optimization` and `wp-qa` skills to reduce duplication.

## Selected Mode

`--port` (rewrite idiomatically for the local stack).

## Scope

**In scope:**
- `skills/accessibility/SKILL.md` — user-invocable skill with WCAG 2.2 AA primer.
- `skills/accessibility/references/accessibility-checklist.md` — consolidated checklist.
- `skills/accessibility/references/known-issues-template.md` — handoff-ready template.
- Updates to `skills/html-optimization/SKILL.md`, `skills/wp-qa/SKILL.md`, `skills/wp-handoff/SKILL.md`.
- Consolidation/redirect of duplicate checklist files in `html-optimization` and `wp-qa`.
- License attribution for ported content.

**Out of scope:**
- Automated axe-core or Playwright implementation (leave to existing `wp-qa` references).
- Changes to `schemas/wp-build.schema.json`.
- Per-project generated skills.

## Phases

| Phase | Name | Status | File |
|-------|------|--------|------|
| 1 | [Design & Analysis](./phase-01-design.md) | done | `phase-01-design.md` |
| 2 | [Create Skill & References](./phase-02-create-skill.md) | done | `phase-02-create-skill.md` |
| 3 | [Update Consumer Skills](./phase-03-update-consumers.md) | done | `phase-03-update-consumers.md` |
| 4 | [Verify & Document](./phase-04-verify-document.md) | done | `phase-04-verify-document.md` |

## Dependencies

No blocking cross-plan dependencies. Touches only skill documentation; does not modify pipeline scripts or schemas.

## Risk Score

**4/10 (Low–Medium)**

| Risk | Severity | Mitigation |
|------|----------|------------|
| License contamination from GPL-3.0 source | Medium | Rewrite all prose; attribute source only in short notes. |
| Existing skills depend on old checklist paths | Low | Replace old files with redirects rather than deleting them outright. |
| Skill overlaps with `wp-qa` a11y checks | Low | Keep `accessibility` as guidance/checklist; `wp-qa` owns execution. |
| Scope creep into full a11y automation | Low | Exclude axe/Playwright implementation; only reference existing tools. |

## Rollback Strategy

- Remove `skills/accessibility/`.
- Revert edits to `skills/html-optimization/SKILL.md`, `skills/wp-qa/SKILL.md`, `skills/wp-handoff/SKILL.md`.
- Restore original checklist files under `html-optimization/` and `wp-qa/` from git if they were deleted.
- No manifest schema or runtime script changes, so rollback has no pipeline side effects.

## Acceptance Criteria

- [x] `skills/accessibility/SKILL.md` exists and passes `claude plugin validate .`.
- [x] The new skill is user-invocable and describes when to use it (a11y audit, WCAG compliance, keyboard/screen-reader support).
- [x] WCAG 2.2 AA is the stated target, with clear distinction between automated and manual criteria.
- [x] `skills/accessibility/references/accessibility-checklist.md` and `known-issues-template.md` exist.
- [x] Existing `html-optimization` and `wp-qa` skills reference the new skill's checklist rather than maintaining duplicate content.
- [x] `skills/wp-handoff/SKILL.md` mentions the known-issues template.
- [x] License/attribution for the ported content is recorded.
