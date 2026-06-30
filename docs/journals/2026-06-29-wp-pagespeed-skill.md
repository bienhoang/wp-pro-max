# WP PageSpeed Skill — Implementation Complete

**Date:** 2026-06-29  
**Plan:** `plans/2026-06-27-wp-pagespeed-skill/`

## What changed

Added a standalone `wp-pagespeed` skill to the WP Pro Max toolkit for auditing
public URLs with Google PageSpeed Insights v5:

- `skills/wp-pagespeed/SKILL.md` — model-invocable skill with frontmatter,
  usage instructions, MCP server mention, and localhost tunnel guidance.
- `skills/wp-pagespeed/references/run-pagespeed.sh` — bash helper that calls
  the PSI API directly (or reads a sample response), writes JSON/Markdown
  reports, and handles errors and retries.
- `skills/wp-pagespeed/references/mcp-config.md` — optional copy-paste config
  snippets for Claude Desktop, Grok, and Antigravity using the upstream
  `pagespeed-insights-mcp` server.
- `skills/wp-pagespeed/references/sample-psi-response.json` — checked-in PSI
  response for offline parsing and report-generation tests.

## Key design decisions

- Kept the skill MCP-agnostic: the bash helper works with only `curl`, `jq`,
  and a `PAGESPEED_API_KEY` env var. The MCP server is documented as optional.
- Used `PAGESPEED_API_KEY` for the helper (user preference) and documented
  `GOOGLE_API_KEY` in `mcp-config.md` to match the upstream server's contract.
- Rejected dangerous shell metacharacters in URLs while allowing `?` and `&`
  so query-string URLs work; the URL is URI-encoded before any shell use.
- Retried only on HTTP 429 or 5xx by capturing the status code with curl's
  `--write-out` flag.
- Included nanosecond timestamps in filenames to avoid overwrites.

## Verification

- `bash -n` and `zsh -n` both pass.
- Negative cases produce clear errors and non-zero exits:
  missing API key, missing URL, bad scheme, embedded credentials,
  shell metacharacters, and invalid strategy.
- Sample-response mode generates a Markdown report with overall score,
  LCP, CLS, FCP, TBT, SI, INP, and the top 5 opportunities.
- Sample mode supports optional `strategy` and `locale` overrides.
- No secrets or API keys were committed.

## Follow-ups

- Validate against a live URL once a `PAGESPEED_API_KEY` is available.
- Consider adding a `--output-dir` flag if users want reports outside the
  current working directory.
