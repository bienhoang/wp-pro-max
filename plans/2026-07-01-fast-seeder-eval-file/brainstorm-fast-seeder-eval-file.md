# Brainstorm — Fix slow WordPress seeder (eval-file PHP batch)

- **Date:** 2026-07-01
- **Repo:** wp-pro-max (Claude Code plugin)
- **Topic:** seeder chạy quá lâu (stages `seed-content` + `seed-plugin-data`)
- **Modes:** none (no `--html` / `--wiki`)
- **Decisions:** scope = both (unblock run + fix plugin); approach = C+D (eval-file PHP batch + decouple author/execute); coverage = both seed stages; engine = replace `seed-helpers.sh` with PHP generator; idempotency keys = PHP emits JSON summary → bash merges once.

## Problem statement

Seeding a build takes minutes (~9 min observed) and is fragile (heavy agent died mid-run from API overload). Two independent cost multipliers:

1. **Per-call container startup.** Runner = `wp-env run cli wp` / `npx @wordpress/env run cli` spins up a fresh Docker container per command (~3.7s). `docker exec` into the live `cli` container = ~1.3s.
2. **Chatty idempotency.** Every `ensure_*` in `scripts/seed-helpers.sh` does lookup → create → (meta) → `jq` rewrite of the manifest, *per record*. ~42 records ⇒ 150+ `wp` calls.

Runner swap fixes only (1). Root cause is process-per-command.

## Requirements (locked)

- **Expected output:** seeding for both stages runs in **one `wp eval-file` invocation per stage**, in seconds; idempotent on re-run (0 duplicates); orchestrator runs the batch (agent death cannot lose a run).
- **Acceptance:**
  - `seed-content` (~42 records) finishes in seconds, not minutes.
  - Re-run = 0 duplicate posts/menu items/terms/media (in-process idempotency).
  - PHP errors don't abort the whole batch silently — collected + reported; partial success still re-runnable.
  - `claude plugin validate .` passes; `bash -n` / `node --check` / `php -l` clean; behavioral test against live wp-env matches manifest counts.
- **Scope boundary (OUT):** no change to canonical stage order/gates; not touching `migrate-urls.sh` / ship path (uses `WP_CLI_RUN` over SSH — leave as is); no new manifest schema fields beyond existing `seed.*`.
- **Constraints:** WP-CLI only (no raw SQL — `eval-file` runs PHP via WP API, compliant); zsh-safe sourced scripts (no top-level `set -euo pipefail`, no `status` local, sourcing guards); idempotency keys still recorded in `seed.idempotencyKeys`; never write WP output into this repo.
- **Touchpoints:** `scripts/seed-helpers.sh` (retire), new `scripts/wp-cli-runner.sh` + `scripts/seed-batch-runtime.php`, skills `content-seeding` + `plugin-data-seeding`, agent `wp-data-engineer`, `commands/build.md` (orchestrator runs batch), `CLAUDE.md`/README references.

## Evaluated approaches

| | Speedup | Effort | Architecture | Notes |
|---|---|---|---|---|
| A — runner swap (docker exec, auto-detect) | ~3× | low | unchanged | still 150 calls (~3 min) |
| B — fold `--meta_input` + batch manifest writes | +2-3× on A | med | bash kept | still chatty |
| **C — single `wp eval-file` PHP batch** ⭐ | **50-100×** | high | engine rewrite | 1 container startup; WP-CLI-compliant |
| D — decouple author/execute (orchestrator runs) | robustness | low | orthogonal | do regardless |

**Chosen: C + D.** A is folded in as the shared runner for any remaining ad-hoc `wp` calls.

## Chosen design

### 1. Shared runner — `scripts/wp-cli-runner.sh`
Resolve runner once, auto-detect the live container (no hardcoded hash):
- `WP_CLI_RUN` set → honor it (SSH/remote/ship still work).
- else live container `docker ps --filter name=cli --format '{{.Names}}'` found → `docker exec -i <name> wp`.
- else fallback `wp-env run cli wp`.
Zsh-safe argv build (reuse the existing `${=...}` vs `read -ra` pattern). Sourced by seed scripts and any stage doing WP-CLI.

### 2. Batch runtime — `scripts/seed-batch-runtime.php`
Idempotent in-process helpers mirroring today's bash semantics, all native WP API:
- `seed_ensure_post($slug,$title,$content,$ptype,$template,$meta=[])` — `get_posts(name,post_type,any)`; `wp_insert_post`; folds `$meta` via `update_post_meta`; returns ID.
- `seed_ensure_term` (`term_exists`/`wp_insert_term`), `seed_ensure_menu` + items (`wp_get_nav_menu_object`, `wp_update_nav_menu_item`, dedupe by title), `seed_set_front_page`, `seed_ensure_option`, `seed_import_media` (`wp_insert_attachment` + `wp_generate_attachment_metadata` from mounted theme assets path), `seed_set_featured`, `seed_ensure_acf_value` (`update_field` if ACF loaded, else postmeta with field key), `seed_set_elementor_data` (`wp_slash(json)` → `_elementor_data` + `_elementor_edit_mode=builder`).
- Wrap each op in try/catch → collect errors, **continue**.
- End: `echo json_encode(['idempotencyKeys'=>[...],'created'=>N,'skipped'=>M,'errors'=>[...],'ids'=>{...}])`.

DRY: runtime lives in one shipped `.php`; the generator **prepends** it to the data payload to form one self-contained stream piped via `wp eval-file -` (stdin) — avoids container mount-path concerns for the script itself.

### 3. Generators (skills)
- `content-seeding`: author a **PHP data payload** (pages/posts/terms/menus arrays) with body HTML embedded directly in the payload (drops the `content/*.html` round-trip; optionally still write them for human review). Media points at the **mounted** theme assets path (reachable in container).
- `plugin-data-seeding`: same engine — ACF values (`update_field`), Elementor `_elementor_data`, CF7/WPForms config — one batch.

### 4. Decouple (D)
- `wp-data-engineer` agent: **authors the payload only**, no long WP-CLI loops.
- Orchestrator (`build` skill/command): concatenates runtime + payload, runs `wp eval-file -`, captures stdout JSON, merges `idempotencyKeys` into `wp-build.json` **once** via `jq`, marks progress. Agent death → no run lost.

## Idempotency model (PHP, in-process, microseconds)
posts→`get_posts(name)`; terms→`term_exists`; menus→`wp_get_nav_menu_object` + item-title walk; options→`get_option` compare; media→attachment-by-title query; featured/meta→`get_post_meta` compare. Same stable keys recorded into `seed.idempotencyKeys`.

## Risks & mitigations
- **Whole-batch abort on PHP fatal** → per-op try/catch + error collection; re-run safe.
- **stdin support** → `wp eval-file -` reads stdin; `docker exec -i` required (runner handles).
- **ACF not loaded** → `function_exists('update_field')` fallback to postmeta + field key.
- **Media reachability** → import from mounted theme assets path only; URLs via `media_sideload_image`.
- **Elementor** → `wp_slash` the JSON; set edit mode + canvas template.
- **Migration risk (replace bash)** → ship deprecated `seed-helpers.sh` one release with a notice, remove after both skills cut over + validated.

## Migration phases (for /ck:plan)
1. `scripts/wp-cli-runner.sh` (auto-detect) + `scripts/seed-batch-runtime.php` (helpers + JSON summary). `php -l`, `bash -n`.
2. Rewrite `content-seeding` skill → PHP payload generator; orchestrator runs eval-file + merges summary. Behavioral test on live wp-env.
3. Rewrite `plugin-data-seeding` skill → same engine (ACF/Elementor/forms).
4. `wp-data-engineer` agent: author-payload role; deprecate `seed-helpers.sh`; update `CLAUDE.md`/README.
5. `claude plugin validate .` + full behavioral seed against a target build; confirm counts + zero-dup re-run.

## Immediate runbook (this build — operational, not plugin code)
1. Resolve runner: `CLI=$(docker ps --filter name=cli --format '{{.Names}}')` → `WP_CLI_RUN="docker exec -i $CLI wp"`.
2. Run the already-authored `seed-content.sh` (script complete, agent died before running).
3. Verify: `wp post list --post_type=page --field=post_name`, CPT counts, front page, menus.
4. Continue pipeline: `seed-plugin-data` → `i18n` (ja-only, no Polylang) → `seo` → `security` → `qa` (gates ship) → `ship`/`handoff`.

## Success metrics
- seed wall-clock: minutes → seconds (≥20× on real builds).
- container invocations per seed stage: ~150 → 1.
- run survives heavy-agent death (orchestrator-driven).
- re-run dup count = 0.

## Unresolved questions
- Embed page bodies in PHP payload vs keep `content/*.html` for human review? (Recommend: embed; optional debug-write.)
- Should the JSON summary also feed a per-stage `seed.report` block in the manifest, or only merge keys? (Recommend: small `seed.lastSummary` for observability.)
