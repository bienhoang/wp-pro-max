# Brainstorm — Theme Branding & Colors customization (logo + deep colors + reset)

**Date:** 2026-07-01
**Status:** Approved → handing to `/ck:plan`
**Modes:** plain markdown (no `--html`/`--wiki`)

## Problem statement

Generated WordPress themes ship with **hardcoded** branding. Site owner cannot,
without a developer, change the **logo** (header + footer) or the **theme colors**
(button/text/bg/…). Want an end-user editing UI baked into the generated theme,
with a **reset-to-default** path back to the original design.

## Exact requirements (locked)

- **Expected output:** an in-WP editing UI inside every generated theme that lets
  the site owner (1) set header + **separate footer** logo, (2) edit theme colors
  deeply, (3) **reset to defaults**. Defaults = the `designTokens` values.
- **Acceptance:** owner uploads logos + changes colors in wp-admin → reflected on
  front-end → "Reset to defaults" returns to the original design-token look.
- **Scope boundary:** all 3 strategies, **strategy-native** (no new unified UI
  framework). No new pipeline stage. Colors editable = **every `:root` color
  token** (deep but bounded; NOT every color literal in `main.css`).
- **Constraints:** manifest-driven; namespaced w/ theme slug; i18n + escaped;
  idempotent (re-run rewrites same files); heavy authoring → `wp-theme-developer`.
- **Touchpoints:** `convert` (header/footer render + `:root` defaults),
  `scaffold` (registration wiring), `designTokens`, `wp-handoff` (docs).

## Decisions

| Decision | Choice |
|----------|--------|
| Strategies | All three, **strategy-native** |
| classic-acf UI home | **WordPress Customizer** |
| Color depth | **Every `:root` color token** (curated-complete) |
| Footer logo | **Separate uploadable** footer logo (fallback → site logo) |
| Pipeline placement | Wire into existing `convert` + `scaffold` — **no new stage** |

## Approaches evaluated

- **A — Strategy-native (chosen).** Lean on each backend's built-in editor; build
  custom UI only where missing. *Pro:* least code, idiomatic, YAGNI/KISS. *Con:*
  editing UX differs per strategy.
- **B — Unified custom UI on all strategies.** One panel injected everywhere.
  *Pro:* consistent UX. *Con:* fights + duplicates native editors (FSE Global
  Styles, Elementor Site Settings); violates YAGNI. **Rejected.**
- **classic-acf UI home:** Customizer (chosen — live preview, native color/image
  controls, idiomatic) vs ACF options page (weaker preview) vs custom Settings
  page (most code). **Customizer chosen.**

## Recommended solution

Shared concept: a **token registry generated from `designTokens`** = single source
of truth for defaults, Customizer controls, inline-CSS emitter, and reset. The
design-token values ARE the reset target.

### classic-acf (the real build) — `inc/customizer.php` (scaffold stage)
- **Logos section:** header via native `custom_logo`; new `footer_logo`
  (`WP_Customize_Image_Control`); live preview.
- **Colors section:** auto-generate one `WP_Customize_Color_Control` per color CSS
  variable in `:root`, labelled/grouped from the registry.
- **Reset:** custom "Reset to defaults" button control; JS resets every control to
  its token default (live preview); save clears overrides.
- **Emit:** `wp_add_inline_style` re-declares `:root{ --x: <theme_mod> }` only for
  **overridden** vars → unset vars fall back to `style.css` defaults (idempotent).
- `footer.php` renders `footer_logo` (fallback → site logo).
- Registry `inc/theme-tokens.php` (or manifest-derived) holds defaults.

### block-fse — mostly native
- Colors/buttons/text/bg **+ reset = native Global Styles** (Site Editor → Styles
  → "Reset to defaults"). Header logo = Site Logo block (already present).
- **Only custom piece:** separate **footer logo** — small `footer_logo` control +
  render in `parts/footer.html`.

### page-builder (Elementor) — native
- Colors = Elementor **Global Colors**; logo = Site Identity widget.
- Separate footer logo = footer-template logo widget / same `footer_logo` mod.

### Cross-cutting
- Namespaced, i18n, escaped, idempotent.
- `wp-handoff` doc: per-strategy "change logo & colors / reset" section.
- Optional `theme.customizer` manifest record (editable vars + strategy path).

## Risks & mitigations

1. **"Every variable" panel bloat** → bounded to `:root` color tokens (curated-
   complete), not every CSS color literal. Mitigated by decision.
2. **FSE footer logo** not fully native → one small custom control. Accepted.
3. **FSE "deep" = theme.json palette** (native edits presets, not arbitrary vars);
   slightly different surface than classic but consistent in spirit.
4. **Customizer live-preview JS** adds `customizer-preview.js` + controls JS —
   modest surface; keep small.

## Success metrics

- Owner sets header + footer logo + every `:root` color, sees it live + on
  front-end, and resets to the exact design-token defaults — on a classic-acf
  build, with no PHP notices and no developer involvement.
- FSE/Elementor builds expose the same capability via native editors + the footer-
  logo control.
- Re-running `scaffold` is idempotent (same files, no drift).

## Next steps / dependencies

- Plan placement: extend `wp-scaffold` (+ small `convert` footer-logo slot) and the
  three `theme-conversion` references; update `wp-handoff`.
- Depends on `designTokens` being populated (tokens stage) for defaults.

## Open questions

- Manifest: add `theme.customizer` to `schemas/wp-build.schema.json`, or keep the
  registry purely in-theme? (Lean: in-theme registry; record a boolean flag only.)
- Color grouping/labels in the Customizer panel for large token sets — auto from
  slug, or a curated label map? (Default: humanize the slug.)
