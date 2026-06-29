# Accessibility Known Issues

Project: **{{PROJECT_NAME}}**  
Report date: **{{DATE}}**  
WCAG target: **2.2 AA**  
Prepared by: **{{AUTHOR}}**

## Summary

- **Total issues:** {{TOTAL}}
- **Critical:** {{CRITICAL}} | **Serious:** {{SERIOUS}} | **Moderate:** {{MODERATE}} | **Minor:** {{MINOR}}
- **Overall status:** {{PASS/FAIL/PENDING}}

## Issue log

| # | Page / Location | WCAG Criterion | Severity | Status | Remediation note | Owner |
|---|-----------------|----------------|----------|--------|------------------|-------|
| 1 | `{{URL or template}}` | `{{e.g. 1.1.1 Non-text Content}}` | critical / serious / moderate / minor | open / in-progress / fixed | `{{concrete fix}}` | `{{owner}}` |
| 2 | `{{URL or template}}` | `{{e.g. 1.4.3 Contrast Minimum}}` | critical / serious / moderate / minor | open / in-progress / fixed | `{{concrete fix}}` | `{{owner}}` |

## Testing environment

- **Browser(s):** {{browser + version}}
- **Assistive tech:** {{screen reader / keyboard-only / none}}
- **Automated tool(s):** {{axe-core / Lighthouse / Playwright}}
- **WordPress strategy:** {{classic-acf / block-fse / page-builder / sage}}
- **Base URL tested:** {{URL}}

## Notes

- `{{Context that does not fit in the table: design constraints, blocked fixes, vendor limitations.}}`

## Sign-off

| Role | Name | Date | Status |
|------|------|------|--------|
| QA lead | | | |
| Developer | | | |
| Client / product owner | | | |

---

*Template from WP Pro Max `accessibility` skill. Conventions adapted from [alessioarzenton/claude-code-wp-toolkit](https://github.com/alessioarzenton/claude-code-wp-toolkit) (GPL-3.0), rewritten for WP Pro Max (MIT).*
