# Red-Team Plan Review — Scope & Complexity Critic / Contract Verifier

Plan: `plans/2026-06-26-woocommerce-catalog-build-extension/`
Reviewer lens: YAGNI enforcer + interface/contract verification against codebase.
Date: 2026-06-26.

All findings below are grep/read-verified against the actual repo. 7 findings.

---

## Finding 1: "Existing mock-WP-CLI test pattern" is fabricated — no test harness exists
**Severity:** High
**Location:** `plan.md:38` ("mocked-WP-CLI exercises of seed helpers (the existing pattern proven on `seed-helpers.sh`)"); `phase-06-seeding.md:14` ("same approach already used to verify `seed-helpers.sh`"), `:59`, `:67`, `:77`.
**Flaw:** The TDD framing across the plan rests on a precedent that does not exist. There is no `scripts/tests/` directory, no `*mock-test*` file, and no test file of any kind in the repo. `seed-helpers.sh` exposes a `WP_CLI_RUN` override (`seed-helpers.sh:17-19,48-56`) that *would enable* mocking, but nothing has ever exercised it. The plan presents harness-building as a free "reuse" when it is net-new work.
**Failure scenario:** Phase 6 is sized as "mirror the existing mock test." In reality the executor must design the mock-`wp` stub, the call-recording mechanism, the bash+zsh dual-run rig, and the assertion format from scratch — the single most expensive deliverable in the plan, hidden behind a false "proven pattern" claim. Effort estimate is wrong; Phase 6 is under-scoped.
**Evidence:** `find . -path ./.git -prune -o -name "*test*" -print` → empty. `ls scripts/tests` → "No such file or directory". `grep -ni mock scripts/seed-helpers.sh` → no matches.
**Suggested fix:** Drop "existing/proven pattern" wording. Add an explicit Phase-6 sub-task: build the mock-`wp` harness (stub script + call log + bash/zsh runner) as a first-class deliverable, and re-estimate the phase accordingly.

---

## Finding 2: `ensure_wc_term` duplicates the existing `ensure_term` helper
**Severity:** Medium
**Location:** `phase-06-seeding.md:18-19,41` (new `ensure_wc_term <taxonomy> <name> <slug> [parent-slug]`); `brainstorm:89`.
**Flaw:** `seed-helpers.sh:237-252` already defines `ensure_term <taxonomy> <name> <slug>` — a taxonomy-agnostic, check-before-create, slug-keyed helper that records `term:${tax}:${slug}`. WooCommerce categories (`product_cat`) and attribute terms (`pa_<slug>`) are ordinary WP taxonomies; `ensure_term product_cat ...` already works unchanged. The only delta the new helper adds is the optional `[parent-slug]` for hierarchical categories. A whole parallel helper re-implements the same list/create/record logic for one extra argument. The brainstorm itself asks (`brainstorm:89`, review prompt) whether "ensure_term + meta suffice."
**Failure scenario:** Two near-identical term helpers drift over time (different stderr logging, different key formats), and the WC variant silently diverges from the idempotency contract the original guarantees.
**Evidence:** `seed-helpers.sh:237-252` (full `ensure_term` body — taxonomy passed as `$1`, slug-keyed dedupe).
**Suggested fix:** Extend `ensure_term` with an optional 4th `[parent-slug]` arg (resolve parent term_id, pass `--parent`) instead of adding `ensure_wc_term`. Keep only `ensure_wc_product` as genuinely new (it sets price/sku/stock meta the generic helper does not).

---

## Finding 3: Variable-product modeling is gold-plating that contradicts the plan's own scope
**Severity:** Medium
**Location:** `phase-01-schema-contract.md:38` (`type` enum `simple | variable`, `attributes`, `gallery`); `phase-03-modeling.md:32-33` (variable mapping rules); `plan.md:33` (out of scope: "complex variable products"); `plan.md:86-87` + `brainstorm:129` (open question, "best-effort, never block on complexity").
**Flaw:** The plan declares variable products out of scope and defers the decision to an open question, yet bakes variable-product structure into the schema (Phase 1), authors mapping rules for it (Phase 3), and carries a seeding fallback for it (Phase 6). Building schema fields + mapping logic + seed branches for a capability you have explicitly deferred is textbook YAGNI violation. Catalog MVP = simple products.
**Failure scenario:** Reviewers/executors spend effort on variation attribute modeling and `wp wc product_variation` paths that "never block on complexity" — i.e. code that, by its own rule, will be skipped at runtime whenever it gets hard. Dead-on-arrival branches.
**Evidence:** `phase-01-schema-contract.md:38`, `phase-03-modeling.md:32-33` vs `plan.md:33,86`.
**Suggested fix:** Cut `variable` from the SP1 schema enum and from modeling/seeding. Keep `type: "simple"` const only. Record variable products as a one-line SP3 backlog note. Resolve the open question to "defer entirely" before implementation, not during.

---

## Finding 4: WooCommerce theming across all 3 strategies is scope creep vs a classic-acf MVP
**Severity:** Medium
**Location:** `phase-05-convert-scaffold.md:32-37` (classic-acf + block-fse + page-builder branches), `:46-49` (3 reference edits), `:75-78` (admits FSE "broad", "non-goal of pixel-perfect").
**Flaw:** SP1's acceptance criterion is "`/shop/` and a single product render HTTP 200 with theme styling" (`plan.md:50`). classic-acf alone satisfies that with the most concrete mechanism (a `woocommerce/` template-override directory). The plan instead spreads Woo support across all three backends, while admitting FSE block-template work is "broad" and only "render + token styling," and page-builder is merely "a thin shell + note." Doing best-effort/caveated FSE and page-builder Woo theming in the same round is gold plating that triples Phase 5's surface for no MVP gain.
**Failure scenario:** Phase 5 balloons into three partially-validated theming paths; FSE/page-builder Woo overrides ship under-tested (no live e2e, per `phase-05:78`), creating the appearance of multi-strategy support that isn't actually verified.
**Evidence:** `phase-05-convert-scaffold.md:32-37,75-78` vs acceptance `plan.md:50`.
**Suggested fix:** SP1 = classic-acf Woo overrides only (full implementation + the one strategy that meets acceptance). Reduce block-fse and page-builder to documented "add `add_theme_support('woocommerce')`; full overrides deferred" stubs, or move them to a follow-up round.

---

## Finding 5: `commerce.settings` carries SP3 shipping/tax fields into the SP1 schema
**Severity:** Medium
**Location:** `phase-01-schema-contract.md:45` (`settings: { currency, currencyPos, weightUnit, baseLocation }`); `plan.md:31` (out of scope: "shipping/tax (SP3)").
**Flaw:** `weightUnit` is only meaningful for shipping calculation and `baseLocation` for tax/shipping zones — both explicitly SP3. Embedding them in the SP1 manifest contract is premature abstraction for a deferred sub-project. Only `currency` and `currencyPos` are catalog-display relevant.
**Failure scenario:** SP1 sets `weightUnit`/`baseLocation` that nothing in catalog depth reads, and SP3 later finds the contract shape already frozen by a round that never used or validated those fields.
**Evidence:** `phase-01-schema-contract.md:45` vs `plan.md:31`.
**Suggested fix:** Keep only `currency` + `currencyPos` in SP1 `commerce.settings`. Add `weightUnit`/`baseLocation` in SP3 when shipping/tax actually consume them (`additionalProperties: true` at root — `schemas/wp-build.schema.json:8` — means deferring them breaks nothing).

---

## Finding 6: 7 phases are too granular; Phase 4 is a single table row + a no-op verification
**Severity:** Medium
**Location:** `phase-04-plugin-selection.md` (whole phase); `plan.md:55-63` (phase table).
**Flaw:** Phase 4's entire functional change is one selection-table row mapping e-commerce → `woocommerce`, plus a step that explicitly *confirms an existing merge needs no change*: `plugin-selection/SKILL.md:89` already merges `select(.source=="wporg") | .slug` into `.wp-env.json`, and `woocommerce` is a bare wporg slug. That is a paragraph, not a phase. Each phase carries its own fixture + `claude plugin validate .` ceremony, so over-splitting multiplies overhead. Phase 1 (schema/contract) and Phase 2 (detection, which writes `commerce.enabled` into that contract) also share the analyze/contract boundary and are reasonable to merge.
**Failure scenario:** Ceremony cost (per-phase fixtures, validation runs, status tracking) exceeds the work; the plan reads as padded.
**Evidence:** `phase-04-plugin-selection.md:24-49` vs verified existing merge at `skills/plugin-selection/SKILL.md:89`.
**Suggested fix:** Fold Phase 4 into Phase 1 (schema + contract + the plugin-selection row are all contract-level edits). Consider merging Phase 1+2. Target ~4-5 phases.

---

## Finding 7: Detection heuristic scoring is over-engineered given the mandatory human gate
**Severity:** Low
**Location:** `phase-02-detection.md:26-35` (≥2-signal cluster rule, VN+EN regex sets, breadcrumb/nav matching); `plan.md:51` + `phase-02:58` (mandatory user confirmation gate after analyze).
**Flaw:** The plan specifies a formal multi-signal scoring rubric to avoid false positives, then *also* requires a mandatory user gate that confirms `commerce.enabled` before any Woo install. With an explicit `--commerce` flag, brief override, and a human gate as the real safety net, the elaborate ≥2-distinct-signal scoring machinery is largely belt-and-suspenders. (Low severity: this lives in skill markdown, so cost is modest — but it is still avoidable complexity in guidance the model must follow.)
**Failure scenario:** Two competing "sources of truth" for enablement (heuristic score vs human gate) create ambiguity about when commerce auto-enables, and the rubric invites over-fitting to the two sample fixtures.
**Evidence:** `phase-02-detection.md:26-35` vs gate at `phase-02-detection.md:58` / `plan.md:51`.
**Suggested fix:** Reduce HTML detection to a single coarse "looks like a shop (repeated priced cards)" surfaced *to the gate* as a suggestion; let flag/brief + the human gate be authoritative. Drop the formal ≥2-signal scoring rubric.

---

## Verified-correct claims (not findings, for calibration)
- `additionalProperties: true` at schema root — true (`schemas/wp-build.schema.json:8`); `commerce` can be added optionally with zero back-compat break.
- `ecommerce` already in `plugins[].category` enum — true (`schemas/wp-build.schema.json:169`).
- Existing wporg→`.wp-env.json` merge picks up the slug unchanged — true (`plugin-selection/SKILL.md:89`).
- `import_media` dedupes by filename; `set_featured_image`, `_seed_record_key` exist — true (`seed-helpers.sh:254-293,66`).
- plugin-data-seeding has a routing table with a forms branch to mirror — true (`plugin-data-seeding/SKILL.md:34-42`).
- No commerce/Woo work in `plans/20260626-wp-pro-max-kit` — true (grep empty); no duplication.
- All referenced files exist (theme-conversion refs, component-detection.md, manifest-contract.md, plugin-data-seeding refs).

## Unresolved questions
- Does any consumer in SP1 read `commerce.settings.currencyPos`, or is even that display field unused until checkout? Confirm before adding.
