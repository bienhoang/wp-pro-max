# Field Group Examples (per strategy)

Concrete, drop-in examples for a `service` CPT with fields: subtitle (text),
icon (text), price (number), and a repeater of feature rows.

## classic-acf — ACF local JSON

Save to `<theme>/acf-json/group_service_details.json`. ACF auto-syncs files in
that folder. `key` values must be stable and unique.

```json
{
  "key": "group_service_details",
  "title": "Service Details",
  "fields": [
    { "key": "field_service_subtitle", "label": "Subtitle", "name": "subtitle", "type": "text" },
    { "key": "field_service_icon", "label": "Icon", "name": "icon", "type": "text", "instructions": "Dashicon or SVG name" },
    { "key": "field_service_price", "label": "Price", "name": "price", "type": "number", "prepend": "$" },
    {
      "key": "field_service_features", "label": "Features", "name": "features", "type": "repeater",
      "button_label": "Add feature",
      "sub_fields": [
        { "key": "field_service_feature_text", "label": "Feature", "name": "text", "type": "text" }
      ]
    }
  ],
  "location": [[{ "param": "post_type", "operator": "==", "value": "service" }]],
  "active": true,
  "show_in_rest": true
}
```

Template read (PHP): `the_field('subtitle')`, `get_field('price')`, repeater via
`have_rows('features')` / `the_sub_field('text')`.

## block-fse — block bindings (WP 6.5+)

Register meta on the CPT (in `functions.php` or via scaffold), then bind core
blocks to it in a block template/pattern. Meta registration:

```php
register_post_meta('service', 'subtitle', [
  'show_in_rest' => true, 'single' => true, 'type' => 'string',
]);
register_post_meta('service', 'price', [
  'show_in_rest' => true, 'single' => true, 'type' => 'number',
]);
```

Binding in block markup (`templates/single-service.html`):

```html
<!-- wp:paragraph {"metadata":{"bindings":{"content":{"source":"core/post-meta","args":{"key":"subtitle"}}}}} -->
<p></p>
<!-- /wp:paragraph -->
```

Repeaters are not native; model repeating features as a child block pattern or a
serialized meta consumed by a custom block.

## page-builder — dynamic fields

Store field values in postmeta (ACF or plain meta), then reference via the
builder's dynamic tags.

Elementor dynamic tag (in `_elementor_data` JSON, simplified):

```json
{
  "settings": {
    "title": "",
    "__dynamic__": { "title": "[elementor-tag id=\"abc\" name=\"acf-text\" settings=\"%7B%22key%22%3A%22subtitle%22%7D%22]" }
  }
}
```

Bricks: bind an element to `{acf_subtitle}` or `{cf_price}` in the element
settings. The seed stage writes the meta; the builder renders it at runtime.

## Naming conventions
- Field `name`: `snake_case`, matches the meta key used in templates and seeds.
- ACF `key`: globally unique, prefixed `field_<cpt>_<name>` so syncing is stable.
- Record all meta keys you introduce; the seed stage reuses them as part of the
  idempotency contract.
