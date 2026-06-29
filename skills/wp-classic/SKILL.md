---
name: wp-classic
description: >-
  Conventions and reference for classic PHP WordPress 7.x themes with ACF
  (the WP Pro Max classic-acf strategy). Use when generating or reviewing
  classic theme code, template parts, CPT/taxonomy registration, ACF blocks,
  and enqueues. Reads strategy and project fields from wp-build.json.
user-invocable: true
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# WP-Classic Stack

Conventions for a classic PHP theme running on WordPress 7.x with ACF Pro. This
is the stack skill behind the `classic-acf` conversion strategy in WP Pro Max.

## When to invoke

- You are writing or reviewing a classic PHP theme file.
- You need naming, code-style, or template conventions for `strategy = classic-acf`.
- You want the canonical checklist or component workflow for this stack.

## Stack

| Layer | Choice |
|-------|--------|
| WordPress | 7.x |
| PHP | 8.2+ |
| Runtime | `@wordpress/env` Docker WordPress (`wp-content/themes/<themeSlug>/`) |
| Theme type | Classic PHP templates — no Blade / Acorn / Sage |
| Custom fields | ACF Pro (field groups authored in GUI, exported to `acf-json/`) |
| CSS | Vanilla CSS with `:root` design tokens, or project-specific tooling |

## Layout

```
wp-content/themes/<themeSlug>/
├── style.css
├── functions.php
├── header.php  footer.php  index.php
├── front-page.php  page.php  single.php  archive.php
├── single-<cpt>.php  archive-<cpt>.php
├── templates/              # optional custom page templates
├── parts/                  # reusable template parts
├── inc/
│   ├── post-types.php      # CPT + taxonomy registration
│   ├── taxonomies.php      # optional split
│   ├── acf-blocks.php      # acf_register_block_type()
│   ├── enqueue.php         # asset enqueues
│   ├── image-sizes.php     # add_image_size()
│   └── helpers.php         # theme helpers
├── acf-json/               # ACF field-group JSON
├── assets/{css,js,images}
└── languages/              # translation files
```

**Default templates live in the theme root.** Use `templates/` only for custom
page templates that declare `Template Name:`.

## Core conventions

| Artifact | Convention |
|----------|------------|
| Files | kebab-case (`front-page.php`, `parts/hero.php`) |
| Functions | prefixed `snake_case` (`<slug>_setup()`) |
| Classes | `PascalCase` (`<Slug>_Hero_Block`) |
| Constants | `UPPER_SNAKE_CASE` (`<SLUG>_VERSION`) |
| Text domain | `project.textDomain` from `wp-build.json` |
| Indentation | Tabs per WPCS |

- Escape on output (`esc_html`, `esc_attr`, `esc_url`, `wp_kses_post`).
- Start PHP files with `defined( 'ABSPATH' ) || exit;`.
- Enqueue assets with `wp_enqueue_*`; never inline `<script>`/`<link>`.
- Pass data to partials with `get_template_part( 'parts/name', null, $args )`.
- Register CPTs/taxonomies in `inc/post-types.php`; do not inline in `functions.php`.
- Register ACF blocks in `inc/acf-blocks.php`.
- Point ACF JSON load/save to the theme's `acf-json/` directory.

## References

- **Canonical agent reference**: `../../references/classic-acf.md` — file set,
  real templates, registration code, ACF patterns, and anti-patterns. Read this
  before authoring any classic-acf theme files.
- **Code-review checklist**: `./references/code-review-checklist.md`
- **Component workflow**: `./references/component-workflow.md`

## Anti-patterns

- Blade, Acorn, Sage, `@include`, View Composers.
- Hardcoded colors or spacing — use design tokens.
- Unsafe `echo`, unescaped data.
- Inline scripts/styles.
- Complex ACF field-group PHP — use the GUI + `acf-json/`.

---

Conventions adapted from [alessioarzenton/claude-code-wp-toolkit](https://github.com/alessioarzenton/claude-code-wp-toolkit) (GPL-3.0), rewritten for WP Pro Max (MIT).
