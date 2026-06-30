---
phase: 6
title: "Seeding"
status: pending
effort: ""
---

# Phase 6: Seeding

<!-- Updated: Validation Session 1 - install moved to Phase 4 (re-assert here); attributes deferred to SP3 -->

## Overview

Seed the WooCommerce catalog idempotently: create product **categories →
products → images** via the **`wp wc` CLI** (install/activate + `wp wc` presence
already done + asserted in Phase 4), after content exists. Add a reusable
mock-WP-CLI test harness (net-new — no test infra exists yet) and the seeding
helpers/branch. **Attributes (`pa_*`) are deferred to SP3** (validation Q1) —
SP1 seeds categories + simple products only.

## Requirements

- Functional: `seed-helpers.sh` gains `ensure_wc_product` (create-if-missing by
  explicit slug via `wp wc product create --slug`) and extends `ensure_term` with
  an optional `[parent-slug]` arg (for hierarchical `product_cat`) instead of a
  duplicate helper. `plugin-data-seeding` adds a WooCommerce branch routed like the
  forms branch.
- Non-functional: idempotent (re-run → no duplicates), zsh-safe AND bash-safe when
  sourced (repo memory: no top-level `set -euo`, zsh BASH_SOURCE/word-split guards),
  records each slug to `commerce.seededProductSlugs` immediately after its create.
  **No raw SQL** for product data (removes the SQL-injection vector).

## Architecture

### 6.0 Woo active re-assert (install owned by Phase 4 — validation Q2)
Phase 4 (`plugins` stage) installs + activates WooCommerce and verifies the
`wp wc` namespace, aborting the build if absent (validation Q3). This phase only
**re-asserts** `wp plugin is-active woocommerce` as a cheap pre-seed guard and
fails clearly if state regressed. It does NOT install. Never fall back to
`wp post create --post_type=product` (omits `product_type` term +
`wc_product_meta_lookup` rows → query-invisible products); `wp wc` is the only
product-create path.

### 6.0c Untrusted-data boundary (fixes red-team C4/H1/S7)
`commerce.catalog.*` originates from scraped HTML = UNTRUSTED. Phase 3 sanitizes
descriptions with **`wp_kses_post`** (validation Q4 — keeps basic formatting,
strips `<script>`/`on*=`) and normalizes prices to canonical decimal; this phase
ASSERTS the values it seeds are already sanitized/numeric and passes them only
through the argv-array `wp_cli` runner (no shell string building, no `wp db query`).

### 6.1 Seed order (attributes deferred — validation Q1)
1. **categories** → `ensure_term product_cat <name> <slug> [parent-slug]`. Parent
   resolved to term_id and passed as `--parent` (fixes flat-hierarchy F7); create
   parents before children.
2. **products** → `wp wc product create --slug="$slug" --name --sku
   --regular_price [--sale_price] --description --short_description
   --category_ids --stock_status` (explicit `--slug` fixes idempotency C2).
   Re-read the actual `post_name`; if Woo auto-suffixed (`-2`) → fail loudly
   rather than silently duplicate. No `--attributes` in SP1.
3. **images** → product-scoped import (see 6.2). Set featured + gallery
   (`_product_image_gallery` = CSV of attachment IDs).
4. Record each slug to `commerce.seededProductSlugs` right after its create;
   the WooCommerce branch READS this list as a skip fast-path (fixes write-only
   F5) in addition to the slug existence check.

(SP3 will add `pa_*` attribute registration + reload + term creation — red-team
F4 mitigation moves there with the variable-product work.)

### 6.2 Media — local only + per-product namespacing (fixes S6 SSRF + C5/A2)
- Import ONLY local files (the optimization stage downloads any remote/scraped
  images to local first). Never `wp media import <remote-url>` (SSRF).
- `import_media` dedupes by attachment title library-wide → cross-product
  basename collisions (`1.jpg`). Use a product-scoped title key
  (`title="${product_slug}-${base}"`) so two products with the same basename get
  distinct attachments.

### 6.3 Idempotency helpers
- `ensure_wc_product <slug> <name> <regular_price> [sku] [category-slugs-csv] [stock]`
  — lookup by slug (skip-list + `wp wc product list --slug`), create with explicit
  `--slug`, print ID, record key. Mirrors existing helper idioms (stderr log,
  porcelain ID).
- Extend `ensure_term` signature to `ensure_term <taxonomy> <name> <slug> [parent-slug]`
  (resolve parent → `--parent`); avoids a near-duplicate `ensure_wc_term`.

### 6.4 Rewrite flush (fixes F8)
After seeding: `wp rewrite flush --hard` and verify `woocommerce_shop_page_id` is
set, so product permalinks + the Shop page resolve (the env-stage flush ran before
Woo existed).

## Related Code Files

- Create: `scripts/tests/seed-helpers-wc.mock-test.sh` — **net-new** mock harness
  (no test infra exists in repo; M1). Define a fake `wp` via `WP_CLI_RUN` that
  records calls + returns canned IDs; this harness is an explicit deliverable.
- Modify: `scripts/seed-helpers.sh` (add `ensure_wc_product`; add `[parent-slug]`
  to `ensure_term`; product-scoped media key; Woo install/activate + `wp wc`
  guard helpers; extend direct-dispatch usage list).
- Create: `skills/plugin-data-seeding/references/woocommerce-seeding.md` (`wp wc`
  command map, is-active re-assert, gallery meta, slug idempotency, untrusted-data
  rule, NO-raw-SQL rule, rewrite flush; attributes out of scope — SP3).
- Modify: `skills/plugin-data-seeding/SKILL.md` (WooCommerce branch in routing
  table mirroring forms; remove any raw-SQL suggestion for products).
- Modify: `agents/wp-data-engineer.md` (acceptance: Woo active asserted, products
  query-visible via `wc_get_product`, re-run no duplicates, images per-product).

## Implementation Steps

1. **(TEST FIRST)** Build `scripts/tests/seed-helpers-wc.mock-test.sh` (the harness
   itself is new work, not a copy of a non-existent precedent). Assert: (a) first
   `ensure_wc_product` creates with `--slug`; (b) second same-slug call is a no-op;
   (c) `ensure_term` with parent passes `--parent`; (d) two products with identical
   image basenames yield DISTINCT attachment IDs; (e) missing `wp wc` → fail-fast
   exit nonzero; (f) runs clean under BOTH `bash` and `zsh`. Must fail before impl.
2. Implement the is-active re-assert, helpers, media namespacing, rewrite flush
   (install/activate + `wp wc` check live in Phase 4).
3. Author `woocommerce-seeding.md`; add the Woo branch to `plugin-data-seeding`;
   strip any product raw-SQL path.
4. Update `wp-data-engineer` acceptance.
5. Run: `bash -n scripts/seed-helpers.sh`, `bash` + `zsh` mock test,
   `claude plugin validate .`.

## Success Criteria

- [ ] Mock harness written + failing first (TDD); no reliance on a pre-existing
      test (none exists).
- [ ] `wp plugin is-active woocommerce` re-asserted before seeding (install in Phase 4).
- [ ] No `wp post create` product fallback; `wp wc` is the only create path.
- [ ] `ensure_wc_product` passes explicit `--slug`; re-run creates no duplicate
      (mock test green); auto-suffix detected → loud failure.
- [ ] Categories hierarchical (`--parent` passed). No `pa_*` attributes in SP1.
- [ ] Two products with same image basename → distinct attachments (mock asserts).
- [ ] No raw SQL for product data anywhere; only argv-array `wp_cli`.
- [ ] `commerce.seededProductSlugs` recorded per-create AND read as skip fast-path.
- [ ] `wp rewrite flush --hard` run; `woocommerce_shop_page_id` set.
- [ ] Helpers source/run clean under bash AND zsh; `bash -n` clean; `claude plugin validate .` passes.

## Risk Assessment

- Risk: Woo state regresses between Phase 4 install and seeding → mitigation:
  cheap `is-active` re-assert at 6.0 before any write.
- Risk: zsh breakage in sourced helper (repo memory footgun) → mitigation: mirror
  existing guards; test under zsh explicitly.
- Risk: `wp wc` truly unavailable in wp-env image → mitigation: Phase 4 aborts the
  build early (validation Q3); verified in the Phase 7 live e2e (Docker present).
