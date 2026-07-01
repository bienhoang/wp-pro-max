---
phase: 2
title: "wpx wrapper script"
status: done
effort: "S"
---

# Phase 2: wpx wrapper script

## Overview

Ship `scripts/wpx.sh` — the one canonical WP-CLI entry every stage uses. It
reuses `wp-cli-runner.sh` resolution so a WP call runs against the long-lived
`-cli-1` container (`docker exec`, ~0.1s) instead of booting a fresh container
per call (~3.7s).

## Requirements

- Functional: `bash wpx.sh <wp subcommand...>` runs the command through the
  resolved runner and forwards stdin (so `wpx.sh eval-file …` keeps working).
  Resolution: `WP_CLI_RUN` override verbatim → live `-cli-1` `docker exec -i` →
  `wp-env run cli wp` fallback (exactly `wp_cli_resolve`).
- Non-functional: zsh-safe (no top-level `set -euo pipefail` when sourced; no
  `status`/`path` locals; sourcing-vs-exec guard like `wp-cli-runner.sh`); exit
  code is the WP command's exit code, not the wrapper's.

## Architecture

`wpx.sh` is a near-trivial shim over the already-reviewed `wp_cli` function in
`scripts/wp-cli-runner.sh`. It sources that lib and calls `wp_cli "$@"`. Keeping
it a *separate tiny file* (rather than telling prose to source the lib directly)
gives skills one short, memorable command and a single migration target.

Verify wp-env leaves a persistent `cli` service: `wp-env` compose runs the `cli`
container with a tty, so `docker ps` shows `<proj>-cli-1` between calls — this is
what `_wpcli_detect_container` binds to. If a future wp-env version stops doing
so, the fallback path still works (correctness preserved, speed reverts).

**Readiness, not just presence (Red Team #14).** `_wpcli_detect_container` keys
on the container *name appearing in `docker ps`*, not on WordPress being
provisioned/ready. `wp-env run cli` internally waits for readiness; a raw
`docker exec` does not. So `wpx` against an *up-but-unready* container (mid
`wp-env start`, restarting, DB not migrated) can fail. Mitigation: `wpx` must
**fail loudly** on a non-zero `docker exec` (never swallow → never a silent
wrong result), and stage skills already gate on an explicit readiness probe
(`wpx option get siteurl` before real work — content-seeding does this). Do NOT
add auto-retry/health-loop logic here (YAGNI); document that `wpx` assumes
env-setup has completed, and the loud failure tells the operator to wait/start.

**What wpx does and does NOT guarantee (Red Team #8).** It changes the *default
command the prose tells the model to run*. It does not intercept or rewrite
commands the model actually issues, and it cannot force compliance. Treat it as a
fast, consistent default — the measurable win lands when (a) the model uses it
and (b) a live `-cli-1` resolves; otherwise it transparently falls back.

## Related Code Files

- Create: `scripts/wpx.sh`
- Reference (resolution + stdin forward, do NOT duplicate): `scripts/wp-cli-runner.sh`
- Verify (persistent cli container assumption): `scripts/wp-env-bootstrap.sh`
- Test: add `test/wpx.test.sh` (resolution + stdin), wire into `test/run.sh`

## Implementation Steps

1. Write `scripts/wpx.sh`: shebang, `SCRIPT_DIR` resolve, source
   `wp-cli-runner.sh`, sourcing-vs-exec guard, on direct exec call
   `wp_cli "$@"` and propagate `$?`.
2. Confirm `wp_cli` already forwards this process stdin (it does — verify the
   `"${_WP_CLI_ARGV[@]}" "$@"` call inherits stdin) so `wpx.sh eval-file -`
   works; add a comment pinning that contract.
3. Add `test/wpx.test.sh`: with `WP_CLI_RUN="printf %s\n"` (or a stub), assert
   `wpx.sh option get siteurl` invokes the override with args intact and a piped
   payload reaches stdin.
4. Behaviorally verify against a live wp-env (manual/acceptance): `wpx.sh option
   get siteurl` returns the URL via `docker exec`, not a fresh container.
5. `bash -n scripts/wpx.sh`; run `test/run.sh`.

## Success Criteria

- [ ] `scripts/wpx.sh option get siteurl` works against a running wp-env via the
      live container (observably faster than `wp-env run cli`).
- [ ] `printf '{}' | scripts/wpx.sh eval-file -` forwards stdin to the runner.
- [ ] `WP_CLI_RUN` override is honored verbatim; `WP_CLI_REQUIRE_CONTAINER=1`
      surfaces the loud failure from the lib unchanged.
- [ ] `test/wpx.test.sh` passes inside `test/run.sh`; `bash -n` clean.
- [ ] No duplication of resolution logic — `wpx.sh` only sources/calls the lib.

## Risk Assessment

- *Ambiguous container (multiple wp-env up)* → lib already returns rc=2 and the
  caller fails loudly; document that `WP_CLI_RUN` is the escape hatch.
- *Stdin not forwarded in some shells* → covered by `test/wpx.test.sh`.
- *Tests-cli-1 mis-bind* → lib already excludes `-tests-cli-1`; add a regression
  assertion in the test.
