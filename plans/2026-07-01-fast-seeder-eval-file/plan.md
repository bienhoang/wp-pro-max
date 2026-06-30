---
title: "Fast seeder: single wp eval-file PHP batch"
description: ""
status: done
priority: P2
branch: "main"
tags: []
blockedBy: []
blocks: [2026-06-26-woocommerce-catalog-build-extension]
created: "2026-06-30T18:56:03.912Z"
createdBy: "ck:plan"
source: skill
---

# Fast seeder: single wp eval-file PHP batch

## Overview

Replace the seeder's "bash-function-per-op, container-per-call" engine with a
**single `wp eval-file` PHP batch per stage**. Today `seed-content` +
`seed-plugin-data` fire 150+ `wp` calls (lookup→create→meta→jq each, every call a
fresh Docker container ~3.7s) → ~9 min and fragile (heavy agent died mid-run).
New design (**JSON data channel**, per red-team): ship **one reviewed PHP
runtime** (`seed-batch-runtime.php`); the generator emits a **pure-JSON payload**
(never executable PHP); the runtime is invoked once via `wp eval-file
seed-batch-runtime.php` and reads the payload as JSON from stdin
(`json_decode(file_get_contents('php://stdin'))`). Idempotency checks run
in-process via native WP API (microseconds). The **seed skill runs the batch
inline** (preserving the thin-coordinator architecture — not the heavy agent,
not new logic in `build.md`) and merges the summary into `wp-build.json`, so
agent death cannot lose a run. Covers both seed stages; retires
`scripts/seed-helpers.sh`.

**Why JSON, not generated PHP:** embedding untrusted source HTML / ACF values /
Elementor JSON into generated PHP literals is a parse-fatal + PHP-injection (RCE)
surface with no safe encoding scheme — and concatenating a runtime `<?php` file
with a payload `<?php` file does not even parse. A JSON payload is data only:
zero injection class, one shipped+reviewed PHP file. Source brainstorm
(supersedes its "embed bodies in PHP payload" and "WP-CLI-compliant" notes):
[`./brainstorm-fast-seeder-eval-file.md`](./brainstorm-fast-seeder-eval-file.md).

**Target:** seed wall-clock minutes → seconds (≥20×); ~150 invocations → 1 per
stage; re-run dup count 0; run survives heavy-agent death.

**TDD:** each phase locks behavior with a behavioral harness (stub WP-CLI that
records calls + a live wp-env acceptance run) **before** the implementation that
makes it pass. Idempotency is the regression contract carried over from the
current `seed-helpers.sh`.

**Env constraints (verified):** host has Docker + Node + jq but **no host PHP** —
all `php -l` / batch execution goes through the container (`docker exec … php -l`
for lint; `wp eval-file seed-batch-runtime.php` with the JSON payload on stdin for
execution). Sourced scripts stay zsh-safe (no top-level
`set -euo pipefail`, no `status`/`path` locals, sourcing guards) per
`scripts/seed-helpers.sh` precedent.

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Test Harness + Runner](./phase-01-test-harness-runner.md) | Done |
| 2 | [Batch Runtime](./phase-02-batch-runtime.md) | Done |
| 3 | [Content-Seeding Migration](./phase-03-content-seeding-migration.md) | Done |
| 4 | [Plugin-Data Migration](./phase-04-plugin-data-migration.md) | Done |
| 5 | [Retire Bash + Docs](./phase-05-retire-bash-docs.md) | Done (shim kept) |

## Execution Note (2026-07-01, /cook)

Implemented all 5 phases. Live-verified against a real wp-env (`*-tests-cli-1`
throwaway container): idempotency zero-dup (`created:0` on re-run), fatal-safe
partial-key flush, ACF `_<field>` fallback row, Elementor JSON round-trip with
quotes, append+unique merge, zero-op + incomplete-run loud failures.

**Deviations from the phase docs (intentional):**
- **Payload fixture is `.json`, not `.php`** (phase-01 listed
  `fixtures/payload.sample.php`) — the pivot makes the payload pure JSON; named
  `payload.sample.json` to match reality.
- **Fatal-safety is `try/catch(\Throwable)`, not solely
  `register_shutdown_function`** — empirically, under WP-CLI an *uncatchable*
  fatal pre-empts userland shutdown functions (WP/WP-CLI's own fatal handler
  exits first; proven with a marker-file probe). The catch makes every
  *catchable* fatal (hook fatals, Errors, bad data) deterministic; a true
  OOM/timeout yields no sentinel, which the driver treats as a loud non-zero
  failure (idempotency makes the re-run safe). `register_shutdown_function` is
  kept as a best-effort backstop.
- **Phase 5 keeps `seed-helpers.sh` as a deprecated shim** (user decision) rather
  than deleting it, because the pending WooCommerce plan still extends it. Header
  marks it superseded; docs point at the batch engine. Remove once woo rebases.
- **`WP_CLI_CONTAINER` escape hatch** added to the runner (explicit container
  override; also lets tests target the throwaway tests container).

New files: `scripts/seed-batch-runtime.php`, `scripts/seed-batch-run.sh`,
`scripts/wp-cli-runner.sh`, `test/seeder/` (stub + 4 host tests + run.sh + live
acceptance + fixtures).

## Acceptance Criteria (whole plan)

- [ ] Payload is **pure JSON** (no generated PHP); runtime is the only PHP and `json_decode`s stdin.
- [ ] `seed-content` for ~42 records completes in seconds via one `wp eval-file` call.
- [ ] Re-run of either stage produces **0** duplicate posts/menu items/terms/media — **verified by a mandatory live wp-env run**, not the stub (no PHP executes under `claude plugin validate`).
- [ ] PHP errors mid-batch are collected + reported; a fatal (OOM/timeout/hook) still emits the summary via `register_shutdown_function`; partial run re-runnable.
- [ ] `seed.idempotencyKeys` merged **append + unique** (not jq `*`, which replaces arrays); `seed.lastRun` recorded; `seed.lastSummary` for observability.
- [ ] Summary on stdout is wrapped in a unique sentinel (e.g. `WPBUILD_SUMMARY{…}WPBUILD_END`) so `WP_DEBUG` notices can't break the parse.
- [ ] The **seed skill** runs the batch inline and merges the summary; the agent only authors the payload (thin-coordinator preserved).
- [ ] Container runner binds to **this project's** `*-cli-1` (exact, excludes `*-tests-cli-1`); empty/zero-op runs fail loudly, not silently "done".
- [ ] Media reachable in-container (mount `outputDir` or preserve a media-path-prefix escape hatch); generated payload + any debug body files are git-ignored in the target project.
- [ ] `content/<slug>.html` files are **kept** (QA `search-replace` + `post update` depend on them).
- [ ] `claude plugin validate .` passes; `bash -n`, `node --check`, container `php -l` clean.
- [ ] `scripts/seed-helpers.sh` removed; no dangling references in skills/agents/docs/**pending plans**.

## Dependencies

- **Soft overlap** with `plans/2026-07-01-parallel-build-orchestration/` — both
  edit `commands/build.md`, but **different sections** (that plan: theme-`convert`
  fan-out; this plan: seed-stage batch execution). No hard `blockedBy`; whoever
  lands second rebases the build.md orchestrator section carefully.
- **Blocks `2026-06-26-woocommerce-catalog-build-extension`** (red-team H5): its
  `phase-06-seeding.md` extends `scripts/seed-helpers.sh`, which this plan removes
  in Phase 5. The woo plan is marked `blockedBy` this one; it must rebase its
  seeding onto the JSON batch engine (or keep a shim) before Phase 5 deletes the
  bash helpers. Phase 5's reference scan **must** include pending plans, not just
  ship runbooks.
- No schema changes beyond additive `seed.*` fields; ship/`migrate-urls.sh`
  SSH `WP_CLI_RUN` path left untouched.

## Red Team Review

### Session — 2026-07-01
**Findings:** 15 (15 accepted, 0 rejected) — 3 hostile reviewers (Security
Adversary, Failure Mode Analyst, Assumption Destroyer), 24 raw → deduped to 15.
**Severity breakdown:** 6 Critical, 6 High, 3 Medium.
**Headline:** pivot from generated-PHP payload → **pure-JSON data channel** (one
shipped runtime `json_decode`s stdin). Dissolves the injection class + the
unparseable-concat bug at once. Reports in `./reports/`.

| # | Finding | Severity | Disposition | Applied To |
|---|---------|----------|-------------|------------|
| 1 | Untrusted source embedded in generated PHP literals → parse-fatal + RCE; no encoding scheme | Critical | Accept | plan, Ph2, Ph3, Ph4 |
| 2 | Runtime+payload concat = two `<?php` → unparseable (proven `php -l` exit 255) | Critical | Accept (folded into #1) | plan, Ph2 |
| 3 | jq `*` merge replaces arrays → `idempotencyKeys` clobbered | Critical | Accept | Ph2 |
| 4 | End-of-run-only summary → PHP fatal loses partial state | Critical | Accept | Ph2 |
| 5 | `--filter name=cli \| head -n1` picks wrong (`-tests-cli-1`) container | Critical | Accept | Ph1 |
| 6 | Idempotency tested only by stub; no PHP in CI → contract unenforced | Critical | Accept | Ph1, Ph2 |
| 7 | "WP-CLI-compliant" overclaim; eval-file ≠ dry-run-guarded | High | Accept (modified) | Ph2, Ph4 |
| 8 | Media path: only theme dir mounted; `outputDir` assets unreachable; dropped prefix escape hatch | High | Accept | Ph2, Ph3 |
| 9 | stdout JSON has no sentinel; `WP_DEBUG` notices break parse | High | Accept | Ph2 |
| 10 | ACF `update_field` needs registered group; fallback drops `_<field>` key row | High | Accept | Ph4 |
| 11 | Elementor missing `_elementor_template_type=wp-page` + version meta | High | Accept | Ph4 |
| 12 | Pending WooCommerce plan extends `seed-helpers.sh` → Ph5 deletion breaks it | High | Accept | plan, Ph5 |
| 13 | Secrets/tokens materialized into committed payload + debug-write | Medium | Accept | Ph3 |
| 14 | Dropping `content/<slug>.html` breaks QA `search-replace` + `post update` | Medium | Accept | Ph3 |
| 15 | "Orchestrator runs the batch" contradicts thin-coordinator; no build.md wiring | Medium | Accept (modified) | Ph3, Ph4 |

## Validation Log

### Session — 2026-07-01
Verification pass skipped (the `## Red Team Review` above already carries
file:line evidence per the validate guard). 4 open decision points confirmed:

1. **Media path (red-team H1) → mount `outputDir` in `.wp-env.json`.** The
   env-setup adds an `optimization.outputDir` mapping so assets resolve by
   absolute container path; `mediaPathPrefix` is no longer the primary mechanism
   (kept only as an optional override). → Ph2, Ph3, and `wp-env-bootstrap.sh`.
2. **Runner fallback (red-team H6) → pipe-test both paths; if `wp-env run cli wp`
   does not forward stdin, drop it.** Then docker-exec is required and resolution
   fails loudly when no project `*-cli-1` container is found. → Ph1, Ph2.
3. **ACF (red-team H3) → rely on acf-json autoload so `update_field` runs; on the
   postmeta fallback also write the `_<field>` key row.** Matches Ph4 as written.
4. **WooCommerce plan (red-team H5) → defer; `blockedBy` link only.** This plan
   does not migrate woo; the woo plan rebases its seeding onto the JSON batch
   engine when it runs. Phase 5 warns if woo hasn't rebased before deletion.
   Matches Ph5 + frontmatter as written.

**Propagation:** decision 1 → Ph2 (media-path section + `wp-env-bootstrap.sh`
touchpoint, mount primary / prefix optional) and Ph3; decision 2 → Ph1 (fallback
gated on stdin test) consistent with Ph2 H6; decisions 3 & 4 already matched the
plan as written. Post-propagation sweep: fixed one stale prefix-first ordering
(Ph2 risk line). **No unresolved contradictions.** Plan eligible for `/ck:cook`.

### Whole-Plan Consistency Sweep
Ran after applying all 15 findings. Decision delta: generated-PHP payload →
**pure-JSON data channel**; runtime reads `php://stdin`; skill runs batch inline;
`content/<slug>.html` kept; key merge append+unique; container bind exact;
summary fatal-safe + sentinel-wrapped; woo plan `blockedBy`.

Swept all phase files + `plan.md` for stale pre-pivot terms (`$SEED_PAYLOAD`,
"prepend/concatenate runtime", "embed bodies in PHP", "drop content/*.html",
"orchestrator runs the batch", jq `*` merge, bare `eval-file -`). Every surviving
mention is in negative/explanatory or finding-log context; no affirmative stale
usage remains. `eval-file` invocation wording normalized to
`wp eval-file seed-batch-runtime.php` + stdin payload across Ph1–Ph4 and the
overview. **Result: 0 unresolved contradictions.** Plan is ready for `/ck:cook`.
