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

# Resolve the shared generic helpers next to this file.
if [ -n "${BASH_VERSION:-}" ]; then
	_MANIFEST_LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
elif [ -n "${ZSH_VERSION:-}" ]; then
	_MANIFEST_LIB_DIR="$(dirname "${(%):-%x}")"
fi
[ -z "${MANIFEST_CORE_SOURCED:-}" ] && {
	# shellcheck source=manifest-core.sh
	source "${_MANIFEST_LIB_DIR}/manifest-core.sh"
	MANIFEST_CORE_SOURCED=1
}

# Create the manifest if absent. Args: <project-name> <theme-slug> [strategy]
wpbuild_init() {
	_manifest_require_jq || return 1
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

# Read a value. Arg: <jq-filter>
wpbuild_get() { _manifest_get "$WP_BUILD_FILE" "$@"; }

# Set a value (JSON). Args: <jq-path> <json-value>
wpbuild_set() { _manifest_set "$WP_BUILD_FILE" "$@"; }

# Deep-merge an object into the manifest root. Arg: <json-object>
wpbuild_merge() { _manifest_merge "$WP_BUILD_FILE" "$@"; }

# Record stage progress. Args: <stage-id> <state> [notes]
wpbuild_progress() { _manifest_progress "$WP_BUILD_FILE" "$@"; }

# Return 0 if a stage is already done. Arg: <stage-id>
wpbuild_is_done() { _manifest_is_done "$WP_BUILD_FILE" "$@"; }

# Print a human progress summary.
wpbuild_status() { _manifest_status "$WP_BUILD_FILE"; }

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
