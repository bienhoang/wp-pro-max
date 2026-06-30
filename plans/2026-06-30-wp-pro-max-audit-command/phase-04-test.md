---
phase: 4
title: "Test"
status: pending
priority: P2
dependencies: [3]
---

# Phase 4: Test

## Overview

Exercise the audit command in static and live modes, verify outputs, and catch edge cases.

## Requirements

- Functional: Command runs correctly on sample project and generated theme/plugin.
- Non-functional: No destructive side effects; reports are deterministic enough for re-runs.

## Test matrix

| Scenario | Command | Expected |
|---|---|---|
| No manifest | `/wp-pro-max:audit` | Friendly error: run init/build first. |
| Static only | `/wp-pro-max:audit --static` | Runs code-style/a11y/security static scans; no wp-env needed. |
| Live with wp-env | `/wp-pro-max:audit --live` | Runs live performance/security/a11y probes. |
| Scope all | `/wp-pro-max:audit --scope all` | Includes third-party plugins/themes as external. |
| Re-run | `/wp-pro-max:audit` twice | Overwrites previous audit entry; stable output. |

## Implementation steps

1. Run `claude plugin validate .` after all files are in place.
2. Syntax-check new scripts:
   - `bash -n scripts/audit-aggregate.sh`
   - `node --check` any new `.mjs` helpers.
3. Test static mode on `examples/sample-site` or a fresh `wp-pro-max:init` project.
4. If Docker available, start wp-env and test live mode.
5. Verify report files and `wp-build.json` audit entry.
6. Test `--scope all` and confirm external findings are marked.

## Success criteria

- [ ] Plugin validates.
- [ ] Static mode completes without errors.
- [ ] Live mode completes when wp-env is running.
- [ ] Reports contain findings for each requested category when issues exist.
- [ ] Re-running produces updated but structurally stable output.
