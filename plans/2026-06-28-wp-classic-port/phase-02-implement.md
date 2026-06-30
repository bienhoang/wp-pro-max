---
phase: 2
title: "Implement"
status: done
priority: P2
dependencies: [1]
---

# Phase 2: Implement

## Overview

Create the new skill, reference, and helper docs, then wire them into the existing `theme-conversion` and `wp-scaffold` skills.

## Requirements

- **Functional**: All new files exist and existing skills reference `references/classic-acf.md` correctly.
- **Non-functional**: Content is rewritten for WP Pro Max conventions; license attribution is present; no placeholders from the source installer leak in.

## Related Code Files

- **Create**: `skills/wp-classic/SKILL.md`, `skills/wp-classic/references/code-review-checklist.md`, `skills/wp-classic/references/component-workflow.md`, `references/classic-acf.md`
- **Modify**: `skills/theme-conversion/SKILL.md`, `skills/wp-scaffold/SKILL.md`
- **Delete**: none

## Implementation Steps

1. **Create `references/classic-acf.md`** (canonical agent reference):
   - Header: `# Classic ACF Strategy Reference`.
   - Section: Stack target (WordPress 7.x, PHP 8.2+, standard wp-env).
   - Section: Theme anatomy (`templates/` optional; root templates default; `parts/`, `inc/`, `assets/`, `acf-json/`).
   - Section: Naming conventions (kebab files, prefixed snake_case functions, PascalCase classes, UPPER constants).
   - Section: Code style (WPCS tabs, Prettier, escaping, i18n).
   - Section: Template pattern (`get_template_part('parts/name', 'variant', $args)`).
   - Section: CPT/tax registration in `inc/post-types.php`.
   - Section: ACF blocks in `inc/acf-blocks.php`; field groups via GUI + `acf-json/`.
   - Section: Enqueue in `inc/enqueue.php`.
   - Section: ACF JSON load/save point snippet.
   - Section: What NOT to do (Blade, Acorn, unsafe echo, hardcoded colors, inline scripts).
2. **Create `skills/wp-classic/SKILL.md`**:
   - Frontmatter as designed in Phase 1.
   - Brief stack summary and when to invoke.
   - Link to `references/classic-acf.md` as the deep reference.
   - Link to `skills/wp-classic/references/code-review-checklist.md` and `component-workflow.md`.
3. **Create `skills/wp-classic/references/code-review-checklist.md`**:
   - Generic checklist: naming, escaping, WPCS, a11y, CSS, git.
   - Remove source's project-specific placeholders (`{{PROJECT_NAME}}`, `{{TEXT_DOMAIN}}`).
4. **Create `skills/wp-classic/references/component-workflow.md`**:
   - Generic 11-step workflow but Figma-free.
   - Keep design-token mapping tables (spacing → Tailwind or rem; colors → CSS variables).
   - Keep build + quick a11y validation steps.
   - Keep memory-update step (map to `.claude/memory.md` or `wp-build.json` notes as appropriate).
5. **Modify `skills/theme-conversion/SKILL.md`**:
   - Ensure step 3 lists `classic-acf → references/classic-acf.md` and the file exists.
   - Add a note that the agent must read `references/classic-acf.md` before authoring classic files.
6. **Modify `skills/wp-scaffold/SKILL.md`**:
   - Add `inc/acf-blocks.php` to the list of generated includes for `classic-acf`.
   - Add the ACF JSON load/save point snippet (or reference `references/classic-acf.md` for it).
7. **Attribution footer**: In each derived file, add a short note: "Conventions adapted from alessioarzenton/claude-code-wp-toolkit (GPL-3.0), rewritten for WP Pro Max (MIT)."

## Success Criteria

- [x] `references/classic-acf.md` exists and is ≤ ~250 lines.
- [x] `skills/wp-classic/SKILL.md` exists with correct frontmatter and links.
- [x] `skills/wp-classic/references/code-review-checklist.md` exists with no project placeholders.
- [x] `skills/wp-classic/references/component-workflow.md` exists with Figma steps removed.
- [x] `theme-conversion/SKILL.md` and `wp-scaffold/SKILL.md` reference `references/classic-acf.md`.
- [x] No `{{VAR}}` placeholders remain in new/modified files.
- [x] License attribution is present in each new file.
