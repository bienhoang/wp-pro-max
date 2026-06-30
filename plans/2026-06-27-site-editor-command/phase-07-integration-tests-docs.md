---
phase: 7
title: "Integration Tests & Docs"
status: done
priority: P2
dependencies: [3, 4, 5, 6]
---

# Phase 7: Integration Tests & Docs

## Overview

Run an end-to-end integration test on `examples/sample-site`, fix any issues, and update project documentation so the new command is discoverable.

## Requirements

- Functional: A full `site-editor` workflow runs on `examples/sample-site`: optimize → redesign → add page → enrich → pre-conversion QA → preview.
- Functional: After site-editor changes, the pipeline can continue through `theme-conversion` and `wp-qa` without errors.
- Functional: `source/` remains untouched after the whole workflow.
- Non-functional: Docs updated in `docs/codebase-summary.md` and `docs/project-roadmap.md` (if present) to mention the new command/skills.

## Architecture

Integration test script: `plans/2026-06-27-site-editor-command/fixtures/integration-test.sh`

Steps:

1. Set up a temp copy of `examples/sample-site` as `source/` in a mock project.
2. Run `html-optimization` to produce `.wp-pro-max/optimized/`.
3. Run `/wp-pro-max:site-editor --redesign "reorder services before hero on index"`.
4. Run `/wp-pro-max:site-editor --add-pages "contact"`.
5. Run `/wp-pro-max:site-editor --enrich "improve alt text and meta descriptions"`.
6. Run `/wp-pro-max:site-editor --check`.
7. Assert `siteEditor.*` manifest state is consistent and `source/` is unchanged.
8. Continue through `theme-conversion` and `wp-qa` (optional, requires wp-env).
9. Verify that `theme-conversion` warns (but does not fail) if `siteEditor.preConversionQa.passed == false`.

## Related Code Files

- Create: `plans/2026-06-27-site-editor-command/fixtures/integration-test.sh`
- Modify: `docs/codebase-summary.md`
- Modify: `docs/project-roadmap.md` (if it exists)
- Read: `commands/build.md`, `skills/theme-conversion/SKILL.md`

## Implementation Steps

1. **TDD — write the integration test first.** Define the expected manifest state after each subcommand.
2. Run the integration test; expect failures.
3. Fix any skill/command bugs surfaced by the integration test.
4. Verify idempotency: run `--all` twice; second run should skip.
5. Verify rollback: corrupt a redesign attempt and ensure `--revert` restores from backup.
6. Update `docs/codebase-summary.md` with the new command and skills.
7. Update `docs/project-roadmap.md` to mark site-editor as done.
8. Run final validation:
   ```bash
   claude plugin validate .
   bash -n scripts/*.sh
   node --check scripts/*.mjs
   ```

## Test-First Structure

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(mktemp -d)"
cp -R examples/sample-site "$ROOT/source"
cd "$ROOT"
# Run optimize skill to populate .wp-pro-max/optimized/
# Run site-editor subcommands
# Assert manifest state
diff -rq examples/sample-site "$ROOT/source" && echo "source unchanged: OK"
```

## Success Criteria

- [ ] Integration test script exists and passes.
- [ ] `--redesign`, `--add-pages`, `--enrich`, `--check`, `--preview`, and `--all` all work on `examples/sample-site`.
- [ ] Pipeline can continue from `theme-conversion` onward.
- [ ] `source/` is unchanged after the full workflow.
- [ ] `claude plugin validate .` passes.
- [ ] `docs/codebase-summary.md` and `docs/project-roadmap.md` mention the new command and skills.

## Risk Assessment

- **Risk:** Integration test requires wp-env for full pipeline validation.  
  **Mitigation:** Make wp-env validation optional in the integration test; static checks are mandatory.
- **Risk:** `theme-conversion` ignores pre-conversion QA results and converts a known-bad HTML copy.  
  **Mitigation:** Document that `theme-conversion` should warn when `siteEditor.preConversionQa.passed == false`; do not gate conversion in this iteration.
- **Risk:** Docs drift from implementation.  
  **Mitigation:** Update docs immediately after integration test passes; include exact command examples.
