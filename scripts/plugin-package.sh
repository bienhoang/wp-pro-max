#!/usr/bin/env bash
# plugin-package.sh — build a distributable .zip from an explicit allowlist.
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

# Load manifest helpers ------------------------------------------------------
export WP_PLUGIN_FILE="${WP_PLUGIN_FILE:-./wp-plugin.json}"
# shellcheck source=plugin-manifest-lib.sh
source "${_SCRIPT_DIR}/plugin-manifest-lib.sh"

if [ ! -f "$WP_PLUGIN_FILE" ]; then
	echo "plugin-package: $WP_PLUGIN_FILE not found" >&2
	exit 1
fi

SLUG="$(wpplugin_get '.plugin.slug')"
VERSION="$(wpplugin_get '.plugin.version // "0.1.0"')"
HAS_BLOCK="$(wpplugin_get '.tooling.blockBuild // false')"
HAS_COMPOSER="$(wpplugin_get '.tooling.composer // false')"

DIST_DIR="dist"
ZIP_FILE="${DIST_DIR}/${SLUG}-${VERSION}.zip"

# Validate environment -------------------------------------------------------
if ! command -v zip >/dev/null 2>&1; then
	echo "plugin-package: 'zip' command not found" >&2
	exit 1
fi

# Build steps ----------------------------------------------------------------
if [ "$HAS_BLOCK" = "true" ] && [ -f package.json ]; then
	if ! command -v npm >/dev/null 2>&1; then
		echo "plugin-package: npm not found (required for block build)" >&2
		exit 1
	fi
	npm install
	npm run build
fi

if [ "$HAS_COMPOSER" = "true" ] && [ -f composer.json ]; then
	if ! command -v npx >/dev/null 2>&1; then
		echo "plugin-package: npx not found (required for Composer via wp-env)" >&2
		exit 1
	fi
	npx @wordpress/env run cli bash -c "cd /var/www/html/wp-content/plugins/${SLUG} && composer install --no-dev --no-interaction --prefer-dist"
fi

# Build zip from allowlist ---------------------------------------------------
mkdir -p "$DIST_DIR"
rm -f "$ZIP_FILE"

# Assemble explicit top-level entries.
ALLOWED=("${SLUG}.php" uninstall.php readme.txt inc src languages)
[ "$HAS_COMPOSER" = "true" ] && [ -d vendor ] && ALLOWED+=(vendor)

BLOCK_BUILDS=()
if [ "$HAS_BLOCK" = "true" ]; then
	for d in blocks/*/build; do
		[ -d "$d" ] && BLOCK_BUILDS+=("$d")
	done
	if [ ${#BLOCK_BUILDS[@]} -eq 0 ]; then
		echo "plugin-package: block build directories missing" >&2
		exit 1
	fi
fi

# Check that every requested entry exists.
for entry in "${ALLOWED[@]}"; do
	if [ ! -e "$entry" ]; then
		echo "plugin-package: expected entry missing: $entry" >&2
		exit 1
	fi
done

zip -r "$ZIP_FILE" "${ALLOWED[@]}" "${BLOCK_BUILDS[@]}" -x "*.DS_Store" -x "*.git*"

# Post-zip assertions --------------------------------------------------------
ERRORS=0

# 1. No non-allowlisted top-level entries.
TOP_LEVELS=$(unzip -Z -1 "$ZIP_FILE" | awk -F'/' 'NF>=1 {print $1}' | sort -u)
for entry in $TOP_LEVELS; do
	case "$entry" in
		"${SLUG}.php"|uninstall.php|readme.txt|inc|src|languages|blocks|vendor)
			;;
		*)
			echo "plugin-package: non-allowlisted top-level entry in zip: $entry" >&2
			ERRORS=$((ERRORS + 1))
			;;
	esac
done

# 2. Secret / dev file patterns.
SECRET_HITS=$(unzip -Z -1 "$ZIP_FILE" | grep -E '(/|^)\.env($|/)|\.key$|\.pem$|wp-config\.php$|wp-plugin\.json$|\.wp-env\.json$|composer\.json$|package\.json$|phpcs\.xml\.dist$|phpunit\.xml\.dist$|node_modules/' || true)
if [ -n "$SECRET_HITS" ]; then
	echo "plugin-package: disallowed files in zip:" >&2
	printf '%s\n' "$SECRET_HITS" >&2
	ERRORS=$((ERRORS + 1))
fi

# 3. Every declared block has build/block.json.
if [ "$HAS_BLOCK" = "true" ]; then
	for block_dir in blocks/*/; do
		[ -d "$block_dir" ] || continue
		name="$(basename "$block_dir")"
		if [ ! -f "${block_dir}build/block.json" ]; then
			echo "plugin-package: block $name missing build/block.json" >&2
			ERRORS=$((ERRORS + 1))
		fi
		zip_list="$(unzip -Z -1 "$ZIP_FILE")"
		if ! printf '%s\n' "$zip_list" | grep -q "^blocks/${name}/build/block\.json$"; then
			echo "plugin-package: blocks/${name}/build/block.json not in zip" >&2
			echo "plugin-package: zip entries:" >&2
			printf '%s\n' "$zip_list" | grep "blocks/${name}" >&2
			ERRORS=$((ERRORS + 1))
		fi
	done
fi

if [ "$ERRORS" -gt 0 ]; then
	rm -f "$ZIP_FILE"
	echo "plugin-package: packaging failed ($ERRORS error(s))" >&2
	exit 1
fi

echo "plugin-package: built $ZIP_FILE" >&2
