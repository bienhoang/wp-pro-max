#!/usr/bin/env bash
# migrate-urls.sh — safe `wp search-replace` wrapper for the ship stage.
#
# Migrates every occurrence of the local URL to the production URL (or any
# explicit from→to pair) across all WordPress tables, handling PHP-serialized
# data correctly. It is SAFE BY DEFAULT: it always runs a `--dry-run` first and
# prints the change count; nothing is written unless you pass `--apply`.
#
# Reads `urls.local` and `urls.production` from the pipeline manifest
# (wp-build.json) when --from/--to are not given on the command line.
#
# Usage:
#   # Preview only (default) — reads urls.* from the manifest:
#   bash migrate-urls.sh
#
#   # Actually apply the replacement:
#   bash migrate-urls.sh --apply
#
#   # Explicit pair, override the manifest:
#   bash migrate-urls.sh --from http://localhost:8888 --to https://acme.com --apply
#
#   # Produce a migrated SQL dump WITHOUT touching the live DB:
#   bash migrate-urls.sh --export migrated.sql
#
#   # Run against a REMOTE host over SSH (configure the runner):
#   WP_CLI_RUN="ssh deploy@acme.com wp --path=/var/www/acme" \
#     bash migrate-urls.sh --apply
#
# All WordPress CLI runs go through wp-env by default. Override with WP_CLI_RUN:
#   WP_CLI_RUN="wp-env run cli wp"        # default (local Docker WordPress)
#   WP_CLI_RUN="wp"                       # local WP-CLI directly
#   WP_CLI_RUN="ssh user@host wp --path=/var/www/site"   # remote over SSH
#
# Requires: jq (only when reading URLs from the manifest).
set -euo pipefail

_MIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_MIG_DIR}/manifest-lib.sh"

# ---------------------------------------------------------------------------
# WP-CLI runner (same convention as seed-helpers.sh)
# ---------------------------------------------------------------------------
# shellcheck disable=SC2206
read -r -a _WP_CLI_RUN_ARR <<< "${WP_CLI_RUN:-wp-env run cli wp}"

wp_cli() {
  "${_WP_CLI_RUN_ARR[@]}" "$@"
}

_mig_log() { printf 'migrate-urls: %s\n' "$*" >&2; }
_mig_die() { _mig_log "ERROR: $*"; exit 1; }

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
FROM=""
TO=""
APPLY=0
EXPORT_FILE=""
INCLUDE_GUID=0
NETWORK=0
PRECISE=0
declare -a EXTRA_ARGS=()

_usage() {
  sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)        FROM="${2:?--from needs a value}"; shift 2 ;;
    --to)          TO="${2:?--to needs a value}"; shift 2 ;;
    --apply)       APPLY=1; shift ;;
    --export)      EXPORT_FILE="${2:?--export needs a file path}"; shift 2 ;;
    --include-guid) INCLUDE_GUID=1; shift ;;
    --network)     NETWORK=1; shift ;;
    --precise)     PRECISE=1; shift ;;
    --)            shift; EXTRA_ARGS+=("$@"); break ;;
    -h|--help)     _usage 0 ;;
    *)             _mig_die "unknown argument: $1 (use --help)" ;;
  esac
done

# ---------------------------------------------------------------------------
# Resolve the from→to URL pair (CLI flags win; else read the manifest)
# ---------------------------------------------------------------------------
if [[ -z "$FROM" || -z "$TO" ]]; then
  [[ -f "$WP_BUILD_FILE" ]] || _mig_die "no --from/--to given and manifest '$WP_BUILD_FILE' not found"
  [[ -z "$FROM" ]] && FROM="$(wpbuild_get '.urls.local // empty')"
  [[ -z "$TO"   ]] && TO="$(wpbuild_get '.urls.production // empty')"
fi

[[ -n "$FROM" ]] || _mig_die "source URL is empty (set urls.local in the manifest or pass --from)"
[[ -n "$TO"   ]] || _mig_die "target URL is empty (set urls.production in the manifest or pass --to)"
[[ "$FROM" != "$TO" ]] || _mig_die "source and target URLs are identical ('$FROM') — nothing to do"

# ---------------------------------------------------------------------------
# Build the shared search-replace argument list
# ---------------------------------------------------------------------------
# --all-tables-with-prefix : cover every table for this install's prefix so
#                            serialized data in plugin tables is migrated too.
# --skip-columns=guid      : GUIDs are permanent identifiers, not live links —
#                            rewriting them breaks feed/import dedupe (default).
# --recurse-objects        : walk into serialized arrays/objects (the whole point).
# --report-changed-only    : keep the preview readable.
build_sr_args() {
  local -n _out="$1"
  _out=("$FROM" "$TO" --all-tables-with-prefix --recurse-objects --report-changed-only)
  [[ "$INCLUDE_GUID" -eq 1 ]] || _out+=(--skip-columns=guid)
  [[ "$NETWORK"      -eq 1 ]] && _out+=(--network)
  [[ "$PRECISE"      -eq 1 ]] && _out+=(--precise)
  if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then _out+=("${EXTRA_ARGS[@]}"); fi
}

declare -a SR_ARGS
build_sr_args SR_ARGS

_mig_log "from : $FROM"
_mig_log "to   : $TO"
_mig_log "guid : $([[ "$INCLUDE_GUID" -eq 1 ]] && echo 'rewritten' || echo 'skipped (default)')"

# ---------------------------------------------------------------------------
# Export mode: dump a migrated SQL file, never touch the live DB.
# Strategy: snapshot → search-replace --export (DB stays untouched because
# --export writes the rewritten rows to a file instead of the database).
# ---------------------------------------------------------------------------
if [[ -n "$EXPORT_FILE" ]]; then
  _mig_log "export mode → $EXPORT_FILE (live database is NOT modified)"
  wp_cli search-replace "${SR_ARGS[@]}" --export="$EXPORT_FILE"
  _mig_log "wrote migrated SQL dump: $EXPORT_FILE"
  exit 0
fi

# ---------------------------------------------------------------------------
# Step 1 — ALWAYS dry-run first and surface the change count.
# ---------------------------------------------------------------------------
_mig_log "running dry-run preview…"
DRY_OUT="$(wp_cli search-replace "${SR_ARGS[@]}" --dry-run 2>&1)" || {
  printf '%s\n' "$DRY_OUT" >&2
  _mig_die "dry-run failed (is WP reachable via '${_WP_CLI_RUN_ARR[*]}'?)"
}
printf '%s\n' "$DRY_OUT"

# Sum the "replacements" column from the WP-CLI table output for a total.
CHANGE_COUNT="$(printf '%s\n' "$DRY_OUT" \
  | awk -F'|' 'NF>=5 && $4 ~ /[0-9]+/ { gsub(/[^0-9]/,"",$4); s+=$4 } END { print s+0 }')"
_mig_log "dry-run total replacements: ${CHANGE_COUNT}"

# ---------------------------------------------------------------------------
# Step 2 — Apply only with explicit --apply.
# ---------------------------------------------------------------------------
if [[ "$APPLY" -ne 1 ]]; then
  _mig_log "DRY-RUN ONLY. Re-run with --apply to write these ${CHANGE_COUNT} change(s)."
  exit 0
fi

if [[ "$CHANGE_COUNT" -eq 0 ]]; then
  _mig_log "nothing to replace (0 changes) — skipping apply."
  exit 0
fi

_mig_log "applying ${CHANGE_COUNT} replacement(s)…"
wp_cli search-replace "${SR_ARGS[@]}"
_mig_log "search-replace applied. Remember to: wp rewrite flush && wp cache flush"
