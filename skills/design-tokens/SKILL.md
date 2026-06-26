---
name: design-tokens
description: >-
  Extracts a design system from source HTML/CSS for a WordPress theme. Pulls the
  color palette, font families (predicting real Google Fonts names rather than
  defaults), spacing scale, breakpoints, and border radius, then formats them
  for theme.json (block-fse) and CSS custom properties (classic). Runs
  scripts/extract-tokens.mjs, then curates and names the raw results. Reads
  source CSS and writes `designTokens.*` (colors, fonts, spacing, breakpoints,
  radius) in wp-build.json. Use after html-analysis, when building a WordPress
  design system / theme.json / palette, or when the pipeline reaches the
  `tokens` stage.
allowed-tools: [Read, Write, Glob, Grep, Bash]
---

# Design Tokens (`tokens` stage)

Derive a coherent design system from the source styles. Read `source`/
`optimization.outputDir` CSS; write `designTokens`.

## 0. Resume guard

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh"
wpbuild_is_done tokens && [[ "${1:-}" != "--force" ]] && { echo "tokens already done"; exit 0; }
wpbuild_progress tokens in-progress
```

## 1. Run the extractor

Prefer the optimized copy if present, else the raw source.

```bash
SRC=$(wpbuild_get '.optimization.outputDir // (.source.htmlPaths[0] | sub("/[^/]+$";""))')
node "${CLAUDE_PLUGIN_ROOT}/scripts/extract-tokens.mjs" "$SRC" > "$SRC/.tokens.raw.json"
```

The extractor returns frequency-ranked `{colors, fonts, spacing, breakpoints,
radius, meta}`. CLI: `node extract-tokens.mjs <css-or-html-glob...>`.

## 2. Curate the palette

From ranked `colors`, build a semantic palette (keep raw `name` hints from
custom properties). Assign roles by frequency + usage context:

| Role | Pick |
|------|------|
| `primary` | most-used non-neutral brand color |
| `secondary` / `accent` | next most-used distinct hues |
| `foreground` / `background` | darkest/lightest near-neutral |
| `surface` / `muted` | mid neutrals |

Collapse near-duplicates (ΔE small / within a few hex points). Target a tight
palette (~6-10 entries). Each entry: `{ "name", "slug", "value", "role" }`.
Note any WCAG-AA contrast risks for the conversion stage.

## 3. Resolve fonts → real Google Fonts

The extractor flags `googleFont: true` for title-case families. Confirm/repair
the **real** family name (not a generic default):

- A `fonts.googleapis.com` link is authoritative — use that exact `family=`.
- Otherwise map the declared name to its real Google Fonts name (e.g. `Inter`,
  `Poppins`, `Roboto`, `Playfair Display`, `Montserrat`, `Lora`, `Work Sans`).
- Assign roles: most-used / body-context → `body`; display/heading context →
  `heading`. Capture weights seen in the CSS (`font-weight`) for loading.

```json
{ "name": "Inter", "role": "body", "googleFont": true, "weights": [400, 600, 700],
  "fallback": "system-ui, sans-serif" }
```

Never emit a bare `sans-serif`/`serif` as the chosen font; that is a fallback
only. See `references/google-fonts-prediction.md`.

## 4. Normalize spacing, breakpoints, radius

- **Spacing:** snap raw values to a consistent scale (e.g. 4/8px base:
  4,8,12,16,24,32,48,64). Express in `rem` for theme.json. Name steps
  `--space-1..n` or t-shirt sizes.
- **Breakpoints:** the extractor labels sm/md/lg/xl/2xl; keep the dominant px
  per label.
- **Radius:** keep distinct values + `full` (pill). Name `sm/md/lg/full`.

## 5. Emit for both targets

Produce both shapes so either strategy can consume them; store both under
`designTokens` plus generated artifacts noted in `notes`.

**theme.json (block-fse)** — `settings.color.palette`, `typography.fontFamilies`,
`spacing.spacingSizes`, `settings.custom`. **CSS custom properties (classic)** —
`:root { --color-primary: …; --font-heading: …; --space-4: …; --radius-md: … }`.

See `references/theme-json-mapping.md` for exact field mapping + examples.

## 6. Write outputs

```bash
wpbuild_set '.designTokens' "$TOKENS_JSON"
wpbuild_progress tokens done "P colors, F fonts (Google: …), S spacing steps, B breakpoints"
```

`designTokens` shape: `{ colors[], fonts[], spacing[], breakpoints{}, radius[] }`.

## Output contract

Print the palette (name+hex), the chosen Google Fonts with roles/weights, the
spacing scale, breakpoints, and radius set. These feed `theme-conversion`
(theme.json or CSS variables) and inform contrast checks. Keep the raw extractor
output (`.tokens.raw.json`) for traceability.

See also: `references/google-fonts-prediction.md`, `references/theme-json-mapping.md`.
