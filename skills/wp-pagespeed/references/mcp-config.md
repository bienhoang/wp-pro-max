# PageSpeed Insights MCP Server Config

Optional wiring for the upstream
[ruslanlap/pagespeed-insights-mcp](https://github.com/ruslanlap/pagespeed-insights-mcp)
server. The `wp-pagespeed` skill works without this server.

## Claude Desktop

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "pagespeed-insights": {
      "command": "npx",
      "args": ["-y", "pagespeed-insights-mcp"],
      "env": {
        "GOOGLE_API_KEY": "your-api-key"
      }
    }
  }
}
```

## Grok

Add to `~/.grok/config.toml` or project-scoped `.grok/config.toml`:

```toml
[[mcp.servers]]
name = "pagespeed-insights"
command = "npx"
args = ["-y", "pagespeed-insights-mcp"]
env = { GOOGLE_API_KEY = "your-api-key" }
```

## Google Antigravity

Add to `~/.gemini/config/mcp_config.json`:

```json
{
  "mcpServers": {
    "pagespeed-insights": {
      "command": "npx",
      "args": ["-y", "pagespeed-insights-mcp"],
      "env": {
        "GOOGLE_API_KEY": "your-api-key"
      }
    }
  }
}
```

## Notes

- Replace `your-api-key` with a Google Cloud API key that has PageSpeed Insights
  API access enabled.
- The env var name expected by the upstream server is `GOOGLE_API_KEY`, not
  `PAGESPEED_API_KEY`.
- Keep the config file out of version control; it contains a secret.
