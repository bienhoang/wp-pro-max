# Runbook — `rsync` deploy target (files only)

Ships theme + uploads (and optionally plugins) over rsync. The DATABASE is
migrated separately by the operator; this skill still runs the URL search-replace
once the DB is in place on the target.

Use when: the host already has the DB (e.g. managed migration), or you are pushing
code-only updates to an existing live site.

## 1. Pre-flight + backup

```bash
[[ "$(wpbuild_get '.qa.passed')" == "true" ]] || { echo "QA gate failed"; exit 1; }
ssh "$HOST" 'echo ok'
STAMP="$(date -u +%Y%m%d-%H%M%S)"; RB="${RPATH%/}/wp-build-backups/$STAMP"
# Back up the theme dir being replaced (DB is the operator's responsibility here)
ssh "$HOST" "mkdir -p '$RB' && tar -C '$RPATH' -czf '$RB/wp-content.tgz' wp-content"
wpbuild_set '.deploy.rollbackPoint' "\"$RB\""
```

## 2. Sync files

```bash
THEME_NAME="$(basename "$(wpbuild_get '.theme.path')")"
rsync -az --delete "$(wpbuild_get '.theme.path')/" \
  "$HOST:$RPATH/wp-content/themes/$THEME_NAME/"
# Media — additive only, never --delete:
rsync -az ./wp-content/uploads/ "$HOST:$RPATH/wp-content/uploads/" 2>/dev/null || true
```

## 3. URL search-replace (only if the DB still has local URLs)

```bash
WP_CLI_RUN="ssh $HOST wp --path=$RPATH" bash "${CLAUDE_PLUGIN_ROOT}/scripts/migrate-urls.sh"
WP_CLI_RUN="ssh $HOST wp --path=$RPATH" bash "${CLAUDE_PLUGIN_ROOT}/scripts/migrate-urls.sh" --apply
ssh "$HOST" "wp --path='$RPATH' rewrite flush && wp --path='$RPATH' cache flush"
```

## 4. Smoke test

```bash
curl -fsS -o /dev/null -w '%{http_code}\n' "$(wpbuild_get '.urls.production')"   # 200
ssh "$HOST" "wp --path='$RPATH' theme list --status=active --field=name"         # the shipped theme
```

## Rollback

```bash
RB="$(wpbuild_get '.deploy.rollbackPoint')"
ssh "$HOST" "tar -C '$RPATH' -xzf '$RB/wp-content.tgz' && wp --path='$RPATH' cache flush"
```

## Notes

- rsync transfers diffs only → fast for repeat code deploys.
- Never `--delete` the uploads directory; you would destroy client media.
- Activate the theme remotely if it is new: `ssh "$HOST" "wp --path=$RPATH theme activate $THEME_NAME"`.
