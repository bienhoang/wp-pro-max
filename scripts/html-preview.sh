#!/usr/bin/env bash
# html-preview.sh — open an HTML file in the default browser.
# Usage: bash html-preview.sh <path-to-html>

set -euo pipefail

FILE="${1:-}"

if [ -z "$FILE" ]; then
	echo "Usage: html-preview.sh <path-to-html>" >&2
	exit 2
fi

if [ ! -f "$FILE" ]; then
	echo "html-preview: file not found: $FILE" >&2
	exit 1
fi

ABSOLUTE="$(cd "$(dirname "$FILE")" && pwd)/$(basename "$FILE")"

case "$(uname -s)" in
	Darwin*)
		open "$ABSOLUTE"
		;;
	Linux*)
		xdg-open "$ABSOLUTE"
		;;
	CYGWIN*|MINGW*|MSYS*)
		start "$ABSOLUTE"
		;;
	*)
		echo "html-preview: unsupported platform; open $ABSOLUTE manually" >&2
		exit 1
		;;
esac
