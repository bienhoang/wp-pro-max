#!/usr/bin/env bash
# seed-helpers.sh — DEPRECATED (retained as a shim). The seed stages now run as a
# single PHP batch: build a pure-JSON payload and apply it via
#   scripts/seed-batch-run.sh <payload.json>   →   wp eval-file seed-batch-runtime.php
# (one container call per stage, idempotent, ~20× faster). See
# scripts/seed-batch-runtime.php, scripts/seed-batch-run.sh, scripts/wp-cli-runner.sh
# and the content-seeding / plugin-data-seeding skills. Do NOT add new callers.
#
# This file is kept ONLY because the pending WooCommerce catalog plan
# (plans/2026-06-26-woocommerce-catalog-build-extension/phase-06-seeding.md)
# still extends it; it must rebase its seeding onto the JSON batch engine before
# this shim is removed. New work uses the batch engine.
#
# (Legacy behavior, unchanged below) idempotent "create-if-missing" WP-CLI helpers
# for the seeding stages: every function checks existence before writing and
# records a stable key into the manifest's `seed.idempotencyKeys`, so re-runs are
# safe.
#
# Source this from a seed script:
#   source "${CLAUDE_PLUGIN_ROOT}/scripts/seed-helpers.sh"
#   home_id="$(ensure_page home "Home" ./content/home.html templates/front-page.php)"
#   ensure_menu "Primary"
#   ensure_menu_item_post "Primary" "$home_id" "Home"
#   set_front_page home
#
# Or invoke a single function directly:
#   bash "${CLAUDE_PLUGIN_ROOT}/scripts/seed-helpers.sh" ensure_option blogname "Acme"
#
# All WordPress CLI runs go through wp-env by default. Override with WP_CLI_RUN:
#   WP_CLI_RUN="wp"                       # talk to a local WP-CLI directly
#   WP_CLI_RUN="wp-env run cli wp"        # default (Docker WordPress)
#
# Requires: jq. Manifest helpers come from manifest-lib.sh (sourced below).
# NOTE: no top-level `set -euo pipefail` — this file is sourced, and enabling it
# would alter the caller's shell (and zsh leaves BASH_SOURCE unset). The executed
# dispatcher at the bottom turns strict mode on for direct `bash` invocation.

# Locate this script's dir portably: CLAUDE_PLUGIN_ROOT in the plugin runtime,
# else via the active shell (bash BASH_SOURCE / zsh %x), else $0.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh" ]; then
  _SEED_DIR="${CLAUDE_PLUGIN_ROOT}/scripts"
elif [ -n "${BASH_SOURCE:-}" ]; then
  _SEED_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elif [ -n "${ZSH_VERSION:-}" ]; then
  eval '_SEED_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"'
else
  _SEED_DIR="$(cd "$(dirname "$0")" && pwd)"
fi
# shellcheck source=/dev/null
source "${_SEED_DIR}/manifest-lib.sh"

# ---------------------------------------------------------------------------
# WP-CLI runner
# ---------------------------------------------------------------------------
# Build an argv array from WP_CLI_RUN so multi-word runners (e.g.
# "wp-env run cli wp") word-split correctly without eval.
# Build the runner argv in a shell-aware way (zsh needs ${=...} to word-split;
# the zsh-only syntax is hidden behind eval so bash never parses it).
if [ -n "${ZSH_VERSION:-}" ]; then
  eval '_WP_CLI_RUN_ARR=( ${=WP_CLI_RUN:-wp-env run cli wp} )'
else
  # shellcheck disable=SC2206
  read -r -a _WP_CLI_RUN_ARR <<< "${WP_CLI_RUN:-wp-env run cli wp}"
fi

# wp_cli <subcommand...> — run a WP-CLI command through the configured runner.
wp_cli() {
  "${_WP_CLI_RUN_ARR[@]}" "$@"
}

_seed_log() { printf 'seed-helpers: %s\n' "$*" >&2; }

# ---------------------------------------------------------------------------
# Idempotency-key bookkeeping (manifest seed.idempotencyKeys + seed.lastRun)
# ---------------------------------------------------------------------------

# _seed_record_key <key> — append a stable key (deduped) to seed.idempotencyKeys.
_seed_record_key() {
  local key="${1:?key}" tmp
  [[ -f "$WP_BUILD_FILE" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  tmp="$(mktemp)"
  jq --arg k "$key" '
    .seed = (.seed // {}) |
    .seed.idempotencyKeys = (((.seed.idempotencyKeys // []) + [$k]) | unique)
  ' "$WP_BUILD_FILE" > "$tmp" && mv "$tmp" "$WP_BUILD_FILE"
}

# seed_mark_run — stamp seed.lastRun with the current UTC time.
seed_mark_run() {
  local ts tmp
  [[ -f "$WP_BUILD_FILE" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  tmp="$(mktemp)"
  jq --arg ts "$ts" '.seed = (.seed // {}) | .seed.lastRun = $ts' \
    "$WP_BUILD_FILE" > "$tmp" && mv "$tmp" "$WP_BUILD_FILE"
}

# ---------------------------------------------------------------------------
# Lookup helpers (all return empty string + exit 0 when nothing is found, so
# they are safe to use under `set -o pipefail`).
# ---------------------------------------------------------------------------

# _seed_find_post_by_slug <slug> [post_type] — echo the first matching post ID.
_seed_find_post_by_slug() {
  local slug="${1:?slug}" ptype="${2:-page}"
  wp_cli post list --post_type="$ptype" --name="$slug" --post_status=any \
    --field=ID 2>/dev/null | tr -d '\r' | head -n1 || true
}

# _seed_find_attachment_by_title <title> — echo the first attachment ID whose
# title matches exactly (used to dedupe media by filename).
_seed_find_attachment_by_title() {
  local title="${1:?title}"
  wp_cli post list --post_type=attachment --post_status=any \
    --fields=ID,post_title --format=json 2>/dev/null | tr -d '\r' \
    | jq -r --arg t "$title" 'map(select(.post_title==$t)) | (.[0].ID // empty)' 2>/dev/null || true
}

# _seed_menu_exists <name> — return 0 when a menu with this name exists.
_seed_menu_exists() {
  local name="${1:?menu}"
  wp_cli menu list --field=name 2>/dev/null | tr -d '\r' | grep -qx "$name"
}

# _seed_menu_has_title <menu> <title> — return 0 when the menu already has an
# item with this title (stable dedupe key for menu items).
_seed_menu_has_title() {
  local menu="${1:?menu}" title="${2:?title}"
  wp_cli menu item list "$menu" --format=json 2>/dev/null | tr -d '\r' \
    | jq -e --arg t "$title" 'any(.[]?; .title == $t)' >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Create-if-missing primitives
# ---------------------------------------------------------------------------

# ensure_page <slug> <title> [content-file] [template] — create a page keyed by
# slug if none exists; print the page ID either way.
ensure_page() {
  ensure_post "${1:?slug}" "${2:?title}" "${3:-}" page "${4:-}"
}

# ensure_post <slug> <title> [content-file] [post_type] [template]
#   Creates a post/page keyed by slug if absent; prints the ID.
ensure_post() {
  local slug="${1:?slug}" title="${2:?title}" content_file="${3:-}"
  local ptype="${4:-post}" template="${5:-}" id content=""
  id="$(_seed_find_post_by_slug "$slug" "$ptype")"
  if [[ -n "$id" ]]; then
    _seed_log "$ptype '$slug' exists (ID $id)"
    printf '%s\n' "$id"
    return 0
  fi
  if [[ -n "$content_file" && -f "$content_file" ]]; then
    content="$(cat "$content_file")"
  fi
  id="$(wp_cli post create --post_type="$ptype" --post_title="$title" \
    --post_name="$slug" --post_status=publish --post_content="$content" \
    --porcelain | tr -d '\r')"
  if [[ -n "$template" ]]; then
    wp_cli post meta update "$id" _wp_page_template "$template" >/dev/null
  fi
  _seed_record_key "${ptype}:${slug}"
  _seed_log "created $ptype '$slug' (ID $id)"
  printf '%s\n' "$id"
}

# ensure_menu <name> — create a nav menu keyed by name if absent.
ensure_menu() {
  local name="${1:?menu name}"
  if _seed_menu_exists "$name"; then
    _seed_log "menu '$name' exists"
    return 0
  fi
  wp_cli menu create "$name" >/dev/null
  _seed_record_key "menu:${name}"
  _seed_log "created menu '$name'"
}

# ensure_menu_item_post <menu> <page-id> <title> — link a page/post into a menu,
# deduped by item title.
ensure_menu_item_post() {
  local menu="${1:?menu}" page_id="${2:?page id}" title="${3:?title}"
  if _seed_menu_has_title "$menu" "$title"; then
    _seed_log "menu '$menu' already has item '$title'"
    return 0
  fi
  wp_cli menu item add-post "$menu" "$page_id" --title="$title" >/dev/null
  _seed_record_key "menu-item:${menu}:${title}"
  _seed_log "added post $page_id ('$title') to menu '$menu'"
}

# ensure_menu_item_custom <menu> <title> <url> — add a custom-link menu item,
# deduped by item title.
ensure_menu_item_custom() {
  local menu="${1:?menu}" title="${2:?title}" url="${3:?url}"
  if _seed_menu_has_title "$menu" "$title"; then
    _seed_log "menu '$menu' already has item '$title'"
    return 0
  fi
  wp_cli menu item add-custom "$menu" "$title" "$url" >/dev/null
  _seed_record_key "menu-item:${menu}:${title}"
  _seed_log "added custom '$title' -> $url to menu '$menu'"
}

# assign_menu_location <menu> <location> — bind a menu to a theme location
# (idempotent: assign is a no-op if already bound there).
assign_menu_location() {
  local menu="${1:?menu}" location="${2:?location}"
  wp_cli menu location assign "$menu" "$location" >/dev/null 2>&1 || \
    _seed_log "could not assign '$menu' to location '$location' (theme may lack it)"
  _seed_record_key "menu-location:${location}"
}

# set_front_page <home-slug> [blog-slug] — switch reading settings to a static
# front page (and optional posts page) by slug.
set_front_page() {
  local home_slug="${1:?home slug}" blog_slug="${2:-}" home_id blog_id
  home_id="$(_seed_find_post_by_slug "$home_slug" page)"
  if [[ -z "$home_id" ]]; then
    _seed_log "set_front_page: home page '$home_slug' not found — create it first"
    return 1
  fi
  ensure_option show_on_front page
  ensure_option page_on_front "$home_id"
  if [[ -n "$blog_slug" ]]; then
    blog_id="$(_seed_find_post_by_slug "$blog_slug" page)"
    [[ -n "$blog_id" ]] && ensure_option page_for_posts "$blog_id"
  fi
  _seed_record_key "front-page:${home_slug}"
  _seed_log "front page set to '$home_slug' (ID $home_id)"
}

# ensure_option <name> <value> — update an option only when the value differs.
ensure_option() {
  local name="${1:?option}" value="${2?value}" current
  current="$(wp_cli option get "$name" 2>/dev/null | tr -d '\r' || true)"
  if [[ "$current" == "$value" ]]; then
    _seed_log "option '$name' already '$value'"
    return 0
  fi
  wp_cli option update "$name" "$value" >/dev/null
  _seed_record_key "option:${name}"
  _seed_log "set option '$name' = '$value'"
}

# ensure_term <taxonomy> <name> <slug> — create a term keyed by slug if absent.
ensure_term() {
  local tax="${1:?taxonomy}" name="${2:?name}" slug="${3:?slug}" existing
  existing="$(wp_cli term list "$tax" --slug="$slug" --field=term_id 2>/dev/null \
    | tr -d '\r' | head -n1 || true)"
  if [[ -n "$existing" ]]; then
    _seed_log "term '$slug' in '$tax' exists (ID $existing)"
    printf '%s\n' "$existing"
    return 0
  fi
  existing="$(wp_cli term create "$tax" "$name" --slug="$slug" --porcelain 2>/dev/null \
    | tr -d '\r' | head -n1 || true)"
  _seed_record_key "term:${tax}:${slug}"
  _seed_log "created term '$slug' in '$tax' (ID ${existing:-?})"
  printf '%s\n' "$existing"
}

# import_media <glob> — import files into the media library, deduped by filename
# (matched against existing attachment titles). Prints each attachment ID.
# Note: paths are passed to WP-CLI as-is. When using wp-env, files must be
# reachable inside the container; set WP_MEDIA_PATH_PREFIX to prepend a mapped
# container path if your assets live outside the default mount.
import_media() {
  local pattern="${1:?glob}" prefix="${WP_MEDIA_PATH_PREFIX:-}"
  local f base title existing id
  shopt -s nullglob
  for f in $pattern; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f")"
    title="${base%.*}"
    existing="$(_seed_find_attachment_by_title "$title")"
    if [[ -n "$existing" ]]; then
      _seed_log "media '$base' exists (ID $existing)"
      printf '%s\n' "$existing"
      continue
    fi
    id="$(wp_cli media import "${prefix}${f}" --title="$title" --porcelain 2>/dev/null \
      | tr -d '\r' | tail -n1 || true)"
    _seed_record_key "media:${title}"
    _seed_log "imported media '$base' (ID ${id:-?})"
    printf '%s\n' "$id"
  done
  shopt -u nullglob
}

# set_featured_image <post-id> <attachment-id> — attach a featured image.
set_featured_image() {
  local pid="${1:?post id}" att="${2:?attachment id}" current
  current="$(wp_cli post meta get "$pid" _thumbnail_id 2>/dev/null | tr -d '\r' || true)"
  if [[ "$current" == "$att" ]]; then
    _seed_log "post $pid already has featured image $att"
    return 0
  fi
  wp_cli post meta update "$pid" _thumbnail_id "$att" >/dev/null
  _seed_record_key "featured:${pid}"
  _seed_log "set featured image $att on post $pid"
}

# ensure_acf_value <post-id> <field> <value> — set a postmeta (ACF) value only
# when it differs from the current stored value.
ensure_acf_value() {
  local pid="${1:?post id}" field="${2:?field}" value="${3?value}" current
  current="$(wp_cli post meta get "$pid" "$field" 2>/dev/null | tr -d '\r' || true)"
  if [[ "$current" == "$value" ]]; then
    _seed_log "meta '$field' on post $pid already set"
    return 0
  fi
  wp_cli post meta update "$pid" "$field" "$value" >/dev/null
  _seed_record_key "meta:${pid}:${field}"
  _seed_log "set meta '$field' on post $pid"
}

# ---------------------------------------------------------------------------
# Direct invocation: `bash seed-helpers.sh <function> [args...]`
# ---------------------------------------------------------------------------
# Detect direct execution vs being sourced, in bash and zsh (top-level check —
# do NOT wrap in a function; zsh's eval-context loses the :file marker inside one).
_seed_sourced=1
if [ -n "${BASH_VERSION:-}" ]; then
  [ "${BASH_SOURCE[0]}" = "$0" ] && _seed_sourced=0
elif [ -n "${ZSH_VERSION:-}" ]; then
  case "${ZSH_EVAL_CONTEXT:-}" in *:file*) _seed_sourced=1 ;; *) _seed_sourced=0 ;; esac
fi

if [ "$_seed_sourced" = "0" ]; then
  set -euo pipefail
  _fn="${1:-}"
  if [ -z "$_fn" ]; then
    echo "usage: seed-helpers.sh <function> [args...]" >&2
    echo "functions: ensure_page ensure_post ensure_menu ensure_menu_item_post" >&2
    echo "           ensure_menu_item_custom assign_menu_location set_front_page" >&2
    echo "           ensure_option ensure_term import_media set_featured_image" >&2
    echo "           ensure_acf_value seed_mark_run" >&2
    exit 1
  fi
  shift
  "$_fn" "$@"
fi
