# Classic ACF Strategy Reference

Use when `strategy = classic-acf`. A classic PHP theme for WordPress 7.x:
`header.php`/`footer.php` + root templates + reusable `parts/` pulled with
`get_template_part()`, custom data via ACF Pro field groups stored as JSON in
`acf-json/` (auto-sync). CSS variables come from `designTokens`.

Conventions adapted from [alessioarzenton/claude-code-wp-toolkit](https://github.com/alessioarzenton/claude-code-wp-toolkit) (GPL-3.0), rewritten for WP Pro Max (MIT).

## Stack target

- **WordPress** 7.x
- **PHP** 8.2+
- **Runtime** `@wordpress/env` Docker WordPress (`wp-content/themes/<themeSlug>/`)
- **Custom fields** ACF Pro (assumed for this strategy)
- **Theme** Classic PHP theme — no Blade, Acorn, Sage, or full-site editing

## Theme anatomy

```
wp-content/themes/<themeSlug>/
├── style.css                 # theme header + :root CSS variables from tokens
├── functions.php             # setup, supports, menus, require inc/*
├── header.php  footer.php    index.php
├── front-page.php  page.php  single.php  archive.php
├── single-<cpt>.php  archive-<cpt>.php
├── templates/                # optional custom page templates
│   └── landing.php
├── parts/                    # reusable partials
│   ├── hero.php  card.php  cta.php
├── inc/                      # registration + wiring includes
│   ├── post-types.php        # CPTs + taxonomies
│   ├── acf-blocks.php        # acf_register_block_type()
│   ├── enqueue.php           # wp_enqueue_* assets
│   └── helpers.php           # theme helper functions
├── acf-json/                 # ACF field-group JSON (populated by scaffold stage)
├── assets/{css,js,images}    # optimized assets
└── screenshot.png
```

**Default template location is the theme root.** Use `templates/` only for
custom page templates that need a `Template Name:` header. Every
`analysis.pages[].path` maps to a root template; record the mapping in
`theme.templateMap`.

## Naming conventions

| Type | Convention | Example |
|------|------------|---------|
| Template / part files | kebab-case | `front-page.php`, `parts/hero.php` |
| PHP functions | `snake_case` with theme prefix | `<slug>_setup()`, `<slug>_enqueue_assets()` |
| PHP classes | `PascalCase` | `Acme_Hero_Block` |
| Constants | `UPPER_SNAKE_CASE` | `<SLUG>_VERSION` |
| Text domain | from `project.textDomain` | `acme` |

## Code style

- **PHP**: WordPress Coding Standards — tabs, one space inside parentheses, Yoda
  conditions where the project uses them.
- **JS/CSS**: Prettier (if configured).
- Escape on output: `esc_html()`, `esc_attr()`, `esc_url()`, `wp_kses_post()`.
- Start every PHP file with `defined( 'ABSPATH' ) || exit;`.
- Use `get_theme_file_uri()` / `get_theme_file_path()` for assets.
- Wrap user-facing strings in `__()` / `esc_html__()` / `_e()` with the project
  text domain.

## Template pattern

Use `get_template_part()` with the third `$args` parameter for data passing:

```php
get_template_part( 'parts/hero', null, array(
    'title'    => get_the_title(),
    'subtitle' => get_bloginfo( 'description' ),
) );
```

In the partial:

```php
<?php
/**
 * Hero part.
 *
 * @package Acme
 *
 * @var array $args { @type string $title @type string $subtitle }
 */
$title    = isset( $args['title'] ) ? $args['title'] : '';
$subtitle = isset( $args['subtitle'] ) ? $args['subtitle'] : '';
?>
<section class="hero">
    <h1 class="hero__title"><?php echo esc_html( $title ); ?></h1>
    <?php if ( $subtitle ) : ?>
        <p class="hero__subtitle"><?php echo esc_html( $subtitle ); ?></p>
    <?php endif; ?>
</section>
```

## CPT / taxonomy registration

Create `inc/post-types.php` (and optionally `inc/taxonomies.php`) and require
from `functions.php`:

```php
<?php
/**
 * Custom post types + taxonomies.
 *
 * @package Acme
 */
defined( 'ABSPATH' ) || exit;

function acme_register_post_types() {
    register_post_type(
        'event',
        array(
            'labels'       => array(
                'name'          => __( 'Events', 'acme' ),
                'singular_name' => __( 'Event', 'acme' ),
                'add_new_item'  => __( 'Add New Event', 'acme' ),
            ),
            'public'       => true,
            'has_archive'  => true,
            'show_in_rest' => true,
            'menu_icon'    => 'dashicons-calendar-alt',
            'supports'     => array( 'title', 'editor', 'thumbnail', 'excerpt' ),
            'rewrite'      => array( 'slug' => 'events' ),
        )
    );
}
add_action( 'init', 'acme_register_post_types' );
```

## ACF blocks

If the design includes ACF-powered blocks, register them in `inc/acf-blocks.php`
and require it from `functions.php`:

```php
<?php
/**
 * ACF block types.
 *
 * @package Acme
 */
defined( 'ABSPATH' ) || exit;

function acme_register_acf_blocks() {
    if ( ! function_exists( 'acf_register_block_type' ) ) {
        return;
    }
    acf_register_block_type( array(
        'name'            => 'hero',
        'title'           => __( 'Hero', 'acme' ),
        'description'     => __( 'Hero block with image and text.', 'acme' ),
        'render_template' => 'parts/blocks/hero.php',
        'category'        => 'theme',
        'icon'            => 'cover-image',
        'keywords'        => array( 'hero', 'banner' ),
        'supports'        => array( 'align' => array( 'wide', 'full' ) ),
    ) );
}
add_action( 'acf/init', 'acme_register_acf_blocks' );
```

## Enqueue

Use `inc/enqueue.php` for front-end assets:

```php
<?php
/**
 * Theme asset enqueues.
 *
 * @package Acme
 */
defined( 'ABSPATH' ) || exit;

function acme_enqueue_assets() {
    $version = wp_get_theme()->get( 'Version' );
    wp_enqueue_style( 'acme-style', get_stylesheet_uri(), array(), $version );
    wp_enqueue_style( 'acme-main', get_theme_file_uri( 'assets/css/main.css' ), array( 'acme-style' ), $version );
    wp_enqueue_script( 'acme-main', get_theme_file_uri( 'assets/js/main.js' ), array(), $version, true );
}
add_action( 'wp_enqueue_scripts', 'acme_enqueue_assets' );
```

## Theme customization — Customizer (logos + colors + reset)

End-user branding for `classic-acf`: header + **separate footer logo**, a color
control per `:root` color token (deep), and **reset-to-defaults** (colors +
logos). Authored by `scaffold` into `inc/customizer.php` + two JS files; required
from `functions.php` and enqueued from `inc/enqueue.php`. The full cross-strategy
contract (registry derivation, sanitizer, emitter, reset, GC, file matrix) is in
`skills/wp-scaffold/references/theme-customization.md` — this section is the
classic PHP/JS template.

> The guarded `<slug>_the_footer_logo()` **render helper is defined in `convert`**
> (foundation), not here — see
> `skills/theme-conversion/references/classic-acf.md`. Scaffold only adds the
> Customizer control that sets the mod.

**Branding store = theme_mods only.** Logos and brand colors live solely in
`theme_mods_<slug>`, never on an ACF options page — so reset is complete. (ACF
options, if used, hold *content* like CTA copy, not branding.)

### `inc/customizer.php`

```php
<?php
/**
 * Branding & Colors Customizer (logos + deep colors + reset).
 * Generated by scaffold from designTokens.colors[]. @package Acme
 */
defined( 'ABSPATH' ) || exit;

/**
 * Editable color-token registry — single source for register + emit + reset.
 * Deterministic: derived 1:1 from designTokens.colors[] at scaffold time, so
 * this array is byte-stable across `scaffold --force`.
 */
function acme_color_tokens() {
	return array(
		array( 'slug' => 'primary',    'cssVar' => '--color-primary',    'label' => __( 'Primary', 'acme' ),    'default' => '#1a73e8', 'group' => 'brand' ),
		array( 'slug' => 'secondary',  'cssVar' => '--color-secondary',  'label' => __( 'Secondary', 'acme' ),  'default' => '#34a853', 'group' => 'brand' ),
		array( 'slug' => 'foreground', 'cssVar' => '--color-foreground', 'label' => __( 'Foreground', 'acme' ), 'default' => '#202124', 'group' => 'text' ),
		array( 'slug' => 'background', 'cssVar' => '--color-background', 'label' => __( 'Background', 'acme' ), 'default' => '#ffffff', 'group' => 'surface' ),
	);
}

/**
 * Allow #hex (3/4/6/8), rgb()/rgba(), hsl()/hsla(); else '' (drop). Used on
 * save AND re-applied on output — DB-imported / `wp eval` mods bypass save.
 */
function acme_sanitize_color( $value ) {
	$value = trim( (string) $value );
	if ( preg_match( '/^#(?:[0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})$/i', $value ) ) {
		return strtolower( $value );
	}
	if ( preg_match( '/^(?:rgba?|hsla?)\(\s*[0-9.,%\/\sdega]+\)$/i', $value ) ) {
		return $value;
	}
	return '';
}

function acme_customize_register( $wp_customize ) {
	$wp_customize->add_panel( 'acme_branding', array(
		'title'    => __( 'Branding & Colors', 'acme' ),
		'priority' => 30,
	) );

	// --- Logos -------------------------------------------------------------
	$wp_customize->add_section( 'acme_logos', array(
		'title' => __( 'Logos', 'acme' ),
		'panel' => 'acme_branding',
	) );
	// Header logo uses core custom-logo; surface it in this section.
	if ( $wp_customize->get_control( 'custom_logo' ) ) {
		$wp_customize->get_control( 'custom_logo' )->section = 'acme_logos';
	}
	// Separate footer logo — attachment ID via Media control.
	$wp_customize->add_setting( 'acme_footer_logo', array(
		'default'           => 0,
		'sanitize_callback' => 'absint',
		'transport'         => 'postMessage',
	) );
	$wp_customize->add_control( new WP_Customize_Media_Control( $wp_customize, 'acme_footer_logo', array(
		'label'     => __( 'Footer Logo', 'acme' ),
		'section'   => 'acme_logos',
		'mime_type' => 'image',
	) ) );
	// Live-preview the footer logo by re-rendering its wrapper via the guarded
	// helper — handles the set / clear / fallback states without wp.media.
	if ( isset( $wp_customize->selective_refresh ) ) {
		$wp_customize->selective_refresh->add_partial( 'acme_footer_logo', array(
			'selector'            => '.site-branding--footer',
			'render_callback'     => 'acme_the_footer_logo',
			'container_inclusive' => false,
			'fallback_refresh'    => true,
		) );
	}

	// --- Colors (one control per :root token) ------------------------------
	$wp_customize->add_section( 'acme_colors', array(
		'title' => __( 'Colors', 'acme' ),
		'panel' => 'acme_branding',
	) );
	$i = 0;
	foreach ( acme_color_tokens() as $t ) {
		$key = 'acme_color_' . $t['slug'];
		$wp_customize->add_setting( $key, array(
			'default'           => $t['default'],
			'sanitize_callback' => 'acme_sanitize_color',
			'transport'         => 'postMessage',
		) );
		$wp_customize->add_control( new WP_Customize_Color_Control( $wp_customize, $key, array(
			'label'   => $t['label'],
			'section' => 'acme_colors',
			// Group order via priority from the deterministic group.
			'priority' => 10 * array_search( $t['group'], array( 'brand', 'text', 'surface', 'state' ), true ) + $i++,
		) ) );
	}

	// --- Reset -------------------------------------------------------------
	$wp_customize->add_section( 'acme_reset', array(
		'title' => __( 'Reset', 'acme' ),
		'panel' => 'acme_branding',
	) );
	$wp_customize->add_setting( 'acme_reset_noop', array(
		'default'           => '',
		'sanitize_callback' => '__return_empty_string',
		'transport'         => 'postMessage',
	) );
	$wp_customize->add_control( new Acme_Reset_Control( $wp_customize, 'acme_reset_noop', array(
		'label'   => __( 'Reset branding to defaults', 'acme' ),
		'section' => 'acme_reset',
	) ) );
}
add_action( 'customize_register', 'acme_customize_register' );

/**
 * Inline-CSS emitter: :root override only for color mods != default. Re-runs
 * the function-color sanitizer on output and writes CSS-context-safe values.
 */
function acme_customizer_css() {
	$css = '';
	foreach ( acme_color_tokens() as $t ) {
		$val = get_theme_mod( 'acme_color_' . $t['slug'], $t['default'] );
		if ( $val === $t['default'] ) {
			continue;
		}
		$val = acme_sanitize_color( $val );
		if ( '' === $val ) {
			continue;
		}
		$css .= $t['cssVar'] . ':' . $val . ';';
	}
	if ( '' === $css ) {
		return;
	}
	$handle = wp_style_is( 'acme-main', 'registered' ) ? 'acme-main' : 'acme-style';
	wp_add_inline_style( $handle, ':root{' . $css . '}' );
}
add_action( 'wp_enqueue_scripts', 'acme_customizer_css', 20 );

/**
 * Keep the DB clean: drop any color mod equal to its default so reset is a true
 * revert; GC orphan acme_color_* mods no longer in the registry (token rename).
 */
function acme_customize_save_after() {
	$valid = array();
	foreach ( acme_color_tokens() as $t ) {
		$valid[ 'acme_color_' . $t['slug'] ] = $t['default'];
	}
	$mods = get_theme_mods();
	if ( ! is_array( $mods ) ) {
		return;
	}
	foreach ( $mods as $key => $val ) {
		if ( 0 !== strpos( (string) $key, 'acme_color_' ) ) {
			continue;
		}
		if ( ! isset( $valid[ $key ] ) || $val === $valid[ $key ] ) {
			remove_theme_mod( $key ); // orphan, or equals default
		}
	}
}
add_action( 'customize_save_after', 'acme_customize_save_after' );
```

### Reset control class (`inc/class-acme-reset-control.php`)

```php
<?php
defined( 'ABSPATH' ) || exit;

if ( class_exists( 'WP_Customize_Control' ) ) {
	class Acme_Reset_Control extends WP_Customize_Control {
		public $type = 'acme_reset';
		public function render_content() {
			printf(
				'<button type="button" class="button button-link-delete acme-reset">%s</button>',
				esc_html( $this->label )
			);
		}
	}
}
```

Both JS files read the **localized token map** (`AcmeCustomizer.tokens`, one entry
per registry token: `slug` / `cssVar` / `default`) so the slug list is never
hardcoded — re-deriving it on the server keeps `scaffold --force` byte-stable and
the JS in lockstep with the registry.

### `assets/js/customizer-preview.js`

```js
( function ( wp, data ) {
	var api = wp.customize;
	// Colors → set the token's cssVar live on :root (postMessage).
	( data.tokens || [] ).forEach( function ( t ) {
		api( 'acme_color_' + t.slug, function ( value ) {
			value.bind( function ( to ) {
				document.documentElement.style.setProperty( t.cssVar, to );
			} );
		} );
	} );
	// Footer logo previews via a selective-refresh partial (registered in
	// inc/customizer.php) — no wp.media here. custom_logo uses core's partial.
}( window.wp, window.AcmeCustomizer || {} ) );
```

### `assets/js/customizer-controls.js`

```js
( function ( wp, $, data ) {
	wp.customize.bind( 'ready', function () {
		$( document ).on( 'click', '.acme-reset', function ( e ) {
			e.preventDefault();
			( data.tokens || [] ).forEach( function ( t ) {
				var s = wp.customize( 'acme_color_' + t.slug );
				if ( s ) { s.set( t.default ); } // default from the registry map, not s.default
			} );
			var fl = wp.customize( 'acme_footer_logo' );
			if ( fl ) { fl.set( 0 ); }
			var cl = wp.customize( 'custom_logo' );
			if ( cl ) { cl.set( '' ); }
		} );
	} );
}( window.wp, jQuery, window.AcmeCustomizer || {} ) );
```

Enqueue both from `inc/enqueue.php`, localizing the registry so the JS stays in
sync (use `wp_get_theme()->get( 'Version' )` for cache-busting — do not assume an
`ACME_VERSION` constant exists in the enqueue context):

```php
add_action( 'customize_preview_init', function () {
	$ver = wp_get_theme()->get( 'Version' );
	wp_enqueue_script( 'acme-customizer-preview', get_theme_file_uri( 'assets/js/customizer-preview.js' ), array( 'customize-preview' ), $ver, true );
	wp_localize_script( 'acme-customizer-preview', 'AcmeCustomizer', array( 'tokens' => acme_color_tokens() ) );
} );
add_action( 'customize_controls_enqueue_scripts', function () {
	$ver = wp_get_theme()->get( 'Version' );
	wp_enqueue_script( 'acme-customizer-controls', get_theme_file_uri( 'assets/js/customizer-controls.js' ), array( 'customize-controls', 'jquery' ), $ver, true );
	wp_localize_script( 'acme-customizer-controls', 'AcmeCustomizer', array( 'tokens' => acme_color_tokens() ) );
} );
```

Wire `inc/customizer.php` from `functions.php`:

```php
require get_theme_file_path( 'inc/class-acme-reset-control.php' );
require get_theme_file_path( 'inc/customizer.php' );
```

## ACF JSON load / save point

In `functions.php` (or `inc/acf-json.php`):

```php
add_filter( 'acf/settings/save_json', function () {
    return get_stylesheet_directory() . '/acf-json';
} );
add_filter( 'acf/settings/load_json', function ( $paths ) {
    $paths[] = get_stylesheet_directory() . '/acf-json';
    return $paths;
} );
```

The `scaffold` stage writes field-group JSON to `acf-json/`; ACF auto-syncs on
admin load.

## What NOT to do

- No Blade, Acorn, Sage, `@include`, or View Composers.
- No hardcoded colors — use `var(--color-*)` from `designTokens`.
- No unsafe `echo` — escape every output.
- No inline `<script>` or `<link>` tags in templates — enqueue everything.
- No CPT/tax registration inline in `functions.php` — keep it in `inc/post-types.php`.
- No complex ACF field-group PHP — author fields in the ACF GUI and export to
  `acf-json/`.
- No fixed heading levels in reusable components — pass the level as an arg.
- No container/Bedrock-specific paths unless the project explicitly uses Bedrock.

## Build order

1. Dirs + `style.css` header + `:root` tokens.
2. `functions.php` (supports, menus, enqueue, ACF JSON point, require includes).
3. `header.php`, `footer.php`, `index.php`.
4. Root templates per `analysis.pages[].role` → record `theme.templateMap`.
5. `parts/*` per `analysis.components[]`.
6. `inc/post-types.php`, `inc/acf-blocks.php` (if blocks), `inc/enqueue.php`.
7. Copy optimized assets into `assets/`.
8. Hand detailed field-group JSON to the `scaffold` stage.
