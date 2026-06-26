---
name: content-seeding
description: >-
  Seeds real WordPress content into the running wp-env site (stage
  `seed-content`). Extracts the actual body content of each analyzed page from
  the optimized source HTML (never lorem), creates pages/posts, imports media and
  sets featured images, builds nav menus from contentModel.menus, sets the static
  front page, and applies core options (blogname, permalink). All writes go
  through the idempotent scripts/seed-helpers.sh so re-runs are safe. Emits a
  generated seed-content.sh into the target project and records
  seed.contentScript + seed.idempotencyKeys. Use when populating WordPress pages,
  posts, menus, media, or reading settings, or when the pipeline reaches the
  `seed-content` stage.
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# Content Seeding (stage `seed-content`)

Populate the live WordPress site with the **real** content of the source site:
pages, posts, media, menus, front page, and core options. Runs after
`scaffold` and after wp-env is up. Every mutation goes through
`scripts/seed-helpers.sh`, which checks-before-creates and records stable
idempotency keys — so this stage is safe to re-run.

## Inputs (from `wp-build.json`)

| Field | Use |
|-------|-----|
| `analysis.pages[]` | Which pages to create (path, title, role). |
| `optimization.outputDir` | Where the optimized, production HTML lives. |
| `source.htmlPaths` / `source.briefPath` | Fallback content source. |
| `contentModel.menus[]` | Menus + items + theme locations to build. |
| `contentModel.postTypes[]` | Non-page records to seed as posts. |
| `theme.templateMap` | Page slug → WP template (passed to ensure_page). |
| `project.name` | Default `blogname`. |

## 0. Resume guard + setup

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh"
wpbuild_is_done seed-content && [[ "${1:-}" != "--force" ]] && { echo "seed-content done"; exit 0; }
wpbuild_progress seed-content in-progress
OUTDIR="$(wpbuild_get '.optimization.outputDir // "."')"
```

Verify wp-env is reachable before seeding:
`wp-env run cli wp option get siteurl` (if it errors, stop and ask to start env).

## 1. Extract real body content per page

For each `analysis.pages[]` entry, read the matching optimized HTML and extract
the **main content** (drop the global header/nav/footer — those become theme
template parts, not page body). Keep headings, paragraphs, lists, images, and
links. Strategy-aware extraction and the exact selectors are in
`references/content-extraction.md`.

Write each page's cleaned body to `content/<slug>.html` in the target project.
Rewrite asset `src`/`href` to point at media-library URLs after import (step 3),
or leave relative and let the importer rewrite. Do **not** invent placeholder
text — if a page has no extractable body (e.g. a pure builder layout), leave the
body minimal; the builder data is seeded in `seed-plugin-data`.

When `source.type == "brief"`, generate page bodies from the requirements brief
instead, one section per required page.

## 2. Decide slugs + roles

- `role: home` → slug `home`, becomes the static front page.
- `role: page` → slug from the source path/title (kebab-case).
- `role: post`/`single` → seed as `post` (or the mapped CPT).
- `role: archive` → no page; handled by CPT archive + menu archive link.

## 3. Generate `seed-content.sh` in the target project

Author a script that records **exactly** what gets created, sourcing the shared
helpers. Example skeleton (the skill fills real values from the manifest):

```bash
#!/usr/bin/env bash
set -euo pipefail
source "${CLAUDE_PLUGIN_ROOT}/scripts/seed-helpers.sh"   # WP_CLI_RUN override honored

# --- Core options ---------------------------------------------------------
ensure_option blogname "Acme Studio"
ensure_option blogdescription "Design that ships"
ensure_option permalink_structure '/%postname%/'

# --- Media (dedupe by filename) ------------------------------------------
hero_id="$(import_media './assets/images/hero.jpg')"

# --- Pages (body extracted from optimized HTML) --------------------------
home_id="$(ensure_page home    "Home"    ./content/home.html    front-page.php)"
about_id="$(ensure_page about  "About"   ./content/about.html)"
contact_id="$(ensure_page contact "Contact" ./content/contact.html templates/page-contact.php)"
[[ -n "$hero_id" ]] && set_featured_image "$home_id" "$hero_id"

# --- Menus (from contentModel.menus) -------------------------------------
ensure_menu "Primary"
ensure_menu_item_post   "Primary" "$home_id"    "Home"
ensure_menu_item_post   "Primary" "$about_id"   "About"
ensure_menu_item_post   "Primary" "$contact_id" "Contact"
assign_menu_location    "Primary" primary

# --- Reading settings -----------------------------------------------------
set_front_page home

seed_mark_run
```

Key rules for the generated script:

- Always `source` `seed-helpers.sh`; never call raw `wp` for create operations.
- Capture IDs from `ensure_*` into shell vars and reuse them (menus, featured).
- For CPT records, loop `ensure_post <slug> <title> <file> <cpt>`; set fields with
  `ensure_acf_value` (full ACF values are the job of `seed-plugin-data`, but
  simple scalar meta can be seeded here).
- Permalink + `rewrite flush` once at the end if the structure changed.

## 4. Run it (idempotently)

```bash
wpbuild_set '.seed.contentScript' '"seed-content.sh"'
bash ./seed-content.sh
```

Re-running must produce zero duplicate pages/menu items (helpers short-circuit
on existing slugs/titles). Spot-check: `wp post list --post_type=page --field=post_name`.

## 5. Record outputs

```bash
wpbuild_progress seed-content done "N pages, M posts, menus + front page seeded"
```

`seed.contentScript`, `seed.idempotencyKeys`, and `seed.lastRun` are updated by
the helpers / this stage. Hand off to `seed-plugin-data` for ACF/Elementor/forms.

## Delegation

Heavy WP-CLI / DB work and verification go to the **wp-data-engineer** agent.
Pass it: the target project path, manifest path, the generated `seed-content.sh`,
the page list, and acceptance criteria (no duplicates on re-run; front page set;
menus assigned). Never hand it full conversation history.

See also: `references/content-extraction.md`.
