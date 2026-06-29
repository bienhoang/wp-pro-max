---
phase: 2
title: "Create Skill & References"
status: done
priority: P2
dependencies: [1]
---

# Phase 2: Create Skill & References

## Overview

Create the `skills/accessibility/` directory, write the main `SKILL.md`, and produce the two reference files: a consolidated WCAG 2.2 AA checklist and a known-issues handoff template.

## Requirements

- **Functional**: The skill is discoverable by the model and gives clear a11y guidance plus actionable checklists.
- **Non-functional**: Content is rewritten for WP Pro Max; license attribution is present; files stay concise (skill ≤ ~200 lines, references can be longer).

## Architecture

### `skills/accessibility/SKILL.md`

Frontmatter as designed in Phase 1.

Body sections:

1. **When to use** — trigger phrases and relationship to `html-optimization`/`wp-qa`.
2. **WCAG 2.2 AA target** — brief POUR overview (Perceivable, Operable, Understandable, Robust).
3. **Automated vs manual** — what tools can catch (alt text, labels, contrast ratios) vs what requires human review (meaningful alt text, focus order, screen-reader flow).
4. **WordPress-relevant rules** — semantic landmarks, heading order, ARIA only when necessary, keyboard support, skip links, focus visibility.
5. **Classic / Block / Sage notes** — short callouts for each strategy used in WP Pro Max.
6. **Testing commands** — example `wp-env` + browser/axe checks; reference the checklist.
7. **References** — links to `accessibility-checklist.md` and `known-issues-template.md`.
8. **Attribution footer** — short GPL-3.0 source note.

### `skills/accessibility/references/accessibility-checklist.md`

Consolidated checklist derived from source `a11y-checklist.md` but:

- Replace Blade/Tailwind-specific phrasing with strategy-agnostic HTML/CSS guidance.
- Add optional callouts for Sage/classic/block builders.
- Group by POUR principles or by verification method (automated / manual).
- Keep it usable as a pass/fail checklist during QA.

### `skills/accessibility/references/known-issues-template.md`

Handoff-ready template with placeholders:

- Project name / date
- Issue list: location, WCAG criterion, severity, status, remediation note, owner
- Testing environment and tools used
- Sign-off section

## Related Code Files

- **Create**: `skills/accessibility/SKILL.md`
- **Create**: `skills/accessibility/references/accessibility-checklist.md`
- **Create**: `skills/accessibility/references/known-issues-template.md`
- **Read**: existing skill files for style reference.

## Implementation Steps

1. Create directory `skills/accessibility/references/`.
2. Write `SKILL.md` with frontmatter and body sections.
3. Write `accessibility-checklist.md` with consolidated WCAG 2.2 AA checks.
4. Write `known-issues-template.md` with handoff-ready placeholders.
5. Add attribution footer in each new file: "Conventions adapted from alessioarzenton/claude-code-wp-toolkit (GPL-3.0), rewritten for WP Pro Max (MIT)."
6. Run `claude plugin validate .` to confirm the new skill frontmatter parses.
7. Mark phase complete and move to Phase 3.

## Success Criteria

- [ ] `skills/accessibility/SKILL.md` exists with valid frontmatter and ≤ ~200 lines.
- [ ] `skills/accessibility/references/accessibility-checklist.md` exists and covers WCAG 2.2 AA essentials.
- [ ] `skills/accessibility/references/known-issues-template.md` exists with placeholders.
- [ ] License attribution is present in each new file.
- [ ] `claude plugin validate .` passes.

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Checklist becomes too long | Move deep detail to references; keep skill body concise. |
| Source-specific terminology leaks | Review for Blade/DDEV/Tailwind assumptions and replace. |
| Frontmatter validation fails | Run `claude plugin validate .` immediately. |
