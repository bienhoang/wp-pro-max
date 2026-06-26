# Predicting Real Google Fonts Names

The extractor reports declared family names. The goal is the **real** font the
theme should load — usually a Google Font — not a CSS fallback keyword.

## Priority order

1. **Explicit Google Fonts link/import** — authoritative. Parse `family=` from
   `fonts.googleapis.com/css2?family=...`. The extractor already weights these
   highest (`count += 5`). Use the exact name and weights from the query.
2. **`@font-face` src** — if it points at a known foundry/Google file, map to the
   canonical family name.
3. **Declared family in `font-family` stacks** — the first (preferred) family.
   Match it to the closest real Google Font.

## Common declared → real Google Font map

| Declared / lookalike | Real Google Font |
|----------------------|------------------|
| Helvetica, Arial, "Helvetica Neue" | Inter / Roboto / Work Sans |
| "Times New Roman", Georgia | Lora / PT Serif / Playfair Display (display) |
| Circular, Gilroy, Avenir | Poppins / Montserrat / Nunito Sans |
| "SF Pro", -apple-system | Inter (closest web-safe match) |
| Futura | Jost / Questrial |
| Garamond | EB Garamond / Cormorant |
| Courier, monospace code | JetBrains Mono / Source Code Pro / Roboto Mono |

## Role assignment

- **heading** — family used on `h1`–`h3`, large display text. Often a distinct
  display/serif/geometric face.
- **body** — family used on `body`, `p`, base text. Usually a readable sans.
- If only one family exists, it serves both roles.

## Weights

Collect `font-weight` values seen near each family (and from the Google link's
`:wght@...`). Load only the weights actually used (avoid shipping all 9). Map
named weights: normal=400, bold=700, light=300, semibold=600, medium=500.

## Output per font

```json
{ "name": "Poppins", "role": "heading", "googleFont": true,
  "weights": [600, 700], "fallback": "system-ui, sans-serif",
  "source": "fonts.googleapis.com link" }
```

## Hard rule

Never select a generic keyword (`sans-serif`, `serif`, `system-ui`) as `name`.
Those are `fallback` only. If detection is ambiguous, pick the closest real
Google Font from the table above and note the assumption in `notes`.
