---
phase: 3
title: "Command Authoring"
status: done
priority: P1
dependencies: [1, 2]
---

# Phase 3: Command Authoring

## Overview

Author `commands/site-editor.md`, the user entry point that dispatches to the three child skills. The command stays outside the main pipeline for this iteration and does not gate `ship`.

## Requirements

- Functional: `commands/site-editor.md` supports `--redesign`, `--add-pages`, `--enrich`, `--check`, `--preview`, `--all`, and interactive mode.
- Functional: The command refuses to run if `wp-build.json` or `optimization.outputDir` is missing.
- Functional: The command auto-descends into `wp/` in an `init`-scaffolded parent-wrapper project, like `build.md` and `init.md`.
- Functional: Each subcommand invokes the matching child skill with `Skill(name="wp-pro-max:<skill>", arguments="...")`.
- Non-functional: The command file is ≤ ~150 lines and follows the frontmatter/argument pattern of existing commands.

## Architecture

```yaml
---
description: Edit the optimized HTML copy before WordPress conversion. Redesign sections, add/enrich pages, and run pre-conversion UI/UX QA.
argument-hint: [--redesign <instructions> [--page <path>]] [--add-pages <page-list>|--from-brief] [--enrich <instructions>] [--approve] [--check [--quick|--thorough]] [--preview] [--revert] [--all]
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Task, Skill]
---
```

Subcommand mapping:

| CLI flag | Child skill | Notes |
|----------|-------------|-------|
| `--redesign "<instructions>"` | `wp-pro-max:section-redesign` | Applies to all optimized pages by default; use `--page <path>` to limit scope. |
| `--add-pages "<page-list>"` | `wp-pro-max:content-enrichment` | Comma-separated list or `--from-brief`. Generated content is draft until `--approve`. |
| `--enrich "<instructions>"` | `wp-pro-max:content-enrichment` | Rewrites headings/alt/meta; marks draft content. Draft until `--approve`. |
| `--approve` | `wp-pro-max:content-enrichment` | Finalizes previously generated draft content. |
| `--check [--quick\|--thorough]` | `wp-pro-max:pre-conversion-qa` | Default is `--quick`. |
| `--preview` | (command-local) | Calls `scripts/html-preview.sh` on `optimization.outputDir/index.html`. |
| `--revert` | (command-local) | Restores optimized copy from the latest backup and clears redesign changes. |
| `--all` | sequence | redesign → enrich → check (quick mode unless `--thorough`). |

Interactive mode (no flags): print detected pages/sections from `analysis.pages[]` and present a numbered menu:

```text
WP Pro Max Site Editor — optimized copy at .wp-pro-max/optimized/
Pages: 1) index.html (home) — sections: hero, services
       2) about.html (page) — sections: hero, team
Actions: [r] redesign  [a] add pages  [e] enrich  [c] check  [p] preview  [q] quit
```

`--all` runs redesign → enrich → check in quick mode. `--all --thorough` runs check in thorough mode.

`--revert` restores `optimization.outputDir` from the latest backup in `siteEditor.redesign.backupDir` and clears `siteEditor.redesign.appliedChanges[]`.

Procedure sketch:

```bash
set -e
source "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh"

# Resolve project root: prefer current dir, else parent-wrapper ./wp/
if [ ! -f "$WP_BUILD_FILE" ] && [ -f "./wp/wp-build.json" ]; then
  cd ./wp
fi
[ -f "$WP_BUILD_FILE" ] || { echo "site-editor: wp-build.json not found"; exit 1; }

OUTDIR="$(wpbuild_get '.optimization.outputDir // ""')"
[ -n "$OUTDIR" ] && [ -d "$OUTDIR" ] || { echo "site-editor: optimized copy missing; run /wp-pro-max:build --to optimize first"; exit 1; }

# Parse flags and dispatch
```

## Related Code Files

- Create: `commands/site-editor.md`
- Read: `commands/build.md`, `commands/init.md` (for parent-wrapper and dispatch patterns)
- Read: `scripts/manifest-lib.sh`
- Read: `scripts/html-preview.sh`

## Implementation Steps

1. **TDD — define expected behavior.** Create `plans/.../fixtures/test-site-editor-command.sh` that:
   - runs the command parser against `--redesign`, `--check`, `--preview` flags in a mock project.
   - asserts the command exits non-zero when `wp-build.json` is absent.
   - asserts the command exits non-zero when `optimization.outputDir` is absent.
2. Run the test; expect failures.
3. Write `commands/site-editor.md` with frontmatter, argument parsing, dependency guard, and skill dispatch.
4. Re-run tests.
5. Manually invoke `/wp-pro-max:site-editor --preview` against `examples/sample-site` to verify browser opens.

## Test-First Structure

```bash
# In a temporary mock project:
mkdir -p /tmp/site-editor-test/wp
# Missing manifest → exit 1
bash -c 'source commands/site-editor.md parse --redesign "x"'  # or equivalent dry-run
# Missing optimized dir → exit 1
# Valid project → dispatch to skill (mock skill call)
```

Because commands are markdown consumed by the plugin runtime, also validate the file with:

```bash
claude plugin validate .   # ensures commands/site-editor.md is parseable
```

## Success Criteria

- [ ] `commands/site-editor.md` exists with correct frontmatter and usage docs.
- [ ] Missing manifest and missing optimized directory produce clear errors.
- [ ] Each flag dispatches to the correct child skill.
- [ ] `--preview` opens the optimized index in the default browser.
- [ ] `--all` runs redesign → enrich → check in order.
- [ ] `claude plugin validate .` passes.

## Risk Assessment

- **Risk:** Command dispatches to a skill name that does not exist yet (chicken-and-egg during implementation).  
  **Mitigation:** Implement the command after the skills exist, or stub the skill files first in Phase 4–6.
- **Risk:** Interactive mode is underspecified and hard to test.  
  **Mitigation:** Ship a minimal interactive prompt in this iteration; expand later.
- **Risk:** User runs command from project root in a parent-wrapper layout and it cannot find `wp-build.json`.  
  **Mitigation:** Mirror `build.md`/`init.md` behavior: auto-descend into `./wp/` when the manifest is there.
