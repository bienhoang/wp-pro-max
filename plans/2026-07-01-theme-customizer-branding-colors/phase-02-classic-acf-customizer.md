---
phase: 2
title: "classic-acf Customizer"
status: complete
priority: P1
dependencies: [1]
effort: "M-L"
---

# Phase 2: classic-acf Customizer

## Overview

The real custom build. Author the WordPress Customizer UI for `classic-acf` themes:
**Logos** (header native + separate footer logo), **Colors** (one control per `:root`
color token from the Phase-1 registry — "deep"), and **Reset to defaults**, with live
preview and an inline-CSS emitter driven by `get_theme_mod`. Heavy authoring delegated
to **wp-theme-developer**; the skill/reference define exactly what it writes.

## Requirements

- Functional:
  - Customizer panel "Branding & Colors" with two sections.
  - Logos: header logo via native `custom-logo` (already wired); new `footer_logo` via
    **`WP_Customize_Media_Control`** storing an **attachment ID** (`sanitize_callback =
    absint`); live preview; footer renders via the guarded helper (fallback → site logo
    → title). <!-- Updated: Red Team Session 1 (F7) - Media control + attachment ID -->
  - Colors: auto-generate a color control per token in the registry; `default` =
    token `value`; key = `<slug>_color_<sanitize_key slug>`; the control edits the
    token's **`cssVar` from the registry** (NOT a `--color-<slug>` guess). postMessage
    live preview. <!-- Updated: Red Team Session 1 (F1) - cssVar from registry -->
  - Reset: custom button control = **full revert** — resets all color controls to
    defaults AND clears `custom_logo` + `footer_logo` in live preview; on save, default-
    valued overrides cleared → falls back to defaults + no-logo state.
  - Colors are **hex + rgb(a)/hsl(a)**: function-color allowlist sanitizer on save AND
    re-validated on output; pick a control that round-trips the format (alpha-capable
    where the value carries alpha). NOT bare `sanitize_hex_color`.
    <!-- Updated: Red Team Session 1 (F2) - hex-only superseded -->
  - Inline CSS: `wp_add_inline_style` emits `:root{ <cssVar>: <sanitized> }` only for
    tokens whose mod ≠ default; value escaped for **CSS context**; emitter **asserts the
    `<slug>-main` style handle is registered** before attaching (else attach to
    `<slug>-style`). <!-- Updated: Red Team Session 1 (F8) -->
- Non-functional: namespaced fns + mod keys; i18n all labels; escape every output in its
  correct context (CSS-context for emitter, `esc_url`/`esc_attr` for logo `<img>`);
  deterministic — re-running scaffold rewrites byte-identical file.

## Architecture

- **`inc/customizer.php`** (new; required from `functions.php` by scaffold wiring):
  - `<slug>_customize_register( $wp_customize )` on `customize_register`:
    - Panel `<slug>_branding`.
    - Section `<slug>_logos`: move core `custom_logo` into it; add `footer_logo` setting
      (`sanitize_callback = 'absint'`, `transport = postMessage`) +
      `WP_Customize_Media_Control` (`mime_type => 'image'`).
    - Section `<slug>_colors`: loop the registry; per token register setting (`default` =
      token `value`, `sanitize_callback` = the function-color allowlist, `transport` =
      `postMessage`) + color control. Group via `priority` from the (deterministic)
      `group`.
    - Section `<slug>_reset`: custom `WP_Customize_Control` subclass rendering the
      "Reset to defaults" button.
  - **Registry accessor** `<slug>_color_tokens()` returns the generated array
    (`cssVar`/`slug`/`label`/`default`/`group`). Single source for register + emit +
    reset. Scaffold also **GCs** `<slug>_color_*` mods not in this array (F10).
  - **Emitter** `<slug>_customizer_css()` on `wp_enqueue_scripts` (after main style):
    build `:root{}` only where `get_theme_mod( key, $default ) !== $default`, **re-running
    the function-color sanitizer on each value (drop on fail)** and CSS-context escaping;
    assert `<slug>-main` is registered then `wp_add_inline_style( '<slug>-main', $css )`.
  - **Save cleanup** on `customize_save_after`: `remove_theme_mod` for any color mod equal
    to its default — DB stays clean, reset is a true revert.
- **`assets/js/customizer-preview.js`** (`customize-preview` dep): bind each color setting
  → set the token's `cssVar` on `document.documentElement`; bind `footer_logo` (+
  `custom_logo`) → swap/clear the footer/header `<img>`.
- **`assets/js/customizer-controls.js`** (`customize-controls` dep): Reset button → for
  each color control `setting.set( setting.default )`; clear `custom_logo` + `footer_logo`.
  Logo settings are registered `transport = postMessage` with preview bindings so the
  revert previews live (core image/logo controls default to `refresh` — F14).
- **`footer.php`** render: calls the **guarded `<slug>_the_footer_logo()` helper that is
  defined in `convert` (Phase 1), not here** — Phase 2 only adds the control that sets the
  mod. Helper: `wp_get_attachment_image( $id, 'full' )` if `footer_logo` set (escaped),
  else `the_custom_logo()`, else site-title link. Stable wrapper id for preview JS.
  <!-- Updated: Red Team Session 1 (F3) - helper defined in convert, guarded -->
- **ACF single-source (F15):** colors/logos live ONLY as theme_mods. The classic
  reference must NOT also expose logo/brand-color fields on an ACF options page (audit
  `classic-acf.md` `get_field(...,'option')` usage). State theme_mods as the sole branding
  store so reset is complete.
- **Enqueue:** scaffold's `inc/enqueue.php` enqueues the two JS files on
  `customize_preview_init` / `customize_controls_enqueue_scripts`.

## Related Code Files

- Create (authored into generated theme by wp-theme-developer; defined here as the
  canonical template):
  - `inc/customizer.php`
  - `assets/js/customizer-preview.js`
  - `assets/js/customizer-controls.js`
  - custom reset control class (inline in `inc/customizer.php` or
    `inc/class-<slug>-reset-control.php`)
- Modify (generated theme): `functions.php` (require `inc/customizer.php`),
  `footer.php` (footer-logo render), `inc/enqueue.php` (customizer JS).
- Modify (plugin docs — the templates the agent follows):
  - `skills/theme-conversion/references/classic-acf.md` — add the customizer file to the
    file set, the footer-logo render in `footer.php`, and the `:root` defaults note.
  - `references/classic-acf.md` (canonical wp-classic reference) — add the customizer
    pattern (register/emit/reset) + footer-logo helper as canonical classic conventions.
  - `skills/wp-classic/references/` — add customizer to component-workflow + review
    checklist (CSS-context escaping, function-color sanitize + output re-validate,
    Media-control absint, namespacing, i18n).

## Implementation Steps

1. Update `references/classic-acf.md` (canonical): full customizer pattern — registry
   accessor (reads `cssVar`), `customize_register` (logos via Media control + colors +
   reset), function-color sanitizer, the inline-CSS emitter (output re-sanitize + CSS
   escape + handle assert), save-cleanup + orphan GC — real, escaped, namespaced PHP.
   Also place the **guarded `<slug>_the_footer_logo()` helper in the convert-stage
   section** (header/footer authoring), not scaffold.
2. Add `customizer-preview.js` + `customizer-controls.js` snippets (color→`cssVar` live,
   logo postMessage bindings, reset behavior).
3. Update `skills/theme-conversion/references/classic-acf.md` file set + `footer.php`
   guarded-helper render + build-order; cross-link the canonical reference.
4. Update `wp-scaffold/SKILL.md` classic path: generate `<slug>_color_tokens()` (with
   `cssVar`) deterministically; list customizer files in the writable set; agent
   acceptance.
5. **Audit `classic-acf.md` for ACF-options-stored branding** (logo/brand color); ensure
   none duplicates the theme_mod store (F15). Add customizer items to `wp-classic`
   component-workflow + code-review-checklist (CSS-context escape, function-color
   sanitize, Media-control absint, namespacing, i18n).
6. `bash -n`/`node --check` any scripts; `claude plugin validate .`.

## Success Criteria

- [ ] Canonical `classic-acf` reference shows a complete, escaped, namespaced
      `inc/customizer.php`: registry accessor (reads `cssVar`), logos (Media control) +
      colors (function-color sanitizer) + reset registration, emitter (output re-sanitize
      + CSS-context escape + handle assert), save-cleanup + orphan GC.
- [ ] Guarded `<slug>_the_footer_logo()` helper authored in the **convert** section;
      `footer.php` calls it; attachment-ID render via `wp_get_attachment_image()`.
- [ ] Preview + controls JS: color → `cssVar` live; logo postMessage bindings; reset
      reverts colors + both logos live.
- [ ] ACF options audited — no duplicate logo/brand-color store (F15). `wp-classic`
      checklist covers CSS-context escape + function-color sanitize + absint.
- [ ] `claude plugin validate .` passes.

## Risk Assessment

- **Reset semantics.** Native Customizer has no global reset. Mitigation: custom button +
  JS `setting.set(default)` + clear logos (postMessage) + `customize_save_after` cleanup.
- **Color sanitize (F2).** Tokens may be rgb(a)/hsl(a). Mitigation: function-color
  allowlist on save AND output; never `sanitize_hex_color` alone; CSS-context escape so a
  malformed DB-imported mod can't break out of `:root{}`.
- **cssVar mismatch (F1).** Editing must target the var the theme uses. Mitigation:
  control + emitter read `cssVar` from the registry; Phase 4 greps registry vs emitted
  `:root`.
- **Panel bloat for large token sets.** Mitigation: group + collapse; bounded to `:root`
  tokens (per design).
- **Preview targeting + main.css (F9).** Inline `:root` must win the cascade. Mitigation:
  emit after main stylesheet; `convert` keeps `main.css` `:root`-color-free so reset
  reverts to the token default, not a raw source color.
