---
phase: 3
title: "FSE & Page-Builder Native"
status: complete
priority: P2
dependencies: [1]
effort: "S-M"
---

# Phase 3: FSE & Page-Builder Native

## Overview

Wire the two features for `block-fse` and `page-builder` the strategy-native way:
colors + reset come from the backends' built-in editors (no custom UI); the only custom
addition is the **separate footer logo**, which neither backend gives natively. Mostly
reference/doc updates + a tiny render slot.

## Requirements

- Functional:
  - **block-fse:** colors/buttons/text/bg edited via native **Global Styles**; reset via
    native Styles → "Reset to defaults". Header logo = Site Logo block (already present).
    Add separate **footer logo** — this requires **authoring a real customizer file +
    `customize_register` hook** for the FSE theme (it has none), plus a dynamic render in
    `parts/footer.html` via a registered **image block-bindings source**.
  - **page-builder (Elementor):** colors via **Global Colors** (Site Settings); header
    logo via Site Identity/logo widget. Footer logo via **one chosen mechanism** (below),
    not an either/or.
- Non-functional: reuse the Phase-1 footer-logo key (attachment ID) + guarded helper
  (DRY); namespaced; i18n; deterministic; do NOT rebuild what native editors already do.

## Architecture

- **block-fse footer logo (F5/F11 — must author wiring, not just docs).** FSE has no
  `inc/` and a deliberately tiny `functions.php` (`block-fse.md:8-26,242-270`) — there is
  nowhere a `customize_register` lives today. So Phase 3 MUST author for the FSE theme:
  1. a customizer file (`inc/customizer.php` or a `functions.php` block) registering the
     `<slug>_footer_logo` Media control (attachment ID) + `add_action('customize_register')`,
     added to the FSE file set + build order;
  2. a registered **image block-bindings source** (NOT the text-meta example at
     `block-fse.md:272-290`) that resolves the mod to an image URL, bound on an
     `wp:image`/`wp:site-logo` attribute in `parts/footer.html` (call out FSE image-
     attribute binding support; if unsupported on target WP, fall back to a PHP-rendered
     footer pattern). <!-- Updated: Red Team Session 1 (F5/F11) -->
  3. **Document the block-theme reality:** WP hides the Customizer admin menu for block
     themes — handoff (Phase 4) must give the owner the `/wp-admin/customize.php` path.
- **Elementor footer logo (F12 — pick ONE).** Default: render the **guarded
  `<slug>_the_footer_logo()` helper (attachment ID) in the host theme's `footer.php`
  shell**, set by a Customizer Media control authored in the host theme (same as classic).
  If instead the footer is fully builder-managed (Elementor replaces `get_footer()`
  output), there is NO shared-mod path — then the footer logo is an Elementor logo widget
  only. The reference must state which applies and NOT promise "identical render / shared
  key" for the builder-managed case.
- **No color UI authored** for either backend — document where the owner edits colors
  (Site Editor → Styles; Elementor → Site Settings → Global Colors) and where reset lives.

## Related Code Files

- Modify: `skills/theme-conversion/references/block-fse.md` —
  - Note native Global Styles = the color editor + reset (point to it; don't rebuild).
  - **Add to the FSE file set + build order:** a customizer file + `customize_register`
    hook in `functions.php` (Media control, attachment ID); a registered image block-
    bindings source; the `parts/footer.html` bound render with Site-Logo fallback.
- Modify: `skills/theme-conversion/references/page-builder.md` —
  - Note Elementor Global Colors / Site Identity as the native color + header-logo UI.
  - Show the host-theme `footer.php` shell calling the guarded helper (default path), AND
    state the builder-managed-footer case where only an Elementor logo widget applies.
- Modify: `skills/wp-scaffold/SKILL.md` — fse/builder customization path: author the
  footer-logo wiring (FSE customizer file + bindings; builder host-theme control) +
  native-editor pointer; explicitly no custom color UI.
- Reference: `skills/wp-scaffold/references/theme-customization.md` (Phase 1) — fill the
  fse/builder rows of the file matrix with the authored footer-logo files.

## Implementation Steps

1. Update `block-fse.md`: native-color/reset note + **author** the FSE customizer file +
   `customize_register` hook (Media control) + image block-bindings source + bound
   `parts/footer.html` render + Site-Logo fallback. Add files to FSE file set/build order.
2. Update `page-builder.md`: native-color/header-logo note + host-theme `footer.php`
   guarded-helper render (default) + the builder-managed-footer caveat (widget-only).
3. Update `wp-scaffold/SKILL.md` fse/builder branch (author footer-logo wiring per
   strategy + native-editor pointer; no color UI).
4. `claude plugin validate .`.

## Success Criteria

- [ ] `block-fse.md` documents native Global Styles for colors/reset AND **authors** a
      working footer-logo path: customizer file + `customize_register` hook (Media
      control), image block-bindings source, bound `parts/footer.html` render, Site-Logo
      fallback — all added to the FSE file set/build order (not doc-only).
- [ ] `page-builder.md` documents Elementor Global Colors/Site Identity AND a single
      footer-logo mechanism (host-theme helper default; builder-managed caveat) — no
      "identical render" claim for the builder-managed case.
- [ ] `wp-scaffold/SKILL.md` fse/builder path authors footer-logo wiring + native-editor
      pointer (no duplicated color UI).
- [ ] Footer-logo key (attachment ID) consistent across strategies where a shared mod
      applies. `claude plugin validate .` passes.

## Risk Assessment

- **FSE has no customizer host (F5).** Mitigation: author the file + hook + add to file
  set/build order; document the hidden-menu `/wp-admin/customize.php` access in handoff.
- **FSE image binding may be unsupported (F11).** Mitigation: name the bindings source
  explicitly; fall back to a PHP-rendered footer pattern if image-attribute binding isn't
  available on the target WP version.
- **Builder-managed footer bypasses the shell (F12).** Mitigation: pick one mechanism per
  case; drop the shared-key/identical-render promise for the builder-managed footer.
- **Scope creep into rebuilding native editors.** Mitigation: explicit "no color UI for
  fse/builder" note; only footer logo + docs.
