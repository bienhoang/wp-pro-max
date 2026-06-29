---
name: section-redesign
description: Redesign, reorder, add, or remove sections in the optimized HTML copy before WordPress theme conversion. Reads wp-build.json, edits optimization.outputDir only, and records changes in siteEditor.redesign. Use when asked to redesign a section, move sections, change a page layout, or apply section-level changes to the optimized HTML.
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# Section Redesign (`section-redesign` stage)

Manipulate sections in the optimized HTML copy (`optimization.outputDir`).
Source files are read-only; all edits happen on the working copy. Every change is
recorded in `siteEditor.redesign.appliedChanges[]` so it can be reviewed or
reverted.

## Inputs

- `optimization.outputDir` — working copy path.
- `analysis.pages[]` — pages and their sections.
- `analysis.components[]` — reusable blocks.
- `designTokens` — colors, fonts, spacing.
- User instructions from `$ARGUMENTS` (e.g. "move services before hero on index").

## Outputs

- Modified HTML in `optimization.outputDir`.
- `siteEditor.redesign.appliedChanges[]`.
- `siteEditor.redesign.backupDir`.
- `siteEditor.redesign.lastModified`.
- `siteEditor.redesign.canRevert`.
- Updated `analysis.pages[].sections[]`.
- `progress.section-redesign`.

## Procedure

```bash
set -e
source "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh"
source "${CLAUDE_PLUGIN_ROOT}/scripts/html-section-lib.sh"

wpbuild_is_done section-redesign && [[ "${1:-}" != "--force" ]] && { echo "section-redesign already done"; exit 0; }
wpbuild_progress section-redesign in-progress

OUTDIR="$(wpbuild_get '.optimization.outputDir')"
BACKUP_BASE="./.wp-pro-max/optimized-backup"
mkdir -p "$BACKUP_BASE"
# Keep only the 5 latest backups
ls -1td "$BACKUP_BASE"/* 2>/dev/null | tail -n +6 | xargs -r rm -rf
BACKUP="$BACKUP_BASE/$(date -u +%Y%m%d-%H%M%S)"
cp -R "$OUTDIR" "$BACKUP"

# Snapshot the original page list/sections so --revert can restore them.
ORIGINAL_PAGES="$(wpbuild_get '.analysis.pages')"
wpbuild_merge '{"siteEditor":{"redesign":{"originalPages":'"$ORIGINAL_PAGES"'}}}'

# Parse scope from $ARGUMENTS. Default to all pages in analysis.pages[].
# Limit to --page <path> if provided.
```

1. **Parse intent.** Decide whether the request is to:
   - `reorder` sections (e.g. "move services before hero"),
   - `remove` a section (e.g. "remove the testimonials section"),
   - `add` a section (e.g. "add a CTA section after hero"),
   - `rewrite` a section's markup or CSS class (e.g. "make the hero full-bleed").

2. **Resolve scope.** If `--page <path>` is given, edit only that page; otherwise
   apply to every `analysis.pages[].path` under `$OUTDIR`.

3. **Apply the change with helpers.** Use `scripts/html-section-lib.sh`:
   - `section_find`, `section_replace`, `section_insert_before`,
     `section_insert_after`, `section_remove`, `section_reorder`.
   - For new sections, generate semantic HTML that matches the existing design
     tokens and component patterns (see `references/component-reuse.md`).

4. **Validate HTML after each edit.** Parse the result with cheerio; if the
   document becomes malformed, restore from `$BACKUP` and record the failure.

5. **Update the manifest.** Append an entry to
   `siteEditor.redesign.appliedChanges[]`:

   ```json
   {
     "page": "index.html",
     "action": "reorder",
     "sections": ["services", "hero"],
     "timestamp": "2026-06-27T10:05:00Z"
   }
   ```

   Update `analysis.pages[].sections[]` if the page structure changed.

6. **Finish.** Write `siteEditor.redesign.{backupDir,lastModified,canRevert}` and
   mark `progress.section-redesign` done.

```bash
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
wpbuild_merge '{"siteEditor":{"redesign":{"backupDir":"'"$BACKUP"'","lastModified":"'"$TS"'","canRevert":true}}}'
wpbuild_progress section-redesign done "N sections changed"
```

## Safety rules

- Never edit `source/` or `assets/`.
- Always back up before the first edit in a run.
- Mark AI-generated blocks with `data-wp-pro-max="draft"` until the user approves.
- If a requested selector is missing, stop and report; do not guess.
