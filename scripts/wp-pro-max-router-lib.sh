#!/usr/bin/env bash
# WP Pro Max natural-language router helpers
# Usage: source this file in commands/wp-pro-max.md

set -euo pipefail

WPM_ROUTE_DIR="${WPM_ROUTE_DIR:-./.wp-pro-max}"
WPM_ROUTE_FILE="${WPM_ROUTE_FILE:-$WPM_ROUTE_DIR/route.json}"

wpm_route_ensure_dir() {
  mkdir -p "$WPM_ROUTE_DIR"
}

# Print concise help when no request is given
wpm_route_print_help() {
  cat <<'EOF'
WP Pro Max — natural-language router

Usage: /wp-pro-max "<what you want to do>"

Examples:
  /wp-pro-max "build a site from ./examples/sample-site"
  /wp-pro-max "check status"
  /wp-pro-max "audit accessibility"
  /wp-pro-max "run a best-practice audit"
  /wp-pro-max "fix audit findings"
  /wp-pro-max "convert to a block theme"
  /wp-pro-max "seed the team members"
  /wp-pro-max "ship to production"
  /wp-pro-max "fix the header template"

Available targets:
  Commands: build, status, env, init, plugin, a11y-audit, audit, fix, figma, component, site-editor
  Skills:   html-analysis, html-optimization, theme-conversion, plugin-selection,
            wp-scaffold, content-seeding, plugin-data-seeding, wp-i18n, wp-seo,
            wp-security, wp-qa, wp-audit, wp-fix, wp-ship, wp-handoff, wp-env-setup, section-redesign,
            content-enrichment, pre-conversion-qa
  Agents:   wp-theme-developer, wp-data-engineer, wp-deployer, wp-plugin-developer,
            a11y-checker, figma-analyzer
EOF
}

# Build the classifier input JSON from the raw request.
# Prints the input file path.
wpm_route_prepare_input() {
  local request="$1"
  wpm_route_ensure_dir
  local input_file
  input_file="$WPM_ROUTE_DIR/route-input.json"
  jq -n \
    --arg request "$request" \
    --arg pwd "$(pwd)" \
    --arg route_file "$WPM_ROUTE_FILE" \
    '{request: $request, pwd: $pwd, route_file: $route_file}' \
    > "$input_file"
  printf '%s\n' "$input_file"
}

# Validate that the route file exists and has the minimum shape.
# Prints the route file path on success.
wpm_route_validate() {
  local route_file="$1"
  if [ ! -f "$route_file" ]; then
    echo "wp-pro-max: classifier did not produce a route file" >&2
    exit 1
  fi
  if ! jq -e '.target_type' "$route_file" >/dev/null 2>&1; then
    echo "wp-pro-max: classifier returned an invalid route file" >&2
    exit 1
  fi
  printf '%s\n' "$route_file"
}
