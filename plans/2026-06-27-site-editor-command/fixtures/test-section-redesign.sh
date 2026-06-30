#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

echo "== Phase 4 TDD: section-redesign skill mechanics =="

TMP="$(mktemp -d)"
mkdir -p "$TMP/.wp-pro-max/optimized"
cp -R "$ROOT/examples/sample-site/"* "$TMP/.wp-pro-max/optimized/"

cat > "$TMP/wp-build.json" <<'EOF'
{
  "version": "1",
  "project": { "name": "Test", "themeSlug": "test" },
  "strategy": "classic-acf",
  "analysis": {
    "pages": [
      { "path": "index.html", "title": "Home", "role": "home", "sections": ["hero", "services"] }
    ]
  },
  "optimization": { "outputDir": "./.wp-pro-max/optimized" },
  "progress": {},
  "siteEditor": {}
}
EOF

cd "$TMP"
source "$ROOT/scripts/manifest-lib.sh"
export WP_BUILD_FILE="$TMP/wp-build.json"

# Backup pattern
BACKUP_BASE="./.wp-pro-max/optimized-backup"
mkdir -p "$BACKUP_BASE"
BACKUP="$BACKUP_BASE/$(date -u +%Y%m%d-%H%M%S)"
cp -R "$TMP/.wp-pro-max/optimized" "$BACKUP"

# Reorder services before hero using the helper
ORDER="$(mktemp)"
printf 'section.services\nsection.hero\n' > "$ORDER"
source "$ROOT/scripts/html-section-lib.sh"
section_reorder "$TMP/.wp-pro-max/optimized/index.html" "$ORDER"

# Validate HTML still parses (use project-root cheerio)
NODE_PATH="$ROOT/node_modules" node -e "require('cheerio').load(require('fs').readFileSync('$TMP/.wp-pro-max/optimized/index.html','utf8'))"

# Update manifest
jq --arg backup "$BACKUP" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
  .analysis.pages[0].sections = ["services", "hero"]
| .siteEditor.redesign = {
    appliedChanges: [{
      page: "index.html",
      action: "reorder",
      sections: ["services", "hero"],
      timestamp: $ts
    }],
    backupDir: $backup,
    lastModified: $ts,
    canRevert: true
  }
' "$TMP/wp-build.json" > "$TMP/wp-build.json.tmp" && mv "$TMP/wp-build.json.tmp" "$TMP/wp-build.json"

# Assertions
SECTIONS="$(jq -r '.analysis.pages[0].sections | join(",")' "$TMP/wp-build.json")"
[ "$SECTIONS" = "services,hero" ] || { echo "sections not reordered: $SECTIONS"; exit 1; }

[ "$(jq -r '.siteEditor.redesign.appliedChanges | length' "$TMP/wp-build.json")" -eq 1 ] || { echo "appliedChanges missing"; exit 1; }

HTML="$(cat "$TMP/.wp-pro-max/optimized/index.html")"
# services should appear before hero in the HTML
SERVICES_POS="$(echo "$HTML" | grep -bo 'section id="services"' | head -1 | cut -d: -f1)"
HERO_POS="$(echo "$HTML" | grep -bo 'section class="hero"' | head -1 | cut -d: -f1)"
[ "$SERVICES_POS" -lt "$HERO_POS" ] || { echo "HTML order not reordered"; exit 1; }

rm -rf "$TMP"
echo "Phase 4 TDD: PASS"
