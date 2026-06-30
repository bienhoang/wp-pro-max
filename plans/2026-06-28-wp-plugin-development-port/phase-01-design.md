---
phase: 1
title: "Design & Analysis"
status: done
priority: P2
dependencies: []
---

# Phase 1: Design & Analysis

## Overview

Analyze the source `wp-plugin-development` skill, inspect the existing `wp-plugin-dev` builder skill and `wp-plugin-developer` agent, and finalize the file layout, naming, and integration contracts for the ported always-active guidance skill.

## Requirements

- **Functional**: Define exactly which files to create, which files to modify, and how the new skill relates to the existing builder skill.
- **Non-functional**: Keep the distinction between builder (`wp-plugin-dev`) and guidance (`wp-plugin-development`) crystal clear; rewrite for WP Pro Max conventions; respect MIT license.

## Architecture

```text
wp-pro-max/
├── skills/wp-plugin-development/
│   ├── SKILL.md                                  # always-active guidance skill
│   └── references/
│       ├── plugin-lifecycle.md                   # activation/deactivation/uninstall
│       ├── plugin-security-baseline.md           # sanitize/escape/nonces/caps/SQL
│       ├── plugin-data-storage.md                # options/postmeta/custom tables
│       └── plugin-checklist.md                   # verification + common errors
├── skills/wp-plugin-dev/SKILL.md                 # modified: add "See also" section
├── agents/wp-plugin-developer.md                 # modified: add reference pointer
├── README.md                                     # modified: mention new skill
└── LICENSE                                       # new or updated: dual-license note
```

## Related Code Files

- **Read**: source skill manifest in `plan.md`; `skills/wp-plugin-dev/SKILL.md`; `agents/wp-plugin-developer.md`.
- **Read**: `README.md` to identify where to list the new skill.
- **Create**: `skills/wp-plugin-development/SKILL.md`, `skills/wp-plugin-development/references/plugin-lifecycle.md`, `plugin-security-baseline.md`, `plugin-data-storage.md`, `plugin-checklist.md`.
- **Modify**: `skills/wp-plugin-dev/SKILL.md`, `agents/wp-plugin-developer.md`, `README.md`.

## Implementation Steps

1. Inspect `skills/wp-plugin-dev/SKILL.md` and `agents/wp-plugin-developer.md` to understand current plugin standards and reference patterns.
2. Decide on naming and frontmatter:
   ```yaml
   ---
   name: wp-plugin-development
   description: >-
     Always-active guidance for WordPress plugin development in WP Pro Max.
     Consult when creating or restructuring plugins, hooks, lifecycle, settings,
     security, data storage, or REST routes. Complements the opt-in
     wp-plugin-dev builder skill.
   user-invocable: false
   allowed-tools: [Read]
   ---
   ```
3. Define reference file responsibilities:
   - `plugin-lifecycle.md`: activation/deactivation hooks, `flush_rewrite_rules`, `uninstall.php`.
   - `plugin-security-baseline.md`: input sanitization, output escaping, nonces, capability checks, prepared SQL.
   - `plugin-data-storage.md`: options vs postmeta vs custom tables vs transients; migration/versioning; idempotent cron.
   - `plugin-checklist.md`: verification checklist, common errors, "What NOT to do".
4. Define integration edits:
   - `wp-plugin-dev/SKILL.md`: add a "See also" section pointing to `skills/wp-plugin-development/references/`.
   - `agents/wp-plugin-developer.md`: add a line instructing the agent to consult the references before authoring custom plugin code.
   - `README.md`: mention the new skill under plugin development; optionally update skill count.
5. Decide license attribution location (`LICENSE` file update/create).

## Success Criteria

- [ ] File list and integration edits are documented in this phase.
- [ ] Frontmatter for the new skill is drafted.
- [ ] Distinction between `wp-plugin-dev` and `wp-plugin-development` is documented.
- [ ] No verbatim GPL-3.0 prose is copied into design notes.

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Name collision confuses users | Use consistent prefixes and explicit cross-reference wording. |
| Source not available locally | Rely on source manifest and rewrite from domain knowledge. |
| Overlap with `wp-plugin-developer` agent standards | Keep agent standards intact; add pointers only. |
