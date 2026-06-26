---
name: content-modeling
description: >-
  Derives the WordPress content model from analyzed HTML. Turns repeated
  structures (e.g. team member, service, portfolio, testimonial cards) into
  custom post types and taxonomies, proposes ACF field groups (classic-acf),
  block bindings (block-fse), or builder dynamic fields (page-builder), and
  builds the navigation menu tree from the information architecture. Reads
  `analysis` and writes `contentModel.*` (postTypes, taxonomies, fieldGroups,
  menus) in wp-build.json, emitting field-group JSON examples. Use after
  html-analysis, when designing WordPress CPTs/taxonomies/ACF fields/menus, or
  when the pipeline reaches the `model` stage.
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash]
---

# Content Modeling (`model` stage)

Translate detected repeated structures into WordPress data structures. Read
`analysis` (+ `strategy`); write `contentModel`.

## 0. Resume guard

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh"
wpbuild_is_done model && [[ "${1:-}" != "--force" ]] && { echo "model already done"; exit 0; }
wpbuild_progress model in-progress
STRATEGY=$(wpbuild_get '.strategy')
```

## 1. Identify content types

From `analysis.components`, promote **record components** (kind `card`/`grid`,
3+ occurrences, content-bearing) to custom post types. Map names to clean
slugs:

| Repeated structure | CPT slug | Singular / Plural |
|--------------------|----------|-------------------|
| team / staff cards | `team_member` | Team Member / Team |
| service cards | `service` | Service / Services |
| portfolio / project tiles | `portfolio` | Project / Portfolio |
| testimonial quotes | `testimonial` | Testimonial / Testimonials |
| pricing tiers | `pricing_plan` | Plan / Pricing |
| FAQ items | `faq` | FAQ / FAQs |
| events | `event` | Event / Events |

Do not create a CPT for one-off content (use a Page) or for true blog posts
(use core `post`). Each CPT:

```json
{
  "slug": "service",
  "labels": { "singular": "Service", "plural": "Services" },
  "supports": ["title", "editor", "thumbnail", "excerpt"],
  "hasArchive": true,
  "showInRest": true,
  "menuIcon": "dashicons-hammer"
}
```

`showInRest: true` is required for the block editor and FSE bindings.

## 2. Derive taxonomies

When records cluster by category/tag-like grouping, add a taxonomy:

```json
{ "slug": "service_category", "objectType": ["service"], "hierarchical": true }
```

Hierarchical (category-like) for nested grouping; non-hierarchical (tag-like)
for flat labels. Reuse core `category`/`post_tag` for `post` instead of cloning.

## 3. Fields per type — strategy-adaptive

Inspect one instance of each record component and list its fields (see the
field-inference table in `html-analysis/references/component-detection.md`).
Then emit per `strategy`:

- **classic-acf** → ACF field group JSON (saved later to `<theme>/acf-json/`).
- **block-fse** → block bindings mapping fields to `meta` source on core blocks.
- **page-builder** → builder dynamic-field tags (Elementor dynamic tags / Bricks
  `{cpt_field}`), data later stored in postmeta.

Field type mapping:

| Visible content | ACF type | meta key |
|-----------------|----------|----------|
| short text / title | text | `subtitle` |
| long text | textarea / wysiwyg | `body` |
| image | image | `photo` |
| link/button | link | `cta` |
| number/price | number | `price` |
| date | date_picker | `event_date` |
| repeated rows | repeater | `items` |
| icon | text/select | `icon` |

See `references/field-group-examples.md` for full JSON for each strategy.

## 4. Build the menu tree

From `analysis.informationArchitecture`, construct menus. Map top-level nav to a
`primary` menu and footer links to a `footer` menu:

```json
{
  "name": "Primary",
  "location": "primary",
  "items": [
    { "title": "Home", "type": "page", "ref": "home" },
    { "title": "Services", "type": "post_type_archive", "ref": "service" },
    { "title": "About", "type": "page", "ref": "about" },
    { "title": "Contact", "type": "page", "ref": "contact" }
  ]
}
```

Item types: `page`, `post_type_archive`, `custom` (external/anchor), `taxonomy`.
Preserve nesting from the IA tree as nested `items`.

## 5. Write outputs

```bash
wpbuild_set '.contentModel' "$MODEL_JSON"
wpbuild_progress model done "N CPTs, M taxonomies, K field groups, menus: primary/footer"
```

`contentModel` shape: `{ postTypes[], taxonomies[], fieldGroups[], menus[] }`.
Field groups should be ready to drop into `acf-json/` (classic) or consumed by
the conversion stage (fse/page-builder).

## Output contract

Print: CPT list with field counts, taxonomies, menu structure, and which
strategy shaped the field output. Hand off to `theme-conversion` (templates),
`wp-scaffold` (registers CPTs/taxonomies/ACF), and `content-seeding`.

Heavy ACF JSON authoring for many groups may be delegated to the
`wp-theme-developer` agent; this skill produces the model + canonical examples.

See also: `references/field-group-examples.md`.
