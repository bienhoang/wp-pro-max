# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

`wp-pro-max` is **not an application** — it is a Claude Code **plugin** (a kit of
Skills + Agents + Commands + shared scripts). It ships a manifest-driven pipeline
that converts static HTML (or a requirements brief) into a production WordPress
site. The pipeline runs *against a separate target WordPress project*, not against
this repo. Most files here are markdown (skill/agent/command definitions) plus a
few shell/node helper scripts.

Read `README.md`, `references/manifest-contract.md`, and
`docs/system-architecture.md` before authoring or editing any stage.

## Validate / check (there is no build or test runner)

```bash
claude plugin validate .          # validate plugin + marketplace manifests (the gate)
bash -n scripts/<file>.sh         # syntax-check a shell script
node --check scripts/<file>.mjs   # syntax-check a node script
```

Scripts are exercised behaviorally with a mocked WP-CLI (set `WP_CLI_RUN="echo"`
or a stub) rather than a test suite. The build environment has Docker, Node, and
Composer available — verify script behavior here directly rather than deferring.

## Architecture (the big picture)

The whole system is **manifest-driven**. A single file `wp-build.json` (written to
the *target* WordPress project root, never to this repo) is the source of truth.
Every stage: (1) reads its inputs from the manifest, (2) does work, (3) writes its
outputs back, (4) records progress. This is what makes runs **resumable** and
**idempotent** — re-running skips any stage already marked `done`.

- **Schema:** `schemas/wp-build.schema.json` defines the manifest shape
  (`source`, `strategy`, `analysis`, `contentModel`, `designTokens`, `plugins`,
  `theme`, `seed`, `urls`, `deploy`, `progress`).
- **Stage contract:** `references/manifest-contract.md` — the authoritative rules
  every stage must obey. Canonical stage ids: `analyze · optimize · model ·
  tokens · convert · plugins · scaffold · seed-content · seed-plugin-data · qa ·
  seo · security · i18n · ship · env · handoff`.

### Component layers

- **Commands** (`commands/*.md`) — user entry points. `build` is the orchestrator
  (runs stages in order, honors `--from/--to/--auto`, gates ship on QA); `status`
  prints manifest progress; `env` manages wp-env. The orchestrator coordinates and
  delegates — it does not do heavy work itself.
- **Skills** (`skills/<name>/`) — one per pipeline stage, auto-invoked by name
  (`wp-pro-max:<name>`). Each owns exactly one stage id. A skill routes work,
  updates the manifest, and delegates heavy authoring to an agent. Layout:
  `SKILL.md` (≤ ~200 lines, imperative) + `references/*.md` (deep detail loaded on
  demand) + optional `templates/`.
- **Agents** (`agents/*.md`) — heavy lifters spawned by skills:
  `wp-theme-developer` (theme PHP / theme.json / patterns), `wp-data-engineer`
  (WP-CLI seeding + safe DB ops), `wp-deployer` (backup/migrate/ship). Pass an
  agent: target paths, manifest path, files it may modify, acceptance criteria,
  constraints — **never** full conversation history.
- **Scripts** (`scripts/`, called via `${CLAUDE_PLUGIN_ROOT}/scripts/`) — shared
  helpers: `manifest-lib.sh` (manifest read/write/progress), `seed-helpers.sh`
  (idempotent create-if-missing WP-CLI helpers), `wp-env-bootstrap.sh`,
  `extract-tokens.mjs`, `visual-diff.mjs`, `migrate-urls.sh`.

### Adaptive theme conversion

`theme-conversion` analyzes once, then routes to one of three backends by
`strategy`, each with its own reference file under the skill:
`classic-acf` (PHP + ACF), `block-fse` (theme.json + block templates), or
`page-builder` (Elementor/Bricks, data as `_elementor_data` postmeta).

## Conventions you must follow

- **wp-env / WP-CLI only.** All WordPress CLI goes through
  `wp-env run cli wp <command>` (CWD = target project with `.wp-env.json`). Never
  hardcode container paths; theme/plugins are mounted via `.wp-env.json` mappings.
- **Idempotency.** Seeding checks existence before create and records stable keys
  in `seed.idempotencyKeys`. Prefer WP-CLI over raw SQL; destructive `wp db query`
  requires a `--dry-run` preview first.
- **Sourced scripts must be zsh-safe.** The runtime Bash tool is zsh. Sourced
  helpers must NOT enable `set -euo pipefail` at top level (it alters the caller's
  shell), must avoid zsh-reserved names like `status`, and must detect
  sourcing-vs-execution without relying on `BASH_SOURCE` alone. See the
  source/execute guards in `manifest-lib.sh` and `seed-helpers.sh` — match them.
- **Skill `description` frontmatter** drives auto-invocation: write it in third
  person, mention "WordPress", the stage verb, and the manifest fields it
  reads/writes. Keep `SKILL.md` lean and push real detail into `references/`.
- **Namespace** PHP function names and the i18n text domain with the theme slug.

## Notes

- `docs/` and `plans/` are git-ignored (see `.gitignore`) — they are working docs,
  not shipped plugin content.
- Do not write `wp-build.json` or any WordPress output into this repo; those belong
  in the target project the pipeline operates on.
