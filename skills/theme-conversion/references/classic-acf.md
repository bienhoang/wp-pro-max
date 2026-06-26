# Backend: classic-acf (PHP templates + Advanced Custom Fields)

Use when `strategy = classic-acf`. A classic PHP theme: `header.php`/`footer.php`
+ `index.php`/`front-page.php` + page templates, reusable `template-parts/`
pulled with `get_template_part()`, and custom data via ACF field groups stored as
JSON in `acf-json/` (auto-sync). CSS variables come from `designTokens`.

## File set (theme root `wp-content/themes/<themeSlug>/`)

```
style.css                 # theme header + :root CSS variables from tokens
functions.php             # enqueue, theme supports, menus, CPT/tax, ACF json point
header.php  footer.php
index.php                 # fallback loop
front-page.php            # home (role=home)
page.php                  # generic page
templates/landing.php     # Template Name: Landing (role=landing)
single.php  archive.php   # blog/CPT (when contentModel has post types)
single-<cpt>.php archive-<cpt>.php   # per custom post type
template-parts/
  hero.php  card.php  cta.php  section.php   # from analysis.components[]
acf-json/                 # ACF field-group JSON (populated by scaffold stage)
assets/
  css/  js/  images/      # optimized assets copied from optimization.outputDir
screenshot.png
```

Map: each `analysis.pages[]` → a template above; record in `theme.templateMap`.
Each repeated `analysis.components[]` → a `template-parts/<kind>.php` rendered via
`get_template_part( 'template-parts/<kind>', null, $args )`.

## style.css (header + tokens)

Replace token values from `designTokens`. The header block is what WordPress
reads to register the theme.

```css
/*
Theme Name: Acme Corporate
Theme URI: https://example.com/
Author: WP Pro Max
Description: Converted from static HTML via WP Pro Max (classic-acf).
Version: 1.0.0
Requires at least: 6.4
Requires PHP: 8.2
Text Domain: acme
License: GPL-2.0-or-later
*/

:root {
  /* designTokens.colors[] -> --color-<slug> */
  --color-primary: #1a73e8;
  --color-secondary: #34a853;
  --color-text: #202124;
  --color-bg: #ffffff;
  /* designTokens.fonts[] -> --font-<role> */
  --font-heading: "Poppins", system-ui, sans-serif;
  --font-body: "Inter", system-ui, sans-serif;
  /* designTokens.spacing[] -> --space-<step> */
  --space-sm: 0.5rem;
  --space-md: 1rem;
  --space-lg: 2rem;
  /* designTokens.radius[] -> --radius-<name> */
  --radius-md: 8px;
}
```

The full compiled stylesheet (layout + component CSS adapted from source) goes in
`assets/css/main.css` and is enqueued; keep `style.css` to the header + `:root`.

## functions.php (minimal in convert; scaffold extends)

```php
<?php
/**
 * Theme bootstrap for Acme (classic-acf).
 *
 * @package Acme
 */

defined( 'ABSPATH' ) || exit;

if ( ! defined( 'ACME_VERSION' ) ) {
	define( 'ACME_VERSION', '1.0.0' );
}

/**
 * Theme supports + nav menu locations.
 */
function acme_setup() {
	load_theme_textdomain( 'acme', get_template_directory() . '/languages' );

	add_theme_support( 'title-tag' );
	add_theme_support( 'post-thumbnails' );
	add_theme_support( 'automatic-feed-links' );
	add_theme_support( 'html5', array( 'search-form', 'gallery', 'caption', 'style', 'script', 'navigation-widgets' ) );
	add_theme_support( 'custom-logo', array( 'height' => 64, 'width' => 200, 'flex-height' => true, 'flex-width' => true ) );
	add_theme_support( 'responsive-embeds' );

	register_nav_menus(
		array(
			'primary' => __( 'Primary Menu', 'acme' ),
			'footer'  => __( 'Footer Menu', 'acme' ),
		)
	);
}
add_action( 'after_setup_theme', 'acme_setup' );

/**
 * Enqueue front-end styles and scripts.
 */
function acme_enqueue_assets() {
	wp_enqueue_style( 'acme-style', get_stylesheet_uri(), array(), ACME_VERSION );
	wp_enqueue_style( 'acme-main', get_theme_file_uri( 'assets/css/main.css' ), array( 'acme-style' ), ACME_VERSION );
	wp_enqueue_script( 'acme-main', get_theme_file_uri( 'assets/js/main.js' ), array(), ACME_VERSION, true );
}
add_action( 'wp_enqueue_scripts', 'acme_enqueue_assets' );

/**
 * Tell ACF to load/save field groups from the theme's acf-json/ directory.
 * This keeps field definitions in version control (populated by the scaffold stage).
 */
add_filter( 'acf/settings/save_json', function () {
	return get_stylesheet_directory() . '/acf-json';
} );
add_filter( 'acf/settings/load_json', function ( $paths ) {
	$paths[] = get_stylesheet_directory() . '/acf-json';
	return $paths;
} );

// CPT / taxonomy registration is added by the scaffold stage (wp-scaffold) below this line.
```

## header.php

```php
<?php
/**
 * Site header.
 *
 * @package Acme
 */
?>
<!doctype html>
<html <?php language_attributes(); ?>>
<head>
	<meta charset="<?php bloginfo( 'charset' ); ?>">
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<?php wp_head(); ?>
</head>
<body <?php body_class(); ?>>
<?php wp_body_open(); ?>
<a class="skip-link screen-reader-text" href="#main"><?php esc_html_e( 'Skip to content', 'acme' ); ?></a>

<header class="site-header" role="banner">
	<div class="site-branding">
		<?php
		if ( has_custom_logo() ) {
			the_custom_logo();
		} else {
			printf(
				'<a class="site-title" href="%1$s" rel="home">%2$s</a>',
				esc_url( home_url( '/' ) ),
				esc_html( get_bloginfo( 'name' ) )
			);
		}
		?>
	</div>

	<nav class="primary-nav" aria-label="<?php esc_attr_e( 'Primary', 'acme' ); ?>">
		<?php
		wp_nav_menu(
			array(
				'theme_location' => 'primary',
				'container'      => false,
				'menu_class'     => 'menu',
				'fallback_cb'    => false,
				'depth'          => 2,
			)
		);
		?>
	</nav>
</header>

<main id="main" class="site-main">
```

## footer.php

```php
<?php
/**
 * Site footer.
 *
 * @package Acme
 */
?>
</main><!-- #main -->

<footer class="site-footer" role="contentinfo">
	<nav class="footer-nav" aria-label="<?php esc_attr_e( 'Footer', 'acme' ); ?>">
		<?php
		wp_nav_menu(
			array(
				'theme_location' => 'footer',
				'container'      => false,
				'menu_class'     => 'footer-menu',
				'fallback_cb'    => false,
				'depth'          => 1,
			)
		);
		?>
	</nav>
	<p class="copyright">
		<?php
		/* translators: %1$s: year, %2$s: site name. */
		printf( esc_html__( '© %1$s %2$s. All rights reserved.', 'acme' ), esc_html( gmdate( 'Y' ) ), esc_html( get_bloginfo( 'name' ) ) );
		?>
	</p>
</footer>

<?php wp_footer(); ?>
</body>
</html>
```

## front-page.php (role=home) — composes template parts

```php
<?php
/**
 * Front page. Sections come from analysis.pages[role=home].sections[].
 *
 * @package Acme
 */

get_header();

// Each section maps to a template part discovered in analysis.components[].
get_template_part( 'template-parts/hero', null, array(
	'title'    => get_bloginfo( 'name' ),
	'subtitle' => get_bloginfo( 'description' ),
) );

get_template_part( 'template-parts/section', 'features' );
get_template_part( 'template-parts/cta' );

get_footer();
```

## page.php (generic)

```php
<?php
/**
 * Generic page template.
 *
 * @package Acme
 */

get_header();

while ( have_posts() ) :
	the_post();
	?>
	<article id="post-<?php the_ID(); ?>" <?php post_class( 'page-content' ); ?>>
		<header class="entry-header">
			<h1 class="entry-title"><?php the_title(); ?></h1>
		</header>
		<div class="entry-content">
			<?php
			the_content();
			wp_link_pages();
			?>
		</div>
	</article>
	<?php
endwhile;

get_footer();
```

## templates/landing.php (role=landing — custom page template)

```php
<?php
/**
 * Template Name: Landing
 * Template Post Type: page
 *
 * @package Acme
 */

get_header();

while ( have_posts() ) :
	the_post();
	get_template_part( 'template-parts/hero', null, array( 'title' => get_the_title() ) );
	?>
	<div class="landing-body">
		<?php the_content(); ?>
	</div>
	<?php
	get_template_part( 'template-parts/cta' );
endwhile;

get_footer();
```

## index.php (required fallback loop)

```php
<?php
/**
 * Fallback loop.
 *
 * @package Acme
 */

get_header();

if ( have_posts() ) :
	while ( have_posts() ) :
		the_post();
		?>
		<article <?php post_class(); ?>>
			<h2 class="entry-title">
				<a href="<?php the_permalink(); ?>"><?php the_title(); ?></a>
			</h2>
			<div class="entry-summary"><?php the_excerpt(); ?></div>
		</article>
		<?php
	endwhile;
	the_posts_pagination();
else :
	?>
	<p><?php esc_html_e( 'Nothing found.', 'acme' ); ?></p>
	<?php
endif;

get_footer();
```

## template-parts/hero.php (accepts args from get_template_part 3rd arg)

```php
<?php
/**
 * Hero section. Reusable component from analysis.components[kind=hero].
 *
 * @package Acme
 *
 * @var array $args { @type string $title @type string $subtitle }
 */

$title    = isset( $args['title'] ) ? $args['title'] : get_the_title();
$subtitle = isset( $args['subtitle'] ) ? $args['subtitle'] : '';
// ACF example: an optional background image field on the page.
$bg = function_exists( 'get_field' ) ? get_field( 'hero_background' ) : '';
?>
<section class="hero"<?php echo $bg ? ' style="background-image:url(' . esc_url( $bg ) . ')"' : ''; ?>>
	<div class="hero__inner">
		<h1 class="hero__title"><?php echo esc_html( $title ); ?></h1>
		<?php if ( $subtitle ) : ?>
			<p class="hero__subtitle"><?php echo esc_html( $subtitle ); ?></p>
		<?php endif; ?>
	</div>
</section>
```

## template-parts/card.php

```php
<?php
/**
 * Card component (used in grids / feature lists).
 *
 * @package Acme
 *
 * @var array $args { @type string $title @type string $text @type string $url @type string $image }
 */

$title = isset( $args['title'] ) ? $args['title'] : '';
$text  = isset( $args['text'] ) ? $args['text'] : '';
$url   = isset( $args['url'] ) ? $args['url'] : '';
$image = isset( $args['image'] ) ? $args['image'] : '';
?>
<article class="card">
	<?php if ( $image ) : ?>
		<img class="card__image" src="<?php echo esc_url( $image ); ?>" alt="<?php echo esc_attr( $title ); ?>" loading="lazy">
	<?php endif; ?>
	<h3 class="card__title"><?php echo esc_html( $title ); ?></h3>
	<p class="card__text"><?php echo esc_html( $text ); ?></p>
	<?php if ( $url ) : ?>
		<a class="card__link" href="<?php echo esc_url( $url ); ?>"><?php esc_html_e( 'Read more', 'acme' ); ?></a>
	<?php endif; ?>
</article>
```

## template-parts/cta.php

```php
<?php
/**
 * Call-to-action band. Pulls copy from an ACF options/page field when present.
 *
 * @package Acme
 */

$heading = function_exists( 'get_field' ) ? get_field( 'cta_heading', 'option' ) : '';
$heading = $heading ? $heading : __( 'Ready to get started?', 'acme' );
$btn_url = function_exists( 'get_field' ) ? get_field( 'cta_button_url', 'option' ) : home_url( '/contact/' );
?>
<section class="cta">
	<h2 class="cta__heading"><?php echo esc_html( $heading ); ?></h2>
	<a class="cta__button" href="<?php echo esc_url( $btn_url ); ?>"><?php esc_html_e( 'Contact us', 'acme' ); ?></a>
</section>
```

## ACF field groups (acf-json/)

The `scaffold` stage writes field-group JSON here from `contentModel.fieldGroups`.
The convert stage only creates the empty `acf-json/` directory and wires the
load/save filters (above). Example shape the scaffold stage emits
(`acf-json/group_hero.json`):

```json
{
  "key": "group_hero",
  "title": "Hero",
  "fields": [
    { "key": "field_hero_background", "label": "Hero Background", "name": "hero_background", "type": "image", "return_format": "url" }
  ],
  "location": [[{ "param": "page_template", "operator": "==", "value": "templates/landing.php" }]],
  "active": true
}
```

## Build order

1. Create dirs + `style.css` header with `:root` tokens.
2. Write `functions.php` (supports, menus, enqueue, ACF json point).
3. `header.php`, `footer.php`, `index.php`.
4. Page templates per `analysis.pages[].role` → record template map.
5. `template-parts/*` per `analysis.components[]`.
6. Copy optimized assets from `optimization.outputDir` into `assets/`.
7. Hand CPT/tax/field-group wiring to the `scaffold` stage.
