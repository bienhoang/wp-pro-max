---
phase: 3
title: "Update Consumer Skills & Agent"
status: done
priority: P2
dependencies: [2]
---

# Phase 3: Update Consumer Skills & Agent

## Overview

Wire the new `wp-plugin-development` skill into the existing opt-in builder (`wp-plugin-dev`) and the plugin developer agent so they reference the canonical guidance without duplicating it.

## Requirements

- **Functional**: `wp-plugin-dev` skill and `wp-plugin-developer` agent point to the new references.
- **Non-functional**: Minimal edits; preserve existing builder procedures and agent non-negotiable standards.

## Related Code Files

- **Modify**: `skills/wp-plugin-dev/SKILL.md`
- **Modify**: `agents/wp-plugin-developer.md`

## Implementation Steps

1. **Update `skills/wp-plugin-dev/SKILL.md`**:
   - Add a "See also" or "References" section near the end.
   - Point to `skills/wp-plugin-development/references/` for lifecycle, security, data storage, and checklist details.
   - Keep the existing `new`, `add`, `lint|test|package` procedures unchanged.

2. **Update `agents/wp-plugin-developer.md`**:
   - In the workflow or standards section, add a line instructing the agent to consult `skills/wp-plugin-development/references/` for lifecycle, security, data storage, and checklist details before authoring custom plugin code.
   - Keep all existing non-negotiable standards intact.

3. Verify that no duplicate content was introduced; the new references should be the single source of truth for the covered topics.

## Success Criteria

- [ ] `wp-plugin-dev/SKILL.md` references the new `wp-plugin-development` references.
- [ ] `agents/wp-plugin-developer.md` references the new `wp-plugin-development` references.
- [ ] Existing builder procedures and agent standards remain unchanged.
- [ ] `claude plugin validate .` still passes.

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Builder procedures accidentally modified | Only add cross-reference sections; do not change existing steps. |
| Agent standards drift | Add reference pointer without altering the non-negotiable list. |
| Validation fails after edits | Validate after each file edit. |
