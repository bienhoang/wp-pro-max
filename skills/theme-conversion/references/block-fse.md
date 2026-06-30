# Backend: block-fse (theme.json + block templates & patterns)

Use when `strategy = block-fse`. A Full Site Editing block theme: a `theme.json`
(version 3) generated from `designTokens`, HTML block templates in `templates/`,
template parts in `parts/`, and reusable block patterns in `patterns/`. No PHP
loop files — WordPress renders block markup directly.

## File set (theme root `wp-content/themes/<themeSlug>/`)

```
style.css                 # theme header ONLY (block themes style via theme.json)
theme.json                # version 3 — settings + styles from designTokens
functions.php             # tiny: enqueue editor assets, register patterns dir, block bindings
templates/
  index.html              # required fallback
  front-page.html         # role=home
  page.html               # role=page
  page-landing.html       # role=landing (custom template, declared in theme.json)
  single.html  archive.html
parts/
  header.html  footer.html
patterns/
  hero.php  features.php  cta.php   # PHP-registered patterns (header comment metadata)
assets/                   # fonts/images referenced by theme.json + patterns
screenshot.png
```

Map: each `analysis.pages[]` → a `templates/*.html`; record in `theme.templateMap`.
Each `analysis.components[]` → a pattern in `patterns/` and/or a part in `parts/`.

## style.css (header only)

```css
/*
Theme Name: Acme FSE
Author: WP Pro Max
Description: Block (FSE) theme converted from static HTML via WP Pro Max.
Version: 1.0.0
Requires at least: 6.5
Requires PHP: 8.2
Text Domain: acme
License: GPL-2.0-or-later
*/
```

## theme.json (version 3, generated from designTokens)

- `designTokens.colors[]` → `settings.color.palette` (`{slug,color,name}`).
- `designTokens.fonts[]` → `settings.typography.fontFamilies` (+ `fontFace` for self-hosted).
- `designTokens.spacing[]` → `settings.spacing.spacingSizes`.
- `designTokens.breakpoints` / `layout` → `settings.layout.contentSize/wideSize`.
- `designTokens.radius[]` → applied in `styles` / element styles.
- Custom page templates listed under `customTemplates`; parts under `templateParts`.

```json
{
  "$schema": "https://schemas.wp.org/trunk/theme.json",
  "version": 3,
  "settings": {
    "appearanceTools": true,
    "layout": { "contentSize": "768px", "wideSize": "1200px" },
    "color": {
      "palette": [
        { "slug": "primary", "color": "#1a73e8", "name": "Primary" },
        { "slug": "secondary", "color": "#34a853", "name": "Secondary" },
        { "slug": "foreground", "color": "#202124", "name": "Foreground" },
        { "slug": "background", "color": "#ffffff", "name": "Background" }
      ],
      "custom": false,
      "defaultPalette": false
    },
    "typography": {
      "fluid": true,
      "fontFamilies": [
        {
          "slug": "heading",
          "name": "Poppins",
          "fontFamily": "\"Poppins\", system-ui, sans-serif",
          "fontFace": [
            { "fontFamily": "Poppins", "fontWeight": "400 700", "fontStyle": "normal", "src": ["file:./assets/fonts/poppins.woff2"] }
          ]
        },
        {
          "slug": "body",
          "name": "Inter",
          "fontFamily": "\"Inter\", system-ui, sans-serif"
        }
      ],
      "fontSizes": [
        { "slug": "small", "size": "0.875rem", "name": "Small" },
        { "slug": "medium", "size": "1rem", "name": "Medium" },
        { "slug": "large", "size": "1.5rem", "name": "Large" },
        { "slug": "x-large", "size": "2.25rem", "name": "Extra Large" }
      ]
    },
    "spacing": {
      "units": ["px", "em", "rem", "vh", "vw", "%"],
      "spacingSizes": [
        { "slug": "30", "size": "0.5rem", "name": "Small" },
        { "slug": "50", "size": "1rem", "name": "Medium" },
        { "slug": "70", "size": "2rem", "name": "Large" }
      ]
    }
  },
  "styles": {
    "color": { "background": "var(--wp--preset--color--background)", "text": "var(--wp--preset--color--foreground)" },
    "typography": { "fontFamily": "var(--wp--preset--font-family--body)", "lineHeight": "1.6" },
    "elements": {
      "button": {
        "color": { "background": "var(--wp--preset--color--primary)", "text": "#ffffff" },
        "border": { "radius": "8px" }
      },
      "h1": { "typography": { "fontFamily": "var(--wp--preset--font-family--heading)", "fontSize": "var(--wp--preset--font-size--x-large)" } },
      "link": { "color": { "text": "var(--wp--preset--color--primary)" } }
    }
  },
  "templateParts": [
    { "name": "header", "title": "Header", "area": "header" },
    { "name": "footer", "title": "Footer", "area": "footer" }
  ],
  "customTemplates": [
    { "name": "page-landing", "title": "Landing", "postTypes": ["page"] }
  ]
}
```

## parts/header.html

```html
<!-- wp:group {"tagName":"header","className":"site-header","layout":{"type":"flex","justifyContent":"space-between"}} -->
<header class="wp-block-group site-header">
	<!-- wp:site-logo {"width":160} /-->
	<!-- wp:navigation {"layout":{"type":"flex","orientation":"horizontal"}} /-->
</header>
<!-- /wp:group -->
```

## parts/footer.html

```html
<!-- wp:group {"tagName":"footer","className":"site-footer","layout":{"type":"constrained"}} -->
<footer class="wp-block-group site-footer">
	<!-- wp:paragraph {"align":"center"} -->
	<p class="has-text-align-center">© <!-- wp:post-date /--> Acme. All rights reserved.</p>
	<!-- /wp:paragraph -->
</footer>
<!-- /wp:group -->
```

## templates/index.html (required fallback)

```html
<!-- wp:template-part {"slug":"header","tagName":"header"} /-->

<!-- wp:group {"tagName":"main","layout":{"type":"constrained"}} -->
<main class="wp-block-group">
	<!-- wp:query {"queryId":0,"query":{"perPage":10,"inherit":true}} -->
	<div class="wp-block-query">
		<!-- wp:post-template -->
			<!-- wp:post-title {"isLink":true,"level":2} /-->
			<!-- wp:post-excerpt /-->
		<!-- /wp:post-template -->
		<!-- wp:query-pagination -->
			<!-- wp:query-pagination-previous /-->
			<!-- wp:query-pagination-numbers /-->
			<!-- wp:query-pagination-next /-->
		<!-- /wp:query-pagination -->
	</div>
	<!-- /wp:query -->
</main>
<!-- /wp:group -->

<!-- wp:template-part {"slug":"footer","tagName":"footer"} /-->
```

## templates/front-page.html (role=home — composes patterns)

```html
<!-- wp:template-part {"slug":"header","tagName":"header"} /-->

<!-- wp:group {"tagName":"main","layout":{"type":"constrained"}} -->
<main class="wp-block-group">
	<!-- wp:pattern {"slug":"acme/hero"} /-->
	<!-- wp:pattern {"slug":"acme/features"} /-->
	<!-- wp:pattern {"slug":"acme/cta"} /-->
</main>
<!-- /wp:group -->

<!-- wp:template-part {"slug":"footer","tagName":"footer"} /-->
```

## templates/page.html (role=page)

```html
<!-- wp:template-part {"slug":"header","tagName":"header"} /-->

<!-- wp:group {"tagName":"main","layout":{"type":"constrained"}} -->
<main class="wp-block-group">
	<!-- wp:post-title {"level":1} /-->
	<!-- wp:post-content {"layout":{"type":"constrained"}} /-->
</main>
<!-- /wp:group -->

<!-- wp:template-part {"slug":"footer","tagName":"footer"} /-->
```

## patterns/hero.php (PHP-registered pattern — header comment is the metadata)

```php
<?php
/**
 * Title: Hero
 * Slug: acme/hero
 * Categories: featured, banner
 * Description: Full-width hero with heading, subtext and CTA.
 *
 * @package Acme
 */
?>
<!-- wp:cover {"dimRatio":40,"minHeight":480,"align":"full"} -->
<div class="wp-block-cover alignfull" style="min-height:480px">
	<span aria-hidden="true" class="wp-block-cover__background has-background-dim-40 has-background-dim"></span>
	<div class="wp-block-cover__inner-container">
		<!-- wp:heading {"level":1,"textAlign":"center"} -->
		<h1 class="wp-block-heading has-text-align-center"><?php echo esc_html__( 'Build faster with Acme', 'acme' ); ?></h1>
		<!-- /wp:heading -->
		<!-- wp:paragraph {"align":"center"} -->
		<p class="has-text-align-center"><?php echo esc_html__( 'Everything you need to launch.', 'acme' ); ?></p>
		<!-- /wp:paragraph -->
		<!-- wp:buttons {"layout":{"type":"flex","justifyContent":"center"}} -->
		<div class="wp-block-buttons">
			<!-- wp:button -->
			<div class="wp-block-button"><a class="wp-block-button__link wp-element-button" href="#"><?php echo esc_html__( 'Get started', 'acme' ); ?></a></div>
			<!-- /wp:button -->
		</div>
		<!-- /wp:buttons -->
	</div>
</div>
<!-- /wp:cover -->
```

## functions.php (tiny for block themes)

```php
<?php
/**
 * Block theme bootstrap. theme.json handles styling; this wires patterns + bindings.
 *
 * @package Acme
 */

defined( 'ABSPATH' ) || exit;

function acme_setup() {
	load_theme_textdomain( 'acme', get_template_directory() . '/languages' );
	add_theme_support( 'post-thumbnails' );
	add_theme_support( 'editor-styles' );
}
add_action( 'after_setup_theme', 'acme_setup' );

// Register a pattern category so converted patterns group cleanly in the inserter.
function acme_register_pattern_categories() {
	register_block_pattern_category( 'acme', array( 'label' => __( 'Acme', 'acme' ) ) );
}
add_action( 'init', 'acme_register_pattern_categories' );

// Patterns in patterns/*.php are auto-registered by core from their header comments.
// Block bindings (dynamic field output, the FSE analog of ACF) are registered by the scaffold stage:
//   register_meta(...) + register_block_bindings_source('acme/field', ...).
```

### Block bindings (FSE analog of ACF — added by scaffold)

```php
register_block_bindings_source( 'acme/field', array(
	'label'              => __( 'Acme Field', 'acme' ),
	'get_value_callback' => function ( array $source_args, $block ) {
		$post_id = get_the_ID();
		return esc_html( get_post_meta( $post_id, $source_args['key'], true ) );
	},
) );
```

Bound in template HTML:

```html
<!-- wp:paragraph {"metadata":{"bindings":{"content":{"source":"acme/field","args":{"key":"subtitle"}}}}} -->
<p></p>
<!-- /wp:paragraph -->
```

## Theme customization (colors native, footer logo authored)

End-user branding for FSE. Cross-strategy contract:
`skills/wp-scaffold/references/theme-customization.md`.

- **Colors + reset = native Global Styles.** The owner edits colors in
  Site Editor → Styles, and resets via Styles → "Reset to defaults". Do **not**
  author a custom color UI — `theme.json` defaults are the source of truth.
- **Header logo = Site Logo block** (already in `parts/header.html`).
- **Footer logo = authored** (FSE has no native separate-footer-logo). FSE has no
  `inc/` and a deliberately tiny `functions.php`, so scaffold MUST author a real
  Customizer hook + an image block-bindings source — not just docs:

```php
// functions.php (scaffold appends) — footer-logo Customizer control.
function acme_customize_register_footer_logo( $wp_customize ) {
	$wp_customize->add_setting( 'acme_footer_logo', array(
		'default'           => 0,
		'sanitize_callback' => 'absint',
	) );
	$wp_customize->add_control( new WP_Customize_Media_Control( $wp_customize, 'acme_footer_logo', array(
		'label'     => __( 'Footer Logo', 'acme' ),
		'section'   => 'title_tagline', // Site Identity
		'mime_type' => 'image',
	) ) );
}
add_action( 'customize_register', 'acme_customize_register_footer_logo' );

// Image block-bindings source: resolves the mod → image URL for binding.
// Falls back to the site logo so the bound <img> is never empty when a logo
// exists (block bindings substitute an attribute; they cannot remove the block).
function acme_register_footer_logo_binding() {
	register_block_bindings_source( 'acme/footer-logo', array(
		'label'              => __( 'Footer Logo', 'acme' ),
		'get_value_callback' => function () {
			$id = absint( get_theme_mod( 'acme_footer_logo', 0 ) );
			if ( ! $id ) {
				$id = absint( get_theme_mod( 'custom_logo', 0 ) ); // fall back to site logo
			}
			return $id ? esc_url( wp_get_attachment_image_url( $id, 'full' ) ) : '';
		},
	) );
}
add_action( 'init', 'acme_register_footer_logo_binding' );
```

Bound on the image `url` attribute in `parts/footer.html` (WP 6.7+ supports
binding image attributes). The binding already resolves footer-logo → site-logo,
so use a **single** bound image (do NOT also add a `wp:site-logo` block — that
double-renders):

```html
<!-- wp:image {"metadata":{"bindings":{"url":{"source":"acme/footer-logo"}}},"className":"footer-logo"} -->
<figure class="wp-block-image footer-logo"><img src="" alt=""/></figure>
<!-- /wp:image -->
```

> **Preferred default for FSE — PHP-rendered footer pattern.** Because a bound
> `wp:image` still renders an empty `<img src="">` when the site has *no* logo at
> all (and to avoid relying on WP 6.7 image-attribute binding), the robust default
> is a registered **footer pattern** (`patterns/footer.php`) whose markup calls
> the guarded `acme_the_footer_logo()` helper (defined in `convert`), referenced
> from `parts/footer.html`. Use the bound `wp:image` above only when the target WP
> supports image-attribute binding and a logo is guaranteed set.
>
> **Block-theme reality:** WP hides the Customizer admin menu for block themes.
> Handoff (Phase 4) gives the owner the direct path `/wp-admin/customize.php` to
> reach the footer-logo control.

Add to the **file set**: `inc/customizer.php` (or the `functions.php` block above)
+ the bound `parts/footer.html`.

## Build order

1. `style.css` header + `theme.json` from `designTokens`.
2. `parts/header.html`, `parts/footer.html` (footer-logo bound `wp:image` +
   Site-Logo fallback).
3. `templates/index.html` (required) + per-role templates → record template map.
4. `patterns/*.php` per `analysis.components[]`.
5. Tiny `functions.php` (pattern category, text domain). **Scaffold** appends the
   footer-logo `customize_register` hook + image block-bindings source.
6. Hand block-bindings / meta registration to the `scaffold` stage.
