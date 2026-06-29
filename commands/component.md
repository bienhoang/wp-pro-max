---
description: Create a new UI component from a Figma design or component name.
---

# Component Creation from Figma

Given a Figma link, generate a complete UI component following the active theme's design system and conversion strategy.

## Input

- `$ARGUMENTS`: Figma URL or component name.

## Steps

1. **Guard: verify Figma MCP is available** (only when a Figma URL is provided).
   - Try a lightweight MCP call or check that the `mcp__figma__*` tools are registered.
   - If unavailable, print the setup instructions from `skills/figma-bridge/references/figma-mcp-setup.md` and stop.

2. **Check existing components**:
   - Read `wp-build.json` to determine the active theme path and conversion strategy (`classic`, `block-fse`, or `builder`).
   - Search the theme's `parts/`, `templates/`, `components/`, or equivalent directories for an existing component with the same name or similar pattern.
   - If it exists, ask the user whether to extend it or create a variant.

3. **If a Figma URL is provided, delegate analysis to the `figma-analyzer` agent**:
   - Extract fileKey and nodeId.
   - Return layout, colors, typography, spacing, and token mapping.

4. **Read project tokens**:
   - Use `wp-build.json` `designTokens` and theme CSS files discovered with `Glob`.
   - Map Figma values to tokens: spacing `px / 4`, colors via CSS variables, typography via theme classes.
   - Flag any Figma value without a matching token.

5. **Generate the component**:
   - Follow the active strategy:
     - **classic**: PHP template partial + CSS, ACF fields if needed.
     - **block-fse**: block pattern or template part + `theme.json` styles.
     - **builder**: Elementor/Bricks component markup + CSS.
   - Apply accessibility rules from `skills/wp-a11y/SKILL.md`.
   - Escape output with `esc_html()`, `esc_attr()`, `wp_kses_post()`, etc.

6. **Validate**:
   - Run the project's build command if one exists (e.g., `npm run build` or `wp-pro-max:build`).
   - Run a quick accessibility check on the generated template.

7. **Report**:
   - Created or modified files.
   - Figma reference screenshot (if available).
   - Warnings: missing tokens, manual attention needed, build/a11y results.

## Notes

- If the input is a component name without a Figma URL, build from the existing design system and ask the user for any missing details.
- Do not generate `.mcp.json` or per-project installer files.

---

*Ported and rewritten for WP Pro Max from `alessioarzenton/claude-code-wp-toolkit` (GPL-3.0). Target license: MIT.*
