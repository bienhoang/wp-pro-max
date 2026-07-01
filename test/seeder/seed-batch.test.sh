#!/usr/bin/env bash
# seed-batch.test.sh — ORCHESTRATION acceptance test for the seed batch driver
# (scripts/seed-batch-run.sh, Phase 2). With a stub `wp` standing in for the PHP
# runtime, it asserts the bash-exercisable contract:
#   (a) exactly ONE `eval-file` invocation per run,
#   (b) the JSON payload reaches the runtime via stdin (non-empty) — on BOTH the
#       `docker exec -i … wp` and `wp-env run cli wp` runner paths (red-team H6),
#   (c) the summary is parsed from BETWEEN the sentinels (not bare stdout, which
#       carries WP_DEBUG noise), and merged append+unique into the manifest.
# Zero-dup / idempotency is NOT asserted here — no PHP runs. That is the live
# wp-env gate in Phase 2.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$HERE/../../scripts" && pwd)"
DRIVER="$SCRIPTS/seed-batch-run.sh"
FIXTURE="$HERE/fixtures/payload.sample.json"

fails=0
ok()  { printf '  ok   - %s\n' "$1"; }
bad() { printf '  FAIL - %s\n' "$1"; fails=$((fails + 1)); }

echo "seed-batch.test.sh"

if [ ! -f "$DRIVER" ]; then
  # Phase-1 RED state: the driver does not exist yet. This is the gate Phase 2
  # closes — report it as a failure for the right reason.
  bad "scripts/seed-batch-run.sh not present yet (expected RED until Phase 2)"
  echo
  echo "seed-batch.test.sh: $fails FAILED (driver absent — Phase 2 gate)"
  exit 1
fi

# Build a sandbox PATH whose `wp`, `docker`, and `wp-env` all funnel into the
# stub runtime with stdin forwarded, so we can exercise each runner path.
make_sandbox() {
  local dir; dir="$(mktemp -d)"
  # `wp` → the recording stub runtime.
  cat > "$dir/wp" <<EOF
#!/usr/bin/env bash
exec "$HERE/stub-wp.sh" "\$@"
EOF
  # `docker exec -i <c> wp eval-file …`: strip `exec -i <c>`, leaving
  # `wp eval-file …`; re-exec that program through the sandbox stub (stdin kept).
  cat > "$dir/docker" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "ps" ]; then printf '%s\n' "\${STUB_DOCKER_PS:-}"; exit 0; fi
if [ "\$1" = "exec" ]; then
  shift
  while [ "\${1:-}" = "-i" ] || [ "\${1:-}" = "-t" ]; do shift; done
  shift                       # drop <container>; remaining: wp eval-file …
  prog="\$1"; shift
  exec "$dir/\$prog" "\$@"
fi
exit 0
EOF
  # `wp-env run cli wp <args...>` → run stub wp, stdin preserved.
  cat > "$dir/wp-env" <<EOF
#!/usr/bin/env bash
# args: run cli wp <subcommand...>
if [ "\$1" = "run" ]; then
  shift; shift; shift        # drop 'run' 'cli' 'wp'
  exec "$dir/wp" "\$@"
fi
exit 0
EOF
  chmod +x "$dir/wp" "$dir/docker" "$dir/wp-env"
  printf '%s\n' "$dir"
}

# Run one orchestration pass on a chosen runner path; echo the manifest path.
run_once() {
  local mode="$1"            # "override" | "docker" | "wpenv"
  local sandbox; sandbox="$(make_sandbox)"
  local work; work="$(mktemp -d)"
  local manifest="$work/wp-build.json"
  printf '{"version":"1","seed":{"idempotencyKeys":["pre:existing"]}}\n' > "$manifest"
  local log="$work/calls.log"; : > "$log"

  (
    export PATH="$sandbox:/usr/bin:/bin"
    export SEED_TEST_LOG="$log"
    export WP_BUILD_FILE="$manifest"
    case "$mode" in
      override) export WP_CLI_RUN="wp" ;;                        # straight to stub wp
      docker)   unset WP_CLI_RUN; export STUB_DOCKER_PS="proj-12ab-cli-1" ;;
      wpenv)    unset WP_CLI_RUN; export STUB_DOCKER_PS="" ;;    # no cli container → wp-env fallback
    esac
    bash "$DRIVER" "$FIXTURE" >/dev/null 2>&1
  )

  printf '%s\n' "$work"
}

assert_pass() {
  local mode="$1" work log manifest evalcount stdinbytes keys lastsum
  work="$(run_once "$mode")"
  log="$work/calls.log"
  manifest="$work/wp-build.json"

  evalcount="$(grep -c '^eval-file' "$log" 2>/dev/null || printf '0')"
  [ "$evalcount" = "1" ] && ok "[$mode] exactly one eval-file invocation" \
    || bad "[$mode] expected 1 eval-file call, got $evalcount"

  stdinbytes="$(cat "${log}.stdin" 2>/dev/null || printf '0')"
  [ "${stdinbytes:-0}" -gt 0 ] 2>/dev/null && ok "[$mode] payload delivered on stdin ($stdinbytes bytes)" \
    || bad "[$mode] stdin to runtime was empty (silent-empty-stdin guard)"

  # Summary parsed from between sentinels and merged append+unique: the pre-existing
  # key must survive AND the new keys must be present.
  keys="$(jq -c '.seed.idempotencyKeys' "$manifest" 2>/dev/null || printf 'null')"
  case "$keys" in
    *'pre:existing'*) ok "[$mode] pre-existing idempotency key preserved (append, not replace)" ;;
    *) bad "[$mode] pre-existing key lost on merge — got $keys" ;;
  esac
  case "$keys" in
    *'page:home'*) ok "[$mode] summary keys merged from sentinel-wrapped stdout" ;;
    *) bad "[$mode] summary keys not merged — got $keys" ;;
  esac

  lastsum="$(jq -r '.seed.lastSummary.created // "MISSING"' "$manifest" 2>/dev/null || printf 'MISSING')"
  [ "$lastsum" = "2" ] && ok "[$mode] seed.lastSummary recorded for observability" \
    || bad "[$mode] seed.lastSummary.created expected 2, got $lastsum"
}

assert_pass override
assert_pass docker
assert_pass wpenv

echo
[ "$fails" -eq 0 ] && { echo "seed-batch.test.sh: PASS"; exit 0; } || { echo "seed-batch.test.sh: $fails FAILED"; exit 1; }
