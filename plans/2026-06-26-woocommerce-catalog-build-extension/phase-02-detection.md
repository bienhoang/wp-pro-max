---
phase: 2
title: "Detection"
status: pending
effort: ""
---

# Phase 2: Detection

## Overview

Teach the `analyze` stage to detect commerce intent from both sources (HTML
heuristics + brief/`--commerce` flag) and set `commerce.enabled`/`detectedFrom`.
Wire the `--commerce` flag and a confirmation gate into the orchestrator.

## Requirements

- Functional: `html-analysis` sets `commerce.enabled=true` + `detectedFrom` when
  shop signals present OR brief/flag forces it. `build.md` accepts `--commerce`
  and gates `commerce.enabled` for user confirmation after analyze.
- Non-functional: low false-positive rate — a lone price on a landing page must
  NOT trigger Woo; require a *cluster* of signals. Brief/flag overrides heuristics.

## Architecture

Detection heuristics (need ≥2 distinct signals to enable from HTML):
- Repeated product card grid (`analysis.components` card/grid kind, 3+ occurrences)
  co-located with price tokens.
- Price tokens: regex `[$€£]|₫|VND|\bgiá\b` near repeated cards.
- Add-to-cart / buy affordances: `add[-_ ]?to[-_ ]?cart`, `buy now`, `mua ngay`,
  `thêm vào giỏ`, `data-product`, `.product`, `woocommerce` classes.
- Shop/category breadcrumb or nav: `/shop`, `/products`, `/cua-hang`, `/san-pham`.

Force-on paths (single signal sufficient): `--commerce` flag, or brief text
matching shop/e-commerce/bán hàng/cửa hàng → `detectedFrom` includes `flag`/`brief`.

**Signal-tagging for the CPT collision (red-team H7/A5):** the commerce card+price
heuristic overlaps `content-modeling`'s CPT-promotion heuristic (card/grid 3+,
content-modeling SKILL:32-33). To avoid suppressing legitimate CPTs (service /
portfolio) on a stray price token, tag the SPECIFIC component instances that carry
commerce signals (price + add-to-cart on the same card) in
`commerce.catalog`/analysis — Phase 3's CPT-skip applies only to those tagged
instances, NOT the whole model stage.

**`--auto` behavior (red-team S3/S4/H2):** under `--auto`, heuristic HTML detection
must NOT silently install Woo + seed untrusted data. Commerce proceeds under
`--auto` ONLY when forced by the explicit `--commerce` flag or a brief. Pure
heuristic detection under `--auto` records `commerce.enabled` as a SUGGESTION and
still requires confirmation before the `plugins`/seed stages act on it.

## Related Code Files

- Modify: `skills/html-analysis/SKILL.md` (new section "8. Detect commerce intent").
- Modify: `skills/html-analysis/references/component-detection.md` (add product-card
  signal table) — confirm file exists; create section if missing.
- Modify: `commands/build.md` (document `--commerce` in argument-hint + Input;
  add gate note after analyze; specify the `--auto` rule: heuristic-only detection
  needs confirmation even under `--auto`; `--commerce`/brief may proceed).
- Create (test fixtures):
  `examples/fixtures/shop-page.sample.html` (clear product grid + prices + add-to-cart),
  `examples/fixtures/landing-page.sample.html` (one price, no grid — must NOT trigger).

## Implementation Steps

1. **(TEST FIRST)** Write the two HTML fixtures and a documented manual check:
   running analyze (or the heuristic grep set) on `shop-page` → enabled;
   on `landing-page` → not enabled. Encode the grep/heuristic assertions in the
   phase so they can be re-run.
2. Add the detection section to `html-analysis` with the signal table + the
   ≥2-signal rule and force-on paths; write `commerce.enabled`,
   `commerce.detectedFrom`, and seed hints into `commerce.catalog` (rough
   category/product guesses for the model stage to refine).
3. Add `--commerce` to `build.md` and the post-analyze confirmation gate.
4. Validate.

## Success Criteria

- [ ] Fixtures written before skill edit.
- [ ] `shop-page.sample.html` → `commerce.enabled=true`, `detectedFrom` includes `html`.
- [ ] `landing-page.sample.html` → `commerce.enabled` stays false/absent (no false positive).
- [ ] `--commerce` flag forces enable with `detectedFrom` including `flag`.
- [ ] Commerce-signal-bearing card instances are tagged so Phase 3 CPT-skip is
      scoped to them (not the whole stage).
- [ ] `--auto` rule documented: heuristic-only detection still requires confirm.
- [ ] `build.md` documents flag + gate; `claude plugin validate .` passes.

## Risk Assessment

- Risk: false positives on pricing/portfolio pages → mitigation: ≥2-signal rule
  + per-instance signal tagging + mandatory user gate after analyze (never
  auto-proceed to install Woo, including under `--auto` for heuristic-only).
- Risk: VN-language signals missed → mitigation: include Vietnamese terms in the
  regex set (mua ngay / giá / cửa hàng / sản phẩm).
