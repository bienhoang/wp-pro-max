# Plugin Architecture Reference

Canonical layout and template bodies for a WP Pro Max standalone plugin.
All template bodies are embedded in this reference as fenced code blocks marked
with `<!-- file: ... -->` comments. `plugin-scaffold.sh` extracts and tokenizes
them. No separate `templates/` directory is used.

## File layout

```
<slug>/
  <slug>.php          # WordPress header + bootstrap
  uninstall.php       # guarded uninstall entry point
  readme.txt          # WordPress.org readme (filled by tooling.md)
  inc/autoload.php    # PSR-4 fallback autoloader (no Composer required)
  src/Plugin.php      # singleton bootstrap + registrar marker
  languages/          # POT/translation files
  .gitignore
```

## Bootstrap `<slug>.php`

<!-- file: bootstrap.php -->
```php
<?php
/**
 * Plugin Name: __NAME__
 * Plugin URI:  https://example.com/__SLUG__
 * Description: __DESCRIPTION__
 * Version:     __VERSION__
 * Author:      __AUTHOR__
 * License:     GPL-2.0-or-later
 * License URI: https://www.gnu.org/licenses/gpl-2.0.html
 * Text Domain: __TEXTDOMAIN__
 * Domain Path: /languages
 *
 * @package __NAMESPACE__
 */

defined( 'ABSPATH' ) || exit;

define( '__CONST_PREFIX___PLUGIN_FILE', __FILE__ );
define( '__CONST_PREFIX___PLUGIN_DIR', __DIR__ );

if ( file_exists( __DIR__ . '/vendor/autoload.php' ) ) {
	require __DIR__ . '/vendor/autoload.php';
}

// Real PSR-4 fallback autoloader; always registered so the plugin runs without Composer.
require __DIR__ . '/inc/autoload.php';

\__NAMESPACE__\Plugin::instance();
```

## `uninstall.php`

<!-- file: uninstall.php -->
```php
<?php
/**
 * Fired when the plugin is uninstalled.
 *
 * @package __NAMESPACE__
 */

defined( 'WP_UNINSTALL_PLUGIN' ) || exit;
```

## `inc/autoload.php`

<!-- file: inc/autoload.php -->
```php
<?php
/**
 * PSR-4 fallback autoloader.
 *
 * @package __NAMESPACE__
 */

defined( 'ABSPATH' ) || exit;

spl_autoload_register(
	function ( $classname ) {
		$prefix = '__NAMESPACE__\\';
		if ( strpos( $classname, $prefix ) !== 0 ) {
			return;
		}

		$relative = substr( $classname, strlen( $prefix ) );
		$file     = plugin_dir_path( __FILE__ ) . '../src/' . str_replace( '\\', '/', $relative ) . '.php';
		$real     = realpath( $file );
		$base     = realpath( plugin_dir_path( __FILE__ ) . '../src/' );

		if ( false === $real || strpos( $real, $base . DIRECTORY_SEPARATOR ) !== 0 ) {
			return;
		}

		require $real;
	}
);
```

## `src/Plugin.php`

<!-- file: src/Plugin.php -->
```php
<?php
/**
 * Plugin bootstrap.
 *
 * @package __NAMESPACE__
 */

namespace __NAMESPACE__;

defined( 'ABSPATH' ) || exit;

/**
 * Main plugin class.
 */
final class Plugin {

	/**
	 * Singleton instance.
	 *
	 * @var Plugin|null
	 */
	private static $instance = null;

	/**
	 * Plugin file path.
	 *
	 * @var string
	 */
	private $file = '';

	/**
	 * Plugin version.
	 *
	 * @var string
	 */
	private $version = '__VERSION__';

	/**
	 * Retrieve the singleton instance.
	 *
	 * @return Plugin
	 */
	public static function instance() {
		if ( null === self::$instance ) {
			self::$instance = new self();
		}
		return self::$instance;
	}

	/**
	 * Constructor.
	 */
	private function __construct() {
		$this->file = defined( '__CONST_PREFIX___PLUGIN_FILE' ) ? constant( '__CONST_PREFIX___PLUGIN_FILE' ) : __FILE__;
		$this->register();
	}

	/**
	 * Register hooks and feature classes.
	 */
	private function register() {
		add_action( 'init', array( $this, 'init' ) );
		/* wp-plugin-dev:registrar */
	}

	/**
	 * Initialize.
	 */
	public function init() {}

	/**
	 * Plugin directory path.
	 *
	 * @return string
	 */
	public function dir() {
		return plugin_dir_path( $this->file );
	}

	/**
	 * Plugin directory URL.
	 *
	 * @return string
	 */
	public function url() {
		return plugin_dir_url( $this->file );
	}

	/**
	 * Plugin version.
	 *
	 * @return string
	 */
	public function version() {
		return $this->version;
	}
}
```

## `.gitignore`

<!-- file: .gitignore -->
```
node_modules/
vendor/
blocks/*/build/
dist/
*.log
.DS_Store
```

## `readme.txt` (placeholder)

<!-- file: readme.txt -->
```
=== __NAME__ ===
Contributors: __AUTHOR__
Tags: __SLUG__
Requires at least: 6.0
Tested up to: 6.5
Requires PHP: 7.4
Stable tag: __VERSION__
License: GPL-2.0-or-later
License URI: https://www.gnu.org/licenses/gpl-2.0.html

__DESCRIPTION__

== Description ==

__DESCRIPTION__

== Changelog ==

= __VERSION__ =
* Initial release.
```

## Registrar marker rule

`src/Plugin.php` contains a literal sentinel comment:

```php
/* wp-plugin-dev:registrar */
```

Feature generators must insert registration code **immediately before this
marker** and leave the marker in place. The marker is a guaranteed insertion
point; if it is missing, `add` fails loudly. The agent must never move, delete,
or rephrase this comment.
