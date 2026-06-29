---
phase: 4
title: "Verify & Document"
status: done
priority: P2
dependencies: [3]
---

# Phase 4: Verify & Document

## Overview

Validate the ported accessibility skill and its wiring, record license attribution, and update project documentation to reflect the new skill.

## Requirements

- **Functional**: All acceptance criteria are met; plugin validation passes; internal links resolve.
- **Non-functional**: License/attribution is recorded in the project; docs are updated consistently.

## Related Code Files

- **Read/Validate**: `skills/accessibility/SKILL.md`, `skills/accessibility/references/accessibility-checklist.md`, `skills/accessibility/references/known-issues-template.md`
- **Read/Validate**: `skills/html-optimization/SKILL.md`, `skills/wp-qa/SKILL.md`, `skills/wp-handoff/SKILL.md`
- **Create/Modify**: `LICENSE` or `README.md` for attribution
- **Modify**: `README.md` (skills list), `docs/codebase-summary.md` if needed

## Implementation Steps

1. **Validation run**:
   - Run `claude plugin validate .` and fix any frontmatter or manifest errors.
   - Run `bash -n` on any touched shell scripts (none expected in this plan).
   - Grep for broken internal links (`skills/accessibility/...`, `references/accessibility-checklist.md`).
   - Confirm no `{{VAR}}` or source-specific placeholders remain.

2. **License attribution**:
   - If a top-level `LICENSE` file exists, add a note that `skills/accessibility/` is derived from `alessioarzenton/claude-code-wp-toolkit` (GPL-3.0) while the rest of the project remains MIT.
   - If no `LICENSE` file exists, create one with the dual-license note.

3. **Documentation updates**:
   - Update `README.md` skills list to include `accessibility`.
   - Optionally update `docs/codebase-summary.md` if it lists skills.
   - Ensure `docs/project-roadmap.md` or similar does not list this plan as pending once complete.

4. **Final consistency sweep**:
   - Re-read all new and modified files for contradictions.
   - Confirm `html-optimization` and `wp-qa` still reference the same checklist path.
   - Confirm attribution appears in every derived file.

5. Mark plan status `done` and this phase complete.

## Success Criteria

- [ ] `claude plugin validate .` passes.
- [ ] Internal links to `skills/accessibility/` resolve.
- [ ] `README.md` lists the new `accessibility` skill.
- [ ] License/attribution is recorded.
- [ ] No duplicate checklist content remains.
- [ ] `plan.md` status updated to `done`.

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Attribution missing from one file | Grep for attribution string across new files. |
| README skills list count mismatch | Increment count if one is stated. |
| Validation fails at final step | Fix frontmatter/link issues before marking done. |
