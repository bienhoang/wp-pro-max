---
name: wp-plugin-development
description: >-
  Always-active guidance for WordPress plugin development in WP Pro Max.
  Consult when creating or restructuring plugins, hooks, lifecycle, settings,
  security, data storage, or REST routes. Complements the opt-in wp-plugin-dev
  builder skill.
user-invocable: false
allowed-tools: [Read]
---

# WP Plugin Development

Always-active guidance for WordPress plugin work in WP Pro Max. This skill does
not scaffold code; it supplies the conventions and reference checks that keep
plugin code secure, maintainable, and consistent with the kit.

## When this skill applies

- Creating or restructuring a standalone WordPress plugin.
- Writing activation, deactivation, uninstall, or upgrade routines.
- Choosing where and how to store data (options, postmeta, custom tables,
  transients).
- Adding settings pages, REST routes, shortcodes, or custom post types.
- Reviewing plugin code for security, lifecycle, or common errors.

## Relationship to `wp-plugin-dev`

| Skill | Role | Invocation |
|-------|------|------------|
| `wp-plugin-dev` | Builder — scaffolds `wp-plugin.json`, feature classes, and dev loop. | Opt-in via `/wp-pro-max:plugin ...` |
| `wp-plugin-development` | Guidance — supplies always-active rules and reference material. | Always active for plugin intent |

Do not duplicate reference content inside `wp-plugin-dev`. Point to the files
below instead.

## References

- `references/plugin-lifecycle.md` — activation, deactivation, uninstall, and
  upgrade/version routines.
- `references/plugin-security-baseline.md` — sanitize, escape, nonces,
  capabilities, prepared SQL, and file guards.
- `references/plugin-data-storage.md` — options, postmeta, custom tables,
  transients, and idempotent cron.
- `references/plugin-checklist.md` — pre-ship verification, common errors, and
  anti-patterns.

---

*Conventions adapted from [alessioarzenton/claude-code-wp-toolkit](https://github.com/alessioarzenton/claude-code-wp-toolkit) (GPL-3.0), rewritten for WP Pro Max (MIT).*
