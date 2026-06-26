# Runbook — `ssh-wpcli` deploy target

rsync theme + `wp-content` over SSH, migrate the DB with remote WP-CLI, then run
local→production URL search-replace. Assumes SSH access and WP-CLI on the host.

Variables (from manifest): `HOST=deploy.host`, `RPATH=deploy.path`,
`LOCAL=urls.local`, `PROD=urls.production`, `THEME=theme.path`.

## 1. Pre-flight

```bash
ssh "$HOST" 'echo ok'                                  # connectivity
ssh "$HOST" "wp --path=$RPATH option get siteurl"      # remote WP responds
[[ "$(wpbuild_get '.qa.passed')" == "true" ]] || { echo "QA gate failed"; exit 1; }
```

## 2. Remote backup (rollback point) — ALWAYS first

```bash
STAMP="$(date -u +%Y%m%d-%H%M%S)"; RB="${RPATH%/}/wp-build-backups/$STAMP"
ssh "$HOST" "mkdir -p '$RB' \
  && wp --path='$RPATH' db export '$RB/db.sql' \
  && tar -C '$RPATH' -czf '$RB/wp-content.tgz' wp-content"
wpbuild_set '.deploy.rollbackPoint' "\"$RB\""
```

## 3. Push files

```bash
# Theme: safe to mirror (delete removed files)
rsync -az --delete "$THEME/" "$HOST:$RPATH/wp-content/themes/$(basename "$THEME")/"
# Uploads: NEVER --delete (would destroy media)
rsync -az ./wp-content/uploads/ "$HOST:$RPATH/wp-content/uploads/" 2>/dev/null || true
# Plugins pinned in the build (if shipping local copies)
rsync -az ./wp-content/plugins/ "$HOST:$RPATH/wp-content/plugins/" 2>/dev/null || true
```

## 4. Database

Two strategies — pick one:

**A. Export local DB and import remotely (full content migration):**
```bash
wp-env run cli wp db export - > /tmp/local.sql
scp /tmp/local.sql "$HOST:/tmp/local.sql"
ssh "$HOST" "wp --path='$RPATH' db import /tmp/local.sql && rm /tmp/local.sql"
```

**B. Seed from scratch on the remote (no local DB):** run the generated
`seed-content.sh` / plugin-data script remotely with `WP_CLI_RUN="ssh $HOST wp --path=$RPATH"`.

## 5. URL search-replace (dry-run → apply)

```bash
WP_CLI_RUN="ssh $HOST wp --path=$RPATH" bash "${CLAUDE_PLUGIN_ROOT}/scripts/migrate-urls.sh"          # preview
WP_CLI_RUN="ssh $HOST wp --path=$RPATH" bash "${CLAUDE_PLUGIN_ROOT}/scripts/migrate-urls.sh" --apply  # apply
ssh "$HOST" "wp --path='$RPATH' rewrite flush && wp --path='$RPATH' cache flush"
```

## 6. Smoke test

```bash
ssh "$HOST" "wp --path='$RPATH' option get siteurl"     # == $PROD
curl -fsS -o /dev/null -w '%{http_code}\n' "$PROD"      # 200
WP_CLI_RUN="ssh $HOST wp --path=$RPATH" bash "${CLAUDE_PLUGIN_ROOT}/scripts/migrate-urls.sh"  # 0 changes
```

## Rollback

```bash
RB="$(wpbuild_get '.deploy.rollbackPoint')"
ssh "$HOST" "wp --path='$RPATH' db import '$RB/db.sql' \
  && tar -C '$RPATH' -xzf '$RB/wp-content.tgz' \
  && wp --path='$RPATH' cache flush && wp --path='$RPATH' rewrite flush"
```
