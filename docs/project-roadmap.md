# Project Roadmap

**Updated:** 2026-06-29 · **Version:** 0.2.0

## Status — v0.2 (in progress)

v0.1 pipeline is complete. v0.2 adds the optional site-editor command and child
skills that operate on the optimized HTML copy before theme conversion.

| Phase | Scope | Status |
|-------|-------|--------|
| 01 Foundation | plugin/marketplace manifests, manifest schema, manifest-lib.sh, contract docs | ✅ done |
| 02 Intake & analysis | html-analysis, html-optimization, content-modeling, design-tokens, extract-tokens.mjs | ✅ done |
| 03 Convert & scaffold | theme-conversion (3 backends), plugin-selection, wp-scaffold, wp-env-setup, wp-theme-developer, wp-env-bootstrap.sh | ✅ done |
| 04 Data seeding | content-seeding, plugin-data-seeding, wp-data-engineer, seed-helpers.sh | ✅ done |
| 05 Quality gates | wp-qa, wp-seo, wp-security, visual-diff.mjs | ✅ done |
| 06 Ship | wp-ship (+3 runbooks), wp-deployer, migrate-urls.sh | ✅ done |
| 07 Orchestration & docs | build/status/env commands, README, docs, sample site | ✅ done |
| 08 i18n & handoff | wp-i18n (vi/en/ja), wp-handoff | ✅ done |
| 09 Plugin builder | wp-plugin-dev, wp-plugin-developer, plugin-scaffold.sh, plugin-env-bootstrap.sh, plugin-package.sh, wp-plugin.schema.json | ✅ done |
| 10 Site editor | `/wp-pro-max:site-editor`, section-redesign, content-enrichment, pre-conversion-qa | ✅ done |
| 11 Classic ACF strategy | `wp-classic` skill + `references/classic-acf.md`, wired into `theme-conversion` and `wp-scaffold` | ✅ done |
| 12 Accessibility skill port | `skills/accessibility/` + references, wired into `html-optimization`, `wp-qa`, and `wp-handoff`; license attribution in `LICENSE` | ✅ done |

## Verified

- `claude plugin validate .` passes.
- All shell scripts `bash -n` clean; node scripts `node --check` clean.
- `extract-tokens.mjs` extracts named colors/fonts/spacing from real CSS.
- `manifest-lib.sh` + `seed-helpers.sh` source cleanly and run in **both bash and
  zsh**; idempotent helpers exercised with a mocked WP-CLI.
- New site-editor scripts pass fixture-level TDD and an end-to-end integration
  test on `examples/sample-site`.

## Next (v0.2 candidates)

- **Live e2e run**: execute the full pipeline against `examples/sample-site` via
  wp-env in this environment (Docker is present; host `php` is absent, so PHP
  linting and containerized verification are done inside wp-env).
- **`acf-cli` availability**: confirm/pin an ACF CLI source for field-group sync
  in plugin-selection (open question from Phase 04).
- **Playwright bundling**: smoother first-run for `visual-diff.mjs`
  (auto-install chromium).
- **More example sites** per strategy (FSE, page-builder) for regression.
- **CI**: shellcheck + node --check + plugin validate on push.
- **Fuller PHPUnit fixtures** for generated plugins.

## Open questions

- Default deploy target preference (ssh-wpcli vs ai1wm) — currently ssh-wpcli.
- Should the orchestrator auto-pick strategy or always confirm with the user?
