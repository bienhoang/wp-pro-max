# Runbook — `ai1wm` deploy target (All-in-One WP Migration)

Package the whole local site into a `.wpress` archive and restore it on the
target. AI1WM rewrites URLs during restore, so explicit search-replace is usually
unnecessary — but verify afterward.

Requires the `all-in-one-wp-migration` plugin on BOTH sides. The unrestricted
`.wpress` size needs the free **File Extension** companion or WP-CLI.

## 1. Pre-flight + remote backup

```bash
[[ "$(wpbuild_get '.qa.passed')" == "true" ]] || { echo "QA gate failed"; exit 1; }
# Pre-restore backup on target = rollback point
STAMP="$(date -u +%Y%m%d-%H%M%S)"; RB="${RPATH%/}/wp-build-backups/$STAMP.wpress"
ssh "$HOST" "wp --path='$RPATH' ai1wm backup && \
  mv \$(ls -t '$RPATH'/wp-content/ai1wm-backups/*.wpress | head -1) '$RB'"
wpbuild_set '.deploy.rollbackPoint' "\"$RB\""
```

## 2. Export local `.wpress`

```bash
wp-env run cli wp ai1wm backup
# Archive lands in wp-content/ai1wm-backups/*.wpress
LOCAL_WPRESS="$(ls -t ./wp-content/ai1wm-backups/*.wpress | head -1)"
```

## 3. Transfer + restore

```bash
scp "$LOCAL_WPRESS" "$HOST:$RPATH/wp-content/ai1wm-backups/"
ssh "$HOST" "wp --path='$RPATH' ai1wm restore $(basename "$LOCAL_WPRESS") --yes"
ssh "$HOST" "wp --path='$RPATH' rewrite flush && wp --path='$RPATH' cache flush"
```

## 4. Verify + residual URL check

```bash
ssh "$HOST" "wp --path='$RPATH' option get siteurl"   # == urls.production
curl -fsS -o /dev/null -w '%{http_code}\n' "$(wpbuild_get '.urls.production')"
# AI1WM should have rewritten URLs; confirm none of the local URL remain:
WP_CLI_RUN="ssh $HOST wp --path=$RPATH" bash "${CLAUDE_PLUGIN_ROOT}/scripts/migrate-urls.sh"
```

If the dry-run reports leftover `urls.local` references, apply once with `--apply`.

## Rollback

```bash
RB="$(wpbuild_get '.deploy.rollbackPoint')"
ssh "$HOST" "wp --path='$RPATH' ai1wm restore '$(basename "$RB")' --yes"
```

## Notes

- AI1WM is the simplest target (handles serialized data + URLs), but archives can
  be large; prefer `ssh-wpcli` for big media libraries (rsync diffs only).
- The free plugin caps upload size in the admin UI; the WP-CLI path bypasses it.
