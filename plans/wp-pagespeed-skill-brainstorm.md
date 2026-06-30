---
title: "Brainstorm: wp-pagespeed skill integration"
date: 2026-06-26
status: agreed
source: user request + codebase scout
---

# Brainstorm Report: Add `wp-pagespeed` Skill

## 1. Problem-first inversion

**User's starting point:** "Thêm skill hỗ trợ https://github.com/ruslanlap/pagespeed-insights-mcp."

**Underlying problem:** The WP Pro Max toolkit currently audits Core Web Vitals only through local Lighthouse CLI or Playwright fallback inside `wp-qa`. There is no dedicated, reusable skill for running PageSpeed Insights (PSI) audits against a WordPress site, nor any guidance for leveraging the ruslanlap PageSpeed Insights MCP server.

**Alternative framings:**
- We need a PSI audit skill that works regardless of whether the user has configured an MCP client.
- We need a reusable performance-check helper that can be called independently of the `qa` pipeline gate.
- We need documentation that lets users optionally wire the ruslanlap MCP server into their Claude Desktop / compatible client.

**Chosen framing:** Build a standalone `wp-pagespeed` skill that provides both (a) usage guidance for the ruslanlap MCP server and (b) a self-contained bash helper that calls the Google PageSpeed Insights API directly, so the skill is useful even when MCP is not configured.

## 2. Exact requirements captured

| Item | Decision |
|------|----------|
| **Expected output** | New skill `skills/wp-pagespeed/` containing `SKILL.md` + bash helper script(s) in `skills/wp-pagespeed/references/`. |
| **Acceptance criteria** | Skill can audit a single URL and produce a JSON/Markdown report with LCP/CLS/INP/TBT/SI and opportunities. |
| **Scope boundary (out)** | No auto-installation of the MCP server; no CI/CD workflow; no modification to `wp-qa`. |
| **Non-negotiable constraints** | Helper scripts written in Bash; API key from env var `PAGESPEED_API_KEY`; reports written to standalone files, not `wp-build.json`. |
| **Touchpoints** | None modified; skill optionally references `wp-qa` for context but does not depend on it. |

## 3. Evaluated approaches

### Option A — Documentation + direct PSI API bash wrapper (recommended)
- `SKILL.md` explains when to use the skill, how to configure the ruslanlap MCP server in Claude Desktop, and how to fall back to the bash helper.
- `references/run-pagespeed.sh` calls `https://www.googleapis.com/pagespeedonline/v5/runPagespeed` with `curl`, parses JSON with `jq`, and writes a Markdown report.
- **Pros:** Simple, no MCP runtime dependency, easy to test, aligns with existing bash-heavy `scripts/`, satisfies acceptance criteria immediately.
- **Cons:** Does not exercise the 16 MCP tools directly; the MCP server becomes a secondary/advanced usage path.

### Option B — Bash stdio MCP client
- Script spawns `npx pagespeed-insights-mcp`, speaks JSON-RPC over stdin/stdout, and maps tool calls to report sections.
- **Pros:** Truly uses the MCP server and its richer toolset (recommendations, visual analysis, network waterfall, etc.).
- **Cons:** Complex, fragile (pino logs, stdio handling, timeouts), hard to maintain, over-engineered for a single-URL audit requirement.

### Option C — Pure documentation/config template
- `SKILL.md` only provides Claude Desktop config snippet and prompt templates for the 16 tools.
- **Pros:** Faithful to "supporting the MCP server" wording.
- **Cons:** No helper script, so it fails the "Skill + helper scripts" output requirement and is useless if the user has not configured MCP.

## 4. Final recommended solution

**Adopt Option A.**

Rationale:
- Keeps the skill useful out-of-the-box without requiring MCP client setup.
- Honors KISS/YAGNI: the acceptance criteria is a single-URL PSI audit, not a full MCP client implementation.
- Leaves the door open to later enhance the skill with Option B tooling if the user adopts MCP widely.

## 5. Implementation sketch

```text
skills/wp-pagespeed/
├── SKILL.md
└── references/
    ├── run-pagespeed.sh      # bash helper: curl PSI API → JSON + Markdown report
    └── mcp-config.md         # Claude Desktop / Grok / Antigravity config snippets
```

### `SKILL.md` frontmatter
```yaml
---
name: wp-pagespeed
description: >-
  Audit a WordPress page with Google PageSpeed Insights. Use when the user asks
  for performance analysis, Core Web Vitals, Lighthouse scores, or PageSpeed
  Insights reports. Provides a standalone bash helper and optional guidance for
  the ruslanlap PageSpeed Insights MCP server. Reads a URL and strategy;
  writes a standalone JSON/Markdown report.
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---
```

### `references/run-pagespeed.sh` behavior
1. Require env var `PAGESPEED_API_KEY`.
2. Accept positional args: `URL [strategy] [locale]` (defaults: strategy=mobile, locale=en).
3. Call `https://www.googleapis.com/pagespeedonline/v5/runPagespeed`.
4. Extract LCP, CLS, FCP, TBT, SI, INP, overall score, and top opportunities.
5. Write `<timestamp>-pagespeed-<slug>.json` and `<timestamp>-pagespeed-<slug>.md`.
6. Exit non-zero on API error or missing key.

## 6. Risks and considerations

| Risk | Mitigation |
|------|------------|
| PSI API quota / rate limits | Document the free tier; warn users with high-volume use. |
| `jq` not installed | Check early and print install hint; keep script simple enough to be portable. |
| `GOOGLE_API_KEY` vs `PAGESPEED_API_KEY` mismatch | The ruslanlap MCP server uses `GOOGLE_API_KEY`, but user chose `PAGESPEED_API_KEY`. Helper script will read `PAGESPEED_API_KEY`; `mcp-config.md` will use `GOOGLE_API_KEY`. Document the distinction. |
| URL without protocol rejected | Validate `http://` or `https://` prefix before calling API. |
| Scope creep into `wp-qa` | Explicitly gate: skill is standalone; do not modify `wp-qa` in this round. |

## 7. Success metrics

- `skills/wp-pagespeed/SKILL.md` exists with valid frontmatter and clear usage.
- `skills/wp-pagespeed/references/run-pagespeed.sh` runs successfully against a real URL when `PAGESPEED_API_KEY` is set.
- Report contains LCP, CLS, INP/TBT, SI, FCP, overall performance score, and top 5 opportunities.
- Skill mentions the ruslanlap MCP server and provides config guidance without requiring it.

## 8. Next steps and dependencies

1. Create skill directory and files.
2. Test `run-pagespeed.sh` with a sample URL and valid API key.
3. Optionally register the new skill in `.claude-plugin/plugin.json` / `marketplace.json` if project requires skill registration.
4. Hand off to `/ck:plan` for implementation phasing.

**Implementation plan:** [`plans/2026-06-27-wp-pagespeed-skill/plan.md`](./2026-06-27-wp-pagespeed-skill/plan.md)

## 9. Decision log

| Decision | Rationale |
|----------|-----------|
| Skill name `wp-pagespeed` | User preference; clear and consistent with `wp-qa`, `wp-seo`, etc. |
| Bash helper | User preference; matches existing `scripts/*.sh` conventions. |
| Standalone report files | User chose not to touch `wp-build.json`; keeps skill independent. |
| `PAGESPEED_API_KEY` env var | User preference; helper uses this, MCP config uses `GOOGLE_API_KEY` per upstream docs. |
| Option A over B/C | Best balance of functionality, maintainability, and meeting exact acceptance criteria. |
