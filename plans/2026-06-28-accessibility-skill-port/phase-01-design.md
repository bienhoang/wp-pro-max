---
phase: 1
title: "Design & Analysis"
status: done
priority: P2
dependencies: []
---

# Phase 1: Design & Analysis

## Overview

Analyze the source accessibility skill(s), inspect the existing WP Pro Max skills that already touch accessibility (`html-optimization`, `wp-qa`, `wp-handoff`), and finalize the file layout, naming, and integration contracts for the ported capability.

## Requirements

- **Functional**: Define exactly which files to create, which files to modify, and how the new skill is invoked.
- **Non-functional**: Keep content rewritten for WP Pro Max conventions; avoid duplicating checklist content across skills; respect MIT license by rewriting rather than copying.

## Architecture

```text
wp-pro-max/
├── skills/accessibility/
│   ├── SKILL.md                                  # user-invocable skill entry
│   └── references/
│       ├── accessibility-checklist.md            # consolidated WCAG 2.2 AA checklist
│       └── known-issues-template.md              # handoff template for target project
├── skills/html-optimization/SKILL.md             # modified: reference new checklist
├── skills/wp-qa/SKILL.md                         # modified: reference new checklist + skill
├── skills/wp-handoff/SKILL.md                    # modified: mention known-issues template
├── skills/html-optimization/references/
│   └── accessibility-checklist.md                # redirect or delete
└── skills/wp-qa/references/
    └── accessibility-checklist.md                # redirect or delete
```

## Related Code Files

- **Read**: source skill files if available locally; otherwise use the source manifest in `plan.md`.
- **Read**: `skills/html-optimization/SKILL.md`, `skills/wp-qa/SKILL.md`, `skills/wp-handoff/SKILL.md`.
- **Read**: `skills/html-optimization/references/accessibility-checklist.md` and `skills/wp-qa/references/accessibility-checklist.md` if they exist.
- **Create**: `skills/accessibility/SKILL.md`, `skills/accessibility/references/accessibility-checklist.md`, `skills/accessibility/references/known-issues-template.md`.
- **Modify**: `skills/html-optimization/SKILL.md`, `skills/wp-qa/SKILL.md`, `skills/wp-handoff/SKILL.md`.
- **Delete/Redirect**: duplicate `accessibility-checklist.md` files in `html-optimization/` and `wp-qa/`.

## Implementation Steps

1. Inspect existing consumer skills to understand current a11y content and checklist references.
2. Decide on a naming convention:
   - Skill slug: `accessibility`
   - References: `accessibility-checklist.md`, `known-issues-template.md`
3. Draft frontmatter for the new skill:
   ```yaml
   ---
   name: accessibility
   description: >-
     Accessibility audit and remediation guide for WP Pro Max builds. Use when
     the user asks about WCAG compliance, keyboard navigation, screen-reader
     support, color contrast, alt text, heading order, or accessibility fixes.
     Reads source/optimized HTML or theme templates; produces a checklist and
     optional known-issues handoff.
   user-invocable: true
   allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
   ---
   ```
4. Define the integration edits:
   - `html-optimization/SKILL.md` §4: replace `references/accessibility-checklist.md` link with `skills/accessibility/references/accessibility-checklist.md`.
   - `wp-qa/SKILL.md` a11y section: reference the new skill's checklist and `known-issues-template.md`.
   - `wp-handoff/SKILL.md`: add a bullet that the handoff package may include `docs/a11y-known-issues.md` from the template.
5. Decide whether to delete old checklist files or replace them with short redirect notes. Default: replace with redirect notes to avoid breaking old links.
6. Document license attribution location (new `LICENSE` file or note in `README.md`).

## Success Criteria

- [ ] File list and integration edits are documented in this phase.
- [ ] Existing duplicate checklist content is mapped to the new consolidated location.
- [ ] No verbatim GPL-3.0 prose is copied into design notes.
- [ ] Frontmatter for the new skill is drafted.

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Old checklist files have external links | Replace with redirect notes rather than deleting. |
| Source skill not available locally | Rely on source manifest and rewrite from domain knowledge. |
| Overlap with `wp-qa` execution steps | Keep `accessibility` skill as guidance; `wp-qa` remains execution owner. |
