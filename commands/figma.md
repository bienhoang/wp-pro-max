---
description: Analyze a Figma node and extract design specs mapped to the project's design tokens.
---

# Figma Design Analysis

Analyze a Figma node and return design specs translated to the active WordPress theme's tokens.

## Input

- `$ARGUMENTS`: Figma URL.

## Steps

1. **Guard: verify Figma MCP is available**.
   - Try `mcp__figma__get_metadata` with a placeholder or the parsed file key.
   - If the tool is missing or the call fails, print the setup instructions from `skills/figma-bridge/references/figma-mcp-setup.md` and stop.

2. **Parse the URL** to extract `fileKey` and `nodeId`.

3. **Delegate to the figma-analyzer agent** with the URL and any relevant context from `wp-build.json`.

4. **Report**:
   - Layout structure (flex, grid, spacing).
   - Colors → project CSS variables/tokens.
   - Typography → project heading/body classes.
   - Spacing → token/utility mapping.
   - Existing components to reuse.
   - New components to create.
   - Missing tokens to flag to the designer.

## Notes

- This command does not modify files. It returns a structured spec report.
- Token sources are read from `wp-build.json` and the active theme's CSS, not from hardcoded paths.

---

*Ported and rewritten for WP Pro Max from `alessioarzenton/claude-code-wp-toolkit` (GPL-3.0). Target license: MIT.*
