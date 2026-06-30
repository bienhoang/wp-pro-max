---
phase: 2
title: "PerfBackend"
status: done
priority: P2
dependencies: [1]
---

# Phase 2: Port `wp-performance-backend` skill

## Overview

Create `skills/wp-performance-backend/SKILL.md` that diagnoses and resolves backend performance issues in the context of WP Pro Max's `wp-env` pipeline.

## Requirements

- **Functional**: Skill provides baseline → diagnose → fix → verify workflow for TTFB, DB queries, autoload options, object cache, cron, and remote HTTP.
- **Non-functional**: User-invocable; uses `wp-env run cli wp …` for all WP-CLI commands; targets WordPress 7.x; rewritten from source.

## Related Code Files

- **Create**: `skills/wp-performance-backend/SKILL.md`
- **Modify**: none
- **Delete**: none

## TDD Tests (write first)

1. `scripts/validate-port.sh skills/wp-performance-backend/SKILL.md` passes frontmatter check.
2. The file does not contain `{{TEXT_DOMAIN}}`, `{{PREFIX}}`, or other `{{VAR}}` placeholders.
3. Every WP-CLI snippet uses `wp-env run cli wp …` (not bare `wp` or Bedrock `--path=web/wp` as default).
4. The file mentions "WordPress 7.x" or "WordPress 7" at least once.
5. No Bedrock-only paths (e.g., `web/app/`, `web/wp`) appear unless explicitly marked optional.

## Implementation Steps

1. Run the tests above; confirm they fail (red).
2. Create `skills/wp-performance-backend/SKILL.md` with frontmatter:
   ```yaml
   ---
   name: wp-performance-backend
   description: >-
     Diagnose and optimize WordPress 7.x backend performance: TTFB, DB queries,
     object cache, autoload options, cron, and remote HTTP. Use during QA or when
     a generated site feels slow. Works inside the wp-env pipeline.
   user-invocable: true
   allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
   ---
   ```
3. Rewrite content from the source, keeping the structure but adapting:
   - Replace bare WP-CLI with `wp-env run cli wp …`.
   - Replace curl examples with a note that the target URL comes from `wp-build.json` `env.localUrl` or can be discovered via `wp-env run cli wp option get home`.
   - Replace `{{TEXT_DOMAIN}}` cache group with the actual theme slug from `wp-build.json`.
   - Update "WordPress 6.9" section to "WordPress 7.x performance improvements" (or remove if specifics are unknown; keep generic).
   - Keep guardrails (no `SAVEQUERIES`/`WP_DEBUG` in production, measure before fixing).
4. Add a short license attribution footer.
5. Re-run tests; confirm green.

## Success Criteria

- [x] `skills/wp-performance-backend/SKILL.md` exists and passes `validate-port.sh`.
- [x] No `{{VAR}}` placeholders remain.
- [x] All WP-CLI examples use `wp-env run cli wp …`.
- [x] File mentions WordPress 7.x.
- [x] Baseline → diagnose → fix → verify workflow is preserved.
