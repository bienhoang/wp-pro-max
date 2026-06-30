---
phase: 1
title: "Design"
status: done
priority: P2
dependencies: []
---

# Phase 1: Design

## Overview

Define the exact file layout, adaptation rules, and test harness for the three ports.

## Requirements

- **Functional**: Each feature has a clear home in WP Pro Max's plugin structure.
- **Non-functional**: Rewritten for MIT license; no `{{VAR}}` placeholders; no per-project `.claude/` installer assumptions; WordPress 7.x target.

## Architecture

```text
wp-pro-max/
├── skills/
│   └── wp-performance-backend/
│       └── SKILL.md
├── skills/
│   └── figma-bridge/
│       ├── SKILL.md
│       └── references/
│           └── figma-mcp-setup.md   (condensed from source)
├── skills/
│   └── wp-a11y/
│       └── SKILL.md                 (rules reference for agent)
├── agents/
│   ├── a11y-checker.md
│   └── figma-analyzer.md
├── commands/
│   ├── a11y-audit.md
│   ├── figma.md
│   └── component.md
└── scripts/
    └── validate-port.sh             (TDD helper: frontmatter + link + placeholder checks)
```

## TDD Harness

Create a reusable validation script `scripts/validate-port.sh` that checks:

1. Required frontmatter keys (`name`, `description`, `user-invocable` for skills; `description` for commands/agents).
2. No `{{[A-Z_]+}}` placeholders in new files.
3. No hardcoded Bedrock-only paths unless marked optional (e.g., `web/app/themes`, `web/wp`).
4. WP-CLI commands use `wp-env run cli wp …` pattern (for performance skill).
5. All internal markdown links resolve (`references/…`, `skills/…`, `agents/…`, `commands/…`).
6. Agents declare only allowed tools.

The script is written **first** and run against the empty file set to confirm failure.

## Adaptation Rules

| Source convention | WP Pro Max convention |
|---|---|
| `.claude/skills/core/…` | `skills/<name>/SKILL.md` |
| `.claude/agents/…` | `agents/<name>.md` |
| `.claude/commands/…` | `commands/<name>.md` |
| `{{VAR}}` placeholders | `wp-build.json` manifest reads at runtime |
| WordPress 6.x | **WordPress 7.x** |
| Bedrock/DDEV paths | Standard `wp-env` paths; Bedrock optional |
| `.claude/docs/a11y-known-issues.md` | Target project docs; agent simply reports findings |
| Per-project `.mcp.json` | Document Figma MCP setup in skill reference; do not generate `.mcp.json` |
| `accessibility` skill dependency | Create `skills/wp-a11y/SKILL.md` or inline core rules |

## Implementation Steps

1. Write `scripts/validate-port.sh`.
2. Run it; confirm it fails because no new files exist yet.
3. Finalize frontmatter templates for skills, agents, and commands.
4. Document the three feature scopes and what is **excluded** (installer, hooks, `.mcp.json` generation, per-project templates).

## Success Criteria

- [x] `scripts/validate-port.sh` exists and fails (red) before implementation.
- [x] File layout and adaptation rules are documented.
- [x] Each feature's scope and exclusions are listed.
