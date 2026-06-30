---
name: wp-scaffold
description: >-
  Scaffolds the live WordPress code into the converted theme (stage `scaffold`).
  Wires functions.php, registers custom post types and taxonomies from the
  content model, writes ACF field-group JSON to acf-json/ (classic) or block
  bindings (FSE), declares nav-menu locations, enqueues assets, and adds image
  sizes. Use when generating WordPress registration code, ACF field groups,
  register_post_type/register_taxonomy, theme functions wiring, or image sizes
  from a content model. Reads contentModel, designTokens, strategy, theme; writes
  theme.files. Delegates heavy authoring to the wp-theme-developer agent.
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# WP Scaffold (stage `scaffold`)

Where `convert` produced the theme skeleton + template map, `scaffold` fills in
the *working WordPress wiring*: the code that registers data structures, fields,
menus, assets, and image sizes. Runs after `convert` and `plugins`.

## Inputs (from `wp-build.json`)

| Field | Produces |
|-------|----------|
| `theme.path` | Where to write code (`wp-content/themes/<slug>/`). |
| `strategy` | classic-acf ⇒ ACF JSON; block-fse ⇒ block bindings/meta; page-builder ⇒ thin shell only. |
| `contentModel.postTypes[]` | `register_post_type()` calls. |
| `contentModel.taxonomies[]` | `register_taxonomy()` calls. |
| `contentModel.fieldGroups[]` | `acf-json/group_*.json` (classic) or `register_meta()` + bindings (FSE). |
| `contentModel.menus[]` | `register_nav_menus()` locations. |
| `designTokens` | `add_image_size()` from breakpoints; enqueue handles. |
| `designTokens.colors[]` | Editable color-token registry (`--color-<slug>`). |
| `theme.customization.enabled` | Gate for the branding (logos + colors + reset) step. |

## Procedure

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh"
wpbuild_is_done scaffold && [[ "${1:-}" != "--force" ]] && { echo "scaffold done"; exit 0; }
wpbuild_progress scaffold in-progress
STRATEGY="$(wpbuild_get '.strategy')"
THEME="$(wpbuild_get '.theme.path')"
TEXTDOMAIN="$(wpbuild_get '.project.textDomain')"
```

1. **Generate registration code** into a dedicated include (keeps `functions.php`
   lean and under the modularization budget):
   `inc/post-types.php`, `inc/taxonomies.php`, `inc/image-sizes.php`,
   `inc/enqueue.php`. For `classic-acf` also generate `inc/acf-blocks.php` when
   the content model includes ACF blocks. Require them from `functions.php`.
2. **classic-acf:** write each `contentModel.fieldGroups[]` entry as
   `acf-json/group_<key>.json` (ACF auto-syncs on admin load). The load/save
   point was wired in `convert`.
3. **block-fse:** register post meta + a block-bindings source per field; do not
   write ACF JSON.
4. **page-builder:** registration of CPTs/tax still applies; fields are handled
   by the builder + seeded postmeta, so no ACF/bindings.
5. **Menus + image sizes + enqueues** for all strategies.
6. **Theme customization (logos + colors + reset)** — when
   `theme.customization.enabled`. Derive the color-token registry from
   `designTokens.colors[]` (each `{ slug, value }` → `cssVar = --color-<slug>`,
   `sanitize_key()`'d slug, deterministic `label`/`group` as pure functions of
   the slug), then route by `strategy`:
   - `classic-acf` → author `inc/customizer.php` (panel + logo/footer-logo/color
     controls + reset), `assets/js/customizer-preview.js`,
     `assets/js/customizer-controls.js`; require + enqueue from `inc/enqueue.php`.
   - `block-fse` → author a customizer file + `customize_register` hook for the
     **footer logo** only (Media control) + an image block-bindings source bound
     in `parts/footer.html`; colors/reset stay in native Global Styles.
   - `page-builder` → host-theme footer-logo Media control + guarded helper
     render; colors via native Global Colors.

   Constraints (inherited by Phase 2/3 agents): namespace all fns + mod keys with
   the theme slug; i18n every label; **escape output in its correct context**
   (CSS context for the `:root` emitter, `esc_url`/`esc_attr` for logo `<img>`);
   function-color sanitizer (hex|rgb(a)|hsl(a)) on save **and** output; emit
   `:root` overrides only for mods ≠ default and attach to `<slug>-main`;
   **deterministic** output (byte-stable `scaffold --force`); **GC** orphan
   `<slug>_color_*` mods absent from the current registry. The guarded
   `<slug>_the_footer_logo()` render helper is authored in `convert`, not here.
   Full spec + per-strategy file matrix: `references/theme-customization.md`.
7. **Delegate** the actual PHP/JSON authoring to **wp-theme-developer** (paths,
   manifest, contentModel slice, strategy, acceptance: activates with no PHP
   notices, `wp post-type list`/`wp taxonomy list` show the new types, ACF group
   imports cleanly, customizer registers with no notices).
8. **Record files + finish.**

   ```bash
   wpbuild_set '.theme.files' "$UPDATED_FILES_JSON"   # append the new inc/ + acf-json/ files
   wpbuild_progress scaffold done "strategy=${STRATEGY}"
   ```

## functions.php wiring (require the includes)

```php
// Append to functions.php (after the convert-stage setup):
require get_theme_file_path( 'inc/post-types.php' );
require get_theme_file_path( 'inc/taxonomies.php' );
require get_theme_file_path( 'inc/image-sizes.php' );
if ( 'classic-acf' === $strategy ) {
    require get_theme_file_path( 'inc/acf-blocks.php' );
}
```

For the `classic-acf` strategy, also ensure the ACF JSON load/save point is set
so field groups written to `acf-json/` are auto-synced:

```php
add_filter( 'acf/settings/save_json', function () {
    return get_stylesheet_directory() . '/acf-json';
} );
add_filter( 'acf/settings/load_json', function ( $paths ) {
    $paths[] = get_stylesheet_directory() . '/acf-json';
    return $paths;
} );
```

See `references/classic-acf.md` for the full canonical reference.

## inc/post-types.php — register_post_type from contentModel.postTypes[]

```php
<?php
/**
 * Custom post types. Generated from contentModel.postTypes[].
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

## inc/taxonomies.php — register_taxonomy from contentModel.taxonomies[]

```php
<?php
/**
 * Custom taxonomies. Generated from contentModel.taxonomies[].
 *
 * @package Acme
 */

defined( 'ABSPATH' ) || exit;

function acme_register_taxonomies() {
	register_taxonomy(
		'event_category',
		array( 'event' ),
		array(
			'labels'            => array(
				'name'          => __( 'Event Categories', 'acme' ),
				'singular_name' => __( 'Event Category', 'acme' ),
			),
			'public'            => true,
			'hierarchical'      => true,
			'show_in_rest'      => true,
			'show_admin_column' => true,
			'rewrite'           => array( 'slug' => 'event-category' ),
		)
	);
}
add_action( 'init', 'acme_register_taxonomies' );
```

## inc/image-sizes.php — add_image_size from designTokens.breakpoints

```php
<?php
/**
 * Custom image sizes for responsive output.
 *
 * @package Acme
 */

defined( 'ABSPATH' ) || exit;

function acme_image_sizes() {
	add_image_size( 'acme-card', 600, 400, true );      // grid/card thumbnails
	add_image_size( 'acme-hero', 1920, 800, true );     // full-width hero
}
add_action( 'after_setup_theme', 'acme_image_sizes' );

// Expose them in the editor image-size dropdown.
function acme_image_size_names( $sizes ) {
	return array_merge( $sizes, array(
		'acme-card' => __( 'Card', 'acme' ),
		'acme-hero' => __( 'Hero', 'acme' ),
	) );
}
add_filter( 'image_size_names_choose', 'acme_image_size_names' );
```

## ACF field-group JSON (classic-acf) — acf-json/group_event.json

```json
{
  "key": "group_event_details",
  "title": "Event Details",
  "fields": [
    { "key": "field_event_date",  "label": "Event Date",  "name": "event_date",  "type": "date_picker", "return_format": "Y-m-d", "required": 1 },
    { "key": "field_event_venue", "label": "Venue",        "name": "venue",       "type": "text" },
    { "key": "field_event_price", "label": "Ticket Price", "name": "price",       "type": "number", "prepend": "$" }
  ],
  "location": [[{ "param": "post_type", "operator": "==", "value": "event" }]],
  "menu_order": 0,
  "active": true,
  "show_in_rest": 1
}
```

## Block bindings + meta (block-fse) — inc/block-bindings.php

```php
<?php
/**
 * Register post meta + a block-bindings source (FSE analog of ACF fields).
 *
 * @package Acme
 */

defined( 'ABSPATH' ) || exit;

function acme_register_meta() {
	register_post_meta( 'event', 'event_date', array(
		'type'         => 'string',
		'single'       => true,
		'show_in_rest' => true,
		'auth_callback' => function () { return current_user_can( 'edit_posts' ); },
	) );
}
add_action( 'init', 'acme_register_meta' );

function acme_register_bindings() {
	register_block_bindings_source( 'acme/meta', array(
		'label'              => __( 'Acme Meta', 'acme' ),
		'get_value_callback' => function ( array $args ) {
			return esc_html( get_post_meta( get_the_ID(), $args['key'], true ) );
		},
	) );
}
add_action( 'init', 'acme_register_bindings' );
```

## Verify

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" theme activate "$(wpbuild_get '.project.themeSlug')"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" post-type list --field=name
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" taxonomy list --field=name
# classic-acf: confirm ACF picked up the JSON
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" eval 'var_export( function_exists("acf_get_field_groups") );'
```

No PHP notices on activation; new post types/taxonomies listed; ACF groups
visible in admin (Custom Fields → Field Groups, marked "synced from JSON").
