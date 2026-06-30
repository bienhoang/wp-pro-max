#!/usr/bin/env bash
# plugin-data-payload.test.sh — assert the seed-plugin-data payload CONTRACT
# (pure JSON, same channel as content): acf entries (post→field→value), elementor
# entries (post→data tree) with a quote-bearing widget, consumable by the driver
# in ONE eval-file call. The _elementor_data round-trip, ACF `_<field>` fallback
# row, and zero-dup re-run are asserted in the LIVE run (live-acceptance covers
# the runtime; here we lock the host-observable payload shape).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$HERE/../../scripts" && pwd)"
PAYLOAD="$HERE/fixtures/plugin-data-payload.expected.json"

fails=0
ok()  { printf '  ok   - %s\n' "$1"; }
bad() { printf '  FAIL - %s\n' "$1"; fails=$((fails + 1)); }

echo "plugin-data-payload.test.sh"

jq -e . "$PAYLOAD" >/dev/null 2>&1 && ok "payload is valid JSON" || bad "payload is not valid JSON"
grep -q '<?php' "$PAYLOAD" && bad "payload contains a PHP tag (must be data-only)" || ok "payload has no PHP (data-only channel)"

# ACF section shape.
[ "$(jq -r '.acf | length' "$PAYLOAD")" -ge 1 ] && ok "acf[] present" || bad "acf[] missing"
[ "$(jq -r '.acf[0] | has("post") and has("field") and has("value")' "$PAYLOAD")" = "true" ] \
  && ok "acf entry has post/field/value" || bad "acf entry shape wrong"

# Elementor section: data is a JSON array (the layout tree), every element has an id.
[ "$(jq -r '.elementor[0].data | type' "$PAYLOAD")" = "array" ] \
  && ok "elementor data is a JSON array (not a PHP string)" || bad "elementor data not an array"
missing_ids="$(jq -r '[.elementor[0].data | .. | objects | select(has("elType")) | select((.id // "") == "")] | length' "$PAYLOAD")"
[ "$missing_ids" = "0" ] && ok "every elementor element carries an id" || bad "$missing_ids elements missing id"

# Quote-bearing widget content survives JSON round-trip (the classic footgun is
# PHP-literal escaping — gone now that the channel is JSON).
editor="$(jq -r '.elementor[0].data[0].elements[0].elements[0].settings.editor' "$PAYLOAD")"
case "$editor" in
  *'"here"'*'&'*"'apostrophes'"*) ok "quote/ampersand-bearing widget HTML preserved in JSON" ;;
  *) bad "widget HTML mangled: $editor" ;;
esac

# Driver consumes it in exactly ONE eval-file invocation (stub runtime).
sandbox="$(mktemp -d)"; work="$(mktemp -d)"
cat > "$sandbox/wp" <<EOF
#!/usr/bin/env bash
exec "$HERE/stub-wp.sh" "\$@"
EOF
chmod +x "$sandbox/wp"
printf '{"version":"1","seed":{}}\n' > "$work/wp-build.json"
(
  export PATH="$sandbox:/usr/bin:/bin"
  export SEED_TEST_LOG="$work/calls.log"; : > "$work/calls.log"
  export WP_BUILD_FILE="$work/wp-build.json"
  export WP_CLI_RUN="wp"
  bash "$SCRIPTS/seed-batch-run.sh" "$PAYLOAD" >/dev/null 2>&1
)
ev="$(grep -c '^eval-file' "$work/calls.log" 2>/dev/null || echo 0)"
[ "$ev" = "1" ] && ok "driver issued exactly one eval-file invocation" || bad "expected 1 eval-file call, got $ev"

rm -rf "$sandbox" "$work"
echo
[ "$fails" -eq 0 ] && { echo "plugin-data-payload.test.sh: PASS"; exit 0; } || { echo "plugin-data-payload.test.sh: $fails FAILED"; exit 1; }
