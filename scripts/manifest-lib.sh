#!/usr/bin/env bash
# manifest-lib.sh — shared helpers to read/write the wp-build.json pipeline manifest.
#
# Two ways to use it:
#   1) source it:   source "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh"
#                   then call wpbuild_get / wpbuild_set / wpbuild_progress ...
#   2) sub-command: bash "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh" progress analyze done "note"
#
# Sourcing is safe in both bash and zsh: this file does NOT enable `set -e` at the
# top level (that would alter the caller's shell) and avoids shell-reserved names
# such as `status` (read-only in zsh).
#
# Requires: jq. Operates on $WP_BUILD_FILE (default: ./wp-build.json).

WP_BUILD_FILE="${WP_BUILD_FILE:-./wp-build.json}"

_wpbuild_require_jq() {
  command -v jq >/dev/null 2>&1 || { echo "manifest-lib: 'jq' is required" >&2; return 1; }
}

_wpbuild_tmp() {
  # mktemp is POSIX on macOS/Linux; fall back to a pid-based name if absent.
  mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/wpbuild.$$.tmp"
}

# Create the manifest if absent. Args: <project-name> <theme-slug> [strategy]
wpbuild_init() {
  _wpbuild_require_jq || return 1
  local name="${1:?project name}" slug="${2:?theme slug}" strategy="${3:-classic-acf}"
  if [ -f "$WP_BUILD_FILE" ]; then
    echo "manifest-lib: $WP_BUILD_FILE already exists (left untouched)" >&2
    return 0
  fi
  jq -n --arg name "$name" --arg slug "$slug" --arg strategy "$strategy" '{
    version: "1",
    project: { name: $name, themeSlug: $slug, textDomain: $slug },
    strategy: $strategy,
    progress: {}
  }' > "$WP_BUILD_FILE"
  echo "manifest-lib: created $WP_BUILD_FILE" >&2
}

# Read a value. Arg: <jq-filter>   e.g. wpbuild_get '.strategy'
wpbuild_get() {
  _wpbuild_require_jq || return 1
  jq -r "${1:?jq filter}" "$WP_BUILD_FILE"
}

# Set a value (JSON). Args: <jq-path> <json-value>
#   wpbuild_set '.strategy' '"block-fse"'
#   wpbuild_set '.plugins' '[{"slug":"wordpress-seo","required":true}]'
wpbuild_set() {
  _wpbuild_require_jq || return 1
  local path="${1:?jq path}" value="${2:?json value}" tmp
  tmp="$(_wpbuild_tmp)"
  jq "${path} = (${value})" "$WP_BUILD_FILE" > "$tmp" && mv "$tmp" "$WP_BUILD_FILE"
}

# Deep-merge an object into the manifest root. Arg: <json-object>
wpbuild_merge() {
  _wpbuild_require_jq || return 1
  local value="${1:?json object}" tmp
  tmp="$(_wpbuild_tmp)"
  jq ". * (${value})" "$WP_BUILD_FILE" > "$tmp" && mv "$tmp" "$WP_BUILD_FILE"
}

# Record stage progress. Args: <stage-id> <state> [notes]
# state: pending | in-progress | done | failed | skipped
wpbuild_progress() {
  _wpbuild_require_jq || return 1
  local stage="${1:?stage id}" state="${2:?state}" notes="${3:-}" ts tmp
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  tmp="$(_wpbuild_tmp)"
  jq --arg s "$stage" --arg st "$state" --arg n "$notes" --arg ts "$ts" \
    '.progress[$s] = {status: $st, updatedAt: $ts, notes: $n}' \
    "$WP_BUILD_FILE" > "$tmp" && mv "$tmp" "$WP_BUILD_FILE"
}

# Return 0 if a stage is already done (resume/idempotency). Arg: <stage-id>
wpbuild_is_done() {
  _wpbuild_require_jq || return 1
  [ "$(jq -r --arg s "$1" '.progress[$s].status // "pending"' "$WP_BUILD_FILE")" = "done" ]
}

# Print a human progress summary.
wpbuild_status() {
  _wpbuild_require_jq || return 1
  echo "WP Pro Max — $(wpbuild_get '.project.name') [$(wpbuild_get '.strategy')]"
  jq -r '.progress | to_entries[] | "  \(.key): \(.value.status)"' "$WP_BUILD_FILE" 2>/dev/null \
    || echo "  (no progress yet)"
}

# Sub-command dispatcher: only runs when EXECUTED, not when sourced.
# Detect execution vs sourcing at top level (bash + zsh). Must NOT be wrapped in
# a function — zsh's ZSH_EVAL_CONTEXT loses the `:file` marker inside one.
_wpbuild_sourced=1
if [ -n "${BASH_VERSION:-}" ]; then
  [ "${BASH_SOURCE[0]}" = "$0" ] && _wpbuild_sourced=0
elif [ -n "${ZSH_VERSION:-}" ]; then
  case "${ZSH_EVAL_CONTEXT:-}" in *:file*) _wpbuild_sourced=1 ;; *) _wpbuild_sourced=0 ;; esac
fi

if [ "$_wpbuild_sourced" = "0" ]; then
  set -euo pipefail
  cmd="${1:-}"; shift || true
  case "$cmd" in
    init)     wpbuild_init "$@" ;;
    get)      wpbuild_get "$@" ;;
    set)      wpbuild_set "$@" ;;
    merge)    wpbuild_merge "$@" ;;
    progress) wpbuild_progress "$@" ;;
    is-done)  wpbuild_is_done "$@" ;;
    status)   wpbuild_status "$@" ;;
    *) echo "usage: manifest-lib.sh {init|get|set|merge|progress|is-done|status} ..." >&2; exit 2 ;;
  esac
fi
