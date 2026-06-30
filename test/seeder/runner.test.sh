#!/usr/bin/env bash
# runner.test.sh — assert wp_cli_resolve picks the right runner across branches,
# and that container detection rejects `*-tests-cli-1` and fails loudly on >1.
# No live Docker: a stub `docker` on PATH supplies canned `docker ps` output.
# No `-e`: this file is its own reporter (counts fails); a failing check must not
# abort the run, and wp_cli_resolve intentionally returns non-zero in some cases.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$(cd "$HERE/../../scripts" && pwd)/wp-cli-runner.sh"

fails=0
ok()   { printf '  ok   - %s\n' "$1"; }
bad()  { printf '  FAIL - %s\n' "$1"; fails=$((fails + 1)); }
check(){ [ "$2" = "$3" ] && ok "$1" || { bad "$1"; printf '         want: %s\n         got:  %s\n' "$3" "$2"; }; }

# Build a throwaway PATH with a stub `docker` that prints $STUB_DOCKER_PS, or an
# empty PATH-dir (no docker) when STUB_DOCKER_PS is unset.
mk_stub_docker() {
  local dir; dir="$(mktemp -d)"
  if [ "${1:-}" = "none" ]; then
    printf '%s\n' "$dir"; return 0   # no docker binary in this dir
  fi
  cat > "$dir/docker" <<EOF
#!/usr/bin/env bash
# stub docker: only 'ps' is modeled.
if [ "\$1" = "ps" ]; then
  printf '%s\n' "${STUB_DOCKER_PS:-}"
  exit 0
fi
exit 0
EOF
  chmod +x "$dir/docker"
  printf '%s\n' "$dir"
}

# Run wp_cli_resolve in a clean subshell with a controlled PATH + env.
resolve_with() {
  # $1 = "none" to omit docker; else canned multi-line container list goes in $2
  local mode="$1" ps_list="${2:-}" require="${3:-}"
  local sd; sd="$(STUB_DOCKER_PS="$ps_list" mk_stub_docker "$mode")"
  (
    export PATH="$sd:/usr/bin:/bin"
    export STUB_DOCKER_PS="$ps_list"
    [ -n "$require" ] && export WP_CLI_REQUIRE_CONTAINER="$require"
    unset WP_CLI_RUN
    # shellcheck source=/dev/null
    source "$RUNNER"
    # Capture rc without letting a non-zero resolve abort the subshell, so the
    # ::rc= line is always emitted for the ambiguous / require-container cases.
    local rc=0 out
    out="$(wp_cli_resolve 2>/dev/null)" || rc=$?
    printf '%s\n::rc=%s\n' "$out" "$rc"
  )
}

echo "runner.test.sh"

# 1. WP_CLI_RUN override wins, verbatim.
out="$( WP_CLI_RUN="wp --path=/srv" bash -c 'source "'"$RUNNER"'"; wp_cli_resolve' )"
check "WP_CLI_RUN override is honored" "$out" "wp --path=/srv"

# 2. docker-exec branch: exactly one real cli container (a -tests-cli-1 decoy is
#    present and MUST be excluded).
out="$(resolve_with docker "$(printf 'wp-env-acme-12ab34cd-cli-1\nwp-env-acme-12ab34cd-tests-cli-1\nwp-env-acme-12ab34cd-mysql-1')" | grep -v '::rc=')"
check "docker-exec picks the single non-tests cli container" \
  "$out" "docker exec -i wp-env-acme-12ab34cd-cli-1 wp"

# 3. wp-env fallback when no cli container is listed.
out="$(resolve_with docker "$(printf 'some-other-mysql-1\n')" | grep -v '::rc=')"
check "wp-env fallback when no cli container present" "$out" "wp-env run cli wp"

# 3b. wp-env fallback when docker is absent entirely.
out="$(resolve_with none "" | grep -v '::rc=')"
check "wp-env fallback when docker binary absent" "$out" "wp-env run cli wp"

# 4. Ambiguous: >1 real cli container → fail loudly (non-zero rc, no guess).
full="$(resolve_with docker "$(printf 'wp-env-a-1111-cli-1\nwp-env-b-2222-cli-1')")"
rc="$(printf '%s\n' "$full" | sed -n 's/^::rc=//p')"
picked="$(printf '%s\n' "$full" | grep -v '::rc=')"
[ "$rc" != "0" ] && ok "ambiguous >1 cli container fails loudly (rc=$rc)" \
  || bad "ambiguous >1 cli container should fail loudly (got rc=$rc, picked='$picked')"

# 5. Require-container mode: 0 matches → fail loudly instead of wp-env fallback.
full="$(resolve_with docker "$(printf 'only-mysql-1\n')" 1)"
rc="$(printf '%s\n' "$full" | sed -n 's/^::rc=//p')"
[ "$rc" != "0" ] && ok "WP_CLI_REQUIRE_CONTAINER=1 fails loudly on 0 matches (rc=$rc)" \
  || bad "WP_CLI_REQUIRE_CONTAINER=1 should fail on 0 matches (got rc=$rc)"

# Resolve from a specific working dir (so basename-narrowing is exercised).
resolve_in_dir() {
  local wd="$1" ps_list="$2"
  local sd; sd="$(STUB_DOCKER_PS="$ps_list" mk_stub_docker docker)"
  (
    export PATH="$sd:/usr/bin:/bin"
    export STUB_DOCKER_PS="$ps_list"
    unset WP_CLI_RUN WP_CLI_CONTAINER
    cd "$wd" || exit 99
    # shellcheck source=/dev/null
    source "$RUNNER"
    local rc=0 out
    out="$(wp_cli_resolve 2>/dev/null)" || rc=$?
    printf '%s\n::rc=%s\n' "$out" "$rc"
  )
}

# 7. Token-anchored narrowing: PWD basename `site` must NOT bind another
#    project's `mysite-…-cli-1` (substring footgun). With two real cli containers
#    up and no token match, this is ambiguous → fail loudly (never bind `mysite`).
site_dir="$(mktemp -d)/site"; mkdir -p "$site_dir"
full="$(resolve_in_dir "$site_dir" "$(printf 'mysite-staging-ab12-cli-1\nothersite-cd34-cli-1')")"
rc="$(printf '%s\n' "$full" | sed -n 's/^::rc=//p')"
picked="$(printf '%s\n' "$full" | grep -v '::rc=')"
{ [ "$rc" != "0" ] || [ -z "$picked" ]; } \
  && ok "basename 'site' does NOT substring-bind 'mysite-…-cli-1' (token-anchored)" \
  || bad "wrong-DB bind: basename 'site' resolved to '$picked'"

# 8. Token match still narrows correctly when the basename is a real segment.
acme_dir="$(mktemp -d)/acme"; mkdir -p "$acme_dir"
out="$(resolve_in_dir "$acme_dir" "$(printf 'wp-env-acme-1111-cli-1\nwp-env-other-2222-cli-1')" | grep -v '::rc=')"
check "basename 'acme' narrows to its own wp-env-acme-…-cli-1" \
  "$out" "docker exec -i wp-env-acme-1111-cli-1 wp"

# 6. Sources cleanly under zsh too (the runtime shell), if zsh is available.
if command -v zsh >/dev/null 2>&1; then
  if zsh -c 'source "'"$RUNNER"'"; WP_CLI_RUN="wp"; r="$(wp_cli_resolve)"; [ "$r" = "wp" ]' 2>/dev/null; then
    ok "wp-cli-runner.sh sources cleanly under zsh"
  else
    bad "wp-cli-runner.sh failed to source/resolve under zsh"
  fi
else
  ok "zsh not present — skipping zsh source check"
fi

echo
[ "$fails" -eq 0 ] && { echo "runner.test.sh: PASS"; exit 0; } || { echo "runner.test.sh: $fails FAILED"; exit 1; }
