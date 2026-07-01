#!/usr/bin/env bash
# content-payload.test.sh — assert the seed-content payload CONTRACT that the
# content-seeding skill must emit: pure JSON (no PHP), the expected
# posts/menus/front-page, page bodies carried as JSON STRING values, and that the
# payload is consumable by the driver in exactly ONE eval-file invocation. Body
# EXTRACTION fidelity (HTML → body) and zero-dup are verified by the live wp-env
# run, not here (no PHP under `claude plugin validate`).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$HERE/../../scripts" && pwd)"
PAYLOAD="$HERE/fixtures/content-payload.expected.json"

fails=0
ok()  { printf '  ok   - %s\n' "$1"; }
bad() { printf '  FAIL - %s\n' "$1"; fails=$((fails + 1)); }

echo "content-payload.test.sh"

# 1. Pure JSON (no PHP) — must parse with jq, and contain no PHP open tag.
jq -e . "$PAYLOAD" >/dev/null 2>&1 && ok "payload is valid JSON" || bad "payload is not valid JSON"
grep -q '<?php' "$PAYLOAD" && bad "payload contains a PHP tag (must be data-only)" || ok "payload has no PHP (data-only channel)"

# 2. Required content sections present.
[ "$(jq -r '.posts | length' "$PAYLOAD")" -ge 1 ] && ok "posts[] present" || bad "posts[] missing"
[ "$(jq -r '[.posts[].slug] | index("home")' "$PAYLOAD")" != "null" ] && ok "home page in posts[]" || bad "home page missing"
[ "$(jq -r '.frontPage' "$PAYLOAD")" = "home" ] && ok "frontPage points at home" || bad "frontPage not set to home"
[ "$(jq -r '.menus[0].items | length' "$PAYLOAD")" -ge 1 ] && ok "menu items present" || bad "menu items missing"
[ "$(jq -r '.menus[0].location' "$PAYLOAD")" = "primary" ] && ok "menu bound to a theme location" || bad "menu location missing"

# 3. Page bodies are JSON STRING values (not PHP literals, not objects).
btype="$(jq -r '.posts[0].content | type' "$PAYLOAD")"
[ "$btype" = "string" ] && ok "page body is a JSON string value" || bad "page body type is $btype (expected string)"

# 4. Driver consumes it in exactly ONE eval-file invocation (stub runtime).
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
merged="$(jq -r '.seed.lastSummary.created // "none"' "$work/wp-build.json" 2>/dev/null)"
[ "$merged" != "none" ] && ok "summary merged into manifest after content run" || bad "summary not merged"

rm -rf "$sandbox" "$work"
echo
[ "$fails" -eq 0 ] && { echo "content-payload.test.sh: PASS"; exit 0; } || { echo "content-payload.test.sh: $fails FAILED"; exit 1; }
