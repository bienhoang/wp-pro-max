---
phase: 7
title: "QA & Docs"
status: pending
effort: ""
---

# Phase 7: QA & Docs

## Overview

Add commerce smoke checks to `wp-qa`, run a **mandatory live e2e gate** against
wp-env (Docker is present — confirmed), and update project docs/roadmap for the
commerce layer + SP2/SP3 backlog.

## Requirements

- Functional: `wp-qa` adds shop/product checks (when `commerce.enabled`):
  `/shop/` + one single product return HTTP 200, show price + image. A live e2e
  run (wp-env start → pipeline/seed → curl) is a release GATE, not deferred.
- Non-functional: QA gate semantics unchanged (`qa.passed` still gates ship);
  commerce checks fold into the existing pass/fail.

## Architecture

**Live e2e gate (red-team H6 — Docker IS installed; the prior "no Docker" claim
was false and is removed):**
1. `wp-env start` on a commerce-enabled sample/fixture site.
2. Assert `wp plugin is-active woocommerce` (Phase 6 install guard) and `wp wc`
   namespace present.
3. Run seeding; assert products are query-visible (`wp wc product list` /
   `wc_get_product` non-false) — catches the broken-product failure mode.
4. `wp rewrite flush --hard`; resolve `woocommerce_shop_page_id`; curl `/shop/`
   and the first `commerce.seededProductSlugs` product URL → expect HTTP 200 with
   price + image markers (red-team F8 permalink/flush check).
5. Re-run seed → assert no duplicate products (idempotency, red-team C2/F5).

QA additions in the skill mirror these as `commerce.enabled`-gated steps; reuse
`visual-diff.mjs` when a source shop page exists in `analysis.pages`.

Docs:
- `docs/system-architecture.md` — commerce as a cross-cutting trace (not a stage),
  note the `commerce` manifest block + untrusted-data contract.
- `docs/codebase-summary.md` — list touched skills + new references/helpers/tests.
- `docs/project-roadmap.md` — SP1 status; add SP2 (live store mgmt) + SP3
  (checkout + VN gateways + variable products + attributes/pa_* + shipping/tax settings) backlog;
  correct the stale "no Docker" note (Docker present); update open questions.

## Related Code Files

- Modify: `skills/wp-qa/SKILL.md` (commerce smoke section + live e2e steps, gated on `commerce.enabled`).
- Modify: `docs/system-architecture.md`, `docs/codebase-summary.md`, `docs/project-roadmap.md`.

## Implementation Steps

1. **(TEST FIRST)** Define the live e2e assertion script/steps: shop + product
   200 with price+image, products query-visible, re-run idempotent. This is the
   gate, run for real (Docker available).
2. Add the commerce smoke + live-e2e section to `wp-qa`.
3. Run the live e2e on a commerce fixture; capture results into `qa`.
4. Update the three docs + roadmap backlog (SP2/SP3, incl. variable products +
   attributes/`pa_*` + shipping/tax moved to SP3) + correct the Docker note + open questions.
5. Final whole-plan check: `claude plugin validate .`, all `bash -n` clean, node
   `--check` clean, mock test green (bash+zsh), live e2e green.

## Success Criteria

- [ ] `wp-qa` has a `commerce.enabled`-gated smoke + live-e2e section.
- [ ] Live e2e RUN (not deferred): `/shop/` + product URL 200 with price+image;
      products query-visible; re-run no duplicates.
- [ ] `qa.passed` still gates ship; commerce checks integrated.
- [ ] Docs describe commerce as cross-cutting + untrusted-data contract; roadmap
      lists SP2 + SP3 backlog; stale "no Docker" note corrected.
- [ ] `claude plugin validate .` passes; full verification harness + live e2e green.

## Risk Assessment

- Risk: wp-env first-run pulls images / time budget → mitigation: that is the real
  constraint (NOT "no Docker"); document actual run time; keep the e2e as the gate.
- Risk: docs drift from implementation → mitigation: update docs in this phase
  after skills are final; re-read before editing.
