#!/usr/bin/env bash
# plugin-env-bootstrap.sh — generate a plugin-local .wp-env.json and start wp-env.
#
# Run from the plugin project root (where wp-plugin.json lives).

set -euo pipefail

# Resolve paths -------------------------------------------------------------
if [ -n "${BASH_VERSION:-}" ]; then
	_SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
elif [ -n "${ZSH_VERSION:-}" ]; then
	_SCRIPT_DIR="$(dirname "${(%):-%x}")"
fi
_CLAUDE_PLUGIN_ROOT="${_SCRIPT_DIR}/.."
_REFERENCE_DIR="${_CLAUDE_PLUGIN_ROOT}/skills/wp-plugin-dev/references"

# Load manifest helpers ------------------------------------------------------
export WP_PLUGIN_FILE="${WP_PLUGIN_FILE:-./wp-plugin.json}"
# shellcheck source=plugin-manifest-lib.sh
source "${_SCRIPT_DIR}/plugin-manifest-lib.sh"

if [ ! -f "$WP_PLUGIN_FILE" ]; then
	echo "plugin-env-bootstrap: $WP_PLUGIN_FILE not found" >&2
	exit 1
fi

SLUG="$(wpplugin_get '.plugin.slug')"
NAMESPACE="$(wpplugin_get '.plugin.namespace')"
TEXTDOMAIN="$(wpplugin_get '.plugin.textDomain')"
NAME="$(wpplugin_get '.plugin.name')"
VERSION="$(wpplugin_get '.plugin.version // "0.1.0"')"
WP_VERSION="$(wpplugin_get '.env.wpVersion // "latest"')"
PHP_VERSION="$(wpplugin_get '.env.phpVersion // "8.2"')"
PORT="$(wpplugin_get '.env.port // 8888')"

# Emit .wp-env.json ----------------------------------------------------------
if [ ! -f .wp-env.json ]; then
	jq -n \
		--arg slug "$SLUG" \
		--arg wp "$WP_VERSION" \
		--arg php "$PHP_VERSION" \
		'{
			core: (if $wp == "latest" then "WordPress/WordPress" else "WordPress/WordPress#" + $wp end),
			phpVersion: $php,
			plugins: [],
			mappings: { ("wp-content/plugins/" + $slug): "." }
		}' > .wp-env.json
	echo "plugin-env-bootstrap: wrote .wp-env.json" >&2
fi

_extract_tooling() {
	local marker="$1"
	local md="${_REFERENCE_DIR}/tooling.md"
	awk -v m="$marker" '
		$0 ~ "^<!-- file: " m " -->$" { found = 1; next }
		found && /^```/ {
			if (inblock) { exit }
			inblock = 1
			next
		}
		found && inblock { print }
	' "$md"
}

_tokenize_common() {
	sed \
		-e "s|__SLUG__|$SLUG|g" \
		-e "s|__NAMESPACE__|$NAMESPACE|g" \
		-e "s|__TEXTDOMAIN__|$TEXTDOMAIN|g" \
		-e "s|__NAME__|$NAME|g" \
		-e "s|__VERSION__|$VERSION|g"
}

# Always ensure tooling stubs are present; they are harmless if unused.
ensure_tooling() {
	local composer_body phpcs_body phpunit_body test_body
	composer_body="$(_extract_tooling composer.json | _tokenize_common)"
	phpcs_body="$(_extract_tooling phpcs.xml.dist | _tokenize_common)"
	phpunit_body="$(_extract_tooling phpunit.xml.dist | _tokenize_common)"
	test_body="$(_extract_tooling tests/test-activation.php | _tokenize_common)"

	local bootstrap_body
	bootstrap_body="$(_extract_tooling tests/bootstrap.php | _tokenize_common)"

	[ -f composer.json ]    || printf '%s\n' "$composer_body" > composer.json
	[ -f phpcs.xml.dist ]   || printf '%s\n' "$phpcs_body" > phpcs.xml.dist
	[ -f phpunit.xml.dist ] || printf '%s\n' "$phpunit_body" > phpunit.xml.dist
	[ -f tests/bootstrap.php ] || { mkdir -p tests; printf '%s\n' "$bootstrap_body" > tests/bootstrap.php; }
	[ -f tests/test-activation.php ] || printf '%s\n' "$test_body" > tests/test-activation.php

	wpplugin_set '.tooling.composer' 'true'
	wpplugin_set '.tooling.phpcs' 'true'
	wpplugin_set '.tooling.phpunit' 'true'
}

ensure_tooling

# Start wp-env ---------------------------------------------------------------
if ! command -v npx >/dev/null 2>&1; then
	echo "plugin-env-bootstrap: npx not found; install Node >= 20" >&2
	exit 1
fi

npx @wordpress/env start

echo "plugin-env-bootstrap: wp-env started on http://localhost:$PORT" >&2
