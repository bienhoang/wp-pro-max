# WP Plugin Dev implementation journal

**Date:** 2026-06-26  
**Scope:** Add a standalone, opt-in WordPress plugin builder to WP Pro Max.

## What changed

- New `wp-plugin.json` manifest and `schemas/wp-plugin.schema.json`.
- Extracted `scripts/manifest-core.sh` as a shared, zsh-safe helper; refactored
  `scripts/manifest-lib.sh` to thin wrappers and added
  `scripts/plugin-manifest-lib.sh` for `wpplugin_*` + `wpplugin_init`.
- New `scripts/plugin-scaffold.sh` — deterministic skeleton, real PSR-4 fallback
  autoloader, registrar marker, and `add <feature>` generators.
- New `scripts/plugin-env-bootstrap.sh` and `scripts/plugin-package.sh` for the
  plugin-local wp-env dev loop and allowlisted `.zip` packaging.
- New `skills/wp-plugin-dev/` with SKILL.md and reference bodies (architecture,
  feature generators, block build, tooling).
- New `agents/wp-plugin-developer.md` standards-only agent.
- New `commands/plugin.md` (`/wp-pro-max:plugin`).
- Updated README and architecture/roadmap/codebase-summary docs.

## Key decisions

- Kept the plugin builder separate from the HTML→site pipeline; the skill
  no-ops when `wp-build.json` is present and `wp-plugin.json` is absent.
- Templates live in `references/*.md` (kit convention), not a separate
  `templates/` tree, avoiding duplicated bodies.
- Generated plugins always register the fallback autoloader; Composer is only
  for dev tooling.
- Block build uses a per-block `wp-scripts` invocation and copies `block.json`
  into `blocks/<name>/build/` so the PHP registration can find it.

## Verification

- `bash -n` clean for all shell scripts; helpers source cleanly in bash and zsh.
- `jq empty` valid for both schemas; `claude plugin validate .` passes.
- End-to-end against `acme-widgets` in wp-env: activation with zero notices,
  sub-namespaced autoload, PHPCS clean, PHPUnit 3/3, block builds and registers,
  shortcode renders, `.zip` packages with only allowlisted files.

## Open items

- The REST controller smoke test only asserts route registration; a future
  iteration can add authenticated REST round-trip coverage.
- The generated PHPUnit bootstrap re-fires `init` for tests; fuller fixtures
  are listed as a roadmap next step.
