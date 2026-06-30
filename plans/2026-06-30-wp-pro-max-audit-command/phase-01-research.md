---
phase: 1
title: "Research"
status: pending
priority: P1
dependencies: []
---

# Phase 1: Research

## Overview

Inventory existing skills, scripts, references, and available tooling so the audit command reuses as much as possible and defines exact checklist rules.

## Requirements

- Functional: Produce a concrete checklist per category with rule IDs, severity, and detection method.
- Non-functional: Prefer repo-existing tools; document fallbacks when a tool is missing.

## Related code files

- Read: `skills/wp-qa/SKILL.md`, `skills/wp-security/SKILL.md`, `skills/wp-a11y/SKILL.md`, `skills/accessibility/SKILL.md`, `skills/wp-performance-backend/SKILL.md`, `skills/wp-plugin-development/SKILL.md`
- Read: `scripts/visual-diff.mjs`, `scripts/pre-qa-*.mjs`, `skills/wp-security/references/secrets-scan.sh`
- Read: `schemas/wp-build.schema.json`, `references/manifest-contract.md`

## Implementation steps

1. Review existing skill/reference files and extract reusable rules:
   - a11y: `skills/wp-a11y/SKILL.md` and `skills/accessibility/references/accessibility-checklist.md`
   - security: `skills/wp-security/references/hardening-checklist.md`, `references/secrets-scan.sh`, plugin security baseline
   - performance: `skills/wp-performance-backend/SKILL.md`, `skills/wp-pagespeed/references/run-pagespeed.sh`
   - code style: `skills/wp-plugin-development/references/plugin-security-baseline.md`, WPCS rules
2. Determine which tools are reliably available:
   - `phpcs` + WPCS inside wp-env
   - `axe-core` via Playwright (`skills/wp-qa/references/a11y-axe.mjs`)
   - `lighthouse` / PageSpeed Insights
   - `wp doctor` (optional)
3. Define the detection matrix: for each rule, specify static regex, static tool, or live tool.
4. Draft `skills/wp-audit/references/checklist.md` with rule IDs, severities, and messages.

## Success criteria

- [ ] `skills/wp-audit/references/checklist.md` exists and covers a11y, security, performance, code style.
- [ ] Each rule has `id`, `category`, `severity`, `scope`, `detection`, `messageTemplate`.
- [ ] Tool inventory lists primary and fallback for each category.
