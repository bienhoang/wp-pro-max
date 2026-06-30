# Plugin Lifecycle

Canonical patterns for plugin activation, deactivation, uninstall, and upgrade
routines.

## Activation

Use `register_activation_hook` for one-time setup. Guard against running on every
request by setting an option and checking it on `admin_init`.

```php
<?php
/**
 * Plugin activation handler.
 */
function myplugin_activate() {
	myplugin_create_tables();
	myplugin_schedule_cron();
	myplugin_set_default_options();

	// Flush rewrite rules once, then let init re-flush if needed.
	flush_rewrite_rules();

	update_option( 'myplugin_version', MYPLUGIN_VERSION );
}
register_activation_hook( __FILE__, 'myplugin_activate' );
```

## Deactivation

Clean up scheduled events and transient state. Do **not** delete user data or
options unless the user explicitly requested it.

```php
<?php
/**
 * Plugin deactivation handler.
 */
function myplugin_deactivate() {
	wp_clear_scheduled_hook( 'myplugin_daily_sync' );
	delete_transient( 'myplugin_remote_config' );
}
register_deactivation_hook( __FILE__, 'myplugin_deactivate' );
```

## Uninstall

Prefer a dedicated `uninstall.php` file. Only delete data that the plugin owns.
Respect the `UNINSTALL_PLUGIN` constant.

```php
<?php
/**
 * Fired when the plugin is uninstalled.
 */

if ( ! defined( 'WP_UNINSTALL_PLUGIN' ) ) {
	exit;
}

// Only remove data if the plugin stored its own tables or options.
global $wpdb;
$wpdb->query( "DROP TABLE IF EXISTS {$wpdb->prefix}myplugin_items" );
delete_option( 'myplugin_version' );
delete_option( 'myplugin_settings' );
```

## Idempotent upgrade routine

Check the stored version on `admin_init` and run migrations exactly once.

```php
<?php
/**
 * Run upgrade routines if the plugin version changed.
 */
function myplugin_maybe_upgrade() {
	$current_version = get_option( 'myplugin_version', '0.0.0' );

	if ( version_compare( $current_version, MYPLUGIN_VERSION, '>=' ) ) {
		return;
	}

	if ( version_compare( $current_version, '1.1.0', '<' ) ) {
		myplugin_migrate_110();
	}

	update_option( 'myplugin_version', MYPLUGIN_VERSION );
}
add_action( 'admin_init', 'myplugin_maybe_upgrade' );
```

## Rewrite rules

Flush rules **only** on activation and when a post type/taxonomy/endpoint
changes. Do not call `flush_rewrite_rules()` unconditionally on every `init`.

---

*Conventions adapted from [alessioarzenton/claude-code-wp-toolkit](https://github.com/alessioarzenton/claude-code-wp-toolkit) (GPL-3.0), rewritten for WP Pro Max (MIT).*
