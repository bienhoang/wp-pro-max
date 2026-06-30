# Red-Team Plan Review — WooCommerce Catalog Build Extension (SP1)

Lens: Failure Mode Analyst · Verification: Flow Tracer
Reviewer: code-reviewer · Date: 2026-06-26
Verdict: REQUEST CHANGES — 3 Critical, 3 High, 2 Medium. The plan's two headline
guarantees (Woo active before seed; idempotent re-run with no duplicates) are
both unproven against the actual codebase and, as traced, fail.

---

## Finding 1: WooCommerce is pinned into config but never installed/activated in the running container
**Severity:** Critical
**Location:** plan dependency claim in `phase-04-plugin-selection.md:63-64` and
`phase-06-seeding.md:29`; traced against `commands/build.md:23-27,36-39`,
`scripts/wp-env-bootstrap.sh` (plugins read → `_wpenv start`),
`skills/wp-env-setup/SKILL.md` resume guard.

**Flaw:** The build runs `env` FIRST (`build.md` step 2 "Provision env first"),
before `plugins`. `wp-env-bootstrap.sh` reads `plugins[]` from the manifest *at
env time* (empty — `plugins` stage has not run) and then calls `_wpenv start`,
which is the only point wp-env installs+activates plugins. The `plugins` stage
runs later and writes Woo into `.wp-env.json` and the manifest, but NOTHING
re-runs `wp-env start` / re-provisions afterward. Worse, the `env` stage is then
marked `done`, so its resume guard (`wpbuild_is_done env`) blocks any
re-provision on a later run without `--force`. Phase 4's mitigation
("handled by orchestrator — plugins stage precedes seed") is an ordering
fallacy: ordering the stage is necessary but not sufficient; the container is
never told about the new plugin.

**Failure scenario:** Pipeline reaches `seed-plugin-data`, calls
`wp wc product create` (or even the fallback `wp post create --post_type=product`)
against a WordPress where WooCommerce is neither installed nor active. `wp wc`
namespace is absent; `product` post_type/`product_cat`/`pa_*` taxonomies are
unregistered. Every seed command errors. Entire phase 6 fails on first live run.

**Evidence (file:line):**
- `commands/build.md:23-27` stage order `env → … → plugins → scaffold → seed-*`
- `commands/build.md:36-39` "Provision env first … wp-env start" (env precedes plugins)
- `scripts/wp-env-bootstrap.sh` reads `plugins_json` from manifest then `_wpenv start` (single start, no later re-start)
- `skills/wp-env-setup/SKILL.md` resume guard `wpbuild_is_done env && … exit 0`
- `skills/plugin-selection/SKILL.md` Verify line: "wp-env run cli wp plugin list --status=active (after env start)" — assumes a start that has already happened
- `plans/.../phase-04-plugin-selection.md:63-64` mitigation claim

**Suggested fix:** Add an explicit step in the `plugins` stage (or a phase-6
precondition) that actually provisions Woo into the live container after
`.wp-env.json` is updated: `wp-env start` re-run (or
`wp plugin install woocommerce --activate` via `wp_cli`), then assert
`wp plugin is-active woocommerce` before any seeding. Account for the `env`
resume guard (force re-provision or move plugin install into a step that is not
gated by `wpbuild_is_done env`).

---

## Finding 2: Slug-based idempotency breaks because the create command never sets the slug
**Severity:** Critical
**Location:** `phase-06-seeding.md:33` (create command) vs `phase-06-seeding.md:18-20,38`
(idempotency-by-slug claim); helper `scripts/seed-helpers.sh:94-98,135-156`.

**Flaw:** Phase 6 documents creation as
`wp wc product create --name --sku --regular_price ...` with NO `--slug`.
WooCommerce/WordPress then derives `post_name` from the product **name**
(`sanitize_title(name)`), and auto-suffixes on collision (`-2`, `-3`). But the
re-run existence check is keyed on the intended `slug` argument via
`_seed_find_post_by_slug "$slug" product` (`wp post list --name=$slug`). Whenever
`slug != sanitize_title(name)` (e.g. catalog slug `p-001` / name "Blue Shirt", or
any Woo auto-suffixed slug), the lookup misses an existing product and creates a
**new duplicate on every re-run**.

**Failure scenario:** First run creates "Blue Shirt" → post_name `blue-shirt`.
Re-run: `_seed_find_post_by_slug "p-001"` returns empty → creates "Blue Shirt"
again → post_name `blue-shirt-2`. Third run → `blue-shirt-3`. `/shop/` fills with
duplicates; the headline acceptance criterion "re-run adds no duplicates"
(`plan.md:46`) is violated.

**Evidence (file:line):**
- `phase-06-seeding.md:33` create command lacks `--slug`
- `phase-06-seeding.md:18-20` "create-if-missing by slug"
- `scripts/seed-helpers.sh:94-98` `_seed_find_post_by_slug` matches on `--name=$slug`
- `plan.md:46` "re-run adds no duplicates"

**Suggested fix:** Pass `--slug="$slug"` explicitly to `wp wc product create`
(and `--post_name` in the fallback), and after creation re-read the actual
`post_name`; if Woo auto-suffixed it, fail loudly rather than silently
duplicating. Add a mock-test assertion that the create call carries the slug.

---

## Finding 3: Fallback `wp post create --post_type=product` yields invisible/broken products
**Severity:** Critical
**Location:** `phase-06-seeding.md:34-36` fallback path; `plan.md:83` open question.

**Flaw:** The documented fallback sets only `_price,_regular_price,_sku,_stock_status`
meta plus a vague "wp wc re-sync". It omits two things WooCommerce requires for a
product to be a valid, shoppable product:
1. The `product_type` **taxonomy term** (`simple`) — a raw `wp post create` leaves
   it unset; `wc_get_product()` can return `false` and the product won't render.
2. The `wp_wc_product_meta_lookup` row — Woo populates this only through the
   `WC_Product` CRUD save hooks, never on a raw `post create`+`post meta`. Shop
   archive queries, price sorting, and filtering read the lookup table, so the
   product won't appear in `/shop/`. There is no `wc tool run
   regenerate_product_lookup_tables` step anywhere (grep: zero hits for
   `product_type` / `meta_lookup` / `regenerate` across the plan).

**Failure scenario:** `wp wc` is unavailable (the exact case the fallback exists
for); products are created as bare posts with price meta but no `simple` type and
no lookup row. Phase 7 QA (`/shop/` 200 with the product listed + price) fails —
shop renders empty even though posts exist in the DB.

**Evidence (file:line):**
- `phase-06-seeding.md:34-36` fallback meta list (no product_type term, no lookup regen)
- grep across plan dir: no occurrence of `product_type` / `meta_lookup` / `regenerate`
- `phase-07-qa-docs.md:28-29` QA asserts shop page lists product + price

**Suggested fix:** If the `wp wc` fallback is kept, document the full minimum:
set `product_type` term (`wp wc product_cat`/`wp term ... product_type simple`),
all required meta, then run `wp wc tool run regenerate_product_lookup_tables` (or
prefer abandoning the raw fallback and hard-requiring `wp wc`, failing the run if
absent). Add a QA assertion that the product appears in the shop loop, not just
that a post exists.

---

## Finding 4: `pa_*` attribute taxonomies are not registered before terms are created
**Severity:** High
**Location:** `phase-06-seeding.md:32`; helper reuse `scripts/seed-helpers.sh:238-252`.

**Flaw:** Phase 6 says "attributes + terms → `wp wc product_attribute` + `pa_<slug>`
terms" and the fallback helper `ensure_wc_term <taxonomy>` reuses `ensure_term`,
which calls `wp term create "$tax"`. A `pa_<slug>` taxonomy does not exist until
(a) `wp wc product_attribute create` inserts the row in
`wp_woocommerce_attribute_taxonomies` AND (b) WooCommerce re-registers
taxonomies on a fresh load (`register_taxonomy` runs on `init`). Creating
`pa_color` terms in the same (or immediately following) CLI process before that
re-init fails with "Invalid taxonomy". In the no-`wp wc` fallback, `pa_*` cannot
be registered at all via `wp term create`.

**Failure scenario:** `ensure_wc_term pa_color Red red` runs right after the
attribute is created → "Invalid taxonomy pa_color" → attribute terms missing →
products have no attributes; if the helper doesn't hard-fail, it silently
records a key for a term that was never created.

**Evidence (file:line):**
- `phase-06-seeding.md:32` attribute+term step
- `scripts/seed-helpers.sh:238-252` `ensure_term` → `wp term create "$tax"` (no taxonomy-registration guard)

**Suggested fix:** After `wp wc product_attribute create`, force a Woo reload
before term creation (separate `wp_cli` invocation is usually enough, or
`wp wc product_attribute list` to confirm registration); guard `ensure_wc_term`
to verify `wp taxonomy get "$tax"` succeeds before attempting term create, and
fail loudly otherwise.

---

## Finding 5: `commerce.seededProductSlugs` is write-only — it provides zero dedup protection
**Severity:** High
**Location:** `phase-06-seeding.md:38,81`; `phase-01-schema-contract.md:46,71`;
`phase-07-qa-docs.md:29`; `plan.md:46`.

**Flaw:** Tracing every reference: `seededProductSlugs` is only ever WRITTEN
(phase 6 step 4, schema) and is READ exactly once — by QA to pick a product URL
(phase 7). It is never read to skip already-seeded products. The real dedup
relies solely on the WP-CLI slug lookup, which Finding 2 shows is broken. So the
manifest's advertised "idempotency record" is decorative: it satisfies the
acceptance wording ("records keys") while contributing nothing to the actual
"re-run adds no duplicates" guarantee.

**Failure scenario:** A reviewer/operator sees `seededProductSlugs` populated and
assumes re-runs are safe; in reality duplicates accumulate (Finding 2) because
nothing consults that list before creating.

**Evidence (file:line):**
- Written only: `phase-06-seeding.md:38`, `phase-01-schema-contract.md:71`
- Read only by QA for a URL: `phase-07-qa-docs.md:29`
- No read-to-skip anywhere (grep across plan dir confirms)

**Suggested fix:** Either make `ensure_wc_product` consult `seededProductSlugs`
as a fast-path skip (and reconcile against live state), or drop the claim that it
provides idempotency and state explicitly that idempotency is lookup-based — then
make the lookup correct (Finding 2).

---

## Finding 6: No partial-failure recovery; cross-entity references can dangle
**Severity:** Medium
**Location:** `phase-06-seeding.md:29-40,85-93` (Risk Assessment).

**Flaw:** Seed order is categories → attributes → products, with products
referencing categories/attributes by slug. Phase 6's risk section covers only
`wp wc` availability, zsh breakage, and gallery CSV — nothing about a mid-run
abort. If category or attribute creation partially fails, product creation
proceeds and assigns products to categories/attributes that don't exist
(silently dropped by Woo). If the product loop aborts midway, `seededProductSlugs`
(written per step 4) may not reflect created posts, and `seed-plugin-data` stays
`in-progress`; the next run re-enters the whole branch and (given Finding 2)
duplicates the already-created products. No rollback or reconciliation is
specified.

**Failure scenario:** Image import for product 5 fails (missing optimized asset);
the script exits non-zero under `set -euo pipefail`; products 1-4 exist, 5-N do
not, categories half-created. Re-run duplicates 1-4 and orphans their category
assignments.

**Evidence (file:line):**
- `phase-06-seeding.md:29-40` ordered seed with slug references
- `phase-06-seeding.md:85-93` risks omit partial-failure/rollback
- `scripts/seed-helpers.sh:22-24` no top-level `set -euo` in the sourced lib (so failure behavior depends on the generated script's mode)

**Suggested fix:** Specify resume/reconciliation: verify each referenced
category/attribute exists before assigning; record each slug immediately after
its own create (not in a batch at the end); document expected behavior on
mid-loop failure and that re-run reconciles rather than duplicates.

---

## Finding 7: Hierarchical categories will be created flat — parent handling unspecified
**Severity:** Medium
**Location:** `phase-06-seeding.md:43` helper signature; `scripts/seed-helpers.sh:238-252`.

**Flaw:** `ensure_wc_term <taxonomy> <name> <slug> [parent-slug]` advertises a
parent argument, but the cited model (`ensure_term`) calls
`wp term create "$tax" "$name" --slug=...` with no `--parent`. The brainstorm and
schema require hierarchical categories (`categories[].parent`,
`phase-01-schema-contract.md:38`). Without resolving parent-slug → parent
term_id and passing `--parent`, every category is created at the top level.

**Failure scenario:** A "Men > Shirts" hierarchy collapses to two sibling
top-level categories; product breadcrumbs and shop category nav don't match the
source IA. Re-run lookups by slug still "find" them, masking the structural bug.

**Evidence (file:line):**
- `phase-06-seeding.md:43` signature with `[parent-slug]`
- `scripts/seed-helpers.sh:238-252` `ensure_term` has no parent support
- `phase-01-schema-contract.md:38` categories carry `parent`

**Suggested fix:** Specify that `ensure_wc_term` resolves parent-slug to a
term_id (creating the parent first) and passes `--parent`; add a mock-test
asserting the `--parent` flag is present for child categories.

---

## Finding 8: Product permalinks/shop page depend on a rewrite flush that runs before Woo exists
**Severity:** Medium
**Location:** `phase-07-qa-docs.md:28-29`; `scripts/wp-env-bootstrap.sh` (rewrite flush during env).

**Flaw:** `wp rewrite flush` happens once, inside `wp-env-bootstrap.sh` during the
`env` stage — before WooCommerce registers the `product` post_type and its
rewrite rules (and before the Shop page exists). QA then resolves
`woocommerce_shop_page_id` and curls single-product URLs. With no post-activation
`wp rewrite flush`, single-product pretty URLs can 404 and the shop page id may be
unset (it is created by Woo's activation routine — which, per Finding 1, never
runs).

**Failure scenario:** `/shop/` and `/product/<slug>/` return 404 despite valid DB
rows; QA fails for a reason unrelated to seeding correctness, costing debugging
time.

**Evidence (file:line):**
- `scripts/wp-env-bootstrap.sh` rewrite structure/flush block (env stage, pre-Woo)
- `phase-07-qa-docs.md:28-29` QA reads `woocommerce_shop_page_id` + curls product URL

**Suggested fix:** Add a `wp rewrite flush --hard` (and confirm
`woocommerce_shop_page_id`) after WooCommerce is activated and products are
seeded, as an explicit phase-6/7 step — not relying on the env-stage flush.

---

## Cross-cutting note
Findings 1, 2, 3 are causally chained: even if activation is fixed (1), the slug
(2) and product-validity (3) gaps independently break the two headline acceptance
criteria. The mocked-WP-CLI test strategy (phase 6 step 1) will pass while all
three real failures remain, because mocks return canned IDs and never exercise
Woo's slug derivation, taxonomy registration, or the lookup table. The TDD claim
is therefore a phantom-test risk: green mocks, broken store.

## Unresolved questions
- Does the target wp-env flow expect a manual `wp-env start` re-run after the
  `plugins` stage, or should plugin install move into the `plugins` stage itself?
  The plan assumes the former implicitly but never states it.
- Is the `wp post create` fallback actually reachable in supported environments,
  or should the plan hard-require `wp wc` and fail fast? Keeping a fallback that
  produces broken products is worse than failing.
