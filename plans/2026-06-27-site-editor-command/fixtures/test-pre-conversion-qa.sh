#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

echo "== Phase 6 TDD: pre-conversion-qa skill mechanics =="

# Dirty fixture should fail a11y/validity
DIRTY="$ROOT/plans/2026-06-27-site-editor-command/fixtures/sample-invalid.html"
node "$ROOT/scripts/pre-qa-a11y.mjs" "$DIRTY" > /tmp/pre-qa-a11y-dirty.json || true
[ "$(jq -r '.passed' /tmp/pre-qa-a11y-dirty.json)" = "false" ] || { echo "expected dirty a11y to fail"; exit 1; }

node "$ROOT/scripts/pre-qa-html-validity.mjs" "$DIRTY" > /tmp/pre-qa-valid-dirty.json || true
[ "$(jq -r '.passed' /tmp/pre-qa-valid-dirty.json)" = "false" ] || { echo "expected dirty validity to fail"; exit 1; }

# Clean fixture should pass
CLEAN="$ROOT/plans/2026-06-27-site-editor-command/fixtures/sample-section.html"
node "$ROOT/scripts/pre-qa-a11y.mjs" "$CLEAN" > /tmp/pre-qa-a11y-clean.json
[ "$(jq -r '.passed' /tmp/pre-qa-a11y-clean.json)" = "true" ] || { echo "expected clean a11y to pass"; exit 1; }

node "$ROOT/scripts/pre-qa-html-validity.mjs" "$CLEAN" > /tmp/pre-qa-valid-clean.json
[ "$(jq -r '.passed' /tmp/pre-qa-valid-clean.json)" = "true" ] || { echo "expected clean validity to pass"; exit 1; }

# Brand check with tokens
cat > /tmp/tokens.json <<'EOF'
{
  "colors": [{ "name": "brand", "value": "#0f766e" }],
  "fonts": [{ "name": "body", "family": "Inter, sans-serif" }]
}
EOF

cat > /tmp/brand-dirty.html <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head><title>Brand dirty</title><meta charset="UTF-8"></head>
<body>
  <main><p style="color: #ff00ff; background-color: #00ff00; font-family: Comic Sans;">x</p></main>
</body>
</html>
EOF

node "$ROOT/scripts/pre-qa-brand.mjs" /tmp/brand-dirty.html --tokens /tmp/tokens.json > /tmp/pre-qa-brand-dirty.json || true
[ "$(jq -r '.passed' /tmp/pre-qa-brand-dirty.json)" = "false" ] || { echo "expected brand dirty to fail"; exit 1; }

cat > /tmp/brand-clean.html <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head><title>Brand clean</title><meta charset="UTF-8"></head>
<body>
  <main><p style="color: #0f766e; font-family: Inter, sans-serif;">x</p></main>
</body>
</html>
EOF

node "$ROOT/scripts/pre-qa-brand.mjs" /tmp/brand-clean.html --tokens /tmp/tokens.json > /tmp/pre-qa-brand-clean.json
[ "$(jq -r '.passed' /tmp/pre-qa-brand-clean.json)" = "true" ] || { echo "expected brand clean to pass"; cat /tmp/pre-qa-brand-clean.json; exit 1; }

# Responsive check (thorough) on clean fixture
node "$ROOT/scripts/pre-qa-responsive.mjs" "$CLEAN" > /tmp/pre-qa-resp.json || true
[ "$(jq -r '.passed' /tmp/pre-qa-resp.json)" = "true" ] || { echo "responsive check failed unexpectedly"; cat /tmp/pre-qa-resp.json; exit 1; }
[ "$(jq '.viewports | length' /tmp/pre-qa-resp.json)" -eq 3 ] || { echo "expected 3 viewports"; exit 1; }

echo "Phase 6 TDD: PASS"
