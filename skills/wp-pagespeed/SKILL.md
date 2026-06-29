---
name: wp-pagespeed
description: >-
  Audit any public URL with Google PageSpeed Insights. Use when the user asks
  for performance analysis, Core Web Vitals, Lighthouse scores, or PageSpeed
  Insights reports. Provides a standalone bash helper and optional guidance for
  wiring the ruslanlap PageSpeed Insights MCP server. Reads a URL and strategy;
  writes a standalone JSON/Markdown report.
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# WP PageSpeed

Audit a public URL with Google PageSpeed Insights v5 and get a self-contained
JSON/Markdown report.

## When to use

- User asks for a "PageSpeed Insights", "Lighthouse", "Core Web Vitals", or
  "performance audit" of a URL.
- Complement `wp-qa` by spot-checking a production URL without running the full
  pipeline.
- Compare mobile vs. desktop performance for a WordPress site.

## Prerequisites

- `curl`
- `jq`
- A Google API key exported as `PAGESPEED_API_KEY`

Get a key from [Google Cloud Console](https://developers.google.com/speed/docs/insights/v5/get-started#APIKey)
if you do not have one.

## Quick use

```bash
export PAGESPEED_API_KEY="your-key"
bash skills/wp-pagespeed/references/run-pagespeed.sh https://example.com mobile
```

Arguments:

1. URL (required) — must start with `http://` or `https://`.
2. Strategy (optional) — `mobile` (default) or `desktop`.
3. Locale (optional) — defaults to `en`.

The helper writes two files in the current directory:

- `<timestamp>-pagespeed-<slug>.json` — raw PSI response plus metadata.
- `<timestamp>-pagespeed-<slug>.md` — human-readable report.

## What the report contains

- Overall performance score (0–100).
- Core Web Vitals and lab metrics: LCP, CLS, FCP, TBT, SI, INP (when available).
- Top 5 opportunities sorted by estimated savings.
- One-line recommendation summary.

## Test without an API key

The checked-in sample response lets you validate report generation offline:

```bash
bash skills/wp-pagespeed/references/run-pagespeed.sh \
  --sample skills/wp-pagespeed/references/sample-psi-response.json
```

## MCP server (optional)

You can wire the upstream
[ruslanlap/pagespeed-insights-mcp](https://github.com/ruslanlap/pagespeed-insights-mcp)
server into Claude Desktop, Grok, or Antigravity. This is **optional** — the
skill works standalone. See `references/mcp-config.md` for copy-paste snippets.

## Localhost / internal URLs

PageSpeed Insights can only audit public URLs. To audit a local WordPress site,
expose it temporarily with one of:

- [ngrok](https://ngrok.com/): `ngrok http 8888`
- [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/): `cloudflared tunnel --url http://localhost:8888`
- [localtunnel](https://localtunnel.github.io/www/): `npx localtunnel --port 8888`

Then pass the public tunnel URL to the helper.

## Limits

- The PSI API enforces quota per API key.
- Only `http://` and `https://` URLs are accepted.
- The helper retries once after 2 seconds on HTTP 429 or 5xx errors.
- Never pass `PAGESPEED_API_KEY` as a command-line argument; always `export` it.

## References

- `references/run-pagespeed.sh` — standalone audit helper.
- `references/mcp-config.md` — optional MCP server config snippets.
- `references/sample-psi-response.json` — offline sample for testing.
