# Red-Team Plan Review — Security Adversary + Fact Checker

Plan: `2026-07-01-wpcli-runner-and-test-harness`
Reviewer lens: Security Adversary (injection / wrong-container / allowlist bypass) + Fact Checker (every claim grepped).
Verdict: **Do not approve as written.** Two contradictory gates, a file-level allowlist that exempts the highest-risk DB-op files, an incomplete migration universe that makes the new gate red on day one, and a node_modules-blind test harness.

---

## Finding 1: `validate-port.sh` already enforces the OPPOSITE rule — the plan creates two mutually-exclusive gates
- **Severity:** Critical
- **Location:** Phase 3, section "Related Code Files (migrate)" (lists `scripts/validate-port.sh` under "scripts → source lib"); Phase 4, section "Requirements" rule 3.
- **Flaw:** The plan classifies `scripts/validate-port.sh` as a *runner consumer* to migrate by sourcing `wp-cli-runner.sh` and calling `wp_cli`. It is not a runner consumer at all — it is an existing **doc linter** whose rule is the exact inverse of the new contract-lint. `validate-port.sh:188` raises an error when a WP-CLI snippet does **not** use `wp-env run cli wp`, while Phase 4 rule 3 raises an error when a snippet **does** use `wp-env run cli`. After Phase 3 rewrites ~25 prose snippets to `wpx`, `validate-port.sh` flags every one of them; the new lint flags any that are left raw. No prose state can satisfy both.
- **Failure scenario:** Phase 3 lands. `test/run.sh` (Phase 1) is supposed to be "the single green gate," but if it ever invokes `validate-port.sh` it now fails on the migrated snippets ("should use 'wp-env run cli wp ...'"), and the contract-lint independently fails on whatever raw calls remain. The team is wedged: every edit that pleases one linter breaks the other. Separately, the contract-lint's own `grep -rn 'wp-env run cli'` matches `validate-port.sh:188` (the literal appears in both the regex and the error string), so the gate fails on the linter file itself unless it is allowlisted — which the plan never does.
- **Evidence:** `scripts/validate-port.sh:185-190` (`if [[ ! "$line" =~ wp-env[[:space:]]+run[[:space:]]+cli[[:space:]]+wp ]]; then log_error "...should use 'wp-env run cli wp ...'"`); Phase 3 file line 57 (migrate list includes `scripts/validate-port.sh`); Phase 4 file lines 23, 62.
- **Suggested fix:** Add an explicit phase task to *invert or remove* `validate-port.sh`'s WP-CLI-snippet rule (it should now require `wpx`, or be deleted in favor of the contract-lint). Remove `validate-port.sh` from the "source the lib" list — it does not run WP-CLI, it lints prose. Allowlist or rewrite the literal on line 188.

---

## Finding 2: File-level allowlist blanket-exempts the ship DB-op runbook — dangerous raw calls slip through forever
- **Severity:** High
- **Location:** Phase 3, section "Architecture" (allowlist definition); Phase 4, section "Architecture" ("The allowlist is an explicit array of repo-relative paths").
- **Flaw:** The allowlist is **per-file**, not per-line/per-pattern. Whole files (`skills/wp-ship/references/ssh-wpcli-runbook.md`, `ai1wm-runbook.md`, `references/wp-cli-cheatsheet.md`, `commands/env.md`, and `wp-cli-runner.sh`/`wpx.sh`) are exempted in full. The ship runbook is precisely where remote, destructive DB operations live (`wp db export`, and by extension `db import`/`db query`/`search-replace --apply` on production over SSH). Exempting the entire file means the regression guard is blind exactly where the blast radius is largest.
- **Failure scenario:** A later edit adds `wp-env run cli wp db query "DROP TABLE wp_users"` or a destructive `db import` example into `ssh-wpcli-runbook.md`. Because the file is wholly allowlisted, the contract-lint stays green; the "always use wpx / no raw call rot" invariant the plan sells as its centerpiece is silently defeated for the one file class that runs DB mutations against production. An operator copy-pastes the unguarded example and runs it against the wrong host.
- **Evidence:** `skills/wp-ship/references/ssh-wpcli-runbook.md:44` (`wp-env run cli wp db export - > /tmp/local.sql` — file allowlisted in full per Phase 3 lines 38-40, 58-59); Phase 4 file lines 40-42 ("array of repo-relative paths"); `scripts/wp-cli-runner.sh:22,106` (comment line 22 vs real fallback line 106 — a file-level entry can't distinguish them either).
- **Suggested fix:** Allowlist by anchored line content, not by file. Encode the few legitimate literals (the runner fallback `printf 'wp-env run cli wp\n'`, the cheatsheet's documented form, the runbook's specific export line) as exact-match exceptions, so any *new* raw call in those files still FAILs.

---

## Finding 3: Test harness scans `node_modules` — the gate lints dependencies and goes nondeterministic
- **Severity:** High
- **Location:** Phase 1, section "Implementation Steps" steps 3-5; Phase 4, section "Implementation Steps" step 5.
- **Flaw:** Every traversal excludes only `./.git/*`: `find . -name '*.sh'`, `find . -name '*.mjs'`, the container `php -l` walk, and the contract-lint's `grep -rn 'wp-env run cli'`. `node_modules/` exists in this repo (`package.json` has `devDependencies`). The harness will `bash -n` / `node --check` / `grep` across the entire dependency tree.
- **Failure scenario:** `node --check` runs over hundreds of vendored `.mjs` files authored for newer/older Node syntax, or `bash -n` over a dependency's install script with shell constructs the local bash rejects → the "single green gate" fails on third-party code the team never wrote, and pass/fail varies by machine and by `npm install` state. Best case it is merely slow; worst case it is permanently red and not deterministically reproducible. The contract-lint's `grep` also scans vendored docs, inflating findings.
- **Evidence:** Phase 1 file lines 43-48 (`find . -name '*.sh' -not -path './.git/*'`, `find . -name '*.mjs'`, container `php -l` each `*.php`); Phase 4 file line 62 (`grep -rn 'wp-env run cli'`); repo has `node_modules/` present and `package.json:9` (`"devDependencies"`).
- **Suggested fix:** Exclude `node_modules`, `vendor`, and `.git` in every `find`/`grep` (e.g., `-not -path './node_modules/*' -not -path './vendor/*'` or `git ls-files`). Prefer `git ls-files '*.sh' '*.mjs' '*.php'` so the gate only ever inspects tracked plugin sources.

---

## Finding 4: Migration universe is incomplete — the new lint is red on day one, and some raw calls are not wpx-convertible
- **Severity:** High
- **Location:** Phase 3, section "Related Code Files (migrate)" and "Architecture" (allowlist); Phase 4 rule 3.
- **Flaw:** Files carrying raw `wp-env run cli` are neither in the migrate list nor the allowlist:
  (a) `commands/plugin.md:63,73` — and these are `wp-env run cli composer install`, `wp-env run cli vendor/bin/phpcs`, `wp-env run tests-cli phpunit`. `wpx` wraps only `wp` subcommands (it prepends `wp`/runner), so these **cannot** be migrated to `wpx` at all, yet the Phase 4 pattern `wp-env run cli` matches them and will FAIL them.
  (b) `references/manifest-contract.md:52` — has a raw call; Phase 5 edits this file but the plan does not guarantee the literal is removed or allowlisted.
  (c) `scripts/seed-helpers.sh` — the plan hedges "seed-helpers.sh if still present"; it **is** present, defaults to `wp-env run cli wp` at lines 60/63 plus comment lines 29-31, and is not in the migrate list or allowlist. The "if still present" wording proves the migration set was not verified against the tree.
- **Failure scenario:** Phase 4 lands; `test/contract-lint.sh` immediately FAILs on `commands/plugin.md`, `seed-helpers.sh`, and possibly `manifest-contract.md`. For `commands/plugin.md` there is no valid fix (those are not `wp` commands), so the gate is unsatisfiable without either narrowing the lint pattern or adding ad-hoc allowlist entries the plan never budgeted.
- **Evidence:** `commands/plugin.md:63,73` (`wp-env run cli composer install`, `wp-env run cli vendor/bin/phpcs`, `wp-env run tests-cli phpunit`); `references/manifest-contract.md:52`; `scripts/seed-helpers.sh:30-31,60,63`; Phase 3 file lines 42-59 (migrate + allowlist lists omit all three); Phase 4 file line 23.
- **Suggested fix:** Re-derive the full universe with `grep -rln 'wp-env run cli'` (30 files; verified) and explicitly bucket each into migrate / allowlist / cannot-convert. Narrow the lint to match only `wp-env run cli wp` (the wpx-convertible form), so `composer`/`phpcs`/`tests-cli` lines are not falsely flagged. Resolve whether `seed-helpers.sh` is live or dead before depending on it.

---

## Finding 5: Re-pointing `migrate-urls.sh` at the auto-detect runner changes the runner for a destructive production search-replace
- **Severity:** High
- **Location:** Phase 3, section "Related Code Files (migrate)" ("Modify (scripts → source lib): `scripts/migrate-urls.sh`"); plan.md "Acceptance criteria" bullet 2.
- **Flaw:** `migrate-urls.sh` is the ship-stage URL rewriter that runs `wp search-replace ... --apply` (a live DB mutation). It currently sources `manifest-lib.sh` (for `wpbuild_get`, used to read `urls.local`/`urls.production`) and defines its **own** `wp_cli` defaulting to the deterministic `wp-env run cli wp`. Phase 3 says to "source `wp-cli-runner.sh` and call `wp_cli`." That swap (a) changes runner resolution for a destructive op from a fixed target to CWD-basename container auto-detection, and (b) risks dropping the `manifest-lib.sh` source if "source the lib" is read as replace-not-add — which breaks `wpbuild_get` and thus the from/to URL read. The plan's own acceptance says "ship SSH `WP_CLI_RUN` path untouched," yet this script is the SSH ship migration tool and is on the modify list.
- **Failure scenario:** With `WP_CLI_RUN` unset (a local `--apply`), the new auto-detect either binds a different `-cli-1` than the old fixed `wp-env run cli` did, or hard-fails on a multi-instance host where the old path worked — for a command that *writes* the database. If the implementer replaces rather than augments the `source` line, `wpbuild_get` is undefined and `migrate-urls.sh` aborts at URL resolution, or worse silently reads empty URLs.
- **Evidence:** `scripts/migrate-urls.sh:35-49` (own `wp_cli`, default `wp-env run cli wp`, sources `manifest-lib.sh`), `:91-92` (`wpbuild_get '.urls.local'`/`.urls.production`), `:140,165` (`search-replace --dry-run` / `--apply`); Phase 3 file lines 56-57; plan.md lines 53, 88.
- **Suggested fix:** Spell out for `migrate-urls.sh`: keep the `manifest-lib.sh` source, *add* the runner lib, and preserve the deterministic default for a destructive op (or require `WP_CLI_RUN`/`WP_CLI_REQUIRE_CONTAINER` for `--apply`). Add an explicit test that `--apply` resolves to the intended target and that `urls.*` still read.

---

## Finding 6: Phase 4 stage-id rule is unimplementable as specified — no parseable stage declaration exists
- **Severity:** Medium
- **Location:** Phase 4, section "Requirements" rule 2 and "Implementation Steps" step 4 ("grep stage-id declarations; assert ∈ canonical").
- **Flaw:** Skills do not declare their stage id in any structured field — there is no `stage:` frontmatter key in any `SKILL.md`, and skill directory names (`html-analysis`, `design-tokens`, `theme-conversion`) are not the stage ids (`analyze`, `tokens`, `convert`). Stage ids appear only inside free-prose `description` text (e.g., "...reaches the `analyze` stage"). "Grep stage-id declarations" has no anchor: it will either match nothing (the rule silently enforces nothing — a false sense of a gate) or match prose tokens and throw false positives that block the gate on valid skills.
- **Failure scenario:** The rule ships, greps for backticked words, and flags a legitimate skill that mentions another stage in prose ("after `convert`, run `seed-content`") as an out-of-set violation — or matches nothing and provides zero real enforcement while reporting green. (Note: the canonical set in Phase 4 step 1, including `section-redesign`/`content-enrichment`/`pre-conversion-qa`, *was* verified correct against `references/manifest-contract.md:16-19` — the defect is the detection mechanism, not the list.)
- **Evidence:** No `^stage:` in any `skills/*/SKILL.md` (grep returns empty); `skills/html-analysis/SKILL.md:1-14` (stage id "analyze" appears only in prose `description`, frontmatter has no stage field); name==dir confirmed for sampled skills (so the rule-1 name check is fine); Phase 4 file lines 21-22, 61.
- **Suggested fix:** Define an actual machine-readable anchor (add a `stage:` frontmatter key to each `SKILL.md`, or map dir→stage in the lint), then assert against it. Do not lint stage ids from prose.

---

## Non-issues confirmed (so they are not re-raised)
- **Seeder stays safe:** `seed-batch-run.sh` is *not* in the migration set; it keeps its own `docker cp` + `docker exec -i ... < payload` transport and the silent-zero-op / incomplete-run guards (`scripts/seed-batch-run.sh:24-136`). The migration does not regress it.
- **stdin forwarding:** `wp_cli` forwards the caller's stdin naturally via `"${_WP_CLI_ARGV[@]}" "$@"` (`scripts/wp-cli-runner.sh:123-128`); the Phase 2 stdin claim is accurate.
- **argv injection:** WP subcommands pass through as argv (no shell eval), so LLM-generated content in titles/options is not a shell-injection surface via `wpx`. `WP_CLI_RUN` is operator-set, not external input.
- **Canonical stage list** in Phase 4 step 1 matches the contract (`references/manifest-contract.md:16-19`).
- **"30 files" claim** matches the tree (`grep -rln 'wp-env run cli'` → 30 files).

---

## Findings summary
1. `validate-port.sh` enforces the opposite rule — two mutually-exclusive gates — **Critical**
2. File-level allowlist blanket-exempts the ship DB-op runbook (dangerous raw calls slip through) — **High**
3. Test harness scans `node_modules` — gate lints dependencies, nondeterministic — **High**
4. Migration universe incomplete (`commands/plugin.md`, `manifest-contract.md`, `seed-helpers.sh`); some raw calls are not wpx-convertible — **High**
5. `migrate-urls.sh` runner swap changes target for a destructive production search-replace; risks dropping `manifest-lib` — **High**
6. Phase 4 stage-id rule unimplementable — no parseable stage declaration — **Medium**
