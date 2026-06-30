# Accessibility Skill Port — Completion

Date: 2026-06-29
Plan: plans/2026-06-28-accessibility-skill-port
Commit: 1580fed

## What changed

Created a dedicated `accessibility` skill for WP Pro Max and wired it into the
existing pipeline skills.

- **New skill** (`skills/accessibility/SKILL.md`): user-invocable entry point
  with WCAG 2.2 AA target, POUR overview, automated-vs-manual distinction, and
  WordPress strategy notes (classic/ACF, block/FSE, page builder, Sage).
- **New references**:
  - `accessibility-checklist.md` — consolidated pass/fail checklist covering
    images, structure, landmarks, forms, keyboard, contrast, motion, and robust
    markup.
  - `known-issues-template.md` — handoff-ready template for outstanding a11y
    findings.
- **Consumer updates**:
  - `html-optimization` now points to the shared checklist and mentions the
    accessibility skill.
  - `wp-qa` references the shared checklist and skill for remediation guidance.
  - `wp-handoff` lists `docs/a11y-known-issues.md` as an optional deliverable.
- **Duplicate cleanup**: old `accessibility-checklist.md` files under
  `html-optimization/references/` and `wp-qa/references/` became redirects.
- **Project docs**: README skill count updated to 19, `LICENSE` created with
  attribution, `docs/codebase-summary.md`, `docs/project-roadmap.md`, and
  `docs/system-architecture.md` updated.

## Decisions

- Kept old checklist paths as redirect files rather than deleting them, avoiding
  broken internal links.
- Left placeholders in `known-issues-template.md` because it is a copy-paste
  template, not generated output.
- Did not add axe-core/Playwright automation; `wp-qa` already owns execution
  tools and the new skill only provides guidance.

## Verification

- `claude plugin validate .` passed.
- Code-review subagent approved with no regressions; stage output contracts
  (`optimization.a11yFixes`, `qa.a11y`, handoff outputs) preserved.

## Risks accepted

None. The port is low-risk documentation-only work.
