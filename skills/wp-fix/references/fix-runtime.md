# Runtime ops

WP-CLI operations `wp-fix` may run, and the guard each one carries.

Every call goes through `wpx` — pass the **subcommand only** (`wpx` prepends `wp`
itself):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" option get siteurl
```

Propose-only applies here exactly as it does to file edits: **show what you are
about to run and why, get approval, then run it.** A runtime op has no diff to
show, so state the current value and the intended value instead.

## Policy table

| Op | Guard |
|---|---|
| `option get`, `db query` (SELECT), `plugin list`, `theme list`, `post list` | Read-only. Run freely. |
| `option update`, `option delete` | Propose → approve → run. Record the option **name** in `fix.runtimeChanges[]`. |
| `rewrite flush`, `cache flush`, `transient delete` | Propose → approve → run. Idempotent and cheap; still announce it. |
| `menu location assign` | Propose → approve → run. |
| `plugin activate`, `plugin deactivate` | `AskUserQuestion` first. Record the original state; restore on failure or interrupt. |
| `db query` (non-SELECT) | **SELECT preview → `db export` → confirm row set → write.** See below. |
| `user update`, `role update` | `AskUserQuestion` first. Permission changes are not remediation collateral. |

## Secrets — names only, never values

`fix.runtimeChanges[]` records the option **name**:

```bash
fix_record runtimeChanges '{"cmd":"option update","option":"permalink_structure"}'
```

Never the value. Option values hold SMTP passwords, API tokens, and license keys,
and `wp-build.json` is committed. `skills/wp-security/references/secrets-scan.sh:8`
never prints a matched secret value — recording one here would invert the repo's
own rule. The schema has no `before`/`after` field for this reason; do not add one.

If the user must see a value to decide, show it **in the conversation** and still
record only the name.

## DB writes

`wp db query` has **no `--dry-run` flag.** That flag is `search-replace`-only
(`scripts/migrate-urls.sh:140`). Anyone who "remembers" `wp db query --dry-run`
is remembering a command that does not exist — it will not error helpfully, it
will pass `--dry-run` to MySQL as part of the statement.

The guard is a **matching `SELECT` preview**, per `agents/wp-data-engineer.md:56-59`:

> a guarded `wp db query` runs its matching `SELECT` preview first and you confirm
> the row set before the `INSERT`/`UPDATE`; take a `wp db export` backup before
> multi-row mutations and always use `$(wp db prefix)`

Order, every time:

```bash
# 1. Preview the EXACT rows the write will touch — same WHERE clause.
PREFIX="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" db prefix)"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" db query \
  "SELECT option_id, option_name FROM ${PREFIX}options WHERE option_name = 'broken_option'"

# 2. Back up before any multi-row mutation.
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" db export "$FIX_BACKUP_DIR/pre-fix.sql"

# 3. Show the row set, get approval, THEN write.
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" db query \
  "UPDATE ${PREFIX}options SET option_value = '...' WHERE option_name = 'broken_option'"
```

Rules:
- The preview's `WHERE` must be **identical** to the write's. A preview of a
  different row set proves nothing.
- Never hardcode `wp_` — always `db prefix`.
- Prefer the WP API (`option update`, `post meta update`) over raw SQL. Raw SQL is
  a documented last resort (`references/manifest-contract.md:76-78`), not a shortcut.
- A `SELECT` returning 0 rows means the diagnosis is wrong. Stop and re-triage —
  do not run the write "just in case".

## Plugin bisect

For a suspected plugin conflict. Destructive to a live site: deactivating a
plugin on a site someone is using is visible immediately.

```bash
# 1. Record the original state FIRST — this is the restore point.
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" plugin list --status=active --field=name > "$FIX_BACKUP_DIR/active-plugins.txt"
```

Then, only after `AskUserQuestion` approval:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" plugin deactivate <slug>
# …reproduce the symptom…
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" plugin activate <slug>
```

Restore every plugin in `active-plugins.txt` when the bisect ends — including on
failure or interrupt. A half-finished bisect leaves the site in a state the user
did not ask for and may not notice until later.

Record each toggle: `fix_record runtimeChanges '{"cmd":"plugin deactivate","option":"<slug>"}'`.

## When wp-env is unreachable

`audit_wp_env_reachable` (sourced via `wp-fix-lib.sh`) returns non-zero. Every op
on this page is then unavailable — say so rather than reporting a runtime fix that
never ran. Static file fixes and `php -l` still work; a white screen may be
*why* wp-env is unreachable (see `fix-php-fatal.md`).
