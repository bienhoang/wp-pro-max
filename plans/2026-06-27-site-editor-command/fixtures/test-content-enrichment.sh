#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

echo "== Phase 5 TDD: content-enrichment skill mechanics =="

TMP="$(mktemp -d)"
mkdir -p "$TMP/requirements" "$TMP/.wp-pro-max/optimized"
cp -R "$ROOT/examples/sample-site/"* "$TMP/.wp-pro-max/optimized/"

cat > "$TMP/requirements/brief.md" <<'EOF'
# Project brief

## Pages

- Contact: contact page with form and address
- Portfolio: portfolio showcase
EOF

cat > "$TMP/wp-build.json" <<'EOF'
{
  "version": "1",
  "project": { "name": "Test", "themeSlug": "test" },
  "strategy": "classic-acf",
  "source": { "briefPath": "./requirements/brief.md" },
  "analysis": {
    "pages": [
      { "path": "index.html", "title": "Home", "role": "home", "sections": ["hero", "services"] }
    ]
  },
  "optimization": { "outputDir": "./.wp-pro-max/optimized" },
  "contentModel": { "menus": [] },
  "progress": {},
  "siteEditor": {}
}
EOF

cd "$TMP"

# --add-pages via CLI
node "$ROOT/scripts/content-enrichment.mjs" "$TMP/wp-build.json" --add-pages "Contact, Portfolio"

[ -f "$TMP/.wp-pro-max/optimized/contact.html" ] || { echo "contact.html missing"; exit 1; }
[ -f "$TMP/.wp-pro-max/optimized/portfolio.html" ] || { echo "portfolio.html missing"; exit 1; }

# Draft markers present
[ "$(grep -c 'data-wp-pro-max="draft"' "$TMP/.wp-pro-max/optimized/contact.html")" -gt 0 ] || { echo "draft marker missing"; exit 1; }

# Manifest updated
[ "$(jq '.analysis.pages | length' "$TMP/wp-build.json")" -eq 3 ] || { echo "analysis.pages not updated"; exit 1; }
[ "$(jq '.contentModel.menus[0].items | length' "$TMP/wp-build.json")" -eq 2 ] || { echo "menu not updated"; exit 1; }
[ "$(jq '.siteEditor.contentEnrichment.addedPages | length' "$TMP/wp-build.json")" -eq 2 ] || { echo "addedPages not recorded"; exit 1; }

# --from-brief in a fresh copy
rm -rf "$TMP/.wp-pro-max/optimized" "$TMP/wp-build.json"
mkdir -p "$TMP/requirements" "$TMP/.wp-pro-max/optimized"
cp -R "$ROOT/examples/sample-site/"* "$TMP/.wp-pro-max/optimized/"
cat > "$TMP/requirements/brief.md" <<'EOF'
# Project brief

## Pages

- Contact: contact page with form and address
- Portfolio: portfolio showcase
EOF
cat > "$TMP/wp-build.json" <<'EOF'
{
  "version": "1",
  "project": { "name": "Test", "themeSlug": "test" },
  "strategy": "classic-acf",
  "source": { "briefPath": "./requirements/brief.md" },
  "analysis": { "pages": [{ "path": "index.html", "title": "Home", "role": "home", "sections": ["hero", "services"] }] },
  "optimization": { "outputDir": "./.wp-pro-max/optimized" },
  "contentModel": { "menus": [] },
  "progress": {},
  "siteEditor": {}
}
EOF

node "$ROOT/scripts/content-enrichment.mjs" "$TMP/wp-build.json" --from-brief
[ -f "$TMP/.wp-pro-max/optimized/contact.html" ] || { echo "brief contact.html missing"; exit 1; }
[ "$(jq '.siteEditor.contentEnrichment.addedPages | length' "$TMP/wp-build.json")" -eq 2 ] || { echo "brief addedPages not recorded"; exit 1; }

# --approve removes draft markers
node "$ROOT/scripts/content-enrichment.mjs" "$TMP/wp-build.json" --approve
[ "$(grep -c 'data-wp-pro-max="draft"' "$TMP/.wp-pro-max/optimized/contact.html")" -eq 0 ] || { echo "draft marker still present after approve"; exit 1; }

rm -rf "$TMP"
echo "Phase 5 TDD: PASS"
