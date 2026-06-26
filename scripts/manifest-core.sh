#!/usr/bin/env bash
# manifest-core.sh — generic, zsh-safe helpers to read/write a JSON manifest.
#
# This file is SOURCED by wrapper libraries (manifest-lib.sh, plugin-manifest-lib.sh).
# It does NOT enable `set -e` at the top level and avoids zsh-reserved names.
#
# The wrappers bind a concrete manifest file path; these functions accept the file
# as their first argument, so one implementation serves both pipelines.

_manifest_require_jq() {
	command -v jq >/dev/null 2>&1 || { echo "manifest-core: 'jq' is required" >&2; return 1; }
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
	local file="${1:?manifest file}" path="${2:?jq path}" value="${3:?json value}" tmp
	tmp="$(_manifest_tmp)"
	jq "${path} = (${value})" "$file" > "$tmp" && mv "$tmp" "$file"
}

# Generic deep-merge. Args: <file> <json-object>
#   _manifest_merge "./wp-build.json" '{"source":{"type":"html-files"}}'
_manifest_merge() {
	_manifest_require_jq || return 1
	local file="${1:?manifest file}" value="${2:?json object}" tmp
	tmp="$(_manifest_tmp)"
	jq ". * (${value})" "$file" > "$tmp" && mv "$tmp" "$file"
}

# Record stage progress. Args: <file> <stage-id> <state> [notes]
# state: pending | in-progress | done | failed | skipped
_manifest_progress() {
	_manifest_require_jq || return 1
	local file="${1:?manifest file}" stage="${2:?stage id}" state="${3:?state}" notes="${4:-}" ts tmp
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
