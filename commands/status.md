---
description: Show the WP Pro Max build manifest and per-stage progress for the current project.
argument-hint: "[--json]"
allowed-tools: [Read, Bash]
---

# /wp-pro-max:status

Report the state of the current WordPress build from `wp-build.json`.

## Procedure

1. Locate `wp-build.json` in the current project. If absent, tell the user to run
   `/wp-pro-max:build <source>` first.
2. Print the human summary:
   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh"
   wpbuild_status
   ```
3. Summarize key facts: project name, theme strategy/builder, selected plugins,
   locales (`i18n.locales`), QA pass/fail, deploy target + last deploy + rollback
   point, and the next non-`done` stage to run.
4. With `--json`, print the raw manifest (`cat wp-build.json | jq .`).

## Output

A compact status block + the recommended next command
(e.g. `/wp-pro-max:build --from qa`).
