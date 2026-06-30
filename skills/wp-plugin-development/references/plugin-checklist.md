# Plugin Checklist & Common Errors

Use this list before shipping or reviewing a WordPress plugin built in WP Pro
Max.

## Pre-ship verification

- [ ] Every PHP file starts with `defined( 'ABSPATH' ) || exit;`.
- [ ] All user input is sanitized; all output is escaped at the point of echo.
- [ ] Forms/AJAX that write data verify a nonce.
- [ ] Admin screens and REST write routes check a concrete capability.
- [ ] SQL queries use `$wpdb->prepare()`; no literal table prefixes.
- [ ] Rewrite rules are flushed only on activation or when post types change.
- [ ] Cron events are scheduled only if `wp_next_scheduled()` returns false.
- [ ] Activation creates tables/options; deactivation clears crons/transients.
- [ ] `uninstall.php` removes plugin-owned data and respects `WP_UNINSTALL_PLUGIN`.
- [ ] Plugin activates with zero PHP notices/warnings under `WP_DEBUG`.
- [ ] All user-facing strings are internationalized with the plugin textdomain.
- [ ] Scripts and styles are enqueued; no inline `<script src>` or `<link>` tags.
- [ ] Asset paths use `plugin_dir_url()` / `plugin_dir_path()`.
- [ ] The `src/Plugin.php` registrar marker (`/* wp-plugin-dev:registrar */`) is
      intact.

## Common errors

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Headers already sent | Whitespace before `<?php` or after `?>` | Remove trailing/newline whitespace; prefer omitting closing `?>` |
| Permission denied on admin form | Missing `current_user_can()` | Add capability check before processing/rendering |
| Nonce verification failed | Nonce missing or expired | Emit with `wp_nonce_field()` and verify with the same action |
| Data not saved / XSS | Raw `$_POST` echoed or stored | Sanitize on input, escape on output |
| Broken rewrite rules | `flush_rewrite_rules()` called too late or too often | Flush on activation; register hooks on `init` |
| Cron running multiple times | Missing `wp_next_scheduled()` guard | Guard `wp_schedule_event()` |
| DB table not created | `dbDelta()` called without `upgrade.php` | `require_once ABSPATH . 'wp-admin/includes/upgrade.php';` |
| SQL injection | Concatenated query variables | Use `$wpdb->prepare()` |
| 500 on activation | Fatal error in activation hook | Move heavy logic into a class method; avoid output |

## What NOT to do

- Do not use `extract()` on user-supplied arrays.
- Do not trust `is_admin()` as a security check.
- Do not store passwords, API secrets, or keys in options without encryption.
- Do not call `wp_die()` inside activation hooks for routine failures; return
  gracefully and log.
- Do not modify WordPress core files.
- Do not autoload large option values.
- Do not delete user content on deactivation; reserve that for uninstall.

---

*Conventions adapted from [alessioarzenton/claude-code-wp-toolkit](https://github.com/alessioarzenton/claude-code-wp-toolkit) (GPL-3.0), rewritten for WP Pro Max (MIT).*
