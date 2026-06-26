# Maintenance Runbook (template)

Generated into the target project's `docs/maintenance-runbook.md`, populated from
`wp-build.json`. Below is the structure + the concrete commands to emit.

## Common tasks

| Task | How |
|------|-----|
| Add a page | WP Admin → Pages → Add New (or duplicate a similar page). For ACF themes, fill the field group. |
| Add a CPT entry | Admin → `<CPT label>` → Add New. CPTs: list from `contentModel.postTypes`. |
| Edit menus | Appearance → Menus → location `<from contentModel.menus>`. |
| Clear cache | `wp cache flush` (+ the cache plugin's "Purge All"). |
| Regenerate thumbnails | `wp media regenerate --yes` (after changing image sizes). |
| Update permalinks | Settings → Permalinks → Save (or `wp rewrite flush`). |

## Safe plugin/theme/core updates

1. Snapshot first: `wp db export pre-update.sql` and back up `wp-content`.
2. Update on **staging**, run the `wp-qa` checks, then promote via `wp-ship`.
3. Production update order: plugins → theme → core; re-test after each.

```bash
wp plugin update --all --dry-run     # preview
wp plugin update --all
wp theme update --all
wp core update
wp cache flush && wp rewrite flush
```

## Troubleshooting

- **White screen / 500**: enable `WP_DEBUG`, check `wp-content/debug.log`. Disable
  the last-changed plugin: `wp plugin deactivate <slug>`.
- **Plugin conflict**: bisect — `wp plugin deactivate --all`, reactivate one by one.
- **Stale content**: purge cache plugin + `wp cache flush`; hard-refresh CDN.
- **Broken images after migration**: re-run `wp-qa` link check + `wp media
  regenerate`; verify `wp search-replace` covered the old URL.
- **Locale not switching** (i18n): confirm `.mo` files compiled and Polylang/WPML
  languages registered.

## Rollback

This site records a rollback point on every deploy:
`deploy.rollbackPoint = <from manifest>`.

To undo the latest deploy, follow the `wp-ship` rollback procedure for the active
`deploy.target` (`ssh-wpcli` / `ai1wm` / `rsync`):

```bash
# ssh-wpcli example:
RB="<deploy.rollbackPoint>"
ssh "<deploy.host>" "wp --path='<deploy.path>' db import '$RB/db.sql' \
  && tar -C '<deploy.path>' -xzf '$RB/wp-content.tgz' \
  && wp --path='<deploy.path>' cache flush && wp --path='<deploy.path>' rewrite flush"
```

After rollback, re-run the smoke test (home + key pages return 200, siteurl correct).

## Escalation

- Hosting/SSH issues → host support (see `credentials-handoff.md` for where access lives).
- Premium plugin issues (ACF PRO, WPML, Elementor Pro) → vendor support with the license.
