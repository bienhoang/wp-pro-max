# WordPress Hardening Checklist (WP-CLI / wp-config)

Each item lists the action, the command (via `wp-env run cli wp …`), and when to
apply it. Record applied ids into `security.hardeningApplied[]`. Items are
idempotent — re-running is safe.

## wp-config constants

```bash
# Block the in-dashboard theme/plugin code editor (stops post-exploit edits).
wp-env run cli wp config set DISALLOW_FILE_EDIT true --raw            # id: disable-file-edit

# Force HTTPS for admin + login — ONLY when production is https.
wp-env run cli wp config set FORCE_SSL_ADMIN true --raw               # id: force-ssl-admin

# Block plugin/theme install+update from the dashboard on locked prod (optional;
# skip if the site self-updates). Comment out if the host manages updates.
# wp-env run cli wp config set DISALLOW_FILE_MODS true --raw

# Reduce post revisions noise / autosave (hardening-adjacent hygiene).
wp-env run cli wp config set WP_POST_REVISIONS 10 --raw

# Rotate auth keys & salts (invalidates stolen cookies).
wp-env run cli wp config shuffle-salts                                # id: strong-salts
# Older WP-CLI without shuffle-salts: regenerate from the secret-key API and
# wp config set each constant (AUTH_KEY, SECURE_AUTH_KEY, ... NONCE_SALT).
```

## Debug off in production

```bash
wp-env run cli wp config set WP_DEBUG false --raw
wp-env run cli wp config set WP_DEBUG_DISPLAY false --raw
```

## Users — least privilege

```bash
wp-env run cli wp user list --role=administrator --fields=ID,user_login,user_email
# Expect only the accounts you intend. Downgrade stray admins:
# wp-env run cli wp user set-role <ID> editor
# Ensure no user named 'admin' with a weak/default password remains.
```

## XML-RPC, version hiding, headers

These are applied by the emitted mu-plugin (`security-mu-plugin.php`):

- `disable-xmlrpc` — filter `xmlrpc_enabled` → false **only if** no plugin needs
  it (Jetpack, some mobile apps, pingbacks). Confirm before disabling.
- `hide-version` — remove `wp_generator`, strip `?ver=` from enqueued asset URLs.
- `security-headers` — `Strict-Transport-Security` (prod https only),
  `X-Frame-Options: SAMEORIGIN`, `X-Content-Type-Options: nosniff`,
  `Referrer-Policy: strict-origin-when-cross-origin`, and a conservative
  `Content-Security-Policy` (start report-only; tighten per site).

## Login brute-force protection

```bash
wp-env run cli wp plugin list --status=active --field=name | grep -E 'limit-login-attempts-reloaded|wordfence' \
  || echo "no login-limiter active — install one (plugin-selection should have added it)"
```

## File permissions (host guidance — do NOT chmod blindly)

Recommended on the production host (not the wp-env container):

```
find /path/to/wp -type d -exec chmod 755 {} \;
find /path/to/wp -type f -exec chmod 644 {} \;
chmod 600 wp-config.php           # readable only by the web user
```

Verify nothing is world-writable: `find . -perm -2 -type f`. Deny PHP execution
in `wp-content/uploads/` (Apache `.htaccess` `php_flag engine off` or an nginx
`location ~* /uploads/.*\.php$ { deny all; }`). Emit as guidance in the report;
the `wp-deployer` agent applies it during ship.

## Recording

```bash
printf '%s\n' '["disable-file-edit","force-ssl-admin","strong-salts","disable-xmlrpc","hide-version","security-headers","least-privilege","debug-off"]' > sec/hardening-applied.json
```

Only include ids you actually applied (e.g. omit `force-ssl-admin` for an
http-only local build).
