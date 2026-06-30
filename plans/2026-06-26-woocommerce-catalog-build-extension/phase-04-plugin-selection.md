---
phase: 4
title: "Plugin Selection"
status: pending
effort: ""
---

# Phase 4: Plugin Selection

<!-- Updated: Validation Session 1 - plugins stage now owns Woo install+activate; wp wc abort-on-absent -->

## Overview

When `commerce.enabled`, the `plugins` stage selects WooCommerce, pins its slug
into `.wp-env.json`, AND installs + activates it in the running container (the
env stage already ran, so a pin alone does not install it — red-team C1).

## Requirements

- Functional: `plugin-selection` adds a row mapping the e-commerce need →
  `woocommerce` (`source: wporg`, `category: ecommerce`, `required: true` when
  `commerce.enabled`); merges slug into `.wp-env.json`; then runs
  `wp plugin install woocommerce --activate` in the live container and asserts
  `wp plugin is-active woocommerce`. Verifies `wp wc` namespace present; if absent
  → **abort the build** with remediation (validation decision: commerce was
  requested, do not silently skip).
- Non-functional: minimal set (YAGNI) — catalog depth pulls ONLY `woocommerce`;
  no payment/shipping add-ons (those are SP3). Install step idempotent
  (`is-active` short-circuits).

## Architecture

Extend the selection table with:

| Need | Default slug | Category | When |
|------|--------------|----------|------|
| E-commerce / catalog | `woocommerce` | `ecommerce` | `required: true` when `commerce.enabled` |

`woocommerce` is a bare wporg slug → flows through the existing `.wp-env.json`
merge logic unchanged (the skill already merges `source==wporg` slugs). No premium
ZIP handling needed for catalog depth.

**Install+activate (validation decision Q2):** because the `env` stage starts
wp-env BEFORE this stage selected Woo, pinning the slug does not install it in the
already-running container. After the merge, this stage runs
`wp plugin install woocommerce --activate` + asserts `is-active`, then checks
`wp wc --help`. Missing `wp wc` → abort (validation Q3). Seeding (Phase 6) then
only RE-asserts, never installs.

## Related Code Files

- Modify: `skills/plugin-selection/SKILL.md` (add the e-commerce row to the
  selection table + example output including `woocommerce`; add the
  install+activate+`is-active`+`wp wc`-check+abort-on-absent procedure when
  `commerce.enabled`).

## Implementation Steps

1. **(TEST FIRST)** Document the assertion: given a manifest with
   `commerce.enabled=true`, the resulting `plugins[]` MUST contain
   `{slug: woocommerce, category: ecommerce, required: true}` and `.wp-env.json`
   `plugins` MUST include `"woocommerce"`. Use the Phase 1 fixture as input.
2. Add the table row + example to `plugin-selection`.
3. Confirm the existing `.wp-env.json` merge (`select(.source=="wporg")`) picks up
   `woocommerce` with no code change; note it explicitly.
4. Validate.

## Success Criteria

- [ ] Assertion documented before skill edit.
- [ ] `commerce.enabled` → `woocommerce` in `plugins[]` (ecommerce, required:true).
- [ ] `woocommerce` appears in `.wp-env.json` `plugins` via existing merge.
- [ ] Stage installs+activates Woo in the live container; `is-active` asserted;
      install step idempotent on re-run.
- [ ] `wp wc` namespace verified; absent → build aborts with remediation message.
- [ ] Catalog depth adds no other commerce plugin; `claude plugin validate .` passes.

## Risk Assessment

- Risk: scope creep (adding Stripe/shipping now) → mitigation: explicit
  catalog-depth-only rule; SP3 owns gateways.
- Risk: pinning `woocommerce` into `.wp-env.json` does NOT install/activate it in
  the already-running container (env stage ran before plugins; resume guard blocks
  re-provision — red-team C1). Ordering is necessary, not sufficient → the actual
  install + `is-active` assertion is owned by Phase 6 (6.0), not this phase.
