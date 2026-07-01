---
phase: 1
title: "Foundation & Scaffold Contract"
status: complete
priority: P1
dependencies: []
effort: "S-M"
---

# Phase 1: Foundation & Scaffold Contract

## Overview

Define the shared contract every strategy follows: the editable color-token registry
(from `designTokens`), the inline-CSS emitter + reset semantics, the footer-logo
convention, and where this work lands in the pipeline. Deliverable is **spec + wiring
in `wp-scaffold`**, not strategy-specific PHP (that's Phase 2/3). This phase makes the
rules canonical so the three backends stay consistent.

## Requirements

- Functional: one documented derivation `designTokens.colors[]` → registry → editable-
  control list, where each token's `cssVar` is the **actual `:root` var name `convert`
  emits** (see var-name contract below). A `customization` step added to the `scaffold`
  stage that delegates per-strategy authoring. Footer-logo key + fallback rule defined
  once. Defensive handling (skip + warn) for malformed/missing token entries.
- Non-functional: KISS/DRY — no duplicated token lists; **deterministic** registry so
  `scaffold --force` is byte-stable; namespaced + i18n conventions stated so Phase 2/3
  agents inherit them.

## Architecture

- **Token registry.** Canonical shape the scaffold passes to the theme agent:
  ```
  colorTokens[] = [ { cssVar: "--color-primary", slug: "primary",
                      label: "Primary", default: "#1a73e8", group: "brand" }, … ]
  ```
  Built from the **curated** `designTokens.colors[]` entry `{ name, slug, value, role }`
  (`design-tokens/SKILL.md:54`) — read `slug` + `value`, defensive skip+warn if absent.
  <!-- Updated: Red Team Session 1 (F13) - real entry shape -->
  - **Var-name contract (F1).** `cssVar` MUST equal the var `convert` actually wrote to
    `:root`. The token reference abbreviates some slugs (`foreground`→`--color-fg`,
    `background`→`--color-bg`, `theme-json-mapping.md:69-70`). Resolve by making `convert`
    emit `--color-<slug>` **verbatim** (hard contract, no abbreviation/collapse) AND
    carry the resulting `cssVar` in the registry. Registry/emitter/reset all read that
    one `cssVar`. Never re-apply a `--color-<slug>` template downstream.
  - **Slug safety (F6).** `slug` is `sanitize_key()`-ed before forming `cssVar` and the
    `<slug>_color_<slug>` mod key. The raw token `name` is NEVER echoed into CSS.
  - **Determinism (F10).** `label` (humanize) and `group` (brand/text/surface/state) are
    **pure functions of the slug** — a fixed lookup/rule computed by the scaffold script,
    not free-form by the agent — so re-runs are byte-identical.
- **Color value contract (F2).** Token values may be `#hex`, `rgb(a)`, or `hsl(a)`
  (`extract-tokens.mjs:96`). The sanitizer is a **function-color allowlist**
  (`/^#[0-9a-f]{3,8}$|^rgba?\(...\)$|^hsla?\(...\)$/i`), applied on save AND re-applied on
  **output** (DB-imported / `wp eval` mods bypass the save callback). Drop-on-fail.
- **Emitter + reset contract (F9):**
  - Defaults live in the theme's `style.css`/`theme.json` `:root` (emitted by `convert`).
    `convert` must ensure `assets/css/main.css` carries **no conflicting `:root` color
    vars** (it loads after `style.css`), else reset reverts to the raw source color, not
    the token default. Alternative: emitter always emits the FULL default `:root`.
  - A runtime override re-declares `:root{ --x: <sanitized value> }` **only** for tokens
    whose stored value ≠ default; values escaped for **CSS context** (not `esc_attr`).
  - "Reset" clears color overrides + logos → defaults + no-logo reapply.
  - **GC (F10):** on scaffold, prune `<slug>_color_*` theme_mods absent from the current
    registry (orphans from a token rename), so stale mods can't silently override.
- **Footer-logo convention (F3/F7):** key `<slug>_footer_logo`, stored as an
  **attachment ID** (`WP_Customize_Media_Control` + `absint`). One **guarded** render
  helper `<slug>_the_footer_logo()` — `wp_get_attachment_image()` if set, else
  `the_custom_logo()`, else site title. **Defined in `convert`** (foundation) behind a
  `function_exists`/empty-mod guard so an activated-but-not-yet-scaffolded theme never
  fatals; scaffold only adds the control that sets it.
- **Pipeline placement (F3/F5/F8):** `scaffold` adds the customization step (routes by
  `strategy`). `convert` gains the **guarded footer-logo render helper + render slot** in
  its foundation files. Because `convert` wipes+recreates the theme dir and activates it
  (`theme-conversion/SKILL.md:45-51,154-158`), the orchestrator must **re-chain
  `scaffold` after any `convert` re-run** when `theme.customization.enabled`. Pin the
  inline-CSS style handle (`<slug>-main`) as a contract value both this plan and the
  fan-out plan must preserve, and have the emitter assert the handle is registered.

## Related Code Files

- Modify: `skills/wp-scaffold/SKILL.md` — add the "Theme customization (logos + colors
  + reset)" step: derive `colorTokens` from `designTokens`, route by strategy, list the
  new files each strategy writes, state the namespace/i18n/idempotency constraints, and
  the wp-theme-developer delegation (paths, acceptance, constraints).
- Modify: `references/manifest-contract.md` — document the footer-logo key, the
  var-name (`cssVar`) contract, the `<slug>-main` inline-style handle contract, and the
  convert→scaffold re-chain rule as cross-stage conventions (authoritative, not buried in
  one skill).
- Modify: `schemas/wp-build.schema.json` — (a) add `theme.customization.enabled`
  (boolean); (b) **tighten `designTokens.colors[].items`** to require `slug` (kebab
  `pattern`) + `value` (color `pattern`: hex|rgb(a)|hsl(a)), reconciling the `value` vs
  theme.json `color` key (F13). Registry stays in-theme.
  <!-- Updated: Red Team Session 1 (F2/F6/F13) - hex-only superseded; schema tightened -->
- Modify: `references/classic-acf.md` (+ block-fse token emit) — make `convert` emit
  `:root` color vars as `--color-<slug>` **verbatim** (no `fg`/`bg` abbreviation) and
  strip any `:root` color redeclarations from `assets/css/main.css` (F1/F9).
- Create: `skills/wp-scaffold/references/theme-customization.md` — the deep reference
  (registry derivation table, emitter pseudo-code, reset semantics, footer-logo helper,
  per-strategy file matrix) that Phase 2/3 link to instead of re-explaining.

## Implementation Steps

1. Write `references/theme-customization.md`: registry derivation table (real entry
   `{name,slug,value,role}` → `sanitize_key`'d slug → `cssVar`), the **var-name verbatim
   contract**, the function-color sanitizer (save + output), the emitter + reset contract
   incl. `main.css` `:root`-free requirement + orphan-mod GC, the **guarded** footer-logo
   helper (attachment ID), and a per-strategy file matrix (classic → `inc/customizer.php`
   + JS; fse → customizer file + functions.php hook + footer block-binding; builder →
   chosen footer mechanism + native colors note).
2. Add the customization step to `wp-scaffold/SKILL.md` inputs + procedure; reference the
   new doc; state constraints (namespace, i18n, CSS-context escape, determinism,
   orphan-GC, agent delegation).
3. Record the footer-logo key, `cssVar` contract, `<slug>-main` handle contract, and the
   convert→scaffold re-chain rule in `references/manifest-contract.md`.
4. Schema: add `theme.customization.enabled`; tighten `designTokens.colors[].items`
   (`slug`/`value` patterns).
5. Make `convert` emit `--color-<slug>` verbatim + strip `main.css` `:root` color vars.
6. Syntax-gate any touched JSON/scripts; `claude plugin validate .`.

## Success Criteria

- [ ] `theme-customization.md` defines registry (real entry shape + `cssVar` verbatim
      contract + sanitize_key slug), function-color sanitizer, emitter+reset (incl.
      main.css `:root`-free + orphan GC), guarded attachment-ID footer helper, and the
      per-strategy file matrix — Phase 2/3 implementable with no further design.
- [ ] `wp-scaffold/SKILL.md` has the customization step + constraints (CSS-context
      escape, determinism, GC); still lean.
- [ ] `manifest-contract.md` records footer-logo key, `cssVar` contract, `<slug>-main`
      handle contract, convert→scaffold re-chain rule.
- [ ] Schema: `theme.customization.enabled` added AND `designTokens.colors[]` tightened
      (`slug`/`value` patterns); `convert` emits `--color-<slug>` verbatim; `main.css`
      `:root`-free. `claude plugin validate .` passes.

## Risk Assessment

- **Var-name contract drift (F1).** If `convert` keeps abbreviating (`fg`/`bg`), the
  registry silently edits phantom vars. Mitigation: verbatim-emit contract + carry
  `cssVar`; Phase 4 greps the emitted `:root` against the registry.
- **`convert` emit change blast radius.** Forcing `--color-<slug>` verbatim + stripping
  `main.css` `:root` touches existing token output. Mitigation: scope to color vars;
  keep other tokens unchanged; verify theme still renders.
- **Coordination with the fan-out plan.** Footer-logo render slot + `<slug>-main` handle
  must stay stable in the foundation agent's writable set. Mitigation: pin both in
  `manifest-contract.md` so either plan honors them.
