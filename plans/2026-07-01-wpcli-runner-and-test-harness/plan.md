---
title: "Plugin-wide fast WP-CLI runner + standing test harness"
description: ""
status: done
priority: P2
branch: "feat/seed-batch-eval-file"
tags: []
blockedBy: []
blocks: []
created: "2026-06-30T20:05:18.212Z"
createdBy: "ck:plan"
source: skill
---

# Plugin-wide fast WP-CLI runner + standing test harness

## Overview

Two architecture-review wins for `wp-pro-max`, shipped together because the
second enforces the first:

- **#1 — Plugin-wide fast WP-CLI runner.** The seeder already reuses a
  long-lived container (`scripts/wp-cli-runner.sh`, `docker exec`), but
  `wp-env run cli` still appears in **~33 files / ~120 lines** (re-measured;
  earlier "30/~25" was wrong — Red Team #11). A fresh Docker container costs
  ~3.7s **per call**; heaviest stages: i18n ~20, security ~19, perf-backend 17,
  seo ~15 → ~1 min/stage of pure boot. Ship a thin `scripts/wpx.sh` wrapper
  (Hybrid-C: `docker exec` into the live `-cli-1` as default, `wp-env run cli`
  as fallback, `WP_CLI_RUN` override honored) and migrate the **prose `wp`
  call-sites in `skills/` + `agents/`** to it. **Scope is prose-only** — scripts
  keep their own runners (avoids the `wp_cli` name collision in `seed-helpers.sh`
  and a destructive runner swap in `migrate-urls.sh`; Red Team #6/#7). Non-`wp`
  commands (`composer`, `phpcs`, `tests-cli phpunit`) and heterogeneous stages
  (`make-pot`, `search-replace`, `plugin activate`) are **not** wpx-wrappable —
  allowlisted, not migrated.

  **Honest framing (Red Team #8):** skills are *prose instructing the model*, not
  a runtime. `wpx` changes the documented **default** the model is told to use,
  and the lint enforces *instruction consistency* — it is **not** runtime
  enforcement of executed commands. The speed win is real but **contingent** on a
  live `-cli-1`, correct CWD-basename narrowing (`wp-cli-runner.sh:58-68`), model
  compliance, and the silent fallback. Claim is "consistent fast default +
  measurable when the container is live," not "mechanically guaranteed swap."
- **#2 — Standing test harness.** Today coverage is scattered — `test/seeder/`
  tests + `scripts/validate-port.sh` (a second standing linter) — and nothing is
  wired into one gate. Add `test/run.sh` aggregator (`claude plugin validate`
  with SKIP-if-absent + `bash -n` + `node --check` + `php -l` via a throwaway
  `php:8.2-cli` container + `validate-port.sh` + seeder tests; all walks exclude
  `node_modules`/`vendor`/`.git`) and a static **contract lint** (frontmatter;
  canonical stage ids via greppable `wpbuild_progress <id>`; manifest keys ⊆
  schema as WARN; and **no raw `wp-env run cli`** outside a reasoned allowlist).
  The lint enforces *instruction consistency* (authors/model aren't told to use
  the slow path) — it is the regression guard for #1, **not** runtime enforcement
  (Red Team #8).

Brainstorm: [`./brainstorm-wpcli-runner-and-test-harness.md`](./brainstorm-wpcli-runner-and-test-harness.md).

**Build order (why this phase sequence):** stand up the gate first (P1), so #1
is verifiable as it lands; add the wrapper (P2) and migrate prose (P3); then the
contract lint (P4) keeps the documented `wpx` default consistent (instruction-
level, not runtime — Red Team #8); validate + reconcile docs last (P5).

## Acceptance criteria (whole plan)

- [x] `scripts/wpx.sh` resolves runner via `wp-cli-runner.sh`: live `-cli-1`
      `docker exec` default, `wp-env run cli` fallback, `WP_CLI_RUN` override
      verbatim; forwards stdin; zsh-safe (no top-level `set -euo pipefail`, no
      `status`/`path` locals, sourcing guard).
- [x] All migrated **prose `wp` call-sites in `skills/`+`agents/`** use `wpx`;
      remaining `wp-env run cli` lives only in the explicit, reasoned allowlist
      (fallback line in `wp-cli-runner.sh`; `commands/env.md`; `commands/plugin.md`
      non-`wp` calls; ship SSH runbooks; `seed-helpers.sh`/`migrate-urls.sh`
      script-internal runners; `references/wp-cli-cheatsheet.md`).
- [x] **`scripts/validate-port.sh` is reconciled, not bypassed** — its snippet
      assertion (previously *required* `wp-env run cli wp`) now requires `wpx`,
      so the two linters agree instead of contradicting (Red Team #1).
- [x] `test/run.sh` is the single gate and is green: `claude plugin validate .`
      (SKIP+warn if `claude` CLI absent), `bash -n` all `.sh`, `node --check`
      all `.mjs`, `php -l` all `.php` via a throwaway `php:8.2-cli` container
      (NOT wp-env; SKIP only when Docker itself is absent), plus `test/seeder/`.
      All file walks **exclude `node_modules`, `vendor`, `.git`** (Red Team #4).
- [x] `test/contract-lint.sh` fails on: missing/invalid SKILL frontmatter; a
      `wpbuild_progress`/`wpbuild_is_done <id>` using an id outside the canonical
      set (the greppable signal — there is no `stage:` field; Red Team #10); and
      any `wp-env run cli` outside the allowlist. Invoked by `test/run.sh`.
- [x] No host PHP assumed — `php -l` runs via the throwaway container.
- [x] README/`manifest-contract.md`/`docs/tech-stack.md`/`docs/system-architecture.md`
      (+ `CLAUDE.md`) reconciled: one canonical "WP-CLI via `wpx`" rule; seeding
      delegation prose (agent authors payload, skill runs inline) corrected.

## Implementation notes (deviations from the as-written plan)

Two gaps the Red Team missed, resolved with documented defaults:

1. **Lint scope excludes `plans/` + `reports/`, not just `node_modules/vendor/.git`.**
   Those trees are tracked (CLAUDE.md's "git-ignored" claim is stale) and hold
   ~150 `wp-env run cli` mentions in finding-log context — a literal whole-repo
   scan could never go green (contradicting the plan's own consistency sweep,
   which treats those mentions as finding-log). The contract lint scans the
   shipped instruction surface (skills/agents/commands/scripts/references/docs)
   and allowlists docs/`README`/`CLAUDE.md`/`test/`; `plans/`+`reports/` are
   excluded as historical artifacts.
2. **Migrated ALL `wp` subcommand lines in skills/agents** (incl. `make-pot`,
   `plugin install/activate`, `pll …`), per the authoritative phase-03 step 2.
   The plan.md overview caveat ("make-pot/search-replace/plugin activate not
   wpx-wrappable") is contradicted by the executable phase and is technically
   wrong — they are valid `wp` subcommands; `wpx` prepends the runner + `wp`. The
   `search-replace` case never applies (it lives in the allowlisted
   `migrate-urls.sh`). `vuln-scan.sh` stays raw via a `WP_CLI_RUN` line-pattern
   allowlist (it is a standalone script with its own runner default).
3. **Added `audit` to the canonical stage ids** in `manifest-contract.md` — the
   `audit` stage (skill `wp-audit`, command `audit`, `schema.audit`,
   `wpbuild_progress audit`) shipped earlier without updating the contract list;
   the new lint correctly flagged the drift, fixed at source.

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Test aggregator + harness gate](./phase-01-test-aggregator-harness-gate.md) | Done |
| 2 | [wpx wrapper script](./phase-02-wpx-wrapper-script.md) | Done |
| 3 | [Prose migration to wpx](./phase-03-prose-migration-to-wpx.md) | Done |
| 4 | [Contract lint enforcer](./phase-04-contract-lint-enforcer.md) | Done |
| 5 | [Validation + docs reconcile](./phase-05-validation-docs-reconcile.md) | Done |

## Dependencies

- **`fast-seeder-eval-file` — DONE (foundational).** It introduced
  `wp-cli-runner.sh` + `test/seeder/`, which this plan builds on. No action
  needed; just don't regress its runner contract.
- **`parallel-build-orchestration` — pending, SOFT overlap, no hard blocker.**
  It edits `commands/build.md` (convert section) + `manifest-core.sh`
  write-guard; this plan touches neither's logic (it adds `wpx.sh`, `test/`, and
  prose). The contract lint (P4) may later assert the write-guard, but does not
  require that plan. Whoever lands second skims for incidental `test/run.sh`
  additions. Not marked `blockedBy`/`blocks` — relationship is genuinely *none*.
- **`woocommerce-catalog-build-extension` — pending.** Was blocked by the seeder
  plan (now done). It may adopt `wpx` once shipped, but does not block this plan.
- No schema changes; ship `WP_CLI_RUN` SSH path is left untouched (verified
  allowlist item in P3/P4).

## Red Team Review

### Session — 2026-07-01
**Reviewers:** 3 (Security Adversary / Fact Checker, Failure Mode Analyst / Flow
Tracer, Assumption Destroyer / Scope Auditor) via `code-reviewer`, hostile
lenses, codebase-evidence required.
**Findings:** 14 consolidated (24 raw → deduped), every one carrying `file:line`
evidence (all passed the evidence filter). **All 14 Accepted.**
**Severity:** 2 Critical, 6 High, 6 Medium.
**Headline:** the plan's central gate was unreachable as written — `validate-port.sh`
enforces the *opposite* rule, and several `wp-env run cli` files were in neither
the migrate list nor the allowlist. Fixes: reconcile `validate-port.sh` to `wpx`;
narrow migration to prose-only; precise reasoned allowlist; honest reframing that
prose-lint is instruction-consistency, not runtime enforcement.

| # | Finding | Sev | Disposition | Applied To |
|---|---------|-----|-------------|------------|
| 1 | `validate-port.sh:185-188` enforces the OPPOSITE rule (requires `wp-env run cli wp`) → collides with the new lint | Critical | Accept | P3, P4 — update its assertion to `wpx` |
| 2 | Contract-lint can never go green: files with `wp-env run cli` in neither list; Phase 3 done-grep only scanned `skills/ agents/` | Critical | Accept | P3, P4 — same whole-repo scope; complete allowlist |
| 3 | Non-`wp` commands (`composer`/`phpcs`/`tests-cli phpunit`) unmigratable but lint-blocked (`commands/plugin.md:63,73`) | High | Accept | P3, P4 — allowlist, not migrate |
| 4 | Harness scans `node_modules` (find/grep exclude only `./.git/*`; `package.json:9` devDeps) | High | Accept | P1, P4 — exclude node_modules/vendor/.git |
| 5 | PHP-lint SKIP-not-FAIL is circular (acceptance also needs Docker) → `.php` errors ship green in no-Docker CI | High | Accept | P1 — `php:8.2-cli` throwaway container for `php -l` |
| 6 | `wp_cli` name collision: `seed-helpers.sh:67` defines its own vs `wp-cli-runner.sh:116` | High | Accept | P3 — scripts out of scope (prose-only) |
| 7 | `migrate-urls.sh:45,91-92` runner swap silently changes a destructive prod `search-replace` target | High | Accept | P3 — not migrated; allowlisted |
| 8 | Over-claim: prose-swap is a *suggestion*; lint greps instructions not executed cmds; win contingent on live container + CWD narrowing + fallback | High | Accept | plan, P2, P5 — reframe claims |
| 9 | File-level allowlist blanket-exempts ship DB-op runbooks | Medium | Accept | P4 — reasoned, path-scoped allowlist w/ rationale |
| 10 | Phase-4 stage-id rule unimplementable (no parseable `stage:` field); hard-coded canonical array → drift | Medium | Accept | P4 — grep `wpbuild_progress <id>`; derive set from contract |
| 11 | Scope counts wrong (33 files/~120 lines vs 30/~25) | Medium | Accept | plan, P3 — recount in P3 step 1 |
| 12 | `claude plugin validate` assumed present in CI, no skip fallback | Medium | Accept | P1 — SKIP+warn when `claude` absent |
| 13 | Allowlist phantom entry ("fallback in wpx.sh") + missing real fallback strings | Medium | Accept | P4 — fix allowlist contents |
| 14 | `wpx` raw `docker exec` bypasses wp-env readiness wait → flaky on unready container | Medium | Accept | P2 — readiness note + loud-fail (no silent) |

**Verified TRUE — do not reverse:** `wp_cli` stdin forwarding (`wp-cli-runner.sh:127`
+ `-i` `:92`); `-tests-cli-1` exclusion (`:51`); argv path is not shell-injection;
canonical stage set matches `manifest-contract.md:16-23`; seeder transport
(`seed-batch-run.sh`) untouched and safe.

Reports: `./reports/from-code-reviewer-to-planner-red-team-*.md` (3).

### Whole-Plan Consistency Sweep
Re-read `plan.md` + all 5 phase files after applying the 14 findings. Decision
deltas propagated: migration scope **prose-only** (scripts out — #6/#7);
`validate-port.sh` **reconciled to `wpx`** (not allowlisted — #1); php-lint via
throwaway **`php:8.2-cli`** container (not wp-env — #5); all walks exclude
`node_modules`/`vendor`/`.git` (#4); `claude`/Docker checks SKIP-not-FAIL
(#5/#12); stage-id lint greps **`wpbuild_progress <id>`** + canonical **derived
from the contract** (#10); allowlist **precise/path:line-pattern**, no phantom
`wpx.sh` entry, includes `seed-helpers.sh`/`migrate-urls.sh` (#9/#13); counts
corrected to ~33/~120 (#11); `docs/tech-stack.md` added to P5 reconcile (#2);
honest "instruction-level, not runtime" framing throughout (#8).
Swept for stale terms (`source the lib into scripts`, `container php -l`,
`30/~25`, `locks #1`/`mechanical`, `CANONICAL_STAGES=(`, phantom `wpx.sh`
fallback, loose stage-id rule): every surviving mention is in negative/finding-
log context. **Zero unresolved contradictions — eligible for implementation.**
