# Code Review Checklist — Classic WordPress Theme

Generic checklist for reviewing a classic PHP theme generated or edited under
the `wp-classic` / `classic-acf` strategy. Remove items that do not apply to the
specific project.

Conventions adapted from [alessioarzenton/claude-code-wp-toolkit](https://github.com/alessioarzenton/claude-code-wp-toolkit) (GPL-3.0), rewritten for WP Pro Max (MIT).

## Naming and structure

- [ ] Template files use kebab-case (`front-page.php`, `parts/hero.php`).
- [ ] Functions use the theme prefix and `snake_case` (`<slug>_setup()`).
- [ ] PHP classes use `PascalCase`.
- [ ] Template partials live in `parts/` or a consistent folder.
- [ ] Root templates are the default; `templates/` is only used for custom page
      templates with a `Template Name:` header.

## Escaping and security

- [ ] All outputs escaped: `esc_html()`, `esc_attr()`, `esc_url()`, `wp_kses_post()`.
- [ ] No `echo` of user or DB data without escaping.
- [ ] Nonces verified in any form handling (`wp_verify_nonce`, `check_admin_referer`).
- [ ] Custom queries use `$wpdb->prepare()`.
- [ ] PHP files start with `defined( 'ABSPATH' ) || exit;`.

## PHP templates

- [ ] Header docblock documents any `$args` the partial accepts.
- [ ] Default values are set: `$title = isset( $args['title'] ) ? $args['title'] : '';`.
- [ ] Reusable parts are included with `get_template_part()`, not `include`/`require`.
- [ ] ACF blocks and macro components use a root `<section>` tag (excluding
      header/footer).

## Design tokens

- [ ] Colors come from CSS variables (`var(--color-*)`) — no hardcoded hex.
- [ ] Spacing/radius values are consistent with the design-token system.

## Accessibility (WCAG 2.2 AA)

- [ ] Semantic landmarks: `<header>`, `<nav aria-label="…">`, `<main>`, `<footer>`.
- [ ] Skip-to-content link is present.
- [ ] Images have meaningful `alt` text (empty `alt=""` for decorative images).
- [ ] Decorative SVGs use `aria-hidden="true" focusable="false"`.
- [ ] Visible focus ring is preserved (no `outline: none` without replacement).
- [ ] Color contrast is at least 4.5:1 for normal text, 3:1 for large text.
- [ ] Correct heading order and labelled form controls.

## CSS

- [ ] No `!important` without justification.
- [ ] Responsive behavior is defined (media queries or responsive classes).
- [ ] Hover/focus/active states are defined.

## Enqueues and assets

- [ ] Styles/scripts registered with `wp_enqueue_*`.
- [ ] Asset URLs use `get_theme_file_uri()` / `get_stylesheet_uri()`.
- [ ] Scripts load in the footer when possible (`true` for `$in_footer`).

## WordPress integration

- [ ] CPT/tax registration lives in `inc/post-types.php` (or split files), not
      inline in `functions.php`.
- [ ] ACF blocks are registered in `inc/acf-blocks.php`.
- [ ] ACF JSON load/save point points to the theme's `acf-json/` directory.
- [ ] `functions.php` requires all `inc/*.php` files.
- [ ] Text domain matches `project.textDomain` everywhere.

## Theme customization (Customizer — branding & colors)

- [ ] Color controls + emitter read the registry `cssVar` (the actual emitted
      `--color-<slug>`), not a re-guessed `--color-<slug>` template.
- [ ] Color sanitizer is a **function-color allowlist** (hex/rgb(a)/hsl(a)),
      applied on save AND re-applied on output — never bare `sanitize_hex_color`.
- [ ] Emitter escapes values for **CSS context** (not `esc_attr`) and emits a
      `:root` override only for mods ≠ default; attaches to `<slug>-main` (asserts
      it is registered, else `<slug>-style`).
- [ ] Footer logo stored as an **attachment ID** (`WP_Customize_Media_Control` +
      `absint`); rendered via the guarded `<slug>_the_footer_logo()` helper
      (defined in `convert`).
- [ ] Reset reverts colors **and** both logos; `customize_save_after` drops mods
      equal to default and GCs orphan `<slug>_color_*` mods (token rename).
- [ ] Branding lives only in theme_mods — no duplicate logo/brand-color on an ACF
      options page.
- [ ] All Customizer fns + mod keys namespaced with the theme slug; labels i18n'd.

## Git

- [ ] Commit messages follow Conventional Commits (`feat`, `fix`, `docs`, etc.).
- [ ] No sensitive files committed (`.env`, credentials, etc.).

## WPCS

- [ ] Tab indentation (WordPress standard).
- [ ] One space after keywords (`if`, `for`, `foreach`, etc.).
- [ ] Yoda conditions used where the project uses them.
- [ ] `phpcs` passes if configured.

## References

- Stack conventions: `../SKILL.md`
- Canonical reference: `../../../references/classic-acf.md`
