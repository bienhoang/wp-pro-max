---
phase: 2
title: "Shared Helpers"
status: done
priority: P1
dependencies: [1]
---

# Phase 2: Shared Helpers

## Overview

Create the shared scripts that the three child skills will call. These are pure helpers: they operate on the optimized HTML copy and know nothing about the overall pipeline state.

## Requirements

- Functional: `scripts/html-section-lib.sh` parses, inserts, removes, and reorders HTML sections by CSS selector/section id.
- Functional: `scripts/html-preview.sh` opens a given HTML file in the default browser on macOS (`open`) and falls back gracefully on Linux (`xdg-open`) / Windows (`start`).
- Functional: `scripts/pre-qa-a11y.mjs` performs a static HTML a11y scan (alt text, heading order, landmarks, form labels, contrast notes) without requiring a browser.
- Functional: `scripts/pre-qa-responsive.mjs` uses Playwright to render a page at 375/768/1280 and detect overflow/horizontal scroll.
- Non-functional: all scripts are `bash -n` / `node --check` clean, zsh-safe when sourced, and idempotent on re-run.

## Architecture

```text
scripts/
  html-section-lib.sh      # section_* helper functions
  html-preview.sh          # preview <file>
  pre-qa-a11y.mjs          # static WCAG-ish scan
  pre-qa-responsive.mjs    # Playwright viewport rendering
```

### `html-section-lib.sh`

Functions (sourced, no top-level `set -e`):

```bash
section_find() {   # <html-file> <selector>  -> prints matched outer HTML
section_replace() { # <html-file> <selector> <new-html-file>
section_insert_before() { # <html-file> <selector> <new-html-file>
section_insert_after() {  # <html-file> <selector> <new-html-file>
section_remove() {  # <html-file> <selector>
section_reorder() { # <html-file> <ordered-selectors-file>
section_backup() {  # <html-file> <backup-dir>
```

Implementation note: use `node` + `cheerio` (single lightweight dependency) or pure `sed`/regex only if the selector is a simple `id`. Prefer cheerio for reliability. The helper script must install cheerio on first use (`npm list cheerio >/dev/null 2>&1 || npm install cheerio --no-save` from the target project root) so the user does not need to pre-install.

### `html-preview.sh`

```bash
bash scripts/html-preview.sh <path-to-html>
```

Uses `open` on macOS, `xdg-open` on Linux, `start` on Windows. Errors clearly if the file does not exist.

### `pre-qa-a11y.mjs`

Static parser-based scan (no browser):

- Parse HTML with `node-html-parser` or cheerio.
- Check: every `<img>` has `alt` or `role="presentation"`; exactly one `<h1>`; heading levels never skip; `<main>` exists; `<nav>` has `aria-label`; form controls have labels.
- Contrast: read computed style if available, otherwise flag inline `color`/`background-color` pairs that look risky and defer to manual review.
- Output JSON: `{ passed, violations[], byRule{} }`.

### `pre-qa-responsive.mjs`

Playwright-based:

- `npm i -D playwright` if missing; `npx playwright install chromium` on first run.
- Render page at viewports `[{w:375,h:812}, {w:768,h:1024}, {w:1280,h:800}]`.
- Detect `window.innerWidth < document.documentElement.scrollWidth` (horizontal overflow) and any `console.error`.
- Output JSON: `{ passed, viewports: [{width,height,overflow,consoleErrors}] }`.

## Related Code Files

- Create: `scripts/html-section-lib.sh`
- Create: `scripts/html-preview.sh`
- Create: `scripts/pre-qa-a11y.mjs`
- Create: `scripts/pre-qa-responsive.mjs`
- Create: `plans/2026-06-27-site-editor-command/fixtures/sample-section.html` (for replace/insert tests)
- Create: `plans/2026-06-27-site-editor-command/fixtures/sample-invalid.html` (for a11y tests)

## Implementation Steps

1. **TDD — create fixtures and a test script.** Write `plans/.../fixtures/test-shared-helpers.sh` that:
   - syntax-checks all new shell scripts (`bash -n`).
   - syntax-checks all new Node scripts (`node --check`).
   - runs `section_find` against a sample page and expects to extract the hero section.
   - runs `section_replace` and asserts the new section appears and the old one is gone.
   - runs `pre-qa-a11y.mjs` against `sample-invalid.html` and expects violations.
2. Run the test script; expect failures because helpers do not exist yet.
3. Implement `html-section-lib.sh` using a small Node helper (`scripts/html-section-cli.mjs`) or cheerio sourced functions.
4. Implement `html-preview.sh`.
5. Implement `pre-qa-a11y.mjs`.
6. Implement `pre-qa-responsive.mjs`.
7. Re-run tests until green.

## Test-First Structure

```bash
bash -n scripts/html-section-lib.sh
bash -n scripts/html-preview.sh
node --check scripts/pre-qa-a11y.mjs
node --check scripts/pre-qa-responsive.mjs

# Behavioral tests (examples)
bash scripts/html-section-lib.sh find examples/sample-site/index.html "section.hero"
bash scripts/html-preview.sh examples/sample-site/index.html  # opens browser, verify manually
node scripts/pre-qa-a11y.mjs examples/sample-site/index.html
node scripts/pre-qa-responsive.mjs examples/sample-site/index.html
```

## Success Criteria

- [ ] All four scripts exist and pass syntax checks.
- [ ] `section_find/replace/insert/remove/reorder` work against `examples/sample-site` HTML.
- [ ] `html-preview.sh` opens the optimized copy in the default browser without error.
- [ ] `pre-qa-a11y.mjs` reports violations for a deliberately broken fixture and passes for a clean fixture.
- [ ] `pre-qa-responsive.mjs` runs at all three viewports and reports overflow status.

## Risk Assessment

- **Risk:** cheerio/Playwright dependency not installed.  
  **Mitigation:** Add an install-on-demand snippet in each script; do not require the user to pre-install. For Playwright, also install Chromium via `npx playwright install chromium` on first `--thorough` run.
- **Risk:** `html-section-lib.sh` sourced functions leak shell options.  
  **Mitigation:** Follow `manifest-lib.sh` sourcing guard pattern; no top-level `set -euo pipefail`.
