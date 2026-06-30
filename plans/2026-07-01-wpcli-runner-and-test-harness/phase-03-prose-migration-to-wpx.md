---
phase: 3
title: "Prose migration to wpx"
status: done
effort: "M"
---

# Phase 3: Prose migration to wpx

## Overview

Rewrite the **prose `wp` call-sites in `skills/` + `agents/`** from
`wp-env run cli wp …` to `bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" …` so the
documented default is the fast path. **Scope is prose-only.** Scripts are out
(Red Team #6/#7). Phase 4's lint then keeps it consistent.

## Requirements

- Functional: instructional `wp-env run cli wp X` in `skills/`+`agents/` → `wpx … X`
  (the wrapper calls `wp_cli`, which prepends `wp` — pass the subcommand only,
  no `wp` prefix). Re-measure the true set first (Red Team #11: the tree has
  ~33 files / ~120 lines of `wp-env run cli`, NOT "30/~25"; after subtracting
  scripts, non-`wp` commands, docs, and the allowlist, the actual migrate set is
  the `skills/`+`agents/` `wp`-subcommand lines).
- Non-functional: preserve each command's semantics and flags exactly.

## Architecture

**Three classes — only the first migrates:**

1. **Skill/agent prose** (`skills/**/*.md`, `agents/*.md`) — token-replace,
   keeping args. This is the migrate set.
2. **Scripts — OUT OF SCOPE (do not source the lib into them).**
   - `scripts/seed-helpers.sh` **defines its own `wp_cli`** (`:67`) with
     different semantics than `wp-cli-runner.sh:116`; sourcing both = an
     order-dependent clobber (Red Team #6). Leave it; it is also slated for
     retirement by the (done) fast-seeder plan — verify whether it is still
     referenced; if dead, removal is a separate cleanup, not this plan.
   - `scripts/migrate-urls.sh` runs a **destructive prod `search-replace --apply`**
     and has its own `wp_cli`/`WP_CLI_RUN` path (`:45,91-92`). Swapping its
     runner silently changes the DB target (Red Team #7). Leave it untouched;
     allowlist it.
3. **Non-`wp` commands — allowlist, cannot migrate.** `commands/plugin.md:63,73`
   uses `wp-env run cli composer …`, `vendor/bin/phpcs`, and
   `wp-env run tests-cli phpunit`; `wpx` only runs `wp` subcommands (Red Team #3).
   Same for `skills/wp-security/references/vuln-scan.sh` if it shells non-`wp`.

**Reconcile `validate-port.sh`, do NOT just allowlist it (Red Team #1).** Its
snippet linter currently *asserts snippets use `wp-env run cli wp`*
(`scripts/validate-port.sh:185-188`) — the exact inverse of Phase 4's rule. No
tree can pass both. Fix: **update that assertion to require `wpx`** so both
linters enforce the same canonical. (It is a `.sh`, but this is an assertion-
string change, not a runner swap — safe, unlike #6/#7.)

**Allowlist (explicit, reasoned — the single source consumed by Phase 4):**
| Path / pattern | Why it stays raw |
|---|---|
| `scripts/wp-cli-runner.sh` (fallback line `:99`) | the fallback string itself |
| `scripts/seed-helpers.sh`, `scripts/migrate-urls.sh` | script-internal runners (#6/#7) |
| `commands/env.md` | it *is* the env wrapper command |
| `commands/plugin.md`, `vuln-scan.sh` non-`wp` lines | not `wp` subcommands (#3) |
| `skills/wp-ship/references/{ssh-wpcli,ai1wm}-runbook.md` | remote SSH `WP_CLI_RUN` form |
| `references/wp-cli-cheatsheet.md` | documents both forms |
| docs (`README.md`, `docs/system-architecture.md`, `docs/tech-stack.md`, `references/manifest-contract.md`) | reconciled in P5 to show `wpx` as canonical; any residual `wp-env run cli` mention is explanatory |

Note (Red Team #13): there is **no** "fallback line inside `wpx.sh`" — `wpx.sh`
is a pure shim; do not list a phantom entry. The real fallback strings are in
`wp-cli-runner.sh` and `migrate-urls.sh`.

## Related Code Files

- Modify (migrate prose `wp` call-sites): `skills/wp-performance-backend/SKILL.md`,
  `skills/wp-security/SKILL.md` + `references/hardening-checklist.md`,
  `skills/wp-i18n/SKILL.md` + `references/multilingual-data.md` +
  `references/translation-ready.md`, `skills/wp-seo/SKILL.md` +
  `references/seo-plugin-config.md`, `skills/theme-conversion/SKILL.md` +
  `references/page-builder.md`, `skills/plugin-data-seeding/references/forms-seeding.md`,
  `skills/wp-scaffold/SKILL.md`, `skills/content-seeding/SKILL.md`,
  `skills/plugin-selection/SKILL.md`, `skills/wp-qa/SKILL.md`,
  `skills/wp-env-setup/SKILL.md` (env-check line), `agents/wp-theme-developer.md`,
  `agents/wp-data-engineer.md`, `agents/wp-deployer.md` (non-ship-SSH lines).
  Note: `vuln-scan.sh` — migrate only its `wp` lines; allowlist any non-`wp` line.
- Modify (assertion only, NOT a runner swap): `scripts/validate-port.sh`
  (`:185-188` → require `wpx` instead of `wp-env run cli wp`).
- Do NOT modify (allowlist — see table above): `scripts/seed-helpers.sh`,
  `scripts/migrate-urls.sh`, `commands/env.md`, `commands/plugin.md`,
  `references/wp-cli-cheatsheet.md`, ship SSH runbooks, the fallback lines.

## Implementation Steps

1. **Recount the truth** (Red Team #11): `grep -rn 'wp-env run cli' . --include='*.md'
   --include='*.sh' | grep -v node_modules` across the whole repo. Bucket each
   line into: migrate (skills/agents `wp` prose) | allowlist | validate-port
   assertion. The bucketed list IS the work order.
2. Migrate bucket 1 file by file: `wp-env run cli wp <sub>` →
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" <sub>`, preserving flags.
3. Update `validate-port.sh:185-188` assertion string to `wpx` (Red Team #1).
4. After each file, re-grep that file to confirm only allowlisted mentions remain.
5. **Confirm Phase 3's done-grep scope == Phase 4's lint scope** (Red Team #2):
   both walk the whole repo minus `node_modules`/`vendor`/`.git`; a residual
   non-allowlisted `wp-env run cli` ANYWHERE fails the gate. Do not scope the
   done-check to `skills/ agents/` only.
6. Run `test/run.sh` (must be green: bash -n, plugin validate, validate-port,
   contract-lint once Phase 4 lands).

## Success Criteria

- [ ] Whole-repo `grep 'wp-env run cli'` (minus excludes) returns ONLY allowlisted
      lines — verified at the same scope Phase 4 lints, not just `skills/ agents/`.
- [ ] `validate-port.sh` asserts `wpx` (agrees with the new lint); both green together.
- [ ] Each migrated command keeps identical WP subcommand + flags.
- [ ] Scripts (`seed-helpers.sh`, `migrate-urls.sh`) untouched; no `source
      wp-cli-runner.sh` added to them; no `wp_cli` collision introduced.
- [ ] Ship SSH `WP_CLI_RUN` runbooks + `commands/env.md` + `commands/plugin.md`
      non-`wp` lines unchanged.
- [ ] `test/run.sh` green after migration.

## Risk Assessment

- *Semantic drift during bulk edit* → per-file re-grep + plugin validate;
  high-call files (i18n/security/seo) reviewed line-by-line.
- *Mis-bucketing a non-`wp` line into migrate* → it would produce a broken
  `wpx composer …`; caught by reading each line's command before replacing, and
  by `commands/plugin.md` being wholly in the allowlist.
- *validate-port edit breaks its own tests* → run `validate-port.sh` (via
  `test/run.sh`) after the assertion change.
