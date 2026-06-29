#!/usr/bin/env bash
# html-section-lib.sh — shared HTML section operations for site-editor skills.
# Sourced library: no top-level set -e, safe for bash and zsh.
#
# Functions:
#   section_find <html-file> <selector>
#   section_replace <html-file> <selector> <new-html-file>
#   section_insert_before <html-file> <selector> <new-html-file>
#   section_insert_after <html-file> <selector> <new-html-file>
#   section_remove <html-file> <selector>
#   section_reorder <html-file> <ordered-selectors-file>
#   section_backup <html-file> <backup-dir>

if [ -n "${BASH_VERSION:-}" ]; then
	_HTML_SECTION_LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
elif [ -n "${ZSH_VERSION:-}" ]; then
	_HTML_SECTION_LIB_DIR="$(dirname "${(%):-%x}")"
fi

_HTML_SECTION_CLI="${_HTML_SECTION_LIB_DIR}/html-section-cli.mjs"

# Ensure cheerio is available for the CLI helper. Installs into the plugin root
# (where this script lives) so the CLI can require it reliably.
_ensure_cheerio() {
	node -e "require('cheerio')" >/dev/null 2>&1 && return 0
	echo "html-section-lib: installing cheerio (one-time)…" >&2
	(cd "${_HTML_SECTION_LIB_DIR}/.." && npm install cheerio --no-save) >/dev/null 2>&1 || {
		echo "html-section-lib: failed to install cheerio" >&2
		return 1
	}
}

section_find() {
	local file="${1:?html file}" selector="${2:?selector}"
	_ensure_cheerio || return 1
	node "${_HTML_SECTION_CLI}" find "$file" "$selector"
}

section_replace() {
	local file="${1:?html file}" selector="${2:?selector}" newfile="${3:?new html file}"
	_ensure_cheerio || return 1
	node "${_HTML_SECTION_CLI}" replace "$file" "$selector" "$newfile"
}

section_insert_before() {
	local file="${1:?html file}" selector="${2:?selector}" newfile="${3:?new html file}"
	_ensure_cheerio || return 1
	node "${_HTML_SECTION_CLI}" insert-before "$file" "$selector" "$newfile"
}

section_insert_after() {
	local file="${1:?html file}" selector="${2:?selector}" newfile="${3:?new html file}"
	_ensure_cheerio || return 1
	node "${_HTML_SECTION_CLI}" insert-after "$file" "$selector" "$newfile"
}

section_remove() {
	local file="${1:?html file}" selector="${2:?selector}"
	_ensure_cheerio || return 1
	node "${_HTML_SECTION_CLI}" remove "$file" "$selector"
}

section_reorder() {
	local file="${1:?html file}" selectors_file="${2:?selectors file}"
	_ensure_cheerio || return 1
	node "${_HTML_SECTION_CLI}" reorder "$file" "$selectors_file"
}

section_backup() {
	local file="${1:?html file}" backup_dir="${2:?backup dir}"
	[ -f "$file" ] || { echo "section_backup: file not found: $file" >&2; return 1; }
	mkdir -p "$backup_dir"
	local name
	name="$(basename "$file")"
	cp "$file" "${backup_dir}/${name}"
}
