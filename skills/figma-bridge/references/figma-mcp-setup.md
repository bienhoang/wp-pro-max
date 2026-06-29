# Figma MCP Setup

The Figma bridge is optional. It only works when a Figma MCP server is connected to Claude Code.

## Install the Figma MCP server

1. Open Claude Code settings and add the Figma MCP server from the marketplace, or install it manually if your organization provides one.
2. Restart Claude Code after adding the server.

## Authenticate

1. In Claude Code, open the MCP panel and select the Figma server.
2. Choose **Authenticate** and authorize Claude Code to read your Figma files.
3. The OAuth token is persisted across sessions.

## Verify

Run a lightweight test call:

```text
mcp__figma__get_metadata(fileKey="<a-known-file-key>")
```

If it returns metadata, the bridge is ready.

## Scope

The Figma MCP server should have read access to:

- File metadata
- Design context (nodes, layout, styles)
- Screenshots
- Variables / design tokens

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `mcp__figma__*` tool not found | MCP server is not installed or not loaded. Add it and restart. |
| Authentication fails | Re-authenticate in the MCP panel. Ensure the Figma account can access the file. |
| Empty response | Verify the file key and node id. Some files require explicit team/organization access. |

---

*Condensed from `alessioarzenton/claude-code-wp-toolkit` (GPL-3.0). Target license: MIT.*
