# Playbook: template hierarchy, assets, theme.json

Symptoms: wrong template renders, 404 on a page that exists, "mất style",
`theme.json` not applied.

Branch on `strategy` from `wp-build.json` — the same symptom has three different
causes across the three backends.

```bash
STRATEGY="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh" get '.strategy')"
```

## Wrong template renders

WordPress picks the **first file that exists** in the hierarchy. The bug is
almost always a file that exists and should not, or one that is missing so a
broader fallback wins.

Ask WordPress what it actually chose rather than reasoning about the hierarchy
from memory:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" eval '
  add_filter("template_include", function($t){ echo "TEMPLATE: $t\n"; return $t; }, 9999);
  $wp_query = new WP_Query(["pagename" => "about"]);
'
```

| Strategy | Where the decision lives |
|---|---|
| `classic-acf` | PHP files at theme root: `page-{slug}.php` → `page-{id}.php` → `page.php` → `singular.php` → `index.php` |
| `block-fse` | `templates/*.html` — a `templates/page-about.html` beats `templates/page.html`. **Not** the PHP hierarchy |
| `page-builder` | The builder usually takes over `single`/`page`; the theme template may never render at all |

Common causes:
- A `page-{slug}.php` left over from conversion that shadows the intended template.
- `block-fse`: a `templates/*.html` present but the theme is missing `index.html`,
  which WordPress requires as the FSE fallback.
- A Custom Post Type registered with `has_archive => false`, so the archive 404s.

## 404 on a page that exists

Check in this order — the cheapest, most common cause first:

```bash
# 1. Permalinks. A stale rewrite table 404s every pretty URL.
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" option get permalink_structure
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" rewrite flush

# 2. Does the post exist and is it published?
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" post list --post_type=page --field=post_name

# 3. CPT registered with the right rewrite slug?
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" eval 'print_r(get_post_type_object("service")->rewrite);'
```

A CPT registered on `init` **after** the rewrite rules are built needs one flush;
a CPT whose `rewrite.slug` collides with an existing page slug 404s permanently
and needs the collision resolved, not a flush.

## Styles missing / theme.json not applied

### classic-acf

Enqueue problems, in order of likelihood:

```php
// Cache-busting with filemtime — a stale browser/CDN copy looks exactly like
// "my CSS change did nothing". Commit b8b12c2 fixed this exact class of bug.
wp_enqueue_style(
    'acme-main',
    get_stylesheet_directory_uri() . '/assets/css/main.css',
    [],
    filemtime( get_stylesheet_directory() . '/assets/css/main.css' )
);
```

- **Handle collision** — two `wp_enqueue_style()` calls with the same handle:
  the second is silently ignored. `wpx eval 'print_r(wp_styles()->registered["acme-main"]);'`
- **Dependency order** — a stylesheet that must override another must declare it
  in `$deps`, not merely be enqueued later.
- **Hook** — enqueues belong on `wp_enqueue_scripts`. On `init` they are too
  early and silently do nothing.
- **A hardcoded version string** that never changes: the file updates, the URL
  does not, the browser serves the old copy. Use `filemtime()`.

### block-fse

`theme.json` failing to apply is usually one of:

- **Invalid JSON.** WordPress fails silently — no notice, styles just do not
  appear. Always check first: `jq -e . "$THEME_PATH/theme.json"`
- **Wrong `$schema` / `version`.** WordPress 6.x expects `"version": 3`. A v2
  file parses but several v3 keys are ignored.
- **Cached.** `theme.json` is cached in a transient; the theme file changed but
  the cache did not:
  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" transient delete --all
  ```
  In a `WP_DEBUG` environment the cache is bypassed, which is why "it works
  locally with debug on" is a misleading signal.
- **A user global-styles override.** Edits in the Site Editor are stored as a
  `wp_global_styles` post and **beat `theme.json`**. Inspect before rewriting the
  file — the file may be perfectly correct and simply overridden:
  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" post list --post_type=wp_global_styles --field=ID
  ```
  Resetting a user's Site Editor customisations is destructive:
  `AskUserQuestion` first.

### page-builder

The builder holds its own CSS cache, generated per page into `uploads/`. Theme
CSS changes do not invalidate it — the page keeps serving the old generated file:

```bash
# Elementor: regenerate the generated CSS files.
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" elementor flush-css
```

If `elementor` is not a registered WP-CLI command the plugin is inactive or too
old — say so rather than reporting a flush that never ran.

Builder-rendered pages ignore most theme templates by design. A theme-side CSS
fix for a builder page is usually the wrong layer: the content lives in
`_elementor_data` (→ `fix-data.md`).

## Verify

```bash
php -l <changed file>
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" eval 'echo get_stylesheet_directory();'
```

Then reload the page. A CSS fix that cannot be seen is not verified — say which
viewport/page you actually checked, or ask the user to confirm.
