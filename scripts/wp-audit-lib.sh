#!/usr/bin/env bash
# wp-audit-lib.sh — argument parsing and wp-env detection for /wp-pro-max:audit.
# Sourced library: no top-level set -e, zsh-safe.

# Parse $ARGUMENTS from the command invocation.
# Sets:
#   AUDIT_SCOPE    self|all
#   AUDIT_MODE     static|live|auto
#   AUDIT_FORMAT   md|json|both
#   AUDIT_OUT_DIR  directory for final JSON report
#   AUDIT_DOCS_DIR directory for Markdown report
#   AUDIT_WORK_DIR directory for intermediate scanner JSON
audit_parse_args() {
  AUDIT_SCOPE="self"
  AUDIT_MODE="auto"
  AUDIT_FORMAT="both"
  AUDIT_OUT_DIR="."
  AUDIT_DOCS_DIR=""
  AUDIT_WORK_DIR="./audit"

  while [ $# -gt 0 ]; do
    case "$1" in
      --scope)
        [ $# -ge 2 ] || { echo "audit: --scope requires self|all" >&2; return 2; }
        case "$2" in
          self|all) AUDIT_SCOPE="$2" ;;
          *) echo "audit: --scope must be self or all" >&2; return 2 ;;
        esac
        shift 2 ;;
      --live)
        AUDIT_MODE="live"; shift ;;
      --static)
        AUDIT_MODE="static"; shift ;;
      --format)
        [ $# -ge 2 ] || { echo "audit: --format requires md|json|both" >&2; return 2; }
        case "$2" in
          md|json|both) AUDIT_FORMAT="$2" ;;
          *) echo "audit: --format must be md, json, or both" >&2; return 2 ;;
        esac
        shift 2 ;;
      --out)
        [ $# -ge 2 ] || { echo "audit: --out requires a directory" >&2; return 2; }
        AUDIT_OUT_DIR="$2"; shift 2 ;;
      --docs-dir)
        [ $# -ge 2 ] || { echo "audit: --docs-dir requires a directory" >&2; return 2; }
        AUDIT_DOCS_DIR="$2"; shift 2 ;;
      --)
        shift; break ;;
      -*)
        echo "audit: unknown option $1" >&2; return 2 ;;
      *)
        echo "audit: unexpected argument $1" >&2; return 2 ;;
    esac
  done
}

# Resolve the wp-env runner: prefer a global `wp-env`, else `npx @wordpress/env`.
# Mirrors the runner in scripts/wp-env-bootstrap.sh so projects that depend on
# `npx @wordpress/env` (no global install) are detected instead of failing fast.
audit_wp_env_run() {
  if command -v wp-env >/dev/null 2>&1; then
    wp-env "$@"
  else
    npx --yes @wordpress/env "$@"
  fi
}

# Return 0 if wp-env is reachable.
audit_wp_env_reachable() {
  audit_wp_env_run run cli wp option get siteurl >/dev/null 2>&1
}
