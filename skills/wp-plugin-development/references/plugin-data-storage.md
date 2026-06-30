# Plugin Data Storage

Guidance for choosing where and how to persist plugin data.

## Storage options

| Mechanism | Best for | Avoid |
|-----------|----------|-------|
| Options API (`get_option`) | Small global settings, feature flags, version markers | Large arrays, unbounded lists, frequently changing data |
| Postmeta | Data attached to a specific post, page, or CPT | Global plugin state |
| Custom table | Structured relational data, large datasets, custom queries | One-off values, data that maps cleanly to posts |
| Transients | Cached computed values, remote responses | Data that must survive cache flush |

## Options API

Use autoload sparingly. For large or rarely used options, set `'autoload' =>
'no'`.

```php
<?php
$settings = get_option( 'myplugin_settings', array() );
$settings['endpoint'] = esc_url_raw( $new_endpoint );
update_option( 'myplugin_settings', $settings, 'no' );
```

## Postmeta

Sanitize on save; escape on read/output.

```php
<?php
update_post_meta( $post_id, '_myplugin_sync_status', sanitize_text_field( $status ) );
$status = get_post_meta( $post_id, '_myplugin_sync_status', true );
```

Prefix meta keys with `_` to hide them from the default custom fields UI.

## Custom tables

Create tables on activation with the same charset/collate as WordPress.

```php
<?php
function myplugin_create_tables() {
	global $wpdb;

	$charset_collate = $wpdb->get_charset_collate();
	$table_name      = $wpdb->prefix . 'myplugin_items';

	$sql = "CREATE TABLE IF NOT EXISTS {$table_name} (
		id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
		post_id bigint(20) unsigned NOT NULL,
		status varchar(20) NOT NULL DEFAULT 'pending',
		created_at datetime DEFAULT CURRENT_TIMESTAMP,
		PRIMARY KEY (id),
		KEY post_id (post_id),
		KEY status (status)
	) {$charset_collate};";

	require_once ABSPATH . 'wp-admin/includes/upgrade.php';
	dbDelta( $sql );
}
```

Use `$wpdb->prepare()` for queries. Drop tables in `uninstall.php`, not on
deactivation.

## Transients and caching

Set reasonable expiration. Store fallback values so a missing transient does not
break the UI.

```php
<?php
function myplugin_get_remote_config() {
	$config = get_transient( 'myplugin_remote_config' );

	if ( false === $config ) {
		$config = myplugin_fetch_remote_config();

		if ( ! is_wp_error( $config ) ) {
			set_transient( 'myplugin_remote_config', $config, HOUR_IN_SECONDS );
		}
	}

	return $config;
}
```

## Idempotent cron

Schedule events only if not already scheduled.

```php
<?php
function myplugin_schedule_cron() {
	if ( ! wp_next_scheduled( 'myplugin_daily_sync' ) ) {
		wp_schedule_event( time(), 'daily', 'myplugin_daily_sync' );
	}
}
```

## Versioning and migrations

Store the plugin version in an option. Run migrations in `admin_init` when the
stored version is behind the plugin version. See `plugin-lifecycle.md` for the
upgrade routine pattern.

---

*Conventions adapted from [alessioarzenton/claude-code-wp-toolkit](https://github.com/alessioarzenton/claude-code-wp-toolkit) (GPL-3.0), rewritten for WP Pro Max (MIT).*
