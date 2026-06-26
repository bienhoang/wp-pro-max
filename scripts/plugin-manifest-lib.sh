#!/usr/bin/env bash
# plugin-manifest-lib.sh — shared helpers to read/write the wp-plugin.json manifest.
#
# Two ways to use it:
#   1) source it:   source "${CLAUDE_PLUGIN_ROOT}/scripts/plugin-manifest-lib.sh"
#                   then call wpplugin_get / wpplugin_set / wpplugin_progress ...
#   2) sub-command: bash "${CLAUDE_PLUGIN_ROOT}/scripts/plugin-manifest-lib.sh" init acme-widgets
#
# Sourcing is safe in both bash and zsh: no top-level `set -e`, no reserved names.
#
# Requires: jq. Operates on $WP_PLUGIN_FILE (default: ./wp-plugin.json).

WP_PLUGIN_FILE="${WP_PLUGIN_FILE:-./wp-plugin.json}"

# Resolve the shared generic helpers next to this file.
if [ -n "${BASH_VERSION:-}" ]; then
	_PLUGIN_MANIFEST_LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
elif [ -n "${ZSH_VERSION:-}" ]; then
	_PLUGIN_MANIFEST_LIB_DIR="$(dirname "${(%):-%x}")"
fi
[ -z "${MANIFEST_CORE_SOURCED:-}" ] && {
	# shellcheck source=manifest-core.sh
	source "${_PLUGIN_MANIFEST_LIB_DIR}/manifest-core.sh"
	MANIFEST_CORE_SOURCED=1
}

# Derive a PHP namespace from a kebab-case slug: acme-widgets -> AcmeWidgets
_wpplugin_to_pascal() {
	printf '%s' "$1" | awk -F'[-_]' '{
		for (i = 1; i <= NF; i++) {
			printf "%s", toupper(substr($i, 1, 1)) substr($i, 2)
		}
		printf "\n"
	}'
}

# Derive a human name from a kebab-case slug: acme-widgets -> Acme Widgets
_wpplugin_to_title() {
	printf '%s' "$1" | awk -F'[-_]' '{
		for (i = 1; i <= NF; i++) {
			printf "%s%s", (i == 1 ? "" : " "), toupper(substr($i, 1, 1)) substr($i, 2)
		}
		printf "\n"
	}'
}

# Create a wp-plugin.json manifest if absent.
# Args: <slug> [namespace] [name]
# When omitted, namespace is PascalCase(slug) and name is TitleCase(slug).
wpplugin_init() {
	_manifest_require_jq || return 1
	local slug="${1:?slug}" namespace="${2:-}" name="${3:-}" textdomain
	if [ -f "$WP_PLUGIN_FILE" ]; then
		echo "plugin-manifest-lib: $WP_PLUGIN_FILE already exists (left untouched)" >&2
		return 0
	fi
	textdomain="$slug"
	[ -z "$namespace" ] && namespace="$(_wpplugin_to_pascal "$slug")"
	[ -z "$name" ] && name="$(_wpplugin_to_title "$slug")"

	if ! [[ "$slug" =~ ^[a-z0-9-]+$ ]]; then
		echo "plugin-manifest-lib: invalid slug '$slug' (expected ^[a-z0-9-]+$)" >&2
		return 1
	fi
	if ! [[ "$textdomain" =~ ^[a-z0-9-]+$ ]]; then
		echo "plugin-manifest-lib: invalid textdomain '$textdomain'" >&2
		return 1
	fi
	if ! [[ "$namespace" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]]; then
		echo "plugin-manifest-lib: invalid namespace '$namespace'" >&2
		return 1
	fi

	jq -n \
		--arg slug "$slug" \
		--arg name "$name" \
		--arg namespace "$namespace" \
		--arg textdomain "$textdomain" \
		'{
			version: "1",
			plugin: { slug: $slug, name: $name, namespace: $namespace, textDomain: $textdomain },
			architecture: "oop",
			progress: {}
		}' > "$WP_PLUGIN_FILE"
	echo "plugin-manifest-lib: created $WP_PLUGIN_FILE" >&2
}

# Read a value. Arg: <jq-filter>
wpplugin_get() { _manifest_get "$WP_PLUGIN_FILE" "$@"; }

# Set a value (JSON). Args: <jq-path> <json-value>
wpplugin_set() { _manifest_set "$WP_PLUGIN_FILE" "$@"; }

# Deep-merge an object into the manifest root. Arg: <json-object>
wpplugin_merge() { _manifest_merge "$WP_PLUGIN_FILE" "$@"; }

# Record stage progress. Args: <stage-id> <state> [notes]
wpplugin_progress() { _manifest_progress "$WP_PLUGIN_FILE" "$@"; }

# Return 0 if a stage is already done. Arg: <stage-id>
wpplugin_is_done() { _manifest_is_done "$WP_PLUGIN_FILE" "$@"; }

# Print a human progress summary.
wpplugin_status() { _manifest_status "$WP_PLUGIN_FILE"; }

# Sub-command dispatcher: only runs when EXECUTED, not when sourced.
_wpplugin_sourced=1
if [ -n "${BASH_VERSION:-}" ]; then
	[ "${BASH_SOURCE[0]}" = "$0" ] && _wpplugin_sourced=0
elif [ -n "${ZSH_VERSION:-}" ]; then
	case "${ZSH_EVAL_CONTEXT:-}" in *:file*) _wpplugin_sourced=1 ;; *) _wpplugin_sourced=0 ;; esac
fi

if [ "$_wpplugin_sourced" = "0" ]; then
	set -euo pipefail
	cmd="${1:-}"; shift || true
	case "$cmd" in
		init)     wpplugin_init "$@" ;;
		get)      wpplugin_get "$@" ;;
		set)      wpplugin_set "$@" ;;
		merge)    wpplugin_merge "$@" ;;
		progress) wpplugin_progress "$@" ;;
		is-done)  wpplugin_is_done "$@" ;;
		status)   wpplugin_status "$@" ;;
		*) echo "usage: plugin-manifest-lib.sh {init|get|set|merge|progress|is-done|status} ..." >&2; exit 2 ;;
	esac
fi
