#!/usr/bin/env bash
# wpx.test.sh — assert the wpx.sh shim: (1) forwards the WP SUBCOMMAND + flags
# verbatim to the resolved runner (no extra `wp` prefix, since wp_cli adds it),
# (2) forwards this process's stdin (so `wpx eval-file -` works), (3) propagates
# the WP command's exit code, and (4) delegates container resolution to the lib
# (excluding `*-tests-cli-1`). No live Docker/WP: a WP_CLI_RUN override stub and a
# stub `docker` supply all behavior.
# No `-e`: this file is its own reporter; some assertions expect non-zero rc.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WPX="$(cd "$HERE/../scripts" && pwd)/wpx.sh"
RUNNER="$(cd "$HERE/../scripts" && pwd)/wp-cli-runner.sh"

fails=0
ok()  { printf '  ok   - %s\n' "$1"; }
bad() { printf '  FAIL - %s\n' "$1"; fails=$((fails + 1)); }
check(){ [ "$2" = "$3" ] && ok "$1" || { bad "$1"; printf '         want: %s\n         got:  %s\n' "$3" "$2"; }; }

echo "wpx.test.sh"

# A runner stub that echoes its args and (if piped) its stdin, so we can observe
# exactly what wpx forwarded.
STUB="$(mktemp)"
cat > "$STUB" <<'EOF'
#!/usr/bin/env bash
printf 'ARGS:%s\n' "$*"
if [ ! -t 0 ]; then sed 's/^/STDIN:/'; fi
EOF
chmod +x "$STUB"

# 1. Subcommand + flags forwarded verbatim; no extra `wp` injected by the shim.
out="$( WP_CLI_RUN="$STUB" bash "$WPX" option get siteurl --format=json )"
check "forwards subcommand + flags verbatim" "$out" "ARGS:option get siteurl --format=json"

# 2. stdin is forwarded to the runner (eval-file - contract).
out="$( printf 'PAYLOAD-123' | WP_CLI_RUN="$STUB" bash "$WPX" eval-file - )"
args_line="$(printf '%s\n' "$out" | sed -n '1p')"
stdin_line="$(printf '%s\n' "$out" | sed -n '2p')"
check "stdin forward — args"  "$args_line"  "ARGS:eval-file -"
check "stdin forward — stdin" "$stdin_line" "STDIN:PAYLOAD-123"

# 3. Exit code is the WP command's, not the wrapper's.
WP_CLI_RUN="true"  bash "$WPX" anything >/dev/null 2>&1
check "propagates success exit code" "$?" "0"
WP_CLI_RUN="false" bash "$WPX" anything >/dev/null 2>&1
check "propagates failure exit code" "$?" "1"

# 4. Resolution is delegated to the lib and excludes `*-tests-cli-1`. Source wpx
#    (which sources the lib) under a stub docker and assert wp_cli_resolve picks
#    the single real cli container, never the tests one.
sd="$(mktemp -d)"
cat > "$sd/docker" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "ps" ] && printf '%s\n' "${STUB_DOCKER_PS:-}"
exit 0
EOF
chmod +x "$sd/docker"
out="$(
  export PATH="$sd:/usr/bin:/bin"
  export STUB_DOCKER_PS="$(printf 'wp-env-acme-9f9f-cli-1\nwp-env-acme-9f9f-tests-cli-1\nwp-env-acme-9f9f-mysql-1')"
  unset WP_CLI_RUN WP_CLI_CONTAINER
  # shellcheck source=/dev/null
  . "$WPX"
  wp_cli_resolve 2>/dev/null
)"
check "delegates resolution; excludes *-tests-cli-1" \
  "$out" "docker exec -i wp-env-acme-9f9f-cli-1 wp"

# 5. Sources cleanly under zsh too (the runtime shell), if available.
if command -v zsh >/dev/null 2>&1; then
  if zsh -c 'WP_CLI_RUN="true"; source "'"$WPX"'"' 2>/dev/null; then
    ok "wpx.sh sources cleanly under zsh"
  else
    bad "wpx.sh failed to source under zsh"
  fi
else
  ok "zsh not present — skipping zsh source check"
fi

rm -f "$STUB"; rm -rf "$sd"
echo
[ "$fails" -eq 0 ] && { echo "wpx.test.sh: PASS"; exit 0; } || { echo "wpx.test.sh: $fails FAILED"; exit 1; }
