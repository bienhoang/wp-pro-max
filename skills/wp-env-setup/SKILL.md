---
name: wp-env-setup
description: >-
  Provisions the local WordPress environment with wp-env (stage `env`). Scaffolds
  .wp-env.json (WordPress core, PHP 8.2, port, theme/plugin mappings, debug
  config) from the manifest, starts the Docker WordPress, and sets the permalink
  structure. Use when setting up a local WordPress dev environment, generating
  .wp-env.json, running wp-env start, or mounting the generated theme. Reads
  strategy, plugins, project.themeSlug, theme, env; writes env.* and the
  .wp-env.json file. Calls scripts/wp-env-bootstrap.sh.
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# WP Env Setup (stage `env`)

Stand up a reproducible local WordPress via `@wordpress/env` (Docker), mounting
the generated theme so theme edits are live, and installing selected plugins.

## Inputs (from `wp-build.json`)

| Field | Use |
|-------|-----|
| `project.themeSlug` | Theme folder to mount + activate. |
| `theme.path` | Source theme dir to map into the container. |
| `plugins[]` | wordpress.org slugs → `.wp-env.json` `plugins`. |
| `env.port` | Host port (default 8888). |
| `env.phpVersion` / `env.wpVersion` | Versions (default php 8.2, core latest). |
| `strategy` / `builder` | page-builder ⇒ ensure builder plugin present. |

## Procedure

This stage is mostly a thin wrapper over `scripts/wp-env-bootstrap.sh`, which
does the heavy lifting (generate `.wp-env.json`, `wp-env start`, permalinks,
flush). Prefer calling the script; only edit `.wp-env.json` by hand for cases the
script does not cover.

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh"
wpbuild_is_done env && [[ "${1:-}" != "--force" ]] && { echo "env done"; exit 0; }
wpbuild_progress env in-progress

# Generate .wp-env.json, start Docker WP, set permalinks, flush rewrites.
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wp-env-bootstrap.sh"

PORT="$(wpbuild_get '.env.port // 8888')"
wpbuild_set '.env.localUrl' "\"http://localhost:${PORT}\""
wpbuild_set '.env.phpVersion' "\"$(wpbuild_get '.env.phpVersion // "8.2"')\""
wpbuild_progress env done "wp-env up on :${PORT}"
```

## Generated `.wp-env.json` (shape)

The bootstrap script renders this from the manifest. Reference shape:

```json
{
  "core": null,
  "phpVersion": "8.2",
  "plugins": [ "advanced-custom-fields", "wordpress-seo", "contact-form-7" ],
  "themes": [ "./wp-content/themes/acme" ],
  "port": 8888,
  "config": {
    "WP_DEBUG": true,
    "WP_DEBUG_LOG": true,
    "WP_DEBUG_DISPLAY": false,
    "WP_ENVIRONMENT_TYPE": "local"
  },
  "mappings": {
    "wp-content/themes/acme": "./wp-content/themes/acme"
  }
}
```

Notes:
- `core: null` ⇒ latest stable WordPress. Pin via `env.wpVersion`
  (e.g. `"WordPress/WordPress#6.6"`) when reproducibility matters.
- `themes` installs/links the theme; `mappings` makes edits live (bind mount).
- Plugins are wordpress.org slugs from `plugins[]` (`source=wporg`); premium
  ZIPs go in as a path/URL string instead.

## Post-start tasks

```bash
# Activate the converted theme.
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" theme activate "$(wpbuild_get '.project.themeSlug')"
# Pretty permalinks (needed for CPT archives / SEO).
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" rewrite structure '/%postname%/' --hard
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" rewrite flush --hard
```

## Common controls

```bash
wp-env start          # start / re-provision
wp-env stop           # stop containers
wp-env clean all      # wipe DB (destructive)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" ...  # any WP-CLI command
wp-env logs           # tail container logs
```

## Verify

```bash
curl -s -o /dev/null -w '%{http_code}' "http://localhost:$(wpbuild_get '.env.port // 8888')"   # expect 200/301
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" theme list --status=active
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" plugin list --status=active
```
