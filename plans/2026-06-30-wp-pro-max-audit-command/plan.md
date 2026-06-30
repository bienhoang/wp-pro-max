---
title: "WP Pro Max Audit Command"
description: "Add /wp-pro-max:audit to scan self-authored theme/plugin code against a best-practice checklist (a11y, security, performance, code style) and emit a report plus wp-build.json entry."
status: done
priority: P2
branch: "main"
tags: [command, skill, audit, a11y, security, performance, code-style, qa]
blockedBy: []
blocks: []
created: "2026-06-30T06:26:07.181Z"
createdBy: "ck:plan"
source: skill
---

# WP Pro Max Audit Command

## Overview

Add a new user-invocable command `/wp-pro-max:audit` that scans the current WP Pro Max target project for best-practice violations across four categories: **a11y**, **security**, **performance**, and **code style / WordPress conventions**. The command is read-only by default, produces a Markdown + JSON report grouped by category, and writes an `audit` entry into `wp-build.json`. It runs static checks always; live checks run only when `wp-env` is running, otherwise the command auto-degrades to static mode with a clear warning.

This plan also optionally defines the bare `/wp-pro-max` prefix behavior via a root help command.

## Background

- Brainstorm report: `reports/brainstorm-2026-06-30-wp-pro-max-audit.md`
- Related completed plans:
  - `plans/2026-06-27-site-editor-command/`
  - `plans/2026-06-28-accessibility-skill-port/`
  - `plans/2026-06-28-port-wp-kit-extras/`
  - `plans/2026-06-28-wp-plugin-development-port/`

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Research](./phase-01-research.md) | pending |
| 2 | [Design](./phase-02-design.md) | pending |
| 3 | [Implement](./phase-03-implement.md) | pending |
| 4 | [Test](./phase-04-test.md) | pending |
| 5 | [Validate](./phase-05-validate.md) | pending |

## Scope

- **In scope**: New `commands/audit.md`, new `skills/wp-audit/SKILL.md`, helper script `scripts/audit-aggregate.sh`, schema update for `audit` in `wp-build.json`, optional `commands/wp-pro-max.md` root help.
- **Out of scope**: Auto-fixing findings, GUI dashboard, CI integration, remote production scanning.

## Success criteria

- `/wp-pro-max:audit` runs in static mode without `wp-env` (auto-degrades with warning if wp-env is not running).
- `/wp-pro-max:audit --live` runs when `wp-env` is available.
- Report groups findings by category (a11y, security, performance, code style).
- Report is written to `docs/audit-<timestamp>.md` and `audit-<timestamp>.json`.
- `wp-build.json` contains `audit.summary` and `audit.findings[]`.
- Default scope only scans self-authored theme + plugin; `--scope all` includes third-party read-only.
- Plugin validates with `claude plugin validate .`.
