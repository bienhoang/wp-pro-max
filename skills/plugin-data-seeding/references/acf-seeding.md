# ACF Seeding — field group JSON sync + value seeding

ACF (Advanced Custom Fields) splits into two concerns:

1. **Field definitions** — the field group, stored as JSON in
   `<theme>/acf-json/group_<key>.json` (written by the `scaffold` stage; ACF
   auto-syncs it into the DB on admin load).
2. **Field values** — per-post data, stored in `wp_postmeta`. This stage seeds
   values, idempotently, via `ensure_acf_value`.

## 1. Register the definitions

ACF "Local JSON" auto-sync registers any group found in `acf-json/`. To force it
from CLI when available:

```bash
wp acf sync --all          # acf-cli / ACF PRO; registers/updates groups from JSON
```

If `wp acf` is unavailable, loading any admin page triggers the sync. Verify:

```bash
wp post list --post_type=acf-field-group --field=post_title
```

## 2. How ACF stores a value (the meta pairing)

For a field named `subtitle` with field key `field_subtitle_001`, ACF writes
**two** meta rows per post:

| meta_key | meta_value |
|----------|------------|
| `subtitle` | the actual value |
| `_subtitle` | `field_subtitle_001` (the field key reference) |

`get_field('subtitle')` works off this pairing, and the admin shows the value in
the right field. Seed both:

```bash
ensure_acf_value "$post_id" subtitle  "Fast, reliable delivery"
ensure_acf_value "$post_id" _subtitle "field_subtitle_001"
```

The field key comes from the group JSON (`fields[].key`). When you only need the
value readable by templates and not editable in admin, the value row alone is
enough — but seed the `_field` reference for full fidelity.

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

Seed each row explicitly with `ensure_acf_value`. For complex/serialized values
(link, group), prefer setting via PHP at seed time to get correct serialization:

```bash
wp eval 'update_field("cta", ["title"=>"Buy","url"=>"/checkout","target"=>""], 1234);'
```

`update_field()` (ACF API) serializes correctly and writes the `_field`
reference for you — preferred for non-scalar fields. Keep it idempotent by
guarding with a `get_field` check, mirroring `ensure_acf_value`.

## 4. Seeding at post-create time

When a post is first created you can batch scalar meta with `--meta_input`:

```bash
wp post create --post_type=service --post_title="Delivery" --post_status=publish \
  --meta_input='{"subtitle":"Fast","_subtitle":"field_subtitle_001","price":"1990"}'
```

This is equivalent to a series of `ensure_acf_value` calls but only valid the
first time the post is created; for existing posts use the helper.

## 5. Idempotency

`ensure_acf_value` reads the current meta and only writes when it differs, and
records `meta:<post-id>:<field>` in `seed.idempotencyKeys`. Re-running the
generated `seed-plugin-data.sh` therefore makes no changes once values match.
