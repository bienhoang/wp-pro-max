---
name: html-optimization
description: >-
  Optimizes and cleans static HTML/CSS before WordPress conversion. Dedupes and
  consolidates markup and CSS, applies semantic-HTML and accessibility fixes
  (alt text, heading order, landmarks, contrast notes), and produces an image
  optimization plan (webp/avif, responsive sizes, lazy-load). Writes an
  optimized copy of the source without mutating originals. Reads `analysis` and
  writes `optimization.*` (outputDir, imagePlan, a11yFixes, notes) in
  wp-build.json. Use after html-analysis, before theme conversion, or when the
  pipeline reaches the `optimize` stage, or when asked to clean up source markup
  or plan image optimization for a WordPress build.
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash]
---

# HTML Optimization (`optimize` stage)

Clean the source so the conversion stage starts from semantic, deduplicated,
accessible markup. Read `analysis` (and `source`); write `optimization`.
**Never mutate originals** — always emit into a fresh `outputDir`.

## 0. Resume guard

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh"
wpbuild_is_done optimize && [[ "${1:-}" != "--force" ]] && { echo "optimize already done"; exit 0; }
wpbuild_progress optimize in-progress
```

## 1. Make a working copy

```bash
SRC_DIR=$(wpbuild_get '.source.htmlPaths[0]' | xargs dirname)
OUT_DIR="./.wp-pro-max/optimized"
mkdir -p "$OUT_DIR"
cp -R "$SRC_DIR/." "$OUT_DIR/"     # operate only inside OUT_DIR from here on
```

All edits below target files **inside `$OUT_DIR`**. Originals stay untouched.

## 2. Markup cleanup & dedupe

- Remove dead/commented markup, empty wrappers, editor cruft, tracking junk.
- Collapse `<div>` soup into landmarks: `<header> <nav> <main> <section>
  <article> <aside> <footer>`.
- Replace presentational tags (`<b>/<i>` for meaning, `<font>`) with semantic
  equivalents (`<strong>/<em>`, CSS).
- Factor repeated components (from `analysis.components`) into a single canonical
  markup snippet so the conversion stage maps one shape → one template part.
- Deduplicate inline styles: lift repeated declarations into shared classes.

## 3. CSS consolidation

- Merge duplicate rules and identical declaration blocks.
- Group repeated literal values toward variables (pair with `tokens` stage):
  repeated colors/spacing become `var(--…)` candidates — note them, do not
  invent a token system here (that is the `tokens` stage's job).
- Drop unused selectors when safe (cross-check against the markup in `$OUT_DIR`).
- Keep one ordered stylesheet per concern; remove `!important` where avoidable.

## 4. Accessibility fixes

Apply concrete, verifiable fixes and log each one in `a11yFixes`:

- **Images:** every `<img>` gets meaningful `alt`; decorative images get
  `alt=""`. Infer alt from nearby heading/caption/file name.
- **Headings:** exactly one `<h1>` per page; no skipped levels (h2→h4).
- **Landmarks:** ensure `<main>`, labelled `<nav aria-label>`, `<header>`/`<footer>`.
- **Forms:** every control has a `<label for>` or `aria-label`; group with
  `<fieldset>/<legend>`.
- **Interactive:** real `<button>`/`<a>` instead of click-bound `<div>`; visible
  focus states; `aria-expanded` on toggles.
- **Contrast:** compute text/background ratios from the palette; flag pairs
  below WCAG AA (4.5:1 normal, 3:1 large) as notes — do not silently recolor
  brand values; recommend the nearest accessible adjustment.

See `references/accessibility-checklist.md` for the full WCAG-AA pass list.

## 5. Image optimization plan

Do **not** transcode here (no binaries assumed). Produce a plan the scaffold/
seed stages execute. For each image in `analysis.assets.images`:

```json
{
  "src": "assets/hero.jpg",
  "role": "hero",
  "formats": ["avif", "webp", "jpg"],
  "responsiveSizes": [480, 768, 1024, 1600],
  "lazyLoad": true,
  "fetchPriority": "high",
  "dimensions": "from markup or intrinsic if known"
}
```

Rules: above-the-fold/hero → `loading="eager"` + `fetchpriority="high"`;
everything else → `loading="lazy"`. Recommend `avif`+`webp` with original
fallback, and `srcset`/`sizes` per breakpoint (from `designTokens.breakpoints`
when available). Detail in `references/image-optimization.md`.

## 6. Write outputs

```bash
wpbuild_set '.optimization' "$OPT_JSON"
# example assembly:
wpbuild_merge '{"optimization":{"outputDir":"./.wp-pro-max/optimized"}}'
wpbuild_progress optimize done "cleaned N files, K a11y fixes, M images planned"
```

`optimization` shape: `{ outputDir, imagePlan[], a11yFixes[], notes[] }`.

## Output contract

Print: files cleaned, count of a11y fixes (by category), images in the plan, and
any contrast warnings the user must approve. The optimized copy lives in
`outputDir` and becomes the input for `theme-conversion`.

See also: `references/accessibility-checklist.md`, `references/image-optimization.md`.
