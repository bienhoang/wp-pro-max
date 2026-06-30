---
name: wp-seo
description: >-
  Applies on-page SEO to a WordPress build (stage `seo`). Sets per-page meta
  titles/descriptions, Open Graph and Twitter cards, canonical URLs and robots
  directives; injects schema.org JSON-LD (Organization, WebSite, BreadcrumbList,
  and Article/Product as relevant); and generates the XML sitemap — configuring
  the installed SEO plugin (Yoast/Rank Math/SEOPress) via WP-CLI where possible,
  or the theme head as fallback. Delegates analysis/audits to the installed
  claude-seo plugin (claude-seo:seo / seo-schema / seo-technical) when present.
  Use when applying SEO meta, schema, sitemap, canonicals, or robots to
  WordPress, or when the pipeline reaches the `seo` stage. Reads analysis.pages,
  contentModel, project; writes seo.{metaApplied,schemaTypes,sitemap}.
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# WP SEO (stage `seo`)

Make every page discoverable and rich-result eligible: titles, descriptions,
social cards, canonical/robots, structured data, and a sitemap. **Prefer
delegating** the heavy lifting to the installed `claude-seo` plugin; only emit
direct WP-CLI/theme config as a fallback.

## Inputs (from `wp-build.json`)

| Field | Use |
|-------|-----|
| `analysis.pages[]` | Per-page title/role → meta + which schema applies. |
| `contentModel.postTypes[]` | Article (`post`) vs Product (`product`) schema. |
| `project.name` / `project.description` | Organization + WebSite schema. |
| `urls.local` / `urls.production` | Canonical base + sitemap URLs. |
| `plugins[]` | Which SEO plugin is installed (Yoast/Rank Math/SEOPress). |

## 0. Resume guard + setup

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh"
wpbuild_is_done seo && [[ "${1:-}" != "--force" ]] && { echo "seo done"; exit 0; }
wpbuild_progress seo in-progress
SEO_PLUGIN="$(wpbuild_get '[.plugins[]?|select(.category=="seo")|.slug][0] // "none"')"
SITE="$(wpbuild_get '.urls.production // .urls.local // .env.localUrl // "http://localhost:8888"')"
```

## 1. Detect & delegate to `claude-seo` (preferred)

If the `claude-seo` plugin/skills are installed, delegate rather than
re-implement. Map our work to its skills:

- **Audit & gaps** → `claude-seo:seo` (full or single-page analysis), or
  `claude-seo:seo-audit` for a site crawl. Use to validate after applying.
- **Structured data** → `claude-seo:seo-schema` to detect/validate/generate
  JSON-LD (Organization, WebSite, BreadcrumbList, Article/Product).
- **Technical** → `claude-seo:seo-technical` for robots.txt, canonicals, Core
  Web Vitals, indexability, security headers crossover.
- **Sitemap** → `claude-seo:seo-sitemap` to validate/generate the XML sitemap.

Detection (any hit ⇒ delegate):

```bash
ls "$HOME/.claude/plugins"/*/skills/seo-schema 2>/dev/null \
  || ls "$HOME/.claude/skills/claude-seo"* 2>/dev/null \
  && echo "claude-seo present → delegate"
```

Workflow when present: generate page-level meta plan + entity facts here, hand
the JSON-LD generation to `claude-seo:seo-schema`, write the plugin output to
the WP page meta / theme head, then run `claude-seo:seo` to score the result and
record findings. See `references/delegate-claude-seo.md`.

## 2. Per-page meta (title / description / OG / Twitter / canonical / robots)

Configure through the installed SEO plugin's postmeta (works headless via
WP-CLI). Yoast example (slugs differ per plugin — table in
`references/seo-plugin-config.md`):

```bash
# Resolve the WP post ID for a slug, then set Yoast meta:
PID="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" post list --post_type=page --name=about --field=ID)"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" post meta update "$PID" _yoast_wpseo_title    "About Acme %%sep%% %%sitename%%"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" post meta update "$PID" _yoast_wpseo_metadesc "Who we are and what we build."
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" post meta update "$PID" _yoast_wpseo_opengraph-title       "About Acme"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" post meta update "$PID" _yoast_wpseo_opengraph-description  "Who we are and what we build."
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" post meta update "$PID" _yoast_wpseo_twitter-title         "About Acme"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" post meta update "$PID" _yoast_wpseo_canonical             "$SITE/about/"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" post meta update "$PID" _yoast_wpseo_meta-robots-noindex   "0"
```

When **no SEO plugin** is installed, write meta into the theme head via a small
`mu-plugin` or `functions.php` filter — template in
`references/theme-head-fallback.php`. Derive descriptions from the page's real
content (first meaningful paragraph), never lorem.

## 3. Structured data (schema.org JSON-LD)

Emit JSON-LD appropriate to each page (prefer `claude-seo:seo-schema`):

- **Organization** + **WebSite** (with `potentialAction` SearchAction) site-wide,
  injected once via the head template / SEO plugin's knowledge graph settings.
- **BreadcrumbList** on every non-home page from the menu/IA hierarchy.
- **Article** for `post`/`single`; **Product** for a `product` CPT (price,
  availability, brand, aggregateRating when data exists — omit fields you cannot
  populate; never fabricate ratings).

Track which types you applied: `schemaTypes` (step 5). Templates in
`references/schema-templates.md`.

## 4. Sitemap + robots + canonical policy

- **Sitemap**: enable the SEO plugin's XML sitemap (Yoast/Rank Math expose it at
  `/sitemap_index.xml`; SEOPress at `/sitemaps.xml`). If none, register WP core
  sitemaps (`/wp-sitemap.xml`, on by default since WP 5.5) and confirm reachable.
- **robots.txt**: allow crawl, point to the sitemap, disallow `/wp-admin/`
  (except `admin-ajax.php`). Template in `references/seo-plugin-config.md`.
- **Canonicals**: self-referential per page using the production host; ensure no
  duplicate `localhost` canonicals survive ship (the `ship` stage runs
  `wp search-replace` for URLs — but set canonical base to production here).

Verify the sitemap:
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" eval 'echo home_url("/sitemap_index.xml");'` then
`curl -sI "$SITE/sitemap_index.xml"` (expect `200`).

## 5. Record outputs

```bash
wpbuild_set '.seo.metaApplied' 'true'
wpbuild_set '.seo.schemaTypes' '["Organization","WebSite","BreadcrumbList","Article"]'
wpbuild_set '.seo.sitemap'     'true'
wpbuild_progress seo done "meta+schema+sitemap via ${SEO_PLUGIN}"
```

Set `schemaTypes` to exactly what you emitted. If a check failed (sitemap 404,
plugin missing and fallback not writable), record `seo done` with a note, or
`failed` if SEO is required for ship.

## Delegation

- SEO analysis/scoring/generation → installed **claude-seo** skills (preferred).
- Theme head/functions.php edits → **wp-theme-developer** agent with the meta
  map, schema JSON, target theme path, and acceptance criteria (valid JSON-LD,
  sitemap reachable, canonicals on production host).

See: `references/seo-plugin-config.md`, `references/schema-templates.md`,
`references/theme-head-fallback.php`, `references/delegate-claude-seo.md`.
