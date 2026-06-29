---
phase: 3
title: "Update Consumer Skills"
status: done
priority: P2
dependencies: [2]
---

# Phase 3: Update Consumer Skills

## Overview

Wire the new `accessibility` skill into the existing skills that already touch accessibility: `html-optimization`, `wp-qa`, and `wp-handoff`. Remove or redirect duplicate checklist content so there is a single source of truth.

## Requirements

- **Functional**: Existing skills reference the new accessibility skill and checklist; no stale duplicate content remains.
- **Non-functional**: Minimal edits; preserve existing stage output contracts (`optimization.a11yFixes`, `optimization.notes`, `qa.a11y`).

## Related Code Files

- **Modify**: `skills/html-optimization/SKILL.md`
- **Modify**: `skills/wp-qa/SKILL.md`
- **Modify**: `skills/wp-handoff/SKILL.md`
- **Modify/Delete**: `skills/html-optimization/references/accessibility-checklist.md`
- **Modify/Delete**: `skills/wp-qa/references/accessibility-checklist.md`

## Implementation Steps

1. **Update `skills/html-optimization/SKILL.md`**:
   - In §4 (Accessibility fixes), change the reference link from `references/accessibility-checklist.md` to `skills/accessibility/references/accessibility-checklist.md`.
   - Add a short note: "For deeper WCAG guidance and manual checks, invoke `/wp-pro-max:accessibility`."
   - Keep the stage output contract (`optimization.a11yFixes`, `optimization.notes`) unchanged.

2. **Update `skills/wp-qa/SKILL.md`**:
   - In the a11y section, reference `skills/accessibility/references/accessibility-checklist.md` for the full pass list.
   - Add a note that the `accessibility` skill can be invoked for remediation guidance before re-running QA.
   - Keep the QA gate output shape (`qa.a11y`) unchanged.

3. **Update `skills/wp-handoff/SKILL.md`**:
   - Add a bullet under outputs (or a cross-reference note) that the handoff package may include `docs/a11y-known-issues.md`, generated from `skills/accessibility/references/known-issues-template.md`.

4. **Consolidate duplicate checklists**:
   - Option A (recommended): replace `skills/html-optimization/references/accessibility-checklist.md` and `skills/wp-qa/references/accessibility-checklist.md` with short redirect notes pointing to `skills/accessibility/references/accessibility-checklist.md`.
   - Option B: delete the old files and update any internal links. Only choose this if no other file references them.

5. Run `claude plugin validate .` and check for broken internal links.

## Success Criteria

- [ ] `html-optimization/SKILL.md` links to the new accessibility checklist.
- [ ] `wp-qa/SKILL.md` links to the new accessibility checklist and skill.
- [ ] `wp-handoff/SKILL.md` mentions the known-issues template.
- [ ] Duplicate checklist files are either removed or converted to redirects.
- [ ] No existing stage output contracts are changed.
- [ ] `claude plugin validate .` still passes.

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Output contracts accidentally modified | Make only link/cross-reference edits in consumer skills. |
| Deleted checklist files break old references | Use redirect notes or grep for references before deleting. |
| Plugin validation fails after edits | Validate after each skill edit. |
