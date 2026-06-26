<?php
/**
 * wp-pro-max SEO head fallback.
 *
 * Drop this into the generated theme's functions.php (or as a mu-plugin) ONLY
 * when no SEO plugin (Yoast / Rank Math / SEOPress) is installed. It emits
 * per-page meta description, Open Graph, Twitter cards, a self-referential
 * canonical, and role-based JSON-LD. When an SEO plugin IS active, do NOT load
 * this — the plugin owns <head> output and double tags hurt rankings.
 *
 * Descriptions come from the page's real excerpt/content (never lorem). Replace
 * the ORG_* constants with manifest values (project.name, urls.production).
 */

if ( ! defined( 'ABSPATH' ) ) { exit; }

if ( ! function_exists( 'wppm_seo_active_plugin' ) ) {
	/** Bail out if a real SEO plugin is present. */
	function wppm_seo_active_plugin() {
		return defined( 'WPSEO_VERSION' )          // Yoast
			|| class_exists( 'RankMath' )           // Rank Math
			|| defined( 'SEOPRESS_VERSION' );       // SEOPress
	}
}

if ( ! function_exists( 'wppm_seo_description' ) ) {
	/** Derive a <=160 char description from the queried object's real content. */
	function wppm_seo_description() {
		$desc = '';
		if ( is_singular() ) {
			$post = get_queried_object();
			$desc = $post->post_excerpt ? $post->post_excerpt : wp_strip_all_tags( $post->post_content );
		} elseif ( is_home() || is_front_page() ) {
			$desc = get_bloginfo( 'description' );
		} elseif ( is_archive() ) {
			$desc = wp_strip_all_tags( term_description() );
		}
		$desc = trim( preg_replace( '/\s+/', ' ', (string) $desc ) );
		if ( mb_strlen( $desc ) > 160 ) {
			$desc = rtrim( mb_substr( $desc, 0, 157 ) ) . '…';
		}
		return $desc;
	}
}

if ( ! function_exists( 'wppm_seo_head' ) ) {
	/** Print meta + canonical + JSON-LD into <head>. */
	function wppm_seo_head() {
		if ( wppm_seo_active_plugin() ) {
			return; // plugin handles SEO output
		}

		$site_name = get_bloginfo( 'name' );
		$canonical = is_singular() ? get_permalink() : home_url( add_query_arg( array(), $GLOBALS['wp']->request ) );
		$desc      = wppm_seo_description();
		$title     = wp_get_document_title();
		$image     = '';
		if ( is_singular() && has_post_thumbnail() ) {
			$image = get_the_post_thumbnail_url( null, 'large' );
		}

		// --- Meta + canonical ------------------------------------------------
		if ( $desc ) {
			printf( "<meta name=\"description\" content=\"%s\">\n", esc_attr( $desc ) );
		}
		printf( "<link rel=\"canonical\" href=\"%s\">\n", esc_url( $canonical ) );

		// --- Open Graph ------------------------------------------------------
		printf( "<meta property=\"og:type\" content=\"%s\">\n", is_singular() && ! is_front_page() ? 'article' : 'website' );
		printf( "<meta property=\"og:title\" content=\"%s\">\n", esc_attr( $title ) );
		printf( "<meta property=\"og:site_name\" content=\"%s\">\n", esc_attr( $site_name ) );
		printf( "<meta property=\"og:url\" content=\"%s\">\n", esc_url( $canonical ) );
		if ( $desc ) {
			printf( "<meta property=\"og:description\" content=\"%s\">\n", esc_attr( $desc ) );
		}
		if ( $image ) {
			printf( "<meta property=\"og:image\" content=\"%s\">\n", esc_url( $image ) );
		}

		// --- Twitter ---------------------------------------------------------
		printf( "<meta name=\"twitter:card\" content=\"%s\">\n", $image ? 'summary_large_image' : 'summary' );
		printf( "<meta name=\"twitter:title\" content=\"%s\">\n", esc_attr( $title ) );
		if ( $desc ) {
			printf( "<meta name=\"twitter:description\" content=\"%s\">\n", esc_attr( $desc ) );
		}
		if ( $image ) {
			printf( "<meta name=\"twitter:image\" content=\"%s\">\n", esc_url( $image ) );
		}

		// --- JSON-LD ---------------------------------------------------------
		wppm_seo_jsonld( $canonical, $site_name, $image );
	}
	add_action( 'wp_head', 'wppm_seo_head', 1 );
}

if ( ! function_exists( 'wppm_seo_jsonld' ) ) {
	/** Emit Organization+WebSite on the front page; Article on singular posts. */
	function wppm_seo_jsonld( $canonical, $site_name, $image ) {
		$org_id = home_url( '/#organization' );
		$graph  = array();

		if ( is_front_page() ) {
			$graph[] = array(
				'@type' => 'Organization',
				'@id'   => $org_id,
				'name'  => $site_name,
				'url'   => home_url( '/' ),
			);
			$graph[] = array(
				'@type'     => 'WebSite',
				'@id'       => home_url( '/#website' ),
				'url'       => home_url( '/' ),
				'name'      => $site_name,
				'publisher' => array( '@id' => $org_id ),
				'potentialAction' => array(
					'@type'       => 'SearchAction',
					'target'      => home_url( '/?s={search_term_string}' ),
					'query-input' => 'required name=search_term_string',
				),
			);
		} elseif ( is_singular( 'post' ) ) {
			$post    = get_queried_object();
			$graph[] = array(
				'@type'            => 'Article',
				'headline'         => get_the_title( $post ),
				'datePublished'    => get_the_date( 'c', $post ),
				'dateModified'     => get_the_modified_date( 'c', $post ),
				'author'           => array( '@type' => 'Person', 'name' => get_the_author_meta( 'display_name', $post->post_author ) ),
				'publisher'        => array( '@id' => $org_id ),
				'mainEntityOfPage' => array( '@type' => 'WebPage', '@id' => $canonical ),
				'image'            => $image ? array( $image ) : array(),
			);
		} else {
			$graph[] = array(
				'@type'           => 'BreadcrumbList',
				'itemListElement' => array(
					array( '@type' => 'ListItem', 'position' => 1, 'name' => 'Home', 'item' => home_url( '/' ) ),
					array( '@type' => 'ListItem', 'position' => 2, 'name' => wp_get_document_title(), 'item' => $canonical ),
				),
			);
		}

		$payload = array( '@context' => 'https://schema.org', '@graph' => $graph );
		echo "<script type=\"application/ld+json\">"
			. wp_json_encode( $payload, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE )
			. "</script>\n";
	}
}
