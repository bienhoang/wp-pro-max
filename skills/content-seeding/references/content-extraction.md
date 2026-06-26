# Content Extraction — optimized HTML → WordPress page body

Goal: pull the **real** editable body of each page out of the optimized source
HTML and store it as `content/<slug>.html`, ready for
`ensure_page <slug> <title> content/<slug>.html`. Never substitute lorem ipsum.

## What belongs in the page body vs. the theme

| HTML region | Destination |
|-------------|-------------|
| `<header>` / global nav | Theme `header.php` / `parts/header.html` — **exclude** |
| `<footer>` / global footer | Theme `footer.php` / `parts/footer.html` — **exclude** |
| `<main>` / primary content | Page body — **include** |
| repeated card/grid records | CPT posts (seed separately), not inline body |
| `<script>` / `<style>` / analytics | Drop (theme enqueues handle assets) |

## Extraction recipe

1. Prefer the first `<main>`; else the largest content container
   (`#content`, `.content`, `article`, `.entry-content`, `[role="main"]`).
2. Remove `header, nav, footer, script, style, noscript, .site-header,
   .site-footer, .menu, .breadcrumbs` nodes from the chosen subtree.
3. Keep semantic content: `h1–h6, p, ul, ol, li, blockquote, figure, img, a,
   table, strong, em`. Strip framework utility wrappers but keep their inner
   content (unwrap `<div class="container">` etc.).
4. Normalize: collapse whitespace, drop empty nodes, keep `alt` on images.
5. For `img src`, rewrite to the media-library URL after `import_media`
   (match by filename), or keep the relative path and rewrite post-import with
   `wp search-replace` (guarded, dry-run first) during QA.

A quick host-side extraction with Node (no new deps; uses regex/cheerio if
available). Pseudocode:

```bash
node -e '
  const fs=require("fs");
  let html=fs.readFileSync(process.argv[1],"utf8");
  // crude main-region capture; replace with cheerio when present
  let m = html.match(/<main[^>]*>([\s\S]*?)<\/main>/i);
  let body = m ? m[1] : html;
  body = body
    .replace(/<(script|style|noscript)[\s\S]*?<\/\1>/gi,"")
    .replace(/<(header|footer|nav)[\s\S]*?<\/\1>/gi,"")
    .trim();
  process.stdout.write(body);
' "$OUTDIR/about.html" > content/about.html
```

Prefer a real parser (cheerio / linkedom) when available for robustness; the
regex form is a last-resort fallback. Validate output is non-empty before
writing the `ensure_page` call.

## Brief-driven fallback (`source.type == "brief"`)

When there is no source HTML, generate each required page body from the brief:
one `<h1>` per page, then the brief's section copy as `<h2>`/`<p>` blocks.
Use the brief's literal wording; do not pad with filler.

## Block vs. classic body

- **classic-acf / page-builder host**: store HTML directly; the classic editor
  stores it verbatim.
- **block-fse**: wrap extracted HTML in block comments so it round-trips in the
  block editor, e.g. `<!-- wp:paragraph --><p>…</p><!-- /wp:paragraph -->`.
  At minimum, wrap a raw chunk in `<!-- wp:html -->…<!-- /wp:html -->` so the
  editor does not flag invalid block content. Headings → `wp:heading`,
  images → `wp:image`, lists → `wp:list`.

## Idempotency contract

The generated `seed-content.sh` only calls `ensure_*` helpers, so content is
keyed by slug/title. Re-extraction overwrites `content/<slug>.html`, but the
page is **updated only by re-running with explicit intent** — `ensure_page`
skips when the slug already exists. To push edited content into an existing
page, use `wp post update <ID> --post_content="$(cat content/<slug>.html)"`
(safe, targets one known ID), not a second `ensure_page`.
