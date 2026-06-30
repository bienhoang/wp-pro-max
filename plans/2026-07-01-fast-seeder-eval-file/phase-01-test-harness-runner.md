---
phase: 1
title: "Test Harness + Runner"
status: done
priority: P1
dependencies: []
---

# Phase 1: Test Harness + Runner

## Overview

Lay the TDD foundation: a behavioral harness (stub `wp` that records every call)
plus the shared runner that binds to **this project's** live `cli` container. The
harness exists first and fails until later phases implement the runtime.

**Test-scope correction (red-team C6):** the stub exercises only what bash can
exercise — **orchestration**: exactly one `eval-file` invocation per stage, stdin
payload assembly, sentinel-delimited summary parse, and the merge math. The
real **idempotency / zero-dup contract runs inside PHP**, which the stub never
executes and which `claude plugin validate .` never runs — so that contract is a
**mandatory live wp-env acceptance run** (Phase 2 gate), not a stub assertion.
Do not claim zero-dup is "tested" by the stub.

## Requirements

- Functional: a stub runner records argv of each `wp`/`docker exec` call so tests
  can assert call count and content without a live WP. A live-mode switch runs
  the same assertions against a real wp-env when Docker is up.
- Functional: `scripts/wp-cli-runner.sh` resolves the runner once — honor
  `WP_CLI_RUN` if set; else `docker exec -i <this-project-cli-container> wp`; else
  `wp-env run cli wp`. No hardcoded container hash.
- Functional (validated decision 2): the `wp-env run cli wp` fallback is retained
  for the **piped-payload** path only if Phase 2's pipe-test proves it forwards
  stdin. If it does not, drop it for batch execution — docker-exec becomes
  required and resolution fails loudly when no project `*-cli-1` is found.
  <!-- Updated: Validation Session 1 - fallback gated on stdin-forwarding test -->

- Functional (red-team C5): container match must be **exact** — `*-cli-1` only,
  **excluding `*-tests-cli-1`** (the test container co-exists), and bound to this
  project's wp-env instance, not just any host container with `cli` in the name.
  If zero or >1 candidate remains after filtering, **fail loudly** (don't pick
  one) — seeding the wrong database is worse than stopping.
- Non-functional: zsh-safe (sourced). Reuse the `${=...}` vs `read -ra` argv
  pattern from `scripts/seed-helpers.sh:47-52`. No top-level `set -euo pipefail`;
  no `status`/`path` locals; sourcing-vs-execution guard.

## Architecture

`scripts/wp-cli-runner.sh` exports `wp_cli_resolve()` → echoes the runner argv
string, and `wp_cli()` → executes through it. Container detection (red-team C5):
`docker ps --format '{{.Names}}'` filtered to names ending in `-cli-1` and
**not** matching `-tests-cli-1`, scoped to this project's wp-env instance hash
when derivable from `.wp-env.json`/CWD; exactly one match required or fail. `-i`
is included so the runtime piped to `wp eval-file` can read stdin.

Empirically confirmed by red-team (do not re-litigate): an eval'd script reads
the piped payload via `php://stdin` (exit 0); wp-env keeps long-lived `*-cli-1`
containers (the docker-exec speed premise is real); stdin is a pipe so `ARG_MAX`
does not bound payload size.

Test layout under `test/seeder/`:
- `stub-wp.sh` — fake `wp` on `PATH`; appends each invocation's argv to
  `$SEED_TEST_LOG`, returns canned IDs/JSON keyed by subcommand (e.g.
  `post create --porcelain` → incrementing int; `post list` → empty first run,
  the created slug on second run to simulate idempotency).
- `runner.test.sh` — asserts `wp_cli_resolve` picks `WP_CLI_RUN` override,
  docker-exec when a cli container is listed (stub `docker`), and the wp-env
  fallback otherwise.
- `seed-batch.test.sh` — the **orchestration** acceptance test (red now): runs a
  fixture payload through the stub and asserts (a) exactly **one** `eval-file`
  invocation per run, (b) the payload reaches the runtime via **stdin** (assert
  the stub received non-empty stdin — guards the silent-empty-stdin false-success
  in red-team H6, on **both** the `docker exec -i` and `wp-env run cli` paths),
  and (c) the summary parses from between the sentinel markers
  (`WPBUILD_SUMMARY{…}WPBUILD_END`), not bare stdout. Zero-dup is NOT asserted
  here (no PHP runs) — that is the live gate in Phase 2.

## Related Code Files

- Create: `scripts/wp-cli-runner.sh`
- Create: `test/seeder/stub-wp.sh`, `test/seeder/runner.test.sh`,
  `test/seeder/seed-batch.test.sh`, `test/seeder/fixtures/payload.sample.php`
- Reference (pattern): `scripts/seed-helpers.sh:43-57`, `scripts/migrate-urls.sh:45-48`

## Implementation Steps

1. **(test-first)** Write `stub-wp.sh` + `runner.test.sh` asserting the three
   resolution branches. Run → fails (no `wp-cli-runner.sh`).
2. Implement `scripts/wp-cli-runner.sh` (`wp_cli_resolve`, `wp_cli`, zsh-safe argv,
   sourcing guard). Run `runner.test.sh` → green; `bash -n` clean.
3. **(test-first)** Write `seed-batch.test.sh` + `fixtures/payload.sample.php`
   expressing the single-invocation + zero-dup contract. Run → fails (no runtime
   yet); this red test is the gate Phase 2 closes.
4. Add a one-line test entrypoint (e.g. `test/seeder/run.sh`) that runs all
   `*.test.sh` and exits non-zero on any failure. No framework — plain bash.

## Success Criteria

- [ ] `runner.test.sh` green: override / docker-exec / wp-env-fallback all correct.
- [ ] Container resolution rejects `*-tests-cli-1` and **fails loudly** on 0 or >1 match (no `head -n1` guess).
- [ ] `wp-cli-runner.sh` sources cleanly under zsh (the runtime shell) and bash.
- [ ] `seed-batch.test.sh` present and **failing for the right reason** (runtime absent); asserts single invocation + non-empty stdin (both runner paths) + sentinel-delimited summary parse.
- [ ] `bash -n` clean on all new scripts; no hardcoded container hash anywhere.

## Risk Assessment

- Stub drift from real WP-CLI output → keep stub minimal, validate the real
  contract in the live-mode acceptance run (Phase 2/3), not only against the stub.
- zsh `${=...}` vs bash word-split divergence → covered by sourcing the runner in
  both shells in `runner.test.sh`.
