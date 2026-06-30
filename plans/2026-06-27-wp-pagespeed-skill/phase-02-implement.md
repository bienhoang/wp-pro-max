---
phase: 2
title: "Implement"
status: completed
priority: P2
dependencies: [1]
---

# Phase 2: Implement

## Overview

Create the skill directory, write `SKILL.md`, the bash helper, and the MCP
configuration reference.

## Requirements

- Functional: skill can be discovered by the model; helper audits one URL and
  writes JSON + Markdown reports.
- Non-functional: bash script is `bash -n` and zsh-safe; follows existing
  project conventions; fails loudly on errors.

## Architecture

### `skills/wp-pagespeed/SKILL.md`

Frontmatter:

```yaml
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
```

Body sections (imperative, ≤ ~180 lines):

1. **When to use** — trigger phrases and relationship to `wp-qa`.
2. **Prerequisites** — `curl`, `jq`, and a `PAGESPEED_API_KEY` env var.
3. **Quick use** — run the helper directly:
   ```bash
   PAGESPEED_API_KEY=xxx bash skills/wp-pagespeed/references/run-pagespeed.sh \
     https://example.com mobile
   ```
4. **What the report contains** — score, CWV metrics, opportunities.
5. **MCP server (optional)** — brief mention + link to `references/mcp-config.md`.
6. **Localhost / internal URLs** — PSI API requires a public URL. To audit a
   local WordPress site, expose it temporarily via ngrok, Cloudflare Tunnel, or
   similar, then pass the public tunnel URL to the helper.
7. **Limits** — PSI API quota, `http(s)://` only.

### `skills/wp-pagespeed/references/run-pagespeed.sh`

Behavior:

1. `set -euo pipefail`.
2. If first arg is `--sample`, read the sample JSON path at `$2`, skip the API
   call, and generate the Markdown report directly. Useful for testing without a
   live key.
3. Otherwise, check `PAGESPEED_API_KEY` is non-empty; else print error and exit 1.
4. Validate `$1` exists and starts with `http://` or `https://`; else exit 1.
5. `STRATEGY="${2:-mobile}"`; accept only `mobile` or `desktop`.
6. `LOCALE="${3:-en}"`.
7. Build slug from URL host + path for filenames.
8. Call PSI API with `curl -fsSL --max-time 60`. On HTTP 429/5xx, sleep 2s and retry once.
9. Write raw JSON to `<timestamp>-pagespeed-<slug>.json`.
10. Extract metrics with `jq` and write Markdown to `<timestamp>-pagespeed-<slug>.md`.
11. Print both output paths on success.

Key implementation details:

- Score display: multiply by 100 and round to integer.
- Metric display: convert ms to seconds when value ≥ 1000ms, keep ms otherwise.
- Opportunities: filter `details.type == "opportunity"`, sort by
  `.numericValue` (savings in ms) descending, take top 5.
- INP: fallback to `"n/a"` if audit missing.
- URL sanitization: reject URLs with embedded credentials (`user:pass@`),
  shell metacharacters, or path traversal patterns; always quote URL when
  passing to `curl`.
- Slug sanitization: reduce to `[a-zA-Z0-9_-]`; replace runs of unsafe chars
  with a single `-`.
- Filename uniqueness: include nanosecond timestamp (`date +%Y%m%d-%H%M%S-%N`)
  to avoid overwrites within the same second.
- Key hygiene: never echo `PAGESPEED_API_KEY`; document that users should
  export it, not pass it on the command line.

### `skills/wp-pagespeed/references/mcp-config.md`

Copy-paste snippets for:

- Claude Desktop (`~/Library/Application Support/Claude/claude_desktop_config.json`)
- Grok (`~/.grok/config.toml` or project-scoped `.grok/config.toml`)
- Google Antigravity (`~/.gemini/config/mcp_config.json`)

Each snippet must set `GOOGLE_API_KEY` (the upstream server's expected env var)
and use the npm package `pagespeed-insights-mcp`.

## Related Code Files

- Create: `skills/wp-pagespeed/SKILL.md`
- Create: `skills/wp-pagespeed/references/run-pagespeed.sh`
- Create: `skills/wp-pagespeed/references/mcp-config.md`
- Create: `skills/wp-pagespeed/references/sample-psi-response.json`

## Implementation Steps

1. Create directory `skills/wp-pagespeed/references/`.
2. Write `SKILL.md` with frontmatter and body sections.
3. Write `run-pagespeed.sh` following the behavior spec above.
4. Write `mcp-config.md` with the three client config snippets.
5. Create `sample-psi-response.json` from a real or sanitized PSI response so
   Phase 3 can test parsing without a live key.
6. Run `bash -n` and `zsh -n` (if available) on `run-pagespeed.sh`.
7. Mark phase complete and move to Phase 3.

## Success Criteria

- [ ] `skills/wp-pagespeed/SKILL.md` exists with valid YAML frontmatter.
- [ ] `skills/wp-pagespeed/references/run-pagespeed.sh` exists and passes
      `bash -n` syntax check.
- [ ] `skills/wp-pagespeed/references/mcp-config.md` exists with copy-paste
      snippets for Claude Desktop, Grok, and Antigravity.
- [ ] `skills/wp-pagespeed/references/sample-psi-response.json` exists and is
      valid JSON for offline parsing tests.
- [ ] Script handles missing API key, missing URL, bad URL scheme, invalid
      strategy, URLs with embedded credentials, and URLs with shell
      metacharacters with clear errors and non-zero exit codes.

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| jq query fails on unexpected JSON | Use `jq -e` and catch errors; print raw JSON path for debugging. |
| URL slug contains unsafe characters | Sanitize with `sed`/`tr` to `[a-zA-Z0-9_-]`. |
| Command injection via URL | Always quote URL variable; reject shell metacharacters and embedded credentials. |
| Path traversal in filename | Sanitize slug; never use raw URL path as filename. |
| File overwrite within same second | Include nanosecond timestamp in filename. |
| API key leak | Never echo `PAGESPEED_API_KEY`; document export-only usage. |
| API returns 429/5xx | Retry once after 2s; do not retry on 4xx client errors. |
| Markdown report format breaks | Generate a sample report during Phase 3 and visually inspect. |
