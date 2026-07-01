---
phase: 4
title: "Handoff & Verification"
status: complete
priority: P2
dependencies: [2, 3]
effort: "S-M"
---

# Phase 4: Handoff & Verification

## Overview

Make the feature discoverable to the site owner and prove it works. Add a per-strategy
"edit your logo & colors / reset" section to the handoff docs, then behaviorally verify
the `classic-acf` path end-to-end in wp-env (the only strategy with custom code) and
confirm idempotency.

## Requirements

- Functional: `wp-handoff` generates a client-facing customization section per strategy.
  Behavioral verification of the classic-acf customizer (register, emit, reset, footer
  logo) against a running wp-env. **Ship preserves customizer state** (F4): add
  `theme_mods_<slug>` migration to the `ship` stage + verify it survives deploy.
- Non-functional: verification uses the project's WP-CLI runner (binds to `*-cli-1`, not
  `*-tests-cli-1`); no host PHP assumed; degrade gracefully when wp-env absent — but the
  **escaping/sanitize correctness checks are a ship gate** (F6), not optional.

## Architecture

- **Handoff docs.** `wp-handoff` already emits a site handbook. Add a "Branding &
  Colors" section that branches by `strategy`:
  - classic-acf → Appearance → Customize → Branding & Colors (logos, colors, Reset).
  - block-fse → Site Editor → Styles (colors + Reset to defaults) + footer-logo control.
  - page-builder → Elementor Site Settings → Global Colors + Site Identity + footer logo.
- **Static (always, even without wp-env):**
  - Grep the registry `cssVar` list against the `:root` block `convert` emitted — every
    editable token's var MUST exist in the theme CSS (F1 phantom-var guard).
  - Grep `assets/css/main.css` for `:root` color vars → MUST be absent (F9 reset guard).
- **Cross-stage activation (F3):** after `convert` (before `scaffold`), activate + hit
  the front-end → no `undefined function <slug>_the_footer_logo()` fatal (guard works).
- **Verification (classic-acf, wp-env):**
  - `wp theme activate` → no PHP notices/fatals.
  - `wp eval` set a color mod (incl. an `rgba()` value, F2) → inline `:root` override
    appears with the correct `cssVar`; unset → disappears.
  - **Injection check (F6):** set a mod to `red} body{display:none}` / non-hex junk via
    `wp eval` (bypasses save sanitizer) → emitter output re-sanitizes/drops it; no CSS
    breakout in rendered HTML.
  - `wp eval` set `footer_logo` (attachment ID) → footer renders via
    `wp_get_attachment_image()`; bad/missing ID → graceful fallback.
  - **Reset = colors + logos:** clear color mods + `custom_logo` + `footer_logo` →
    token-default colors AND no custom logos.
  - **Idempotency (F10):** re-run `scaffold --force` → customizer files byte-identical;
    then mutate `designTokens` (rename a token) + re-run → orphaned `<slug>_color_*` mod
    is GC'd, no phantom override.
  - **Ship state (F4):** export `theme_mods_<slug>` → import on a second site → confirm
    logos+colors reproduce (the migration step works).
- **FSE/builder** verification: confirm the footer-logo control exists + renders + falls
  back (F5 — proves the customizer hook was actually authored, not just documented);
  native color editors are WP core (not re-tested).

## Related Code Files

- Modify: `skills/wp-handoff/SKILL.md` — per-strategy "Branding & Colors" section
  (classic Customizer; FSE Styles + the `/wp-admin/customize.php` path for the hidden
  footer-logo control; Elementor Site Settings).
- Modify: `skills/wp-ship/SKILL.md` (+ runbook) — add a `theme_mods_<slug>` export/import
  step so customizer state migrates on deploy (F4), and `footer_logo` attachment-ID remap
  after media reseed (or require full-DB-import when a footer logo is set, F7).
- Verify only (no source change): generated theme customizer files in a wp-env build.
- Add the WP-CLI verification recipe to
  `skills/wp-scaffold/references/theme-customization.md` (set/emit/reset/footer-logo,
  injection, idempotency+GC, ship-state snippets).

## Implementation Steps

1. Add the "Branding & Colors" section to `wp-handoff`, branched by strategy (incl. the
   FSE hidden-Customizer-menu path).
2. Add the `theme_mods_<slug>` migration + footer-logo ID remap to `wp-ship` (F4/F7).
3. Author the WP-CLI verification recipe (static cssVar/main.css greps, cross-stage
   activation, set/emit/reset, injection, idempotency+GC, ship-state) into
   `theme-customization.md`.
4. Run the recipe against a wp-env classic-acf build if available; capture pass/fail. The
   static greps + cross-stage activation + injection checks are **mandatory gates**; only
   the full wp-env behavioral run defers when wp-env is absent (flagged, not skipped).
5. Reconcile docs: handoff, scaffold, ship, and the three strategy references agree on key
   names, `cssVar` contract, and click-paths.

## Success Criteria

- [ ] `wp-handoff` emits a per-strategy Branding & Colors section (incl. FSE
      `/wp-admin/customize.php` path).
- [ ] `wp-ship` migrates `theme_mods_<slug>` + handles footer-logo ID on deploy; verified
      to reproduce branding on a second site.
- [ ] Static gates pass: every registry `cssVar` exists in the emitted `:root`; `main.css`
      has no `:root` color vars; convert-only activation does not fatal.
- [ ] Where wp-env available, behavioral recipe passes: activate clean; rgba mod →
      correct-`cssVar` override; injection mod is dropped (no CSS breakout); footer logo
      renders + falls back; reset reverts colors+logos; `scaffold --force` byte-identical;
      orphan mod GC'd on token rename.
- [ ] FSE footer-logo control proven to exist (hook authored, not doc-only).
- [ ] `claude plugin validate .` passes.

## Risk Assessment

- **wp-env not available.** Mitigation: static greps + cross-stage activation + injection
  checks are mandatory and wp-env-independent where possible; only full behavioral run
  defers, flagged not skipped.
- **Ship migration correctness (F4/F7).** theme_mods + attachment IDs must survive deploy.
  Mitigation: explicit export/import + ID remap, verified on a second site.
- **Docs drift.** Mitigation: step 5 reconcile; single key/`cssVar`/helper names from
  Phase 1 referenced everywhere.
- **Idempotency + GC (F10).** Mitigation: byte-identical check + token-rename GC check in
  the recipe.
