# Stage Contract & Skill Authoring Conventions

All WP Pro Max stages obey this contract so the pipeline stays composable,
resumable, and idempotent. Read this before authoring any stage skill.

## The manifest

- Single source of truth: `wp-build.json` in the **target WordPress project** root.
- Schema: `schemas/wp-build.schema.json`. Helpers: `scripts/manifest-lib.sh`.
- Every stage: (1) reads inputs from the manifest, (2) does work, (3) writes its
  outputs back, (4) records progress via `wpbuild_progress <stage-id> <status>`.
- Stages must be **resumable**: if `wpbuild_is_done <stage-id>`, skip unless `--force`.

## Stage ids (canonical)

`analyze` · `optimize` · `model` · `tokens` · `convert` · `plugins` ·
`scaffold` · `seed-content` · `seed-plugin-data` · `qa` · `seo` · `security` ·
`i18n` · `ship` · `env` · `handoff`

## Skill layout (each skill folder)

```
skills/<skill-name>/
  SKILL.md            # frontmatter + instructions (≤ ~200 lines; link refs)
  references/*.md     # deep detail loaded on demand
  templates/*         # code templates the skill emits (optional)
```

## SKILL.md frontmatter

```yaml
---
name: <skill-name>            # becomes wp-pro-max:<skill-name>
description: <when to invoke — third person, includes trigger words>
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]   # restrict sensibly
---
```

Write `description` so the model auto-invokes correctly (mention "WordPress",
the stage verb, and inputs/outputs). Keep instructions imperative and concrete.

## wp-env / WP-CLI invocation

- All WordPress CLI runs go through wp-env:
  `wp-env run cli wp <command>` (CWD = target project with `.wp-env.json`).
- Mount the generated theme via `.wp-env.json` `mappings` so edits are live.
- Never hardcode container paths; rely on wp-env defaults.

## Idempotency rules

- Content/data seeding must **check before create** (see `scripts/seed-helpers.sh`).
- Use stable idempotency keys (post slugs, option names, menu names) recorded in
  `seed.idempotencyKeys`.
- DB writes prefer WP-CLI commands. Raw `wp db query` only with explicit guards;
  destructive ops require `--dry-run` preview first.

## Delegation

- Heavy code authoring → `wp-theme-developer` agent.
- Seeding / DB work → `wp-data-engineer` agent.
- Deploy / migration → `wp-deployer` agent.
- Pass the agent: target paths, the manifest path, files it may modify,
  acceptance criteria, constraints. Never pass full conversation history.

## Scripts (shared, via `${CLAUDE_PLUGIN_ROOT}/scripts/`)

- `manifest-lib.sh` — manifest read/write/progress (Phase 01).
- `seed-helpers.sh` — idempotent WP-CLI create-if-missing (Phase 04).
- `wp-env-bootstrap.sh` — scaffold + start wp-env (Phase 03).
- `extract-tokens.mjs` — HTML/CSS → design tokens (Phase 02).
- `visual-diff.mjs` — Playwright pixel diff WP vs source (Phase 05).
- `migrate-urls.sh` — `wp search-replace` wrapper for ship (Phase 06).
