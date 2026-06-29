---
description: Edit the optimized HTML copy before WordPress conversion. Redesign sections, add/enrich pages, and run pre-conversion UI/UX QA.
argument-hint: [--redesign <instructions> [--page <path>]] [--add-pages <page-list>|--from-brief] [--enrich <instructions>] [--approve] [--check [--quick|--thorough]] [--preview] [--revert] [--all]
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Task, Skill]
---

# /wp-pro-max:site-editor

Edit the optimized HTML copy (`.wp-pro-max/optimized/`) after optimization and
before theme conversion. Changes are manifest-driven, source files stay read-only,
and backups enable `--revert`.

## Flags

- `--redesign "<instructions>"` → `wp-pro-max:section-redesign` (all pages; limit with `--page <path>`).
- `--add-pages "<list>"` / `--from-brief` → `wp-pro-max:content-enrichment`.
- `--enrich "<instructions>"` / `--approve` → `wp-pro-max:content-enrichment`.
- `--check [--quick|--thorough]` → `wp-pro-max:pre-conversion-qa` (default `--quick`).
- `--preview` opens `optimization.outputDir/index.html` in the default browser.
- `--revert` restores optimized copy from the latest backup.
- `--all` runs `redesign → enrich → check`.

No flags enters interactive mode: list optimized pages and prompt for an action.

## Procedure

```bash
set -e
source "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh"
source "${CLAUDE_PLUGIN_ROOT}/scripts/site-editor-lib.sh"

site_editor_require_manifest_and_outdir || exit 1
site_editor_parse_args $ARGUMENTS || exit 2

if [ -z "$SITE_EDITOR_ACTION" ]; then
  echo "WP Pro Max Site Editor — optimized copy at $SITE_EDITOR_OUTDIR"
  wpbuild_get '.analysis.pages[] | "\(.path) (\(.role)) — sections: \(.sections | join(", "))"' 2>/dev/null || true
  echo "Actions: [r] redesign [a] add pages [e] enrich [c] check [p] preview [q] quit"
  exit 0
fi

run_skill() { Skill(name="$1", arguments="$2"); }

case "$SITE_EDITOR_ACTION" in
  redesign)
    ARGS="$SITE_EDITOR_REDESIGN"
    [ -n "$SITE_EDITOR_PAGE" ] && ARGS="$ARGS --page $SITE_EDITOR_PAGE"
    run_skill "wp-pro-max:section-redesign" "$ARGS" ;;
  add-pages)
    [ -n "$SITE_EDITOR_FROM_BRIEF" ] && run_skill "wp-pro-max:content-enrichment" "--from-brief" || run_skill "wp-pro-max:content-enrichment" "--add-pages $SITE_EDITOR_ADD_PAGES" ;;
  enrich) run_skill "wp-pro-max:content-enrichment" "--enrich $SITE_EDITOR_ENRICH" ;;
  approve) run_skill "wp-pro-max:content-enrichment" "--approve" ;;
  check) run_skill "wp-pro-max:pre-conversion-qa" "$SITE_EDITOR_CHECK_MODE" ;;
  preview)
    INDEX="$SITE_EDITOR_OUTDIR/index.html"
    [ -f "$INDEX" ] || INDEX="$SITE_EDITOR_OUTDIR/$(wpbuild_get '.analysis.pages[0].path')"
    bash "${CLAUDE_PLUGIN_ROOT}/scripts/html-preview.sh" "$INDEX" ;;
  revert)
    BACKUP="$(wpbuild_get '.siteEditor.redesign.backupDir // ""')"
    [ -n "$BACKUP" ] && [ -d "$BACKUP" ] || { echo "site-editor: no backup to revert from" >&2; exit 1; }
    rm -rf "$SITE_EDITOR_OUTDIR"; cp -R "$BACKUP" "$SITE_EDITOR_OUTDIR"
    ORIGINAL_PAGES="$(wpbuild_get '.siteEditor.redesign.originalPages // ""')"
    [ -n "$ORIGINAL_PAGES" ] && wpbuild_set '.analysis.pages' "$ORIGINAL_PAGES"
    wpbuild_set '.siteEditor.redesign.appliedChanges' '[]'
    wpbuild_set '.siteEditor.redesign.canRevert' 'false'
    echo "site-editor: reverted from $BACKUP" ;;
  all)
    run_skill "wp-pro-max:section-redesign" "$SITE_EDITOR_REDESIGN"
    run_skill "wp-pro-max:content-enrichment" "--enrich $SITE_EDITOR_ENRICH"
    run_skill "wp-pro-max:pre-conversion-qa" "$SITE_EDITOR_CHECK_MODE" ;;
esac
```
