---
phase: 1
title: "Test aggregator + harness gate"
status: done
effort: "S"
---

# Phase 1: Test aggregator + harness gate

## Overview

Stand up `test/run.sh` as the single standing gate for the plugin, folding in the
existing `test/seeder/` tests, so every later phase is verifiable as it lands.
Note: `test/seeder/` is **not** the only existing harness — `scripts/validate-port.sh`
is a second standing linter (Red Team #3/AD); `test/run.sh` should invoke it too.

## Requirements

- Functional: one entrypoint that runs every check (does NOT stop at first
  failure — run all, then exit non-zero if any FAILed, so one run surfaces all
  problems): `claude plugin validate .` → `bash -n` all `*.sh` → `node --check`
  all `*.mjs` → `php -l` all `*.php` → `scripts/validate-port.sh` →
  `test/seeder/run.sh`.
- Non-functional: zsh-safe; **no host PHP** — `php -l` runs in a throwaway
  `php:8.2-cli` Docker container (it needs no WordPress), NOT the wp-env cli
  container; runnable locally and as a CI step.

## Architecture

`test/run.sh` is a thin orchestrator. Each check is a function; a `run_check`
helper prints `PASS/FAIL/SKIP` and accumulates exit status; the script exits
non-zero if any check FAILed.

**File discovery excludes `node_modules`, `vendor`, `.git`** (Red Team #4 —
`package.json:9` devDeps create `node_modules`; the gate must not lint deps).
Centralize this in one `walk()` helper used by every check.

**PHP-lint decoupled from wp-env (Red Team #5).** Earlier design ran `php -l`
inside the wp-env cli container and SKIPped when absent — circular, because the
seeder acceptance that "covers" PHP also needs Docker, so a no-Docker CI checked
no PHP at all. Instead: `docker run --rm -v "$PWD":/code -w /code php:8.2-cli sh
-c 'for f in …; do php -l "$f"; done'`. `php -l` needs only PHP, not WordPress,
so this runs anywhere Docker exists; SKIP only when Docker itself is absent (and
say so loudly with the file count that went unchecked).

**`claude plugin validate` fallback (Red Team #12).** `claude` CLI presence is
not guaranteed (CLAUDE.md's env guarantees list Docker/Node/jq, not `claude`).
If `command -v claude` fails, mark that check SKIP+warn, not FAIL.

## Related Code Files

- Create: `test/run.sh` (aggregator)
- Invoke (existing standing linter): `scripts/validate-port.sh`
- Reference (existing tests to fold in): `test/seeder/run.sh`, `test/seeder/*.test.sh`

## Implementation Steps

1. Write `test/run.sh` with `run_check "<label>" <fn>` (tallies pass/fail/skip;
   never early-exits) and a `walk <ext>` helper that `find`s files excluding
   `node_modules`/`vendor`/`.git`.
2. `check_plugin_validate` → `command -v claude` ? `claude plugin validate .` :
   SKIP+warn.
3. `check_bash_syntax` → `walk sh` → `bash -n`.
4. `check_node_check` → `walk mjs` → `node --check`.
5. `check_php_lint` → `command -v docker` ? one `docker run --rm … php:8.2-cli`
   that `php -l`s every `walk php` file : SKIP+warn with unchecked count.
6. `check_validate_port` → `bash scripts/validate-port.sh` (the snippet linter).
7. `check_seeder` → delegate to `test/seeder/run.sh` if present.
8. Print a summary; `exit 1` if any check FAILed.
9. zsh-safe: executed (not sourced), so `set -euo pipefail` at top is fine; keep
   a sourcing guard if any helper might be sourced by sub-tests.

## Success Criteria

- [ ] `bash test/run.sh` runs ALL checks (no early exit) and exits 0 on a clean tree.
- [ ] A deliberate `bash -n` error makes the gate exit non-zero (and still runs later checks).
- [ ] `node_modules/`/`vendor/` contents are never linted (verified by adding a junk file there → still green).
- [ ] With Docker present, `php -l` runs via `php:8.2-cli` and a bad `.php` FAILs; with Docker absent, PHP-lint SKIPs loudly with a count.
- [ ] `claude` absent → plugin-validate SKIP+warn, gate still completes.
- [ ] `bash -n test/run.sh` clean.

## Risk Assessment

- *`php:8.2-cli` image pull on first CI run* → one-time; pin the tag; acceptable.
  PHP version need only satisfy syntax (8.2 matches the wp-env target).
- *`validate-port.sh` will be edited in Phase 3* → ordering is fine: P1 only
  *invokes* it; P3 updates its assertion. The gate reflects whichever rule is
  current.
- *Run-all (no early-exit) hides ordering* → acceptable; summary lists every FAIL.
