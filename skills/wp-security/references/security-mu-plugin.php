<?php
/**
 * Plugin Name: WP Pro Max Security Hardening
 * Description: Security headers, version hiding, and optional XML-RPC disable.
 *              Emitted by the wp-security stage into wp-content/mu-plugins/.
 *              Edit the constants below to match the build before shipping.
 *
 * mu-plugins load automatically and cannot be deactivated from the dashboard,
 * which is exactly what we want for baseline hardening.
 */

if ( ! defined( 'ABSPATH' ) ) { exit; }

/**
 * Toggle XML-RPC. Set to true ONLY if nothing needs it (Jetpack, pingbacks,
 * some mobile apps). Default: disabled.
 */
if ( ! defined( 'WPPM_DISABLE_XMLRPC' ) ) {
	define( 'WPPM_DISABLE_XMLRPC', true );
}

/* ---------------------------------------------------------------------------
 * 1. Hide version fingerprints
 * ------------------------------------------------------------------------- */
remove_action( 'wp_head', 'wp_generator' );
add_filter( 'the_generator', '__return_empty_string' );

// Strip ?ver= from script/style URLs so the WP version is not leaked there.
function wppm_strip_version_query( $src ) {
	if ( $src && false !== strpos( $src, 'ver=' ) ) {
		$src = remove_query_arg( 'ver', $src );
	}
	return $src;
}
add_filter( 'style_loader_src', 'wppm_strip_version_query', 9999 );
add_filter( 'script_loader_src', 'wppm_strip_version_query', 9999 );

/* ---------------------------------------------------------------------------
 * 2. Disable XML-RPC (optional)
 * ------------------------------------------------------------------------- */
if ( WPPM_DISABLE_XMLRPC ) {
	add_filter( 'xmlrpc_enabled', '__return_false' );
	// Also remove the RSD link + pingback header that advertise it.
	remove_action( 'wp_head', 'rsd_link' );
	add_filter( 'wp_headers', function ( $headers ) {
		unset( $headers['X-Pingback'] );
		return $headers;
	} );
	// Block direct hits to xmlrpc.php.
	add_filter( 'xmlrpc_methods', '__return_empty_array' );
}

/* ---------------------------------------------------------------------------
 * 3. Security headers
 * ------------------------------------------------------------------------- */
function wppm_security_headers( $headers ) {
	// HSTS only over real HTTPS (avoid locking out an http-only local build).
	if ( is_ssl() ) {
		$headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains';
	}
	$headers['X-Frame-Options']        = 'SAMEORIGIN';
	$headers['X-Content-Type-Options'] = 'nosniff';
	$headers['Referrer-Policy']        = 'strict-origin-when-cross-origin';
	$headers['Permissions-Policy']     = 'geolocation=(), microphone=(), camera=()';

	/*
	 * Content-Security-Policy: start permissive + report-only so a strict policy
	 * does not break the freshly converted theme. Tighten per site (remove
	 * 'unsafe-inline' once inline scripts/styles are nonce'd or externalized).
	 */
	$headers['Content-Security-Policy-Report-Only'] =
		"default-src 'self'; img-src 'self' data: https:; "
		. "style-src 'self' 'unsafe-inline' https:; "
		. "script-src 'self' 'unsafe-inline' https:; "
		. "font-src 'self' data: https:; frame-ancestors 'self'";

	return $headers;
}
add_filter( 'wp_headers', 'wppm_security_headers' );

// Frontend responses don't always pass through wp_headers; also emit on send_headers.
function wppm_send_headers() {
	if ( headers_sent() ) {
		return;
	}
	if ( is_ssl() ) {
		header( 'Strict-Transport-Security: max-age=31536000; includeSubDomains' );
	}
	header( 'X-Frame-Options: SAMEORIGIN' );
	header( 'X-Content-Type-Options: nosniff' );
	header( 'Referrer-Policy: strict-origin-when-cross-origin' );
}
add_action( 'send_headers', 'wppm_send_headers' );

/* ---------------------------------------------------------------------------
 * 4. Trim REST API user enumeration for anonymous requests
 * ------------------------------------------------------------------------- */
add_filter( 'rest_endpoints', function ( $endpoints ) {
	if ( ! is_user_logged_in() ) {
		unset( $endpoints['/wp/v2/users'] );
		unset( $endpoints['/wp/v2/users/(?P<id>[\d]+)'] );
	}
	return $endpoints;
} );
