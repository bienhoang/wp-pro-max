---
phase: 1
title: "Design"
status: done
priority: P2
dependencies: []
---

# Phase 1: Design

## Overview

Finalize the file layout, naming conventions, and integration contracts for the ported `wp-classic` capability. This phase produces the exact list of files to create/modify and the convention decisions that later phases must follow.

## Requirements

- **Functional**: Define how `wp-classic` is discovered (user invocation + stage references) and what files it owns.
- **Non-functional**: Keep the kit's existing skill layout (`SKILL.md` + `references/` + optional `templates/`); avoid per-project generated skills; respect MIT license by rewriting rather than copying.

## Architecture

```text
wp-pro-max/
├── skills/wp-classic/
│   ├── SKILL.md                              # user-invocable stack skill
│   └── references/
│       ├── code-review-checklist.md          # generic WPCS/a11y/security checklist
│       └── component-workflow.md             # generic Figma-free component workflow
├── references/classic-acf.md                 # canonical agent reference for classic-acf strategy
├── skills/theme-conversion/SKILL.md          # modified: route classic-acf to references/classic-acf.md
└── skills/wp-scaffold/SKILL.md               # modified: mention inc/acf-blocks.php + acf-json load/save point
```

## Related Code Files

- **Create**: `skills/wp-classic/SKILL.md`, `skills/wp-classic/references/code-review-checklist.md`, `skills/wp-classic/references/component-workflow.md`, `references/classic-acf.md`
- **Modify**: `skills/theme-conversion/SKILL.md`, `skills/wp-scaffold/SKILL.md`
- **Delete**: none

## Implementation Steps

1. **Confirm convention decisions** from `plans/reports/xia-wp-classic-challenge.md`:
   - Target WordPress 7.x, PHP 8.2+.
   - Standard `wp-env` path `wp-content/themes/<slug>`; Bedrock optional.
   - Root template files as default; `templates/` folder noted as optional.
   - ACF Pro assumed for `classic-acf` strategy.
2. **Map source content to local structure**:
   - Stack declaration → `skills/wp-classic/SKILL.md` frontmatter + first section.
   - Project structure, naming, code style → `references/classic-acf.md` "Theme anatomy" section.
   - Template patterns, CPT/tax, ACF blocks, enqueue → `references/classic-acf.md` concrete sections.
   - Anti-patterns → `references/classic-acf.md` "What NOT to do" section.
   - Code-review checklist → `skills/wp-classic/references/code-review-checklist.md` (generic, no project placeholders).
   - Component workflow → `skills/wp-classic/references/component-workflow.md` (Figma-free).
3. **Define integration edits**:
   - `theme-conversion/SKILL.md` step 3: change the bullet from `classic-acf → references/classic-acf.md` (currently a dead reference) and ensure it actually exists.
   - `wp-scaffold/SKILL.md`: add `inc/acf-blocks.php` to the generated includes for classic-acf, and mention the ACF JSON load/save point.
4. **Draft frontmatter** for the new skill:
   ```yaml
   ---
   name: wp-classic
   description: >-
     Conventions and reference for classic PHP WordPress 7.x themes with ACF
     (the WP Pro Max classic-acf strategy). Use when generating or reviewing
     classic theme code, template parts, CPT/taxonomy registration, ACF blocks,
     and enqueues. Reads strategy and project fields from wp-build.json.
   user-invocable: true
   allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
   ---
   ```

## Success Criteria

- [x] File list and integration edits are documented in this phase.
- [x] No Bedrock/DDEV-specific paths appear in the final text unless marked optional.
- [x] No `{{VAR}}` placeholders remain in ported content.
- [x] Challenge decisions are reflected verbatim in the design notes.
