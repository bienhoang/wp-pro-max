#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FX="$(dirname "${BASH_SOURCE[0]}")"

echo "== Phase 2 TDD: shared helpers =="

# Syntax checks
echo "Syntax-checking shell scripts..."
bash -n "$ROOT/scripts/html-section-lib.sh"
bash -n "$ROOT/scripts/html-preview.sh"

echo "Syntax-checking Node scripts..."
node --check "$ROOT/scripts/pre-qa-a11y.mjs"
node --check "$ROOT/scripts/pre-qa-responsive.mjs"

# section_find
echo "Testing section_find..."
FOUND="$(source "$ROOT/scripts/html-section-lib.sh" && section_find "$FX/sample-section.html" "section.hero")"
[[ "$FOUND" == *"<h1>Original Hero</h1>"* ]] || { echo "section_find did not return hero"; exit 1; }

# section_replace
echo "Testing section_replace..."
TMP="$(mktemp -d)"
cp "$FX/sample-section.html" "$TMP/page.html"
cat > "$TMP/new-hero.html" <<'EOF'
<section class="hero">
  <h1>Replaced Hero</h1>
  <p>New hero copy.</p>
</section>
EOF
source "$ROOT/scripts/html-section-lib.sh" && section_replace "$TMP/page.html" "section.hero" "$TMP/new-hero.html"
[[ "$(cat "$TMP/page.html")" == *"<h1>Replaced Hero</h1>"* ]] || { echo "section_replace did not inject new hero"; exit 1; }
[[ "$(cat "$TMP/page.html")" != *"Original Hero"* ]] || { echo "section_replace left old hero"; exit 1; }

# section_insert_before
echo "Testing section_insert_before..."
cp "$FX/sample-section.html" "$TMP/page2.html"
cat > "$TMP/announcement.html" <<'EOF'
<section class="announcement"><p>Announcement</p></section>
EOF
source "$ROOT/scripts/html-section-lib.sh" && section_insert_before "$TMP/page2.html" "section.hero" "$TMP/announcement.html"
[[ "$(cat "$TMP/page2.html")" == *"<section class=\"announcement\">"* ]] || { echo "section_insert_before did not insert"; exit 1; }

# section_remove
echo "Testing section_remove..."
cp "$FX/sample-section.html" "$TMP/page3.html"
source "$ROOT/scripts/html-section-lib.sh" && section_remove "$TMP/page3.html" "section.services"
[[ "$(cat "$TMP/page3.html")" != *"Our services section."* ]] || { echo "section_remove left services"; exit 1; }

# pre-qa-a11y dirty
echo "Testing pre-qa-a11y on invalid fixture..."
node "$ROOT/scripts/pre-qa-a11y.mjs" "$FX/sample-invalid.html" > "$TMP/a11y.json" || true
[ "$(jq -r '.passed' "$TMP/a11y.json")" = "false" ] || { echo "expected invalid fixture to fail a11y"; exit 1; }

# pre-qa-a11y clean
echo "Testing pre-qa-a11y on clean fixture..."
node "$ROOT/scripts/pre-qa-a11y.mjs" "$FX/sample-section.html" > "$TMP/a11y-clean.json"
[ "$(jq -r '.passed' "$TMP/a11y-clean.json")" = "true" ] || { echo "expected clean fixture to pass a11y"; cat "$TMP/a11y-clean.json"; exit 1; }

rm -rf "$TMP"
echo "Phase 2 TDD: PASS"
