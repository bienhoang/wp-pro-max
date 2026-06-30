---
phase: 1
title: "Schema & Contract"
status: pending
effort: ""
---

# Phase 1: Schema & Contract

## Overview

Add the `commerce` block to the manifest schema and document it in the stage
contract. This is the foundation every later phase reads/writes.

## Requirements

- Functional: `schemas/wp-build.schema.json` gains a `commerce` object
  (catalog model + minimal settings + idempotency keys). `references/manifest-contract.md`
  documents which stage reads/writes `commerce.*` AND that `commerce.catalog.*` is
  UNTRUSTED data (scraped HTML) with a sanitization/validation contract.
- Non-functional: backward compatible — `commerce` is optional; existing
  manifests without it still validate (`additionalProperties: true` at root,
  schema:8 — verified). SP1 freezes ONLY catalog-display fields; SP3 fields are
  deferred, not baked in.

## Architecture

`commerce` shape (catalog-only depth, SP1):

```jsonc
"commerce": {
  "enabled": true,
  "platform": "woocommerce",          // enum: woocommerce (only, for now)
  "depth": "catalog",                  // enum: catalog | checkout | full
  "detectedFrom": ["html"],            // array: html | brief | flag
  "catalog": {
    "categories": [{ "slug","name","parent","image" }],   // image = LOCAL path
    // "attributes" reserved for SP3 (validation Q1) — not populated/seeded in SP1
    "products": [{
      "slug","name",
      "type": "simple",                // SP1: const "simple" — variable → SP3
      "sku","regularPrice","salePrice", // prices = canonical decimal string
      "shortDescription","description", // wp_kses_post-sanitized at model stage (Q4)
      "categories":[string],
      "images":[string],"gallery":[string],   // LOCAL relative paths only
      "stockStatus"
    }]
  },
  "settings": { "currency","currencyPos" },   // SP3 owns weightUnit/baseLocation
  "seededProductSlugs": [string]
}
```

Reuse the existing `"ecommerce"` value already in the `plugins[].category` enum
(schema:169 — verified).

**Scope trims applied (red-team M2/C3/C5):**
- `products[].type` is `const "simple"` in SP1 — variable products deferred to SP3
  (they were declared out of scope; do not model/seed them now).
- `settings` keeps only `currency` + `currencyPos`; `weightUnit`/`baseLocation`
  (shipping/tax = SP3) are NOT added to the SP1 contract.

**Untrusted-data contract (red-team C4/H1/S6/S7) — documented here, enforced downstream:**
- `description`/`shortDescription`: sanitized with **`wp_kses_post`** at the
  `model` stage (validation Q4 — keeps p/strong/ul/a, strips `<script>`/`on*=`);
  seeding asserts sanitized.
- `regularPrice`/`salePrice`: normalized to canonical decimal at `model`; schema
  pattern `^[0-9]+(\.[0-9]+)?$` (empty allowed when undetectable).
- `images`/`gallery`/category `image`: LOCAL relative paths only (the optimization
  stage localizes any remote/scraped images first) — prevents SSRF at seed time.

## Related Code Files

- Modify: `schemas/wp-build.schema.json` (add `commerce` property; do NOT make it required).
- Modify: `references/manifest-contract.md` (add `commerce` read/write matrix row per stage).
- Create (test fixture): `examples/fixtures/commerce-manifest.sample.json` — a
  minimal valid manifest with a populated `commerce` block, used as the schema
  test input.

## Implementation Steps

1. **(TEST FIRST)** Author `examples/fixtures/commerce-manifest.sample.json`
   (version "1", project, strategy, progress, plus a 2-product simple `commerce`
   block) AND a malformed variant (`depth:"bogus"` / `type:"variable"`). Install
   ajv-cli; assert valid passes + malformed FAILS (real schema validation, not jq).
2. Add the `commerce` object definition to the schema with enums above
   (`type` const "simple", price pattern, trimmed settings); keep it optional
   (not in root `required`).
3. Update `references/manifest-contract.md`: `analyze` sets
   `commerce.enabled`/`detectedFrom`; `model` writes `commerce.catalog` AND
   sanitizes/normalizes untrusted fields; `plugins` reads `commerce.enabled`;
   `scaffold` reads `commerce`; `seed-plugin-data` reads+writes
   `commerce.seededProductSlugs`. Document the untrusted-data contract.
4. Run ajv validation (both fixtures) + `claude plugin validate .`.

## Success Criteria

- [ ] Test fixture + a malformed variant written before schema edit.
- [ ] A REAL JSON-Schema validator runs the negative test (jq cannot validate
      enums — red-team M3). Node is present → install + use ajv:
      `npm i -D ajv-cli && npx ajv-cli validate -s schemas/wp-build.schema.json -d examples/fixtures/commerce-manifest.sample.json`.
      Valid sample passes; malformed (`depth:"bogus"`, `type:"variable"`) FAILS.
- [ ] `commerce` is optional; an existing manifest with no `commerce` still validates.
- [ ] `claude plugin validate .` passes.
- [ ] `manifest-contract.md` lists `commerce.*` per stage AND the untrusted-data contract.

## Risk Assessment

- Risk: enum constraints unvalidated if jq used → mitigation: ajv is a hard
  prerequisite (Node available per repo memory); do NOT accept a jq smoke for the
  negative test. Pin ajv-cli in devDependencies.
