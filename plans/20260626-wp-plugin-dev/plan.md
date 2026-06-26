---
title: "WP Plugin Dev — standalone WordPress plugin builder skill"
description: ""
status: done
priority: P2
branch: "main"
tags: []
blockedBy: []
blocks: []
created: "2026-06-26T08:18:07.678Z"
createdBy: "ck:plan"
source: skill
---

# WP Plugin Dev — standalone WordPress plugin builder skill

## Overview

Add a **standalone, opt-in** capability to `wp-pro-max` that scaffolds and
develops brand-new WordPress plugins from scratch — separate from the existing
HTML→site pipeline, leaving `wp-scaffold` and `wp-build.json` untouched.

Mirrors the kit's theme-side convention (**Approach B**): a `wp-plugin-dev`
skill (procedure) → a `wp-plugin-developer` agent (heavy PHP) → deterministic
scripts (`plugin-scaffold.sh`, `plugin-package.sh`) → `references/` templates,
driven by a small `wp-plugin.json` manifest. Generated plugins are **OOP +
PSR-4 autoloader**, ship core feature generators (CPT/taxonomy, Settings API
page, REST route, shortcode) **plus a Gutenberg block**, and carry a **full dev
loop** (Composer + PHPCS/WPCS + PHPUnit via wp-env + readme.txt + `.zip`
packaging). Opt-in entry: `/wp-pro-max:plugin`.

Design source: [`brainstorm-wp-plugin-dev.md`](./brainstorm-wp-plugin-dev.md).

### New components (all additive)

| Component | Path | Phase |
|-----------|------|-------|
| Manifest schema | `schemas/wp-plugin.schema.json` | 1 |
| Shared manifest core (zsh-safe) | `scripts/manifest-core.sh` (+ refactor `manifest-lib.sh` to wrap it) | 1 |
| Plugin manifest wrappers | `scripts/plugin-manifest-lib.sh` (`wpplugin_*` + `init`) | 1 |
| Skill | `skills/wp-plugin-dev/SKILL.md` + `references/` (bodies embedded, no `templates/` dir) | 1,3,4,5 |
| Opt-in command | `commands/plugin.md` (`/wp-pro-max:plugin`, allowed-tools incl. `Task`,`Skill`) | 1 |
| Plugin wp-env bootstrap | `scripts/plugin-env-bootstrap.sh` (plugin-local `.wp-env.json`) | 5 |
| Scaffold script | `scripts/plugin-scaffold.sh` | 2 |
| Agent | `agents/wp-plugin-developer.md` (standards only, not feature bodies) | 2 |
| Package script | `scripts/plugin-package.sh` (allowlist) | 5 |

### Resolved design decisions (were open questions in brainstorm)

1. **No-composer fallback** — generated plugins ship a hand-rolled **real PSR-4**
   `require` autoloader (full namespace tail → subdirectory under `src/`, not
   shortname→flat `src/`), so they run without Composer. The bootstrap
   `<slug>.php` loads `vendor/autoload.php` when present, else `inc/autoload.php`
   — the precedence is baked into the Phase 2 template (not added later). The
   autoloader anchors on the plugin namespace prefix and contains paths under
   `src/` (no traversal). Composer is needed only for dev tooling (WPCS, PHPUnit)
   and `--no-dev` packaging. *(Red-team: autoloader-psr4, autoloader-precedence,
   autoloader-traversal.)*
2. **Manifest helper** — **do NOT duplicate** `manifest-lib.sh`. Extract its
   generic helpers into a shared `scripts/manifest-core.sh` parameterized by
   `$MANIFEST_FILE`; `manifest-lib.sh` keeps its `wpbuild_*` public API as thin
   back-compat wrappers, and `plugin-manifest-lib.sh` adds `wpplugin_*` wrappers
   + its own `init` (the only genuinely different function) over the same core.
   This avoids fixing the recorded zsh-sourcing bug twice. The existing theme
   pipeline must be re-tested (bash+zsh, idempotent mock) after the refactor.
   *(Red-team: manifest-lib-duplication.)*
3. **Test harness depth** — v1 ships a minimal WP-PHPUnit smoke test
   (activation with zero notices + one feature assertion); fuller fixtures left
   for a later iteration.
4. **Verification runs in THIS env** — Docker, Composer, npm/node, jq, zip are
   all present (only host `php` is absent; PHP runs inside wp-env containers). So
   activation, PHPCS, PHPUnit, and the block build are verified here via
   Docker/wp-env + npm — not deferred to a hypothetical other machine. The stale
   "no Docker/PHP in build env" roadmap note no longer holds. *(Red-team:
   stale-toolchain-premise.)*
5. **wp-env reuse is plugin-local** — `wp-env-bootstrap.sh` is theme-bound
   (requires `wp-build.json` + `themeSlug`, mounts only themes). The plugin path
   uses a **plugin-local `.wp-env.json`** mapping the plugin dir into
   `wp-content/plugins/<slug>`, generated from `wp-plugin.json`. "Reuse the theme
   bootstrap" was incorrect. *(Red-team: wp-env-bootstrap-theme-only.)*
6. **Opt-in is enforced in the skill body, not just by command omission** —
   skills auto-invoke by description in this kit, so the `wp-plugin-dev`
   description is narrowed to "build a standalone WordPress plugin from scratch"
   intent and the skill body **no-ops when `wp-build.json` is present and
   `wp-plugin.json` is absent** (i.e. inside a theme build), preventing collision
   with `wp-scaffold`. *(Red-team: opt-in-auto-invoke-collision.)*
7. **Templates live in reference `.md`, not a `templates/` tree** — the kit
   convention (`theme-conversion`) embeds canonical, ready-to-copy bodies inside
   reference `.md`. No `skills/*/templates/` dir exists. The scaffold script
   interpolates tokens into bodies sourced from the reference `.md`; the agent
   carries WPCS/security standards only (single source per feature). *(Red-team:
   templates-dir-duplication, feature-code-triple-encoded.)*

### Acceptance (whole plan)

- **Behavioral (verified in-env via Docker/wp-env + npm):**
  `/wp-pro-max:plugin new acme-widgets` then `add cpt|tax|settings|rest|
  shortcode|block`, mounted via the plugin-local `.wp-env.json`, **activates with
  zero PHP notices**; a sub-namespaced class (e.g. `…\PostTypes\…`) loads via the
  no-Composer autoloader; each feature actually works (CPT in admin, REST route
  responds, settings saves sanitized, shortcode renders escaped, block builds and
  renders). This is the real definition of done — not a manifest check.
- Generated plugin passes its own **PHPCS (WPCS)** clean (via wp-env/Docker);
  `package` yields an installable `.zip` containing **only allowlisted files**
  (no dev configs, no secrets, block `build/` present).
- A **security pass** confirms every REST write has a capability-gated
  `permission_callback`, every form/settings write verifies a nonce, and dynamic
  output is escaped.
- `claude plugin validate .` passes **as a manifest-shape check only** (not proof
  of behavior); new shell `bash -n` clean, node `node --check` clean;
  `manifest-core.sh` + both wrappers source in **bash and zsh**; the existing
  theme pipeline still passes after the core refactor.
- `wp-plugin.json` makes runs idempotent/resumable (per-file check-before-write).

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Foundation](./phase-01-foundation.md) | Done |
| 2 | [Scaffold engine](./phase-02-scaffold-engine.md) | Done |
| 3 | [Feature generators](./phase-03-feature-generators.md) | Done |
| 4 | [Gutenberg block](./phase-04-gutenberg-block.md) | Done |
| 5 | [Dev loop](./phase-05-dev-loop.md) | Done |
| 6 | [Docs and validation](./phase-06-docs-and-validation.md) | Done |

## Dependencies

- **`20260626-wp-pro-max-kit`** — COMPLETE (v0.1). Provides the conventions this
  plan mirrors (`manifest-lib.sh`, `wp-env-setup`, `wp-theme-developer`,
  skill/agent/command structure). No blocking relationship: this plan is purely
  additive and changes nothing the kit plan depends on.
- **External toolchain** — Docker/wp-env, Node ≥ 20 + `@wordpress/scripts`,
  Composer + PHPCS/WPCS + PHPUnit. **All present in this env except host `php`**
  (PHP runs inside wp-env containers; Composer host-run needs php so run it via
  `wp-env run cli composer …` when needed). Verification is done here, not
  deferred. Scaffolding still stays toolchain-free so a generated plugin needs no
  Composer to run.

## Out of scope

Wiring into the default HTML→site pipeline; premium-plugin scaffolds;
multisite-specific features; WordPress.org SVN submission automation.

## Validation Log

### Session — 2026-06-26
Red Team section already present with evidence → verification pass skipped per the
validate guard; no `[UNVERIFIED]` tags. 4 critical-questions asked, 4 confirmed.

| Q | Decision | Effect |
|---|----------|--------|
| Manifest refactor | **Shared `manifest-core.sh` + regression test** | Confirms plan decision #2; `wpbuild_*` stay back-compat wrappers; theme-pipeline regression check is a Phase 1 gate. |
| Output location | **`new <slug>` scaffolds into `./<slug>/` in CWD** | `wp-plugin.json` + tree live under `./<slug>/`; the plugin-local `.wp-env.json` maps `./<slug>/` → `wp-content/plugins/<slug>`. *(was implicit; now pinned)* |
| Verify depth | **Full in-env e2e now** | Implementation must stand up wp-env and verify activation/lint/test/block-build/package end-to-end (Phase 6) this round — not deferred. |
| Namespace input | **Auto-derive PascalCase from slug**, optional override | Confirms Phase 1 step 2; `new acme-widgets` → `AcmeWidgets`, override via optional arg. |

No decision reversed a locked choice. Output-location decision propagated to
phase-01 (command/init) and phase-02/phase-05 (scaffold target + wp-env mapping).

### Whole-Plan Consistency Sweep
Re-read all files after propagation. `./<slug>/` output path now consistent
across plan.md, phase-01, phase-02, phase-05; wp-env mapping references the same
path. No stale or contradictory claims. Zero unresolved contradictions.

## Red Team Review

### Session — 2026-06-26
**Findings:** 22 (22 accepted, 0 rejected) — consolidated from 4 hostile
reviewers (Security Adversary, Failure Mode Analyst, Assumption Destroyer, Scope
& Complexity Critic). All carried `file:line` evidence; two load-bearing claims
re-verified by the controller (toolchain present; `wp-env-bootstrap.sh`
theme-only).
**Severity breakdown:** 2 Critical, 9 High, 11 Medium.

| # | Finding | Severity | Disposition | Applied To |
|---|---------|----------|-------------|------------|
| 1 | Fallback autoloader maps shortname→flat `src/`, but classes live in sub-namespaced dirs → fatal on activation | Critical | Accept | Phase 2 |
| 2 | `wp-env-bootstrap.sh` is theme-only (requires `wp-build.json`/`themeSlug`, mounts themes) — "reuse" impossible | Critical | Accept | Phase 5 |
| 3 | Command `allowed-tools` lacks `Skill`/`Task` → router can't dispatch | High | Accept | Phase 1 |
| 4 | Composer-vs-fallback autoloader precedence never wired into `<slug>.php` | High | Accept | Phase 2 |
| 5 | Stale "toolchain absent" premise — Docker/composer/npm present; verify in-env | High | Accept | Phases 2,5,6 |
| 6 | No security-verification gate on generated plugins | High | Accept | Phase 6 |
| 7 | Zip denylist leaks secrets/dev files → allowlist + failing assertion | High | Accept | Phase 5 |
| 8 | `Plugin.php` registry marker not a guaranteed invariant (agent free-forms it) | High | Accept | Phases 2,3 |
| 9 | No atomicity across class-write + registry-edit + manifest-append | High | Accept | Phase 3 |
| 10 | "Opt-in" unenforceable (skills auto-invoke by description; collides with `wp-scaffold`) | High | Accept | Phase 1 |
| 11 | `references/templates/` double-stores code the kit keeps in reference `.md` | High | Accept | Phases 2-5 |
| 12 | Hand-rolled autoloader has no path-traversal guard | Medium | Accept | Phase 2 |
| 13 | `claude plugin validate` is manifest-only, not behavioral | Medium | Accept | Phases 1,6 |
| 14 | `wpplugin_init` arg/required-field & namespace-derivation mismatch | Medium | Accept | Phase 1 |
| 15 | Block `build/` git-ignored → may be dropped from zip | Medium | Accept | Phases 4,5 |
| 16 | `show_in_rest: true` exposes CPT publicly by default | Medium | Accept | Phase 3 |
| 17 | Settings page CSRF — pin to `settings_fields()`/`options.php` flow | Medium | Accept | Phase 3 |
| 18 | Idempotency claim false (coarse stage guard; non-deterministic agent) | Medium | Accept | Phase 2 |
| 19 | `plugin-manifest-lib.sh` near-verbatim of `manifest-lib.sh` → shared core | Medium | Accept | Phase 1 |
| 20 | "Mirrors theme side" two-layer-script rationale is fabricated | Medium | Accept | Phase 2 |
| 21 | Committed `examples/sample-plugin/` is gold-plating → transcript instead | Medium | Accept | Phase 6 |
| 22 | Phase 4 must reuse Phase 3's `add` dispatcher, not re-implement it | Medium | Accept | Phase 4 |

### Whole-Plan Consistency Sweep

Applied after edits; see per-phase notes. Reconciled terms across all files:
- "parallel `plugin-manifest-lib.sh`" → "shared `manifest-core.sh` + thin
  wrappers" (plan.md, phase-01).
- "reuse `wp-env-bootstrap.sh`" → "plugin-local `.wp-env.json` via
  `plugin-env-bootstrap.sh`" (plan.md, phase-05, phase-06).
- "toolchain not installed / verify on a toolchained machine" → "verify in-env
  via Docker/wp-env + npm" (plan.md, phase-02, phase-05, phase-06).
- "`references/templates/…`" → "bodies embedded in reference `.md`" (phase-02..05).
- autoloader "via filename" → "full namespace tail → subdir, with prefix anchor +
  containment + `vendor/autoload.php` precedence" (phase-02).
- `claude plugin validate` reframed as manifest-shape-only everywhere; behavioral
  acceptance added (plan.md, phase-01, phase-06).

No unresolved contradictions remain.
