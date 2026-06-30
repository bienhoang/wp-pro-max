---
phase: 2
title: "Batch Runtime"
status: done
priority: P1
dependencies: [1]
---

# Phase 2: Batch Runtime

## Overview

The heart of the rewrite: `scripts/seed-batch-runtime.php` — a **single shipped,
reviewed** PHP file with idempotent helpers mirroring today's bash semantics but
running **in-process** via the WP API. It reads a **pure-JSON payload from stdin**
(`json_decode(file_get_contents('php://stdin'), true)`) — the payload is **never
executable PHP** (red-team C1/C2). Invoked once per stage via
`wp eval-file <path-to>/seed-batch-runtime.php` with the JSON piped to stdin.
Emits a sentinel-delimited JSON summary. Closes the orchestration gate from
Phase 1; the idempotency contract is closed by the mandatory live run here.

## Requirements

- Functional: read + validate the JSON payload from stdin; on malformed/empty
  JSON, emit an error summary and exit non-zero (no silent no-op).
- Functional: idempotent helpers, each checking existence before writing,
  recording a stable key, counting created/skipped, catching its own errors:
  - `seed_ensure_post($slug,$title,$content,$ptype,$template,$meta=[])` — folds
    meta in (kills the separate `post meta update` round-trip).
  - `seed_ensure_term`, `seed_ensure_menu` + `seed_ensure_menu_item_post` /
    `_custom` (dedupe by title), `seed_assign_menu_location`, `seed_set_front_page`,
    `seed_ensure_option`, `seed_import_media`, `seed_set_featured`,
    `seed_ensure_acf_value`, `seed_set_elementor_data`.
- Functional (red-team C4): summary emit must survive a **fatal**, not just a
  caught exception — register a `register_shutdown_function` that flushes the
  accumulated `idempotencyKeys`/counters/errors even when a non-`Throwable` fatal
  (OOM, timeout, plugin-hook fatal) aborts mid-batch. Try/catch-per-op alone is
  insufficient.
- Functional (red-team H2): wrap the summary in a unique sentinel
  (`WPBUILD_SUMMARY` + json + `WPBUILD_END`) so `WP_DEBUG` notices / banners on
  stdout cannot corrupt the parse.
- Non-functional (red-team #7): runtime uses the **WP API only** — no raw
  `$wpdb` writes — so it does not weaken the repo's "WP-CLI over raw SQL /
  dry-run" posture. Do not call the runtime "WP-CLI-compliant"; it is a reviewed
  shipped script executed via `eval-file`. The guarded `wp db query --dry-run`
  path (Phase 4) stays separate.
- Non-functional: no whole-batch abort — collect errors, continue. PHP 8.2 container.

## Architecture

Idempotency (in-process, native, microseconds):

| Op | Existence check | Write |
|----|-----------------|-------|
| post | `get_posts(['name'=>$slug,'post_type'=>$ptype,'post_status'=>'any'])` — match the bash `_seed_find_post_by_slug` semantics exactly (status `any`, correct `post_type`) so no new dupes | `wp_insert_post` + `update_post_meta` loop |
| term | `term_exists($slug,$tax)` | `wp_insert_term` |
| menu | `wp_get_nav_menu_object($name)` | `wp_create_nav_menu` |
| menu item | walk `wp_get_nav_menu_items` titles | `wp_update_nav_menu_item` |
| option | `get_option` compare | `update_option` |
| media | attachment query by `post_title` | `wp_insert_attachment` + `wp_generate_attachment_metadata` (path resolution per red-team H1 below) |
| featured | `get_post_meta(_thumbnail_id)` compare | `set_post_thumbnail` |
| acf (H3) | `acf_get_field($key)` to resolve; `function_exists('update_field') && group registered ? update_field : update_post_meta` — and on the postmeta fallback **also write the `_<field>` = field-key reference row** (ACF convention) | — |
| elementor (H4) | compare `_elementor_data` | `update_post_meta('_elementor_data', wp_slash($json))` + `_elementor_edit_mode=builder` + **`_elementor_template_type=wp-page`** + `_elementor_version` |

**Execution model (red-team C1/C2 — corrected):** the runtime is the **only**
PHP file and it is **shipped, not generated**. It is invoked via `wp eval-file
seed-batch-runtime.php` while the **JSON payload is piped to stdin**. The runtime
does `json_decode(file_get_contents('php://stdin'), true)` → `seed_run($payload)`.
There is no PHP concatenation, no `$SEED_PAYLOAD` PHP file, no second `<?php`
tag — the earlier "prepend runtime to payload" design was unparseable (two
`<?php` files) and is dropped.

**Media path (red-team H1; validated):** `.wp-env.json` mounts only the theme
dir; the batch runs with CWD = WP root, so relative `assets/...` from
`optimization.outputDir` won't resolve. **Decision: mount `optimization.outputDir`
in `.wp-env.json`** (env-setup adds the mapping) so assets resolve by absolute
container path. `payload.mediaPathPrefix` (the `WP_MEDIA_PATH_PREFIX` heir,
`seed-helpers.sh:256-260`) is kept only as an optional override for assets outside
the mount. Remote URLs use `media_sideload_image`. A failed import must surface in
`errors[]` — never a silent imageless "success".
<!-- Updated: Validation Session 1 - mount outputDir as primary media-path mechanism -->

## Related Code Files

- Create: `scripts/seed-batch-runtime.php` (the only PHP; reads JSON from stdin)
- Create: `scripts/seed-batch-run.sh` (driver: pipe JSON → runtime, parse sentinel
  summary, append+unique key merge)
- Reference (semantics to preserve): `scripts/seed-helpers.sh:66-75,127-307`
  (idempotency keys append+unique, lookup semantics, `WP_MEDIA_PATH_PREFIX`)
- Reference (the merge bug to avoid): `scripts/manifest-core.sh:85` (`. * (value)` replaces arrays)
- Modify (validated decision 1): `scripts/wp-env-bootstrap.sh` `mappings` block
  (`wp-env-bootstrap.sh:89`) to also mount `optimization.outputDir`, so media
  resolves by absolute container path.
- Consumes: `scripts/wp-cli-runner.sh` (Phase 1) for execution

## Implementation Steps

1. **(test-first)** Live-run fixtures (the real idempotency gate, red-team C6):
   a 3-page + 2-CPT JSON payload + a re-run script asserting create-then-skip,
   folded meta, menu-item dedupe, option-only-on-diff, and an `errors[]` entry on
   a forced bad insert. These run against a throwaway wp-env (Docker present).
2. Implement helpers + stdin `json_decode` + `seed_run()` +
   `register_shutdown_function` summary + sentinel wrapping in
   `seed-batch-runtime.php`. Lint via container: `<runner> php -l` (no host PHP).
3. Wire `scripts/seed-batch-run.sh` that: pipes a **JSON payload file** to
   `wp_cli eval-file <runtime.php>`, extracts the summary **between the sentinels**,
   merges `idempotencyKeys` into `wp-build.json` with **append + unique**
   (`(.seed.idempotencyKeys + $new) | unique` — NOT jq `*`, which replaces arrays
   per `manifest-core.sh:85`, red-team C3), sets `seed.lastRun` + `seed.lastSummary`.
   Fail loudly if the summary is absent or the payload had ops but `created+skipped==0`.
4. Run the stub orchestration test (Phase 1) → green. Then the **mandatory live
   acceptance run**: seed the fixture, assert counts; **re-run asserts
   `created:0`** (zero-dup); kill the run mid-batch (simulate fatal) and assert the
   shutdown function still wrote partial keys to the manifest.

## Success Criteria

- [ ] Payload is pure JSON read from stdin; malformed/empty JSON → error summary + non-zero exit (no silent no-op).
- [ ] Stub orchestration test green (single invocation, sentinel parse, stdin non-empty).
- [ ] **Live wp-env fixture: correct counts first run, `created:0` on re-run** (the idempotency gate).
- [ ] Simulated fatal mid-batch: shutdown function still emits summary; partial keys reach the manifest.
- [ ] Forced-error op appears in `errors[]`; batch still completes other ops.
- [ ] Container `php -l` clean; summary parses from between sentinels with `jq -e`.
- [ ] Key merge is append + unique (verified: prior/other-stage keys survive a merge).
- [ ] `seed.idempotencyKeys`/`lastRun`/`lastSummary` written once per run; runtime makes no raw `$wpdb` writes.

## Risk Assessment

- `wp eval-file <file>` + stdin payload: stdin reading confirmed empirically by
  red-team; runner adds `-i`. Validate the `wp-env run cli` fallback forwards
  stdin too (red-team H6) — if it can't, restrict to docker-exec and fail loud.
- ACF (red-team H3): `update_field` silently no-ops if the field group isn't
  loaded in the `eval-file` context; resolve the field via `acf_get_field` and, on
  the postmeta fallback, write both the value and the `_<field>` key reference row.
- Elementor (red-team H4): JSON is `wp_slash`'d for the DB, and the required meta
  trio (`_elementor_edit_mode`, `_elementor_template_type=wp-page`,
  `_elementor_version`) is set. The old "escape JSON into a PHP literal" risk is
  gone — payload is JSON, not PHP. Assert `_elementor_data` round-trips via
  `get_post_meta` with a quote-bearing fixture.
- Media path (red-team H1, validated): primary mechanism is an `outputDir` mount
  in `.wp-env.json`; `mediaPathPrefix` is the optional override. Failed imports
  land in `errors[]`, never a silent imageless success.
