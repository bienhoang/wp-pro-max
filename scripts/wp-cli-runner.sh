#!/usr/bin/env bash
# wp-cli-runner.sh — resolve and run the WP-CLI runner for the seed batch engine.
#
# The seed batch (seed-batch-runtime.php) is executed once per stage via
# `wp eval-file …` with a JSON payload piped to stdin. That requires a runner that
# (a) forwards stdin into the container and (b) binds to THIS project's live
# WordPress container — never the co-resident `*-tests-cli-1` test container, and
# never some other project's wp-env instance.
#
# Source it:
#   source "${CLAUDE_PLUGIN_ROOT}/scripts/wp-cli-runner.sh"
#   wp_cli option get siteurl
#   printf '%s' "$payload_json" | wp_cli eval-file ./scripts/seed-batch-runtime.php
# Or execute it:
#   bash wp-cli-runner.sh resolve         # print the resolved runner argv
#   bash wp-cli-runner.sh wp option get siteurl
#
# Resolution order (wp_cli_resolve):
#   1. $WP_CLI_RUN override, verbatim (e.g. "wp", "ssh host wp --path=/var/www").
#   2. docker exec -i <this-project-cli-1> wp   — when exactly one matching
#      container is up (the fast path: a long-lived container, no per-call boot).
#   3. wp-env run cli wp                          — fallback, unless
#      WP_CLI_REQUIRE_CONTAINER=1 (then a 0/ambiguous match fails loudly).
#
# Container match (red-team C5): names ending in `-cli-1`, EXCLUDING
# `-tests-cli-1`, narrowed to this project's instance by CWD basename when that
# narrowing is unambiguous. Zero matches → fallback (or fail if required); more
# than one match → FAIL LOUDLY (seeding the wrong database is worse than stopping).
#
# zsh-safe: this file is sourced by the seed driver (the runtime shell is zsh). No
# top-level `set -euo pipefail` (it would leak into the caller); no `status`/`path`
# locals (zsh-reserved); sourcing-vs-execution guard at the bottom.

_wpcli_log() { printf 'wp-cli-runner: %s\n' "$*" >&2; }

# _wpcli_detect_container — echo the single matching container name on success.
# Returns: 0 + name (exactly one match); 1 + empty (zero matches / no docker);
# 2 (ambiguous: more than one match — caller must fail loudly).
_wpcli_detect_container() {
  # Explicit override wins (escape hatch; also lets callers target the throwaway
  # tests container deliberately instead of the auto-detected dev one).
  if [ -n "${WP_CLI_CONTAINER:-}" ]; then
    printf '%s\n' "$WP_CLI_CONTAINER"
    return 0
  fi
  command -v docker >/dev/null 2>&1 || return 1

  local all narrowed proj count
  # Candidate set: real cli containers only, never the test container.
  all="$(docker ps --format '{{.Names}}' 2>/dev/null \
    | grep -E -- '-cli-1$' | grep -Ev -- '-tests-cli-1$')"
  [ -n "$all" ] || return 1

  # Narrow to this project's wp-env instance when the CWD basename appears as a
  # delimited TOKEN in a container name (wp-env prefixes instances with the
  # sanitized project dir, e.g. wp-env-<dir>-<hash>-cli-1). A bare substring match
  # would be unsafe: PWD basename `site` must NOT match `mysite-staging-…-cli-1`
  # and bind the wrong database (red-team C5). So require `proj` to sit on `-`/`_`
  # boundaries (or string ends). Only adopt the narrowing when it leaves a
  # non-empty set, so being in the plugin repo (no matching instance) safely keeps
  # the full candidate set.
  proj="$(basename "$PWD")"
  if [ -n "$proj" ]; then
    # Escape regex metacharacters in the basename before building the token regex.
    local proj_re
    proj_re="$(printf '%s' "$proj" | sed 's/[][\\.^$*+?(){}|]/\\&/g')"
    narrowed="$(printf '%s\n' "$all" | grep -E -- "(^|[-_])${proj_re}([-_]|\$)" 2>/dev/null || true)"
    [ -n "$narrowed" ] && all="$narrowed"
  fi

  count="$(printf '%s\n' "$all" | grep -c . 2>/dev/null || printf '0')"
  if [ "$count" -gt 1 ]; then
    _wpcli_log "ERROR: ${count} candidate cli containers match — refusing to guess:"
    printf '%s\n' "$all" | sed 's/^/  - /' >&2
    return 2
  fi
  printf '%s\n' "$all" | grep -m1 .
}

# wp_cli_resolve — echo the runner argv string (space-separated). Exits non-zero
# (after logging) only when a container is REQUIRED but cannot be resolved
# unambiguously.
wp_cli_resolve() {
  if [ -n "${WP_CLI_RUN:-}" ]; then
    printf '%s\n' "$WP_CLI_RUN"
    return 0
  fi

  local container rc
  container="$(_wpcli_detect_container)"; rc=$?
  if [ "$rc" -eq 0 ] && [ -n "$container" ]; then
    printf 'docker exec -i %s wp\n' "$container"
    return 0
  fi
  if [ "$rc" -eq 2 ]; then
    # Ambiguous — never silently fall back to a guessed instance.
    _wpcli_log "ERROR: ambiguous container match; set WP_CLI_RUN to choose explicitly"
    return 2
  fi

  # rc == 1: no container (docker absent or none up).
  if [ "${WP_CLI_REQUIRE_CONTAINER:-}" = "1" ]; then
    _wpcli_log "ERROR: no project '*-cli-1' container found and WP_CLI_REQUIRE_CONTAINER=1"
    return 1
  fi
  printf 'wp-env run cli wp\n'
}

# _wpcli_split <argv-string> — populate the array _WP_CLI_ARGV from a runner
# string, word-splitting correctly under both bash and zsh.
_wpcli_split() {
  local runner="$1"
  if [ -n "${ZSH_VERSION:-}" ]; then
    eval '_WP_CLI_ARGV=( ${=runner} )'
  else
    # shellcheck disable=SC2206
    read -r -a _WP_CLI_ARGV <<< "$runner"
  fi
}

# wp_cli <subcommand...> — run a WP-CLI command through the resolved runner,
# forwarding this process's stdin (so a piped payload reaches `eval-file`).
wp_cli() {
  local runner
  runner="$(wp_cli_resolve)" || return $?
  _wpcli_split "$runner"
  "${_WP_CLI_ARGV[@]}" "$@"
}

# ---------------------------------------------------------------------------
# Direct execution: `bash wp-cli-runner.sh {resolve|wp ...}`
# Detect execution vs sourcing in bash and zsh (top-level; not in a function).
# ---------------------------------------------------------------------------
_wpcli_sourced=1
if [ -n "${BASH_VERSION:-}" ]; then
  [ "${BASH_SOURCE[0]}" = "$0" ] && _wpcli_sourced=0
elif [ -n "${ZSH_VERSION:-}" ]; then
  case "${ZSH_EVAL_CONTEXT:-}" in *:file*) _wpcli_sourced=1 ;; *) _wpcli_sourced=0 ;; esac
fi

if [ "$_wpcli_sourced" = "0" ]; then
  set -euo pipefail
  _cmd="${1:-}"; shift || true
  case "$_cmd" in
    resolve) wp_cli_resolve ;;
    wp)      wp_cli "$@" ;;
    *) echo "usage: wp-cli-runner.sh {resolve | wp <subcommand...>}" >&2; exit 2 ;;
  esac
fi
