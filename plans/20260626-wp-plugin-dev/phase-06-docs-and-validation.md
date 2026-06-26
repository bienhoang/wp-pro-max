---
phase: 6
title: "Docs and validation"
status: done
effort: ""
priority: P2
dependencies: [1, 2, 3, 4, 5]
---

# Phase 6: Docs and validation

## Overview

Document the new capability, run a **security pass** on generated output, run the
**in-env** end-to-end behavioral verification, and update the roadmap.

## Requirements

- Functional: README + docs describe the standalone plugin builder; a **security
  review** asserts auth/escaping correctness; a full `new → add → activate → lint
  → test → package` run is verified in-env.
- Non-functional: `claude plugin validate .` passes **as a manifest-shape check**;
  new shell `bash -n` clean, plain-JS `node --check` clean; helpers source in
  bash + zsh; existing theme pipeline still green after the Phase 1 core refactor.

## Architecture

Docs + verification phase. No new runtime components. Captures the behavioral and
security verification that the earlier static gates do **not** cover (Red-team
#6, #13).

## Related Code Files

- Modify: `README.md` — add the plugin-builder capability + `/wp-pro-max:plugin` usage; update Components counts (skills 16→17, agents 3→4, commands 3→4, scripts list incl. `manifest-core.sh`, `plugin-manifest-lib.sh`, `plugin-scaffold.sh`, `plugin-env-bootstrap.sh`, `plugin-package.sh`).
- Modify: `docs/codebase-summary.md` — map the new skill/agent/scripts/schema + the `manifest-core.sh` refactor.
- Modify: `docs/system-architecture.md` — note the standalone (non-pipeline) capability + `wp-plugin.json` + plugin-local `.wp-env.json`.
- Modify: `docs/project-roadmap.md` — record this work; correct the stale "no Docker/PHP in build env" note.
- Create (docs only): a documented end-to-end transcript in the plan's report — **not** a committed generated plugin (Red-team #21; existing `examples/` are input fixtures).

## Implementation Steps

1. **README** — new "Plugin development" section: what it does, `new`/`add`/
   `lint`/`test`/`package`, prerequisites (Node for blocks; Composer/PHP via
   wp-env for tooling), standalone/opt-in note (and the in-skill guard). Update
   the Components inventory.
2. **Docs** — update `codebase-summary.md` + `system-architecture.md`; state that
   plugin-build state lives in `wp-plugin.json` (separate from `wp-build.json`)
   and that the manifest helpers now share `manifest-core.sh`.
3. **Static sweep** — `bash -n` every new/modified `.sh`; `node --check` plain
   `.js`; `jq empty` the new schema; `claude plugin validate .` (manifest-shape
   only); source helpers in bash + zsh; re-run the existing theme pipeline's
   manifest checks (regression from Phase 1 refactor).
4. **Security pass (Red-team #6)** — review the generated plugin (reuse
   `skills/wp-security` patterns / `hardening-checklist.md`): every REST write has
   a capability-gated `permission_callback`; every settings/form write uses the
   `options.php` nonce flow or `wp_verify_nonce`; all dynamic output is escaped;
   `uninstall.php` is guarded; no CPT is unintentionally `show_in_rest`.
5. **In-env end-to-end (Red-team #5/#13)** — via Docker/wp-env + npm in this
   environment: `new acme-widgets` → `add cpt`, `add settings`, `add rest`, `add
   shortcode`, `add block` → `lint` → `test` → `package`. Confirm zero-notice
   activation, sub-namespaced autoload, PHPCS clean, PHPUnit green, block builds
   and renders, `.zip` installs with only allowlisted files. Record results;
   capture the transcript. Document any check that genuinely cannot run and the
   precise blocker (do not claim verified what was not run).
6. **Roadmap** — add a completed entry; correct the stale toolchain note;
   relocate resolved open questions; list any remaining (fuller PHPUnit fixtures).

## Success Criteria

- [ ] `claude plugin validate .` passes (manifest-shape check).
- [ ] All new shell `bash -n` clean; plain-JS `node --check` clean; schema valid;
      helpers source in bash + zsh; **existing theme pipeline still passes**.
- [ ] Security pass documented with explicit pass/fail per check (REST caps,
      nonce/CSRF, escaping, uninstall guard, REST exposure).
- [ ] **In-env e2e run verified** end-to-end (activation, autoload, lint, test,
      block build, package) — or the exact unverified gap documented with reason.
- [ ] README/docs accurate (incl. corrected toolchain note); roadmap updated.

## Risk Assessment

- **Claiming verified what was not run** (Red-team #5/#13) → behavioral acceptance
  is the real DoD; `claude plugin validate` is explicitly demoted to a
  manifest-shape check; document precise blockers for anything unrun.
- **Security regressions slipping past static gates** (Red-team #6) → dedicated
  security pass reusing `skills/wp-security`, not left to the agent prompt alone.
- **Docs drift** → update Components counts + architecture notes in the same change.
