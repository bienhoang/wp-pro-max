---
description: Build a standalone WordPress plugin from scratch — scaffold, add features, lint, test, and package.
argument-hint: "[new <slug> [namespace] [name]|add <feature>|lint|test|package]"
allowed-tools: [Read, Bash, Glob, Task, Skill]
---

# /wp-pro-max:plugin

Standalone plugin builder. Completely separate from the HTML→site pipeline; it
reads/writes `wp-plugin.json` in the plugin project root.

## Subcommands

- `new <slug> [namespace] [name]` — scaffold a new plugin into `./<slug>/`.
- `add <feature>` — add a secure feature generator to the plugin in CWD.
- `lint` — run PHPCS (WPCS) inside the plugin-local wp-env.
- `test` — run the PHPUnit smoke test inside the plugin-local wp-env.
- `package` — build a distributable `.zip` from the allowlist.

## `new <slug> [namespace] [name]`

Scaffolds into `./<slug>/` in the current working directory.

```bash
set -e
SLUG="${1:?slug required}"
NAMESPACE="${2:-}"
NAME="${3:-}"
ROOT="./${SLUG}"

mkdir -p "$ROOT"
export WP_PLUGIN_FILE="$ROOT/wp-plugin.json"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/plugin-manifest-lib.sh" init "$SLUG" "$NAMESPACE" "$NAME"
```

Then invoke the `wp-plugin-dev` skill to stamp the OOP skeleton:

```bash
Skill(name="wp-plugin-dev", arguments="new")
```

## `add <feature>`

Valid features: `cpt`, `taxonomy`, `settings`, `rest`, `shortcode`, `block`.

Fail loudly if `wp-plugin.json` is not in CWD. Then delegate to the
`wp-plugin-developer` agent:

```bash
Task(
  subagent_type="coder",
  description="Add plugin feature",
  prompt="You are the wp-plugin-developer agent for WP Pro Max. Work in the plugin root: $(pwd). The feature to add is: ${1}. Read the relevant reference in ${CLAUDE_PLUGIN_ROOT}/skills/wp-plugin-dev/references/ (feature-generators.md or block-build.md). Run bash ${CLAUDE_PLUGIN_ROOT}/scripts/plugin-scaffold.sh add ${1} atomically. Verify the class file exists, the registrar marker in src/Plugin.php is still present, and wp-plugin.json features[] recorded the addition. If wp-env is running, activate the plugin and confirm zero PHP notices. Report files created/modified and status."
)
```

## `lint`

```bash
Task(
  subagent_type="coder",
  description="Plugin PHPCS lint",
  prompt="You are the wp-plugin-developer agent. Plugin root: $(pwd). Ensure wp-plugin.json exists. If .wp-env.json is missing, run bash ${CLAUDE_PLUGIN_ROOT}/scripts/plugin-env-bootstrap.sh. Then run PHPCS inside wp-env for this plugin (e.g. wp-env run cli vendor/bin/phpcs or composer lint). Report pass/fail and any fixable issues."
)
```

## `test`

```bash
Task(
  subagent_type="coder",
  description="Plugin PHPUnit test",
  prompt="You are the wp-plugin-developer agent. Plugin root: $(pwd). Ensure the plugin-local wp-env is running (run ${CLAUDE_PLUGIN_ROOT}/scripts/plugin-env-bootstrap.sh if needed). Install dev dependencies if absent (wp-env run cli composer install). Run the PHPUnit smoke test via wp-env run tests-cli phpunit. Report pass/fail and exact output."
)
```

## `package`

```bash
Task(
  subagent_type="coder",
  description="Plugin package zip",
  prompt="You are the wp-plugin-developer agent. Plugin root: $(pwd). Run bash ${CLAUDE_PLUGIN_ROOT}/scripts/plugin-package.sh. Verify the output .zip exists in dist/, contains only allowlisted files, and (if a block exists) includes blocks/<name>/build/block.json. Report the zip path and size."
)
```

## Output

A concise summary: plugin root, subcommand executed, files created/modified, and
the next recommended command.
