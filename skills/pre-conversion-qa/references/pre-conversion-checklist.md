# Pre-Conversion Checklist

What `/wp-pro-max:pre-conversion-qa` checks before theme conversion.

## Quick mode (default)

Runs without a browser.

| Check | Tool | Failure condition |
|-------|------|-------------------|
| Alt text on images | `pre-qa-a11y.mjs` | Any `<img>` without `alt` or `role="presentation"`. |
| Single h1 | `pre-qa-a11y.mjs` | Zero or multiple `<h1>`. |
| Heading order | `pre-qa-a11y.mjs` | Skipped levels (e.g. `h2` → `h4`). |
| Main landmark | `pre-qa-a11y.mjs` | Missing or multiple `<main>`. |
| Nav label | `pre-qa-a11y.mjs` | `<nav>` without `aria-label` or `aria-labelledby`. |
| Form labels | `pre-qa-a11y.mjs` | Form control without `<label>`, `aria-label`, or `title`. |
| Inline contrast | `pre-qa-a11y.mjs` | Inline color pairs below WCAG AA (4.5:1). |
| `<html lang>` | `pre-qa-html-validity.mjs` | Missing `lang` attribute. |
| `<title>` | `pre-qa-html-validity.mjs` | Missing or empty `<title>`. |
| Charset | `pre-qa-html-validity.mjs` | Missing charset meta. |
| Duplicate IDs | `pre-qa-html-validity.mjs` | Duplicate `id` values. |
| Brand colors | `pre-qa-brand.mjs` | Inline color/background-color far from any design token. |
| Brand fonts | `pre-qa-brand.mjs` | Inline `font-family` not matching any token. |

## Thorough mode (`--thorough`)

Adds Playwright rendering at three viewports:

- Mobile: 375 × 812
- Tablet: 768 × 1024
- Desktop: 1280 × 800

Failure conditions: horizontal overflow (`scrollWidth > innerWidth`) or any
`console.error`.
