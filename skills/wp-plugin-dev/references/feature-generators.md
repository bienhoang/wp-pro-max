# Feature Generators Reference

Canonical secure bodies for the five core plugin features. Each body is embedded
as a fenced code block marked with `<!-- file: ... -->`. `plugin-scaffold.sh`
extracts, tokenizes, and writes the class; it then inserts a registration line
at the `src/Plugin.php` registrar marker.

Tokens used in addition to the common manifest tokens:

- `__FEATURE_NAME__` — CamelCase feature name (e.g. `Item`).
- `__FEATURE_CLASS__` — generated class name (e.g. `ItemPostType`).
- `__FEATURE_SLUG__` — snake_case slug for the CPT/taxonomy/REST/shortcode.
- `__FEATURE_SLUG_KEBAB__` — kebab-case slug for shortcode/block handles.
- `__FEATURE_REST_BASE__` — plural REST base (e.g. `items`).
- `__FEATURE_OPTION__` — option name for the settings page.
- `__FEATURE_OBJECT_TYPE__` — post type a taxonomy is bound to (e.g. `item`).
- `__SHOW_IN_REST__` — boolean string `true`/`false` for CPT REST exposure.

## Custom Post Type

<!-- file: PostTypes/ItemPostType.php -->
```php
<?php
/**
 * Custom post type: __FEATURE_NAME__.
 *
 * @package __NAMESPACE__
 */

namespace __NAMESPACE__\PostTypes;

defined( 'ABSPATH' ) || exit;

/**
 * __FEATURE_NAME__ post type.
 */
class __FEATURE_CLASS__ {

	/**
	 * Post type key.
	 *
	 * @var string
	 */
	private $slug = '__FEATURE_SLUG__';

	/**
	 * Register hooks.
	 */
	public function register() {
		add_action( 'init', array( $this, 'register_post_type' ) );
	}

	/**
	 * Register the post type.
	 */
	public function register_post_type() {
		$labels = array(
			'name'                  => __( '__FEATURE_NAME__s', '__TEXTDOMAIN__' ),
			'singular_name'         => __( '__FEATURE_NAME__', '__TEXTDOMAIN__' ),
			'add_new_item'          => __( 'Add New __FEATURE_NAME__', '__TEXTDOMAIN__' ),
			'edit_item'             => __( 'Edit __FEATURE_NAME__', '__TEXTDOMAIN__' ),
			'new_item'              => __( 'New __FEATURE_NAME__', '__TEXTDOMAIN__' ),
			'view_item'             => __( 'View __FEATURE_NAME__', '__TEXTDOMAIN__' ),
			'search_items'          => __( 'Search __FEATURE_NAME__s', '__TEXTDOMAIN__' ),
			'not_found'             => __( 'No __FEATURE_NAME__s found', '__TEXTDOMAIN__' ),
			'not_found_in_trash'    => __( 'No __FEATURE_NAME__s found in trash', '__TEXTDOMAIN__' ),
			'parent_item_colon'     => __( 'Parent __FEATURE_NAME__:', '__TEXTDOMAIN__' ),
			'all_items'             => __( 'All __FEATURE_NAME__s', '__TEXTDOMAIN__' ),
			'archives'              => __( '__FEATURE_NAME__ Archives', '__TEXTDOMAIN__' ),
			'insert_into_item'      => __( 'Insert into __FEATURE_NAME__', '__TEXTDOMAIN__' ),
			'uploaded_to_this_item' => __( 'Uploaded to this __FEATURE_NAME__', '__TEXTDOMAIN__' ),
		);

		$args = array(
			'labels'       => $labels,
			'public'       => true,
			'has_archive'  => true,
			'show_in_rest' => __SHOW_IN_REST__,
			'menu_icon'    => 'dashicons-admin-post',
			'supports'     => array( 'title', 'editor', 'thumbnail', 'excerpt' ),
			'rewrite'      => array( 'slug' => '__FEATURE_SLUG__' ),
		);

		register_post_type( $this->slug, $args );
	}
}
```

## Taxonomy

<!-- file: PostTypes/ItemTaxonomy.php -->
```php
<?php
/**
 * Taxonomy: __FEATURE_NAME__.
 *
 * @package __NAMESPACE__
 */

namespace __NAMESPACE__\PostTypes;

defined( 'ABSPATH' ) || exit;

/**
 * __FEATURE_NAME__ taxonomy.
 */
class __FEATURE_CLASS__ {

	/**
	 * Taxonomy key.
	 *
	 * @var string
	 */
	private $slug = '__FEATURE_SLUG__';

	/**
	 * Object type(s) the taxonomy applies to.
	 *
	 * @var string
	 */
	private $object_type = '__FEATURE_OBJECT_TYPE__';

	/**
	 * Register hooks.
	 */
	public function register() {
		add_action( 'init', array( $this, 'register_taxonomy' ) );
	}

	/**
	 * Register the taxonomy.
	 */
	public function register_taxonomy() {
		$labels = array(
			'name'          => __( '__FEATURE_NAME__s', '__TEXTDOMAIN__' ),
			'singular_name' => __( '__FEATURE_NAME__', '__TEXTDOMAIN__' ),
			'add_new_item'  => __( 'Add New __FEATURE_NAME__', '__TEXTDOMAIN__' ),
			'edit_item'     => __( 'Edit __FEATURE_NAME__', '__TEXTDOMAIN__' ),
			'all_items'     => __( 'All __FEATURE_NAME__s', '__TEXTDOMAIN__' ),
		);

		$args = array(
			'labels'            => $labels,
			'public'            => true,
			'hierarchical'      => true,
			'show_in_rest'      => false,
			'show_admin_column' => true,
			'rewrite'           => array( 'slug' => '__FEATURE_SLUG__' ),
		);

		register_taxonomy( $this->slug, array( $this->object_type ), $args );
	}
}
```

## Settings Page

<!-- file: Admin/SettingsPage.php -->
```php
<?php
/**
 * Plugin settings page.
 *
 * @package __NAMESPACE__
 */

namespace __NAMESPACE__\Admin;

defined( 'ABSPATH' ) || exit;

/**
 * Settings page using the Settings API.
 */
class SettingsPage {

	/**
	 * Option group/name.
	 *
	 * @var string
	 */
	private $option = '__FEATURE_OPTION__';

	/**
	 * Menu slug.
	 *
	 * @var string
	 */
	private $page = '__SLUG__-settings';

	/**
	 * Register hooks.
	 */
	public function register() {
		add_action( 'admin_menu', array( $this, 'add_menu' ) );
		add_action( 'admin_init', array( $this, 'register_settings' ) );
	}

	/**
	 * Add the options page.
	 */
	public function add_menu() {
		add_options_page(
			__( '__NAME__ Settings', '__TEXTDOMAIN__' ),
			__( '__NAME__ Settings', '__TEXTDOMAIN__' ),
			'manage_options',
			$this->page,
			array( $this, 'render' )
		);
	}

	/**
	 * Register settings and fields.
	 */
	public function register_settings() {
		register_setting(
			$this->option,
			$this->option,
			array( 'sanitize_callback' => array( $this, 'sanitize' ) )
		);

		add_settings_section(
			$this->option . '-section',
			__( 'General Settings', '__TEXTDOMAIN__' ),
			array( $this, 'section_description' ),
			$this->page
		);

		add_settings_field(
			$this->option . '-example',
			__( 'Example Setting', '__TEXTDOMAIN__' ),
			array( $this, 'render_field' ),
			$this->page,
			$this->option . '-section',
			array( 'label_for' => $this->option . '-example' )
		);
	}

	/**
	 * Section description.
	 */
	public function section_description() {
		echo '<p>' . esc_html__( 'Configure __NAME__ settings.', '__TEXTDOMAIN__' ) . '</p>';
	}

	/**
	 * Render the field.
	 *
	 * @param array $args Field arguments.
	 */
	public function render_field( $args ) {
		$value = get_option( $this->option, array() );
		$value = isset( $value['example'] ) ? $value['example'] : '';
		printf(
			'<input type="text" id="%1$s" name="%2$s[example]" value="%3$s" class="regular-text">',
			esc_attr( $args['label_for'] ),
			esc_attr( $this->option ),
			esc_attr( $value )
		);
	}

	/**
	 * Sanitize input.
	 *
	 * @param array $input Raw input.
	 * @return array Sanitized input.
	 */
	public function sanitize( $input ) {
		$clean = array();
		if ( isset( $input['example'] ) ) {
			$clean['example'] = sanitize_text_field( $input['example'] );
		}
		return $clean;
	}

	/**
	 * Render the settings page.
	 */
	public function render() {
		if ( ! current_user_can( 'manage_options' ) ) {
			return;
		}
		?>
		<div class="wrap">
			<h1><?php echo esc_html( get_admin_page_title() ); ?></h1>
			<form action="options.php" method="post">
				<?php
				settings_fields( $this->option );
				do_settings_sections( $this->page );
				submit_button();
				?>
			</form>
		</div>
		<?php
	}
}
```

## REST Controller

<!-- file: Rest/ItemsController.php -->
```php
<?php
/**
 * REST controller: __FEATURE_NAME__.
 *
 * @package __NAMESPACE__
 */

namespace __NAMESPACE__\Rest;

defined( 'ABSPATH' ) || exit;

/**
 * __FEATURE_NAME__ REST controller.
 */
class __FEATURE_CLASS__ {

	/**
	 * REST namespace.
	 *
	 * @var string
	 */
	private $namespace = '__SLUG__/v1';

	/**
	 * REST base.
	 *
	 * @var string
	 */
	private $rest_base = '__FEATURE_REST_BASE__';

	/**
	 * Register hooks.
	 */
	public function register() {
		add_action( 'rest_api_init', array( $this, 'register_routes' ) );
	}

	/**
	 * Register routes.
	 */
	public function register_routes() {
		register_rest_route(
			$this->namespace,
			'/' . $this->rest_base,
			array(
				array(
					'methods'             => \WP_REST_Server::READABLE,
					'callback'            => array( $this, 'get_items' ),
					'permission_callback' => array( $this, 'get_items_permissions_check' ),
					'args'                => $this->get_collection_params(),
				),
				array(
					'methods'             => \WP_REST_Server::CREATABLE,
					'callback'            => array( $this, 'create_item' ),
					'permission_callback' => array( $this, 'create_item_permissions_check' ),
					'args'                => $this->get_endpoint_args_for_item_schema(),
				),
			)
		);

		register_rest_route(
			$this->namespace,
			'/' . $this->rest_base . '/(?P<id>[\d]+)',
			array(
				array(
					'methods'             => \WP_REST_Server::READABLE,
					'callback'            => array( $this, 'get_item' ),
					'permission_callback' => array( $this, 'get_items_permissions_check' ),
					'args'                => array(
						'id' => array(
							'required'          => true,
							'validate_callback' => array( $this, 'validate_id' ),
						),
					),
				),
			)
		);
	}

	/**
	 * Validate item ID.
	 *
	 * @param mixed           $param Parameter.
	 * @param WP_REST_Request $request Request.
	 * @param string          $key Key.
	 * @return bool|WP_Error
	 */
	public function validate_id( $param, $request, $key ) { // phpcs:ignore Generic.CodeAnalysis.UnusedFunctionParameter.FoundAfterLastUsed
		return is_numeric( $param ) && absint( $param ) > 0;
	}

	/**
	 * Permissions for reading.
	 *
	 * @return bool
	 */
	public function get_items_permissions_check() {
		return current_user_can( 'read' );
	}

	/**
	 * Permissions for writing.
	 *
	 * @return bool
	 */
	public function create_item_permissions_check() {
		return current_user_can( 'manage_options' );
	}

	/**
	 * Collection params.
	 *
	 * @return array
	 */
	public function get_collection_params() {
		return array(
			'per_page' => array(
				'default'           => 10,
				'sanitize_callback' => 'absint',
				'validate_callback' => function ( $param ) {
					return is_numeric( $param ) && absint( $param ) <= 100;
				},
			),
		);
	}

	/**
	 * Endpoint args for item schema.
	 *
	 * @return array
	 */
	public function get_endpoint_args_for_item_schema() {
		return array(
			'title' => array(
				'required'          => true,
				'type'              => 'string',
				'sanitize_callback' => 'sanitize_text_field',
			),
		);
	}

	/**
	 * Get items.
	 *
	 * @param WP_REST_Request $request Request.
	 * @return WP_REST_Response
	 */
	public function get_items( $request ) { // phpcs:ignore Generic.CodeAnalysis.UnusedFunctionParameter.Found
		$data = array(
			array(
				'id'    => 1,
				'title' => __( 'Sample item', '__TEXTDOMAIN__' ),
			),
		);
		return rest_ensure_response( $data );
	}

	/**
	 * Get item.
	 *
	 * @param WP_REST_Request $request Request.
	 * @return WP_REST_Response
	 */
	public function get_item( $request ) {
		$id = absint( $request->get_param( 'id' ) );
		return rest_ensure_response(
			array(
				'id'    => $id,
				'title' => __( 'Sample item', '__TEXTDOMAIN__' ),
			)
		);
	}

	/**
	 * Create item.
	 *
	 * @param WP_REST_Request $request Request.
	 * @return WP_REST_Response
	 */
	public function create_item( $request ) {
		$title = sanitize_text_field( $request->get_param( 'title' ) );
		return rest_ensure_response(
			array(
				'id'    => 1,
				'title' => $title,
			)
		);
	}
}
```

## Shortcode

<!-- file: Shortcodes/ItemShortcode.php -->
```php
<?php
/**
 * Shortcode: __FEATURE_NAME__.
 *
 * @package __NAMESPACE__
 */

namespace __NAMESPACE__\Shortcodes;

defined( 'ABSPATH' ) || exit;

/**
 * __FEATURE_NAME__ shortcode.
 */
class __FEATURE_CLASS__ {

	/**
	 * Shortcode tag.
	 *
	 * @var string
	 */
	private $tag = '__SLUG__-__FEATURE_SLUG_KEBAB__';

	/**
	 * Register hooks.
	 */
	public function register() {
		add_shortcode( $this->tag, array( $this, 'render' ) );
	}

	/**
	 * Render the shortcode.
	 *
	 * @param array|string $atts Attributes.
	 * @return string
	 */
	public function render( $atts ) {
		$atts = shortcode_atts(
			array(
				'title' => '',
				'count' => 3,
			),
			$atts,
			$this->tag
		);

		$title = sanitize_text_field( $atts['title'] );
		$count = absint( $atts['count'] );

		ob_start();
		?>
		<div class="<?php echo esc_attr( $this->tag ); ?>">
			<h2><?php echo esc_html( $title ? $title : __( 'Default Title', '__TEXTDOMAIN__' ) ); ?></h2>
			<p>
				<?php
				/* translators: %d: number of items */
				echo esc_html( sprintf( __( 'Count: %d', '__TEXTDOMAIN__' ), $count ) );
				?>
			</p>
		</div>
		<?php
		return ob_get_clean();
	}
}
```
