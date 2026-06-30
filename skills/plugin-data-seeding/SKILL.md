---
name: plugin-data-seeding
description: >-
  Seeds plugin-specific data into WordPress after content exists (stage
  `seed-plugin-data`). Strategy-adaptive, emitting a single pure-JSON payload the
  seed batch runtime applies in one `wp eval-file` call: for classic-acf it sets
  ACF field values (with the field-key reference) per post; for page-builder
  (Elementor) it writes `_elementor_data` plus the required meta trio; for forms
  it configures Contact Form 7 / WPForms posts and meta. All writes are
  idempotent (in-process WP API, check-before-write). Reads strategy, plugins,
  contentModel.fieldGroups; records seed.pluginDataPayload + seed.lastSummary. Use
  when seeding ACF values, Elementor builder data, or contact-form configuration,
  or when the pipeline reaches the `seed-plugin-data` stage.
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# Plugin Data Seeding (stage `seed-plugin-data`)

Fill in the data that lives **inside plugins**, after `seed-content` created the
posts/pages. What you seed depends on `strategy` and the selected `plugins`. This
stage emits a **pure-JSON payload** (`seed-plugin-data-payload.json`) and applies
it with the same batch engine as `seed-content` — one `wp eval-file` call,
idempotent, no per-field WP-CLI loops. The batch runtime uses the WP API only;
raw SQL stays a documented last resort with a `--dry-run`/`SELECT` preview.

## 0. Resume guard + setup

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh"
wpbuild_is_done seed-plugin-data && [[ "${1:-}" != "--force" ]] && { echo "seed-plugin-data done"; exit 0; }
wpbuild_progress seed-plugin-data in-progress
STRATEGY="$(wpbuild_get '.strategy')"
[[ -z "$STRATEGY" || "$STRATEGY" == "null" ]] && { echo "strategy unset — run analyze first"; exit 1; }
THEME="$(wpbuild_get '.theme.path')"
```

## 1. Route by strategy / plugins

| Condition | Payload section | Reference |
|-----------|-----------------|-----------|
| `strategy == classic-acf` | `acf[]` (post→field→value→key) | `references/acf-seeding.md` |
| `strategy == page-builder` and builder `elementor` | `elementor[]` (post→data tree) | `references/elementor-data.md` |
| forms plugin in `plugins[]` (`contact-form-7`, `wpforms-lite`) | `posts[]` + `meta` | `references/forms-seeding.md` |

A page-builder site may also need forms — emit all applicable sections into the
one payload.

## 2. classic-acf — field values

1. Ensure each `contentModel.fieldGroups[]` JSON is present in
   `<theme>/acf-json/group_<key>.json` (written by `scaffold`; ACF auto-syncs it).
   Field **definitions** come from JSON; this stage seeds **values**.
2. Emit one `acf[]` entry per post/field. Include the field **`key`** (from the
   group JSON `fields[].key`) so the runtime writes the `_<field>` reference row
   even when ACF is not loaded in the batch context:

```json
"acf": [
  { "post": "service-delivery", "field": "subtitle", "value": "Fast, reliable", "key": "field_subtitle_001" },
  { "post": "service-delivery", "field": "price",    "value": "1990",          "key": "field_price_001" }
]
```

Repeater/array values: pass the JSON array/object directly as `value`; the runtime
serializes via the WP API. Serialization rules + the `_<field>` pairing are in
`references/acf-seeding.md`.

## 3. page-builder — Elementor data

Emit one `elementor[]` entry per page; `data` is the **JSON array** layout tree
(section → column → widget), not a string. The runtime `wp_slash`es it for the DB
and sets the full meta set (`_elementor_data`, `_elementor_edit_mode=builder`,
`_elementor_template_type=wp-page`, `_elementor_version`):

```json
"elementor": [
  { "post": "home", "data": [ { "id": "a1b2c3d", "elType": "section", "elements": [ … ] } ] }
]
```

`data` must have unique 7-char `id`s on every element. **Persist the ids** (store
the tree in `./elementor/<slug>.json`) so unchanged pages produce identical JSON
and skip on re-run. The section→column→widget shape and HTML→widget mapping are in
`references/elementor-data.md`.

## 4. forms — Contact Form 7 / WPForms

Create the form post and its meta in the same payload:

```json
"posts": [
  { "slug": "contact-form", "title": "Contact form", "type": "wpcf7_contact_form",
    "content": "",
    "meta": { "_form": "<label>Your name [text* your-name]</label>…[submit \"Send\"]",
              "_mail": { "active": true, "recipient": "[admin_email]", "subject": "[your-subject]",
                         "sender": "[your-name] <wordpress@example.test>",
                         "body": "From: [your-name]\n\n[your-message]" } } }
]
```

`meta` values that are JSON objects/arrays (e.g. CF7 `_mail`) are serialized
correctly by the runtime's WP-API write, and compared array-aware so re-runs are
no-ops. **WPForms**: the form definition JSON is the post `content` of a `wpforms`
post. Wire the shortcode into the contact page during QA (`wp post update`), not
here. When a setting truly has no API path, use a **guarded** `wp db query` with
its `SELECT` preview first — never an unpreviewed mutation. Details + meta keys in
`references/forms-seeding.md`.

## 5. Run the batch inline + merge the summary

The **skill runs the batch itself** (thin coordinator — not the orchestrator, not
the heavy agent):

```bash
wpbuild_set '.seed.pluginDataPayload' '"seed-plugin-data-payload.json"'
bash "${CLAUDE_PLUGIN_ROOT}/scripts/seed-batch-run.sh" seed-plugin-data-payload.json
wpbuild_progress seed-plugin-data done "ACF values / elementor data / forms seeded"
```

The driver merges `seed.idempotencyKeys` (append+unique), `seed.lastRun`, and
`seed.lastSummary`, and fails loudly if the run did nothing or did not complete.
Re-running yields `created/updated:0` for unchanged data.

## Delegation

The **wp-data-engineer** agent authors the JSON payload (ACF values, the
Elementor widget tree, form definitions) — it does NOT run per-field WP-CLI loops.
**This skill** runs `seed-batch-run.sh` inline and merges the summary. Provide the
agent: target path, manifest path, the field/widget map, and acceptance criteria
(re-run yields no duplicate meta; Elementor renders; forms submit).

See also: `references/acf-seeding.md`, `references/elementor-data.md`,
`references/forms-seeding.md`.
