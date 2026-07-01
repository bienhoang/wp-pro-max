# ACF Seeding — field group JSON sync + value seeding

ACF (Advanced Custom Fields) splits into two concerns:

1. **Field definitions** — the field group, stored as JSON in
   `<theme>/acf-json/group_<key>.json` (written by the `scaffold` stage; ACF
   auto-syncs it into the DB on admin load).
2. **Field values** — per-post data, stored in `wp_postmeta`. This stage seeds
   values idempotently via `acf[]` entries in the seed payload.

## 1. Register the definitions

ACF "Local JSON" auto-sync registers any group found in `acf-json/`. To force it
from CLI when available:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" acf sync --all   # acf-cli / ACF PRO; registers/updates groups from JSON
```

If `wp acf` is unavailable, loading any admin page triggers the sync. Verify:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" post list --post_type=acf-field-group --field=post_title
```

## 2. How ACF stores a value (the meta pairing)

For a field named `subtitle` with field key `field_subtitle_001`, ACF writes
**two** meta rows per post:

| meta_key | meta_value |
|----------|------------|
| `subtitle` | the actual value |
| `_subtitle` | `field_subtitle_001` (the field key reference) |

`get_field('subtitle')` works off this pairing, and the admin shows the value in
the right field. One `acf[]` payload entry seeds both rows — pass the field
**`key`** and the runtime writes the `_<field>` reference for you (even when ACF
is not loaded in the batch context):

```json
{ "post": "<slug>", "field": "subtitle", "value": "Fast, reliable delivery", "key": "field_subtitle_001" }
```

The field key comes from the group JSON (`fields[].key`). When ACF IS loaded, the
runtime uses `update_field` (which writes the `_<field>` row itself). When you
only need the value readable by templates and not editable in admin, omit `key`
(the value row alone is written) — but include `key` for full fidelity.

## 3. Field-type serialization

| ACF field type | Stored value |
|----------------|--------------|
| text / textarea / wysiwyg | the string |
| number | numeric string |
| true_false | `1` / `0` |
| select / radio | the choice value |
| image / file | the attachment **ID** (integer) |
| link | a PHP-serialized array `{title,url,target}` |
| date_picker | `Ymd` (e.g. `20261225`) |
| repeater | a count row + indexed sub-field rows (see below) |

### Repeater fields

A repeater `items` with 2 rows of sub-field `label` stores:

| meta_key | meta_value |
|----------|------------|
| `items` | `2` (row count) |
| `items_0_label` | first label |
| `_items_0_label` | sub-field key |
| `items_1_label` | second label |
| `_items_1_label` | sub-field key |

Emit one `acf[]` entry per row. For complex/serialized values (link, group,
repeater), pass the JSON array/object **directly** as `value` — the runtime
serializes via the WP API (`update_field` when ACF is loaded, else
`update_post_meta`, which serializes arrays correctly):

```json
{ "post": "<slug>", "field": "cta",
  "value": { "title": "Buy", "url": "/checkout", "target": "" },
  "key": "field_cta_001" }
```

The old per-field `wp eval`/`update_field` CLI loops are gone — the batch runtime
applies every entry in one call.

## 4. Idempotency

The runtime reads current meta and writes only when it differs (array-aware
comparison for serialized values), recording `meta:<post-id>:<field>` in
`seed.idempotencyKeys`. Re-running the payload therefore makes no changes once
values match (`updated:0`).
