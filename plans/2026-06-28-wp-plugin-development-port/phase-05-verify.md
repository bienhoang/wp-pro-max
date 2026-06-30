---
phase: 5
title: "Verify"
status: done
priority: P2
dependencies: [4]
---

# Phase 5: Verify

## Overview

Run final validation on the new skill, references, consumer edits, and documentation. Fix any issues and mark the plan complete.

## Requirements

- **Functional**: All acceptance criteria are met; plugin validation passes; internal links resolve.
- **Non-functional**: No stale content or broken references remain.

## Related Code Files

- **Read/Validate**: `skills/wp-plugin-development/SKILL.md`, `skills/wp-plugin-development/references/*.md`
- **Read/Validate**: `skills/wp-plugin-dev/SKILL.md`, `agents/wp-plugin-developer.md`, `README.md`, `LICENSE`

## Implementation Steps

1. **Validation run**:
   - Run `claude plugin validate .` and fix any frontmatter or manifest errors.
   - Run `bash -n` on any touched shell scripts (none expected in this plan).
   - Grep for broken internal links (`skills/wp-plugin-development/...`).
   - Confirm no `{{VAR}}`, Bedrock-only paths, or source-specific placeholders remain.

2. **Consistency sweep**:
   - Re-read all new and modified files for contradictions.
   - Confirm `wp-plugin-dev` and `wp-plugin-developer` reference the same paths.
   - Confirm attribution appears in every derived file.

3. **Documentation final check**:
   - Confirm `README.md` lists the new skill and skills count is correct.
   - Confirm `LICENSE` attribution is present.

4. Update `plan.md` status to `done` and mark this phase complete.

## Success Criteria

- [ ] `claude plugin validate .` passes.
- [ ] Internal links to `skills/wp-plugin-development/` resolve.
- [ ] `README.md` lists the new skill.
- [ ] License/attribution is recorded.
- [ ] No `wp-plugin-dev` builder procedures or agent standards were changed.
- [ ] `plan.md` status updated to `done`.

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Validation fails at final step | Fix frontmatter/link issues before marking done. |
| Broken link to a reference | Grep for all `skills/wp-plugin-development/references/` links. |
| Missing attribution in one file | Grep for attribution string across new files. |
