---
phase: 4
title: "License & Documentation"
status: done
priority: P2
dependencies: [3]
---

# Phase 4: License & Documentation

## Overview

Record the GPL-3.0 → MIT license attribution for the ported content and update project documentation to reflect the new skill.

## Requirements

- **Functional**: License/attribution is present and correct; README lists the new skill.
- **Non-functional**: Documentation updates are minimal and consistent with project style.

## Related Code Files

- **Create/Modify**: `LICENSE` or `README.md`
- **Modify**: `README.md`

## Implementation Steps

1. **License attribution**:
   - If a top-level `LICENSE` file exists, add a note that `skills/wp-plugin-development/` and its references are derived from `alessioarzenton/claude-code-wp-toolkit` (GPL-3.0), while the rest of the project remains MIT.
   - If no `LICENSE` file exists, create one with the dual-license note.

2. **README update**:
   - Under the plugin development section, mention that plugin work is also guided by the always-active `wp-plugin-development` skill.
   - Optionally update the skills list count (e.g., from 17 → 18).

3. **Cross-check**:
   - Ensure every derived file (`SKILL.md` + four references) contains the attribution footer.
   - Ensure no GPL-3.0 prose is copied verbatim.

## Success Criteria

- [ ] License/attribution for ported content is recorded.
- [ ] `README.md` mentions the new `wp-plugin-development` skill.
- [ ] Attribution footer is present in every derived file.

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| License file already has conflicting text | Append a clear "Ported content" section without altering existing license. |
| README skills count mismatch | Verify current count before editing. |
