---
phase: 3
title: "Modeling"
status: pending
effort: ""
---

# Phase 3: Modeling

## Overview

When `commerce.enabled`, the `model` stage maps analyzed HTML/brief into a clean
`commerce.catalog` (categories, attributes, simple products) — WITHOUT registering
a `product` CPT (WooCommerce owns that). Add a focused reference doc.

## Requirements

- Functional: `content-modeling` produces `commerce.catalog` with categories
  (hierarchical), attributes + terms, and products (slug, name, sku, prices,
  descriptions, category refs, image refs, stock). Skip core CPT/ACF modeling for
  product data — Woo provides it.
- Non-functional: idempotent slugs; deterministic mapping; do not invent prices
  (leave empty if not detectable, flag in notes).

## Architecture

Mapping rules (HTML product card → product):
- card heading → `name`/`slug`; price token → `regularPrice` (+ struck price →
  `salePrice`); card body/excerpt → `shortDescription`; card image → `images[0]`.
- repeated category labels / shop nav → `categories[]` (hierarchical from IA).
- **Simple products ONLY in SP1** (red-team C3). `type` is const `"simple"`.
  Variable products are out of scope → defer to SP3; if variants are detected,
  record a note and model as simple. No variable mapping/branch in SP1.
- **No product attributes in SP1** (validation Q1) — size/color swatches are NOT
  mapped to `attributes[]`; deferred to SP3 with the variable-product work.

**Sanitization + normalization at this boundary (red-team C4/H1/S7):**
- `description`/`shortDescription`: run through **`wp_kses_post`** (validation Q4 —
  keeps basic formatting tags, strips `<script>`/`on*=`) BEFORE writing to
  `commerce.catalog` — this is the trust boundary; seeding assumes clean input.
- `regularPrice`/`salePrice`: parse locale formats (`1.990.000₫`, `$1,990.00`) →
  canonical decimal string (`1990000` / `1990.00`); leave empty + note on ambiguity.
- `images`/`gallery`/category `image`: record LOCAL relative paths from the
  optimization output ONLY. Never store remote/scraped URLs (prevents seed-time
  SSRF). If the source was a URL crawl, rely on optimization having localized them.

**CPT collision guard (red-team H7/A5) — narrowly scoped:**
`commerce.catalog` is distinct from `contentModel` — products are NOT a CPT. Skip
the `content-modeling` CPT-promotion path ONLY for the specific card instances
TAGGED with commerce signals in Phase 2 (price + add-to-cart) — NOT for every
repeated card when `commerce.enabled`. A `service`/`portfolio` grid that merely
shows a price must still become its proper CPT.

## Related Code Files

- Modify: `skills/content-modeling/SKILL.md` (new section "6. Commerce catalog
  (when commerce.enabled)"; note the CPT-skip rule for product cards).
- Create: `skills/content-modeling/references/woocommerce-model.md` (full mapping
  table HTML→catalog, attribute/variation rules, VND price parsing, examples).
- Create (test fixture): `examples/fixtures/commerce-analysis.sample.json`
  (an `analysis` + `commerce.enabled` input) and the expected `commerce.catalog`
  shape it should yield.

## Implementation Steps

1. **(TEST FIRST)** Write `commerce-analysis.sample.json` and document the
   expected catalog (≥2 categories, ≥3 products with prices+images) as the
   assertion target.
2. Author `references/woocommerce-model.md` with the mapping rules + examples.
3. Add the commerce-catalog section to `content-modeling` + the product-card
   CPT-skip guard.
4. Validate.

## Success Criteria

- [ ] Fixture + expected catalog written before skill edit.
- [ ] Sample analysis maps to a `commerce.catalog` matching expected categories/
      products (manual diff documented); all `type` = `"simple"`.
- [ ] Descriptions kses-sanitized; prices normalized to canonical decimal;
      images recorded as local paths only (no remote URLs).
- [ ] Only commerce-signal-TAGGED cards skip CPT promotion; a priced
      `service`/`portfolio` grid still becomes its CPT.
- [ ] `woocommerce-model.md` exists with mapping + sanitization + price-normalization
      rules; `claude plugin validate .` passes.

## Risk Assessment

- Risk: double-modeling (product as CPT + Woo product) → mitigation: per-instance
  CPT-skip scoped to tagged commerce cards, not the whole stage.
- Risk: VND price formats (`1.990.000₫`) misparsed → mitigation: documented
  locale-aware parsing rules; leave empty + note on ambiguity.
- Risk: unsanitized scraped HTML reaches seeding → mitigation: sanitize at THIS
  boundary; Phase 6 asserts clean input (defense in depth).
