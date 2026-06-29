# Content Sources

How `/wp-pro-max:content-enrichment` discovers and creates content.

## Brief format (`requirements/brief.md`)

The helper reads the `## Pages` section. Supported line formats:

```markdown
## Pages

- Contact: contact page with form and address
- About
- Services: overview of services
```

- Title is the text before `:`.
- Description after `:` is stored but not parsed further.
- Unsupported lines are ignored with a warning.

## Page scaffolding

New pages are cloned from an existing optimized page (prefer `index.html`) and
kept at the same directory level. Shared `<head>`, navigation, and footer are
preserved so relative links and assets keep working.

## Enrichment targets

- `<title>` and `<meta name="description">`.
- `<img alt="...">` values.
- `<h1>` / `<h2>` / body copy inside `<main>`.
- CTA text and button labels.

All AI-edited blocks receive `data-wp-pro-max="draft"` until `--approve`.
