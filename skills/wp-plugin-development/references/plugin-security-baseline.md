# Plugin Security Baseline

Non-negotiable security practices for WordPress plugin code. These align with
the `wp-plugin-developer` agent standards; use this file as the single source of
truth for plugin security guidance.

## File guard

Every PHP file must start with:

```php
<?php

defined( 'ABSPATH' ) || exit;
```

## Input sanitization

Sanitize as close to the boundary as possible.

| Source | Function |
|--------|----------|
| Plain text | `sanitize_text_field()` |
| Integer | `absint()` |
| Email | `sanitize_email()` |
| URL | `esc_url_raw()` |
| Rich HTML | `wp_kses_post()` or `wp_kses( $text, $allowed_html )` |
| Array of IDs | `array_map( 'intval', (array) $input )` |

```php
<?php

$title   = isset( $_POST['myplugin_title'] ) ? sanitize_text_field( wp_unslash( $_POST['myplugin_title'] ) ) : '';
$limit   = isset( $_POST['myplugin_limit'] ) ? absint( $_POST['myplugin_limit'] ) : 10;
$content = isset( $_POST['myplugin_content'] ) ? wp_kses_post( wp_unslash( $_POST['myplugin_content'] ) ) : '';
```

## Output escaping

Escape at the point of output, even if the data was sanitized on input.

```php
<?php
?>
<input type="text" name="myplugin_title" value="<?php echo esc_attr( $title ); ?>">
<p><?php echo esc_html( $description ); ?></p>
<a href="<?php echo esc_url( $url ); ?>"><?php echo esc_html( $label ); ?></a>
```

## Nonces

Use nonces for any form or AJAX action that writes data.

```php
<?php
// Render.
wp_nonce_field( 'myplugin_save_settings', 'myplugin_settings_nonce' );

// Verify.
if ( ! isset( $_POST['myplugin_settings_nonce'] ) ||
	! wp_verify_nonce( sanitize_text_field( wp_unslash( $_POST['myplugin_settings_nonce'] ) ), 'myplugin_save_settings' ) ) {
	return;
}
```

For admin forms handled by the Settings API, `settings_fields()` emits the nonce
automatically; still gate renders on `current_user_can()`.

## Capability checks

Never rely on `is_admin()` alone. Check a concrete capability.

```php
<?php
if ( ! current_user_can( 'manage_options' ) ) {
	return;
}
```

For custom post types, use the post-type capability map (`edit_posts`,
`publish_posts`, etc.).

## Prepared SQL

Always use `$wpdb->prepare()` when values are interpolated.

```php
<?php
$results = $wpdb->get_results(
	$wpdb->prepare(
		"SELECT * FROM {$wpdb->prefix}myplugin_items WHERE status = %s AND priority > %d",
		$status,
		$priority
	)
);
```

Use `{$wpdb->prefix}` for table names; never hard-code a prefix.

## REST route permissions

Every write route must have a real `permission_callback`.

```php
<?php
register_rest_route(
	'myplugin/v1',
	'/items/(?P<id>\d+)',
	array(
		'methods'             => WP_REST_Server::EDITABLE,
		'callback'            => 'myplugin_rest_update_item',
		'permission_callback' => function () {
			return current_user_can( 'manage_options' );
		},
		'args'                => array(
			'id' => array(
				'required'          => true,
				'validate_callback' => function ( $param ) {
					return is_numeric( $param );
				},
			),
		),
	)
);
```

## Anti-patterns

- Do not echo `$_GET`, `$_POST`, or DB values without escaping.
- Do not use `__return_true` for `permission_callback` on write routes.
- Do not run `flush_rewrite_rules()` on every request.
- Do not store unvalidated serialized data from users.

---

*Conventions adapted from [alessioarzenton/claude-code-wp-toolkit](https://github.com/alessioarzenton/claude-code-wp-toolkit) (GPL-3.0), rewritten for WP Pro Max (MIT).*
