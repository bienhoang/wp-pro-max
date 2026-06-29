#!/usr/bin/env bash
# site-editor-lib.sh — reusable parsing and guard logic for the site-editor command.
# Sourced library: no top-level set -e.

# Resolve project root (handles parent-wrapper wp/ layout) and guard on manifest.
# Sets: SITE_EDITOR_ROOT, SITE_EDITOR_MANIFEST, SITE_EDITOR_OUTDIR
site_editor_require_manifest_and_outdir() {
	if [ -n "${BASH_VERSION:-}" ]; then
		local here="$(pwd)"
	elif [ -n "${ZSH_VERSION:-}" ]; then
		local here="$(pwd)"
	fi

	if [ ! -f "${WP_BUILD_FILE:-./wp-build.json}" ] && [ -f "./wp/wp-build.json" ]; then
		cd ./wp || return 1
	fi
	SITE_EDITOR_ROOT="$(pwd)"
	SITE_EDITOR_MANIFEST="${WP_BUILD_FILE:-./wp-build.json}"

	[ -f "$SITE_EDITOR_MANIFEST" ] || { echo "site-editor: wp-build.json not found" >&2; return 1; }

	local outdir
	outdir="$(jq -r '.optimization.outputDir // ""' "$SITE_EDITOR_MANIFEST")"
	[ -n "$outdir" ] && [ -d "$outdir" ] || { echo "site-editor: optimized copy missing" >&2; return 1; }
	SITE_EDITOR_OUTDIR="$outdir"
}

# Parse site-editor arguments. Sets:
#   SITE_EDITOR_ACTION, SITE_EDITOR_REDESIGN, SITE_EDITOR_PAGE, SITE_EDITOR_ADD_PAGES,
#   SITE_EDITOR_FROM_BRIEF, SITE_EDITOR_ENRICH, SITE_EDITOR_APPROVE,
#   SITE_EDITOR_CHECK_MODE, SITE_EDITOR_PREVIEW, SITE_EDITOR_REVERT, SITE_EDITOR_ALL
site_editor_parse_args() {
	SITE_EDITOR_ACTION=""
	SITE_EDITOR_REDESIGN=""
	SITE_EDITOR_PAGE=""
	SITE_EDITOR_ADD_PAGES=""
	SITE_EDITOR_FROM_BRIEF=""
	SITE_EDITOR_ENRICH=""
	SITE_EDITOR_APPROVE=""
	SITE_EDITOR_CHECK_MODE="--quick"
	SITE_EDITOR_PREVIEW=""
	SITE_EDITOR_REVERT=""
	SITE_EDITOR_ALL=""

	while [ $# -gt 0 ]; do
		case "$1" in
			--redesign)
				[ $# -ge 2 ] || { echo "site-editor: --redesign requires instructions" >&2; return 2; }
				SITE_EDITOR_ACTION="redesign"; SITE_EDITOR_REDESIGN="$2"; shift 2 ;;
			--page)
				[ $# -ge 2 ] || { echo "site-editor: --page requires a path" >&2; return 2; }
				SITE_EDITOR_PAGE="$2"; shift 2 ;;
			--add-pages)
				[ $# -ge 2 ] || { echo "site-editor: --add-pages requires a list" >&2; return 2; }
				SITE_EDITOR_ACTION="add-pages"; SITE_EDITOR_ADD_PAGES="$2"; shift 2 ;;
			--from-brief)
				SITE_EDITOR_ACTION="add-pages"; SITE_EDITOR_FROM_BRIEF=1; shift ;;
			--enrich)
				[ $# -ge 2 ] || { echo "site-editor: --enrich requires instructions" >&2; return 2; }
				SITE_EDITOR_ACTION="enrich"; SITE_EDITOR_ENRICH="$2"; shift 2 ;;
			--approve)
				SITE_EDITOR_ACTION="approve"; SITE_EDITOR_APPROVE=1; shift ;;
			--check)
				SITE_EDITOR_ACTION="check"; shift
				if [ $# -gt 0 ] && { [ "$1" = "--quick" ] || [ "$1" = "--thorough" ]; }; then
					SITE_EDITOR_CHECK_MODE="$1"; shift
				fi ;;
			--preview)
				SITE_EDITOR_ACTION="preview"; SITE_EDITOR_PREVIEW=1; shift ;;
			--revert)
				SITE_EDITOR_ACTION="revert"; SITE_EDITOR_REVERT=1; shift ;;
			--all)
				SITE_EDITOR_ACTION="all"; SITE_EDITOR_ALL=1; shift
				if [ $# -gt 0 ] && { [ "$1" = "--quick" ] || [ "$1" = "--thorough" ]; }; then
					SITE_EDITOR_CHECK_MODE="$1"; shift
				fi ;;
			--)
				shift; break ;;
			-*)
				echo "site-editor: unknown option $1" >&2; return 2 ;;
			*)
				echo "site-editor: unexpected argument $1" >&2; return 2 ;;
			esac
	done
}
