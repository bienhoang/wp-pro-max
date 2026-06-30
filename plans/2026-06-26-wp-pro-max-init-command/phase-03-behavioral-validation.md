---
phase: 3
title: "Behavioral validation"
status: done
effort: ""
priority: P3
dependencies: [1, 2]
---

# Phase 3: Behavioral validation

<!-- Updated: Validation Session 1 - source.type absent assertion; git repo + analyze-detect checks -->

## Overview

Exercise `init` end to end in a throwaway directory (the repo's testing style:
behavioral, no test suite), assert the scaffold + manifest shape, prove
idempotency and build auto-descend, and run the plugin validation gate.

## Requirements

- Functional: verify tree, manifest contents, templates, idempotent re-run, and
  the `build` auto-descend guard.
- Non-functional: run in the scratchpad (not in the repo); leave no artifacts in
  the plugin repo (`wp-build.json`/WP output must never land here).

## Architecture

Validation harness (run from scratchpad, `CLAUDE_PLUGIN_ROOT` = this repo):

```bash
export CLAUDE_PLUGIN_ROOT="/Users/bienhg/Documents/Projects/wp-pro-max"
WORK="$(mktemp -d)"; cd "$WORK"

# Extract & syntax-check the scaffold script embedded in commands/init.md, then run
# the same logic for "Acme Studio" (spaced, mixed case) to test slug derivation.
# (Author may copy the bash block from init.md into a temp .sh for `bash -n`.)
```

## Related Code Files

- Test against: `commands/init.md`, `commands/build.md`, `scripts/manifest-lib.sh`
- No production files created in this phase.

## Implementation Steps

1. **Syntax** — extract the scaffold bash block from `commands/init.md` to a temp
   file and `bash -n` it; `node --check` not applicable.
2. **Scaffold** — run init for `"Acme Studio"`; assert:
   - dirs exist: `requirements source assets design mockups wp`
   - `.gitkeep` in `source assets design mockups`
   - `wp/wp-build.json` exists; templates `requirements/brief.md`, `.gitignore`,
     `README.md` exist; project root is a git repo (`Acme-Studio/.git` present).
3. **Manifest shape** — `jq -e` checks on `wp/wp-build.json` (note: `source.type`
   must be ABSENT):
   ```bash
   jq -e '.version=="1"
     and .project.themeSlug=="acme-studio"
     and .project.textDomain=="acme-studio"
     and .strategy=="classic-acf"
     and (.source|has("type")|not)
     and (.source.htmlPaths==["../source"])
     and (.source.assetDirs==["../assets"])
     and .source.briefPath=="../requirements/brief.md"
     and (.progress=={})' wp/wp-build.json
   ```
4. **Idempotency** — snapshot `wp/wp-build.json` + templates (sha), re-run init,
   assert unchanged (no overwrite, no error, no git re-init).
5. **Build auto-descend** — from `$WORK/Acme-Studio` (parent root, no
   `./wp-build.json`), confirm the guard resolves: 
   `[ ! -f ./wp-build.json ] && [ -f ./wp/wp-build.json ] && echo OK` → `OK`;
   confirm a relative input resolves after `cd ./wp`: `[ -d ../source ]`.
6. **Analyze source.type detect** — exercise the `html-analysis` step-1 snippet
   against the scaffold:
   - empty `source/` + non-empty `brief.md` ⇒ detect `brief`;
   - drop a dummy `source/index.html` ⇒ detect `html-files`;
   - assert the detected value is persisted via `wpbuild_set '.source.type'`.
7. **Plugin gate** — from the repo root: `claude plugin validate .` → passes.
8. **Cleanup** — `rm -rf "$WORK"`; confirm `git status` in the repo shows only the
   intended new/edited files (no stray `wp-build.json`).

## Success Criteria

- [ ] Scaffold script passes `bash -n`.
- [ ] Tree, `.gitkeep`s, 3 templates, and project-root git repo created.
- [ ] `jq -e` manifest assertion (step 3) exits 0 — incl. `source.type` absent.
- [ ] Re-run is idempotent (hashes match, exit 0, no git re-init).
- [ ] Auto-descend guard returns `OK` and `../source` resolves from `wp/`.
- [ ] Analyze detect resolves `brief` vs `html-files` correctly and persists it.
- [ ] `claude plugin validate .` passes; repo working tree has no stray WP output.

## Risk Assessment

- **Env coupling** — `CLAUDE_PLUGIN_ROOT` must point at the repo for the sourced
  helper to resolve. Mitigation: export it explicitly in the harness.
- **macOS `mktemp`/`sed`/`tr` quirks** — runtime shell is zsh on darwin.
  Mitigation: the slug filter uses POSIX `tr`/`sed` only; verify on the actual
  host (Phase 3 runs here, per CLAUDE.md "verify behaviorally here").
