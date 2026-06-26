---
name: wp-ship
description: >-
  Ships a WordPress site from the local wp-env build to a production host/VPS
  (stage `ship`). Backs up the target first, pushes the generated theme +
  wp-content, migrates the database, runs local→production URL search-replace via
  scripts/migrate-urls.sh, flushes rewrites/cache, smoke-tests the live site, and
  records a rollback point. Supports three deploy targets: ssh-wpcli (rsync over
  SSH + remote WP-CLI), ai1wm (All-in-One WP Migration .wpress), and rsync
  (files-only, DB handled separately). Gated on qa.passed and a fresh backup;
  never deploys without both. Use when deploying, shipping, migrating, or going
  live with a WordPress site, running search-replace for production, or rolling
  back a WordPress deployment.
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# WP Ship (stage `ship`)

Promote the locally built WordPress site to production. This is the only stage
that writes to a remote host, so it is **safety-first**: it refuses to run
without `qa.passed == true` and a fresh backup, always previews the URL
search-replace with `--dry-run`, smoke-tests after deploy, and records a
`rollbackPoint` so any deploy can be undone.

## Inputs (from `wp-build.json`)

| Field | Use |
|-------|-----|
| `deploy.target` | `ssh-wpcli` \| `ai1wm` \| `rsync` \| `manual`. |
| `deploy.host` | SSH host / connection string (e.g. `deploy@acme.com`). |
| `deploy.path` | Remote WordPress root (e.g. `/var/www/acme`). |
| `urls.local` | Source URL for search-replace (e.g. `http://localhost:8888`). |
| `urls.production` | Target URL for search-replace (e.g. `https://acme.com`). |
| `theme.path` / `theme.files` | The generated theme to push. |
| `seed.contentScript` / `seed.pluginDataScript` | Run remotely instead of a DB import when seeding from scratch. |
| `qa.passed` | **Gate** — must be `true`. |

## Outputs (written back)

`deploy.target`, `deploy.host`, `deploy.path`, `deploy.lastDeploy` (UTC stamp),
and `deploy.rollbackPoint` (path to the remote pre-deploy DB/files backup).

## 0. Resume guard + setup

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh"
wpbuild_is_done ship && [[ "${1:-}" != "--force" ]] && { echo "ship done"; exit 0; }
TARGET="$(wpbuild_get '.deploy.target // "ssh-wpcli"')"
HOST="$(wpbuild_get '.deploy.host // empty')"
RPATH="$(wpbuild_get '.deploy.path // empty')"
```

## 1. Pre-flight gates (MANDATORY — never skip)

1. **QA gate.** `[[ "$(wpbuild_get '.qa.passed')" == "true" ]]` or stop and tell
   the user to run the `qa` stage first. Do not deploy a site that failed QA.
2. **URLs present.** `urls.local` and `urls.production` must be set and differ.
3. **Connectivity.** For `ssh-wpcli`/`rsync`: `ssh "$HOST" 'echo ok'` succeeds and
   the remote WordPress responds: `ssh "$HOST" "wp --path=$RPATH option get siteurl"`.
4. **Confirmation.** Deploying to production is destructive to the remote DB.
   Confirm target host + path with the user before any write step.

Mark in-progress only after the gates pass:
`wpbuild_progress ship in-progress "target=$TARGET host=$HOST"`.

## 2. Backup the target (ALWAYS, before any write)

You may never deploy without a backup. Take it remotely and record the path as
the rollback point **before** pushing anything:

```bash
STAMP="$(date -u +%Y%m%d-%H%M%S)"
RB="${RPATH%/}/wp-build-backups/${STAMP}"
ssh "$HOST" "mkdir -p '$RB' \
  && wp --path='$RPATH' db export '$RB/db.sql' \
  && tar -C '$RPATH' -czf '$RB/wp-content.tgz' wp-content"
wpbuild_set '.deploy.rollbackPoint' "\"$RB\""
```

For `ai1wm`, the rollback point is a full `.wpress` export taken on the target
before the restore. See the per-target runbook.

## 3. Deploy by target

Pick the runbook for `deploy.target` and follow its exact commands:

- **ssh-wpcli** → `references/ssh-wpcli-runbook.md`
  rsync theme + `wp-content` over SSH → import DB (or run seed scripts remotely)
  → `migrate-urls.sh --apply` local→prod → flush rewrites + cache.
- **ai1wm** → `references/ai1wm-runbook.md`
  Export a `.wpress` locally via WP-CLI → transfer → restore on the target
  (URL rewrite handled inside AI1WM).
- **rsync** → `references/rsync-runbook.md`
  Files only (theme + uploads). DB is migrated separately by the operator;
  this skill still runs the search-replace step once the DB is in place.

The local→production URL migration ALWAYS goes through the shared wrapper, which
forces a dry-run preview first:

```bash
# Preview on the REMOTE host (no writes):
WP_CLI_RUN="ssh $HOST wp --path=$RPATH" \
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/migrate-urls.sh"
# Apply after reviewing the change count:
WP_CLI_RUN="ssh $HOST wp --path=$RPATH" \
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/migrate-urls.sh" --apply
```

## 4. Smoke test the live site

After deploy + search-replace + flush, verify before declaring success:

```bash
ssh "$HOST" "wp --path=$RPATH option get siteurl"   # == urls.production
ssh "$HOST" "wp --path=$RPATH core verify-checksums" || true
curl -fsS -o /dev/null -w '%{http_code}\n' "$(wpbuild_get '.urls.production')"
```

Expect HTTP 200 on the home page and 1–2 key inner pages, the production siteurl,
and no leftover `urls.local` references (a second `migrate-urls.sh` dry-run must
report 0 changes). If any check fails, **roll back** (step 6) and report.

## 5. Record outputs

```bash
wpbuild_set '.deploy.target' "\"$TARGET\""
wpbuild_set '.deploy.host'   "\"$HOST\""
wpbuild_set '.deploy.path'   "\"$RPATH\""
wpbuild_set '.deploy.lastDeploy' "\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
wpbuild_progress ship done "deployed to $HOST:$RPATH; rollbackPoint=$(wpbuild_get '.deploy.rollbackPoint')"
```

## 6. Rollback procedure

Every deploy records `deploy.rollbackPoint`. To undo the most recent deploy,
restore that snapshot on the target:

```bash
RB="$(wpbuild_get '.deploy.rollbackPoint')"
ssh "$HOST" "wp --path='$RPATH' db import '$RB/db.sql' \
  && tar -C '$RPATH' -xzf '$RB/wp-content.tgz' \
  && wp --path='$RPATH' cache flush \
  && wp --path='$RPATH' rewrite flush"
```

For `ai1wm`, restore the pre-deploy `.wpress` via the AI1WM restore command (see
its runbook). After any rollback, re-run the smoke test (step 4) and record the
event: `wpbuild_progress ship failed "rolled back to $RB"`.

## Idempotency & safety notes

- Re-running with the site already live is safe: backups are timestamped (never
  overwritten), rsync only transfers diffs, and `migrate-urls.sh` is a no-op when
  0 changes remain.
- Destructive remote ops (`db import`, AI1WM restore, `--apply`) require the
  pre-flight gates + an existing rollback point first.
- Never hardcode the table prefix; remote WP-CLI resolves it via `--path`.

## Delegation

Hand the actual remote execution to the **wp-deployer** agent. Pass it: target
type, `deploy.host`/`deploy.path`, `urls.local`/`urls.production`, the theme
path, the chosen runbook reference, and acceptance criteria (backup taken before
write, dry-run reviewed, smoke test green, rollbackPoint recorded). Never pass
full conversation history.

See: `references/ssh-wpcli-runbook.md`, `references/ai1wm-runbook.md`,
`references/rsync-runbook.md`.
