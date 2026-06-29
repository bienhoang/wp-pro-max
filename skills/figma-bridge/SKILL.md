---
name: figma-bridge
description: >-
  Translate Figma designs into WordPress code using the project's design tokens.
  Optional/on-demand; requires the Figma MCP server. Use when a designer shares
  a Figma link and you need structured specs mapped to the active theme.
user-invocable: true
disable-model-invocation: true
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# Figma Bridge

Turn a Figma design into production-ready WordPress markup and CSS. This skill is **on-demand** because it depends on the Figma MCP server. If the server is not available, stop and point the user to [Figma MCP setup](references/figma-mcp-setup.md).

## When to use

- A designer shares a Figma URL for a page, section, or component.
- You need to extract layout, colors, typography, and spacing specs.
- You want to map Figma values to the active theme's design tokens.

## Input

A Figma URL in this form:

```text
https://figma.com/design/:fileKey/:fileName?node-id=1-2
```

Extract:

- **fileKey**: the segment after `/design/`.
- **nodeId**: the value of the `node-id` query parameter.

Example:

- URL: `https://figma.com/design/kL9xQn2VwM8pYrTb4ZcHjF/DesignSystem?node-id=42-15`
- fileKey: `kL9xQn2VwM8pYrTb4ZcHjF`
- nodeId: `42-15`

## Workflow

Follow these steps in order.

### Step 0: Verify Figma MCP is available

Try a lightweight MCP call such as `get_metadata`. If it fails, stop and show the setup instructions in `references/figma-mcp-setup.md`. Do not proceed without MCP access.

### Step 1: Read design context

Call:

```text
mcp__figma__get_design_context(fileKey="<fileKey>", nodeId="<nodeId>")
```

This returns layout (flex/grid, Auto Layout, constraints), typography, colors, spacing, component structure, and variants.

If the response is truncated:

1. Call `mcp__figma__get_metadata(fileKey="<fileKey>", nodeId="<nodeId>")`.
2. Identify the needed child nodes.
3. Fetch each child with `get_design_context(fileKey="<fileKey>", nodeId="<childNodeId>")`.

### Step 2: Capture visual reference

Call:

```text
mcp__figma__get_screenshot(fileKey="<fileKey>", nodeId="<nodeId>")
```

Keep the screenshot visible while implementing. The screenshot is the source of truth for visual fidelity.

### Step 3: Verify project tokens

Read the active theme's token sources:

- `wp-build.json` `designTokens` path (if defined).
- Theme CSS files that define CSS custom properties (e.g., `style.css`, `assets/css/theme.css`, or files discovered with `Glob`).

Use `mcp__figma__get_variable_defs(fileKey="<fileKey>", nodeId="<nodeId>")` to compare Figma variables with project tokens. Flag discrepancies to the designer.

### Step 4: Map to project conventions

| Figma property | How to map |
|----------------|------------|
| Fill color | Hex → CSS variable or design token from theme CSS |
| Auto Layout gap | px / 4 = spacing scale number (e.g., 16px → `--spacing-4`) |
| Padding | px / 4 → spacing token or utility class |
| Corner radius | Match to `--radius-*` token |
| Drop shadow | Match to `--shadow-*` token |
| Typography | Match heading/body classes defined in theme CSS |

Use project tokens everywhere. Do not hardcode hex values unless the value is intentionally outside the token set.

### Step 5: Generate code

- Reuse existing theme components/patterns first.
- Generate new markup following the active conversion strategy (classic/ACF, block/FSE, or page builder).
- Apply accessibility rules from `skills/wp-a11y/SKILL.md`.
- Document any intentional deviation from the design with a code comment.

## Token pipeline

```text
Figma Variables
    ↓
Figma Variables2CSS export (in browser)
    ↓
wp-build.json designTokens or theme CSS custom properties
    ↓
Theme classes/utilities
    ↓
Production template + CSS
```

When tokens change in Figma, update the project CSS or `wp-build.json` designTokens and rebuild the theme.

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Truncated Figma output | Design too complex | Use `get_metadata`, then fetch children individually |
| Design doesn't match after implementation | Visual discrepancies | Compare with the screenshot; check spacing, colors, typography |
| Assets not loading | MCP assets endpoint unavailable | Verify Figma MCP is running and the asset URL is fresh |
| Token values differ from Figma | Project tokens are out of sync | Prefer project tokens; flag missing tokens to the designer |

## Examples

### Example 1: Audit a component

1. Parse URL → fileKey and nodeId.
2. `get_design_context` + `get_screenshot` + `get_variable_defs`.
3. Read theme token CSS.
4. Output a structured spec report (layout, colors, typography, spacing, missing tokens).

### Example 2: Build a component

1. Run the audit above.
2. Check existing theme `parts/`, `templates/`, or `components/` for similar patterns.
3. Generate PHP/Block/Page-builder markup and CSS using tokens.
4. Run the active build validation command.

## References

- [Figma MCP setup](references/figma-mcp-setup.md)

---

*Ported and rewritten for WP Pro Max from `alessioarzenton/claude-code-wp-toolkit` (GPL-3.0). Target license: MIT.*
