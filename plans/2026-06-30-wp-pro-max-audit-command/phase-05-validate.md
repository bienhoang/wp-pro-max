---
phase: 5
title: "Validate"
status: pending
priority: P2
dependencies: [4]
---

# Phase 5: Validate

## Overview

Review the final artifacts, confirm acceptance criteria, and hand off to implementation or user review.

## Requirements

- Functional: All success criteria from Phase 4 and the main plan are met.
- Non-functional: Documentation is accurate; no stale references.

## Implementation steps

1. Re-read `commands/audit.md`, `skills/wp-audit/SKILL.md`, and `scripts/audit-aggregate.sh` for consistency.
2. Verify `schemas/wp-build.schema.json` matches actual output.
3. Check report readability on a real run.
4. Update `docs/codebase-summary.md` and `README.md` if the command list changes.
5. Run `claude plugin validate .` one final time.

## Success criteria

- [ ] All plan success criteria are satisfied.
- [ ] `README.md` lists `/wp-pro-max:audit` if command is user-facing.
- [ ] Optional `commands/wp-pro-max.md` help is accurate.
- [ ] No unresolved TODOs or placeholder text in new files.
- [ ] Plan is marked complete via `ck plan check`.
