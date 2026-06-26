# WP-CLI Cheatsheet (via wp-env)

Prefix every command with `wp-env run cli` from the target project root.
Example: `wp-env run cli wp post list --post_type=page`.

## Posts / pages

```bash
wp post create --post_type=page --post_title="Home" --post_status=publish --porcelain
wp post create ./body.html --post_title="About" --post_type=page --post_status=publish
wp post update <ID> --post_content="$(cat body.html)"
wp post meta update <ID> _wp_page_template "templates/landing.php"
wp post list --post_type=page --field=ID
wp post exists <ID>
```

## Front page / reading settings

```bash
wp option update show_on_front page
wp option update page_on_front <HOME_ID>
wp option update page_for_posts <BLOG_ID>
```

## Menus

```bash
wp menu create "Primary"
wp menu location assign primary primary   # second arg = theme location slug
wp menu item add-post primary <PAGE_ID> --title="Home"
wp menu item add-custom primary "Contact" "/contact"
wp menu item list primary --field=title
```

## Media

```bash
wp media import ./assets/images/*.{jpg,png,webp} --porcelain
wp media import ./hero.jpg --post_id=<ID> --featured_image
```

## Terms / taxonomies

```bash
wp term create category "News" --slug=news
wp post term set <ID> category news
```

## Options / users

```bash
wp option update blogname "Acme"
wp option get permalink_structure
wp rewrite structure '/%postname%/' --hard
wp user create editor editor@acme.test --role=editor --user_pass=...
```

## ACF (Advanced Custom Fields)

```bash
# Field groups live as JSON in theme: <theme>/acf-json/*.json  (auto-sync)
# Set ACF values when creating posts:
wp post create --post_type=event --post_title="Launch" \
  --meta_input='{"event_date":"2026-12-25","venue":"HCMC"}'
wp post meta update <ID> custom_field "value"
```

## Elementor (data in postmeta)

```bash
wp post meta update <ID> _elementor_edit_mode builder
wp post meta update <ID> _elementor_data "$(cat page.elementor.json)"
wp post meta update <ID> _elementor_template_type wp-page
wp elementor flush-css <ID>   # if elementor CLI available; else regen on view
```

## Database / migration (guarded)

```bash
wp db export backup.sql
wp search-replace 'http://localhost:8888' 'https://acme.com' --dry-run     # preview
wp search-replace 'http://localhost:8888' 'https://acme.com' --all-tables-with-prefix
wp db query "SELECT COUNT(*) FROM wp_postmeta WHERE meta_key='_elementor_data'"
```

## Import / export (WXR)

```bash
wp import ./export.xml --authors=create
wp export --dir=./exports
```

## Flush

```bash
wp rewrite flush
wp cache flush
```
