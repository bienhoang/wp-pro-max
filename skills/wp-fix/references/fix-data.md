# Playbook: data — ACF fields, Elementor, seed drift

Symptoms: "field trống", ACF returns `null`, an Elementor page is blank or
reverts after saving, seeded content is duplicated or missing.

All reads below are `SELECT`. **Any write follows `fix-runtime.md`'s DB path:
matching `SELECT` preview → `wp db export` → confirm the row set → write.**
`wp db query` has no `--dry-run`.

## ACF field returns null

The dominant cause is a **field-key mismatch**, not a missing value. ACF stores
every field twice: the value under the field *name*, and a reference to the field
*key* under `_<name>`. Break the key reference and `get_field()` returns `null`
while the value sits in the database, plainly visible — which is exactly why this
one wastes so much time.

The mechanics are already documented — **read, do not restate**:
`skills/plugin-data-seeding/references/acf-seeding.md:28-45` (the
`_<name>` → `field_xxx` reference pair) and `:71-83` (repeater sub-field keys).

### Diagnose

```bash
# 1. What does ACF return, and what is actually stored?
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" eval '$p = url_to_postid("http://localhost:8888/about/"); var_dump(get_field("subtitle", $p));'
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" post meta list <post-id> --keys=subtitle,_subtitle
```

Read the result:

| `subtitle` | `_subtitle` | Diagnosis |
|---|---|---|
| has a value | missing | **The key reference was never written.** The classic seed bug |
| has a value | `field_wrong_id` | Key points at a field that does not exist in the group |
| missing | missing | Genuinely never seeded — a seed problem, not a fix problem |
| has a value | correct key | Not a storage bug: check the field group's **location rules** actually match this post |

```bash
# 2. Is ACF even loaded? get_field() on an inactive ACF is a fatal, not a null.
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" eval 'echo function_exists("get_field") ? "ACF OK" : "ACF NOT LOADED";'

# 3. What key does the group JSON actually declare? This is the source of truth.
jq -r '.fields[] | "\(.name) -> \(.key)"' "$THEME_PATH/acf-json/group_*.json"
```

### Fix

Prefer the API over raw SQL — `update_field()` with the **key** writes both rows
correctly and is idempotent:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" eval 'update_field("field_subtitle_001", "Fast, reliable delivery", 42);'
```

Never hand-write `_<name>` rows with `db query` when ACF is loaded — the API
exists precisely to keep the pair consistent, and a manual write is how the pair
drifted in the first place. Raw SQL is only for an ACF-not-loaded environment,
and then with the full DB guard.

If many posts drift, the seed payload is wrong: fix
`seed.pluginDataPayload` and re-run `seed-plugin-data` rather than patching post
by post. `wp-fix` repairs a defect; it does not substitute for a correct seed.

## Elementor: blank page, or reverts after save

Elementor renders from `_elementor_data` (JSON in postmeta) and ignores
`post_content`. A page that is blank in the builder but has content in the editor
is that split.

The required meta trio is documented at
`skills/plugin-data-seeding/references/elementor-data.md:13-20` — `_elementor_data`
alone is not enough; without `_elementor_edit_mode=builder` and
`_elementor_template_type`, Elementor does not recognise the page as its own and
falls back to the theme template.

```bash
# What is present?
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" post meta list <post-id> --keys=_elementor_data,_elementor_edit_mode,_elementor_template_type,_elementor_version

# Is _elementor_data valid JSON? Invalid JSON renders blank, silently.
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" post meta get <post-id> _elementor_data | jq -e . >/dev/null && echo "valid JSON" || echo "CORRUPT"
```

| Finding | Cause |
|---|---|
| `_elementor_data` present, trio incomplete | Seeded data-only — Elementor ignores the page |
| `_elementor_data` is not valid JSON | Corrupt; restore from `fix.backupDir` or re-seed |
| Data present, page reverts after every save | **Element `id`s are not stable across runs.** Elementor re-generates them and the seed overwrites the user's edit on the next run |
| Double-escaped JSON (`\"` inside the value) | Written through a layer that escaped it again — a raw `db query` write instead of the API |

Element `id` stability matters: `elementor-data.md` requires persisting generated
ids so unchanged pages skip. If ids churn, every re-seed clobbers user edits —
which the user experiences as "my changes keep reverting", not as a seed bug.

## Seed idempotency drift

Duplicated content means `seed.idempotencyKeys` no longer matches what is in the
database — the check-before-create lookup misses and creates a second copy.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh" get '.seed.idempotencyKeys'
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" post list --post_type=page --field=post_name | sort | uniq -d
```

Duplicate slugs → the keys drifted (usually a slug edited in wp-admin after
seeding). The fix is reconciling the manifest keys with reality, **not** deleting
posts. Deleting the wrong duplicate destroys the copy the user actually edited —
`AskUserQuestion` with both post IDs, their modified dates, and let the user pick.

## Verify

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" eval 'var_dump(get_field("subtitle", 42));'
```

The field now returns its value, and re-running the seed reports `created:0`
(`references/manifest-contract.md:71`). If the seed still creates rows, the
idempotency key is still wrong — the symptom is fixed, the cause is not.
