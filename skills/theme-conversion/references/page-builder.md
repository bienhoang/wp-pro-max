# Backend: page-builder (Elementor / Bricks)

Use when `strategy = page-builder` (and `builder` = `elementor` | `bricks`).
A lightweight host theme provides the shell (`header`/`footer`/`functions.php`);
the builder renders page bodies from data stored in postmeta. The convert stage
builds the host theme + the **template map that references the builder data** that
the `seed-plugin-data` stage will later write into `_elementor_data`.

## File set (host theme `wp-content/themes/<themeSlug>/`)

```
style.css                 # header + :root CSS variables from designTokens
functions.php             # enqueue, theme supports, menus, builder compatibility
header.php  footer.php
index.php  page.php        # minimal; builder takes over the content area
single.php archive.php
assets/css/ assets/js/
templates/                 # exported builder template JSON (see below)
  home.elementor.json
  about.elementor.json
screenshot.png
```

The PHP shell is intentionally thin (same structure as classic-acf's header/footer
/index/page — reuse those templates, minus ACF and template-parts). The builder
owns section/column/widget layout. Keep `the_content()` in `page.php` so builder
output renders.

## page.php (lets the builder render the body)

```php
<?php
/**
 * Page template — builder renders inside the_content().
 *
 * @package Acme
 */

get_header();

while ( have_posts() ) :
	the_post();
	?>
	<article id="post-<?php the_ID(); ?>" <?php post_class(); ?>>
		<div class="entry-content"><?php the_content(); ?></div>
	</article>
	<?php
endwhile;

get_footer();
```

## functions.php notes for builders

```php
<?php
/**
 * Host theme bootstrap for a page-builder strategy.
 *
 * @package Acme
 */

defined( 'ABSPATH' ) || exit;

function acme_setup() {
	load_theme_textdomain( 'acme', get_template_directory() . '/languages' );
	add_theme_support( 'post-thumbnails' );
	add_theme_support( 'title-tag' );
	add_theme_support( 'align-wide' );           // lets Elementor/Bricks use full/wide widths
	register_nav_menus( array( 'primary' => __( 'Primary Menu', 'acme' ) ) );
}
add_action( 'after_setup_theme', 'acme_setup' );

function acme_enqueue_assets() {
	wp_enqueue_style( 'acme-style', get_stylesheet_uri(), array(), '1.0.0' );
	wp_enqueue_style( 'acme-main', get_theme_file_uri( 'assets/css/main.css' ), array(), '1.0.0' );
}
add_action( 'wp_enqueue_scripts', 'acme_enqueue_assets' );
```

`:root` CSS variables from `designTokens` go in `style.css` exactly as in
classic-acf (so builder widgets can reference `var(--color-primary)` etc.).

## Registering the builder

The builder is a plugin selected by the `plugins` stage (Elementor =
`elementor`; Bricks = `bricks`, premium ZIP). Installation/activation happens via
`.wp-env.json` plugins + WP-CLI:

```bash
wp-env run cli wp plugin activate elementor
# Elementor option: register theme as compatible (optional)
wp-env run cli wp option update elementor_disable_color_schemes yes
```

## Elementor `_elementor_data` structure

Elementor stores each page's layout as a JSON tree in postmeta key
`_elementor_data`. The tree is an array of **sections → columns → widgets**:

```json
[
  {
    "id": "a1b2c3d",
    "elType": "section",
    "settings": { "layout": "full_width", "background_background": "classic", "background_color": "#1a73e8" },
    "elements": [
      {
        "id": "c0l1aaa",
        "elType": "column",
        "settings": { "_column_size": 100 },
        "elements": [
          {
            "id": "wgt1111",
            "elType": "widget",
            "widgetType": "heading",
            "settings": { "title": "Build faster with Acme", "header_size": "h1", "align": "center" }
          },
          {
            "id": "wgt2222",
            "elType": "widget",
            "widgetType": "button",
            "settings": { "text": "Get started", "link": { "url": "/contact/" }, "align": "center" }
          }
        ]
      }
    ]
  }
]
```

Key rules for valid Elementor data:
- Every element needs a unique `id` (7-char hex is conventional).
- Hierarchy is strict: `section` → `column` (with `_column_size`) → `widget`.
- Common `widgetType`s: `heading`, `text-editor`, `image`, `button`, `icon-box`,
  `image-box`, `tabs`, `form` (Elementor Pro), `posts`.
- Companion meta required for the page to open in Elementor:
  `_elementor_edit_mode=builder`, `_elementor_template_type=wp-page`,
  `_elementor_version=<ver>`.

The convert stage writes the JSON tree per page to `templates/<page>.elementor.json`
(human-readable), derived from `analysis.pages[].sections[]` mapped to widgets.
The `seed-plugin-data` stage seeds it (see wp-cli-cheatsheet "Elementor"):

```bash
PID=$(wp-env run cli wp post create --post_type=page --post_title="Home" --post_status=publish --porcelain)
wp-env run cli wp post meta update "$PID" _elementor_edit_mode builder
wp-env run cli wp post meta update "$PID" _elementor_template_type wp-page
wp-env run cli wp post meta update "$PID" _elementor_data "$(cat templates/home.elementor.json)"
wp-env run cli wp elementor flush-css "$PID"   # if elementor CLI present
```

## Template map shape (page-builder)

Because the layout lives in postmeta (not a PHP/HTML file), `theme.templateMap`
points each source page to its builder data file + the meta key the seeder writes:

```json
{
  "index.html": { "wpTemplate": "page.php", "builder": "elementor", "data": "templates/home.elementor.json", "metaKey": "_elementor_data" },
  "about.html": { "wpTemplate": "page.php", "builder": "elementor", "data": "templates/about.elementor.json", "metaKey": "_elementor_data" }
}
```

## Bricks variant (when builder=bricks)

Bricks stores layout in postmeta `_bricks_page_content_2` as a JSON array of
elements (`{ "id", "name", "parent", "children", "settings" }`, flat list linked by
`parent`/`children` rather than nested). Builder data files use
`templates/<page>.bricks.json`; the same template-map shape applies with
`"builder": "bricks"` and `"metaKey": "_bricks_page_content_2"`.

## Build order

1. `style.css` header + `:root` tokens.
2. Thin shell: `functions.php`, `header.php`, `footer.php`, `index.php`, `page.php`.
3. For each `analysis.pages[]`, translate `sections[]` → builder JSON tree and
   write `templates/<page>.<builder>.json`.
4. Record the builder template map (above) in `theme.templateMap`.
5. Leave page creation + `_elementor_data` seeding to `seed-plugin-data`.
