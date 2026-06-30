---
title: "Port WP Plugin Development Skill to WP Pro Max"
description: "Create an always-active wp-plugin-development skill with reference guidance for lifecycle, security, data storage, and common errors, and wire it into wp-plugin-dev and wp-plugin-developer."
status: done
priority: P2
branch: "main"
tags: [skill, plugin, port, wordpress, lifecycle, security]
blockedBy: []
blocks: []
created: "2026-06-28T00:28:00.000Z"
createdBy: "ck:plan"
source: skill
---

# Plan: Port WP Plugin Development Skill to WP Pro Max

## Source

- Repository: `alessioarzenton/claude-code-wp-toolkit`
- Ref: `main` (`9a90d123f330fa29ad887363299abc71832226c1`)
- Artifacts:
  - `core/claude/skills/core/wp-plugin-development/SKILL.md`
  - Context: `core/claude/skills/core/wp-rest-api/SKILL.md`
  - Context: `core/claude/skills/community/wp-cli-ops/SKILL.md`

## Goal

Create a dedicated, idiomatic `wp-plugin-development` skill for `wp-pro-max` that provides always-active rules and reference guidance for WordPress plugin work. It complements (but does not replace) the existing opt-in `wp-plugin-dev` builder skill and its agent.

## Selected Mode

`--port` (rewrite idiomatically for the local stack).

## Scope

**In scope:**
- `skills/wp-plugin-development/SKILL.md` — not user-invocable; points to references.
- `skills/wp-plugin-development/references/plugin-lifecycle.md`
- `skills/wp-plugin-development/references/plugin-security-baseline.md`
- `skills/wp-plugin-development/references/plugin-data-storage.md`
- `skills/wp-plugin-development/references/plugin-checklist.md`
- Updates to `skills/wp-plugin-dev/SKILL.md`, `agents/wp-plugin-developer.md`, `README.md`.
- License/attribution for ported content.

**Out of scope:**
- New plugin builder scripts or manifest schema changes.
- Changes to `wp-plugin-dev` subcommands or reference templates.
- Full per-project generated skills.

## Phases

| Phase | Name | Status | File |
|-------|------|--------|------|
| 1 | [Design & Analysis](./phase-01-design.md) | Pending | `phase-01-design.md` |
| 2 | [Create Skill & References](./phase-02-create-skill.md) | Pending | `phase-02-create-skill.md` |
| 3 | [Update Consumer Skills & Agent](./phase-03-update-consumers.md) | Pending | `phase-03-update-consumers.md` |
| 4 | [License & Documentation](./phase-04-license-docs.md) | Pending | `phase-04-license-docs.md` |
| 5 | [Verify](./phase-05-verify.md) | Pending | `phase-05-verify.md` |

## Dependencies

No blocking cross-plan dependencies. `20260626-wp-plugin-dev` is complete and provides the builder context this skill complements. Touches only documentation; no schema or pipeline script changes.

## Risk Score

**4/10 (Low–Medium)**

| Risk | Severity | Mitigation |
|------|----------|------------|
| License contamination from GPL-3.0 source | Medium | Rewrite all prose; attribute source only in short notes. |
| Confusion between `wp-plugin-dev` and `wp-plugin-development` | Medium | Clear naming and cross-references: `wp-plugin-dev` is the builder; `wp-plugin-development` is always-active guidance. |
| Scope creep into builder implementation | Low | Explicitly exclude changes to `plugin-scaffold.sh`, `wp-plugin.json` schema, and feature generators. |
| Agent standards drift | Low | Keep `wp-plugin-developer.md` non-negotiable standards intact; only add reference pointers. |

## Rollback Strategy

- Remove `skills/wp-plugin-development/`.
- Revert reference edits in `skills/wp-plugin-dev/SKILL.md` and `agents/wp-plugin-developer.md`.
- Revert the `README.md` edit.
- Remove or revert the `LICENSE` change.
- No manifest schema or runtime script changes are required, so rollback has no pipeline side effects.

## Acceptance Criteria

- [ ] `skills/wp-plugin-development/SKILL.md` exists and passes `claude plugin validate .`.
- [ ] The skill is not user-invocable (`user-invocable: false`) and describes when to apply it.
- [ ] Reference files exist for lifecycle, security baseline, data storage, and checklist/common errors.
- [ ] Code examples follow local WPCS conventions (tabs, no `strict_types`, class OOP where applicable).
- [ ] Existing `wp-plugin-dev` skill and `wp-plugin-developer` agent cross-reference the new skill's references.
- [ ] License/attribution for the ported GPL-3.0 content is recorded.
