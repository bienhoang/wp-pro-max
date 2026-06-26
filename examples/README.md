# Example — Acme Studio (sample HTML site)

A tiny 2-page static site used to exercise the WP Pro Max pipeline end to end.

```
sample-site/
  index.html       home: hero + 3 "service" cards + contact footer
  about.html       about: hero + 3 "team" cards (repeated card component)
  assets/style.css design tokens as CSS custom properties (colors, fonts, spacing)
```

The repeated `.card` component and the CSS custom properties are intentional —
they give `content-modeling` a CPT to derive and `design-tokens` real values to
extract.

## Walkthrough

From a working directory where you want the WordPress project created:

```bash
# 1. Run the whole pipeline (interactive gates)
/wp-pro-max:build /path/to/wp-pro-max/examples/sample-site

# or pick a strategy
/wp-pro-max:build .../examples/sample-site --strategy block-fse
```

What each stage does on this site:

1. **analyze** — finds 2 pages (home, about), the repeated card component, the nav
   menu, and the Google Fonts (Inter/Poppins). Recommends a strategy.
2. **optimize** — cleans markup, plans responsive images.
3. **model** — derives a `service` (or `team`) CPT from the repeated cards + the
   primary menu.
4. **tokens** — extracts the palette/fonts/spacing from `style.css`:
   ```bash
   node /path/to/wp-pro-max/scripts/extract-tokens.mjs examples/sample-site/assets/style.css
   ```
5. **convert + scaffold** — builds the theme (templates + CPT + theme.json/ACF).
6. **plugins + env** — pins plugins into `.wp-env.json`, starts wp-env.
7. **seed-content / seed-plugin-data** — creates the pages, menu, and card entries
   from the real HTML content (idempotent).
8. **i18n** — makes the theme translatable; sets up vi/en/ja with Polylang.
9. **seo / security / qa** — metadata + hardening + visual diff vs these HTML files.
10. **ship / handoff** — deploy (configure `deploy.*` first) + client docs.

Inspect progress any time:

```bash
/wp-pro-max:status
```

> Requires Docker + Node ≥ 20 for the live wp-env stages.
