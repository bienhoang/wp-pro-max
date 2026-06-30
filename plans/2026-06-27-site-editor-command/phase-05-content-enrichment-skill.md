---
phase: 5
title: "Content Enrichment Skill"
status: done
priority: P1
dependencies: [1, 2]
---

# Phase 5: Content Enrichment Skill

## Overview

Create `skills/content-enrichment/SKILL.md` and references. The skill adds new pages and enriches existing copy on the optimized HTML copy from the project brief and user prompts.

## Requirements

- Functional: Skill can add pages listed in `requirements/brief.md` or from a comma-separated `--add-pages` argument.
- Functional: Skill can enrich headings, alt text, meta descriptions, and body copy from user instructions.
- Functional: New pages are written to `optimization.outputDir` and registered in `analysis.pages[]` and `contentModel.menus[]`.
- Functional: Generated content is marked with `data-wp-pro-max="draft"` and is not considered final until the user runs with `--approve`.
- Functional: Skill never overwrites existing files without `--force`.
- Non-functional: Source HTML is never touched; skill is idempotent and resumable.

## Architecture

Stage id: `content-enrichment`

Inputs:
- `source.briefPath`
- `analysis.pages[]`
- `optimization.outputDir`
- `contentModel.menus[]`
- User prompt / page list

Outputs:
- New/modified HTML in `optimization.outputDir`
- `siteEditor.contentEnrichment.addedPages[]`
- `siteEditor.contentEnrichment.changes[]`
- `siteEditor.contentEnrichment.lastModified`
- Updated `analysis.pages[]`
- Updated `contentModel.menus[]`

Procedure:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh"
wpbuild_is_done content-enrichment && [[ "${1:-}" != "--force" ]] && { echo "content-enrichment already done"; exit 0; }
wpbuild_progress content-enrichment in-progress

BRIEF="$(wpbuild_get '.source.briefPath // "../requirements/brief.md"')"
OUTDIR="$(wpbuild_get '.optimization.outputDir')"

# Parse mode: --add-pages or --enrich
# Read brief sections "Pages" and "Content & data" if --from-brief
# Brief parser convention:
#   - "## Pages" section contains "- <Title>: <description>" or "- <Title>" lines.
#   - "## Content & data" section contains repeated content types that may become pages.
#   - Unknown formats are ignored with a warning rather than failing.
# For each new page: derive slug from title, scaffold from an existing page template,
#   replace content, write to OUTDIR/<slug>.html, update nav links if a nav component is detected.
# For enrich: iterate existing pages and rewrite targeted elements per instructions
# Mark generated blocks with data-wp-pro-max="draft"
# If --approve is missing, stop after writing and tell the user to review/re-run with --approve
# Record additions/changes

wpbuild_merge '{"siteEditor":{"contentEnrichment":{"lastModified":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}}}'
wpbuild_progress content-enrichment done "N pages added, M changes applied"
```

## Related Code Files

- Create: `skills/content-enrichment/SKILL.md`
- Create: `skills/content-enrichment/references/content-sources.md`
- Create: `skills/content-enrichment/templates/new-page.html` (optional base template)
- Read: `commands/site-editor.md` (for flag contract)

## Implementation Steps

1. **TDD — create fixture and expectation.** In `plans/.../fixtures/content-enrichment/`:
   - Provide a `requirements/brief.md` with a new page request.
   - Provide a mock `wp-build.json` pointing to an optimized copy of `examples/sample-site`.
   - Define expected new file path and expected `analysis.pages[]` / `siteEditor.contentEnrichment.addedPages[]` entries.
2. Run the expectation script; expect failure.
3. Write `skills/content-enrichment/SKILL.md` with resume guard, brief parsing, page generation, and enrichment logic.
4. Write `references/content-sources.md` documenting how brief sections map to pages and content.
5. Implement the skill against the fixture.
6. Verify idempotency and `--force` overwrite behavior.

## Test-First Structure

```bash
# Setup fixture
mkdir -p /tmp/content-enrichment-test/requirements /tmp/content-enrichment-test/.wp-pro-max/optimized
cat > /tmp/content-enrichment-test/requirements/brief.md <<'EOF'
# Project brief
## Pages
- Contact: contact page with form and address
EOF
cp -R examples/sample-site/* /tmp/content-enrichment-test/.wp-pro-max/optimized/
cat > /tmp/content-enrichment-test/wp-build.json <<'EOF'
{ "version":"1", "project":{"name":"Test","themeSlug":"test"}, "strategy":"classic-acf",
  "source":{"briefPath":"./requirements/brief.md"},
  "analysis":{"pages":[{"path":"index.html","title":"Home","role":"home","sections":["hero","services"]}]},
  "optimization":{"outputDir":"./.wp-pro-max/optimized"}, "contentModel":{"menus":[]}, "progress":{}, "siteEditor":{} }
EOF

# Expected: contact.html created, analysis.pages has contact entry, siteEditor.contentEnrichment.addedPages has record
```

## Success Criteria

- [ ] `skills/content-enrichment/SKILL.md` exists with correct frontmatter.
- [ ] `--add-pages` creates new HTML files and registers them in `analysis.pages[]`.
- [ ] `--enrich` rewrites targeted content and records changes.
- [ ] Generated content is marked `data-wp-pro-max="draft"` and requires `--approve` to finalize.
- [ ] Existing files are preserved unless `--force` is passed.
- [ ] `contentModel.menus[]` is updated when navigation changes.
- [ ] Re-running without `--force` skips the stage.

## Risk Assessment

- **Risk:** Generated copy does not match brand voice.  
  **Mitigation:** Mark as draft and require user review; never auto-approve.
- **Risk:** Added page breaks relative links/assets.  
  **Mitigation:** Generate pages at the same directory level as existing pages and copy shared `<head>`/nav/footer from an existing page template.
- **Risk:** Brief format is free-form and hard to parse reliably.  
  **Mitigation:** Document the supported brief convention in `references/content-sources.md`; fail gracefully with a warning for unsupported formats.
