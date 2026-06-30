---
phase: 4
title: "Section Redesign Skill"
status: done
priority: P1
dependencies: [1, 2]
---

# Phase 4: Section Redesign Skill

## Overview

Create `skills/section-redesign/SKILL.md` and supporting references. The skill manipulates sections in the optimized HTML copy: add, remove, reorder, rewrite markup/CSS, and reuse components from `analysis.components[]`.

## Requirements

- Functional: Skill accepts user instructions and applies changes to `.wp-pro-max/optimized/` across all pages by default; `--page <path>` limits scope. Each change is recorded in `siteEditor.redesign.appliedChanges[]`.
- Functional: Skill backs up the optimized copy to `.wp-pro-max/optimized-backup/` before first edit.
- Functional: Skill validates HTML after each edit and rolls back on malformed output.
- Functional: Skill updates `analysis.pages[].sections[]` when sections are added or removed.
- Non-functional: Source HTML is never touched; skill is idempotent and resumable.

## Architecture

Stage id: `section-redesign`

Inputs:
- `analysis.pages[].sections[]`
- `optimization.outputDir`
- `designTokens`
- `analysis.components[]`
- User prompt / instructions

Outputs:
- Modified HTML in `optimization.outputDir`
- `siteEditor.redesign.appliedChanges[]`
- `siteEditor.redesign.backupDir`
- `siteEditor.redesign.lastModified`
- Updated `analysis.pages[].sections[]`
- `siteEditor.redesign.canRevert` (true when a backup exists and matches current state)

Procedure:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh"
wpbuild_is_done section-redesign && [[ "${1:-}" != "--force" ]] && { echo "section-redesign already done"; exit 0; }
wpbuild_progress section-redesign in-progress

OUTDIR="$(wpbuild_get '.optimization.outputDir')"
BACKUP_BASE="./.wp-pro-max/optimized-backup"
BACKUP="${BACKUP_BASE}/$(date -u +%Y%m%d-%H%M%S)"
[ -d "$BACKUP_BASE" ] || mkdir -p "$BACKUP_BASE"
# Keep only the latest N backups (e.g., 5) to avoid unbounded growth
ls -1td "$BACKUP_BASE"/* 2>/dev/null | tail -n +6 | xargs -r rm -rf
# Snapshot current optimized copy before editing
cp -R "$OUTDIR" "$BACKUP"

# Parse target and instruction from $ARGUMENTS or flags
# If no --page is given, iterate all pages in analysis.pages[]
# Use scripts/html-section-lib.sh to locate/replace/reorder sections
# Validate final HTML (node --check or lightweight validator)
# Present changes for user approval; if rejected, restore from backup
# Record changes and update analysis.pages[].sections[]

wpbuild_merge '{"siteEditor":{"redesign":{"backupDir":"'"$BACKUP"'","lastModified":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}}}'
wpbuild_progress section-redesign done "N sections changed"
```

## Related Code Files

- Create: `skills/section-redesign/SKILL.md`
- Create: `skills/section-redesign/references/section-redesign-patterns.md`
- Create: `skills/section-redesign/references/component-reuse.md`
- Read: `skills/html-optimization/SKILL.md`
- Read: `scripts/html-section-lib.sh`

## Implementation Steps

1. **TDD — create fixture and expectation.** In `plans/.../fixtures/section-redesign/`:
   - Copy `examples/sample-site` to a mock `.wp-pro-max/optimized/`.
   - Define a redesign instruction: "Move the services section before the hero on index.html."
   - Define expected HTML diff and expected `siteEditor.redesign.appliedChanges[0]` shape.
2. Run the expectation script; expect failure.
3. Write `skills/section-redesign/SKILL.md` with resume guard, backup, dispatch logic, and output writing.
4. Write `references/section-redesign-patterns.md` covering common transformations (reorder, remove, rewrite markup, rewrite CSS).
5. Write `references/component-reuse.md` explaining how to reuse entries from `analysis.components[]`.
6. Implement the skill behavior against the fixture and compare output.
7. Verify idempotency: run twice; second run should skip unless `--force`.

## Test-First Structure

```bash
# Setup fixture
mkdir -p /tmp/section-redesign-test/.wp-pro-max/optimized
cp -R examples/sample-site/* /tmp/section-redesign-test/.wp-pro-max/optimized/
cat > /tmp/section-redesign-test/wp-build.json <<'EOF'
{ "version":"1", "project":{"name":"Test","themeSlug":"test"}, "strategy":"classic-acf",
  "analysis":{"pages":[{"path":"index.html","title":"Home","role":"home","sections":["hero","services"]}]},
  "optimization":{"outputDir":"./.wp-pro-max/optimized"}, "progress":{}, "siteEditor":{} }
EOF

# Expected: after skill runs, sections order is ["services","hero"] and appliedChanges has one entry
```

## Success Criteria

- [ ] `skills/section-redesign/SKILL.md` exists with correct frontmatter.
- [ ] Skill backs up optimized copy before first edit.
- [ ] Skill applies add/remove/reorder/rewrite operations on the optimized copy (all pages by default, or one page with `--page`).
- [ ] Skill validates HTML and rolls back on parse failure or user rejection.
- [ ] Skill records changes in `siteEditor.redesign.appliedChanges[]`.
- [ ] Skill updates `analysis.pages[].sections[]` when structure changes.
- [ ] Re-running without `--force` skips the stage.

## Risk Assessment

- **Risk:** AI-generated HTML section is malformed.  
  **Mitigation:** Parse with cheerio and compare node count before/after; on failure, restore from backup and record failure.
- **Risk:** Backup grows unbounded.  
  **Mitigation:** Versioned backups with a retention limit (keep latest 5); old backups pruned automatically.
