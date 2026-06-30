# Rollback — Port wp-classic skill

This plan is purely additive. To revert the port:

1. Remove the new skill directory:
   - `skills/wp-classic/SKILL.md`
   - `skills/wp-classic/references/code-review-checklist.md`
   - `skills/wp-classic/references/component-workflow.md`
   - `skills/wp-classic/`

2. Remove the new canonical reference:
   - `references/classic-acf.md`

3. Revert the small edits to existing files:
   - `skills/theme-conversion/SKILL.md` — restore the original `classic-acf` reference path.
   - `skills/wp-scaffold/SKILL.md` — remove the `inc/acf-blocks.php` mention and the ACF JSON load/save snippet.
   - `agents/wp-theme-developer.md` — remove the `classic-acf` reference path and template-location note.
   - `README.md` — change skill count from 18 back to 17 and remove `wp-classic`.
   - `docs/codebase-summary.md` — remove the `wp-classic` row and `classic-acf.md` reference.
   - `docs/project-roadmap.md` — remove phase 11 from the roadmap table.

4. Optionally remove this rollback file and reset the phase statuses in
   `plan.md` / `phase-*.md` to `pending`.
