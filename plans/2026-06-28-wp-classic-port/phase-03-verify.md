---
phase: 3
title: "Verify"
status: done
priority: P2
dependencies: [2]
---

# Phase 3: Verify

## Overview

Validate that the new skill and reference are syntactically correct, internally consistent, and usable by the pipeline without breaking the sample-site build.

## Requirements

- **Functional**: Skill files load without YAML/frontmatter errors; `theme-conversion` can resolve its reference; a dry run of the sample-site pipeline reaches the convert stage.
- **Non-functional**: No dead internal links; no conflicting template conventions; markdown lint passes if a linter is configured.

## Related Code Files

- **Read**: `skills/wp-classic/SKILL.md`, `references/classic-acf.md`, `skills/theme-conversion/SKILL.md`, `skills/wp-scaffold/SKILL.md`
- **Run**: `claude plugin validate .` (if available), or manual frontmatter checks.

## Implementation Steps

1. **Frontmatter validation**:
   - Confirm `skills/wp-classic/SKILL.md` has required fields: `name`, `description`, `user-invocable`.
   - Confirm `references/classic-acf.md` has a valid markdown header.
2. **Link check**:
   - Verify `skills/wp-classic/SKILL.md` links to `references/classic-acf.md`.
   - Verify `skills/theme-conversion/SKILL.md` references `references/classic-acf.md`.
   - Verify `skills/wp-scaffold/SKILL.md` references `references/classic-acf.md` for the ACF JSON snippet.
3. **Pipeline dry run**:
   - Run `/wp-pro-max:init test-wp-classic` in a temporary directory or use the existing `examples/sample-site`.
   - Set `strategy` to `classic-acf` in the generated `wp-build.json`.
   - Run `/wp-pro-max:build --from convert --to convert` and confirm the stage loads `references/classic-acf.md` without errors.
   - If wp-env is not running, at least confirm the stage does not fail because of a missing reference file.
4. **Consistency check**:
   - Confirm `references/classic-acf.md` uses "WordPress 7.x" consistently.
   - Confirm root templates are the default and `templates/` is only an optional note.
   - Confirm no `{{VAR}}` placeholders remain.

## Success Criteria

- [x] `claude plugin validate .` passes (or equivalent manual check).
- [x] All internal markdown links resolve.
- [x] A dry run of the `convert` stage with `strategy=classic-acf` succeeds or fails only for expected missing-runtime reasons (e.g., wp-env not started), not for missing reference files.
- [x] No `{{VAR}}` placeholders or source-installer references remain.
