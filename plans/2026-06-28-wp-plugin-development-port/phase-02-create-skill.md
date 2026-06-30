---
phase: 2
title: "Create Skill & References"
status: done
priority: P2
dependencies: [1]
---

# Phase 2: Create Skill & References

## Overview

Create the `skills/wp-plugin-development/` directory, write the main non-invocable `SKILL.md`, and produce the four reference files covering lifecycle, security, data storage, and a checklist.

## Requirements

- **Functional**: The skill provides canonical guidance that the agent and builder skill can reference.
- **Non-functional**: Content is rewritten for WP Pro Max conventions (WPCS tabs, no `strict_types`, class OOP where applicable); license attribution present; code examples are copy-paste safe.

## Architecture

### `skills/wp-plugin-development/SKILL.md`

Frontmatter as designed in Phase 1.

Body sections:

1. **When this skill applies** — creating/restructuring plugins, hooks, lifecycle, settings, security, data storage.
2. **Relationship to `wp-plugin-dev`** — builder vs guidance.
3. **References** — links to the four reference files.
4. **Attribution footer** — short GPL-3.0 source note.

### `skills/wp-plugin-development/references/plugin-lifecycle.md`

- Activation hook pattern and guard against running on every request.
- Deactivation hook pattern.
- `register_activation_hook` / `register_deactivation_hook` usage.
- `flush_rewrite_rules` on activation only.
- `uninstall.php` pattern (prefer file over `register_uninstall_hook`).
- Idempotent setup: version option + upgrade routine.

### `skills/wp-plugin-development/references/plugin-security-baseline.md`

- Input sanitization: `sanitize_text_field`, `absint`, `wp_kses_post`, etc.
- Output escaping: `esc_html`, `esc_attr`, `esc_url`, `wp_kses_post`.
- Nonces: `wp_nonce_field`, `wp_verify_nonce`, `check_admin_referer`.
- Capability checks: `current_user_can`.
- Prepared SQL: `$wpdb->prepare`.
- `defined( 'ABSPATH' ) || exit;` guard.
- Cross-reference `agents/wp-plugin-developer.md` non-negotiable standards.

### `skills/wp-plugin-development/references/plugin-data-storage.md`

- Options vs postmeta vs custom tables vs transients — when to use each.
- Migration/versioning pattern.
- Idempotent cron registration with `wp_next_scheduled` guard.
- Caching/transient best practices.

### `skills/wp-plugin-development/references/plugin-checklist.md`

- Verification checklist before shipping a plugin.
- Common errors & solutions.
- "What NOT to do" list.

## Related Code Files

- **Create**: `skills/wp-plugin-development/SKILL.md`
- **Create**: `skills/wp-plugin-development/references/plugin-lifecycle.md`
- **Create**: `skills/wp-plugin-development/references/plugin-security-baseline.md`
- **Create**: `skills/wp-plugin-development/references/plugin-data-storage.md`
- **Create**: `skills/wp-plugin-development/references/plugin-checklist.md`
- **Read**: `agents/wp-plugin-developer.md` for alignment.

## Implementation Steps

1. Create directory `skills/wp-plugin-development/references/`.
2. Write `SKILL.md` with frontmatter and concise body.
3. Write each reference file with rewritten, WP Pro Max–aligned content.
4. Ensure code examples use tabs, WPCS style, `snake_case` functions with prefix, and `defined( 'ABSPATH' ) || exit;` guards.
5. Add attribution footer in each derived file: "Conventions adapted from alessioarzenton/claude-code-wp-toolkit (GPL-3.0), rewritten for WP Pro Max (MIT)."
6. Run `claude plugin validate .` to confirm frontmatter parses.
7. Mark phase complete and move to Phase 3.

## Success Criteria

- [ ] `skills/wp-plugin-development/SKILL.md` exists with valid frontmatter and `user-invocable: false`.
- [ ] All four reference files exist and are ≤ ~250 lines each.
- [ ] Code examples follow local WPCS conventions.
- [ ] License attribution is present in each new file.
- [ ] `claude plugin validate .` passes.

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Reference files become too long | Split into the four defined files; keep skill body short. |
| Code examples use `strict_types` | Review and remove; keep WPCS style. |
| Frontmatter validation fails | Run validation immediately after creating SKILL.md. |
