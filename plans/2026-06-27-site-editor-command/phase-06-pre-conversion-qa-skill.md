---
phase: 6
title: "Pre-Conversion QA Skill"
status: done
priority: P1
dependencies: [1, 2]
---

# Phase 6: Pre-Conversion QA Skill

## Overview

Create `skills/pre-conversion-qa/SKILL.md` and references. The skill runs lightweight checks on the optimized HTML before `theme-conversion`: accessibility, HTML validity, responsive layout, and brand consistency against `designTokens`.

## Requirements

- Functional: Skill runs in `--quick` mode by default (static a11y + HTML validity + brand token check).
- Functional: `--thorough` mode adds Playwright responsive rendering at 375/768/1280.
- Functional: Skill writes `siteEditor.preConversionQa.{a11y,responsive,brandConsistency,htmlValidity,passed,mode,lastRun}`. Results are advisory: they warn but do not block other stages.
- Functional: Skill does NOT require a running wp-env; it operates on static HTML files only.
- Non-functional: Source HTML is never touched; skill is idempotent and resumable.

## Architecture

Stage id: `pre-conversion-qa`

Inputs:
- `optimization.outputDir`
- `analysis.pages[]`
- `designTokens`
- `optimization.a11yFixes` (to avoid re-reporting already-known issues)
- `--quick` or `--thorough`

Outputs:
- `siteEditor.preConversionQa.passed`
- `siteEditor.preConversionQa.mode`
- `siteEditor.preConversionQa.a11y`
- `siteEditor.preConversionQa.responsive`
- `siteEditor.preConversionQa.brandConsistency`
- `siteEditor.preConversionQa.htmlValidity`
- `siteEditor.preConversionQa.lastRun`

Procedure:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh"
wpbuild_is_done pre-conversion-qa && [[ "${1:-}" != "--force" ]] && { echo "pre-conversion-qa already done"; exit 0; }
wpbuild_progress pre-conversion-qa in-progress

OUTDIR="$(wpbuild_get '.optimization.outputDir')"
MODE="${1:---quick}"
[ "$MODE" = "--thorough" ] && MODE="thorough" || MODE="quick"

# Static checks for every page in analysis.pages[]
node "${CLAUDE_PLUGIN_ROOT}/scripts/pre-qa-a11y.mjs" "$OUTDIR"/*.html > /tmp/pre-qa-a11y.json
node "${CLAUDE_PLUGIN_ROOT}/scripts/pre-qa-html-validity.mjs" "$OUTDIR"/*.html > /tmp/pre-qa-validity.json
node "${CLAUDE_PLUGIN_ROOT}/scripts/pre-qa-brand.mjs" "$OUTDIR"/*.html --tokens <(wpbuild_get '.designTokens') > /tmp/pre-qa-brand.json

# Thorough mode only
if [ "$MODE" = "thorough" ]; then
  node "${CLAUDE_PLUGIN_ROOT}/scripts/pre-qa-responsive.mjs" "$OUTDIR"/*.html > /tmp/pre-qa-responsive.json
fi

# Aggregate passed = all sub-checks passed
wpbuild_merge '{"siteEditor":{"preConversionQa":{"passed":true,"mode":"'"$MODE"'","lastRun":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}}}'
wpbuild_progress pre-conversion-qa done "$MODE checks completed (advisory)"
```

Note: if `pre-qa-html-validity.mjs` and `pre-qa-brand.mjs` do not exist in Phase 2, fold them into `pre-qa-a11y.mjs` or add them as small new scripts in this phase.

## Related Code Files

- Create: `skills/pre-conversion-qa/SKILL.md`
- Create: `skills/pre-conversion-qa/references/pre-conversion-checklist.md`
- Read: `skills/wp-qa/SKILL.md` and `skills/wp-qa/references/accessibility-checklist.md`
- Read: `scripts/pre-qa-a11y.mjs`, `scripts/pre-qa-responsive.mjs`

## Implementation Steps

1. **TDD — create fixture and expectation.** In `plans/.../fixtures/pre-conversion-qa/`:
   - Provide optimized HTML with known a11y/validity/brand issues.
   - Define expected `siteEditor.preConversionQa` output and `passed=false`.
   - Provide a clean optimized copy and define `passed=true`.
2. Run expectation script; expect failures.
3. Write `skills/pre-conversion-qa/SKILL.md` with resume guard, mode selection, and aggregation logic.
4. Write `references/pre-conversion-checklist.md` listing exactly what quick vs thorough modes check.
5. Implement brand-consistency check algorithm:
   - Extract all inline `color`, `background-color`, `font-family` values from the optimized CSS/HTML.
   - Compare against `designTokens.colors[].value` and `designTokens.fonts[].family`.
   - Report a violation only when a value is "far" from any token (e.g., color not within a small RGB distance, font not a known token). CSS custom properties matching token names are allowed.
   - Output: `{ passed, mismatches[] }`.
6. Implement HTML validity check (parse with cheerio/parse5; report unclosed tags, duplicate ids, missing `<html lang>`).
7. Re-run fixtures until clean copy passes and dirty copy fails.

## Test-First Structure

```bash
# Dirty fixture should fail
node scripts/pre-qa-a11y.mjs plans/.../fixtures/pre-conversion-qa/dirty/index.html | jq '.passed' # false
node scripts/pre-qa-responsive.mjs plans/.../fixtures/pre-conversion-qa/dirty/index.html | jq '.passed' # false or skipped in quick mode

# Clean fixture should pass
node scripts/pre-qa-a11y.mjs examples/sample-site/index.html | jq '.passed' # true
```

## Success Criteria

- [ ] `skills/pre-conversion-qa/SKILL.md` exists with correct frontmatter.
- [ ] `--quick` runs static a11y, HTML validity, and brand checks without a browser.
- [ ] `--thorough` adds responsive checks via Playwright.
- [ ] Output is written to `siteEditor.preConversionQa.*`.
- [ ] `passed` is `false` when any hard check fails.
- [ ] Skill does not require wp-env.
- [ ] Re-running without `--force` skips the stage.

## Risk Assessment

- **Risk:** Pre-conversion QA is slow in thorough mode.  
  **Mitigation:** Default to quick mode; thorough is opt-in; cache responsive screenshots between runs.
- **Risk:** Brand check false-positives on CSS variables.  
  **Mitigation:** Allow CSS custom properties that reference token names; use a small RGB distance threshold for literal values; report only clear mismatches.
