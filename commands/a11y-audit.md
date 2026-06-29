---
description: WCAG 2.2 AA accessibility audit on a specific theme file or the entire active theme.
---

# Accessibility Audit

Scan the active WordPress theme for accessibility issues according to WCAG 2.2 AA.

## Input

- `$ARGUMENTS`: file path to audit, or `all` for a full theme scan.

## Steps

1. **Load the rules**:
   - Read `skills/wp-a11y/SKILL.md` for the audit rules.

2. **Determine files to scan**:
   - Read `wp-build.json` and use `theme.path` as the theme directory.
   - If `$ARGUMENTS` is a file path, scan only that file (resolve relative to the project root if needed).
   - If `$ARGUMENTS` is `all`, scan all PHP templates, block theme parts, patterns, and CSS files under the theme path.
   - Exclude `node_modules/`, `vendor/`, compiled assets, and third-party libraries.

3. **Delegate the scan**:
   - Invoke the `a11y-checker` agent with the file list and the rules context.

4. **Report the results**:
   - Summarize total issues by severity.
   - List the top 3 urgent issues.
   - Suggest next steps (manual review, fixes by `wp-theme-developer`, or automated checks by `wp-qa`).

## Notes

- Do not treat `.claude/docs/a11y-known-issues.md` as a required file. If it exists, you may compare findings for progress tracking, but the audit runs without it.
- This command is read-only. It does not modify theme files.

---

*Ported and rewritten for WP Pro Max from `alessioarzenton/claude-code-wp-toolkit` (GPL-3.0). Target license: MIT.*
