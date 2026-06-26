# Mapping Tokens → theme.json & CSS Variables

Emit both shapes so `theme-conversion` can use whichever the strategy needs.

## theme.json (block-fse)

```json
{
  "version": 3,
  "settings": {
    "color": {
      "palette": [
        { "slug": "primary", "name": "Primary", "color": "#1a73e8" },
        { "slug": "secondary", "name": "Secondary", "color": "#ff5722" },
        { "slug": "foreground", "name": "Foreground", "color": "#0f172a" },
        { "slug": "background", "name": "Background", "color": "#ffffff" }
      ]
    },
    "typography": {
      "fontFamilies": [
        {
          "slug": "heading", "name": "Heading",
          "fontFamily": "\"Playfair Display\", serif",
          "fontFace": [
            { "fontFamily": "Playfair Display", "fontWeight": "600 700",
              "src": ["file:./assets/fonts/playfair-display.woff2"] }
          ]
        },
        { "slug": "body", "name": "Body", "fontFamily": "Inter, system-ui, sans-serif" }
      ],
      "fontSizes": [
        { "slug": "small", "name": "Small", "size": "0.875rem" },
        { "slug": "medium", "name": "Medium", "size": "1rem" },
        { "slug": "large", "name": "Large", "size": "1.5rem" },
        { "slug": "x-large", "name": "X-Large", "size": "2.25rem" }
      ]
    },
    "spacing": {
      "spacingSizes": [
        { "slug": "20", "name": "1", "size": "0.5rem" },
        { "slug": "40", "name": "2", "size": "1rem" },
        { "slug": "60", "name": "3", "size": "1.5rem" },
        { "slug": "80", "name": "4", "size": "2rem" }
      ]
    },
    "custom": {
      "radius": { "sm": "4px", "md": "12px", "lg": "24px", "full": "9999px" }
    }
  }
}
```

Notes:
- `version: 3` for current WP. Palette `slug`s become `var(--wp--preset--color--<slug>)`.
- Breakpoints are not a native theme.json concept; expose them under
  `settings.custom.breakpoints` and use in block CSS / fluid clamps.
- Prefer fluid typography via `settings.typography.fluid: true` when sizes span
  a wide range.

## CSS custom properties (classic-acf / page-builder)

Write to the theme stylesheet (`:root`), generated from the same tokens:

```css
:root {
  /* color */
  --color-primary: #1a73e8;
  --color-secondary: #ff5722;
  --color-fg: #0f172a;
  --color-bg: #ffffff;

  /* type */
  --font-heading: "Playfair Display", serif;
  --font-body: Inter, system-ui, sans-serif;

  /* spacing scale */
  --space-1: 0.5rem;
  --space-2: 1rem;
  --space-3: 1.5rem;
  --space-4: 2rem;

  /* radius */
  --radius-sm: 4px;
  --radius-md: 12px;
  --radius-full: 9999px;
}

/* breakpoints (for reference; used in @media authoring) */
/* --bp-sm: 480px; --bp-md: 768px; --bp-lg: 1024px; --bp-xl: 1280px; */
```

## Consistency rules
- Color `slug`s match between theme.json palette and CSS var names where
  possible (`primary` ↔ `--color-primary`) so templates read predictably.
- Keep spacing in `rem` in both targets; base on a 4/8px scale.
- Enqueue Google Fonts (or self-host the listed weights) in the theme; record
  the enqueue requirement in `designTokens` notes for the conversion stage.
