#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

echo "== Phase 7: site-editor integration test =="

TMP="$(mktemp -d)"
mkdir -p "$TMP/source" "$TMP/.wp-pro-max/optimized"
cp -R "$ROOT/examples/sample-site/"* "$TMP/source/"
cp -R "$ROOT/examples/sample-site/"* "$TMP/.wp-pro-max/optimized/"

cat > "$TMP/wp-build.json" <<'EOF'
{
  "version": "1",
  "project": { "name": "Integration", "themeSlug": "integration" },
  "strategy": "classic-acf",
  "source": { "htmlPaths": ["../source"], "briefPath": "../requirements/brief.md" },
  "analysis": {
    "pages": [
      { "path": "index.html", "title": "Home", "role": "home", "sections": ["hero", "services"] },
      { "path": "about.html", "title": "About", "role": "page", "sections": ["hero", "team"] }
    ],
    "components": []
  },
  "optimization": { "outputDir": "./.wp-pro-max/optimized" },
  "contentModel": { "menus": [] },
  "designTokens": {
    "colors": [{ "name": "brand", "value": "#0f766e" }],
    "fonts": [{ "name": "body", "family": "Inter, sans-serif" }]
  },
  "progress": {},
  "siteEditor": {}
}
EOF

cd "$TMP"
export WP_BUILD_FILE="$TMP/wp-build.json"
source "$ROOT/scripts/manifest-lib.sh"

# Simulate pipeline optimize stage (manifest already points to optimized copy)
wpbuild_progress optimize done "copied from source"

# 1) Redesign: reorder services before hero on index.html
BACKUP_BASE="./.wp-pro-max/optimized-backup"
mkdir -p "$BACKUP_BASE"
BACKUP="$BACKUP_BASE/$(date -u +%Y%m%d-%H%M%S)"
cp -R "$TMP/.wp-pro-max/optimized" "$BACKUP"

ORDER="$(mktemp)"
printf 'section.services\nsection.hero\n' > "$ORDER"
source "$ROOT/scripts/html-section-lib.sh"
section_reorder "$TMP/.wp-pro-max/optimized/index.html" "$ORDER"

jq --arg backup "$BACKUP" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
  .analysis.pages[0].sections = ["services", "hero"]
| .siteEditor.redesign = {
    appliedChanges: [{ page: "index.html", action: "reorder", sections: ["services", "hero"], timestamp: $ts }],
    backupDir: $backup,
    lastModified: $ts,
    canRevert: true
  }
' "$TMP/wp-build.json" > "$TMP/wp-build.json.tmp" && mv "$TMP/wp-build.json.tmp" "$TMP/wp-build.json"
wpbuild_progress section-redesign done "reordered index.html"

# 2) Add page
node "$ROOT/scripts/content-enrichment.mjs" "$TMP/wp-build.json" --add-pages "Contact"
[ -f "$TMP/.wp-pro-max/optimized/contact.html" ] || { echo "contact.html missing"; exit 1; }
[ "$(jq '.analysis.pages | length' "$TMP/wp-build.json")" -eq 3 ] || { echo "pages not updated"; exit 1; }

# 3) Enrich copy (mechanical: improve meta description on index.html)
NODE_PATH="$ROOT/node_modules" node -e "
const fs = require('fs');
const cheerio = require('cheerio');
const html = fs.readFileSync('$TMP/.wp-pro-max/optimized/index.html', 'utf8');
const \$ = cheerio.load(html);
\$('meta[name=description]').attr('content', 'Updated meta description');
\$('main').attr('data-wp-pro-max', 'draft');
fs.writeFileSync('$TMP/.wp-pro-max/optimized/index.html', \$.html());
"
jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
  .siteEditor.contentEnrichment.changes = [{ page: "index.html", type: "meta", timestamp: $ts }]
' "$TMP/wp-build.json" > "$TMP/wp-build.json.tmp" && mv "$TMP/wp-build.json.tmp" "$TMP/wp-build.json"

# 4) Pre-conversion QA quick
TOKENS="$(mktemp)"
wpbuild_get '.designTokens' > "$TOKENS"
A11Y="$(node "$ROOT/scripts/pre-qa-a11y.mjs" "$TMP/.wp-pro-max/optimized"/*.html)"
VALID="$(node "$ROOT/scripts/pre-qa-html-validity.mjs" "$TMP/.wp-pro-max/optimized"/*.html)"
BRAND="$(node "$ROOT/scripts/pre-qa-brand.mjs" "$TMP/.wp-pro-max/optimized"/*.html --tokens "$TOKENS")"
rm -f "$TOKENS"
PASSED="$(echo "$A11Y" "$VALID" "$BRAND" | jq -s '(.[0].passed // true) and (.[1].passed // true) and (.[2].passed // true)')"
wpbuild_merge '{
  "siteEditor": {
    "preConversionQa": {
      "passed": '"$PASSED"',
      "mode": "quick",
      "a11y": '"$A11Y"',
      "htmlValidity": '"$VALID"',
      "brandConsistency": '"$BRAND"',
      "responsive": {},
      "lastRun": "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"
    }
  }
}'
wpbuild_progress pre-conversion-qa done "quick checks"

# Assertions
echo "Manifest siteEditor state:"
jq '.siteEditor' "$TMP/wp-build.json"

[ "$(jq -r '.siteEditor.redesign.appliedChanges | length' "$TMP/wp-build.json")" -eq 1 ] || { echo "redesign changes missing"; exit 1; }
[ "$(jq -r '.siteEditor.contentEnrichment.addedPages | length' "$TMP/wp-build.json")" -eq 1 ] || { echo "added pages missing"; exit 1; }
[ "$(jq -r '.siteEditor.preConversionQa.mode' "$TMP/wp-build.json")" = "quick" ] || { echo "qa mode wrong"; exit 1; }

# Source unchanged
if diff -rq "$ROOT/examples/sample-site" "$TMP/source" >/dev/null 2>&1; then
  echo "source unchanged: OK"
else
  echo "source was modified!" >&2
  diff -rq "$ROOT/examples/sample-site" "$TMP/source" || true
  exit 1
fi

rm -rf "$TMP"
echo "Phase 7 integration test: PASS"
