# Elementor Data — building `_elementor_data` from HTML

Elementor stores a page's layout as a single postmeta key, `_elementor_data`,
holding a **JSON array** of elements. The renderer reads it on the front end.
This stage converts the analyzed sections + optimized HTML of each page into
that JSON and writes the three required meta keys.

## Required postmeta per page

| meta_key | value | meaning |
|----------|-------|---------|
| `_elementor_data` | minified JSON array (see shape) | the layout tree |
| `_elementor_edit_mode` | `builder` | mark page as Elementor-built |
| `_elementor_template_type` | `wp-page` | template kind (`wp-page` / `wp-post`) |
| `_elementor_version` | e.g. `3.x.x` | optional; Elementor backfills on edit |

You do **not** write these keys individually — emit one `elementor[]` payload
entry per page and the runtime sets the full meta set (`_elementor_data` wp_slash'd,
`_elementor_edit_mode=builder`, `_elementor_template_type=wp-page`,
`_elementor_version`):

```json
{ "post": "home", "data": [ { "id": "a1b2c3d", "elType": "section", "elements": [ … ] } ] }
```

`data` is the JSON layout array itself (not a string) — JSON escaping handles the
quotes safely, so the old "escape JSON into a PHP literal" footgun is gone.

## The element tree shape

`_elementor_data` is an array of **section** elements. Each section contains
**columns**; each column contains **widgets**:

```json
[
  {
    "id": "a1b2c3d",
    "elType": "section",
    "settings": { "layout": "boxed", "background_background": "classic" },
    "elements": [
      {
        "id": "c4d5e6f",
        "elType": "column",
        "settings": { "_column_size": 100, "_inline_size": null },
        "elements": [
          {
            "id": "f7a8b9c",
            "elType": "widget",
            "widgetType": "heading",
            "settings": { "title": "Welcome to Acme", "header_size": "h1" },
            "elements": []
          },
          {
            "id": "0d1e2f3",
            "elType": "widget",
            "widgetType": "text-editor",
            "settings": { "editor": "<p>Design that ships.</p>" },
            "elements": []
          }
        ]
      }
    ]
  }
]
```

### Rules

- **Every** element needs a unique `id`: a 7-char lowercase hex string. Generate
  with `openssl rand -hex 4 | cut -c1-7` or a counter; uniqueness within the page
  is what matters. Reusing ids breaks the editor.
- Nesting is strict: `section → column → widget`. Inner sections are allowed as
  a widget-level `elType: "section"` inside a column.
- `_column_size` is the column width in % (columns in a section should sum to
  100). Single-column sections use `100`.
- Settings keys are widget-specific; unknown keys are ignored by Elementor, so
  emit a minimal valid set and let the user refine in the editor.

## HTML → widget mapping

| Source HTML | widgetType | key settings |
|-------------|------------|--------------|
| `<h1>`–`<h6>` | `heading` | `title`, `header_size` (`h1`…`h6`) |
| `<p>`, rich text | `text-editor` | `editor` (HTML string) |
| `<img>` | `image` | `image: {id, url}` (id from media import) |
| `<a class="btn">` / CTA | `button` | `text`, `link: {url, is_external, nofollow}` |
| `<ul>/<ol>` icon list | `icon-list` | `icon_list: [{text, ...}]` |
| `<hr>` / spacing | `divider` / `spacer` | `gap` |
| video embed | `video` | `youtube_url` / `video_type` |
| raw/unknown block | `html` | `html` (verbatim markup) — safe fallback |

Map each analyzed top-level section to one Elementor `section`; its inner block
columns map to `column`s; leaf content nodes map to widgets via the table.
When in doubt, wrap the original markup in an `html` widget so nothing is lost.

## Authoring + validating the JSON

1. Build the tree per page into `./elementor/<slug>.json`.
2. Validate it parses and is an array: `jq -e 'type=="array"' ./elementor/<slug>.json`.
3. Reference that tree as the `data` array of an `elementor[]` payload entry. The
   runtime `wp_slash`es it on write (update_post_meta's wp_unslash cancels it), so
   the stored JSON round-trips intact — no manual slash-escaping.
4. After seeding all pages, regenerate CSS:
   `wp elementor flush-css` (if Elementor CLI present) — otherwise Elementor
   rebuilds CSS on first page view.

## Idempotency

The runtime compares the stored `_elementor_data` against the payload's `data`
and only updates on change. Keep the generated ids **stable** across runs
(persist them in `./elementor/<slug>.json`) so unchanged pages produce identical
JSON and skip the write (`updated:0`).
