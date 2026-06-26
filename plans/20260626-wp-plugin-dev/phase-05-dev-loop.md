---
phase: 5
title: "Dev loop"
status: done
effort: ""
priority: P2
dependencies: [2, 3]
---

# Phase 5: Dev loop

## Overview

Wire the build/test/dev loop onto a generated plugin: Composer + PHPCS (WPCS)
lint, a PHPUnit smoke test on a **plugin-local wp-env**, readme.txt, and an
**allowlist** `.zip` packaging step.

## Requirements

- Functional: `lint` runs PHPCS; `test` runs PHPUnit against a wp-env that
  actually mounts the plugin; `package` builds a distributable `.zip` from an
  allowlist (`composer install --no-dev`, force-includes block `build/`).
- Non-functional: tooling degrades gracefully when a tool is missing (clear
  message, non-zero exit), never corrupts the plugin.

## Architecture

`composer.json` declares PSR-4 autoload (`Namespace\` → `src/`) + dev deps
(`squizlabs/php_codesniffer`, `wp-coding-standards/wpcs`, `phpunit/phpunit` +
`yoast/phpunit-polyfills`). When `vendor/autoload.php` exists it is loaded by the
Phase 2 bootstrap (precedence already wired — no `<slug>.php` edit needed here).

**Plugin-local wp-env (Red-team #2, #5).** `wp-env-bootstrap.sh` is theme-bound
(requires `wp-build.json` + `themeSlug`, mounts only themes), so it is **not
reused**. A new `scripts/plugin-env-bootstrap.sh` generates a plugin-local
`.wp-env.json` from `wp-plugin.json` whose `mappings` bind the plugin dir into
`wp-content/plugins/<slug>`, then `wp-env start`. PHPUnit runs via `wp-env run
tests-cli` and PHPCS/Composer via `wp-env run cli composer …` (host `php` absent;
PHP lives in the container).

Packaging is deterministic with an **allowlist** (Red-team #7): ship only known
plugin files; fail on anything else or any secret-pattern match.

## Related Code Files

- Create: `scripts/plugin-env-bootstrap.sh` — plugin-local `.wp-env.json` + start (driven by `plugin-manifest-lib.sh`).
- Create: `scripts/plugin-package.sh` — allowlist `.zip` builder (`--no-dev`, force-include block `build/`).
- Create: `skills/wp-plugin-dev/references/tooling.md` — composer/phpcs/phpunit/packaging contract + bodies (`composer.json`, `phpcs.xml.dist`, `readme.txt`, `phpunit.xml.dist`, `tests/test-activation.php`).
- Modify: `scripts/plugin-scaffold.sh` — emit composer/phpcs/readme/test stubs when `tooling.*` flags set.
- Modify: `skills/wp-plugin-dev/SKILL.md` — document `lint`/`test`/`package`.

## Implementation Steps

1. **Composer** — `composer.json` template: PSR-4 autoload, dev deps above,
   `scripts.lint`/`scripts.test`. Run via `wp-env run cli composer …` so no host
   php is needed; the plugin still runs without Composer (Phase 2 fallback).
2. **PHPCS** — `phpcs.xml.dist` with the WordPress ruleset, `text_domain` =
   plugin textdomain, excludes (`vendor`, `node_modules`, `build`). `lint` runs
   PHPCS in the container.
3. **Plugin-local wp-env bootstrap** — `plugin-env-bootstrap.sh` writes
   `.wp-env.json` inside the plugin root (`./<slug>/`, per Validation: output
   location) with `"mappings": { "wp-content/plugins/<slug>": "." }` (the plugin
   dir itself) and the WP test suite, then `wp-env start`. zsh-safe; `bash -n`
   clean.
4. **PHPUnit smoke test** — `tests/test-activation.php`: assert the plugin loads,
   the bootstrap class exists, **a sub-namespaced feature class autoloads**,
   activation triggers no error, and one feature assertion (e.g. CPT registered
   when present). `phpunit.xml.dist` minimal. Run via `wp-env run tests-cli
   phpunit`.
5. **readme.txt** — template with the stable header filled from `wp-plugin.json`.
6. **Packaging (allowlist, Red-team #7 + #15)** — `plugin-package.sh`: `wp-env
   run cli composer install --no-dev` (when Composer used), `npm run build` when a
   block exists, then build the zip from an **allowlist**: `<slug>.php`,
   `uninstall.php`, `readme.txt`, `inc/`, `src/`, `languages/`,
   `blocks/*/build/`, `vendor/` (no-dev). **Force-include** block `build/` even
   though git-ignores it. A post-zip assertion **fails** if any file outside the
   allowlist or matching a secret pattern (`.env`, keys, `wp-plugin.json`) is
   present, and **fails** if a declared block lacks `build/block.json`. Output
   `dist/<slug>-<version>.zip`. Idempotent; zsh-safe; `bash -n` clean.

## Success Criteria

- [ ] `lint` runs PHPCS in-container and reports cleanly on generated code.
- [ ] `test` spins up the **plugin-local** wp-env, confirms the plugin is mounted
      and active, and the PHPUnit smoke test (incl. sub-namespaced autoload) is
      green.
- [ ] `package` yields `dist/<slug>-<version>.zip` that installs via wp-admin →
      Upload; the assertion **fails** the build if a non-allowlisted/secret file
      is present or a block `build/block.json` is missing.
- [ ] Missing tool → clear message + non-zero exit, no corruption.
- [ ] `bash -n` clean for `plugin-env-bootstrap.sh` and `plugin-package.sh`.

## Risk Assessment

- **Theme-bound bootstrap reuse was impossible** (Red-team #2) → dedicated
  `plugin-env-bootstrap.sh` with a real plugin mapping is a required deliverable,
  not a hedge.
- **Denylist zip leaking secrets** (Red-team #7) → allowlist + failing assertion.
- **Block `build/` dropped** (Red-team #15) → force-include + presence assertion.
- **Composer needs php** → run through `wp-env run cli composer`.
