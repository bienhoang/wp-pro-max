---
phase: 4
title: "Figma"
status: done
priority: P2
dependencies: [1]
---

# Phase 4: Port `figma-bridge` skill + `figma-analyzer` agent + commands

## Overview

Create a Figma-to-code capability. Because WP Pro Max v1 has no Figma MCP dependency, the skill and commands must be **on-demand** and fail gracefully with setup instructions when MCP is unavailable.

## Requirements

- **Functional**: Skill defines the Figma → token → code workflow. Agent extracts specs via Figma MCP. Commands `/wp-pro-max:figma` and `/wp-pro-max:component` parse a Figma URL and return a structured report or generate a component.
- **Non-functional**: Skill is on-demand (`disable-model-invocation: true`); commands reference `wp-build.json` design tokens; no hardcoded source token file paths.

## Related Code Files

- **Create**: `skills/figma-bridge/SKILL.md`, `skills/figma-bridge/references/figma-mcp-setup.md`, `agents/figma-analyzer.md`, `commands/figma.md`, `commands/component.md`
- **Modify**: none
- **Delete**: none

## TDD Tests (write first)

1. `skills/figma-bridge/SKILL.md` has `disable-model-invocation: true` and `user-invocable: true`.
2. `agents/figma-analyzer.md` declares Figma MCP tools.
3. No `{{VAR}}` placeholders in new files.
4. No hardcoded source paths like `resources/css/common/theme.css`; instead reference `wp-build.json` `designTokens` or theme CSS discovery.
5. `commands/figma.md` and `commands/component.md` define `$ARGUMENTS` usage.
6. Commands include a guard: if Figma MCP is unavailable, print setup instructions and stop.

## Implementation Steps

1. Run the tests; confirm they fail (red).
2. Create `skills/figma-bridge/SKILL.md`:
   - Frontmatter: `name: figma-bridge`, `user-invocable: true`, `disable-model-invocation: true`.
   - Overview of Figma → token → code workflow.
   - URL parsing: file key and node id.
   - Mapping tables (spacing px/4, colors → CSS vars, typography → classes).
   - Note that token sources come from `wp-build.json` `designTokens` and the generated theme CSS.
   - Condensed troubleshooting section.
3. Create `skills/figma-bridge/references/figma-mcp-setup.md`:
   - How to install/enable Figma MCP and authenticate.
   - Keep it short; do not generate `.mcp.json` for the user.
4. Create `agents/figma-analyzer.md`:
   - Frontmatter with MCP tools and `skills: [figma-bridge]`.
   - Process: parse URL, call MCP tools in parallel, read theme CSS token files, map to project tokens, output report.
5. Create `commands/figma.md`:
   - Input: `$ARGUMENTS` = Figma URL.
   - Guard: check if Figma MCP is configured; if not, point to setup reference.
   - Delegate to `figma-analyzer`.
6. Create `commands/component.md`:
   - Input: `$ARGUMENTS` = Figma URL or component name.
   - Guard: check Figma MCP.
   - Check existing components in theme `parts/` / `templates/`.
   - Delegate design analysis to `figma-analyzer`, then generate CSS + template following active strategy (classic/block/builder).
   - Run build validation if a build command exists.
7. Add license attribution footers.
8. Re-run tests; confirm green.

## Success Criteria

- [x] `skills/figma-bridge/SKILL.md` and its setup reference exist.
- [x] `agents/figma-analyzer.md` and both commands exist and pass validation.
- [x] Figma MCP is treated as optional; commands provide setup instructions when unavailable.
- [x] Token mapping uses `wp-build.json` / theme CSS, not hardcoded source paths.
