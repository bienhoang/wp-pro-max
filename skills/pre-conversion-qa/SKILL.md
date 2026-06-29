---
name: pre-conversion-qa
description: Run lightweight accessibility, HTML validity, brand-consistency, and responsive checks on the optimized HTML copy before WordPress theme conversion. Reads wp-build.json, writes siteEditor.preConversionQa, and does not require wp-env. Use when validating the optimized copy, checking pre-conversion quality, or running the site-editor --check command.
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# Pre-Conversion QA (`pre-conversion-qa` stage)

Lightweight quality checks on the optimized HTML copy before `theme-conversion`.
Results are advisory: they warn but do not block conversion.

## Inputs

- `optimization.outputDir` — working copy.
- `analysis.pages[]` — pages to check.
- `designTokens` — colors, fonts.
- `optimization.a11yFixes` — already-known issues.
- `--quick` (default) or `--thorough`.

## Outputs

- `siteEditor.preConversionQa.passed`
- `siteEditor.preConversionQa.mode`
- `siteEditor.preConversionQa.a11y`
- `siteEditor.preConversionQa.responsive`
- `siteEditor.preConversionQa.brandConsistency`
- `siteEditor.preConversionQa.htmlValidity`
- `siteEditor.preConversionQa.lastRun`
- `progress.pre-conversion-qa`.

## Procedure

```bash
set -e
source "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh"

wpbuild_is_done pre-conversion-qa && [[ "${1:-}" != "--force" ]] && { echo "pre-conversion-qa already done"; exit 0; }
wpbuild_progress pre-conversion-qa in-progress

OUTDIR="$(wpbuild_get '.optimization.outputDir')"
MODE="${1:---quick}"
[ "$MODE" = "--thorough" ] && MODE="thorough" || MODE="quick"

# Static checks (always run)
A11Y="$(node "${CLAUDE_PLUGIN_ROOT}/scripts/pre-qa-a11y.mjs" "$OUTDIR"/*.html || true)"
VALID="$(node "${CLAUDE_PLUGIN_ROOT}/scripts/pre-qa-html-validity.mjs" "$OUTDIR"/*.html || true)"
TOKENS_FILE="$(mktemp)"
wpbuild_get '.designTokens' > "$TOKENS_FILE"
BRAND="$(node "${CLAUDE_PLUGIN_ROOT}/scripts/pre-qa-brand.mjs" "$OUTDIR"/*.html --tokens "$TOKENS_FILE" || true)"
rm -f "$TOKENS_FILE"

# Thorough mode adds responsive rendering
RESPONSIVE="{}"
if [ "$MODE" = "thorough" ]; then
  RESPONSIVE="$(node "${CLAUDE_PLUGIN_ROOT}/scripts/pre-qa-responsive.mjs" "$OUTDIR"/*.html || true)"
fi

PASSED="$(echo "$A11Y" "$VALID" "$BRAND" "$RESPONSIVE" | jq -s '
  (.[0].passed // true) and (.[1].passed // true) and (.[2].passed // true) and (.[3].passed // true)
')"

wpbuild_merge '{
  "siteEditor": {
    "preConversionQa": {
      "passed": '"$PASSED"',
      "mode": "'"$MODE"'",
      "a11y": '"$A11Y"',
      "htmlValidity": '"$VALID"',
      "brandConsistency": '"$BRAND"',
      "responsive": '"$RESPONSIVE"',
      "lastRun": "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"
    }
  }
}'
wpbuild_progress pre-conversion-qa done "$MODE checks completed (advisory)"
```

## Notes

- `--quick` runs without a browser and is the default.
- `--thorough` installs/uses Playwright and Chromium for responsive rendering.
- A failing `preConversionQa.passed` should produce a warning in `theme-conversion`
  but must not block conversion in this iteration.
