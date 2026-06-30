---
phase: 5
title: "Verify"
status: done
priority: P2
dependencies: [2, 3, 4]
---

# Phase 5: Verify

## Overview

Run the full validation suite across all three ports and confirm the WP Pro Max plugin still loads correctly.

## Requirements

- **Functional**: All new skills, agents, and commands pass frontmatter, link, and placeholder checks.
- **Non-functional**: No broken references; no leftover source placeholders; plugin validation passes.

## Related Code Files

- **Read**: all files created in phases 2–4.
- **Run**: `scripts/validate-port.sh`, `claude plugin validate .` (if available).

## Implementation Steps

1. Run `scripts/validate-port.sh` against the entire new set:
   ```bash
   bash scripts/validate-port.sh skills/wp-performance-backend/SKILL.md \
                                 skills/wp-a11y/SKILL.md \
                                 agents/a11y-checker.md \
                                 commands/a11y-audit.md \
                                 skills/figma-bridge/SKILL.md \
                                 skills/figma-bridge/references/figma-mcp-setup.md \
                                 agents/figma-analyzer.md \
                                 commands/figma.md \
                                 commands/component.md
   ```
2. Run `claude plugin validate .` if available; fix any reported issues.
3. Check for `{{VAR}}` placeholders across all new files:
   ```bash
   grep -R -E '\{\{[A-Z_]+\}\}' skills/wp-performance-backend skills/wp-a11y skills/figma-bridge agents/a11y-checker.md agents/figma-analyzer.md commands/a11y-audit.md commands/figma.md commands/component.md
   ```
   Expect zero matches.
4. Check for source-specific assumptions:
   - `web/app/` or `web/wp` (Bedrock-only) not present as defaults.
   - `.claude/docs/a11y-known-issues.md` not treated as required.
   - `init-project.sh` / `.mcp.json` generation not referenced.
5. Dry-run command recognition:
   - Create a temporary target project with `/wp-pro-max:init test-extras`.
   - Verify `/wp-pro-max:wp-performance-backend`, `/wp-pro-max:a11y-audit`, `/wp-pro-max:figma`, `/wp-pro-max:component` are recognized (if plugin supports command listing).
6. If any test fails, return to the relevant phase, fix, and re-run.

## Success Criteria

- [x] `scripts/validate-port.sh` passes for all new files.
- [x] `claude plugin validate .` passes (or manual equivalent).
- [x] Zero `{{VAR}}` placeholders in new files.
- [x] Zero unintended Bedrock/`.claude/` assumptions.
- [x] Commands are recognized by the plugin.
