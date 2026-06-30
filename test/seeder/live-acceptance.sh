#!/usr/bin/env bash
# live-acceptance.sh — the MANDATORY live wp-env gate for the seed batch runtime
# (red-team C6). It executes the real PHP runtime against a live WordPress and
# asserts the idempotency / zero-dup contract that the host stub tests CANNOT
# (no PHP runs under `claude plugin validate`). NOT named *.test.sh so the
# host-only run.sh skips it.
#
#   bash test/seeder/live-acceptance.sh [container]
#
# Defaults to this wp-env's dedicated `*-tests-cli-1` THROWAWAY container so the
# dev database is never touched. Requires Docker + a running wp-env.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME="$(cd "$HERE/../../scripts" && pwd)/seed-batch-runtime.php"
FIXTURE="$HERE/fixtures/live-content.json"

# Pick the tests container by default (throwaway); allow override.
CONTAINER="${1:-}"
if [ -z "$CONTAINER" ]; then
  CONTAINER="$(docker ps --format '{{.Names}}' | grep -E -- '-tests-cli-1$' | head -n1)"
fi
[ -n "$CONTAINER" ] || { echo "no tests-cli container found; pass one explicitly"; exit 2; }

fails=0
ok()  { printf '  ok   - %s\n' "$1"; }
bad() { printf '  FAIL - %s\n' "$1"; fails=$((fails + 1)); }

echo "live-acceptance.sh → container: $CONTAINER"
docker exec "$CONTAINER" wp option get siteurl >/dev/null 2>&1 || { echo "wp not reachable in $CONTAINER"; exit 2; }

RT=/tmp/seed-batch-runtime.live.php
docker cp "$RUNTIME" "$CONTAINER:$RT" >/dev/null

# Clean any leftovers from a previous run so the FIRST-run counts are meaningful.
cleanup() {
  docker exec "$CONTAINER" bash -c '
    for s in sbtest-home sbtest-about; do
      id=$(wp post list --post_type=page --name="$s" --post_status=any --field=ID 2>/dev/null | head -n1)
      [ -n "$id" ] && wp post delete "$id" --force >/dev/null 2>&1
    done
    mid=$(wp menu list --fields=term_id,name --format=csv 2>/dev/null | awk -F, "/SBTest Primary/{print \$1}")
    [ -n "$mid" ] && wp menu delete "$mid" >/dev/null 2>&1
    t=$(wp term list category --slug=sbtest-cat --field=term_id 2>/dev/null | head -n1)
    [ -n "$t" ] && wp term delete category "$t" >/dev/null 2>&1
    true
  ' >/dev/null 2>&1 || true
}

echo "  (cleaning any prior test rows)"
cleanup

# ---- 1. First run: correct creations -------------------------------------
# Stage the payload inside the container so eval-file reads it via a simple path.
docker cp "$FIXTURE" "$CONTAINER:/tmp/sb-live.json" >/dev/null
s1="$(docker exec -i "$CONTAINER" sh -c "wp eval-file $RT < /tmp/sb-live.json" 2>/dev/null | grep -o 'WPBUILD_SUMMARY.*WPBUILD_END' | head -n1)"
s1="${s1#WPBUILD_SUMMARY}"; s1="${s1%WPBUILD_END}"

c1="$(jq -r '.created' <<<"$s1" 2>/dev/null || echo '?')"
e1="$(jq -r '(.errors//[])|length' <<<"$s1" 2>/dev/null || echo '?')"
comp1="$(jq -r '.completed' <<<"$s1" 2>/dev/null || echo '?')"
echo "  first-run summary: $s1"
# 2 pages + 1 term + 1 menu + 2 post menu-items + 1 custom item = 7 creations.
[ "$c1" = "7" ] && ok "first run created 7 rows (2 pages, term, menu, 3 menu items)" \
  || bad "first run created=$c1 (expected 7)"
[ "$comp1" = "true" ] && ok "run marked completed" || bad "run not completed (completed=$comp1)"
[ "$e1" = "0" ] && ok "no errors on clean payload" || bad "unexpected errors=$e1"

# verify front page actually set
fp="$(docker exec "$CONTAINER" wp option get show_on_front 2>/dev/null | tr -d '\r')"
[ "$fp" = "page" ] && ok "front page switched to static" || bad "show_on_front=$fp (expected page)"

# ---- 2. Re-run: ZERO duplicates (the idempotency gate) -------------------
s2="$(docker exec -i "$CONTAINER" sh -c "wp eval-file $RT < /tmp/sb-live.json" 2>/dev/null | grep -o 'WPBUILD_SUMMARY.*WPBUILD_END' | head -n1)"
s2="${s2#WPBUILD_SUMMARY}"; s2="${s2%WPBUILD_END}"
c2="$(jq -r '.created' <<<"$s2" 2>/dev/null || echo '?')"
sk2="$(jq -r '.skipped' <<<"$s2" 2>/dev/null || echo '?')"
echo "  re-run summary: $s2"
[ "$c2" = "0" ] && ok "RE-RUN created:0 (zero duplicates — idempotency gate)" \
  || bad "re-run created=$c2 (expected 0 — DUPLICATES!)"
[ "${sk2:-0}" -gt 0 ] 2>/dev/null && ok "re-run skipped existing rows ($sk2)" || bad "re-run skipped=$sk2 (expected >0)"

# page count unchanged across the two runs
pc="$(docker exec "$CONTAINER" wp post list --post_type=page --post_status=any --name=sbtest-home --field=ID 2>/dev/null | wc -l | tr -d ' ')"
[ "$pc" = "1" ] && ok "exactly one sbtest-home page exists after two runs" || bad "found $pc sbtest-home pages (expected 1)"

# ---- 2b. Media import dedups by title across runs -------------------------
docker exec "$CONTAINER" bash -c '
  mkdir -p /tmp/wppm-media
  printf "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M8AAAMBAQDJ/pLvAAAAAElFTkSuQmCC" | base64 -d > /tmp/wppm-media/sbtestpic.png
  for id in $(wp post list --post_type=attachment --post_status=any --field=ID 2>/dev/null); do
    [ "$(wp post get $id --field=post_title 2>/dev/null)" = "sbtestpic" ] && wp post delete $id --force >/dev/null 2>&1
  done; true' >/dev/null 2>&1
MPAY='{"mediaPathPrefix":"/tmp/wppm-media/","media":[{"file":"sbtestpic.png","title":"sbtestpic"}]}'
mc1="$(printf '%s' "$MPAY" | docker exec -i "$CONTAINER" wp eval-file "$RT" 2>/dev/null | grep -o 'WPBUILD_SUMMARY.*WPBUILD_END')"; mc1="${mc1#WPBUILD_SUMMARY}"; mc1="${mc1%WPBUILD_END}"
[ "$(jq -r '.created' <<<"$mc1" 2>/dev/null)" = "1" ] && ok "media import created 1 attachment" || bad "media first import created=$(jq -r '.created' <<<"$mc1" 2>/dev/null)"
mc2="$(printf '%s' "$MPAY" | docker exec -i "$CONTAINER" wp eval-file "$RT" 2>/dev/null | grep -o 'WPBUILD_SUMMARY.*WPBUILD_END')"; mc2="${mc2#WPBUILD_SUMMARY}"; mc2="${mc2%WPBUILD_END}"
[ "$(jq -r '.created' <<<"$mc2" 2>/dev/null)" = "0" ] && ok "media RE-RUN created:0 (deduped by title)" || bad "media re-run created=$(jq -r '.created' <<<"$mc2" 2>/dev/null) (expected 0 — DUP!)"
napic="$(docker exec "$CONTAINER" bash -c 'wp post list --post_type=attachment --post_status=any --field=post_title 2>/dev/null | grep -c "^sbtestpic$"' | tr -d '\r')"
[ "$napic" = "1" ] && ok "exactly one sbtestpic attachment after two media runs" || bad "found $napic sbtestpic attachments (expected 1)"
docker exec "$CONTAINER" bash -c '
  for id in $(wp post list --post_type=attachment --post_status=any --field=ID 2>/dev/null); do
    [ "$(wp post get $id --field=post_title 2>/dev/null)" = "sbtestpic" ] && wp post delete $id --force >/dev/null 2>&1
  done; rm -rf /tmp/wppm-media; true' >/dev/null 2>&1

# ---- 3. Forced error lands in errors[] -----------------------------------
err_payload='{"media":[{"file":"does/not/exist.jpg","title":"sbtest-missing"}]}'
s3="$(printf '%s' "$err_payload" | docker exec -i "$CONTAINER" wp eval-file "$RT" 2>/dev/null | grep -o 'WPBUILD_SUMMARY.*WPBUILD_END' | head -n1)"
s3="${s3#WPBUILD_SUMMARY}"; s3="${s3%WPBUILD_END}"
e3="$(jq -r '(.errors//[])|length' <<<"$s3" 2>/dev/null || echo 0)"
echo "  forced-error summary: $s3"
[ "${e3:-0}" -ge 1 ] && ok "missing-media import surfaced in errors[] (no silent success)" \
  || bad "forced error not reported (errors=$e3)"

# ---- 4. Malformed / empty stdin → error summary + non-zero exit ----------
rc=0
out="$(printf '' | docker exec -i "$CONTAINER" wp eval-file "$RT" 2>/dev/null)" || rc=$?
echo "  empty-stdin output: $(printf '%s' "$out" | grep -o 'WPBUILD_SUMMARY.*WPBUILD_END' | head -n1)"
printf '%s' "$out" | grep -q 'WPBUILD_SUMMARY.*WPBUILD_END' && ok "empty stdin still emits a sentinel summary" \
  || bad "empty stdin produced no sentinel summary"
[ "$rc" != "0" ] && ok "empty stdin exits non-zero (rc=$rc)" || bad "empty stdin should exit non-zero (rc=$rc)"

# ---- 5. Fatal-safe: a mid-batch fatal still emits summary + partial keys ---
# Simulate a fatal that interrupts the batch AFTER partial work by injecting a
# throw at the seed_run call site (inside the runtime's Throwable catch) into a
# THROWAWAY copy — never the shipped file. The summary must still flush, marked
# completed:false, with the fatal captured and partial idempotencyKeys present.
cleanup   # clean DB so seed_run does real work before the fatal
docker cp "$FIXTURE" "$CONTAINER:/tmp/sb-live.json" >/dev/null
docker exec "$CONTAINER" sh -c \
  "sed 's/seed_run(\$payload);/seed_run(\$payload); throw new \\\\Error(\"simulated mid-batch fatal\");/' $RT > /tmp/sb-fatal.php"
s5="$(docker exec -i "$CONTAINER" sh -c 'wp eval-file /tmp/sb-fatal.php < /tmp/sb-live.json' 2>/dev/null | grep -o 'WPBUILD_SUMMARY.*WPBUILD_END' | head -n1)"
s5="${s5#WPBUILD_SUMMARY}"; s5="${s5%WPBUILD_END}"
comp5="$(jq -r '.completed' <<<"$s5" 2>/dev/null || echo '?')"
hasfatal="$(jq -r '(.errors//[])|map(select(test("fatal|simulated")))|length' <<<"$s5" 2>/dev/null || echo 0)"
nkeys5="$(jq -r '(.idempotencyKeys//[])|length' <<<"$s5" 2>/dev/null || echo 0)"
echo "  post-fatal summary: $s5"
printf '%s' "$s5" | grep -q '"created"' && ok "summary still emitted after a mid-batch fatal" \
  || bad "no summary emitted after fatal (lost run state)"
[ "$comp5" = "false" ] && ok "post-fatal summary marked completed:false" || bad "completed=$comp5 (expected false)"
[ "${hasfatal:-0}" -ge 1 ] && ok "the fatal was captured into errors[]" || bad "fatal not captured (count=$hasfatal)"
[ "${nkeys5:-0}" -ge 1 ] && ok "partial idempotencyKeys preserved across the fatal ($nkeys5)" \
  || bad "partial keys lost (count=$nkeys5)"

# ---- cleanup -------------------------------------------------------------
cleanup
docker exec "$CONTAINER" rm -f "$RT" /tmp/sb-live.json /tmp/sb-fatal.php >/dev/null 2>&1 || true

echo
[ "$fails" -eq 0 ] && { echo "live-acceptance.sh: PASS"; exit 0; } || { echo "live-acceptance.sh: $fails FAILED"; exit 1; }
