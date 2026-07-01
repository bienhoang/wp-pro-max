---
name: wp-performance-backend
description: >-
  Diagnose and optimize WordPress 7.x backend performance: TTFB, DB queries,
  object cache, autoload options, cron, and remote HTTP. Use during QA or when
  a generated site feels slow. Works inside the wp-env pipeline.
user-invocable: true
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# WordPress Backend Performance

Use this skill to diagnose and fix backend slowness in a WP Pro Max generated site. It focuses on server-side profiling: TTFB, database queries, object cache, autoloaded options, cron, and remote HTTP calls.

**Pair with**: the `wp-qa` skill for frontend/Core Web Vitals work. Do not use this skill for asset optimization (CSS/JS/images).

## When to use

- A page, REST endpoint, or admin screen has high TTFB.
- You need a structured profiling plan and tooling recommendations.
- The symptom is intermittent or depends on logged-in vs anonymous users.
- The site is running inside the WP Pro Max `wp-env` container.

## Before you start

Read `wp-build.json` to identify:

- `env.localUrl` — the local site URL to measure.
- `theme.slug` — used as the object-cache group name in examples.

If `env.localUrl` is missing, discover the URL with:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" option get home
```

All WP-CLI examples below are written for `wp-env`. Run them from the project root.

## Procedure

### 0) Guardrails

1. Confirm whether you can safely install plugins, change config, or flush caches.
2. Pick a reproducible target URL or REST route and capture a baseline.
3. Do not enable `SAVEQUERIES` or `WP_DEBUG` in production without explicit approval — they add significant overhead.

### 1) Capture a baseline

```bash
# Discover the local URL.
LOCAL_URL=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" option get home)

# Measure TTFB with curl.
curl -o /dev/null -s -w "TTFB: %{time_starttransfer}s\nTotal: %{time_total}s\n" "$LOCAL_URL/sample-page/"

# WP-CLI profile stage breakdown (requires wp-cli/profile-command).
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" profile stage --url="$LOCAL_URL/sample-page/"
```

Store the numbers so you can compare after fixes.

### 2) Quick diagnostics

If the `wp doctor` command is available:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" doctor check
```

It flags common issues such as autoload bloat, active `SAVEQUERIES`/`WP_DEBUG`, too many plugins, and pending updates.

If `wp doctor` is not installed, check manually:

```bash
# Autoload size in bytes.
PREFIX="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" db prefix)"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" db query "SELECT SUM(LENGTH(option_value)) FROM ${PREFIX}options WHERE autoload = 'yes'" --skip-column-names

# Active plugin count.
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" plugin list --status=active --format=count

# Core and PHP version.
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" core version && bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" eval "echo PHP_VERSION;"
```

### 3) Deep profiling

#### A) WP-CLI Profile command

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" profile stage --url="$LOCAL_URL/sample-page/"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" profile hook --url="$LOCAL_URL/sample-page/" --spotlight
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" profile eval 'get_posts(["post_type" => "post", "posts_per_page" => 50]);'
```

#### B) Query Monitor via REST headers

Install and activate Query Monitor, then inspect response headers:

```bash
curl -s -D - "$LOCAL_URL/wp-json/wp/v2/posts" \
  -H "Authorization: Basic $(printf 'user:app-password' | base64)" \
  | grep -i 'x-qm'
```

#### C) Xdebug / XHProf / Blackfire

Use these for PHP-level profiling. They require server configuration; coordinate with hosting or DevOps in production environments.

### 4) Fixes by category

Pick the dominant bottleneck from the profile output.

#### A) Database queries

| Problem | Diagnosis | Solution |
|---------|-----------|----------|
| Too many queries | Query count > 50 per page | Find N+1 patterns, use `update_meta_cache()` |
| Slow queries | Individual queries > 100ms | Add indexes, simplify `meta_query` |
| Expensive `meta_query` | `LIKE` or `NOT EXISTS` on postmeta | Consider a custom taxonomy |
| N+1 on post meta | `get_post_meta()` inside a loop | Use `update_postmeta_cache()` before the loop |

```php
// BEFORE — N+1 pattern.
foreach ( $posts as $post ) {
    $status = get_post_meta( $post->ID, 'custom_status', true );
}

// AFTER — pre-cache + loop.
update_postmeta_cache( wp_list_pluck( $posts, 'ID' ) );
foreach ( $posts as $post ) {
    $status = get_post_meta( $post->ID, 'custom_status', true );
}
```

#### B) Autoload options

Options with `autoload = 'yes'` load on every request:

```bash
PREFIX="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" db prefix)"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" db query "SELECT option_name, LENGTH(option_value) AS size FROM ${PREFIX}options WHERE autoload = 'yes' ORDER BY size DESC LIMIT 20"
```

- Blobs > 100KB: consider disabling autoload or moving the data.
- Core options such as `rewrite_rules`, `active_plugins`, and `widget_*` are normally autoloaded.

```php
// Disable autoload for a heavy option.
wp_set_option_autoload( 'my_heavy_option', false );
```

#### C) Object cache

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" eval "echo file_exists( WP_CONTENT_DIR . '/object-cache.php' ) ? 'YES' : 'NO';"
```

- Without a persistent object cache (Redis, Memcached), the cache is request-scoped only.
- With persistent cache, verify hit rate and avoid storing large blobs.

```php
// Use wp_cache for expensive computed data.
$results = wp_cache_get( 'active_items_count', 'my-theme' );
if ( false === $results ) {
    $results = compute_active_items_count();
    wp_cache_set( 'active_items_count', $results, 'my-theme', HOUR_IN_SECONDS );
}
```

Replace `my-theme` with the theme slug from `wp-build.json` when the cache is theme-specific.

#### D) Remote HTTP calls

External API calls during page rendering kill performance:

- Use short timeouts (`'timeout' => 5`).
- Cache responses with transients.
- Never call external APIs inside a loop.

```php
function fetch_external_data(): array {
    $cached = get_transient( 'external_api_data' );
    if ( false !== $cached ) {
        return $cached;
    }

    $response = wp_remote_get( 'https://api.example.com/data', [ 'timeout' => 5 ] );
    if ( is_wp_error( $response ) ) {
        return [];
    }

    $data = json_decode( wp_remote_retrieve_body( $response ), true );
    set_transient( 'external_api_data', $data, HOUR_IN_SECONDS );
    return $data;
}
```

#### E) Cron

```bash
# List scheduled events.
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" cron event list

# Run a single event for debugging.
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" cron event run my_custom_event
```

- Distribute "due now" spikes across schedules.
- Avoid heavy cron work in the HTTP request path.
- For long tasks, run the event via system crontab (`bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" cron event run …`) instead of relying on `wp-cron.php` in the request path.

### 5) Verify the fix

Repeat the same measurement as the baseline on the same environment and URL:

```bash
curl -o /dev/null -s -w "TTFB: %{time_starttransfer}s\nTotal: %{time_total}s\n" "$LOCAL_URL/sample-page/"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" profile stage --url="$LOCAL_URL/sample-page/"
```

- Compare before/after numbers.
- Confirm functional behavior is unchanged.
- For risky changes, release behind a feature flag or gradually.

## WordPress 7.x performance notes

WordPress 7.x continues to improve backend efficiency. Keep these trends in mind when profiling:

- Classic themes receive more granular block CSS loading.
- Block themes reduce render-blocking assets through `theme.json`.
- Increased inline-CSS thresholds reduce blocking requests.

Use these improvements as context, but still measure before changing code.

## Verification checklist

- [ ] Baseline and post-fix measurements captured on the same environment and URL.
- [ ] `bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" doctor check` clean or improved (if available).
- [ ] No new PHP errors or warnings in the logs.
- [ ] Functional behavior unchanged.
- [ ] Query count reduced (goal: < 50 for a standard page).

## Common errors and solutions

| Problem | Likely cause | Solution |
|---------|--------------|----------|
| No improvement | Wrong URL/site measured, cache masking result, stale OPcache | Verify `--url`, flush OPcache, repeat |
| Noisy data | Background tasks, cold caches, few samples | Warm caches, eliminate variables, take more samples |
| `SAVEQUERIES` overhead | Enabled in production | Disable immediately; use only in dev/staging |
| Object cache not working | Missing drop-in or server down | Verify `object-cache.php` and cache server status |

## What NOT to do

- Do not optimize without measuring first.
- Do not enable `SAVEQUERIES` or `WP_DEBUG` in production without approval.
- Do not install plugins or run load tests in production without coordination.
- Do not flush cache during traffic without reason.
- Do not add MySQL indexes blindly — verify with `EXPLAIN` first.
- Do not cache everything indiscriminately — stale cache is worse than no cache.

---

*Ported and rewritten for WP Pro Max from `alessioarzenton/claude-code-wp-toolkit` (GPL-3.0). Target license: MIT.*
