---
phase: 2
title: "Design"
status: done
priority: P1
dependencies: [1]
---

# Phase 2: Design

## Overview

Design the command interface, data model, file layout, static/live detection, scope rules, and aggregation format.

## Requirements

- Functional: `/wp-pro-max:audit` with flags `--scope`, `--live`, `--static`, `--format`, `--out`. Report grouped by category.
- Non-functional: Manifest-driven, idempotent, read-only on source files, auto-degrade to static when wp-env is unavailable.

## Architecture

```
/wp-pro-max:audit [--scope self|all] [--live|--static] [--format md|json|both] [--out <dir>]
  │
  ├─ Locate wp-build.json → derive theme.path & plugin root
  ├─ Detect wp-env status
  │   └─ If wp-env missing/unreachable and --live not requested → warn and run static only
  ├─ Static phase (always)
  │   ├─ code-style scan (PHPCS/WPCS or fallback regex)
  │   ├─ a11y scan (axe on HTML/templates or manual checklist)
  │   └─ security scan (secrets + unsafe patterns)
  ├─ Live phase (if wp-env running)
  │   ├─ performance (CWV, TTFB, queries, autoload)
  │   ├─ security (vuln scan, active user audit)
  │   └─ a11y (axe on rendered URLs)
  └─ Aggregate → wp-build.json audit entry + reports
```

## Data model

Add to `wp-build.json`:

```json
"audit": {
  "generatedAt": "2026-06-30T...",
  "mode": "static|live",
  "scope": "self|all",
  "summary": {
    "total": 0,
    "critical": 0,
    "high": 0,
    "medium": 0,
    "low": 0,
    "passed": false
  },
  "findings": [
    {
      "id": "a11y-missing-alt",
      "category": "a11y",
      "severity": "high",
      "file": "wp-content/themes/foo/parts/hero.php",
      "line": 12,
      "message": "Informative <img> is missing alt text.",
      "suggestion": "Add descriptive alt or alt=\"\" if decorative."
    }
  ]
}
```

## Scope rules

- `--scope self` (default): theme path from `theme.path` + plugin root if `wp-plugin.json` exists; ignore `node_modules`, `vendor`, `.wp-env`, core/plugins unless mapped.
- `--scope all`: include third-party plugins/themes but flag them as `external: true` and never auto-fix.

## Related code files

- Create: `commands/audit.md`, `skills/wp-audit/SKILL.md`, `skills/wp-audit/references/checklist.md`, `scripts/audit-aggregate.sh`
- Modify: `schemas/wp-build.schema.json`
- Optional create: `commands/wp-pro-max.md`

## Report grouping

Findings are grouped by category in both Markdown and JSON outputs:

```
## a11y
- [high] a11y-missing-alt ...

## security
- [medium] sec-direct-superglobal ...

## performance
- [low] perf-unoptimized-image ...

## code-style
- [high] wpcs-missing-sanitize ...
```

## Implementation steps

1. Write `commands/audit.md` frontmatter and procedure.
2. Write `skills/wp-audit/SKILL.md` with static/live routing and aggregation.
3. Design `scripts/audit-aggregate.sh` input/output contract.
4. Update `schemas/wp-build.schema.json` with `audit` property.
5. Optionally design `commands/wp-pro-max.md` root help output.

## Success criteria

- [ ] `commands/audit.md` defines CLI interface and orchestration.
- [ ] `skills/wp-audit/SKILL.md` defines static/live phases and delegation.
- [ ] Schema update accepted by `claude plugin validate .`.
- [ ] Report template designed for Markdown + JSON.
