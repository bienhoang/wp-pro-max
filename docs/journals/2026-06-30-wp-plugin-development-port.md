# WP Plugin Development Skill Port — Completion

Date: 2026-06-30
Plan: plans/2026-06-28-wp-plugin-development-port
Commit: 2fd1430

## What changed

Created a dedicated, always-active `wp-plugin-development` guidance skill for WP
Pro Max and wired it into the existing plugin builder and agent.

- **New skill** (`skills/wp-plugin-development/SKILL.md`): non-invocable entry
  point that explains when it applies and how it relates to `wp-plugin-dev`.
- **New references**:
  - `plugin-lifecycle.md` — activation, deactivation, uninstall, upgrade
    routines, and rewrite-rule flushing.
  - `plugin-security-baseline.md` — input sanitization, output escaping, nonces,
    capability checks, prepared SQL, REST permissions, and anti-patterns.
  - `plugin-data-storage.md` — options, postmeta, custom tables, transients,
    idempotent cron, and versioning.
  - `plugin-checklist.md` — pre-ship verification, common errors, and what NOT
    to do.
- **Consumer updates**:
  - `skills/wp-plugin-dev/SKILL.md` adds a "See also" section pointing to the
    new references.
  - `agents/wp-plugin-developer.md` instructs the agent to consult the new
    references before authoring custom plugin code.
- **Project docs**: README skill count updated to 23 and the new skill listed;
  `LICENSE` attribution extended to `skills/wp-plugin-development/`;
  `docs/codebase-summary.md` updated to 24 skills and includes
  `wp-plugin-development` in the skills table.

## Decisions

- Kept `wp-plugin-dev` builder procedures and `wp-plugin-developer` agent
  non-negotiable standards unchanged; only added cross-reference pointers.
- Rewrote all reference prose for WP Pro Max conventions (WPCS tabs,
  `snake_case` prefixed functions, `defined( 'ABSPATH' ) || exit;` guards, no
  `strict_types`).
- Placed the same attribution footer in every derived file and updated the
  top-level `LICENSE` with a dual-license note.

## Verification

- `claude plugin validate .` passed.
- Code-review subagent approved with no blocking issues and no regressions to
  existing builder procedures or agent standards.

## Risks accepted

None. The port is low-risk documentation-only work.
