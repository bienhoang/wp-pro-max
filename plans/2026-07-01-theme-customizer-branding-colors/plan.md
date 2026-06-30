---
title: "Theme Branding & Colors customization (logo + deep colors + reset)"
description: ""
status: complete
priority: P2
branch: "feat/seed-batch-eval-file"
tags: []
blockedBy: []
blocks: []
created: "2026-06-30T20:12:09.530Z"
createdBy: "ck:plan"
source: skill
---

# Theme Branding & Colors customization (logo + deep colors + reset)

## Overview

Bake two end-user theme-customization features into every generated WordPress theme:
**(1) logo editing** — header + a *separate* footer logo; **(2) deep color editing** —
every `:root` color token editable; both with a **reset-to-defaults** path. Defaults
come from `designTokens`. Strategy-native: `classic-acf` gets a custom WordPress
Customizer UI; `block-fse` and `page-builder` reuse native editors (Global Styles /
Elementor Site Settings), with only a small custom **footer-logo** control added.

No new pipeline stage. Work wires into existing `convert` (footer-logo render slot)
and `scaffold` (the customization wiring) stages; heavy PHP/JS authoring is delegated
to the **wp-theme-developer** agent. Source brainstorm:
[`brainstorm-report.md`](./brainstorm-report.md).

### Design invariants (apply to every phase)

- **Single source of truth:** an editable color-token registry whose `cssVar` is the
  **actual `:root` custom-property name `convert` emits** (NOT a re-applied
  `--color-<slug>` template — slugs `foreground`/`background` emit `--color-fg`/
  `--color-bg`, per `theme-json-mapping.md:69-70`). Either `convert` emits
  `--color-<slug>` verbatim as a hard contract, or each token carries an explicit
  `cssVar` through `designTokens`. Same registry feeds Customizer controls, the
  inline-CSS emitter, and reset. <!-- Updated: Red Team Session 1 - var-name contract -->
- **Reset = full revert (colors + logos).** Inline CSS emits a `:root` override only
  for vars differing from their token default; reset clears color overrides **and** the
  header/footer logos → defaults + no-logo state reapply. Reset correctness requires
  `main.css` to carry **no conflicting `:root` color vars** (it loads after `style.css`);
  `convert` strips them or the emitter always emits full defaults.
  <!-- Updated: Red Team Session 1 - main.css :root hazard -->
- **Footer logo:** separate `<slug>_footer_logo` stored as an **attachment ID**
  (`WP_Customize_Media_Control` + `absint`), rendered via `wp_get_attachment_image()`,
  fallback → site/header logo → title. The render helper is defined (guarded) in
  `convert`, never only in `scaffold`. <!-- Updated: Red Team Session 1 - media control + guarded helper -->
- **Colors = hex + function-colors.** Tokens may be `#hex`, `rgb(a)`, or `hsl(a)`
  (`extract-tokens.mjs:96` harvests them); sanitize with a function-color-aware allowlist
  (`#hex|rgb()|rgba()|hsl()|hsla()`), NOT bare `sanitize_hex_color`. Re-validate on
  **output** too (theme_mods set via DB import/`wp eval` bypass the save callback).
  <!-- Updated: Red Team Session 1 - hex-only reversed -->
- **Slug safety:** derive `cssVar`/mod keys only from a `sanitize_key()`-ed slug; never
  echo a raw token `name` into CSS (untrusted source-CSS property names → injection).
- **theme_mod state is DB-resident** and survives the `convert` theme-dir wipe but is
  NOT in files: re-running `convert` requires a follow-on `scaffold`; `ship` must
  migrate `theme_mods_<slug>` (export local → import remote) or branding is lost.
- **Conventions:** namespace all PHP fns + mod keys with theme slug; i18n every string;
  escape all output in its correct context (CSS context ≠ `esc_attr`); `label`/`group`
  in the registry are **pure functions of the slug** (deterministic) so `scaffold --force`
  is byte-stable; scaffold GCs `<slug>_color_*` mods absent from the current registry.
- **Editable color set = `:root` color tokens only** (curated-complete), NOT every
  color literal in `main.css`.

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Foundation & Scaffold Contract](./phase-01-foundation-scaffold-contract.md) | Complete |
| 2 | [classic-acf Customizer](./phase-02-classic-acf-customizer.md) | Complete |
| 3 | [FSE & Page-Builder Native](./phase-03-fse-page-builder-native.md) | Complete |
| 4 | [Handoff & Verification](./phase-04-handoff-verification.md) | Complete |

Phase 2 depends on Phase 1 (the registry + emitter contract). Phase 3 depends on
Phase 1 (shared footer-logo convention). Phase 4 depends on 2 + 3.

## Acceptance (whole feature)

- On a `classic-acf` build: owner sets header + footer logo, edits every `:root`
  color, sees changes live in the Customizer preview + on the front-end, and "Reset
  to defaults" returns to the exact design-token look — no PHP notices, no dev help.
- On `block-fse` / `page-builder`: same capability via native editors + the added
  footer-logo control.
- Re-running `scaffold` (and `convert`) is idempotent — identical files, no drift.

## Dependencies

- **Upstream data:** `designTokens` must be populated (tokens stage) — supplies color
  defaults. `analysis`/`contentModel` already available at scaffold time.
- **Coordination (soft):** [`2026-07-01-parallel-build-orchestration`](../2026-07-01-parallel-build-orchestration/plan.md)
  (Theme-Convert Fan-out) rewrites how `convert` authors foundation files
  (`header.php`/`footer.php`/`parts/footer.html`) — the same files Phase 1/2/3 add the
  footer-logo slot to. Additive, no hard block; whichever lands first, the other must
  keep the footer-logo render slot in the foundation agent's writable set.

## Validation Log

### Session 1 — 2026-07-01 (`/ck:plan validate`)

**Verification (Standard tier, 4 phases — Fact Checker + Contract Verifier):**
- Claims checked: 11 · Verified: 11 · Failed: 0 · Unverified: 0
- Confirmed: all referenced plan files exist (`references/manifest-contract.md`,
  `references/classic-acf.md`, `skills/wp-handoff/SKILL.md`,
  `skills/theme-conversion/references/page-builder.md`, wp-classic refs); classic
  enqueue handle is `<slug>-main` (inline-CSS target valid); `page-builder` uses the
  same thin `header.php`/`footer.php` shell as classic (host-theme footer render shares
  the helper — but NOT when Elementor manages the footer, see Red Team F12);
  `inc/enqueue.php` is scaffold-generated; soft-coordination plan path resolves.

**Decisions confirmed:**
1. **Reset scope = colors + logos.** "Reset to defaults" reverts colors to token
   defaults AND clears uploaded header/footer logos (full revert). → Phase 2.
2. **Color format = hex only.** ~~Tokens are `#rrggbb`; `sanitize_hex_color`.~~
   **SUPERSEDED by Red Team Session 1 (Finding 2):** `extract-tokens.mjs:96` harvests
   `rgba()/hsl()` and curation never forces hex → now **hex + function-colors** with an
   allowlist sanitizer. → Phase 1, Phase 2.
3. **FSE footer logo = Customizer image control (Option A).** Same `<slug>_footer_logo`
   key + control as classic; render `<img>` in `parts/footer.html`. Option B
   (theme.json + Image block) rejected for DRY consistency. → Phase 3.
4. **Manifest = single boolean `theme.customization.enabled`** in
   `schemas/wp-build.schema.json`; registry stays in-theme. → Phase 1.

### Whole-Plan Consistency Sweep

Re-read `plan.md` + all 4 phase files after propagation. Reconciled: reset scope now
says colors+logos everywhere (no "optionally logos" ambiguity); hex-only resolves the
Phase-2 color-sanitize risk (downgraded); FSE footer-logo Option A locked (no deferred
choice in Phase 3); manifest flag fixed to the boolean (no "decide here" in Phase 1).
No unresolved contradictions. **Recommendation: proceed.**

## Red Team Review

### Session 1 — 2026-07-01 (3 reviewers: Security Adversary, Assumption Destroyer, Failure Mode Analyst)

**Findings:** 15 (15 accepted, 0 rejected) · **Severity:** 6 Critical, 6 High, 3 Medium.
All findings carried `file:line` codebase evidence; the three load-bearing claims
(rgba/hsl emission, `--color-fg`/`--color-bg` abbreviation, convert wipe+activate) were
independently re-verified before acceptance.

| # | Finding | Sev | Disp | Applied to |
|---|---------|-----|------|-----------|
| 1 | Registry `--color-<slug>` ≠ emitted `--color-fg/bg` → edits/reset hit phantom vars | Critical | Accept | P1, P2 |
| 2 | "Hex-only" false — tokens can be rgba()/hsl(); `sanitize_hex_color` nukes them | Critical | Accept | P1, P2 (→ hex+func sanitizer) |
| 3 | `footer.php` (convert, activated) calls helper defined in scaffold → undefined-fn fatal | Critical | Accept | P1, P2 (guarded helper in convert) |
| 4 | Ship drops `theme_mods_<slug>` (logos+colors) on deploy | Critical | Accept | P4 (migrate theme_mods) |
| 5 | FSE authors no customizer file/hook → footer-logo control never exists; menu hidden | Critical | Accept | P3 |
| 6 | Unsanitized slug/name → CSS property-name / `</style>` injection (stored XSS) | Critical | Accept | P1, P2 (sanitize_key) |
| 7 | `footer_logo` callback ambiguous + render escaping + ID dangles on reseed | High | Accept | P2 (Media control + absint + wp_get_attachment_image) |
| 8 | convert resume-wipe deletes scaffold customizer code; pin `<slug>-main` handle | High | Accept | P1, P2, P4 |
| 9 | Reset breaks if `main.css` re-declares `:root` (loads after style.css) | High | Accept | P1, P2, P4 |
| 10 | Idempotency false: token rename orphans mods; label/group non-deterministic | High | Accept | P1, P4 |
| 11 | FSE static `parts/footer.html` has no block-binding source for footer image | High | Accept | P3 |
| 12 | page-builder footer mechanism contradictory; no control authored | High | Accept | P1, P3 |
| 13 | `designTokens.colors[]` schema unenforced; `value` vs `color` key ambiguity | Medium | Accept | P1 |
| 14 | Logo reset can't live-preview (core controls = `transport:refresh`) | Medium | Accept | P2 |
| 15 | New theme_mod store vs existing ACF options branding — reset won't touch ACF | Medium | Accept | P2 |

**Re-decisions (user, Red Team Session 1):** color format → **hex + rgba/hsl** (allowlist
sanitizer); ship → **migrate `theme_mods_<slug>`** (all strategies); footer logo →
**attachment ID** (`WP_Customize_Media_Control`).

### Whole-Plan Consistency Sweep

Re-read `plan.md` + all 4 phase files after applying the 15 findings. Reconciled:
hex-only removed everywhere (invariants, Validation Log marked superseded, P1/P2);
`cssVar` now sourced from the emitted `:root` (not the slug template) across invariants/
P1/P2; footer-logo storage = attachment ID consistent in invariants/P2/P4; guarded
render helper located in `convert` in invariants/P1/P2; theme_mod migration present in
invariants/P4; FSE + page-builder customizer wiring now authored (not doc-only) in P3.
No unresolved contradictions. **Recommendation: proceed** (re-run validate optional;
all gates passed).

## Implementation Log

### Session — 2026-07-01 (`/cook`, straight-through)

All 4 phases implemented; 13 files changed + 1 new
(`skills/wp-scaffold/references/theme-customization.md`). Each phase
`claude plugin validate .`-gated. All 19 embedded PHP blocks pass `php -l` (8.2 via
Docker); both customizer JS files pass `node --check`; schema parses.

**Empirical gates run now (wp-env-independent):**
- Function-color sanitizer executed against 15 vectors — all valid hex/rgb(a)/hsl(a)
  pass; every CSS-breakout / `</style>` / `url(javascript:)` / `expression()` /
  malformed vector dropped (F6).
- Schema `value` pattern tightened to mirror the PHP grammar — rejects
  `rgb(</style>)`, `rgb(0;}body{)`, invalid 5/7-digit hex (F2/F13/L1).
- Docs-reconcile sweep: footer-logo key, `--color-<slug>` verbatim contract,
  `<slug>-main` handle consistent across all touched files; no `--color-fg/bg`
  emissions remain.

**Deferred (flagged, not skipped):** the full wp-env behavioral run (activate /
set-mod / reset / footer-logo render) and the static `cssVar`/`main.css` greps —
they require a generated target theme, which this plugin repo does not contain. The
recipe lives in `theme-customization.md §7` for the next real build.

### Code Review — resolved (6 findings)

A `code-reviewer` pass confirmed the server-side contract but found defects in the
canonical templates (which author verbatim into every generated theme). All fixed:
- **H1** footer-logo live preview → replaced brittle `.footer-logo` + `wp.media`
  path with a **selective-refresh partial** (`.site-branding--footer`, renders via
  the guarded helper).
- **H2** color reset previewed `setting.default` (undefined in WP's setting JSON) →
  now reads a **localized registry map** (`AcmeCustomizer.tokens`); also removes the
  hardcoded slug lists, tightening F10 determinism.
- **M1** `ACME_VERSION` undefined-constant fatal risk in the customizer enqueues →
  use `wp_get_theme()->get( 'Version' )`.
- **M2** FSE bound `wp:image` rendered empty + double-rendered with `wp:site-logo` →
  binding now falls back to the site-logo URL, single image; **PHP-rendered footer
  pattern** documented as the robust FSE default.
- **L1** schema `value` pattern widened too far → tightened to the PHP char class.
- **L2** "asserts the handle" overstated → reworded to the real fallback-then-no-op.
