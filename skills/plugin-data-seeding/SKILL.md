---
name: plugin-data-seeding
description: >-
  Seeds plugin-specific data into WordPress after content exists (stage
  `seed-plugin-data`). Strategy-adaptive: for classic-acf it loads ACF field
  group JSON (acf-json sync) and sets field values per post; for page-builder
  (Elementor) it builds _elementor_data JSON from the analyzed/optimized HTML and
  writes the Elementor postmeta; for forms it configures Contact Form 7 / WPForms
  entries via WP-CLI or a guarded, dry-run-previewed wp db query. All writes are
  idempotent via scripts/seed-helpers.sh. Reads strategy, plugins,
  contentModel.fieldGroups; writes seed.pluginDataScript. Use when seeding ACF
  values, Elementor builder data, or contact-form configuration, or when the
  pipeline reaches the `seed-plugin-data` stage.
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# Plugin Data Seeding (stage `seed-plugin-data`)

Fill in the data that lives **inside plugins**, after `seed-content` created the
posts/pages. What you seed depends on `strategy` and the selected `plugins`.
Every write goes through `scripts/seed-helpers.sh` (idempotent). Raw SQL is a
last resort and always runs a `--dry-run`/`SELECT` preview first (per contract).

## 0. Resume guard + setup

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh"
wpbuild_is_done seed-plugin-data && [[ "${1:-}" != "--force" ]] && { echo "seed-plugin-data done"; exit 0; }
wpbuild_progress seed-plugin-data in-progress
STRATEGY="$(wpbuild_get '.strategy')"
THEME="$(wpbuild_get '.theme.path')"
```

## 1. Route by strategy / plugins

| Condition | Do | Reference |
|-----------|----|-----------|
| `strategy == classic-acf` | Sync ACF field group JSON + set field values | `references/acf-seeding.md` |
| `strategy == page-builder` and builder `elementor` | Build `_elementor_data` per page | `references/elementor-data.md` |
| forms plugin in `plugins[]` (`contact-form-7`, `wpforms-lite`) | Create/configure forms | `references/forms-seeding.md` |

Run the applicable branches; a page-builder site may also need forms.

## 2. classic-acf — field values

1. Ensure each `contentModel.fieldGroups[]` JSON is present in
   `<theme>/acf-json/group_<key>.json` (written by `scaffold`). Trigger ACF sync
   so the group is registered: `wp acf sync` (if ACF-CLI present) or load the
   admin once. Field **definitions** come from JSON; this stage seeds **values**.
2. For each seeded post, set values with the helper (keyed, idempotent):

```bash
ensure_acf_value "$service_id" subtitle "Fast, reliable delivery"
ensure_acf_value "$service_id" price    "1990"
```

   Or seed at creation time with `--meta_input` (the cheatsheet pattern) when the
   post is first made. For full ACF fidelity also set the field-key reference
   meta (`_<field>` = `field_xxx`) so the admin shows the value against the field;
   see `references/acf-seeding.md` for the exact pairing and repeater/array
   serialization rules.

## 3. page-builder — Elementor data

Build `_elementor_data` (a JSON array of sections → columns → widgets) for each
page from the analyzed sections + optimized HTML, then write the three postmeta
keys. Use the helper so re-runs are safe:

```bash
# elementor JSON authored to ./elementor/<slug>.json
ensure_acf_value "$home_id" _elementor_data       "$(cat ./elementor/home.json)"
ensure_acf_value "$home_id" _elementor_edit_mode  builder
ensure_acf_value "$home_id" _elementor_template_type wp-page
```

`_elementor_data` must be **valid minified JSON** with unique element `id`s. The
section→column→widget shape, widget settings map, and id rules are documented in
`references/elementor-data.md`. After writing, flush Elementor CSS if the CLI is
available (`wp elementor flush-css`), else it regenerates on first view.

## 4. forms — Contact Form 7 / WPForms

- **Contact Form 7**: each form is a `wpcf7_contact_form` post; the template +
  mail settings live in postmeta. Create with `ensure_post` keyed by slug, then
  set the `_form` / `_mail` meta. Map the CF7 shortcode into the contact page
  body. Details + meta keys in `references/forms-seeding.md`.
- **WPForms**: form definition is JSON in the `wpforms` CPT `post_content`.
- When a setting cannot be set via WP-CLI, use a **guarded** `wp db query`:
  run the `SELECT` preview first, show the rows, then run the `INSERT`/`UPDATE`
  only after confirming. Never run an unpreviewed destructive query.

## 5. Generate + run the script

Author `seed-plugin-data.sh` in the target project (sources `seed-helpers.sh`),
recording exactly the meta written. Then:

```bash
wpbuild_set '.seed.pluginDataScript' '"seed-plugin-data.sh"'
bash ./seed-plugin-data.sh
wpbuild_progress seed-plugin-data done "ACF values / elementor data / forms seeded"
```

## Delegation

Delegate the actual WP-CLI/DB execution and any guarded `wp db query` to the
**wp-data-engineer** agent (it owns dry-run discipline and data serialization).
Provide: target path, manifest path, the generated script, the field/widget map,
and acceptance criteria (re-run yields no duplicate meta; Elementor renders;
forms submit).

See also: `references/acf-seeding.md`, `references/elementor-data.md`,
`references/forms-seeding.md`.
