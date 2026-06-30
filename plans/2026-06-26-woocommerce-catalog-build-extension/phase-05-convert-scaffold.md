---
phase: 5
title: "Convert & Scaffold"
status: pending
effort: ""
---

# Phase 5: Convert & Scaffold

## Overview

Make the theme WooCommerce-aware per strategy: declare `add_theme_support`,
provide minimal Woo template overrides styled with the design tokens. Add a Woo
override section to each of the 3 theme-conversion backend references.

## Requirements

- Functional: `wp-scaffold` writes `add_theme_support('woocommerce')` (+ gallery
  supports) and minimal `woocommerce/` overrides when `commerce.enabled`.
  `theme-conversion` references document per-strategy override mechanics.
- Non-functional: render-correct + token-styled, not pixel-perfect (esp. FSE).
  Keep `functions.php` lean (use an `inc/woocommerce.php` include).

## Architecture

Per strategy:
- **classic-acf**: `inc/woocommerce.php` with `add_theme_support('woocommerce')`,
  `wc-product-gallery-zoom/lightbox/slider`; template overrides in theme
  `woocommerce/` (archive-product.php, content-product.php, single-product.php)
  wrapping Woo hooks in the theme's existing layout/markup.
- **block-fse**: declare support in `inc/woocommerce.php`; rely on Woo block
  templates; add block template parts under `templates/`/`parts/` for
  archive-product + single-product where tokens/theme.json need to drive styling.
- **page-builder (Elementor/Bricks)**: thin shell + note that builder Woo widgets
  render product loops; ensure `add_theme_support` present; template data seeded
  in Phase 6.

`add_image_size` already exists in `inc/image-sizes.php` — reuse for product
thumbnails; do not duplicate.

## Related Code Files

- Modify: `skills/wp-scaffold/SKILL.md` (new section "Commerce: WooCommerce theme
  support + template overrides (when commerce.enabled)"; `inc/woocommerce.php`
  example per strategy; `functions.php` require line).
- Modify: `skills/theme-conversion/references/classic-acf.md` — Woo override subsection.
- Modify: `skills/theme-conversion/references/block-fse.md` — Woo block-template subsection.
- Modify: `skills/theme-conversion/references/page-builder.md` — Woo widgets note.
- Modify: `skills/theme-conversion/SKILL.md` (route to the Woo subsection when `commerce.enabled`).
- Modify: `agents/wp-theme-developer.md` (acceptance: Woo templates render, no PHP notices).

## Implementation Steps

1. **(TEST FIRST)** Document the per-strategy assertion: scaffolding a
   `commerce.enabled` manifest MUST produce `inc/woocommerce.php` containing
   `add_theme_support( 'woocommerce' )` and (classic) a `woocommerce/` template
   dir. Add `php -l` to the verification list (best-effort; PHP may be absent —
   note as deferred like the repo's existing PHP-lint gap).
2. Add the scaffold commerce section with the 3 strategy branches.
3. Add Woo subsections to the 3 theme-conversion references + SKILL routing.
4. Update `wp-theme-developer` acceptance criteria.
5. Validate.

## Success Criteria

- [ ] Per-strategy assertion documented before edits.
- [ ] `commerce.enabled` → scaffold emits `inc/woocommerce.php` with
      `add_theme_support('woocommerce')`; classic adds `woocommerce/` overrides.
- [ ] All 3 theme-conversion references have a Woo override subsection (user kept
      full 3-strategy scope).
- [ ] PHP correctness verified by the Phase 7 **live render** (Docker present), not
      by `php -l` (php CLI is absent per repo memory). Run `php -l` opportunistically
      only if a php binary becomes available.
- [ ] `claude plugin validate .` passes.

## Risk Assessment

- Risk: FSE Woo block templates are broad → mitigation: SP1 targets render +
  token styling only; document non-goal of pixel-perfect FSE; live e2e (Phase 7)
  confirms each strategy renders 200.
- Risk: php CLI absent → no static lint → mitigation: the Phase 7 live e2e render
  (Docker available) is the real correctness gate for generated PHP; do NOT defer
  it. 3-strategy scope means e2e SHOULD exercise more than classic where feasible.
