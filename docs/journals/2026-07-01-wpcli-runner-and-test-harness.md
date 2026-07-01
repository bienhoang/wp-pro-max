# WP-CLI Runner & Test Harness: Instruction-Level Enforcement Gone Live

**Date**: 2026-07-01 05:30
**Severity**: Medium
**Component**: Plugin scaffold (skills/agents/test harness)
**Status**: Done

## What Happened

Shipped three layers of a WP-CLI unification: a thin `scripts/wpx.sh` wrapper (docker exec fast path → wp-env fallback, ~3.7s boot to ~0.1s exec), a standing test gate (`test/run.sh`: plugin validate + bash/node/php lints + contract enforcer), and a static contract lint (`test/contract-lint.sh`) that makes the "all WP-CLI via wpx" rule mechanical. Migrated ~22 skill/agent prose call-sites from `wp-env run cli` to the new default. Red Team review surfaced a critical gap: the lint was blind to bare `wp <sub>` executable snippets in acf-seeding.md/forms-seeding.md—model-facing code that would fail in the wp-env-only target. Fixed both the lint (fence-aware, line-start-only rule) AND the snippets themselves (migrated to wpx).

## The Brutal Truth

This was billed as a "speed optimization" but it's actually an **instruction-level standardization**. The speed win is real *only when* a live `-cli-1` container exists, the model uses wpx (not guaranteed), and Docker+CWD-narrowing work (all fallible). What we actually shipped is a regression guard: the lint enforces that prose tells the model to use the fast path when it's available, and silently degrades to wp-env if it isn't. That's not mechanical enforcement—it's documentation with a linter. The honest framing was painful to land because the initial claim ("we'll swap every wp call to the fast runner") overstated what code can guarantee.

## Technical Details

**wpx.sh** (69 lines): sources `wp_cli()` from `wp-cli-runner.sh`, forwards stdin, propagates exit code verbatim. Zsh-safe: no top-level `set -euo pipefail`, no reserved locals (`status`/`path`), guards against bash/zsh diff in sourcing-vs-execution checks (mirrors `wp-cli-runner.sh:59-69`).

**test/run.sh** (217 lines): aggregates `claude plugin validate .` (SKIP+warn if absent) + `bash -n *.sh` + `node --check *.mjs` + `php -l *.php` (via throwaway `php:8.2-cli` container—no host PHP assumed) + `validate-port.sh` + `contract-lint.sh` + seeder behavioral tests. All walks exclude `node_modules`/`vendor`/`.git`. Result: **8 PASS / 0 FAIL / 0 SKIP**.

**contract-lint.sh** (262 lines): FAIL if SKILL.md missing frontmatter, if a `wpbuild_progress <id>` uses a stage id outside the canonical set (derived from `manifest-contract.md`, not hard-coded), if `wp-env run cli` appears outside the allowlist, **or if a bare `wp <sub>` appears at line-start inside a bash fence** (the instruction surface). The fence rule is the key: it closes the gap that let acf-seeding.md's `wp acf sync --all` slip past.

## What We Tried

Initial lint only checked for `wp-env run cli` patterns. That missed bare `wp` executable snippets in skills/references (acf-seeding, forms-seeding), which would fail in a wp-env-only environment where the model is supposed to run them. Red Team code review (3 reviewers, 14 findings all accepted) caught this gap with file:line evidence. Fixed by: (1) adding a fence-aware bare-`wp` rule that greps line-start only (avoids false-positives on prose inline-code), (2) migrating the executable snippets themselves to `wpx`, (3) exempting operator runbooks and non-executable mentions via fence + line-start + prose context.

## Root Cause Analysis

The plan underestimated two things: (1) the breadth of bare `wp` references in the codebase—not all were in the migration scope, some were in executable examples the model would try to run, (2) the gap between "instruction consistency" and "actual compliance"—a lint can check prose but can't force a model to follow it. The honest reframing was hard because it meant admitting the speed win is conditional, not guaranteed. The acf-seeding catch was the humbling lesson: instructions matter more than the implementation when the reader is an LLM.

## Lessons Learned

- **Instruction-level enforcement is weaker than it sounds.** A lint can catch obvious drift but can't force runtime behavior. Future optimization gates should explicitly acknowledge the fallback.
- **Executable snippets in references need the same lint as top-level prose.** We almost shipped code the model would run without using the canonical pattern.
- **Plan-vs-reality gaps need docs, not workarounds.** The three deviations (plans/ + reports/ exclusion, "migrate ALL wp", "audit" stage id) were right decisions but cost clarity; they should have been documented upfront in the plan's "Implementation notes" section.
- **Bare grep is not a contract.** Fence-aware, line-start-only matching caught edge cases that simple `wp` patterns would have missed.

## Next Steps

- Gate is green (8 PASS / 0 FAIL / 0 SKIP). Plan marked done.
- Future wp-cli improvements should revisit the wp-env CWD-narrowing logic in `wp-cli-runner.sh:58-68` (Red Team flagged flakiness on unready containers; loud-fail is correct but operators need the readiness probe in docs).
- Contract drift will be caught automatically by `test/run.sh` on each invocation. No manual gate-keeping needed.
- If the audit stage or other new stages ship, they must update `manifest-contract.md`'s canonical id list or the lint will FAIL them immediately.
