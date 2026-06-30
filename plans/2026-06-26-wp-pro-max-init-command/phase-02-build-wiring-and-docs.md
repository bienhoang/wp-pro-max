---
phase: 2
title: "Build wiring and docs"
status: done
effort: ""
priority: P2
dependencies: [1]
---

# Phase 2: Build wiring and docs

<!-- Updated: Validation Session 1 - source.type auto-detect added to html-analysis -->

## Overview

Teach `/wp-pro-max:build` to auto-descend into `./wp/` when the manifest is not in
CWD (so users can run build from the parent-wrapper root), teach the `analyze`
stage to auto-detect `source.type` when init left it unset, and update plugin
docs to list the new `init` command + describe the project-layout convention.

## Requirements

- Functional:
  - `build` Init/resume step: if `./wp-build.json` absent but `./wp/wp-build.json`
    present → `cd wp` (or treat `wp/` as the project root) before running stages.
  - `html-analysis` step 1: when `.source.type` is null/empty, detect it —
    HTML found under `source.htmlPaths` ⇒ `html-files`; else non-empty
    `source.briefPath` ⇒ `brief`; persist via `wpbuild_set '.source.type'`.
  - Docs reflect `init` as a first-class command and document the layout.
- Non-functional:
  - Minimal, additive edit to `build.md` (~5 lines); preserve existing
    resume/idempotency behavior and the rest of the Procedure.
  - Keep wording consistent with existing command/doc tone.

## Architecture

Auto-descend rule (insert into `commands/build.md` Procedure step 1
"Init / resume", before deriving/creating the manifest):

> If `wp-build.json` is **not** in the current dir but `./wp/wp-build.json`
> exists, treat `./wp/` as the project root (the `init`-scaffolded parent-wrapper
> layout) — run subsequent stages from there. Otherwise behave as today.

This is a documented instruction for the orchestrator (build.md is a markdown
command, not a script), so the change is prose + a small bash hint, e.g.:

```bash
# Resolve project root for the parent-wrapper layout produced by /wp-pro-max:init
if [ ! -f ./wp-build.json ] && [ -f ./wp/wp-build.json ]; then cd ./wp; fi
```

## Related Code Files

- Modify: `commands/build.md` (Procedure step 1 + a one-line mention in Input)
- Modify: `skills/html-analysis/SKILL.md` (step 1 — detect `source.type` when unset)
- Modify: `README.md` (Components → Commands list `build · status · env · init`;
  add an `init` usage example before the build examples)
- Modify: `docs/codebase-summary.md` (commands inventory: add `init`)
- Modify: `docs/system-architecture.md` (note `init` + the parent-wrapper layout
  convention as the pipeline's input/output contract on disk)

## Implementation Steps

1. Edit `commands/build.md`:
   - In `## Input`, add a line: source defaults to the `init` layout — inputs
     under the parent root, manifest in `wp/`.
   - In `## Procedure` step 1, prepend the auto-descend rule + the bash hint above.
   - Do not alter stage order, gates, or delegation sections.
2. Edit `skills/html-analysis/SKILL.md` step 1 ("Read the source descriptor"):
   after `SRC_TYPE=$(wpbuild_get '.source.type')`, when `SRC_TYPE` is
   `null`/empty, detect and persist:
   ```bash
   if [ -z "$SRC_TYPE" ] || [ "$SRC_TYPE" = "null" ]; then
     if ls $(wpbuild_get '.source.htmlPaths[]' 2>/dev/null)/**/*.html >/dev/null 2>&1 \
        || find $(wpbuild_get '.source.htmlPaths[]' 2>/dev/null) -name '*.html' 2>/dev/null | grep -q .; then
       SRC_TYPE=html-files
     elif [ -s "$(wpbuild_get '.source.briefPath')" ]; then
       SRC_TYPE=brief
     fi
     [ -n "$SRC_TYPE" ] && wpbuild_set '.source.type' "\"$SRC_TYPE\""
   fi
   ```
   Keep the edit minimal and consistent with the skill's existing bash style;
   `url` stays user/init-set only (not auto-detected).
3. Edit `README.md`:
   - `## Components` → `**Commands** — build (orchestrator), status, env, init.`
   - `## Usage` → add:
     ```bash
     # Scaffold a new project skeleton, then build
     /wp-pro-max:init acme-studio
     cd acme-studio && /wp-pro-max:build
     ```
5. Edit `docs/codebase-summary.md`: add `commands/init.md` to the commands
   inventory with a one-line purpose.
6. Edit `docs/system-architecture.md`: add a short "Project layout (init)"
   subsection describing the parent-wrapper tree and which stage reads each input
   folder; reference the brainstorm mapping table.
7. Read each file before editing (Read-before-Write); make surgical edits, do not
   rewrite whole files.

## Success Criteria

- [ ] `build.md` documents auto-descend into `./wp/`; rest of procedure intact.
- [ ] `html-analysis` step 1 detects+persists `source.type` when unset; existing
      `html-files`/`url`/`brief` branches unchanged.
- [ ] `README.md` lists `init` in Commands + shows the init→build example.
- [ ] `docs/codebase-summary.md` and `docs/system-architecture.md` mention `init`
      and the layout convention.
- [ ] `claude plugin validate .` still passes (Phase 3).

## Risk Assessment

- **Behavioral drift in build** — the `cd ./wp` hint could surprise users already
  running build from a flat (non-init) project. Mitigation: guard is conditional
  (only when `./wp-build.json` absent AND `./wp/wp-build.json` present); flat
  projects are unaffected.
- **Auto-detect false negative** — both `source/` empty AND `brief.md` empty ⇒
  `source.type` stays unset and analyze can't proceed. Mitigation: analyze should
  emit a clear "no source found — add HTML to source/ or fill requirements/brief.md"
  message rather than failing silently.
- **Doc/command divergence** — keep the layout description in one authoritative
  place (system-architecture) and link from README to avoid drift.
