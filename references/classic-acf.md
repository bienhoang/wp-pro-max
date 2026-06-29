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
