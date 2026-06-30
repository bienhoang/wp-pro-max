---
title: "wp-pro-max:init project scaffolder command"
description: ""
status: done
priority: P2
branch: "main"
tags: []
blockedBy: []
blocks: []
created: "2026-06-26T10:53:14.208Z"
createdBy: "ck:plan"
source: skill
---

# wp-pro-max:init project scaffolder command

## Overview

Add `/wp-pro-max:init` — a command-only entry point that scaffolds a standard
**target WordPress project** working directory and writes a starter
`wp-build.json` wired into the pipeline. Goal: a predictable starting structure so
`build` knows where inputs live and where outputs go, across all 16 pipeline
stages.

Design source: [`brainstorm-wp-pro-max-init-command.md`](./brainstorm-wp-pro-max-init-command.md).

Key decisions (locked in brainstorm):
- **Layout:** parent-wrapper — inputs (`requirements/ source/ assets/ design/
  mockups/`) at the project root; the WordPress project (manifest, wp-env,
  generated theme) lives in a `wp/` subdir.
- **Scope:** folders + manifest + 3 templates (`brief.md`, `.gitignore`,
  `README.md`). No Docker, no skill, no schema change.
- **Component:** command only (`commands/init.md`) — init is not a pipeline stage.
- **Build:** taught to auto-descend into `./wp/` when no manifest in CWD.
- **Reuse:** `scripts/manifest-lib.sh` `wpbuild_init` / `wpbuild_set`; do not
  reimplement manifest logic.

Validation decisions (Session 1):
- **`source.type` left unset** by init — `html-analysis` (`analyze` stage)
  auto-detects it from folder contents (HTML in `source/` ⇒ `html-files`, else
  non-empty `brief.md` ⇒ `brief`) and persists it. Adds a small touchpoint to
  `skills/html-analysis/SKILL.md` step 1.
- **`init` runs `git init`** at the project root (idempotent — skip if already a
  repo), so the emitted `.gitignore` takes effect immediately.
- **Docs breadth:** README + `docs/system-architecture.md` +
  `docs/codebase-summary.md`.

## Acceptance Criteria

- [ ] `/wp-pro-max:init <name>` creates the parent-wrapper tree + `wp/wp-build.json`.
- [ ] Manifest has `project.name`, `project.themeSlug` (kebab, namespaced as
      textDomain), `strategy`, `progress:{}`, and `source` candidate paths
      (`htmlPaths:["../source"]`, `assetDirs:["../assets"]`,
      `briefPath:"../requirements/brief.md"`). **`source.type` is NOT set** by init.
- [ ] `requirements/brief.md`, `.gitignore`, `README.md` generated; empty input
      dirs kept via `.gitkeep`; project root is a git repo (`git init`).
- [ ] `analyze` stage auto-detects and persists `source.type` when unset.
- [ ] Idempotent: re-running does not overwrite an existing manifest/templates or
      re-init an existing git repo.
- [ ] After init, `/wp-pro-max:build` run from the parent root auto-descends into
      `wp/` and resolves inputs correctly.
- [ ] `claude plugin validate .` passes; README + both docs list `init`.

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Init command](./phase-01-init-command.md) | Done |
| 2 | [Build wiring and docs](./phase-02-build-wiring-and-docs.md) | Done |
| 3 | [Behavioral validation](./phase-03-behavioral-validation.md) | Done |

Sequential: P2 depends on P1 (needs the layout/manifest shape `init` produces);
P3 validates P1+P2 end to end.

## Dependencies

No cross-plan blockers. Touches `commands/build.md` and
`skills/html-analysis/SKILL.md` (both originate from the
`20260626-wp-pro-max-kit` foundation plan, which is the original scaffold and is
not concurrently editing the same sections). Additive — no shared-file write
conflict expected.

## Validation Log

### Session 1 — 2026-06-26 (verification: Standard tier)

**Verification Results**
- Claims checked: 7 | Verified: 7 | Failed: 0 | Unverified: 0 | Tier: Standard
- Evidence: `commands/init.md` absent; `source.type` enum
  `[html-files,url,brief]` (schema); `build.md` Init/resume at line 34;
  `wpbuild_init` no-ops on existing file + honors `WP_BUILD_FILE`
  (`manifest-lib.sh:15,30`); `wpbuild_merge/set` honor `WP_BUILD_FILE`; both
  docs exist; no `wp/` naming collision.

**Decisions confirmed**
1. **`source.type` left unset by init; `analyze` auto-detects.** Adds a contained
   touchpoint to `skills/html-analysis/SKILL.md` step 1 → propagated to Phase 1
   (omit type), Phase 2 (new step + related file + risk), Phase 3 (assert absent
   + detect check).
2. **`init` runs `git init`** at project root (idempotent) → Phase 1 step + success
   criterion; Phase 3 git-repo assertion.
3. **Docs breadth: README + system-architecture + codebase-summary** → unchanged
   from Phase 2 (already in scope).

### Whole-Plan Consistency Sweep — Session 1
- Re-read `plan.md` + all 3 phase files.
- No stale `source.type=="html-files"` claims remain (Phase 1 manifest sample,
  Phase 1 merge call, Phase 3 jq assertion all updated to omit/assert-absent).
- `git init` reflected consistently in plan acceptance, Phase 1, Phase 3.
- `html-analysis` touchpoint present in Phase 2 related-files, steps, success
  criteria; Phase 3 exercises it.
- Result: **zero unresolved contradictions.**
