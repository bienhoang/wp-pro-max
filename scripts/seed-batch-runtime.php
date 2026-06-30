<?php
/**
 * seed-batch-runtime.php — the single, shipped, reviewed PHP runtime for the
 * WP Pro Max seed stages (seed-content + seed-plugin-data).
 *
 * It is invoked ONCE per stage as:
 *     printf '%s' "$payload_json" | wp eval-file scripts/seed-batch-runtime.php
 * i.e. WP-CLI bootstraps WordPress, then includes this file, and the JSON payload
 * is read from STDIN. The payload is PURE JSON DATA — never executable PHP — so
 * there is no injection surface and nothing to escape (red-team C1/C2). All
 * mutations go through the WordPress API (no raw $wpdb writes), each one checking
 * existence before writing so re-runs are idempotent (the zero-dup contract).
 *
 * Output: a single sentinel-wrapped JSON summary on stdout —
 *     WPBUILD_SUMMARY{...}WPBUILD_END
 * emitted by a register_shutdown_function so it survives even a PHP fatal
 * (OOM / timeout / plugin-hook fatal), flushing whatever idempotency keys and
 * counters accumulated before the abort (red-team C4). The unique sentinel lets
 * the bash driver recover the JSON even when WP_DEBUG prints notices to stdout
 * (red-team H2).
 *
 * Counters: `created` increments ONLY on real new-row creation (posts, terms,
 * menus, menu items, media, location bindings). Value changes (options, meta,
 * featured image) count as `updated`. A clean re-run therefore reports
 * created:0 / updated:0 — that is the live acceptance gate.
 */

if (! defined('ABSPATH')) {
    fwrite(STDERR, "seed-batch-runtime: must run under WP-CLI (wp eval-file)\n");
    // No WordPress — emit a minimal error summary so the driver never hangs.
    fwrite(STDOUT, 'WPBUILD_SUMMARY' . json_encode([
        'created' => 0, 'updated' => 0, 'skipped' => 0, 'completed' => false,
        'errors' => ['WordPress not bootstrapped (run via wp eval-file)'],
        'idempotencyKeys' => [],
    ]) . "WPBUILD_END\n");
    exit(1);
}

// ---------------------------------------------------------------------------
// Summary state + fatal-safe emit
// ---------------------------------------------------------------------------

$GLOBALS['WPBUILD'] = [
    'created'         => 0,
    'updated'         => 0,
    'skipped'         => 0,
    'completed'       => false,
    'errors'          => [],
    'idempotencyKeys' => [],
];

/** Record a stable idempotency key (deduped), mirroring seed-helpers.sh. */
function seed_key(string $key): void {
    if (! in_array($key, $GLOBALS['WPBUILD']['idempotencyKeys'], true)) {
        $GLOBALS['WPBUILD']['idempotencyKeys'][] = $key;
    }
}

function seed_created(): void { $GLOBALS['WPBUILD']['created']++; }
function seed_updated(): void { $GLOBALS['WPBUILD']['updated']++; }
function seed_skipped(): void { $GLOBALS['WPBUILD']['skipped']++; }

function seed_error(string $context, string $message): void {
    $GLOBALS['WPBUILD']['errors'][] = $context . ': ' . $message;
}

/** Emit the sentinel-wrapped summary exactly once (normal end OR fatal). */
function seed_emit_summary(): void {
    static $emitted = false;
    if ($emitted) {
        return;
    }
    $emitted = true;

    // Fold in an uncaught fatal (OOM/timeout/parse in a hook) if one is pending.
    $last = error_get_last();
    if ($last && in_array($last['type'], [E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR, E_USER_ERROR], true)) {
        seed_error('fatal', $last['message'] . ' @ ' . $last['file'] . ':' . $last['line']);
    }

    $json = json_encode($GLOBALS['WPBUILD']);
    if ($json === false) {
        // Keep idempotencyKeys (plain ASCII) so a re-run can still resume from the
        // manifest even when an error/value string carried invalid UTF-8.
        $json = json_encode([
            'created'         => $GLOBALS['WPBUILD']['created'],
            'updated'         => $GLOBALS['WPBUILD']['updated'],
            'skipped'         => $GLOBALS['WPBUILD']['skipped'],
            'completed'       => $GLOBALS['WPBUILD']['completed'],
            'idempotencyKeys' => $GLOBALS['WPBUILD']['idempotencyKeys'],
            'errors'          => ['summary json_encode failed: ' . json_last_error_msg()],
        ]);
    }
    fwrite(STDOUT, 'WPBUILD_SUMMARY' . $json . "WPBUILD_END\n");
}
register_shutdown_function('seed_emit_summary');

// ---------------------------------------------------------------------------
// Idempotent helpers — each checks existence before writing (WP API only)
// ---------------------------------------------------------------------------

/** Find a post ID by slug + type (status any), matching _seed_find_post_by_slug. */
function seed_find_post(string $slug, string $ptype): ?int {
    $hits = get_posts([
        'name'        => $slug,
        'post_type'   => $ptype,
        'post_status' => 'any',
        'numberposts' => 1,
        'fields'      => 'ids',
    ]);
    return $hits ? (int) $hits[0] : null;
}

/**
 * Create a post keyed by slug if absent; fold meta + template in; set featured.
 * Returns the post ID (existing or new), or null on hard failure.
 */
function seed_ensure_post(array $p, array $mediaMap): ?int {
    $slug     = (string) ($p['slug'] ?? '');
    $title    = (string) ($p['title'] ?? $slug);
    $ptype    = (string) ($p['type'] ?? 'post');
    $content  = (string) ($p['content'] ?? '');
    $template = (string) ($p['template'] ?? '');
    $meta     = is_array($p['meta'] ?? null) ? $p['meta'] : [];

    if ($slug === '') {
        seed_error('post', 'entry missing slug');
        return null;
    }

    try {
        $id = seed_find_post($slug, $ptype);
        if ($id) {
            seed_skipped();
        } else {
            $id = wp_insert_post([
                'post_type'    => $ptype,
                'post_title'   => $title,
                'post_name'    => $slug,
                'post_status'  => 'publish',
                'post_content' => $content,
            ], true);
            if (is_wp_error($id) || ! $id) {
                seed_error('post:' . $slug, is_wp_error($id) ? $id->get_error_message() : 'insert returned 0');
                return null;
            }
            $id = (int) $id;
            seed_created();
            seed_key($ptype . ':' . $slug);
        }

        // Template (idempotent compare).
        if ($template !== '') {
            seed_meta($id, '_wp_page_template', $template);
        }
        // Folded meta (kills the separate post-meta round-trip).
        foreach ($meta as $k => $v) {
            seed_meta($id, (string) $k, $v);
        }
        // Featured image (resolve media title → attachment ID).
        if (! empty($p['featured'])) {
            $att = $mediaMap[(string) $p['featured']] ?? null;
            if ($att) {
                seed_set_featured($id, (int) $att);
            }
        }
        return $id;
    } catch (\Throwable $e) {
        seed_error('post:' . $slug, $e->getMessage());
        return null;
    }
}

/** Set a postmeta value only when it differs (idempotent; array-aware). */
function seed_meta(int $pid, string $key, $value): void {
    $current = get_post_meta($pid, $key, true); // arrays are returned unserialized
    $same = (is_array($value) || is_array($current))
        ? (wp_json_encode($current) === wp_json_encode($value))
        : ((string) $current === (string) $value);
    if ($same) {
        seed_skipped();
        return;
    }
    update_post_meta($pid, $key, $value); // WP serializes arrays correctly
    seed_updated();
    seed_key('meta:' . $pid . ':' . $key);
}

/** Update an option only when the value differs (array-aware compare). */
function seed_ensure_option(string $name, $value): void {
    try {
        $current = get_option($name, null);
        if ($current !== null) {
            $same = (is_array($value) || is_array($current))
                ? (wp_json_encode($current) === wp_json_encode($value))
                : ((string) $current === (string) $value);
            if ($same) {
                seed_skipped();
                return;
            }
        }
        update_option($name, $value);
        seed_updated();
        seed_key('option:' . $name);
    } catch (\Throwable $e) {
        seed_error('option:' . $name, $e->getMessage());
    }
}

/** Create a term keyed by slug if absent; return its term_id. */
function seed_ensure_term(string $tax, string $name, string $slug): ?int {
    try {
        $existing = term_exists($slug, $tax);
        if ($existing) {
            seed_skipped();
            return (int) (is_array($existing) ? $existing['term_id'] : $existing);
        }
        $res = wp_insert_term($name, $tax, ['slug' => $slug]);
        if (is_wp_error($res)) {
            seed_error('term:' . $tax . ':' . $slug, $res->get_error_message());
            return null;
        }
        seed_created();
        seed_key('term:' . $tax . ':' . $slug);
        return (int) $res['term_id'];
    } catch (\Throwable $e) {
        seed_error('term:' . $tax . ':' . $slug, $e->getMessage());
        return null;
    }
}

/** Create a nav menu keyed by name if absent; return its term_id. */
function seed_ensure_menu(string $name): ?int {
    try {
        $obj = wp_get_nav_menu_object($name);
        if ($obj) {
            seed_skipped();
            return (int) $obj->term_id;
        }
        $id = wp_create_nav_menu($name);
        if (is_wp_error($id)) {
            seed_error('menu:' . $name, $id->get_error_message());
            return null;
        }
        seed_created();
        seed_key('menu:' . $name);
        return (int) $id;
    } catch (\Throwable $e) {
        seed_error('menu:' . $name, $e->getMessage());
        return null;
    }
}

/** True when the menu already has an item with this exact title. */
function seed_menu_has_title(int $menu_id, string $title): bool {
    $items = wp_get_nav_menu_items($menu_id);
    if (! $items) {
        return false;
    }
    foreach ($items as $it) {
        if ($it->title === $title) {
            return true;
        }
    }
    return false;
}

/** Add a post to a menu, deduped by item title. */
function seed_ensure_menu_item_post(int $menu_id, string $menu_name, int $post_id, string $title): void {
    try {
        if (seed_menu_has_title($menu_id, $title)) {
            seed_skipped();
            return;
        }
        $res = wp_update_nav_menu_item($menu_id, 0, [
            'menu-item-title'     => $title,
            'menu-item-object'    => get_post_type($post_id) ?: 'page',
            'menu-item-object-id' => $post_id,
            'menu-item-type'      => 'post_type',
            'menu-item-status'    => 'publish',
        ]);
        if (is_wp_error($res)) {
            seed_error('menu-item:' . $menu_name . ':' . $title, $res->get_error_message());
            return;
        }
        seed_created();
        seed_key('menu-item:' . $menu_name . ':' . $title);
    } catch (\Throwable $e) {
        seed_error('menu-item:' . $menu_name . ':' . $title, $e->getMessage());
    }
}

/** Add a custom-link item to a menu, deduped by item title. */
function seed_ensure_menu_item_custom(int $menu_id, string $menu_name, string $title, string $url): void {
    try {
        if (seed_menu_has_title($menu_id, $title)) {
            seed_skipped();
            return;
        }
        $res = wp_update_nav_menu_item($menu_id, 0, [
            'menu-item-title'  => $title,
            'menu-item-url'    => $url,
            'menu-item-type'   => 'custom',
            'menu-item-status' => 'publish',
        ]);
        if (is_wp_error($res)) {
            seed_error('menu-item:' . $menu_name . ':' . $title, $res->get_error_message());
            return;
        }
        seed_created();
        seed_key('menu-item:' . $menu_name . ':' . $title);
    } catch (\Throwable $e) {
        seed_error('menu-item:' . $menu_name . ':' . $title, $e->getMessage());
    }
}

/** Bind a menu to a theme location (idempotent). */
function seed_assign_menu_location(int $menu_id, string $location): void {
    try {
        $locations = get_nav_menu_locations();
        if (isset($locations[$location]) && (int) $locations[$location] === $menu_id) {
            seed_skipped();
            return;
        }
        $locations[$location] = $menu_id;
        set_theme_mod('nav_menu_locations', $locations);
        seed_updated();
        seed_key('menu-location:' . $location);
    } catch (\Throwable $e) {
        seed_error('menu-location:' . $location, $e->getMessage());
    }
}

/** Set the static front page (and optional posts page) by post ID. */
function seed_set_front_page(int $home_id, ?int $blog_id, string $home_slug): void {
    seed_ensure_option('show_on_front', 'page');
    seed_ensure_option('page_on_front', $home_id);
    if ($blog_id) {
        seed_ensure_option('page_for_posts', $blog_id);
    }
    seed_key('front-page:' . $home_slug);
}

/** Find an attachment ID by exact title (dedupe media by filename title). */
function seed_find_attachment(string $title): ?int {
    $hits = get_posts([
        'post_type'   => 'attachment',
        'post_status' => 'any',
        'title'       => $title,
        'numberposts' => 1,
        'fields'      => 'ids',
    ]);
    return $hits ? (int) $hits[0] : null;
}

/**
 * Import one media file into the library, deduped by title. Local paths are
 * resolved with an optional prefix (assets outside the wp-env mount); http(s)
 * URLs are sideloaded. A failed import lands in errors[] — never a silent
 * imageless "success". Returns the attachment ID or null.
 */
function seed_import_media(string $file, string $title, string $prefix): ?int {
    try {
        $existing = seed_find_attachment($title);
        if ($existing) {
            seed_skipped();
            return $existing;
        }

        require_once ABSPATH . 'wp-admin/includes/image.php';
        require_once ABSPATH . 'wp-admin/includes/file.php';
        require_once ABSPATH . 'wp-admin/includes/media.php';

        if (preg_match('#^https?://#i', $file)) {
            $att = media_sideload_image($file, 0, $title, 'id');
            if (is_wp_error($att)) {
                seed_error('media:' . $title, $att->get_error_message());
                return null;
            }
            seed_created();
            seed_key('media:' . $title);
            return (int) $att;
        }

        $path = $prefix . $file;
        if (! file_exists($path)) {
            seed_error('media:' . $title, "file not reachable in container: $path");
            return null;
        }
        $upload = wp_upload_dir();
        if (! empty($upload['error'])) {
            seed_error('media:' . $title, $upload['error']);
            return null;
        }
        $dest = trailingslashit($upload['path']) . wp_basename($path);
        if (! @copy($path, $dest)) {
            seed_error('media:' . $title, "copy failed: $path → $dest");
            return null;
        }
        $filetype = wp_check_filetype(wp_basename($dest), null);
        $att_id   = wp_insert_attachment([
            'post_mime_type' => $filetype['type'] ?: 'application/octet-stream',
            'post_title'     => $title,
            'post_status'    => 'inherit',
        ], $dest);
        if (is_wp_error($att_id) || ! $att_id) {
            seed_error('media:' . $title, is_wp_error($att_id) ? $att_id->get_error_message() : 'insert_attachment failed');
            return null;
        }
        $meta = wp_generate_attachment_metadata((int) $att_id, $dest);
        wp_update_attachment_metadata((int) $att_id, $meta);
        seed_created();
        seed_key('media:' . $title);
        return (int) $att_id;
    } catch (\Throwable $e) {
        seed_error('media:' . $title, $e->getMessage());
        return null;
    }
}

/** Attach a featured image only when it differs. */
function seed_set_featured(int $pid, int $att): void {
    try {
        $current = (int) get_post_meta($pid, '_thumbnail_id', true);
        if ($current === $att) {
            seed_skipped();
            return;
        }
        set_post_thumbnail($pid, $att);
        seed_updated();
        seed_key('featured:' . $pid);
    } catch (\Throwable $e) {
        seed_error('featured:' . $pid, $e->getMessage());
    }
}

/**
 * Set an ACF field value idempotently (red-team H3). Prefer update_field when
 * ACF is loaded and the field/group resolves (it writes the `_<field>` key row
 * itself); otherwise fall back to update_post_meta AND write the `_<field>`
 * field-key reference row so ACF (and the admin) recognize the value. The field
 * key is taken from the payload (`$key`, sourced from the group JSON) and, when
 * absent, resolved via acf_get_field — so the reference row is correct even when
 * ACF is not loaded in the eval-file context.
 */
function seed_ensure_acf_value(int $pid, string $field, $value, ?string $key = null): void {
    try {
        $field_obj = function_exists('acf_get_field') ? acf_get_field($field) : null;

        if (function_exists('update_field') && $field_obj) {
            $current = function_exists('get_field') ? get_field($field, $pid) : null;
            if ($current !== null && $current === $value) {
                seed_skipped();
                return;
            }
            update_field($field, $value, $pid);
            seed_updated();
            seed_key('meta:' . $pid . ':' . $field);
            return;
        }

        // Fallback: raw postmeta + the field-key reference row (red-team H3).
        seed_meta($pid, $field, $value);
        $ref = $key ?: ($field_obj['key'] ?? '');
        if ($ref !== '') {
            seed_meta($pid, '_' . $field, $ref);
        }
    } catch (\Throwable $e) {
        seed_error('acf:' . $pid . ':' . $field, $e->getMessage());
    }
}

/**
 * Write Elementor builder data idempotently (red-team H4). Sets the full meta
 * set: _elementor_data (wp_slash'd so update_metadata's wp_unslash cancels and
 * the JSON stores intact), _elementor_edit_mode=builder,
 * _elementor_template_type=wp-page, _elementor_version.
 */
function seed_set_elementor_data(int $pid, $data): void {
    try {
        // Normalize to a compact JSON string regardless of array/string input.
        if (is_array($data)) {
            $json = wp_json_encode($data);
        } else {
            $json = (string) $data;
            $decoded = json_decode($json, true);
            if ($decoded === null && json_last_error() !== JSON_ERROR_NONE) {
                seed_error('elementor:' . $pid, 'invalid _elementor_data JSON: ' . json_last_error_msg());
                return;
            }
        }

        $current = get_post_meta($pid, '_elementor_data', true);
        if ((string) $current !== (string) $json) {
            // update_metadata wp_unslash()es the value, so wp_slash first.
            update_post_meta($pid, '_elementor_data', wp_slash($json));
            seed_updated();
            seed_key('meta:' . $pid . ':_elementor_data');
        } else {
            seed_skipped();
        }

        seed_meta($pid, '_elementor_edit_mode', 'builder');
        seed_meta($pid, '_elementor_template_type', 'wp-page');
        seed_meta($pid, '_elementor_version', defined('ELEMENTOR_VERSION') ? ELEMENTOR_VERSION : '3.0.0');
    } catch (\Throwable $e) {
        seed_error('elementor:' . $pid, $e->getMessage());
    }
}

// ---------------------------------------------------------------------------
// Orchestration
// ---------------------------------------------------------------------------

function seed_run(array $payload): void {
    $prefix = (string) ($payload['mediaPathPrefix'] ?? '');

    // 1. Options
    foreach (($payload['options'] ?? []) as $name => $value) {
        seed_ensure_option((string) $name, $value);
    }

    // 2. Terms
    foreach (($payload['terms'] ?? []) as $t) {
        if (! empty($t['tax']) && ! empty($t['slug'])) {
            seed_ensure_term((string) $t['tax'], (string) ($t['name'] ?? $t['slug']), (string) $t['slug']);
        }
    }

    // 3. Media → title→ID map (for featured + elementor image refs)
    $mediaMap = [];
    foreach (($payload['media'] ?? []) as $m) {
        if (empty($m['file'])) {
            continue;
        }
        $title = (string) ($m['title'] ?? pathinfo($m['file'], PATHINFO_FILENAME));
        $id = seed_import_media((string) $m['file'], $title, $prefix);
        if ($id) {
            $mediaMap[$title] = $id;
        }
    }

    // 4. Posts → slug→ID map
    $postMap = [];
    foreach (($payload['posts'] ?? []) as $p) {
        $id = seed_ensure_post($p, $mediaMap);
        if ($id && ! empty($p['slug'])) {
            $postMap[(string) $p['slug']] = $id;
        }
    }

    // 5. Menus
    foreach (($payload['menus'] ?? []) as $menu) {
        $name = (string) ($menu['name'] ?? '');
        if ($name === '') {
            continue;
        }
        $menu_id = seed_ensure_menu($name);
        if (! $menu_id) {
            continue;
        }
        foreach (($menu['items'] ?? []) as $item) {
            $title = (string) ($item['title'] ?? '');
            if (! empty($item['post'])) {
                $pid = $postMap[(string) $item['post']] ?? seed_find_post((string) $item['post'], 'page');
                if ($pid) {
                    seed_ensure_menu_item_post($menu_id, $name, (int) $pid, $title !== '' ? $title : (string) $item['post']);
                } else {
                    seed_error('menu-item:' . $name . ':' . $title, 'post not found: ' . $item['post']);
                }
            } elseif (! empty($item['url'])) {
                seed_ensure_menu_item_custom($menu_id, $name, $title, (string) $item['url']);
            }
        }
        if (! empty($menu['location'])) {
            seed_assign_menu_location($menu_id, (string) $menu['location']);
        }
    }

    // 6. Front page
    if (! empty($payload['frontPage'])) {
        $home_slug = (string) $payload['frontPage'];
        $home_id   = $postMap[$home_slug] ?? seed_find_post($home_slug, 'page');
        if ($home_id) {
            $blog_id = null;
            if (! empty($payload['postsPage'])) {
                $blog_id = $postMap[(string) $payload['postsPage']] ?? seed_find_post((string) $payload['postsPage'], 'page');
            }
            seed_set_front_page((int) $home_id, $blog_id ? (int) $blog_id : null, $home_slug);
        } else {
            seed_error('front-page', "home page '$home_slug' not found");
        }
    }

    // 7. ACF field values (seed-plugin-data)
    foreach (($payload['acf'] ?? []) as $a) {
        if (empty($a['post']) || ! isset($a['field'])) {
            continue;
        }
        $pid = $postMap[(string) $a['post']] ?? seed_find_post((string) $a['post'], (string) ($a['type'] ?? 'page'));
        if ($pid) {
            seed_ensure_acf_value(
                (int) $pid,
                (string) $a['field'],
                $a['value'] ?? '',
                isset($a['key']) ? (string) $a['key'] : null
            );
        } else {
            seed_error('acf', 'post not found: ' . $a['post']);
        }
    }

    // 8. Elementor data (seed-plugin-data)
    foreach (($payload['elementor'] ?? []) as $e) {
        if (empty($e['post']) || ! isset($e['data'])) {
            continue;
        }
        $pid = $postMap[(string) $e['post']] ?? seed_find_post((string) $e['post'], (string) ($e['type'] ?? 'page'));
        if ($pid) {
            seed_set_elementor_data((int) $pid, $e['data']);
        } else {
            seed_error('elementor', 'post not found: ' . $e['post']);
        }
    }
}

// ---------------------------------------------------------------------------
// Entry: read pure JSON from stdin, run, let the shutdown function emit summary
// ---------------------------------------------------------------------------

$raw = file_get_contents('php://stdin');
if ($raw === false || trim($raw) === '') {
    seed_error('input', 'empty payload on stdin');
    seed_emit_summary();
    exit(1); // malformed/empty → error summary + non-zero (no silent no-op)
}

$payload = json_decode($raw, true);
if (! is_array($payload)) {
    seed_error('input', 'malformed JSON payload: ' . json_last_error_msg());
    seed_emit_summary();
    exit(1);
}

// Wrap the batch in a Throwable catch: under WP-CLI an UNCATCHABLE fatal (OOM /
// timeout) never reaches a userland shutdown function (WP-CLI's own fatal
// handler exits first), so catching every Throwable here — which includes
// Error/TypeError from a plugin-hook fatal or bad data — is what makes summary
// emission DETERMINISTIC: the partial idempotencyKeys/counters are flushed and
// the run is re-runnable. A genuine OOM still emits no sentinel, which the bash
// driver detects as a loud non-zero failure (never a silent success).
try {
    seed_run($payload);
    $GLOBALS['WPBUILD']['completed'] = true;
} catch (\Throwable $e) {
    seed_error('fatal', $e->getMessage() . ' @ ' . $e->getFile() . ':' . $e->getLine());
    // completed stays false → driver surfaces the failure after merging partials.
}

seed_emit_summary(); // explicit (the shutdown backstop is guarded against a double emit)
