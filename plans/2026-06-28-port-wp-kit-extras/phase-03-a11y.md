---
phase: 3
title: "A11y"
status: done
priority: P2
dependencies: [1]
---

# Phase 3: Port `a11y-checker` agent + `/wp-pro-max:a11y-audit` command

## Overview

Create a read-only accessibility agent, a lightweight rules skill, and a slash command to audit theme templates and CSS for WCAG 2.2 AA issues.

## Requirements

- **Functional**: Agent scans theme files and reports file/line, WCAG rule, severity, and suggested fix. Command accepts a file path or `all` and delegates to the agent.
- **Non-functional**: Agent uses only Read/Grep/Glob; command is user-invocable; no dependency on `.claude/docs/a11y-known-issues.md` in target projects.

## Related Code Files

- **Create**: `skills/wp-a11y/SKILL.md`, `agents/a11y-checker.md`, `commands/a11y-audit.md`
- **Modify**: none
- **Delete**: none

## TDD Tests (write first)

1. `scripts/validate-port.sh agents/a11y-checker.md` passes frontmatter/tools check.
2. `scripts/validate-port.sh commands/a11y-audit.md` passes frontmatter check.
3. `agents/a11y-checker.md` declares only `[Read, Grep, Glob]` tools.
4. No `{{VAR}}` placeholders in new files.
5. `commands/a11y-audit.md` references `agents/a11y-checker.md` and accepts `$ARGUMENTS`.
6. No references to `.claude/docs/a11y-known-issues.md` as a required file (optional mention only).

## Implementation Steps

1. Run the tests; confirm they fail (red).
2. Create `skills/wp-a11y/SKILL.md`:
   - Frontmatter with `name: wp-a11y`, `user-invocable: false`.
   - Condensed WCAG 2.2 AA rules covering semantic markup, forms, images/icons, keyboard/focus, colors/contrast, links/navigation.
   - Keep examples in plain PHP (not Blade) so they work for both classic and block themes.
3. Create `agents/a11y-checker.md`:
   - Frontmatter: `name: a11y-checker`, `tools: [Read, Grep, Glob]`, `model: haiku` (or `sonnet` if read-only audit needs stronger reasoning).
   - Instructions to scan files in the active theme path from `wp-build.json`.
   - Output format: total issues by severity, list sorted by severity, top 3 urgent issues.
   - Reference `skills/wp-a11y/SKILL.md` for rules.
4. Create `commands/a11y-audit.md`:
   - Frontmatter with `description`.
   - Input: `$ARGUMENTS` = file path or `all`.
   - Steps: read `skills/wp-a11y/SKILL.md`, determine files (use `wp-build.json` `theme.path` or argument), delegate scan to `a11y-checker`, report summary.
5. Add license attribution footers.
6. Re-run tests; confirm green.

## Success Criteria

- [x] `skills/wp-a11y/SKILL.md`, `agents/a11y-checker.md`, `commands/a11y-audit.md` exist and pass validation.
- [x] Agent uses only Read/Grep/Glob.
- [x] Command accepts file path or `all`.
- [x] No hard dependency on target project's `.claude/docs/a11y-known-issues.md`.
