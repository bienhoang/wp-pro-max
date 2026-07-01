# Brainstorm — Fast WP-CLI Runner (plugin-wide) + Standing Test Harness

**Date:** 2026-07-01
**Mode:** brainstorm (deep-dive on 2 items, then plan handoff)
**Scope:** combine improvement #1 (generalize WP-CLI runner) + #2 (standing
test/CI harness) into one plan — #2 enforces #1, so they ship together.

## Problem statement

Two of the highest-leverage gaps found during an architecture review of
`wp-pro-max`:

1. **Speed.** The seeder was sped up ~20× by reusing a long-lived container
   (`scripts/wp-cli-runner.sh`, `docker exec`), but that fast path is used by
   only 4 scripts (all seeder/ship). **30 files** still call `wp-env run cli`,
   which boots a fresh Docker container (~3.7s) **per call**. Heaviest stages by
   call count: i18n ~20, security ~19, perf-backend 17, seo ~15. Each heavy
   stage wastes ~1 min in pure container-boot; i18n+security+seo ≈ 3 min/build
   thrown away.

2. **Robustness.** The tool's whole value is correctness + idempotency, yet it
   has no standing test runner — only a per-plan harness. `test/seeder/` already
   has a real pattern (stub-wp.sh, run.sh, 4 tests, fixtures, live-acceptance)
   but it is seeder-scoped and not wired to `claude plugin validate`.

## Evaluated approaches

### #1 Generalize the WP-CLI runner

The trap: unlike the seeder (a shell script that can `source` the runner lib),
most stages are **SKILL.md prose** that tells the model to type
`wp-env run cli wp …`. So "generalize" requires choosing a vehicle.

- **A — `wpx` wrapper + rewrite prose.** Ship `scripts/wpx.sh` (sources
  `wp-cli-runner.sh`); replace `wp-env run cli wp X` → `bash …/wpx.sh X` across
  ~25 files. Pro: one resolution path, kills per-call boot. Con: many markdown
  edits; still prose-discipline (model must use the wrapper).
- **B — Batch every stage like the seeder.** Pro: max speed. Con: large effort
  and **does not generalize** — i18n/security/seo use heterogeneous CLI tools
  (`wp i18n make-pot`, `wp search-replace`, `plugin activate`) with no WP-API
  equivalent; batch only fits real data payloads (already done: ACF/Elementor).
- **C — Hybrid (CHOSEN).** (1) Make the *default* WP-CLI path the long-lived
  `docker exec` via a `wpx` wrapper — eliminates 3.7s→~0.1s/call everywhere
  without refactoring stages into batches; (2) keep eval-file batch only where a
  data payload exists (seeder). Rationale: 90% of the pain is *per-call boot*,
  not *call count*. The wrapper alone fixes i18n/security/seo without rewriting
  them.

Nuance: the cli container must be long-lived; `wp-cli-runner.sh` already detects
the persistent `-cli-1` (excluding `-tests-cli-1`) and **falls back** to
`wp-env run cli` when absent — so correctness holds even if env tears down.
Prose-discipline is closed by a #2 lint that greps for raw `wp-env run cli` and
fails.

### #2 Standing test harness

- **A — `test/run.sh` aggregator (CHOSEN).** One entrypoint:
  `claude plugin validate .` → `bash -n` all `.sh` → `node --check` all `.mjs` →
  `php -l` (via container) all `.php` → seeder behavioral tests. Low effort,
  standing gate, runnable locally AND as a CI step (no lock-in).
- **B — Contract lint (CHOSEN).** Static grep-asserts over skills/agents: valid
  frontmatter; stage-id ∈ canonical set; **no raw `wp-env run cli`** (enforces
  #1); manifest fields referenced exist in schema. Fast, no WP, CI-friendly.
- **C — Golden-manifest fixture (DEFERRED → schema-shape).** analyze/model/tokens
  are LLM-driven, non-deterministic → exact-match brittle. Replace with
  schema-shape assertion (overlaps #3), not exact match.

## Recommended solution

Ship **#1 Hybrid-C** (`wpx` default fast path + fallback) **and** **#2 A+B**
(standing aggregator + contract lint) in one plan. The contract lint (B) is the
enforcer that makes #1's "always use wpx" an invariant, not prose.

Build order:
```
#2-A aggregator (stand up the gate)
   → #1 wpx wrapper + prose migration   ┐ land together
   → #2-B contract lint (locks #1)       ┘
```

## Implementation considerations & risks

- **zsh-safe** for any sourced script (no top-level `set -euo pipefail`, no
  `status`/`path` locals, sourcing guards) — match `wp-cli-runner.sh`.
- **No host PHP** — `php -l` runs via container (`docker exec … php -l`).
- Wrapper must forward stdin (already in `wp_cli`) so future eval-file callers
  keep working.
- Migrating ~25 markdown files is mechanical but wide — do it in one sweep and
  let the lint catch stragglers.
- Ship runbooks' SSH `WP_CLI_RUN` path must stay untouched (the runner honors
  the override verbatim).
- Soft overlap with the two in-flight plans (fast-seeder, convert fan-out): no
  hard conflict; they already use the runner / don't touch these files.

## Success metrics

- Heavy stages (i18n/security/seo) drop per-call container boot (3.7s→~0.1s);
  measurable wall-clock reduction on a sample build.
- `grep -r 'wp-env run cli' skills/` returns only intentional/fallback mentions;
  lint fails on any new raw usage.
- `test/run.sh` is green and is the single gate; `claude plugin validate .`
  passes; `bash -n` / `node --check` / container `php -l` clean.

## Open questions (defaulted, revisit if wrong)

1. Is the wp-env `-cli-1` container long-lived in the real env, or does wp-env
   tear it down? → Default: rely on the runner's detect+fallback; no hard dep.
2. CI target — GitHub Actions or local-only `claude plugin validate`? → Default:
   `test/run.sh` runnable both ways; add a thin GH Actions YAML optionally.
