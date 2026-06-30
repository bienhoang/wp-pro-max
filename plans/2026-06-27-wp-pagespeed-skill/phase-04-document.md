---
phase: 4
title: "Document"
status: completed
priority: P2
dependencies: [3]
---

# Phase 4: Document

## Overview

Do a final review pass, cross-link the brainstorm report, and ensure the skill
is discoverable and consistent with the rest of the toolkit.

## Requirements

- Functional: all new files are self-contained and follow project conventions.
- Non-functional: no dead links; no secrets committed; no leftover temp files.

## Architecture

Final artifact tree:

```text
skills/wp-pagespeed/
├── SKILL.md
└── references/
    ├── run-pagespeed.sh
    ├── mcp-config.md
    └── sample-psi-response.json
```

## Related Code Files

- Read: `skills/wp-pagespeed/SKILL.md`
- Read: `skills/wp-pagespeed/references/run-pagespeed.sh`
- Read: `skills/wp-pagespeed/references/mcp-config.md`
- Read: `skills/wp-pagespeed/references/sample-psi-response.json`
- Read: `../wp-pagespeed-skill-brainstorm.md`

## Implementation Steps

1. Review `SKILL.md` for clarity, concision, and correct frontmatter.
2. Review `run-pagespeed.sh` for:
   - `set -euo pipefail`
   - No hardcoded secrets
   - `PAGESPEED_API_KEY` never echoed
   - URL validation rejects credentials, shell metacharacters, and bad schemes
   - Slug sanitized to `[a-zA-Z0-9_-]`
   - Filenames include nanosecond timestamps
   - Consistent quoting and error handling
   - Portable path handling
3. Review `mcp-config.md` for accuracy against upstream repo examples.
4. Review `sample-psi-response.json` to ensure it contains the fields the
   helper expects and does not include any private URLs or keys.
5. Ensure the brainstorm report links to this plan and vice versa.
6. Run `git status` and confirm only intended files are modified.
7. Remove any temporary sample JSON/Markdown reports generated during testing.
8. Update this plan's `plan.md` status to `completed` (or use `ck plan check`)
   once all acceptance criteria are met.
9. Mark phase complete.

## Success Criteria

- [ ] All new files follow the skill layout from `references/manifest-contract.md`.
- [ ] No secrets, API keys, or personal URLs are committed.
- [ ] `plan.md` and brainstorm report cross-reference each other.
- [ ] `git status` shows only expected new files under `skills/wp-pagespeed/`.
- [ ] Plan status is updated to completed.

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Temporary test reports committed | Add `*.json` and `*.md` reports to `.gitignore` if they land in the project root, or delete them before commit. |
| Skill description does not trigger auto-invocation | Include trigger words: "PageSpeed Insights", "Lighthouse", "Core Web Vitals", "performance audit". |
| Upstream MCP config changes | Link to upstream repo; keep snippets minimal and well-commented. |
