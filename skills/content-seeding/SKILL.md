---
name: content-seeding
description: >-
  Seeds real WordPress content into the running wp-env site (stage
  `seed-content`). Extracts the actual body content of each analyzed page from
  the optimized source HTML (never lorem), then emits a single pure-JSON payload
  (pages/posts, media, menus, terms, front page, core options) that the seed
  batch runtime applies in one `wp eval-file` call. Builds nav menus from
  contentModel.menus, imports media and sets featured images, and sets the static
  front page. All writes are idempotent (check-before-create, in-process WP API),
  so re-runs produce zero duplicates. Records seed.idempotencyKeys, seed.lastRun,
  and seed.lastSummary. Use when populating WordPress pages, posts, menus, media,
  or reading settings, or when the pipeline reaches the `seed-content` stage.
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# Content Seeding (stage `seed-content`)

Populate the live WordPress site with the **real** content of the source site:
pages, posts, media, menus, front page, and core options. Runs after
`scaffold` and after wp-env is up.

This stage emits a **pure-JSON payload** and runs it through the seed batch
engine in **one** `wp eval-file` call (seconds, not minutes). The runtime
(`scripts/seed-batch-runtime.php`) checks existence before every write and
records stable idempotency keys — so this stage is safe to re-run (zero
duplicates). The payload is **data only** (page bodies are JSON strings); it is
never executable PHP, so there is no injection surface.

## Inputs (from `wp-build.json`)

| Field | Use |
|-------|-----|
| `analysis.pages[]` | Which pages to create (path, title, role). |
| `optimization.outputDir` | Where the optimized, production HTML lives. |
| `source.htmlPaths` / `source.briefPath` | Fallback content source. |
| `contentModel.menus[]` | Menus + items + theme locations to build. |
| `contentModel.postTypes[]` | Non-page records to seed as posts. |
| `theme.templateMap` | Page slug → WP template (`posts[].template`). |
| `project.name` | Default `blogname`. |

## 0. Resume guard + setup

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh"
wpbuild_is_done seed-content && [[ "${1:-}" != "--force" ]] && { echo "seed-content done"; exit 0; }
wpbuild_progress seed-content in-progress
OUTDIR="$(wpbuild_get '.optimization.outputDir // "."')"
```

Verify wp-env is reachable before seeding:
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" option get siteurl` (if it errors, stop and ask to start env).

## 1. Extract real body content per page

For each `analysis.pages[]` entry, read the matching optimized HTML and extract
the **main content** (drop the global header/nav/footer — those become theme
template parts, not page body). Keep headings, paragraphs, lists, images, and
links. Strategy-aware extraction and the exact selectors are in
`references/content-extraction.md`.

**Keep writing each page's cleaned body to `content/<slug>.html`** in the target
project — the QA stage's `wp search-replace` and `wp post update` paths depend on
these files. The payload's `content` value is the text of that file (a JSON
string). Do **not** invent placeholder text — if a page has no extractable body
(e.g. a pure builder layout), leave the body minimal; the builder data is seeded
in `seed-plugin-data`.

When `source.type == "brief"`, generate page bodies from the requirements brief
instead, one section per required page.

## 2. Decide slugs + roles

- `role: home` → slug `home`, becomes the static front page.
- `role: page` → slug from the source path/title (kebab-case).
- `role: post`/`single` → seed as `post` (or the mapped CPT) via `type`.
- `role: archive` → no page; handled by CPT archive + menu archive link.

## 3. Author `seed-content-payload.json` (pure JSON)

Write a single JSON object to `seed-content-payload.json` in the target project.
Every page body is a JSON **string** sourced from its `content/<slug>.html` file.

```json
{
  "options":  { "blogname": "Acme Studio", "permalink_structure": "/%postname%/" },
  "mediaPathPrefix": "/var/www/html/wp-content/uploads/wppm-src/",
  "media":    [ { "file": "assets/images/hero.jpg", "title": "hero" } ],
  "posts":    [
    { "slug": "home",  "title": "Home",  "type": "page",
      "template": "front-page.php", "content": "<h1>…real body…</h1>",
      "featured": "hero" },
    { "slug": "about", "title": "About", "type": "page", "content": "<h1>About…</h1>" }
  ],
  "terms":    [ { "tax": "service_cat", "name": "Design", "slug": "design" } ],
  "menus":    [ { "name": "Primary", "location": "primary",
                  "items": [ { "post": "home", "title": "Home" },
                             { "post": "about", "title": "About" },
                             { "title": "Docs", "url": "/docs" } ] } ],
  "frontPage": "home"
}
```

Rules for the payload:

- **Pure data.** Never embed PHP. Page bodies are JSON strings; JSON escaping is
  automatic and safe (no PHP-literal hand-escaping). Large bodies are fine — the
  payload is piped to the runtime over stdin (no `ARG_MAX` limit).
- **Media.** List files relative to `optimization.outputDir`. Set
  `mediaPathPrefix` to `"/var/www/html/wp-content/uploads/wppm-src/"` (the mount
  `wp-env-setup` adds for `outputDir`) so the runtime resolves them by absolute
  container path. Remote images may be `http(s)` URLs (sideloaded). `featured`
  references a media `title`.
- **Menus.** A `{ "post": "<slug>" }` item links a page (resolved by slug);
  a `{ "title", "url" }` item is a custom link. Items dedupe by title.
- **Templates.** `posts[].template` maps to `_wp_page_template` (from
  `theme.templateMap`).
- **No secrets.** Never put real secrets (form recipients, tokens) in the payload
  — pointers only, consistent with the handoff stage.

## 4. Run the batch inline + merge the summary

The **skill runs the batch itself** (thin coordinator — not the orchestrator,
not the heavy agent). The driver pipes the JSON to one `wp eval-file` call,
recovers the sentinel-wrapped summary, and merges it into the manifest
(`seed.idempotencyKeys` append+unique, `seed.lastRun`, `seed.lastSummary`):

```bash
wpbuild_set '.seed.contentPayload' '"seed-content-payload.json"'
bash "${CLAUDE_PLUGIN_ROOT}/scripts/seed-batch-run.sh" seed-content-payload.json
```

The driver fails loudly if the summary is missing, if the run did nothing, or if
the batch did not complete — so a partial run is never reported as success.
Re-running produces **zero** duplicate pages/menu items (the runtime
short-circuits on existing slugs/titles); the re-run summary shows `created:0`.
Spot-check: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" post list --post_type=page --field=post_name`.

## 5. Record outputs

```bash
wpbuild_progress seed-content done "N pages, M posts, menus + front page seeded"
```

`seed.idempotencyKeys`, `seed.lastRun`, and `seed.lastSummary` are written by the
driver. Hand off to `seed-plugin-data` for ACF/Elementor/forms.

## Delegation

The heavy lifting is **content extraction + authoring the JSON payload** — that
is the **wp-data-engineer** agent's deliverable (the agent does NOT run hundreds
of WP-CLI calls). Author and execution are decoupled: the agent returns the
payload, and **this skill runs `seed-batch-run.sh` inline and merges the
summary**, so an agent death cannot lose a run. Pass the agent: the target
project path, manifest path, the page list + extracted bodies, and acceptance
criteria (valid JSON payload; no duplicates on re-run; front page set; menus
assigned). Never hand it full conversation history.

See also: `references/content-extraction.md`.
