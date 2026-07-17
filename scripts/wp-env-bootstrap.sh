#!/usr/bin/env bash
# wp-env-bootstrap.sh — scaffold .wp-env.json from the manifest, start wp-env,
# set permalinks, and flush rewrites. Idempotent: safe to re-run.
#
# Usage (from the target project root, where wp-build.json + .wp-env.json live):
#   bash "${CLAUDE_PLUGIN_ROOT}/scripts/wp-env-bootstrap.sh" [--force]
#
# Reads strategy / builder / plugins / project.themeSlug / theme / env from the
# manifest via manifest-lib.sh. Requires: jq, node (npx), Docker running.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/manifest-lib.sh"

FORCE="${1:-}"
WPENV_FILE="${WPENV_FILE:-./.wp-env.json}"

_log() { printf 'wp-env-bootstrap: %s\n' "$*" >&2; }

_require() {
  command -v "$1" >/dev/null 2>&1 || { _log "'$1' is required but not found"; exit 1; }
}

# Resolve the wp-env runner: prefer a global `wp-env`, else `npx wp-env`.
_wpenv() {
  if command -v wp-env >/dev/null 2>&1; then
    wp-env "$@"
  else
    npx --yes @wordpress/env "$@"
  fi
}

main() {
  _require jq
  [[ -f "$WP_BUILD_FILE" ]] || { _log "manifest $WP_BUILD_FILE not found — run earlier stages first"; exit 1; }

  # ---- Read manifest values (with defaults) -------------------------------
  local slug theme_path port php_version wp_version env_type debug
  slug="$(wpbuild_get '.project.themeSlug')"
  theme_path="$(wpbuild_get '.theme.path // ("wp-content/themes/" + .project.themeSlug)')"
  port="$(wpbuild_get '.env.port // 8888')"
  php_version="$(wpbuild_get '.env.phpVersion // "8.2"')"
  # core: null => latest; honor an explicit env.wpVersion ref when set.
  wp_version="$(wpbuild_get '.env.wpVersion // empty')"
  env_type="local"
  debug=true

  # wordpress.org plugin slugs only (premium ZIPs handled manually).
  # wp-env's `plugins` entries must be a local path or a URL to a .zip — bare
  # slugs are rejected ("Invalid or unrecognized source"), so resolve each
  # wporg slug to its canonical downloads.wordpress.org zip URL.
  local plugins_json
  plugins_json="$(wpbuild_get '[ .plugins[]? | select(.source=="wporg" or (has("source")|not)) | "https://downloads.wordpress.org/plugin/" + .slug + ".zip" ]')"
  [[ "$plugins_json" == "null" || -z "$plugins_json" ]] && plugins_json='[]'

  # core value: a JSON null (latest) or a quoted ref string.
  local core_json='null'
  if [[ -n "$wp_version" && "$wp_version" != "null" ]]; then
    core_json="$(jq -n --arg v "$wp_version" '$v')"
  fi

  # Mount the optimized source dir so the seed batch (seed-batch-runtime.php) can
  # reach media by an absolute container path (red-team H1 / validated decision 1).
  # Mapped at wp-content/uploads/wppm-src → host optimization.outputDir; the seed
  # payload's mediaPathPrefix points at /var/www/html/wp-content/uploads/wppm-src/.
  # Skipped when outputDir is unset or "." (mounting the whole project root is
  # avoided; in that case rely on payload.mediaPathPrefix instead).
  local outdir extra_mappings='{}'
  outdir="$(wpbuild_get '.optimization.outputDir // empty')"
  if [[ -n "$outdir" && "$outdir" != "null" && "$outdir" != "." ]]; then
    extra_mappings="$(jq -n --arg src "$outdir" '{ "wp-content/uploads/wppm-src": $src }')"
    _log "mounting optimized source '$outdir' → wp-content/uploads/wppm-src"
  fi

  # ---- Render .wp-env.json -------------------------------------------------
  # Idempotent: regenerate from the manifest each run (manifest is source of truth).
  if [[ -f "$WPENV_FILE" && "$FORCE" != "--force" ]]; then
    _log "$WPENV_FILE exists — regenerating from manifest (use a backup if hand-edited)"
  fi

  local tmp
  tmp="$(mktemp)"
  jq -n \
    --argjson core "$core_json" \
    --arg php "$php_version" \
    --argjson plugins "$plugins_json" \
    --arg theme "./${theme_path}" \
    --arg themedest "$theme_path" \
    --argjson port "$port" \
    --argjson debug "$debug" \
    --arg envtype "$env_type" \
    --argjson extra "$extra_mappings" \
    '{
      core: $core,
      phpVersion: $php,
      plugins: $plugins,
      themes: [ $theme ],
      port: $port,
      config: {
        WP_DEBUG: $debug,
        WP_DEBUG_LOG: $debug,
        WP_DEBUG_DISPLAY: false,
        WP_ENVIRONMENT_TYPE: $envtype
      },
      mappings: ( { ($themedest): $theme } + $extra )
    }' > "$tmp"
  mv "$tmp" "$WPENV_FILE"
  _log "wrote $WPENV_FILE (php=$php_version, port=$port, plugins=$(jq 'length' <<<"$plugins_json"))"

  # ---- Start wp-env (idempotent; re-runs reprovision) ----------------------
  _log "starting wp-env (Docker) ..."
  _wpenv start

  # ---- Activate theme (best-effort; theme may be scaffolded later) ---------
  if _wpenv run cli wp theme list --field=name 2>/dev/null | grep -qx "$slug"; then
    _wpenv run cli wp theme activate "$slug" || _log "theme activate failed (non-fatal)"
  else
    _log "theme '$slug' not present yet — skipping activation (run after convert/scaffold)"
  fi

  # ---- Permalinks + rewrite flush (idempotent) -----------------------------
  local current
  current="$(_wpenv run cli wp option get permalink_structure 2>/dev/null || echo '')"
  if [[ "$current" != "/%postname%/" ]]; then
    _wpenv run cli wp rewrite structure '/%postname%/' --hard
  fi
  _wpenv run cli wp rewrite flush --hard

  _log "done — WordPress at http://localhost:${port}"
}

main "$@"
