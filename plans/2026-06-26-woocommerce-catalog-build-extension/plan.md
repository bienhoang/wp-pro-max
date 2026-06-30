---
title: "WooCommerce Catalog Build Extension (SP1)"
description: ""
status: pending
priority: P2
branch: "main"
tags: []
blockedBy: []
blocks: []
created: "2026-06-26T08:29:38.128Z"
createdBy: "ck:plan"
source: skill
---

# WooCommerce Catalog Build Extension (SP1)

## Overview

Extend the `wp-pro-max` Claude Code plugin so its HTML→WordPress pipeline can
build a **catalog-only WooCommerce store**. WooCommerce is a **cross-cutting
layer** (a new `commerce` manifest block), NOT a 4th theme strategy and NOT a new
pipeline stage — logic is added to the skills that already own each stage. Runs
under all 3 strategies (classic-acf / block-fse / page-builder).

**Source of truth:** `brainstorm-woocommerce-catalog-build-extension.md` (same dir).

**Scope (SP1):** detect commerce need (HTML heuristics + brief/flag) → select
WooCommerce → scaffold Woo template overrides per strategy → seed
categories/attributes/products/images (idempotent) → QA shop/product pages.

**Out of scope:** cart/checkout/payment/shipping/tax (SP3), VN gateways
VietQR/SePay + GHN/GHTK (SP3), live-store management & orders (SP2), coupons,
multi-currency, complex variable products.

**TDD note:** this plugin has no runtime app; "tests" = the repo's verification
harness — `claude plugin validate .`, `bash -n` + zsh+bash sourcing, `node --check`,
a **mocked-WP-CLI** test for seed helpers, and a **live wp-env e2e** for the
store. NOTE: no test infrastructure exists yet (`find -name '*test*'` is empty) —
Phase 6 BUILDS the mock harness as a first-class deliverable (it is not a copy of
a pre-existing pattern). Each phase writes its check/fixture FIRST.

**Trust boundary:** `commerce.catalog.*` is UNTRUSTED (scraped HTML). The `model`
stage sanitizes descriptions (`wp_kses_post`) + normalizes prices; seeding uses only
the argv-array `wp_cli` runner with NO raw `wp db query` for product data, and
imports only LOCAL image files (no `wp media import <remote-url>` → no SSRF).

## Acceptance criteria (whole plan)

- Input HTML with product cards (or a brief/`--commerce` flag) drives the
  pipeline to a wp-env WordPress with WooCommerce installed + **active**
  (asserted, not assumed — Phase 6 install guard).
- Categories + simple products + images seeded **idempotently** via `wp wc`
  (re-run adds no duplicates; explicit `--slug`); `commerce.seededProductSlugs`
  recorded AND read as a skip fast-path. (Product attributes deferred to SP3.)
- Products are query-visible (`wc_get_product` non-false); `/shop/` + a single
  product render HTTP 200 with theme styling — verified by a **mandatory live
  e2e gate** (Docker present; NOT deferred).
- `claude plugin validate .` passes; all shell `bash -n` + zsh-safe; node
  `--check` clean; mocked-WP-CLI helper test green (bash+zsh); live e2e green.
- Seeded product content is sanitized (no stored XSS); detection does not
  false-positive on non-shop pages (user gate confirms `commerce.enabled`, incl.
  under `--auto` for heuristic-only detection).

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Schema & Contract](./phase-01-schema-contract.md) | Pending |
| 2 | [Detection](./phase-02-detection.md) | Pending |
| 3 | [Modeling](./phase-03-modeling.md) | Pending |
| 4 | [Plugin Selection](./phase-04-plugin-selection.md) | Pending |
| 5 | [Convert & Scaffold](./phase-05-convert-scaffold.md) | Pending |
| 6 | [Seeding](./phase-06-seeding.md) | Pending |
| 7 | [QA & Docs](./phase-07-qa-docs.md) | Pending |

## Dependencies

**Internal phase order (linear):** 1 → 2 → 3 → 4 → 5 → 6 → 7.
Phase 5 needs 3 (model) + 4 (plugins); 6 needs 5 (scaffold) + 4; 7 needs 6.

**Cross-plan:** none blocking.
- `20260626-wp-pro-max-kit` — COMPLETE; this builds on its skills/scripts.
- `20260626-wp-plugin-dev` — pending, standalone WP-plugin builder skill;
  thematically adjacent but **no file overlap** with commerce work → no
  `blockedBy`/`blocks` relationship.

**External:** WooCommerce wporg slug `woocommerce`; `wp wc` CLI (hard-required,
asserted after activate — Phase 6); product images come from the `optimization`
stage output (localized; no remote URLs at seed time).

## Red Team Review

### Session — 2026-06-26
**Reviewers:** 4 (Security Adversary, Failure Mode Analyst, Assumption Destroyer,
Scope & Complexity Critic). **Findings:** 29 raw → 15 deduped, 14 accepted / 1
rejected. **Severity:** 5 Critical, 7 High, 3 Medium. Reports in `reports/`.

| # | Finding | Sev | Disposition | Applied |
|---|---------|-----|-------------|---------|
| 1 | Woo pinned but never installed/activated in running container (env-before-plugins + resume guard) | Critical | Accept | Phase 6 (install+activate guard, is-active assert) |
| 2 | Idempotency broken — create sets no `--slug`, lookup keys on slug → dup re-run | Critical | Accept | Phase 6 (explicit `--slug`, auto-suffix fail-loud) |
| 3 | `wp post create` fallback → query-invisible products | Critical | Accept | Phase 6 (drop fallback, hard-require `wp wc`) |
| 4 | Stored XSS — scraped descriptions seeded unsanitized | Critical | Accept | Phase 3 (kses sanitize) + Phase 6 (assert clean) |
| 5 | `import_media` global filename dedupe corrupts galleries | Critical | Accept | Phase 6 (per-product attachment title key) |
| 6 | SQL injection in documented `wp db query` fallback | High | Accept | Phase 6 (no raw SQL for product data) |
| 7 | Safety gates bypassable under `--auto` | High | Accept | Phase 2 (`--auto` rule: heuristic-only needs confirm) |
| 8 | SSRF + local/remote image-source contradiction | High | Accept | Phase 1/3 (local paths only) + Phase 6 (no remote import) |
| 9 | `pa_*` attribute taxonomies created before registration | High | Accept | Deferred — validation Q1 cut attributes from SP1; F4 mitigation moves to SP3 |
| 10 | `seededProductSlugs` write-only (no dedup value) | High | Accept | Phase 6 (read as skip fast-path, record per-create) |
| 11 | Acceptance unfalsifiable + FALSE "no Docker" premise | High | Accept | Phase 7 (mandatory live e2e gate) + plan.md fix |
| 12 | Commerce detection vs CPT-promotion signal collision | High | Accept | Phase 2 (per-instance signal tag) + Phase 3 (scoped skip) |
| 13 | Variable products = gold-plating vs out-of-scope | Med | Accept | Phase 1/3 (`type` const "simple", defer SP3) |
| 14 | `commerce.settings` carries SP3 shipping/tax fields | Med | Accept | Phase 1 (trim to currency/currencyPos) |
| 15 | Fabricated mock-test precedent (no test infra exists) | Med | Accept | Phase 6 (mock harness = explicit deliverable) + plan.md TDD note |
| — | Detection scoring over-engineered given human gate | Low | Reject | Covered by #12; lives in markdown, gate backstops |

**User decisions during adjudication:** keep all 3 theme strategies (declined the
classic-only MVP trim, finding C4); add live e2e as a gate; hard-require `wp wc`
fail-fast; apply all other accepted findings.

`ensure_term` gains an optional `[parent-slug]` arg instead of a duplicate
`ensure_wc_term` (red-team C2); 7-phase structure retained (C6 acknowledged,
restructuring cost > benefit).

### Whole-Plan Consistency Sweep
Re-read plan.md + all 7 phase files after edits. Reconciled: `wp wc` fallback
removed everywhere (Phase 6 + open questions); `type` const "simple" consistent
(schema Phase 1, mapping Phase 3, seeding Phase 6); "no Docker"/deferred-e2e
language removed (plan acceptance, Phase 5, Phase 7); untrusted-data contract
stated in Phase 1 and enforced in Phase 3 (sanitize) + Phase 6 (assert, no raw
SQL, local media); CPT-skip scoped to tagged instances in both Phase 2 and Phase
3; `seededProductSlugs` now read+write. No unresolved contradictions.

## Validation Log

### Session 1 — 2026-06-26
**Verification pass:** SKIPPED per validate-workflow guard — `## Red Team Review`
already carries `file:line` verification evidence; no `[UNVERIFIED]` tags remain.
**Questions asked:** 4 (all genuine open decision points red-team did not settle).

| Q | Decision | Propagated to |
|---|----------|---------------|
| Q1 Attributes in SP1? | **Defer to SP3** — SP1 = categories + simple products, no `pa_*` | Phase 1 (schema), Phase 3 (no attr mapping), Phase 6 (no attr seed; F4 → SP3), acceptance |
| Q2 Woo install location | **`plugins` stage (Phase 4)** installs+activates+asserts; seeding re-asserts only | Phase 4 (owns install), Phase 6 (6.0 re-assert) |
| Q3 `wp wc` absent behavior | **Abort build** with remediation (commerce was requested) | Phase 4 (abort), Phase 6 (no fallback) |
| Q4 Sanitization policy | **`wp_kses_post`** allowlist (keep basic formatting, strip script/`on*=`) | Phase 1, Phase 3, Phase 6 (6.0c) |

### Whole-Plan Consistency Sweep (post-validation)
Re-read all 8 files. Reconciled: attributes/`pa_*` removed from Phase 1 schema,
Phase 3 mapping, Phase 6 seed order/criteria, and red-team row 9 (now "deferred
SP3"); acceptance "categories + simple products" (was "+ attributes"). Woo
install relocated to Phase 4; Phase 6 6.0 is re-assert-only; Phase 4 risk note +
success criteria updated. `wp_kses_post` consistent across Phases 1/3/6. `wp wc`
abort path single-sourced in Phase 4. SP3 backlog now owns: variable products,
attributes (`pa_*` + F4 mitigation), checkout, VN gateways, shipping/tax settings.
No unresolved contradictions.

## Open questions (resolved by red-team adjudication)

- `wp wc` CLI: **RESOLVED → hard-require + fail-fast** (no broken `wp post create`
  fallback). Phase 6 installs+activates Woo, asserts `wp wc` present, fails clearly
  if not. Verified by the Phase 7 live e2e.
- Variable products: **RESOLVED → defer entirely to SP3.** SP1 models/seeds only
  `type: "simple"`; schema enforces the const.
- Theme-strategy scope: **DECISION (user) → keep all 3 strategies in SP1**
  (classic-acf + block-fse + page-builder Woo overrides). Live e2e validates render.
