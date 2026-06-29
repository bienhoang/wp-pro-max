---
name: content-enrichment
description: Add new pages and enrich headings, alt text, meta descriptions, and body copy on the optimized HTML copy before WordPress theme conversion. Reads wp-build.json, writes new pages into optimization.outputDir, and records changes in siteEditor.contentEnrichment. Use when asked to add pages, write copy, improve alt text, or enrich content for a WordPress build.
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# Content Enrichment (`content-enrichment` stage)

Add pages and enrich copy on the optimized HTML copy. Generated content is marked
as draft until the user explicitly approves it with `--approve`.

## Inputs

- `source.briefPath` — project brief.
- `analysis.pages[]` — existing pages.
- `optimization.outputDir` — working copy.
- `contentModel.menus[]` — navigation model.
- User instructions from `$ARGUMENTS`.

## Outputs

- New/modified HTML in `optimization.outputDir`.
- `siteEditor.contentEnrichment.addedPages[]`.
- `siteEditor.contentEnrichment.changes[]`.
- `siteEditor.contentEnrichment.lastModified`.
- Updated `analysis.pages[]` and `contentModel.menus[]`.
- `progress.content-enrichment`.

## Procedure

```bash
set -e
source "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh"

wpbuild_is_done content-enrichment && [[ "${1:-}" != "--force" ]] && { echo "content-enrichment already done"; exit 0; }
wpbuild_progress content-enrichment in-progress

# Parse mode from $ARGUMENTS:
#   --add-pages "Contact, Portfolio"
#   --from-brief
#   --enrich "improve alt text and meta descriptions"
#   --approve
```

1. **Resume guard.** Skip if already done unless `--force`.

2. **Add pages.** For `--add-pages` or `--from-brief`, run the helper:

   ```bash
   node "${CLAUDE_PLUGIN_ROOT}/scripts/content-enrichment.mjs" \
     "$WP_BUILD_FILE" --from-brief
   ```

   The helper scaffolds each new page from an existing optimized page, marks the
   main content with `data-wp-pro-max="draft"`, updates navigation links, and
   registers the page in `analysis.pages[]` and `contentModel.menus[]`.

3. **Enrich copy.** For `--enrich`, use Read/Edit on the optimized pages to:
   - Improve `<title>` and `<meta name="description">`.
   - Add or improve `alt` text on images.
   - Strengthen headings and body copy per the instructions.
   - Mark AI-edited blocks with `data-wp-pro-max="draft"`.
   Record each change in `siteEditor.contentEnrichment.changes[]`.

4. **Approve.** For `--approve`, run:

   ```bash
   node "${CLAUDE_PLUGIN_ROOT}/scripts/content-enrichment.mjs" \
     "$WP_BUILD_FILE" --approve
   ```

   This removes all `data-wp-pro-max="draft"` markers and records the approval
   timestamp.

5. **Finish.**

   ```bash
   wpbuild_merge '{"siteEditor":{"contentEnrichment":{"lastModified":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}}}'
   wpbuild_progress content-enrichment done "N pages added, M changes applied"
   ```

## Safety rules

- Never overwrite an existing page without `--force`.
- Never edit `source/` or `assets/`.
- All generated/enriched content stays draft until `--approve`.
