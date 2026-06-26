# Accessibility Checklist (WCAG 2.1 AA) — manual fallback

Use this when `a11y-axe.mjs` cannot run (no network to install `@axe-core`).
It mirrors the automated rules so the gate verdict stays consistent. Inspect the
served HTML of each page (`curl -s <url>`) and apply the checks below.

## Critical / serious (gate failures)

| Check | How to verify | WCAG |
|-------|---------------|------|
| Images have alt | Every `<img>` has an `alt` attribute; decorative images use `alt=""`. No `alt` = fail. | 1.1.1 |
| Form fields labelled | Each `input`/`select`/`textarea` has a `<label for>`, wrapping `<label>`, or `aria-label`/`aria-labelledby`. | 1.3.1, 4.1.2 |
| Buttons/links have names | `<a>`/`<button>` have text or `aria-label`; icon-only controls are not empty. | 4.1.2 |
| Single main landmark | Exactly one `<main>` (or `role="main"`); page has `header`/`nav`/`footer` regions. | 1.3.1 |
| Heading order | Exactly one `<h1>`; no skipped levels (h2→h4). | 1.3.1, 2.4.6 |
| Color contrast | Body text ≥ 4.5:1, large text (≥24px or 19px bold) ≥ 3:1, against its background. | 1.4.3 |
| Page language | `<html lang="...">` set. | 3.1.1 |
| Document title | Non-empty, unique `<title>` per page. | 2.4.2 |

## Moderate / minor (warnings — report, don't gate)

- `tabindex` > 0 (manipulates tab order) — avoid.
- Links distinguishable by more than color alone.
- `:focus` visible style present (no `outline: none` without replacement).
- ARIA roles valid and not redundant with native semantics.
- Tables use `<th>`/`scope` for data tables.
- `viewport` meta does not disable zoom (`user-scalable=no` / `maximum-scale=1`).

## Contrast quick method

For each text/background pair, compute relative luminance and the ratio
`(L1 + 0.05) / (L2 + 0.05)`. Pull colors from the computed style; the dominant
palette is already in `designTokens.colors`. Spot-check the lowest-contrast
pairs (light grey text on white is the usual offender).

## Output shape

Aggregate into `qa.a11y`:

```json
{
  "byImpact": { "critical": 0, "serious": 1, "moderate": 3, "minor": 2 },
  "violations": [
    { "url": "http://localhost:8888/contact/", "id": "label",
      "impact": "serious", "help": "Form elements must have labels",
      "nodes": ["#message"] }
  ],
  "passed": false
}
```

`passed = (critical == 0 && serious == 0)`.
