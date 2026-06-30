#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCHEMA="$ROOT/schemas/wp-build.schema.json"
FIXTURE="$(dirname "${BASH_SOURCE[0]}")/site-editor-manifest.json"

echo "== Phase 1 TDD: schema contract =="

# 1) Schema must define a top-level siteEditor property with the three sub-trees.
echo "Checking schema defines siteEditor..."
jq -e '.properties.siteEditor
  and .properties.siteEditor.properties.redesign
  and .properties.siteEditor.properties.contentEnrichment
  and .properties.siteEditor.properties.preConversionQa' "$SCHEMA" >/dev/null

# 2) siteEditor must NOT be required (backward compatible).
echo "Checking siteEditor is not required..."
jq -e '(.required | index("siteEditor")) == null' "$SCHEMA" >/dev/null

# 3) Fixture must validate against the schema.
echo "Validating fixture with ajv..."
npx --yes ajv-cli@5 validate -s "$SCHEMA" -d "$FIXTURE" >/dev/null

echo "Phase 1 TDD: PASS"
