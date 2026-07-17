#!/usr/bin/env bash
# wp-fix.test.sh — behavioral assertions for scripts/wp-fix-lib.sh.
#
# Every invariant here is one that can silently corrupt a user's project if it
# regresses. Each test is written to FAIL without its fix, not merely to pass.
#
# Fixture strategy (mirrors test/seeder/content-payload.test.sh:36): the finding
# INPUT is a committed static JSON fixture; the project tree — wp-build.json and
# the intentionally-vulnerable PHP — is built in an mktemp sandbox at runtime and
# torn down on exit. CLAUDE.md forbids writing wp-build.json or WordPress output
# into this repo, and test/run.sh's walk() does not prune test/, so a committed
# .php fixture would be swept into check_php_lint.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_REPO="$(cd "$HERE/.." && pwd)"
LIB="$ROOT_REPO/scripts/wp-fix-lib.sh"
FIXTURE="$HERE/wp-fix/fixtures/findings.sample.json"

fails=0
ok()  { printf '  ok   - %s\n' "$1"; }
bad() { printf '  FAIL - %s\n' "$1"; fails=$((fails + 1)); }

echo "wp-fix.test.sh"

command -v jq >/dev/null 2>&1 || { echo "  SKIP - jq required"; exit 0; }
[ -f "$FIXTURE" ] || { bad "fixture missing: $FIXTURE"; exit 1; }

# --- sandbox ------------------------------------------------------------------
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
SB="$(cd "$sandbox" && pwd -P)"

mkdir -p "$SB/themes/acme" "$SB/plugins/woocommerce"

# Intentionally-vulnerable PHP — sandbox only, never committed.
printf '%s\n' '<?php' 'get_header();' '?>' '<div>' '<?php' '// line 8 below' 'echo $_GET["q"];' > "$SB/themes/acme/header.php"
printf '%s\n' '<?php' '// escaped via a theme helper — Gate 1 must dismiss this' 'function acme_out($v) { return esc_html($v); }' 'echo acme_out($_GET["q"]);' > "$SB/themes/acme/footer.php"
: > "$SB/themes/acme/page.php"
for i in $(seq 1 50); do echo "// line $i" >> "$SB/themes/acme/page.php"; done

# wp-build.json — sandbox only. __ROOT__ becomes the sandbox's physical path,
# matching audit-static.sh:41 which always emits absolute host paths.
jq --arg root "$SB" '{
  version: "1",
  project: {name: "t", themeSlug: "acme", textDomain: "acme"},
  strategy: "classic-acf",
  theme: {path: "themes/acme"},
  progress: {},
  audit: {
    generatedAt: "2026-07-17T00:00:00Z",
    mode: "static",
    findings: [ .findings[] | del(._case) | .file |= (. | sub("__ROOT__"; $root)) ]
  }
}' "$FIXTURE" > "$SB/wp-build.json"

export WP_BUILD_FILE="$SB/wp-build.json"
# shellcheck source=../scripts/wp-fix-lib.sh
source "$LIB"
FIX_PROJECT_ROOT="$SB"

# =============================================================================
# Rule-set drift guard: FIX_SUPPORTED_RULES must equal what audit-static.sh emits
# =============================================================================
# If someone adds a rule to the scanner and not here, its findings silently land
# in unsupported[] forever. If someone adds one here that the scanner cannot
# produce, fix triages a finding that will never appear.
scanner_ids="$(
  awk '/^IDS=\(/{f=1;next} f&&/^\)/{f=0} f{gsub(/[[:space:]]/,"");if($0!="")print}' \
    "$ROOT_REPO/scripts/audit-static.sh"
  grep -oE 'add_static_finding "wpcs-missing-nonce"' "$ROOT_REPO/scripts/audit-static.sh" \
    | sed 's/.*"\(.*\)"/\1/'
)"
lib_ids="$(jq -r '.[]' <<<"$FIX_SUPPORTED_RULES_JSON" | sort)"
if [ "$(sort <<<"$scanner_ids")" = "$lib_ids" ]; then
  ok "FIX_SUPPORTED_RULES matches audit-static.sh's rule ids exactly (no drift)"
else
  bad "rule-set drift vs audit-static.sh: $(comm -3 <(sort <<<"$scanner_ids") <(echo "$lib_ids") | tr '\n' ' ')"
fi
[ "$(jq 'length' <<<"$FIX_SUPPORTED_RULES_JSON")" -eq 9 ] \
  && ok "FIX_SUPPORTED_RULES holds exactly 9 rules" \
  || bad "expected 9 supported rules, got $(jq 'length' <<<"$FIX_SUPPORTED_RULES_JSON")"

# No category-keyed policy anywhere in the lib (Red Team #1: XSS/SQLi/CSRF are
# category `code-style`, so keying on category puts them on the wrong lane).
if grep -qE 'fix_is_auto|auto[_-]lane|auto-fix' "$LIB"; then
  bad "lib contains an auto-fix lane — v1 is propose-only"
else
  ok "no auto-fix lane in the lib (propose-only)"
fi

# =============================================================================
# Invariant 1: PARTITION — nothing dropped, everything routed
# =============================================================================
fix_parse_args
part="$(fix_load_findings)" || bad "fix_load_findings failed"

sup_n="$(jq '.supported   | length' <<<"$part")"
uns_n="$(jq '.unsupported | length' <<<"$part")"
skp_n="$(jq '.skipped     | length' <<<"$part")"
tot_in="$(jq '.audit.findings | length' "$WP_BUILD_FILE")"

[ "$((sup_n + uns_n + skp_n))" -eq "$tot_in" ] \
  && ok "partition is total: supported+unsupported+skipped == $tot_in input findings (none dropped)" \
  || bad "partition loses findings: $sup_n+$uns_n+$skp_n != $tot_in"

# The 5 fixture findings that are genuinely fixable.
for id in wpcs-output-not-escaped wpcs-missing-sanitize wpcs-direct-db-no-prepare sec-base64-decode; do
  jq -e --arg i "$id" 'any(.supported[]; .id == $i)' <<<"$part" >/dev/null \
    && ok "supported: $id" || bad "supported bucket missing $id"
done

# Everything with line:0, a URL/plugin file, external:true, or an unknown id.
for id in a11y-imgAlt perf-lcp-high sec-live-plugin-contact-form-7 sec-eval sec-committed-secret; do
  jq -e --arg i "$id" 'any(.unsupported[]; .id == $i)' <<<"$part" >/dev/null \
    && ok "unsupported: $id" || bad "$id should be unsupported"
done

# a11y must NEVER be treated as fixable — line:0 gives no anchor.
jq -e 'any(.supported[]; .category == "a11y")' <<<"$part" >/dev/null \
  && bad "an a11y finding reached supported[] — it has no line anchor" \
  || ok "no a11y finding in supported[] (line:0 has no anchor)"

# external:true must never be edited.
jq -e 'any(.supported[]; .external == true)' <<<"$part" >/dev/null \
  && bad "an external:true finding reached supported[] — third-party code" \
  || ok "no external:true finding in supported[] (third-party)"

# Every unsupported finding is routed somewhere. This is the "never silently
# dropped" guarantee.
jq -e 'all(.unsupported[]; (.pointer // "") != "" and (.reason // "") != "")' <<<"$part" >/dev/null \
  && ok "every unsupported finding carries both a reason and a skill pointer" \
  || bad "an unsupported finding has no reason/pointer — it would be silently dropped"

jq -e 'any(.unsupported[]; .id == "a11y-imgAlt" and (.pointer | test("accessibility")))' <<<"$part" >/dev/null \
  && ok "a11y findings point at the accessibility skill" || bad "a11y pointer wrong"
jq -e 'any(.unsupported[]; .id == "perf-lcp-high" and (.pointer | test("performance")))' <<<"$part" >/dev/null \
  && ok "perf findings point at wp-performance-backend" || bad "perf pointer wrong"

# =============================================================================
# Invariant 8: no host paths, no secrets
# =============================================================================
grep -q '/Users/' <<<"$part" && bad "partition leaks a /Users/ host path" \
  || ok "partition emits no /Users/ host path"
jq -e 'any(.supported[]; .file | startswith("/"))' <<<"$part" >/dev/null \
  && bad "supported[] holds an absolute path — the manifest key would be machine-bound" \
  || ok "supported[] paths are all repo-relative"
jq -e 'any(.supported[]; .file == "themes/acme/header.php")' <<<"$part" >/dev/null \
  && ok "absolute finding path relativised to themes/acme/header.php" \
  || bad "rel-path did not strip the project root"

# Live findings keep their URL / plugin-slug form untouched (they are not paths).
jq -e 'any(.unsupported[]; .id == "perf-lcp-high" and .file == "http://localhost:8888/")' <<<"$part" >/dev/null \
  && ok "live URL passes through rel-path untouched" || bad "live URL was mangled"

# =============================================================================
# Invariant 4: LINE-DESCENDING within a file
# =============================================================================
# page.php carries findings at 10 and 42. Fixing 10 first shifts the file's line
# count, leaving 42 pointing at unrelated code.
lines="$(fix_group_by_file "$part" | jq -c '.[] | select(.file == "themes/acme/page.php") | [.findings[].line]')"
[ "$lines" = "[42,10]" ] \
  && ok "fix_group_by_file returns page.php line-descending [42,10]" \
  || bad "expected [42,10], got $lines — lower-line-first invalidates higher line refs"

# =============================================================================
# Invariant 2: no write without approval
# =============================================================================
# The read/triage path must never touch the tree; only an approved edit does.
before="$(find "$SB/themes" -type f -exec shasum {} \; | shasum)"
fix_load_findings >/dev/null; fix_group_by_file >/dev/null; fix_parse_args --dry-run
after="$(find "$SB/themes" -type f -exec shasum {} \; | shasum)"
[ "$before" = "$after" ] \
  && ok "load/triage/--dry-run leave the source tree byte-identical" \
  || bad "the read path mutated source files"
[ "$FIX_DRY_RUN" = "1" ] && ok "--dry-run sets FIX_DRY_RUN=1" || bad "--dry-run not parsed"

# =============================================================================
# Invariant 3: BACKUP precedes write
# =============================================================================
fix_parse_args
fix_backup_dir_init >/dev/null
[ -d "$FIX_BACKUP_DIR" ] && ok "fix_backup_dir_init creates the backup dir" || bad "no backup dir"

orig="$(cat "$SB/themes/acme/header.php")"
fix_backup "$SB/themes/acme/header.php" >/dev/null || bad "fix_backup failed"
[ -f "$FIX_BACKUP_DIR/themes/acme/header.php" ] \
  && ok "fix_backup stores the file under its relative path" || bad "backup missing"
[ "$(cat "$FIX_BACKUP_DIR/themes/acme/header.php")" = "$orig" ] \
  && ok "backup content matches the pre-edit original" || bad "backup content differs"

# Basename collision: two themes, same filename. A basename-keyed backup (the
# section_backup shape) would overwrite the first and silently lose it.
mkdir -p "$SB/themes/other"
echo '<?php echo "other";' > "$SB/themes/other/header.php"
fix_backup "$SB/themes/other/header.php" >/dev/null
n_backups="$(find "$FIX_BACKUP_DIR" -name header.php -type f | wc -l | tr -d ' ')"
[ "$n_backups" -eq 2 ] \
  && ok "two same-named files in different dirs both keep a backup (no collision)" \
  || bad "backup collision: only $n_backups of 2 header.php survived"

# Restore round-trip — the "revert that file" promise needs a real snapshot.
echo 'CLOBBERED' > "$SB/themes/acme/header.php"
fix_restore "$SB/themes/acme/header.php" >/dev/null
[ "$(cat "$SB/themes/acme/header.php")" = "$orig" ] \
  && ok "fix_restore restores the exact pre-edit bytes" || bad "restore did not round-trip"

# Backing up a file that does not exist must fail loudly, not silently no-op.
fix_backup "$SB/themes/acme/nope.php" >/dev/null 2>&1 \
  && bad "fix_backup succeeded on a missing file" || ok "fix_backup fails loudly on a missing file"

# =============================================================================
# Argument parsing
# =============================================================================
fix_parse_args "trắng trang sau khi activate theme"
[ "$FIX_FREE_TEXT" = "trắng trang sau khi activate theme" ] \
  && ok "multi-word free-text survives whole (no word-splitting)" \
  || bad "free-text was split: [$FIX_FREE_TEXT]"

fix_parse_args '$(whoami)'
[ "$FIX_FREE_TEXT" = '$(whoami)' ] \
  && ok "\$( ) in free-text is kept literal, never evaluated" \
  || bad "command substitution leaked: [$FIX_FREE_TEXT]"

fix_parse_args --severity high && [ "$FIX_SEVERITY" = "high" ] \
  && ok "--severity high parses" || bad "--severity failed"
fix_parse_args --bogus 2>/dev/null; [ $? -eq 2 ] \
  && ok "unknown flag returns 2" || bad "unknown flag did not return 2"
fix_parse_args --severity 2>/dev/null; [ $? -eq 2 ] \
  && ok "--severity with no value returns 2" || bad "missing value not caught"
# a11y/performance are not fixable in v1 — accepting them would advertise a run
# that returns nothing but unsupported[].
fix_parse_args --category a11y 2>/dev/null; [ $? -eq 2 ] \
  && ok "--category a11y rejected (not fixable in v1)" || bad "--category a11y should be rejected"

# Severity is a THRESHOLD: --severity high keeps critical+high, drops medium.
fix_parse_args --severity high
p2="$(fix_load_findings)"
jq -e 'any(.supported[]; .id == "sec-base64-decode")' <<<"$p2" >/dev/null \
  && bad "--severity high kept a medium finding" \
  || ok "--severity high filters the medium finding into skipped[]"
jq -e 'any(.skipped[]; .id == "sec-base64-decode")' <<<"$p2" >/dev/null \
  && ok "filtered findings land in skipped[], not dropped" || bad "filtered finding vanished"

fix_parse_args --category security
jq -e 'all(.supported[]; .category == "security")' <<<"$(fix_load_findings)" >/dev/null \
  && ok "--category security narrows to security findings" || bad "--category filter failed"

# =============================================================================
# Invariants 5/6/7: GATE 3 — verification by static re-scan
# =============================================================================
fix_parse_args
cat > "$SB/base.json" <<'EOF'
{"findings":[
  {"id":"wpcs-output-not-escaped","file":"themes/acme/header.php","line":8},
  {"id":"sec-base64-decode","file":"themes/acme/functions.php","line":12}
]}
EOF

# 7 — a `mode: live` baseline: live findings can NEVER be reproduced by a static
# re-scan, so unfiltered they all read as "gone" -> verified:true having fixed
# nothing.
cat > "$SB/base-live.json" <<'EOF'
{"findings":[
  {"id":"perf-lcp-high","file":"http://localhost:8888/","line":0},
  {"id":"sec-live-plugin-contact-form-7","file":"plugin/contact-form-7","line":0},
  {"id":"a11y-axe-color-contrast","file":"http://localhost:8888/","line":0},
  {"id":"wpcs-output-not-escaped","file":"themes/acme/header.php","line":8}
]}
EOF
echo '{"findings":[]}' > "$SB/post-empty.json"
v7="$(fix_verify_diff "$SB/base-live.json" "$SB/post-empty.json" '["themes/acme/header.php"]')"
[ "$(jq -r '[.resolved[].id] | join(",")' <<<"$v7")" = "wpcs-output-not-escaped" ] \
  && ok "Gate 3 counts only static findings as resolved; live ones are excluded" \
  || bad "Gate 3 counted live findings as resolved: $(jq -c '[.resolved[].id]' <<<"$v7")"
jq -e 'any(.resolved[]; (.id | startswith("perf-")) or (.id | startswith("sec-live-")) or (.id | startswith("a11y-axe-")))' <<<"$v7" >/dev/null \
  && bad "a live finding was reported 'gone' by a static re-scan" \
  || ok "no live finding claimed as fixed by a static scan"

# 6 — scanner failure must never read as success. audit-static.sh swallows errors
# (|| true at :232, || echo '{}' at :272) and degrades to an empty set with exit
# 0, which otherwise satisfies "targeted gone AND nothing new" perfectly.
v6="$(fix_verify_diff "$SB/base.json" "$SB/post-empty.json" '["themes/acme/header.php"]')"
[ "$(jq -r '.status' <<<"$v6")" = "scanner-failed" ] && [ "$(jq -r '.verified' <<<"$v6")" = "false" ] \
  && ok "empty post-scan with findings in untouched files => scanner-failed, verified:false" \
  || bad "scanner failure reported as $(jq -r '.status' <<<"$v6") — a false PASS"

echo 'not json at all' > "$SB/post-broken.json"
v6b="$(fix_verify_diff "$SB/base.json" "$SB/post-broken.json" '["themes/acme/header.php"]')"
[ "$(jq -r '.verified' <<<"$v6b")" = "false" ] \
  && ok "unparseable post-scan => verified:false" || bad "unparseable scan reported verified"

v6c="$(fix_verify_diff "$SB/base.json" "$SB/does-not-exist.json" '[]' 2>/dev/null)"
[ "$(jq -r '.verified' <<<"$v6c")" = "false" ] \
  && ok "missing post-scan file => verified:false" || bad "missing scan file reported verified"

# 5 — a new finding introduced by the fix (e.g. a double-escape) must fail the
# gate, not pass because the targeted one is gone.
cat > "$SB/post-new.json" <<'EOF'
{"findings":[{"id":"wpcs-missing-sanitize","file":"themes/acme/header.php","line":8}]}
EOF
v5="$(fix_verify_diff "$SB/base.json" "$SB/post-new.json" '["themes/acme/header.php","themes/acme/functions.php"]')"
[ "$(jq -r '.status' <<<"$v5")" = "fail" ] \
  && ok "a NEW static finding introduced by the fix fails Gate 3" \
  || bad "new finding did not fail the gate: $(jq -c . <<<"$v5")"

# A grown count at the same id+file is also a regression.
cat > "$SB/post-grown.json" <<'EOF'
{"findings":[
  {"id":"wpcs-output-not-escaped","file":"themes/acme/header.php","line":8},
  {"id":"wpcs-output-not-escaped","file":"themes/acme/header.php","line":9},
  {"id":"sec-base64-decode","file":"themes/acme/functions.php","line":12}
]}
EOF
v5b="$(fix_verify_diff "$SB/base.json" "$SB/post-grown.json" '["themes/acme/header.php"]')"
[ "$(jq -r '.status' <<<"$v5b")" = "fail" ] \
  && ok "a grown finding count at one id+file fails Gate 3" || bad "count growth not caught"

# Clean pass: the targeted finding is gone, the untouched one is still there.
cat > "$SB/post-good.json" <<'EOF'
{"findings":[{"id":"sec-base64-decode","file":"themes/acme/functions.php","line":12}]}
EOF
v_ok="$(fix_verify_diff "$SB/base.json" "$SB/post-good.json" '["themes/acme/header.php"]')"
[ "$(jq -r '.status' <<<"$v_ok")" = "pass" ] && [ "$(jq -r '.verified' <<<"$v_ok")" = "true" ] \
  && ok "clean fix => status:pass, verified:true" || bad "clean fix did not pass: $(jq -c . <<<"$v_ok")"
[ "$(jq -r '[.stillPresent[].id] | join(",")' <<<"$v_ok")" = "sec-base64-decode" ] \
  && ok "an untouched baseline finding is reported stillPresent, not resolved" \
  || bad "untouched finding mis-reported"

# =============================================================================
# Per-rule expectation: presence rules vs clearing rules
# =============================================================================
# audit-static.sh greps for risky CONSTRUCTS, not defects. Verified empirically:
# sanitize_text_field(wp_unslash($_GET['q'])) still matches `\$_(GET|…)`, and
# $wpdb->query($wpdb->prepare(…)) still matches `\$wpdb->query\(.*\$`. Only
# sec-eval (fix deletes the construct) and wpcs-missing-nonce (an absence check)
# can be expected to clear. Requiring the other seven to vanish would fail the
# majority of CORRECT fixes and train the user to ignore the gate.
[ "$(jq -r 'sort | join(",")' <<<"$FIX_CLEARING_RULES_JSON")" = "sec-eval,wpcs-missing-nonce" ] \
  && ok "FIX_CLEARING_RULES holds exactly the 2 rules whose fix removes the construct" \
  || bad "clearing-rule set drifted: $FIX_CLEARING_RULES_JSON"

# A correctly fixed PRESENCE rule still matches -> stillFlagged, NOT a failure.
cat > "$SB/base-presence.json" <<'EOF'
{"findings":[{"id":"wpcs-missing-sanitize","file":"themes/acme/header.php","line":8}]}
EOF
v_pres="$(fix_verify_diff "$SB/base-presence.json" "$SB/base-presence.json" '["themes/acme/header.php"]')"
[ "$(jq -r '.verified' <<<"$v_pres")" = "true" ] \
  && ok "a correctly fixed presence rule that still matches does NOT fail the gate" \
  || bad "presence rule still matching wrongly failed the gate — 7/9 correct fixes would report failure"
[ "$(jq -r '[.stillFlagged[].id] | join(",")' <<<"$v_pres")" = "wpcs-missing-sanitize" ] \
  && ok "presence rule reported as stillFlagged with an explanation" \
  || bad "presence rule not reported as stillFlagged"
jq -e '.stillFlagged[0].note | test("presence rule")' <<<"$v_pres" >/dev/null \
  && ok "stillFlagged carries the 'why this is expected' note" || bad "stillFlagged note missing"

# A CLEARING rule that did NOT clear means the fix did not work -> FAIL.
cat > "$SB/base-clearing.json" <<'EOF'
{"findings":[{"id":"sec-eval","file":"themes/acme/legacy.php","line":5}]}
EOF
v_clear="$(fix_verify_diff "$SB/base-clearing.json" "$SB/base-clearing.json" '["themes/acme/legacy.php"]')"
[ "$(jq -r '.status' <<<"$v_clear")" = "fail" ] && [ "$(jq -r '.verified' <<<"$v_clear")" = "false" ] \
  && ok "a targeted clearing rule that did NOT clear fails the gate" \
  || bad "sec-eval still present after being targeted should fail: $(jq -c . <<<"$v_clear")"
[ "$(jq -r '[.unresolved[].id] | join(",")' <<<"$v_clear")" = "sec-eval" ] \
  && ok "the un-cleared clearing rule is named in unresolved[]" || bad "unresolved[] wrong"

# A clearing rule that DID clear -> resolved, pass.
echo '{"findings":[]}' > "$SB/post-cleared.json"
v_done="$(fix_verify_diff "$SB/base-clearing.json" "$SB/post-cleared.json" '["themes/acme/legacy.php"]')"
[ "$(jq -r '.status' <<<"$v_done")" = "pass" ] \
  && ok "a cleared clearing rule passes the gate" || bad "cleared rule did not pass"
[ "$(jq -r '[.resolved[].id] | join(",")' <<<"$v_done")" = "sec-eval" ] \
  && ok "the cleared rule is named in resolved[]" || bad "resolved[] wrong"

# =============================================================================
# Invariant 8 (cont.): manifest writes — secrets and paths
# =============================================================================
fix_init "audit:2026-07-17T00:00:00Z"
fix_record addressed '{"id":"wpcs-output-not-escaped","file":"themes/acme/header.php","line":8,"action":"wrapped in esc_html()"}'
fix_record addressed '{"id":"wpcs-output-not-escaped","file":"themes/acme/header.php","line":8,"action":"wrapped in esc_html()"}'
fix_record dismissed '{"id":"wpcs-output-not-escaped","file":"themes/acme/footer.php","line":6,"reason":"escaped via acme_out() helper"}'
fix_record runtimeChanges '{"cmd":"option update","option":"permalink_structure"}'

[ "$(jq '.fix.addressed | length' "$WP_BUILD_FILE")" -eq 1 ] \
  && ok "fix_record appends and uniques (duplicate collapsed)" || bad "duplicate not collapsed"
[ "$(jq -r '.fix.verified' "$WP_BUILD_FILE")" = "false" ] \
  && ok "fix.verified starts false — success is proven, not assumed" || bad "fix.verified not false at init"

jq -e '.fix.runtimeChanges[] | has("before") or has("after") or has("value")' "$WP_BUILD_FILE" >/dev/null 2>&1 \
  && bad "runtimeChanges records an option VALUE — option values hold credentials and wp-build.json is committed" \
  || ok "runtimeChanges records the option name only, never its value"

jq -c '.fix' "$WP_BUILD_FILE" | grep -q '/Users/\|/private/var\|/var/folders' \
  && bad "fix.* leaks an absolute host path" || ok "fix.* holds no absolute host path"

fix_record bogus '{}' 2>/dev/null; [ $? -eq 2 ] \
  && ok "fix_record rejects an unknown bucket" || bad "unknown bucket accepted"

# Stage id must be canonical, else contract-lint Rule 2 fails on the skill.
wpbuild_progress fix in-progress "test" 2>/dev/null
[ "$(jq -r '.progress.fix.status' "$WP_BUILD_FILE")" = "in-progress" ] \
  && ok "wpbuild_progress fix records stage state (resumable)" || bad "progress fix failed"

# =============================================================================
# END-TO-END: real tree -> real audit-static.sh -> fix_static_rescan -> fix_verify
# =============================================================================
# The Gate 3 tests above hand-write both sides of the diff. That cannot catch a
# mismatch between what the REAL scanner emits and what the diff expects — and it
# didn't: fix_static_rescan returned absolute paths (audit-static.sh:41) while the
# baseline and fix.filesChanged are repo-relative, so findings shared no keys and
# a still-present sec-eval came back {resolved AND new}, unresolved:[]. This block
# exercises the seam the unit tests cannot.
e2e="$(mktemp -d)"
trap 'rm -rf "$sandbox" "$e2e"' EXIT
E2E="$(cd "$e2e" && pwd -P)"
mkdir -p "$E2E/wp-content/themes/acme"
printf '<?php\neval( $code );\n'      > "$E2E/wp-content/themes/acme/legacy.php"
printf '<?php\necho $_GET["q"];\n'    > "$E2E/wp-content/themes/acme/header.php"
printf '<?php\n$x = base64_decode( $d );\n' > "$E2E/wp-content/themes/acme/untouched.php"
echo '{"version":"1","project":{"name":"a","themeSlug":"acme","textDomain":"acme"},"strategy":"classic-acf","theme":{"path":"wp-content/themes/acme"},"progress":{}}' > "$E2E/wp-build.json"

if bash "$ROOT_REPO/scripts/audit-static.sh" "$E2E" "wp-content/themes/acme" self "$E2E/audit" >/dev/null 2>&1; then
  jq -s '{findings:(map(.findings//[])|add)}' "$E2E"/audit/{code-style,a11y,security}.json > "$E2E/raw.json"
  jq --argjson f "$(cat "$E2E/raw.json")" \
     '.audit={generatedAt:"2026-07-17T08:00:00Z",mode:"static",scope:"self",findings:$f.findings}' \
     "$E2E/wp-build.json" > "$E2E/t" && mv "$E2E/t" "$E2E/wp-build.json"

  WP_BUILD_FILE="$E2E/wp-build.json"
  FIX_PROJECT_ROOT="$E2E"
  unset FIX_SCAN_SCOPE
  fix_parse_args

  # Both producers must speak ONE path space, or the diff is meaningless.
  rescan_paths="$(fix_static_rescan "$E2E/rescan" | jq -r '.findings[].file')"
  if printf '%s' "$rescan_paths" | grep -q '^/'; then
    bad "fix_static_rescan emits ABSOLUTE paths — cannot diff against a repo-relative baseline"
  else
    ok "fix_static_rescan emits repo-relative paths (same space as the baseline)"
  fi
  fix_baseline | jq -e 'all(.findings[]; .file | startswith("/") | not)' >/dev/null \
    && ok "fix_baseline emits repo-relative paths" || bad "fix_baseline emits absolute paths"

  # THE regression test: sec-eval targeted but NOT fixed must fail the gate.
  e2e_bad="$(fix_verify '["wp-content/themes/acme/legacy.php"]' "$E2E/v1")"
  if [ "$(jq -r '.verified' <<<"$e2e_bad")" = "false" ] \
     && [ "$(jq -r '[.unresolved[]?.id] | join(",")' <<<"$e2e_bad")" = "sec-eval" ]; then
    ok "E2E: a targeted sec-eval still in the code => verified:false, unresolved:[sec-eval]"
  else
    bad "E2E: un-fixed sec-eval did not fail the gate: $(jq -c '{status,verified,unresolved:[.unresolved[]?.id]}' <<<"$e2e_bad")"
  fi
  jq -e '(.resolved // []) as $r | (.new // []) as $n | any($r[]; .id=="sec-eval") and any($n[]; .id=="sec-eval")' <<<"$e2e_bad" >/dev/null \
    && bad "E2E: sec-eval reported as BOTH resolved and new — the two sides are in different path spaces" \
    || ok "E2E: no finding is simultaneously resolved and new (one path space)"

  # Now actually fix it: sec-eval clears, the presence rule does not, untouched stays.
  printf '<?php\n$map = array( "a" => "A" );\necho esc_html( $map["a"] );\n' > "$E2E/wp-content/themes/acme/legacy.php"
  printf '<?php\n$q = sanitize_text_field( wp_unslash( $_GET["q"] ?? "" ) );\necho esc_html( $q );\n' > "$E2E/wp-content/themes/acme/header.php"
  e2e_ok="$(fix_verify '["wp-content/themes/acme/legacy.php","wp-content/themes/acme/header.php"]' "$E2E/v2")"
  [ "$(jq -r '.status' <<<"$e2e_ok")" = "pass" ] && [ "$(jq -r '.verified' <<<"$e2e_ok")" = "true" ] \
    && ok "E2E: a genuinely correct fix => status:pass, verified:true" \
    || bad "E2E: correct fix did not pass: $(jq -c '{status,verified,unresolved:[.unresolved[]?.id],new:[.new[]?.id]}' <<<"$e2e_ok")"
  jq -e 'any(.resolved[]?; .id == "sec-eval")' <<<"$e2e_ok" >/dev/null \
    && ok "E2E: the cleared sec-eval is reported resolved" || bad "E2E: sec-eval not resolved after a real fix"
  jq -e 'any(.stillFlagged[]?; .id == "wpcs-missing-sanitize")' <<<"$e2e_ok" >/dev/null \
    && ok "E2E: the correctly-fixed presence rule is stillFlagged, not a failure" \
    || bad "E2E: presence rule mis-reported"
  jq -e 'any(.stillPresent[]?; .id == "sec-base64-decode")' <<<"$e2e_ok" >/dev/null \
    && ok "E2E: the untouched file's finding stays stillPresent (scanner-liveness canary)" \
    || bad "E2E: untouched canary lost"

  # Scope must follow the baseline audit. Re-scanning a `scope: all` baseline at
  # `self` shrinks the corpus, so every finding outside the theme vanishes and
  # reads as "fixed" when nothing was touched.
  #
  # Assert this through fix_static_rescan, NOT through fix_resolve_scan_scope
  # alone: a hardcoded `scope="self"` inside the rescan leaves the resolver
  # perfectly correct and still produces the false PASS. Test the seam.
  mkdir -p "$E2E/wp-content/plugins/thirdparty"
  printf '<?php\necho $_GET["q"];\n' > "$E2E/wp-content/plugins/thirdparty/tp.php"

  jq '.audit.scope = "self"' "$E2E/wp-build.json" > "$E2E/t" && mv "$E2E/t" "$E2E/wp-build.json"
  unset FIX_SCAN_SCOPE
  self_files="$(fix_static_rescan "$E2E/sc-self" | jq -r '[.findings[].file] | unique | join(" ")')"
  case "$self_files" in
    *thirdparty*) bad "scope:self re-scan reached outside the theme" ;;
    *)            ok "scope:self re-scan covers the theme only" ;;
  esac

  jq '.audit.scope = "all"' "$E2E/wp-build.json" > "$E2E/t" && mv "$E2E/t" "$E2E/wp-build.json"
  all_files="$(fix_static_rescan "$E2E/sc-all" | jq -r '[.findings[].file] | unique | join(" ")')"
  case "$all_files" in
    *thirdparty*) ok "fix_static_rescan honours audit.scope=all (third-party file scanned)" ;;
    *)            bad "fix_static_rescan ignored audit.scope=all — a scope:all baseline's findings would read as 'fixed' when nothing changed" ;;
  esac

  FIX_SCAN_SCOPE=self
  ovr_files="$(fix_static_rescan "$E2E/sc-ovr" | jq -r '[.findings[].file] | unique | join(" ")')"
  case "$ovr_files" in
    *thirdparty*) bad "FIX_SCAN_SCOPE=self override ignored by fix_static_rescan" ;;
    *)            ok "FIX_SCAN_SCOPE overrides audit.scope in the actual re-scan" ;;
  esac
  unset FIX_SCAN_SCOPE
  jq '.audit.scope = "self"' "$E2E/wp-build.json" > "$E2E/t" && mv "$E2E/t" "$E2E/wp-build.json"
else
  echo "  SKIP - audit-static.sh unavailable; E2E seam not exercised"
fi

# Restore the sandbox manifest for any later assertion.
WP_BUILD_FILE="$SB/wp-build.json"
FIX_PROJECT_ROOT="$SB"

# =============================================================================
# fix_record must not evaluate its input as a jq expression
# =============================================================================
# wpbuild_set passes its value to `jq "<path> = (<value>)"`, which EVALUATES it.
# Interpolating there would let `$ENV.X` read the environment into a committed
# manifest — inverting the names-only secrets rule.
SECRET_PROBE="s3cr3t" fix_record filesChanged '$ENV.SECRET_PROBE' >/dev/null 2>&1
jq -e '[.fix.filesChanged[]?] | any(. == "s3cr3t")' "$WP_BUILD_FILE" >/dev/null 2>&1 \
  && bad "fix_record EVALUATED its input as jq — \$ENV leaked an env var into the manifest" \
  || ok "fix_record does not evaluate its input as a jq expression (no \$ENV leak)"
fix_record filesChanged 'not valid json' >/dev/null 2>&1 \
  && bad "fix_record accepted malformed JSON" || ok "fix_record rejects malformed JSON, manifest untouched"
jq -e . "$WP_BUILD_FILE" >/dev/null 2>&1 && ok "manifest still valid JSON after a rejected write" || bad "manifest corrupted"

# A finding with a valid id+line but NO .file must route to unsupported[], never
# to supported[] (where a later fix_backup "" would fail loudly).
jq '.audit.findings += [{"id":"wpcs-missing-sanitize","category":"code-style","severity":"high","line":5,"external":false}]' \
  "$WP_BUILD_FILE" > "$SB/t" && mv "$SB/t" "$WP_BUILD_FILE"
fix_parse_args
mf="$(fix_load_findings 2>/dev/null)"
if [ -n "$mf" ]; then
  ok "a finding with no .file does not abort the partition"
  jq -e 'any(.supported[]; (.file // "") == "")' <<<"$mf" >/dev/null \
    && bad "a finding with no .file reached supported[] — fix_backup would fail on it" \
    || ok "a finding with no .file is kept out of supported[]"
  jq -e 'any(.unsupported[]; .reason == "no file path — nothing to edit")' <<<"$mf" >/dev/null \
    && ok "a finding with no .file lands in unsupported[] with the right reason" \
    || bad "a finding with no .file was not routed to unsupported[]"
else
  bad "one malformed finding aborted the whole partition"
fi

# --- summary ------------------------------------------------------------------
echo
if [ "$fails" -eq 0 ]; then
  echo "wp-fix.test.sh: all assertions passed"
  exit 0
fi
echo "wp-fix.test.sh: $fails assertion(s) FAILED"
exit 1
