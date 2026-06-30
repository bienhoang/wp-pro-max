---
phase: 1
title: "Init command"
status: done
effort: ""
priority: P1
dependencies: []
---

# Phase 1: Init command

<!-- Updated: Validation Session 1 - source.type omitted (analyze detects); git init added -->

## Overview

Create `commands/init.md` — `/wp-pro-max:init <project-name>` — that scaffolds the
parent-wrapper project tree, writes a starter `wp/wp-build.json` wired to the
input folders, and emits 3 template files. Command-only; reuses
`scripts/manifest-lib.sh`. No Docker, no schema change.

## Requirements

- Functional:
  - Create the parent-wrapper tree (inputs at root, WordPress project in `wp/`).
  - Write `wp/wp-build.json` via `wpbuild_init` + wire `source.*` (paths relative
    to `wp/`) via `wpbuild_merge`.
  - Generate `requirements/brief.md`, `.gitignore`, `README.md`; `.gitkeep` in
    empty input dirs.
  - `git init` the project root (idempotent) so `.gitignore` takes effect.
  - Derive `project.name` (arg, else CWD basename), `themeSlug` (kebab-case,
    used as `textDomain` too), `strategy` (`--strategy`, default `classic-acf`).
  - **Do not set `source.type`** — leave it for `analyze` to auto-detect; only
    write the candidate `source` paths.
- Non-functional:
  - **Idempotent**: re-run never overwrites existing manifest/templates;
    `mkdir -p` for dirs; `[ -f ] ` guards before writing each template.
  - **zsh-safe**: command bash blocks source `manifest-lib.sh` (already
    sourcing-safe); do not set `-euo pipefail` around the sourced helper.
  - Skip wp-env / Docker entirely.

## Architecture

Final tree produced (`<name>` = project root, created under CWD):

```
<name>/
  requirements/  brief.md
  source/        .gitkeep
  assets/        .gitkeep
  design/        .gitkeep
  mockups/       .gitkeep
  wp/            wp-build.json     # WP project root (build CWD + wp-env CWD)
  .gitignore
  README.md
```

Manifest wiring (paths relative to `wp/`, where `build` runs):

```jsonc
// wp/wp-build.json (after init) — note: NO source.type (analyze detects it)
{
  "version": "1",
  "project": { "name": "<name>", "themeSlug": "<slug>", "textDomain": "<slug>" },
  "strategy": "classic-acf",
  "progress": {},
  "source": {
    "htmlPaths": ["../source"],
    "assetDirs": ["../assets"],
    "briefPath": "../requirements/brief.md"
  }
}
```

Helper contracts (verified in `scripts/manifest-lib.sh`):
- `wpbuild_init <name> <slug> [strategy]` — no-op if `$WP_BUILD_FILE` exists;
  writes `version/project/strategy/progress`. Honors `WP_BUILD_FILE`.
- `wpbuild_merge '<json-object>'` — deep-merge into manifest root (one call sets
  the whole `source` object). Honors `WP_BUILD_FILE`.
- Target the right file by exporting `WP_BUILD_FILE="$ROOT/wp/wp-build.json"`
  before calling helpers (avoids a `cd`).

## Related Code Files

- Create: `commands/init.md`
- Reuse (no change): `scripts/manifest-lib.sh` (`wpbuild_init`, `wpbuild_merge`)
- Reference for frontmatter/style: `commands/build.md`, `commands/env.md`

## Implementation Steps

1. Author `commands/init.md` frontmatter:
   ```yaml
   ---
   description: Scaffold a target WordPress project directory (inputs + wp/ + starter wp-build.json) for the WP Pro Max pipeline.
   argument-hint: <project-name> [--slug <theme-slug>] [--strategy classic-acf|block-fse|page-builder]
   allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
   ---
   ```
2. Document the scaffold procedure as a runnable bash block the command executes:
   ```bash
   set -e
   NAME="${1:?project name}"; shift || true
   SLUG=""; STRATEGY="classic-acf"
   # parse --slug / --strategy from "$@" ...
   ROOT="./${NAME}"
   # slug: kebab-case from NAME if --slug absent
   [ -n "$SLUG" ] || SLUG="$(printf '%s' "$NAME" | tr '[:upper:] ' '[:lower:]-' \
       | tr -cd 'a-z0-9-' | sed -E 's/-+/-/g; s/^-|-$//g')"

   mkdir -p "$ROOT"/{requirements,source,assets,design,mockups,wp}
   for d in source assets design mockups; do : > "$ROOT/$d/.gitkeep"; done

   # --- manifest in wp/ (idempotent) ---
   source "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh"
   export WP_BUILD_FILE="$ROOT/wp/wp-build.json"
   wpbuild_init "$NAME" "$SLUG" "$STRATEGY"
   # source.type intentionally omitted — analyze stage detects it.
   wpbuild_merge '{"source":{"htmlPaths":["../source"],"assetDirs":["../assets"],"briefPath":"../requirements/brief.md"}}'

   # --- git init (idempotent) ---
   [ -d "$ROOT/.git" ] || git -C "$ROOT" init -q

   # --- templates (only if absent) ---
   [ -f "$ROOT/requirements/brief.md" ] || cat > "$ROOT/requirements/brief.md" <<'EOF'
   <brief template — see step 3>
   EOF
   [ -f "$ROOT/.gitignore" ] || cat > "$ROOT/.gitignore" <<'EOF'
   <gitignore — see step 4>
   EOF
   [ -f "$ROOT/README.md" ] || cat > "$ROOT/README.md" <<'EOF'
   <readme — see step 5>
   EOF

   echo "Initialized $ROOT — next: cd \"$ROOT/wp\" && /wp-pro-max:build (or run build from $ROOT, it auto-descends)"
   ```
   Note: `.gitkeep` is harmless if the dir is later populated. Use `: >` (truncate)
   only on `.gitkeep`, never on templates.
3. `requirements/brief.md` template — headings feeding analyze/model:
   `# <Project> brief` · `## Goal` · `## Pages` (list w/ role) · `## Content &
   data` (CPTs/fields hints) · `## Brand & design` (colors/fonts/refs in
   `design/`) · `## Plugins / integrations` · `## Locales` (vi/en/ja) ·
   `## Out of scope`.
4. `.gitignore` template: `node_modules/`, `wp/.wp-env/`, `wp/wp-cli.local.yml`,
   `*.log`, `.DS_Store`. (Do NOT ignore `wp/wp-build.json` or the generated
   theme — they are project artifacts.)
5. `README.md` template: one-line per folder (which stage consumes it, per the
   brainstorm mapping table) + the next command (`cd wp && /wp-pro-max:build`).
6. Keep the command body lean and imperative; push any long prose into the
   generated `README.md`, not the command file.

## Success Criteria

- [ ] `commands/init.md` exists with valid frontmatter (description mentions
      WordPress + scaffold + wp-build.json).
- [ ] Running it creates the full tree incl. `wp/wp-build.json` and `.gitkeep`s.
- [ ] `jq` shows `project.name/themeSlug/textDomain`, `strategy`, and the
      `source` candidate paths (`../`-relative) — and `source.type` is ABSENT.
- [ ] Project root is a git repo (`.git/` present); re-run does not re-init.
- [ ] `requirements/brief.md`, `.gitignore`, `README.md` present with real content.
- [ ] Re-run leaves existing manifest + templates byte-identical (idempotent).
- [ ] `bash -n` clean on the extracted scaffold script (validated in Phase 3).

## Risk Assessment

- **Relative-path correctness** — `../source` only resolves when build runs from
  `wp/`. Mitigation: Phase 2 auto-descend + README instruction; Phase 3 asserts.
- **Slug edge cases** (unicode/spaces in NAME) — mitigation: kebab filter chain
  above strips to `[a-z0-9-]`; Phase 3 tests a spaced/mixed-case name.
- **Accidental overwrite on re-run** — mitigation: `wpbuild_init` no-ops on
  existing file; templates guarded by `[ -f ]`.
