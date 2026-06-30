---
phase: 3
title: "Implement"
status: pending
priority: P1
dependencies: [2]
---

# Phase 3: Implement

## Overview

Build the command, skill, helper script, schema update, and optional root help command.

## Requirements

- Functional: All artifacts from Phase 2 are created/modified.
- Non-functional: Follow existing conventions (manifest-driven, zsh-safe sourced scripts, idempotent).

## Related code files

- Create: `commands/audit.md`
- Create: `skills/wp-audit/SKILL.md`
- Create: `skills/wp-audit/references/checklist.md`
- Create: `scripts/audit-aggregate.sh`
- Modify: `schemas/wp-build.schema.json`
- Optional create: `commands/wp-pro-max.md`

## Implementation steps

1. **Checklist reference**
   - Write `skills/wp-audit/references/checklist.md` with rule definitions from Phase 1.

2. **Aggregation script**
   - Write `scripts/audit-aggregate.sh`:
     - Accepts JSON files from each scanner as input.
     - Normalizes into the `audit.findings[]` schema.
     - Computes severity counts and `passed`.
     - Writes `audit-<timestamp>.json`.
   - Must be zsh-safe and not alter caller shell state.

3. **Skill**
   - Write `skills/wp-audit/SKILL.md`:
     - Frontmatter: `name: wp-audit`, `user-invocable: true`.
     - Static phase: run code-style, a11y, security scans via bash/node helpers.
     - Live phase: detect wp-env, run `wp-qa`, `wp-security`, `wp-performance-backend` probes.
     - Aggregate and write `wp-build.json` audit entry.
     - Emit human report to `docs/audit-<timestamp>.md`.

4. **Command**
   - Write `commands/audit.md`:
     - Parse `--scope`, `--live`, `--static`, `--format`, `--out`.
     - Locate `wp-build.json` and derive project root.
     - Invoke `wp-pro-max:audit` skill with parsed args.
     - Print summary and report paths.

5. **Schema**
   - Add `audit` object to `schemas/wp-build.schema.json`.

6. **Optional root help**
   - Write `commands/wp-pro-max.md` listing commands and current status.

## Success criteria

- [ ] `claude plugin validate .` passes.
- [ ] `bash -n scripts/audit-aggregate.sh` passes.
- [ ] All new markdown files render correctly and follow frontmatter conventions.
- [ ] `wp-build.json` schema accepts the new `audit` object.
