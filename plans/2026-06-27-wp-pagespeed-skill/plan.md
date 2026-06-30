---
title: "Add wp-pagespeed skill with PageSpeed Insights support"
description: "Create a standalone wp-pagespeed skill that audits any URL via Google PageSpeed Insights API and optionally guides users to wire the ruslanlap PageSpeed Insights MCP server."
status: completed
priority: P2
branch: "main"
tags: [skill, performance, pagespeed, mcp]
blockedBy: []
blocks: []
created: "2026-06-27T10:14:02.646Z"
createdBy: "ck:plan"
source: skill
---

# Add wp-pagespeed skill with PageSpeed Insights support

## Overview

Add a reusable, standalone skill `wp-pagespeed` to the WP Pro Max toolkit. The
skill lets a user audit any public URL with Google PageSpeed Insights (PSI) and
produces a self-contained JSON + Markdown report. It also documents how to wire
the upstream [ruslanlap/pagespeed-insights-mcp](https://github.com/ruslanlap/pagespeed-insights-mcp)
server into a Claude Desktop / Grok / Antigravity client, but does **not**
require the MCP server to function.

Design source: [`../wp-pagespeed-skill-brainstorm.md`](../wp-pagespeed-skill-brainstorm.md)

## Scope

**In scope:**
- `skills/wp-pagespeed/SKILL.md` with valid frontmatter and usage instructions.
- `skills/wp-pagespeed/references/run-pagespeed.sh` — bash helper that calls the
  PSI API directly via `curl`, parses with `jq`, and writes JSON/Markdown reports.
- `skills/wp-pagespeed/references/mcp-config.md` — copy-paste config snippets for
  Claude Desktop, Grok, and Antigravity.
- `skills/wp-pagespeed/references/sample-psi-response.json` — checked-in PSI
  response for offline parsing tests.
- Test the helper via the sample response; live API test is optional if a key
  is unavailable.

**Out of scope:**
- Automatic installation of the MCP server.
- CI/CD workflow or scheduled audits.
- Modification of `wp-qa` or any pipeline stage.
- Writing results into `wp-build.json`.

## Acceptance criteria

- [ ] `skills/wp-pagespeed/SKILL.md` exists, frontmatter validates, and describes
      when / how to invoke the skill.
- [ ] `skills/wp-pagespeed/references/run-pagespeed.sh` exists, is `bash -n` clean,
      and runs on zsh+bash.
- [ ] Running the helper with `PAGESPEED_API_KEY` set audits a single URL,
      retries once on 429/5xx after 2s, and writes both
      `<timestamp>-pagespeed-<slug>.json` and `.md` with nanosecond timestamps
      to avoid overwrites.
- [ ] Markdown report includes overall score, LCP, CLS, FCP, TBT, SI, INP (when
      available), and the top 5 opportunities.
- [ ] Missing / invalid API key, missing URL, bad URL scheme, URLs with
      embedded credentials, and URLs with shell metacharacters produce clear
      error messages and non-zero exit codes.
- [ ] Script never echoes `PAGESPEED_API_KEY` and documents export-only usage.
- [ ] Skill mentions the ruslanlap MCP server and provides `mcp-config.md`
      without making it mandatory.
- [ ] Skill explains how to audit localhost/internal sites via a public tunnel
      (ngrok / Cloudflare Tunnel).
- [ ] A checked-in `sample-psi-response.json` lets the helper generate a report
      without a live API key for testing/parsing validation.

## Phases

| Phase | Name | Status | File |
|-------|------|--------|------|
| 1 | [Design](./phase-01-design.md) | Completed | `phase-01-design.md` |
| 2 | [Implement](./phase-02-implement.md) | Completed | `phase-02-implement.md` |
| 3 | [Test](./phase-03-test.md) | Completed | `phase-03-test.md` |
| 4 | [Document](./phase-04-document.md) | Completed | `phase-04-document.md` |

## Dependencies

None. This plan is additive and standalone; it does not block or depend on other
in-flight plans.
