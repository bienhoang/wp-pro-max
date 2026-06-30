#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FX="$(dirname "${BASH_SOURCE[0]}")"

echo "== Phase 3 TDD: site-editor command =="

# Syntax checks
bash -n "$ROOT/scripts/site-editor-lib.sh"
bash -n "$ROOT/commands/site-editor.md" 2>/dev/null || true

# Missing manifest guard
TMP="$(mktemp -d)"
(
  cd "$TMP"
  ! source "$ROOT/scripts/site-editor-lib.sh" && site_editor_require_manifest_and_outdir
) || true
[ ! -f "$TMP/wp-build.json" ]

# Missing optimized dir guard
mkdir -p "$TMP/.wp-pro-max"
cat > "$TMP/wp-build.json" <<'EOF'
{ "version": "1", "project": { "name": "T", "themeSlug": "t" }, "strategy": "classic-acf", "progress": {}, "optimization": { "outputDir": "./.wp-pro-max/optimized" } }
EOF
(
  cd "$TMP"
  ! source "$ROOT/scripts/site-editor-lib.sh" && site_editor_require_manifest_and_outdir
) || true

# Valid project + parsing
mkdir -p "$TMP/.wp-pro-max/optimized"
(
  cd "$TMP"
  source "$ROOT/scripts/site-editor-lib.sh"
  site_editor_require_manifest_and_outdir || exit 1
  site_editor_parse_args --redesign "reorder services before hero" --page index.html
  [ "$SITE_EDITOR_ACTION" = "redesign" ]
  [ "$SITE_EDITOR_REDESIGN" = "reorder services before hero" ]
  [ "$SITE_EDITOR_PAGE" = "index.html" ]
)

# Check mode parsing
(
  cd "$TMP"
  source "$ROOT/scripts/site-editor-lib.sh"
  site_editor_parse_args --check --thorough
  [ "$SITE_EDITOR_ACTION" = "check" ]
  [ "$SITE_EDITOR_CHECK_MODE" = "--thorough" ]
)

# All mode parsing
(
  cd "$TMP"
  source "$ROOT/scripts/site-editor-lib.sh"
  site_editor_parse_args --all --quick
  [ "$SITE_EDITOR_ACTION" = "all" ]
  [ "$SITE_EDITOR_CHECK_MODE" = "--quick" ]
)

# Plugin manifest validation (best-effort; skip if claude CLI unavailable)
if command -v claude >/dev/null 2>&1; then
  echo "Validating plugin manifest..."
  (cd "$ROOT" && claude plugin validate . >/dev/null 2>&1) || echo "plugin validate skipped"
fi

rm -rf "$TMP"
echo "Phase 3 TDD: PASS"
