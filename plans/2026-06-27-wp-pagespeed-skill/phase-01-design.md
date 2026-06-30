---
phase: 1
title: "Design"
status: completed
priority: P2
dependencies: []
---

# Phase 1: Design

## Overview

Lock the data contract and file layout before writing code. Verify the PSI v5
API response shape, decide which metrics to extract, and confirm the skill
follows the project's existing skill conventions.

## Requirements

- Functional: define the exact PSI API endpoint, query parameters, and JSON
  paths used to extract scores, metrics, and opportunities.
- Non-functional: keep the helper dependency-free except for `curl` and `jq`;
  match the style of existing `scripts/*.sh` and `skills/*/SKILL.md` files.

## Architecture

```text
skills/wp-pagespeed/
├── SKILL.md
└── references/
    ├── run-pagespeed.sh
    ├── mcp-config.md
    └── sample-psi-response.json
```

- `SKILL.md` is the only file the model reads by default; it links to
  `references/` for deep detail.
- `run-pagespeed.sh` is a standalone bash helper invoked directly by the user
  or by the agent on the user's behalf.
- `mcp-config.md` is optional reference material; it does not execute anything.

### PSI API contract

Endpoint:

```text
https://www.googleapis.com/pagespeedonline/v5/runPagespeed
  ?url=<encoded-url>
  &strategy=<mobile|desktop>
  &locale=<locale>
  &key=<PAGESPEED_API_KEY>
```

Key response paths:

| Field | jq path |
|-------|---------|
| Overall performance score | `.lighthouseResult.categories.performance.score` (0–1) |
| LCP | `.lighthouseResult.audits["largest-contentful-paint"].numericValue` (ms) |
| CLS | `.lighthouseResult.audits["cumulative-layout-shift"].numericValue` |
| FCP | `.lighthouseResult.audits["first-contentful-paint"].numericValue` (ms) |
| TBT | `.lighthouseResult.audits["total-blocking-time"].numericValue` (ms) |
| SI | `.lighthouseResult.audits["speed-index"].numericValue` (ms) |
| INP | `.lighthouseResult.audits["interaction-to-next-paint"]` (may be missing) |
| Opportunities | `.lighthouseResult.audits | to_entries[] | select(.value.details.type == "opportunity")` |

### Report format

- JSON: raw PSI response plus a small `_wpProMaxMeta` block (url, strategy,
  fetchedAt).
- Markdown: human-readable table of scores/metrics, top 5 opportunities sorted
  by savings, and a one-line recommendation summary.

## Related Code Files

- Read: `references/manifest-contract.md`
- Read: `skills/wp-qa/SKILL.md` and `skills/wp-qa/references/core-web-vitals.mjs`
- Read: `skills/wp-plugin-dev/SKILL.md` (for frontmatter and reference style)
- Create: `skills/wp-pagespeed/SKILL.md`
- Create: `skills/wp-pagespeed/references/run-pagespeed.sh`
- Create: `skills/wp-pagespeed/references/mcp-config.md`
- Create: `skills/wp-pagespeed/references/sample-psi-response.json`

## Implementation Steps

1. Read `references/manifest-contract.md` and at least two existing skill
   `SKILL.md` files to confirm frontmatter and layout conventions.
2. Call the PSI API once manually with `curl` and inspect the JSON shape for a
   known URL (e.g., `https://example.com`). Save the response as a temporary
   reference.
3. Draft the jq extraction commands for score, metrics, and opportunities.
4. Define the Markdown report template and filename convention.
5. Document the env-var contract (`PAGESPEED_API_KEY`) and CLI argument shape
   for the helper script.
6. Review the design with the user if any assumption changed; otherwise mark
   phase complete and move to Phase 2.

## Success Criteria

- [ ] PSI v5 response shape is confirmed and sample JSON paths are documented.
- [ ] Extraction strategy for LCP, CLS, FCP, TBT, SI, INP, score, and top 5
      opportunities is decided.
- [ ] Output filenames and report structure are defined.
- [ ] No unresolved design questions remain before implementation starts.

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| PSI API field names differ from Lighthouse docs | Validate with a live response in step 2; keep jq paths in variables so they are easy to adjust. |
| INP audit missing in older Lighthouse versions | Treat INP as optional; report "n/a" when absent. |
| `jq` not available on target machine | Document `jq` as a prerequisite and print an install hint on failure. |
