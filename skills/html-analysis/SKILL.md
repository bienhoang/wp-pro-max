---
name: html-analysis
description: >-
  Analyzes static HTML/CSS/JS (or a URL or written brief) before a WordPress
  build. Detects the page set and each page's role (home/page/post/archive/
  landing), repeated UI components (header, footer, nav, card, hero, grid,
  form, cta), the asset inventory (images, fonts, scripts, styles), and the
  information architecture (sitemap and menu tree). Recommends a theme strategy
  (classic-acf, block-fse, or page-builder). Writes findings to wp-build.json
  under `analysis.*`. Use when intaking a static site, mockup, or design for
  WordPress conversion, or when the build pipeline reaches the `analyze` stage.
allowed-tools: [Read, Glob, Grep, Bash]
---

# HTML Analysis (`analyze` stage)

Inspect the source and record a structured picture of what must be rebuilt in
WordPress. You read `source.*` from the manifest and write `analysis.*`.

## 0. Resume guard

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh"
wpbuild_is_done analyze && [[ "${1:-}" != "--force" ]] && { echo "analyze already done"; exit 0; }
wpbuild_progress analyze in-progress
```

## 1. Read the source descriptor

```bash
SRC_TYPE=$(wpbuild_get '.source.type')          # html-files | url | brief

if [ -z "$SRC_TYPE" ] || [ "$SRC_TYPE" = "null" ]; then
  # Auto-detect source.type from inputs produced by /wp-pro-max:init
  _has_html=false
  while IFS= read -r _p; do
    [ -z "$_p" ] && continue
    if find "$_p" -maxdepth 5 -name '*.html' -print 2>/dev/null | grep -q .; then
      _has_html=true
      break
    fi
  done <<EOF
$(wpbuild_get '.source.htmlPaths[]' 2>/dev/null || true)
EOF

  if [ "$_has_html" = true ]; then
    SRC_TYPE=html-files
  elif [ -s "$(wpbuild_get '.source.briefPath' 2>/dev/null || true)" ]; then
    SRC_TYPE=brief
  fi

  if [ -n "$SRC_TYPE" ]; then
    wpbuild_set '.source.type' "\"$SRC_TYPE\""
  else
    echo "analyze: no source found — add HTML to source/ or fill requirements/brief.md" >&2
    exit 1
  fi
  unset _has_html _p
fi
```

- `html-files`: iterate `source.htmlPaths` + `source.assetDirs`. Use **Glob**
  (`**/*.html`, `**/*.css`, `**/*.js`) then **Read**/**Grep** to inspect.
- `url`: fetch the page(s) with `curl -sL <url>` into the scratchpad, then
  treat the saved files as `html-files`. Crawl same-host links found in nav.
- `brief`: read `source.briefPath`; derive the page set and components from the
  written requirements instead of parsing markup.

## 2. Detect the page set + role

For each HTML file determine its role with this precedence:

| Signal | Role |
|--------|------|
| `index.html` / `home*` / root, hero + mixed sections | `home` |
| repeated post-card list, pagination, `/blog`, `/news` | `archive` |
| single article: `<article>`, byline, published date | `post` |
| one focused conversion goal, minimal nav, strong CTA | `landing` |
| dynamic detail view template (`*-single`, `[slug]`) | `single` |
| everything else (about, contact, services) | `page` |

Capture each page's ordered section list (hero, features, testimonials, …) from
top-level `<section>`/landmark blocks and heading structure.

## 3. Detect repeated UI components

Find structural blocks that recur across (or within) pages and count them.
Search by role with **Grep**:

- `header` / `footer` — `<header>`, `<footer>`, `role="banner|contentinfo"`.
- `nav` — `<nav>`, `role="navigation"`, `.menu`, `.navbar`.
- `card` — repeated sibling blocks with image + heading + text (`.card`, `.item`).
- `hero` — first full-width section with headline + CTA (`.hero`, `.banner`).
- `grid` — repeated columns/`grid`/`row` wrappers holding cards.
- `form` — `<form>`, inputs (contact, newsletter, search).
- `cta` — button clusters / banners pushing one action.

A block repeating **3+ times with the same shape** is a component candidate AND
a content-model candidate (flag it for the `model` stage). Record `name`,
`kind`, and integer `occurrences`.

## 4. Asset inventory

Collect with Grep + Glob, dedupe, store relative paths:

- `images` — `<img src>`, `srcset`, `background-image:url()`, `<picture>`, svg.
- `fonts` — `@font-face`, `fonts.googleapis.com` links, local `.woff2`.
- `scripts` — `<script src>` (note libs: jQuery, GSAP, Swiper, Alpine).
- `styles` — `<link rel=stylesheet>`, inline `<style>`, `.css` files.

## 5. Information architecture

Build the sitemap/menu tree from the primary `<nav>` of the home page (fallback:
union of all nav links). Each node: `{ "label", "url", "children": [] }`.
Mark external links and anchor-only links. This feeds menus in the `model` stage.

## 6. Recommend a theme strategy

Score the source, then recommend (do not silently overwrite a user-set
`strategy`; if one exists, only annotate agreement/conflict in notes):

| Indicator | Lean |
|-----------|------|
| Mostly static marketing pages, a few repeated content types, client wants editor-friendly fields | **classic-acf** |
| Editorial/content-led, wants native block editor + global styles, modern WP | **block-fse** |
| Heavy bespoke interactions, existing builder markup, non-dev maintainers | **page-builder** |

Heuristics: high JS interactivity + many unique layouts → `page-builder` or
`block-fse`; clear repeated record types (team, services, portfolio) → CPT-heavy
→ `classic-acf`. See `references/strategy-decision.md` for the full rubric.

## 7. Write findings

Build the analysis object (jq assembles arrays from your findings) and persist:

```bash
wpbuild_set '.analysis' "$ANALYSIS_JSON"      # full object
# or incrementally:
wpbuild_merge '{"analysis":{"components":[{"name":"service-card","kind":"card","occurrences":6}]}}'
wpbuild_set '.strategy' '"classic-acf"'        # only if not user-set
wpbuild_progress analyze done "N pages, M components, strategy=classic-acf"
```

`analysis` shape (see `schemas/wp-build.schema.json`):
`{ pages[], components[], assets{images,fonts,scripts,styles}, informationArchitecture[] }`.

## Output contract

End by printing a short human summary: page count by role, top components with
counts, asset totals, and the recommended strategy with one-line rationale.
Hand off to `optimize`, `model`, and `tokens`. Deep heavy parsing of large
sites should be delegated; this skill itself stays read-only.

See also: `references/component-detection.md`, `references/strategy-decision.md`.
