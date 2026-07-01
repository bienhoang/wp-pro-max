---
phase: 4
title: "Plugin-Data Migration"
status: done
priority: P2
dependencies: [2, 3]
---

# Phase 4: Plugin-Data Migration

## Overview

Bring the second (and chattier) seed stage onto the same engine. `seed-plugin-data`
sets ACF field values, Elementor `_elementor_data`, and form config — today one
`post meta update` per field. One batch handles all of it.

## Requirements

- Functional: `plugin-data-seeding` SKILL generates `seed-plugin-data-payload.json`
  (pure JSON, same channel as Phase 3) plus strategy-specific sections:
  - `classic-acf` → `acf` entries (post → field → value) via `seed_ensure_acf_value`.
    Red-team H3: resolve the field via `acf_get_field`; if `update_field` can't run
    (group not loaded in the `eval-file` context), fall back to `update_post_meta`
    **and write the `_<field>` field-key reference row** so ACF recognizes it.
  - `page-builder` (Elementor) → `elementor` entries (post → `_elementor_data` JSON)
    via `seed_set_elementor_data`. Red-team H4: set the full meta set —
    `_elementor_data` (wp_slash'd), `_elementor_edit_mode=builder`,
    **`_elementor_template_type=wp-page`**, `_elementor_version`.
  - forms → CF7 / WPForms config (post + meta); guarded `wp db query` stays a
    last resort with the existing `--dry-run` preview rule (`CLAUDE.md:80`) — the
    batch runtime itself uses WP API only, never raw SQL.
- Functional (red-team M3): the **skill** runs the driver inline + merges the
  summary + marks `seed-plugin-data` progress (not build.md, not the heavy agent).
  ACF field-group JSON sync (acf-json) is unchanged — only field **values** move
  to the batch.
- Non-functional: idempotency preserved; strategy read from `strategy` up front,
  fail loudly if unset.

## Architecture

Reuses `seed-batch-runtime.php` + `seed-batch-run.sh` verbatim (DRY). The skill
only authors a different **JSON** payload. Elementor data is `wp_slash`'d in the
runtime and gets the full meta set (edit-mode + `wp-page` template type +
version); ACF resolves the field key via `acf_get_field` and writes the `_<field>`
reference row on the postmeta fallback. Form entries: prefer native option writes
inside the runtime; keep the guarded `wp db query --dry-run` path documented for
the rare config that needs it.

## Related Code Files

- Modify: `skills/plugin-data-seeding/SKILL.md` (JSON-payload generation per
  strategy; run driver **inline** + merge summary)
- Modify: `skills/plugin-data-seeding/references/*.md` (ACF / Elementor / forms
  emit to JSON payload; ACF `_<field>` row + Elementor meta trio documented)
- Verify (likely no edit): `commands/build.md` already delegates seed-plugin-data
  to the inline skill — keep run-logic in the skill, not the orchestrator.
- Modify: `agents/wp-data-engineer.md` (payload-author role covers this stage too)
- Reference: `scripts/seed-batch-runtime.php`, `scripts/seed-batch-run.sh`

## Implementation Steps

1. **(test-first)** Add `test/seeder/plugin-data-payload.test.sh`: fixtures per
   strategy (acf values, an elementor widget with quotes, a CF7 form) → assert the
   payload is valid JSON of the expected shape. The `_elementor_data` round-trip,
   ACF `_<field>` row, and zero-dup re-run are asserted in the **live** run.
2. Rewrite `plugin-data-seeding/SKILL.md` + references to emit JSON payloads per
   strategy and run the driver inline, instead of per-field WP-CLI loops.
3. Keep `commands/build.md` delegating to the inline skill (no run-logic added).
4. Live wp-env run per strategy on a sample: verify ACF values render (incl. the
   `_<field>` row), Elementor layout loads (meta trio set), form submits; re-run zero-dup.

## Success Criteria

- [ ] Payload is valid JSON; `seed-plugin-data` runs as one `eval-file` call; seconds not minutes.
- [ ] ACF values set idempotently incl. the `_<field>` reference row on fallback.
- [ ] Elementor `_elementor_data` round-trips intact + `_elementor_template_type=wp-page` and version meta set.
- [ ] Re-run (live): `created/updated:0` for unchanged data.
- [ ] Skill runs the driver inline; build.md run-logic untouched.
- [ ] `plugin-data-payload.test.sh` green; `claude plugin validate .` passes.
- [ ] Guarded `wp db query` still requires a `--dry-run` preview; runtime makes no raw SQL writes.

## Risk Assessment

- Elementor JSON escaping is the classic footgun → dedicated quote-bearing
  fixture + `get_post_meta` round-trip assertion (carried from Phase 2).
- ACF field-key vs field-name mismatch → resolve via `acf_get_field` when ACF
  loaded; fall back to the documented key. Test both.
- Strategy mis-detection seeds wrong payload → assert `strategy` read up front,
  fail loudly if unset.
