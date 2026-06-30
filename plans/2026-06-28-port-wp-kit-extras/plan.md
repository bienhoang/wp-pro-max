---
title: "Port WP Kit extras: performance backend, a11y checker, figma bridge"
description: "TDD plan to port three high-value capabilities from claude-code-wp-toolkit into WP Pro Max: backend performance skill, a11y checker agent/command, and Figma bridge skill/agent/commands."
status: done
priority: P2
branch: "main"
tags: [skill, agent, command, port, tdd, performance, a11y, figma]
blockedBy: []
blocks: []
created: "2026-06-27T17:59:53.730Z"
createdBy: "ck:plan"
source: skill
---

# Port WP Kit extras: performance backend, a11y checker, figma bridge

## Overview

Port three capabilities from `alessioarzenton/claude-code-wp-toolkit` into WP Pro Max using a **tests-first** approach:

1. **`wp-performance-backend`** skill — diagnose TTFB, DB queries, object cache, autoload, cron, remote HTTP.
2. **`a11y-checker`** agent + `/wp-pro-max:a11y-audit` command — WCAG 2.2 AA audit on theme templates/CSS.
3. **`figma-bridge`** skill + **`figma-analyzer`** agent + `/wp-pro-max:figma` and `/wp-pro-max:component` commands — design-to-code via Figma MCP.

All ports are **rewritten** for WP Pro Max's manifest-driven, `wp-env`-first model and MIT license. Source GPL-3.0 prose is not copied verbatim.

## Source Manifest

| Field | Value |
|---|---|
| Repository | `alessioarzenton/claude-code-wp-toolkit` |
| Default branch | `main` |
| Resolved commit | `9a90d123f330fa29ad887363299abc71832226c1` |
| Features ported | `core/claude/skills/core/wp-performance-backend/SKILL.md`, `core/claude/agents/a11y-checker.md`, `core/claude/commands/a11y-audit.md`, `core/claude/skills/core/figma-bridge/SKILL.md`, `core/claude/agents/figma-analyzer.md`, `core/claude/commands/figma.md`, `core/claude/commands/component.md` |
| Source license | GPL-3.0 |

## Local Destination

| Field | Value |
|---|---|
| Project | `wp-pro-max` |
| Local license | MIT |
| Skill layout | `skills/<skill-name>/SKILL.md` |
| Agent layout | `agents/<agent-name>.md` |
| Command layout | `commands/<command-name>.md` |
| Target manifest | `wp-build.json` |
| Runtime | `@wordpress/env` Docker WordPress |

## TDD Strategy

For each implementation phase:

1. **Write the test/check first** — a validation script or checklist that fails before the feature exists.
2. **Run the test** — confirm it fails (red).
3. **Implement the feature** — create the skill/agent/command.
4. **Run the test again** — confirm it passes (green).
5. **Refactor** — align prose, remove source-specific placeholders, add license attribution.

Tests are lightweight and file-system based because these are documentation/LLM skills, not runtime libraries:

- Frontmatter YAML validation.
- Internal link resolution.
- Placeholder scanning (`{{VAR}}`, Bedrock-only paths, `.claude/` assumptions).
- WP-CLI command pattern checks (must use `wp-env run cli wp …`).
- `claude plugin validate .` (if available).

## Phases

| Phase | Name | Status | File |
|-------|------|--------|------|
| 1 | [Design](./phase-01-design.md) | Pending | `phase-01-design.md` |
| 2 | [PerfBackend](./phase-02-perfbackend.md) | Pending | `phase-02-perfbackend.md` |
| 3 | [A11y](./phase-03-a11y.md) | Pending | `phase-03-a11y.md` |
| 4 | [Figma](./phase-04-figma.md) | Pending | `phase-04-figma.md` |
| 5 | [Verify](./phase-05-verify.md) | Pending | `phase-05-verify.md` |
| 6 | [Document](./phase-06-document.md) | Pending | `phase-06-document.md` |

## Dependencies

No cross-plan blockers. The pending `2026-06-28-wp-classic-port` plan is independent; both plans add skills under `skills/` and do not modify the same files except documentation (`README.md`, `docs/codebase-summary.md`). Documentation updates should be coordinated or merged after both plans complete.

## Risk Score

**7/10 (Medium–High)**

| Risk | Severity | Mitigation |
|---|---|---|
| License contamination (GPL-3.0 → MIT) | High | Rewrite all prose; attribute source only in short notes. |
| Figma features depend on Figma MCP which may not be installed | Medium | Mark Figma skill as optional/on-demand; commands fail gracefully with setup instructions. |
| `a11y-audit` depends on target project structure that may vary | Medium | Agent reads `wp-build.json` theme path; command accepts file path argument. |
| Scope creep into source's installer/hooks | Medium | Exclude `init.sh`, hooks, `.mcp.json`, per-project templates. |
| Documentation merge conflict with wp-classic port | Low | Document phase updates both plan files if needed. |

## Rollback Strategy

- Each feature is additive; remove the created directories/files to revert.
- Existing skills are not mutated except for optional cross-references; those edits are small and reversible.
- Keep this plan and the challenge report as audit trail.
