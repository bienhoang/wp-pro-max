---
description: Provision or manage the local wp-env WordPress environment for the current build.
argument-hint: "[start|stop|clean|destroy|cli <wp-args>]"
allowed-tools: [Read, Bash, Glob]
---

# /wp-pro-max:env

Provision and control the local Docker WordPress (wp-env) used by every build and
seed stage.

## Subcommands ($1)

- *(none)* / `start` — Generate `.wp-env.json` from `wp-build.json` and start:
  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/wp-env-bootstrap.sh"
  ```
  This pins core/PHP/plugins/theme mapping from the manifest, runs `wp-env start`,
  sets permalinks, and flushes rewrites (idempotent).
- `stop` — `wp-env stop`.
- `clean` — `wp-env clean all` (reset DB, keep config).
- `destroy` — `wp-env destroy` (remove containers + volumes).
- `cli <wp-args>` — passthrough WP-CLI, e.g. `/wp-pro-max:env cli plugin list`
  → `wp-env run cli wp plugin list`.

## Prerequisites

Docker running, Node ≥ 20, `@wordpress/env` (`npx wp-env`). If `.wp-env.json` is
missing and there is no manifest yet, tell the user to run
`/wp-pro-max:build <source>` first.

## Output

The wp-env URL (default `http://localhost:8888`) + admin (`/wp-admin`,
user `admin` / pass `password` on default wp-env), and current container status.
