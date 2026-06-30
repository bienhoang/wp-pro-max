#!/usr/bin/env bash
# manifest-core.sh — generic, zsh-safe helpers to read/write a JSON manifest.
#
# This file is SOURCED by wrapper libraries (manifest-lib.sh, plugin-manifest-lib.sh).
# It does NOT enable `set -e` at the top level and avoids zsh-reserved names.
#
# The wrappers bind a concrete manifest file path; these functions accept the file
# as their first argument, so one implementation serves both pipelines.
#
# Concurrency guard: when WP_BUILD_RETURN_FRAGMENT=1, the write helpers refuse to
# mutate the file and instead emit a single `WPBUILD_FRAGMENT {json}` line to
# stdout describing the mutation they would have applied. An orchestrator spawns
# concurrent workers (e.g. the theme `convert` fan-out) with this flag set so they
# physically cannot clobber the shared manifest; the orchestrator collects the
# fragments and applies them itself, sequentially, with the flag unset. Read
# helpers are never affected. See references/parallel-execution.md.

_manifest_require_jq() {
	command -v jq >/dev/null 2>&1 || { echo "manifest-core: 'jq' is required" >&2; return 1; }
}

# Emit a one-line fragment envelope for a spawned worker, then signal the caller
# to return. Args: <op> then op-specific (key value) pairs as a flat JSON object.
# Builds the JSON with jq so paths/notes/values are correctly quoted; `value`
# (for set/merge) is already a JSON value, so prefer --argjson and fall back to a
# string if it is not standalone-parseable.
_manifest_emit_fragment() {
	local frag
	case "$1" in
		set|merge)
			# NB: 'keypath' not 'path' — in zsh, a local named 'path' is tied to $PATH
			# and clobbering it makes jq unfindable inside the function.
			local op="$1" value="${2:?json value}" keypath="${3:-}"
			frag="$(jq -cn --arg op "$op" --arg path "$keypath" --argjson value "$value" \
				'{op:$op} + (if $path == "" then {} else {path:$path} end) + {value:$value}' 2>/dev/null \
				|| jq -cn --arg op "$op" --arg path "$keypath" --arg value "$value" \
				'{op:$op} + (if $path == "" then {} else {path:$path} end) + {value:$value}')"
			;;
		progress)
			frag="$(jq -cn --arg stage "$2" --arg state "$3" --arg notes "${4:-}" \
				'{op:"progress",stage:$stage,state:$state,notes:$notes}')"
			;;
	esac
	printf 'WPBUILD_FRAGMENT %s\n' "$frag"
}

_manifest_tmp() {
	# POSIX mktemp on macOS/Linux; fall back to a pid-based name.
	mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/manifest-core.$$.tmp"
}

# Generic read. Args: <file> <jq-filter>
#   _manifest_get "./wp-build.json" '.strategy'
_manifest_get() {
	_manifest_require_jq || return 1
	local file="${1:?manifest file}" filter="${2:?jq filter}"
	jq -r "$filter" "$file"
}

# Generic write. Args: <file> <jq-path> <json-value>
#   _manifest_set "./wp-build.json" '.strategy' '"block-fse"'
_manifest_set() {
	_manifest_require_jq || return 1
	# NB: 'keypath' not 'path' — a local named 'path' is a zsh special tied to $PATH;
	# clobbering it makes jq unfindable inside this function under zsh.
	local file="${1:?manifest file}" keypath="${2:?jq path}" value="${3:?json value}" tmp
	if [ "${WP_BUILD_RETURN_FRAGMENT:-}" = "1" ]; then
		_manifest_emit_fragment set "$value" "$keypath"
		return 0
	fi
	tmp="$(_manifest_tmp)"
	jq "${keypath} = (${value})" "$file" > "$tmp" && mv "$tmp" "$file"
}

# Generic deep-merge. Args: <file> <json-object>
#   _manifest_merge "./wp-build.json" '{"source":{"type":"html-files"}}'
_manifest_merge() {
	_manifest_require_jq || return 1
	local file="${1:?manifest file}" value="${2:?json object}" tmp
	if [ "${WP_BUILD_RETURN_FRAGMENT:-}" = "1" ]; then
		_manifest_emit_fragment merge "$value"
		return 0
	fi
	tmp="$(_manifest_tmp)"
	jq ". * (${value})" "$file" > "$tmp" && mv "$tmp" "$file"
}

# Record stage progress. Args: <file> <stage-id> <state> [notes]
# state: pending | in-progress | done | failed | skipped
_manifest_progress() {
	_manifest_require_jq || return 1
	local file="${1:?manifest file}" stage="${2:?stage id}" state="${3:?state}" notes="${4:-}" ts tmp
	if [ "${WP_BUILD_RETURN_FRAGMENT:-}" = "1" ]; then
		_manifest_emit_fragment progress "$stage" "$state" "$notes"
		return 0
	fi
	ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	tmp="$(_manifest_tmp)"
	jq --arg s "$stage" --arg st "$state" --arg n "$notes" --arg ts "$ts" \
		'.progress[$s] = {status: $st, updatedAt: $ts, notes: $n}' \
		"$file" > "$tmp" && mv "$tmp" "$file"
}

# Return 0 if a stage is already done. Args: <file> <stage-id>
_manifest_is_done() {
	_manifest_require_jq || return 1
	local file="${1:?manifest file}" stage="${2:?stage id}"
	[ "$(jq -r --arg s "$stage" '.progress[$s].status // "pending"' "$file")" = "done" ]
}

# Print a human progress summary. Arg: <file>
_manifest_status() {
	_manifest_require_jq || return 1
	local file="${1:?manifest file}" name
	name="$(_manifest_get "$file" '.project.name // .plugin.name // ""' 2>/dev/null)"
	[ -n "$name" ] && echo "Project — $name" || echo "Manifest — $file"
	jq -r '.progress | to_entries[] | "  \(.key): \(.value.status)"' "$file" 2>/dev/null \
		|| echo "  (no progress yet)"
}
