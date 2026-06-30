# Red-Team Plan Review — Assumption Destroyer / Scope Auditor

**Plan:** `2026-07-01-wpcli-runner-and-test-harness`
**Reviewer lens:** Assumption Destroyer (skeptic) + Scope Auditor
**Verdict:** Multiple Critical defects. The contract-lint gate (Phase 4) cannot
go green on a "complete" Phase 3 as scoped, two linters in the repo enforce
mutually contradictory invariants, and a whole class of `wp-env run cli` calls
(non-`wp` binaries) cannot be expressed by the proposed wrapper. Counts are
wrong and internally self-contradictory. Do not execute as written.

Findings below. Each cites file:line evidence.

---

## Finding 1: `validate-port.sh` enforces the OPPOSITE invariant and Phase 3 misclassifies it
**Severity:** Critical
**Location:** Phase 3 "Related Code Files (migrate)" (scripts → source lib);
Phase 4 rule 3 (`lint_no_raw_wpenv`).

**Flaw:** Phase 3 lists `scripts/validate-port.sh` as a script that "can `source
wp-cli-runner.sh` and call `wp_cli` directly rather than shelling to `wpx.sh`."
But `validate-port.sh` is not a WP-CLI runner — it is itself a standing linter
("TDD harness for WP Kit extras port") whose RULE asserts that every WP-CLI
snippet in the repo MUST use `wp-env run cli wp ...`. Its two `wp-env run cli`
occurrences are a regex pattern and an error message, not executable calls.
After Phase 3 migrates the codebase to `wpx`, `validate-port.sh` will flag every
migrated `wpx` call-site as wrong, while Phase 4's new `contract-lint.sh` flags
every remaining `wp-env run cli` as wrong. The two gates are mutually
contradictory and the plan never reconciles them.

**Failure scenario:** Phase 3 completes; `validate-port.sh` now fails on all
migrated files (they no longer match `wp-env run cli wp`); Phase 4 lint fails on
any file still using the old form. There is no tree that passes both. Sourcing
`wp-cli-runner.sh` into `validate-port.sh` (as Phase 3 directs) is nonsensical —
it has no WP execution to route.

**Evidence:**
- `scripts/validate-port.sh:4` — `# validate-port.sh — TDD harness for WP Kit extras port.`
- `scripts/validate-port.sh:187` — `if [[ ! "$line" =~ wp-env[[:space:]]+run[[:space:]]+cli[[:space:]]+wp ]]; then`
- `scripts/validate-port.sh:188` — `log_error "[$rel:$line_no] WP-CLI snippet should use 'wp-env run cli wp ...': $line"`
- Phase 3 lines 32-35 + 56-57 (classifies validate-port.sh as a WP-CLI script to source the lib).

**Suggested fix:** Treat `validate-port.sh` as a peer linter, not a runner.
Either retire its `wp-env run cli wp` rule and fold its checks into
`contract-lint.sh`, or update its rule to require `wpx`. Decide ONE source of
truth for the WP-CLI invocation invariant. Remove validate-port.sh from the
"scripts → source lib" migration class.

---

## Finding 2: Phase 4 contract-lint can never go green — 6 files hold `wp-env run cli`, none migrated, none allowlisted
**Severity:** Critical
**Location:** Phase 4 rule 3 / step 5 (`grep -rn 'wp-env run cli' minus
allowlist → FAIL each`); Phase 3 "Related Code Files (migrate)" + allowlist.

**Flaw:** Phase 4's lint greps the repo for `wp-env run cli` and FAILs anything
outside the allowlist (`wp-cli-runner.sh`, `wpx.sh`, `wp-cli-cheatsheet.md`,
ship SSH runbooks, `commands/env.md`). Six files contain `wp-env run cli`,
appear in NEITHER the Phase 3 migrate list NOR the allowlist, and several are
touched by no phase at all:
`commands/plugin.md`, `docs/tech-stack.md`, `scripts/seed-helpers.sh`,
`README.md`, `docs/system-architecture.md`, `references/manifest-contract.md`.

**Failure scenario:** Phase 3 is marked complete per its own checklist
(`grep ... skills/ agents/` returns only allowlisted lines — note it only greps
skills/ and agents/, missing commands/, docs/, scripts/, README). Phase 4 lint
then immediately FAILs on all six files. `test/run.sh` can never be green, so the
plan's top acceptance criterion is unreachable.

**Evidence:**
- `commands/plugin.md:63`, `commands/plugin.md:73`
- `docs/tech-stack.md:8`
- `scripts/seed-helpers.sh:31,56,60,63`
- `README.md:42`
- `docs/system-architecture.md:135`
- `references/manifest-contract.md:52`
- Phase 3 success criterion (line 73) greps only `skills/ agents/` — blind to the above.
- Phase 4 allowlist (lines 53-55 of phase-04, lines 37-40 of phase-03) omits all six.

**Suggested fix:** Re-derive the full call-site inventory with
`grep -rn 'wp-env run cli'` across the WHOLE repo (skills, agents, commands,
references, scripts, docs, README). For each file decide: migrate, allowlist, or
doc-rewrite — and assign it to a phase. Add `seed-helpers.sh` and
`migrate-urls.sh` default-fallback strings to the allowlist explicitly.

---

## Finding 3: `commands/plugin.md` / `wp-plugin-dev` use `wp-env run cli` for NON-`wp` binaries — `wpx` cannot represent them
**Severity:** Critical
**Location:** Phase 3 migration model (`wpx.sh` calls `wp_cli` which prepends
`wp`); Phase 1 claim "only test/seeder/ exists".

**Flaw:** `wpx.sh` is a shim over `wp_cli`, which executes `<runner> wp "$@"` —
it can ONLY run `wp` subcommands. But several `wp-env run cli` call-sites invoke
non-`wp` binaries: `wp-env run cli vendor/bin/phpcs`, `wp-env run cli composer
install`, and `wp-env run tests-cli phpunit` (a different service entirely).
These cannot be migrated to `wpx`. The plan's migration model has no path for
them, yet Phase 4's blanket `wp-env run cli` lint will FAIL them regardless. The
plan also omits the entire `wp-plugin-dev` skill + `plugin` command surface from
scope.

**Failure scenario:** `commands/plugin.md` lines 63/73 are unmigratable (no
`wp` form exists) and unallowlisted → permanent lint FAIL. Plus, Phase 1's
premise that "only `test/seeder/` exists" is false — `validate-port.sh` is a
second standing harness — so the gate design starts from a wrong inventory.

**Evidence:**
- `commands/plugin.md:63` — `... wp-env run cli vendor/bin/phpcs or composer lint ...`
- `commands/plugin.md:73` — `... wp-env run cli composer install ... wp-env run tests-cli phpunit ...`
- `skills/wp-plugin-dev/SKILL.md:71` — `... smoke test via wp-env run tests-cli phpunit.`
- `scripts/wp-cli-runner.sh:127` — `"${_WP_CLI_ARGV[@]}" "$@"` (runner always = `... wp`); resolve always appends `wp` (`:92`, `:106`).
- Phase 1 line 12 — "Today only `test/seeder/` exists" (contradicted by validate-port.sh).

**Suggested fix:** Scope the lint to `wp-env run cli wp` (the form wpx replaces),
NOT bare `wp-env run cli`. Explicitly allowlist non-`wp` runner uses
(phpcs/composer/`tests-cli`). Acknowledge `wp-plugin-dev`/`commands/plugin.md`
as out-of-scope-but-allowlisted, or in-scope with a separate handling note.

---

## Finding 4: Call-site/file counts are wrong and self-contradictory
**Severity:** High
**Location:** plan.md overview (lines 22-30), acceptance (line 51-52); Phase 3
overview (line 15).

**Flaw:** Plan claims "**30 files** still call `wp-env run cli`" and "~25 prose
call-sites to migrate." Actual: 33 files, 123 `wp-env run cli` lines. The "~25"
is internally contradicted by the plan's OWN per-stage tallies in the same
overview: "i18n ~20, security ~19, perf-backend 17, seo ~15" — that is 71
call-sites across just four stages. Real migratable prose is ~90-100+ lines, not
25. The "M" effort and the acceptance criterion "All ~25 prose call-sites use
wpx" are unreliable.

**Failure scenario:** Executor budgets for ~25 edits, hits ~100, treats the
overflow as scope creep or stops early; the acceptance count can never be
satisfied because it was wrong at authoring time.

**Evidence:**
- `grep -rl 'wp-env run cli'` over skills/agents/commands/references/scripts/schemas/docs/README → **33 files**.
- `grep -rn 'wp-env run cli'` same scope → **123 lines**.
- Per-file: `skills/wp-performance-backend/SKILL.md`=17, `wp-security/references/hardening-checklist.md`=11, `wp-i18n/references/multilingual-data.md`=10, `wp-seo/SKILL.md`=9, `wp-i18n/SKILL.md`=8 … (i18n aggregate 20, security aggregate 19 — matching the overview, refuting the "~25 total").

**Suggested fix:** Replace the guessed counts with the grep-derived inventory.
State the migratable-line count (post-allowlist, `wp`-only) explicitly and
re-estimate Phase 3 effort accordingly (likely L, not M).

---

## Finding 5: Prose swap changes a suggestion, not runtime; the contract-lint lints instructions, not executed commands
**Severity:** High
**Location:** plan.md (#1 "the invariant that locks #1"); Phase 3 overview ("so
the model uses the fast path everywhere"); Phase 4 ("makes 'always use wpx'
mechanical instead of prose discipline").

**Flaw:** Skills/agents/commands are MARKDOWN that instruct the model. Rewriting
`wp-env run cli wp X` → `bash wpx.sh X` changes a *suggestion the model may or
may not follow*, not runtime behavior. `contract-lint.sh` greps `.md` files — it
proves the *instructions* are consistent, not that any *executed* command used
`docker exec`. The speed win is contingent on three things the lint cannot
enforce: (a) the model actually typing the suggested command, (b) a live
`-cli-1` container existing in the target project, (c) the CWD-basename
narrowing in `_wpcli_detect_container` resolving to exactly one container. The
plan overstates this as "mechanical" enforcement that "locks #1."

**Failure scenario:** All prose migrated and lint green, yet a build run is no
faster because the model improvised raw `wp-env run cli` or wrote a heredoc the
lint never sees; or the target project has no live container and every call
takes the ~3.7s fallback anyway. The gate reports success; the latency win does
not materialize.

**Evidence:**
- Phase 4 step 5 — `grep -rn 'wp-env run cli'` (operates on source `.md`, not runtime).
- `scripts/wp-cli-runner.sh:62-68` — narrowing depends on `basename "$PWD"` matching a container token; in many target dirs this is non-deterministic.
- `scripts/wp-cli-runner.sh:106` — silent fallback to `wp-env run cli wp` when no container (speed reverts, no signal).

**Suggested fix:** Reframe the claim honestly: the lint enforces *instruction
consistency*, and the wrapper *enables* the fast path when a container exists.
Drop "mechanical"/"locks #1" framing. If real enforcement is wanted, add a
runtime check (e.g., a build-time assertion or telemetry on which runner
resolved), not a static grep over prose.

---

## Finding 6: `claude plugin validate` assumed available in CI with no skip fallback
**Severity:** Medium
**Location:** Phase 1 (step 2 `check_plugin_validate`; "runnable … as a CI
step"; "no-Docker CI"); plan acceptance.

**Flaw:** Phase 1 designs a SKIP fallback only for the PHP-lint check (no
Docker). `check_plugin_validate` calls `claude plugin validate .` with no
availability guard. CLAUDE.md guarantees Docker, Node, Composer, and jq in the
build env — it says nothing about the `claude` CLI being installed in CI. If the
`claude` binary is absent, the very first gate check hard-fails for an
environmental reason, not a real defect.

**Failure scenario:** CI runner lacks the `claude` CLI; `test/run.sh` exits
non-zero at check 1 on every run; the gate is permanently red and gets disabled.

**Evidence:**
- Phase 1 lines 30-31 — anticipates "no-Docker CI" but only SKIPs PHP-lint.
- Phase 1 line 43 — `check_plugin_validate → claude plugin validate .` (no guard).
- CLAUDE.md "Validate / check" + env note: Docker/Node/Composer/jq present, host php absent; `claude` CLI availability unstated.

**Suggested fix:** Add a `command -v claude` guard that SKIPs (with a loud note)
when the CLI is absent, mirroring the PHP-lint SKIP — or document `claude` CLI as
a hard CI prerequisite and fail with a clear "install claude CLI" message.

---

## Finding 7: Allowlist item "fallback line inside `wpx.sh`" is phantom; real fallback strings (`seed-helpers.sh`, `migrate-urls.sh`) are missing
**Severity:** Medium
**Location:** plan.md acceptance (line 52); Phase 3 allowlist (line 38); Phase 4
(line 23, `WPENV_ALLOWLIST`).

**Flaw:** The allowlist repeatedly lists "the fallback line inside
`wp-cli-runner.sh`/`wpx.sh`." But `wpx.sh` (per Phase 2) merely sources the lib
and calls `wp_cli "$@"` — it will contain NO `wp-env run cli` string, so it can
never match the grep; that allowlist entry is phantom. Meanwhile the files that
DO carry default-fallback `wp-env run cli wp` strings — `seed-helpers.sh` (4
lines) and `migrate-urls.sh` (2 lines) — are NOT allowlisted, so they will FAIL
the lint. The allowlist was written without inspecting actual file contents.

**Failure scenario:** Lint passes the phantom wpx.sh entry (no-op) but FAILs on
the real fallback strings in seed-helpers.sh / migrate-urls.sh that legitimately
must keep `wp-env run cli wp` as their default.

**Evidence:**
- Phase 2 lines 29-31, 48 — wpx.sh sources lib, calls `wp_cli "$@"` (no literal `wp-env run cli`).
- `scripts/seed-helpers.sh:31,56,60,63` — default `wp-env run cli wp` strings, unallowlisted.
- `scripts/migrate-urls.sh:30,45` — default `wp-env run cli wp` string, unallowlisted.

**Suggested fix:** Remove the phantom wpx.sh allowlist entry. Add the actual
fallback-bearing files (`seed-helpers.sh`, `migrate-urls.sh`) — or, if those
scripts are migrated to source `wp-cli-runner.sh`, remove their fallback strings
and confirm the lint then passes.

---

## Finding 8: Migrating `migrate-urls.sh` to source the lib silently changes its default runner resolution
**Severity:** Medium
**Location:** Phase 3 ("scripts → source lib"; `migrate-urls.sh`).

**Flaw:** `migrate-urls.sh` currently resolves WP-CLI as
`${WP_CLI_RUN:-wp-env run cli wp}` — a deterministic default. Sourcing
`wp-cli-runner.sh` changes the no-override default from `wp-env run cli wp` to
auto `docker exec` container detection with CWD-basename narrowing
(`_wpcli_detect_container`). For a URL-migration script that ALSO supports
remote ship targets via `WP_CLI_RUN="ssh ..."`, the override path is preserved
(resolve honors `WP_CLI_RUN` first), but the unset-default behavior flips to
container auto-detection — which can bind the wrong instance or fall back
unpredictably. The plan asserts the swap is behavior-preserving; it is not for
the default path.

**Failure scenario:** A local `migrate-urls.sh` run with no `WP_CLI_RUN` set now
auto-detects a container; if multiple wp-env instances are up, resolve returns
rc=2 and the migration aborts where it previously used the wp-env default — a
behavior regression introduced by the "mechanical" swap.

**Evidence:**
- `scripts/migrate-urls.sh:45` — `read -r -a _WP_CLI_RUN_ARR <<< "${WP_CLI_RUN:-wp-env run cli wp}"` (current deterministic default).
- `scripts/wp-cli-runner.sh:83-107` — resolve: override → container auto-detect → fallback; rc=2 on ambiguity aborts.
- Phase 3 line 67 — "source `wp-cli-runner.sh`, replace calls with `wp_cli`" (assumes parity).

**Suggested fix:** Call out the default-path behavior change in Phase 3; verify
`migrate-urls.sh`/ship flows always set `WP_CLI_RUN`, or pin
`WP_CLI_REQUIRE_CONTAINER`/explicit runner so the migration's resolution stays
deterministic. Add a regression test for the no-override default.

---

## Assumptions that VERIFIED TRUE (stated to prevent false reversals)

- **stdin forwarding** (Phase 2 claim): TRUE. `wp_cli` runs
  `"${_WP_CLI_ARGV[@]}" "$@"` with no stdin redirection
  (`scripts/wp-cli-runner.sh:127`) and the fast-path runner is
  `docker exec -i <c> wp` (`:92`, `-i` keeps stdin open). `eval-file -` will
  receive the piped payload on the container path.
- **`-tests-cli-1` exclusion** (Phase 2 claim): TRUE.
  `scripts/wp-cli-runner.sh:51` — `grep -E -- '-cli-1$' | grep -Ev -- '-tests-cli-1$'`.
- **Canonical stage-id set** (Phase 4 lines 53-55): CONSISTENT with the contract.
  Phase 4's 19-element list (16 pipeline + `section-redesign`,
  `content-enrichment`, `pre-conversion-qa`) matches
  `references/manifest-contract.md:16-23`. The schema imposes no stage enum
  (`schemas/wp-build.schema.json:304` — "Keys are stage ids", open). No drift
  today — but Phase 4 hard-codes the set as a duplicated array; future contract
  edits will silently drift from the lint. Recommend deriving the set from the
  contract file at lint time rather than re-declaring it.

---

## Findings summary

1. **Critical** — `validate-port.sh` enforces the opposite invariant; Phase 3 misclassifies it (contradictory linters).
2. **Critical** — Phase 4 contract-lint can never go green: 6 files hold `wp-env run cli`, none migrated/allowlisted.
3. **Critical** — `commands/plugin.md`/`wp-plugin-dev` use `wp-env run cli` for non-`wp` binaries; `wpx` cannot represent them.
4. **High** — File/call-site counts wrong & self-contradictory (claims 30 files/~25 sites; actual 33/123; own tallies imply 71+).
5. **High** — Prose swap changes a suggestion not runtime; lint enforces instructions, not executed commands ("locks #1" overstated).
6. **Medium** — `claude plugin validate` assumed available in CI with no skip fallback.
7. **Medium** — Allowlist "fallback line in wpx.sh" is phantom; real fallback strings in seed-helpers.sh/migrate-urls.sh missing.
8. **Medium** — Sourcing the lib silently changes `migrate-urls.sh` default runner resolution (not behavior-preserving).
