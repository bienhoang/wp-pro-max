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

## Build order

1. `style.css` header + `theme.json` from `designTokens`.
2. `parts/header.html`, `parts/footer.html`.
3. `templates/index.html` (required) + per-role templates → record template map.
4. `patterns/*.php` per `analysis.components[]`.
5. Tiny `functions.php` (pattern category, text domain).
6. Hand block-bindings / meta registration to the `scaffold` stage.
