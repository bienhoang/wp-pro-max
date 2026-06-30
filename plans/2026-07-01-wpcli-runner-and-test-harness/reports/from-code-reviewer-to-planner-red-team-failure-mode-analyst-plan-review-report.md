# Red-Team Plan Review — wpcli-runner-and-test-harness

Reviewer lens: Failure Mode Analyst (Murphy's Law) + Flow Tracer.
Verdict: NOT READY. Multiple phase-breaking gaps confirmed against the live tree.
All findings carry file:line evidence.

---

## Finding 1: `validate-port.sh` is a linter enforcing the OPPOSITE rule; Phase 3 misclassifies it and breaks its assertions

**Severity:** Critical

**Location:** phase-03 lines 32-33, 56-57 ("Scripts → source lib": lists `scripts/validate-port.sh`); `scripts/validate-port.sh:185-189`.

**Flaw:** Phase 3 treats `validate-port.sh` as a script with a WP-CLI *call-site* to migrate ("can `source wp-cli-runner.sh` and call `wp_cli` directly"). It is not. `validate-port.sh` is a **markdown linter**. Its single `wp-env run cli` token is a regex inside a lint *rule* that FAILs any `wp db|profile|plugin|cron|doctor|eval|core` snippet that does NOT route through `wp-env run cli wp`. There is no WP invocation in it to convert.

**Failure scenario:** Phase 3 migrates ~120 prose snippets from `wp-env run cli wp …` to `wpx …`. The next run of `validate-port.sh` then flags **every migrated snippet** as an error (`WP-CLI snippet should use 'wp-env run cli wp ...'`). Two linters now assert contradictory invariants: `validate-port.sh` requires `wp-env run cli wp`; `contract-lint.sh` (Phase 4) forbids it. Whichever is in the gate goes red and stays red. The Phase 3 instruction to "source the lib and call `wp_cli`" in this file is a no-op against a file that has nothing to migrate.

**Evidence:**
```
scripts/validate-port.sh:185  if (( in_block == 1 )) && [[ "$line" =~ ^[[:space:]]*wp[[:space:]]+(db|profile|plugin|cron|doctor|eval|core) ]]; then
scripts/validate-port.sh:187    if [[ ! "$line" =~ wp-env[[:space:]]+run[[:space:]]+cli[[:space:]]+wp ]]; then
scripts/validate-port.sh:188      log_error "[$rel:$line_no] WP-CLI snippet should use 'wp-env run cli wp ...': $line"
```

**Suggested fix:** Remove `validate-port.sh` from Phase 3's migration list. Add an explicit Phase-3 step to *invert or retire* its rule (require `wpx` instead of `wp-env run cli wp`) so it does not conflict with `contract-lint.sh`, or delete the rule and let Phase 4 own it. Decide whether `validate-port.sh` is wired into `test/run.sh` at all (it currently is not in Phase 1's check list — flag the orphan).

---

## Finding 2: PHP-lint SKIP-not-FAIL has a circular mitigation — real `.php` syntax errors ship green in the no-Docker CI

**Severity:** Critical

**Location:** phase-01 lines 22-23, 30-31, 58, 64-66 (SKIP-not-FAIL, "real PHP correctness is also covered by the seeder live-acceptance run").

**Flaw:** The gate is explicitly designed to run "in a no-Docker CI." `php -l` runs only via the container, so with no Docker it SKIPs all `.php`. The stated mitigation — "real PHP correctness is also covered by the seeder live-acceptance run" — is circular: the seeder acceptance ALSO requires a container/Docker, so it is skipped in the exact same environment. Net: in the no-Docker CI, PHP is never syntax-checked by anything.

**Failure scenario:** A syntax error introduced into any of the three shipped PHP files lands green. Worse, two of them (`security-mu-plugin.php`, `theme-head-fallback.php`) are theme/security output files that the seeder acceptance never executes at all — they have *zero* coverage in any CI mode, Docker or not. A broken `security-mu-plugin.php` ships to a production WordPress and fatals on load.

**Evidence:**
```
phase-01:30  with a clear SKIP message when no container is up rather than hard-failing
phase-01:65  container `php -l` is best-effort, real PHP correctness is also covered by the seeder live-acceptance run
$ find . -name '*.php'  →  ./scripts/seed-batch-runtime.php
                           ./skills/wp-security/references/security-mu-plugin.php
                           ./skills/wp-seo/references/theme-head-fallback.php
```

**Suggested fix:** Provide a host-independent PHP lint path so the gate never silently drops PHP coverage: bundle a tiny `php`-only container image for CI (no WP needed for `php -l`), or fail (not skip) when `WP_CLI_REQUIRE_CONTAINER`/a `CI=1` flag is set. At minimum, make SKIP a hard FAIL in CI and only a soft SKIP for interactive local runs, and stop claiming the seeder run covers the two non-seeder PHP files.

---

## Finding 3: `wp_cli` function-name collision between `seed-helpers.sh` and `wp-cli-runner.sh` — order-dependent, divergent semantics

**Severity:** High

**Location:** phase-03 line 32 ("`seed-helpers.sh` if still present … source `wp-cli-runner.sh` and call `wp_cli`"); `scripts/seed-helpers.sh:67-69` vs `scripts/wp-cli-runner.sh:123-128`.

**Flaw:** `seed-helpers.sh` already **defines its own `wp_cli`** with naive semantics (`"${_WP_CLI_RUN_ARR[@]}" "$@"`, default `wp-env run cli wp`, no container detection, no fail-loud). `wp-cli-runner.sh` defines a **different** `wp_cli` that auto-detects `-cli-1`, excludes `-tests-cli-1`, and fails loudly (rc=2) on ambiguous matches. Phase 3 tells the implementer to make `seed-helpers.sh` source `wp-cli-runner.sh` and call `wp_cli` — producing two definitions of the same function name in one scope. The last one sourced silently wins.

**Failure scenario:** A driver that sources both (e.g. anything pulling in `seed-helpers.sh` then `wp-cli-runner.sh`, or vice versa — note `seed-batch-run.sh:28` already sources `wp-cli-runner.sh`) gets whichever `wp_cli` was defined last. Two callers in the same repo can resolve to different runner semantics depending on source order, including the seeding path that the whole "never seed the wrong database" guard (red-team C5) was built to protect. A naive `wp_cli` shadowing the detecting one re-opens the wrong-database risk.

**Evidence:**
```
scripts/seed-helpers.sh:67  wp_cli() {
scripts/seed-helpers.sh:68    "${_WP_CLI_RUN_ARR[@]}" "$@"
scripts/wp-cli-runner.sh:123 wp_cli() {
scripts/wp-cli-runner.sh:127   "${_WP_CLI_ARGV[@]}" "$@"
scripts/seed-batch-run.sh:28 source "${SCRIPT_DIR}/wp-cli-runner.sh"
```

**Suggested fix:** Do not source `wp-cli-runner.sh` into `seed-helpers.sh`. Either (a) leave `seed-helpers.sh` alone (its runner is already container-aware via `seed-batch-run.sh`), or (b) have `seed-helpers.sh` *delete* its local `wp_cli` and depend solely on the lib — but then prove no caller sources both, and namespace the functions to make collisions impossible.

---

## Finding 4: `commands/plugin.md` and `vuln-scan.sh` carry raw `wp-env run cli` for non-`wp` commands (composer/phpcs) that `wpx` cannot wrap — yet they are not allowlisted → Phase 4 lint hard-fails on legitimate call-sites

**Severity:** High

**Location:** phase-03 allowlist lines 37-40, 58-59; phase-04 line 62 (`grep -rn 'wp-env run cli' minus allowlist → FAIL each`); `commands/plugin.md:63,73`.

**Flaw:** `wpx` is `wp`-only — it calls `wp_cli`, which prepends `wp` (`wp-cli-runner.sh:92,106`). `commands/plugin.md` routes **non-`wp`** binaries through wp-env: `wp-env run cli vendor/bin/phpcs`, `wp-env run cli composer install`. These cannot become `wpx …`. They are also absent from the Phase 3/4 allowlist (which lists only fallback lines, cheatsheet, ship runbooks, `commands/env.md`). `vuln-scan.sh:8` likewise holds a `wp-env run cli` docstring token and is not allowlisted.

**Failure scenario:** Phase 4's `lint_no_raw_wpenv` greps the whole tree, subtracts the allowlist, and FAILs each remaining hit with file:line. `commands/plugin.md:63` and `:73` are legitimate, non-migratable call-sites → the gate goes red with no valid remediation (you cannot rewrite `composer install` as a `wp` subcommand). The plan's allowlist forgot the composer/phpcs class entirely.

**Evidence:**
```
commands/plugin.md:63  ... wp-env run cli vendor/bin/phpcs or composer lint ...
commands/plugin.md:73  ... wp-env run cli composer install) ...
skills/wp-security/references/vuln-scan.sh:8  #   WP_CLI_RUN  override the wp invocation (default: "wp-env run cli wp")
scripts/wp-cli-runner.sh:92  printf 'docker exec -i %s wp\n' "$container"   # wpx is wp-only
```

**Suggested fix:** Add `commands/plugin.md` (composer/phpcs) to the allowlist, and define a separate fast path for non-`wp` container commands if speed matters there (e.g. `wpx-run` / `docker exec` for arbitrary binaries) rather than pretending `wpx` covers them. Audit the full tree for every `wp-env run cli <non-wp>` before finalizing the allowlist.

---

## Finding 5: Phase 3 success-criteria grep scope is narrower than Phase 4's lint grep — Phase 3 can be declared "done" while the gate is red

**Severity:** High

**Location:** phase-03 line 73 (`grep -rn 'wp-env run cli' skills/ agents/` returns only allowlisted lines); phase-04 lines 23, 62, 70 (lint greps everything, must pass on "Phase 3 complete").

**Flaw:** Phase 3's completion gate greps only `skills/ agents/`. Phase 4's lint greps the entire repo (scripts/, commands/, references/, docs/). The actual raw occurrences live well outside `skills/ agents/`: `scripts/migrate-urls.sh`, `scripts/seed-helpers.sh`, `scripts/vuln-scan.sh`-class, `commands/plugin.md`, `references/manifest-contract.md`, `docs/*`. Phase 3 can pass its own grep while leaving those untouched.

**Failure scenario:** Phase 3 is marked complete (skills/agents clean). Phase 4 wires `contract-lint.sh` into `test/run.sh`. The first gate run after wiring FAILs on every script/command/reference/doc still holding raw `wp-env run cli`. Because there is no feature flag, the standing gate is now red for all subsequent work — including unrelated PRs — until someone finishes the migration Phase 3 falsely reported done. This is the exact partial-migration / ordering hole the build-order claim ("Phase 4 makes it mechanical") fails to close.

**Evidence:**
```
phase-03:73  `grep -rn 'wp-env run cli' skills/ agents/` returns only allowlisted lines.
phase-04:70  test/contract-lint.sh passes on the migrated tree (Phase 3 complete).
$ grep -rn 'wp-env run cli' skills/ agents/ scripts/ references/ commands/ | wc -l  →  120  (across 32 files)
```

**Suggested fix:** Make Phase 3's completion grep identical in scope to Phase 4's lint (whole-tree minus allowlist), and gate the wiring of `contract-lint.sh` into `test/run.sh` behind a green whole-tree lint. Until then, keep `lint_no_raw_wpenv` at WARN, flip to FAIL only in the same commit that proves the tree clean.

---

## Finding 6: Scope undercount — plan says "~25 prose call-sites / 30 files"; the tree has ~120 occurrences across 32 files. Effort "M" and semantic-drift risk are understated

**Severity:** Medium

**Location:** plan.md lines 24-28, 51-53; phase-03 effort `M`, lines 78-81.

**Flaw:** The plan sizes the migration as "~25 prose call-sites." A whole-tree grep returns 120 `wp-env run cli` occurrences across 32 files, with single files reaching 17 (`wp-performance-backend/SKILL.md`), 11 (`hardening-checklist.md`), 10 (`multilingual-data.md`). Even excluding allowlist/docstrings, this is several multiples of the stated count. The risk note ("semantic drift during bulk edit") is mitigated only by "per-file re-grep + plugin validate" — `plugin validate` does not parse prose WP-CLI semantics, so a dropped flag in a markdown snippet passes validate silently.

**Failure scenario:** Hand-migrating 120 heterogeneous snippets under an "M" budget invites dropped flags / broken quoting in exactly the high-count security/i18n/seo files, none of which any automated check in this plan can catch (validate is schema-level; there is no snippet executor). The defect ships as wrong runtime WP behavior in a generated site.

**Evidence:**
```
plan.md:24  but **30 files** still call `wp-env run cli`
plan.md:51  - [ ] All ~25 prose call-sites use `wpx`
$ grep -rc 'wp-env run cli' (migration scope)  →  perf-backend 17, hardening 11, multilingual 10, ... total 120 / 32 files
```

**Suggested fix:** Re-baseline the count from the live grep, split Phase 3 by file-weight (the 17/11/10 files reviewed line-by-line as the plan already hints), and add a mechanical check that the *WP subcommand+flags* are byte-identical pre/post migration (e.g. normalize `wp-env run cli wp X` and `wpx X` to `X` and diff), since neither `plugin validate` nor the contract lint verifies snippet semantics.

---

## Finding 7: Migrating `migrate-urls.sh` to `wp_cli` changes a destructive DB script's behavior — auto-detection can now FAIL LOUDLY where it previously "just worked"

**Severity:** Medium

**Location:** phase-03 lines 56-57, 67 (scripts → source lib, call `wp_cli`); `scripts/migrate-urls.sh:45,142`; `scripts/wp-cli-runner.sh:95-99` (rc=2 ambiguous → return 2).

**Flaw:** `migrate-urls.sh` currently resolves its runner as `${WP_CLI_RUN:-wp-env run cli wp}` — no container detection, deterministic. Switching it to `wp_cli` adds container auto-detection plus the fail-loud-on-ambiguous (rc=2) path. (Note: the asked-about `set -euo pipefail` leak is NOT a real risk here — `wp-cli-runner.sh` keeps `set -e` inside its exec-guard only, and its sourcing guard correctly sets `_wpcli_sourced=1` when sourced from an executed script; verified at `wp-cli-runner.sh:134-141`. The behavior change, not the leak, is the defect.)

**Failure scenario:** On a developer machine with two wp-env projects up, `migrate-urls.sh --apply` (a script whose entire purpose is to rewrite the production URL across all DB tables) previously ran against the wp-env default; post-migration it now aborts with rc=2 "ambiguous container." That is arguably safer — but it is an unannounced behavior change to a ship-stage destructive tool, and any automation calling it without `WP_CLI_RUN` set now breaks. The plan classifies this as a trivial "source lib + call `wp_cli`" edit and does not flag the contract change.

**Evidence:**
```
scripts/migrate-urls.sh:45   read -r -a _WP_CLI_RUN_ARR <<< "${WP_CLI_RUN:-wp-env run cli wp}"
scripts/wp-cli-runner.sh:95  if [ "$rc" -eq 2 ]; then ... return 2   # new failure mode for migrate-urls
phase-03:67  For scripts: source `wp-cli-runner.sh`, replace calls with `wp_cli <sub>`.
```

**Suggested fix:** Treat `migrate-urls.sh` (a ship-stage / remote-SSH script) like the SSH runbooks — leave its `WP_CLI_RUN` resolution intact and allowlist it, OR explicitly document the new ambiguous-abort behavior and confirm every caller sets `WP_CLI_RUN`. Do not bundle a behavior change to a destructive DB tool inside a "mechanical prose migration" phase.

---

## Finding 8: `wpx` silent fallback + raw `docker exec` bypasses wp-env readiness — env-setup post-start/verify commands become flaky on an up-but-unprovisioned or restarting container

**Severity:** Medium

**Location:** phase-02 lines 35-37 ("`-cli-1` is long-lived … fallback still works"); `skills/wp-env-setup/SKILL.md:85-88,105-106`; `scripts/wp-cli-runner.sh:50-52,90-92`.

**Flaw:** The plan assumes `-cli-1` is steadily long-lived and that the only degradation if it isn't is "speed reverts." But `_wpcli_detect_container` keys on `docker ps` *name presence*, not health. A container that is **created/restarting/rebuilding** still appears in `docker ps`, so `wpx` `docker exec`s into it directly, bypassing the readiness/wait logic that `wp-env run cli` performs. The env-setup stage runs WP-CLI immediately after `wp-env start` (`theme activate`, `rewrite flush --hard`, `theme list`) — precisely the window where the container is up but WordPress may not be provisioned.

**Failure scenario:** During `env` stage (or any restart/rebuild), `wpx rewrite flush --hard` hits a not-yet-ready container via raw `docker exec` and fails or half-applies, where `wp-env run cli` would have waited. Because `wpx` only falls back to `wp-env run cli` when *zero* containers match (not when a matched container is unhealthy), the readiness guarantee is lost exactly when it matters. The asked-about "what if the env is down/restarting" is real: detection sees the name and binds anyway.

**Evidence:**
```
skills/wp-env-setup/SKILL.md:87  wp-env run cli wp rewrite structure '/%postname%/' --hard
skills/wp-env-setup/SKILL.md:88  wp-env run cli wp rewrite flush --hard
scripts/wp-cli-runner.sh:50  all="$(docker ps --format '{{.Names}}' ... grep -E -- '-cli-1$' ...)"   # name presence, not health
scripts/wp-cli-runner.sh:92  printf 'docker exec -i %s wp\n' "$container"   # no readiness wait
```

**Suggested fix:** For the env-setup post-start/verify block, keep `wp-env run cli` (it owns env lifecycle and readiness) and allowlist it, OR add a readiness probe to `wpx`/the lib (e.g. a bounded retry on `docker exec … wp option get siteurl` before declaring the container usable) so `wpx` does not bind to an unhealthy container. Replace the plan's "speed reverts" claim with the real failure mode (flaky exec into unready container).

---

## Findings list

1. `validate-port.sh` is a linter enforcing the OPPOSITE rule; Phase 3 misclassifies it and breaks its assertions — **Critical**
2. PHP-lint SKIP-not-FAIL has a circular mitigation → `.php` syntax errors ship green in no-Docker CI — **Critical**
3. `wp_cli` function-name collision between `seed-helpers.sh` and `wp-cli-runner.sh` (order-dependent, divergent semantics) — **High**
4. `commands/plugin.md`/`vuln-scan.sh` raw `wp-env run cli` for non-`wp` commands are non-migratable and un-allowlisted → Phase 4 lint hard-fails on legit call-sites — **High**
5. Phase 3 completion grep scope narrower than Phase 4 lint grep → "done" while the standing gate is red — **High**
6. Scope undercount ("~25 / 30 files" vs ~120 occurrences / 32 files); effort and semantic-drift risk understated — **Medium**
7. Migrating `migrate-urls.sh` to `wp_cli` silently changes a destructive DB script's runner contract (new ambiguous-abort path) — **Medium**
8. `wpx` raw `docker exec` bypasses wp-env readiness → flaky env-setup commands on up-but-unprovisioned/restarting container — **Medium**
