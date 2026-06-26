---
name: wp-plugin-dev
description: >-
  Build a standalone WordPress plugin from scratch. Use when the user wants to
  scaffold a brand-new plugin (`new <slug>`), add a feature (`add cpt|taxonomy|
  settings|rest|shortcode|block`), or run its dev loop (`lint`, `test`,
  `package`). Reads and writes `wp-plugin.json` in the target plugin root. Not
  for theme builds — it no-ops inside a `wp-build.json` project unless
  `wp-plugin.json` is also present.
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# WP Plugin Dev

Standalone, opt-in WordPress plugin builder for WP Pro Max. It lives next to
(but separate from) the HTML→site pipeline and is driven by `wp-plugin.json`.

## Opt-in guard

This skill auto-invokes on plugin-building intent, so it must **not** collide
with a theme build:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/plugin-manifest-lib.sh"
if [ -f "./wp-build.json" ] && [ ! -f "./wp-plugin.json" ]; then
	echo "wp-plugin-dev: this directory is a WP Pro Max theme build (wp-build.json present, wp-plugin.json absent)."
	echo "Use /wp-pro-max:build for theme work, or run /wp-pro-max:plugin new <slug> from an empty directory."
	exit 0
fi
```

## Subcommands

| Subcommand | Owned by | What happens |
|------------|----------|--------------|
| `new <slug> [namespace] [name]` | this skill | Creates `./<slug>/wp-plugin.json`, then scaffolds the OOP plugin skeleton via `plugin-scaffold.sh`. |
| `add <feature>` | `wp-plugin-developer` agent (Task) | Adds a secure feature class using the canonical reference body and registers it at the `Plugin.php` marker. |
| `lint` | `wp-plugin-developer` agent (Task) | Runs PHPCS inside the plugin-local wp-env. |
| `test` | `wp-plugin-developer` agent (Task) | Starts the plugin-local wp-env and runs the PHPUnit smoke test. |
| `package` | `wp-plugin-developer` agent (Task) | Builds a distributable `.zip` from the allowlist. |

## Procedure (`new`)

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/plugin-manifest-lib.sh"
wpplugin_is_done scaffold new && [[ "${1:-}" != "--force" ]] && { echo "Plugin already scaffolded"; exit 0; }
wpplugin_progress scaffold in-progress
bash "${CLAUDE_PLUGIN_ROOT}/scripts/plugin-scaffold.sh" new
wpplugin_progress scaffold done
```

## Procedure (`add` — agent prompt)

When invoked by `/wp-pro-max:plugin add <feature>`:

1. Locate `wp-plugin.json` in the current directory. If absent, fail loudly.
2. Read `skills/wp-plugin-dev/references/feature-generators.md` (and
   `block-build.md` for `add block`).
3. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/plugin-scaffold.sh" add <feature>`
   to perform the deterministic file creation and marker insert atomically.
4. Verify the feature class exists, the registrar marker in `src/Plugin.php`
   still exists, and `wp-plugin.json` `features[]` recorded the addition.
5. If wp-env is available, activate the plugin and confirm zero PHP notices.

## Procedure (`lint|test|package` — agent prompt)

1. Confirm `wp-plugin.json` is in CWD.
2. For `lint`: run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/plugin-env-bootstrap.sh"`
   if `.wp-env.json` is missing, then run PHPCS inside wp-env.
3. For `test`: ensure the plugin-local wp-env is running, then run the PHPUnit
   smoke test via `wp-env run tests-cli phpunit`.
4. For `package`: run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/plugin-package.sh"`.
5. Report the result and any failures.

## References

- `references/wp-plugin-manifest.md` — manifest field contract and examples.
- `references/plugin-architecture.md` — file layout, bootstrap, autoloader,
  registrar marker.
- `references/feature-generators.md` — canonical secure bodies for CPT,
  taxonomy, settings, REST, and shortcode.
- `references/block-build.md` — Gutenberg block, `@wordpress/scripts`, and
  packaging notes.
- `references/tooling.md` — Composer, PHPCS, PHPUnit, readme.txt, and the
  `.zip` packaging contract.
