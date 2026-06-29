#!/usr/bin/env bash
# Run a Google PageSpeed Insights v5 audit for a single public URL.
# Usage:
#   export PAGESPEED_API_KEY="your-key"
#   bash run-pagespeed.sh <url> [strategy] [locale]
#
# Offline test mode:
#   bash run-pagespeed.sh --sample <path-to-psi-json>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SAMPLE_JSON="${SCRIPT_DIR}/sample-psi-response.json"

PSI_API_URL="https://www.googleapis.com/pagespeedonline/v5/runPagespeed"

err() {
  echo "Error: $1" >&2
  exit "${2:-1}"
}

command -v jq >/dev/null 2>&1 || err "jq is required. Install it (e.g., brew install jq, apt install jq)." 1

usage() {
  cat >&2 <<EOF
Usage:
  export PAGESPEED_API_KEY="your-key"
  bash ${0##*/} <url> [strategy] [locale]

  strategy: mobile (default) or desktop
  locale:   en (default)

Offline test:
  bash ${0##*/} --sample <path-to-psi-json>
EOF
}

# Validate strategy: only mobile or desktop.
validate_strategy() {
  local strategy="$1"
  if [[ "$strategy" != "mobile" && "$strategy" != "desktop" ]]; then
    err "Invalid strategy '$strategy'. Use 'mobile' or 'desktop'." 1
  fi
}

# Validate URL scheme and reject credentials, shell metacharacters, and traversal.
validate_url() {
  local url="$1"

  if [[ -z "$url" ]]; then
    err "URL is required." 1
  fi

  if [[ "$url" != http://* && "$url" != https://* ]]; then
    err "URL must start with http:// or https://." 1
  fi

  # Reject embedded credentials (user:pass@host).
  if [[ "$url" =~ ^https?://[^@/]+@ ]]; then
    err "URL with embedded credentials is not allowed." 1
  fi

  # Reject dangerous shell metacharacters and path traversal.
  # ? and & are allowed because query strings are encoded before shell use.
  local metachar_re='[];|$`*<>()\[{}|\\]'
  if [[ "$url" =~ $metachar_re ]] || [[ "$url" == *..* ]]; then
    err "Invalid URL: contains shell metacharacters or path traversal." 1
  fi
}

# Build a filesystem-safe slug from the URL host + path.
url_to_slug() {
  local url="$1"
  local host_path
  # Strip scheme.
  host_path="${url#http://}"
  host_path="${host_path#https://}"
  # Strip query and fragment.
  host_path="${host_path%%\?*}"
  host_path="${host_path%%#*}"
  # Reduce to safe characters.
  printf '%s' "$host_path" | sed -E 's/[^a-zA-Z0-9_-]+/-/g; s/^-+|-+$//g; s/-+/-/g'
}

# Format a duration: seconds when >= 1000 ms, milliseconds otherwise.
format_duration() {
  local ms="$1"
  if [[ -z "$ms" || "$ms" == "null" || "$ms" == "n/a" ]]; then
    printf 'n/a'
    return
  fi
  if awk "BEGIN {exit !($ms >= 1000)}"; then
    awk -v m="$ms" 'BEGIN {printf "%.2f s", m / 1000}'
  else
    printf '%s ms' "$ms"
  fi
}

# Generate Markdown report from JSON file. Writes to $2.
generate_markdown() {
  local json_file="$1"
  local md_file="$2"
  local url strategy fetched_at

  url="$(jq -r '._wpProMaxMeta.url // .id // "unknown"' "$json_file")"
  strategy="$(jq -r '._wpProMaxMeta.strategy // "mobile"' "$json_file")"
  fetched_at="$(jq -r '._wpProMaxMeta.fetchedAt // "unknown"' "$json_file")"

  local score lcp cls fcp tbt si inp
  score="$(jq -r '.lighthouseResult.categories.performance.score // "n/a"' "$json_file")"
  lcp="$(jq -r '.lighthouseResult.audits["largest-contentful-paint"].numericValue // "n/a"' "$json_file")"
  cls="$(jq -r '.lighthouseResult.audits["cumulative-layout-shift"].numericValue // "n/a"' "$json_file")"
  fcp="$(jq -r '.lighthouseResult.audits["first-contentful-paint"].numericValue // "n/a"' "$json_file")"
  tbt="$(jq -r '.lighthouseResult.audits["total-blocking-time"].numericValue // "n/a"' "$json_file")"
  si="$(jq -r '.lighthouseResult.audits["speed-index"].numericValue // "n/a"' "$json_file")"

  if jq -e '.lighthouseResult.audits["interaction-to-next-paint"]' "$json_file" >/dev/null 2>&1; then
    inp="$(jq -r '.lighthouseResult.audits["interaction-to-next-paint"].numericValue // "n/a"' "$json_file")"
  else
    inp="n/a"
  fi

  local score_display
  if [[ "$score" != "n/a" && "$score" != "null" ]]; then
    score_display="$(awk -v s="$score" 'BEGIN {printf "%d", s * 100}')"
  else
    score_display="n/a"
  fi

  local summary
  if [[ "$score_display" != "n/a" ]]; then
    if (( score_display >= 90 )); then
      summary="Performance looks good. Prioritize the opportunities below to stay in the green."
    elif (( score_display >= 50 )); then
      summary="Performance needs attention. Address the top opportunities first."
    else
      summary="Performance is poor. Tackle the high-impact opportunities immediately."
    fi
  else
    summary="Could not determine an overall performance score."
  fi

  {
    echo "# PageSpeed Insights Report"
    echo ""
    echo "- **URL:** $url"
    echo "- **Strategy:** $strategy"
    echo "- **Fetched:** $fetched_at"
    echo ""
    echo "## Overall score"
    echo ""
    echo "**$score_display / 100**"
    echo ""
    echo "## Metrics"
    echo ""
    echo "| Metric | Value |"
    echo "|--------|-------|"
    echo "| LCP (Largest Contentful Paint) | $(format_duration "$lcp") |"
    echo "| CLS (Cumulative Layout Shift) | $cls |"
    echo "| FCP (First Contentful Paint) | $(format_duration "$fcp") |"
    echo "| TBT (Total Blocking Time) | $(format_duration "$tbt") |"
    echo "| SI (Speed Index) | $(format_duration "$si") |"
    echo "| INP (Interaction to Next Paint) | $(format_duration "$inp") |"
    echo ""
    echo "## Top opportunities"
    echo ""

    local opportunities
    opportunities="$(jq -r '
      .lighthouseResult.audits
      | to_entries[]
      | select(.value.details?.type == "opportunity" and .value.numericValue > 0)
      | {id: .key, title: .value.title, savingsMs: (.value.numericValue // 0)}
      | "\(.savingsMs)|\(.title)"
      ' "$json_file" 2>/dev/null | sort -t'|' -k1 -nr | head -n 5)"

    if [[ -n "$opportunities" ]]; then
      echo "| Estimated savings | Opportunity |"
      echo "|-------------------|-------------|"
      while IFS='|' read -r savings title; do
        printf "| %s | %s |\n" "$(format_duration "$savings")" "$title"
      done <<< "$opportunities"
    else
      echo "No opportunities detected."
    fi

    echo ""
    echo "## Summary"
    echo ""
    echo "$summary"
    echo ""
    echo "---"
    echo ""
    echo "Generated by WP Pro Max \`wp-pagespeed\` skill."
  } > "$md_file"
}

# Call the PSI API and return the raw JSON on stdout.
fetch_psi() {
  local url="$1"
  local strategy="$2"
  local locale="$3"
  local api_key="$4"

  local encoded_url encoded_key
  encoded_url="$(printf '%s' "$url" | jq -sRr @uri)"
  encoded_key="$(printf '%s' "$api_key" | jq -sRr @uri)"

  local attempt=1
  local max_attempts=2
  local curl_status=0
  local http_code
  local response
  local tmp_response
  tmp_response="$(mktemp)"
  trap 'rm -f "$tmp_response"' RETURN

  while (( attempt <= max_attempts )); do
    curl_status=0
    http_code="$(curl -fsSL --max-time 60 \
      -o "$tmp_response" \
      -w '%{http_code}' \
      "${PSI_API_URL}?url=${encoded_url}&strategy=${strategy}&locale=${locale}&key=${encoded_key}" \
      -H "Accept: application/json")" || curl_status=$?

    if (( curl_status == 0 )); then
      cat "$tmp_response"
      return 0
    fi

    # Retry once on rate-limit (429) or server errors (5xx).
    if (( attempt < max_attempts )) && [[ "$http_code" == "429" || "$http_code" == 5* ]]; then
      echo "Transient PSI error (HTTP ${http_code}), retrying in 2s..." >&2
      sleep 2
    else
      break
    fi

    (( attempt++ )) || true
  done

  return "$curl_status"
}

main() {
  local use_sample=false
  local sample_path=""

  if [[ "${1:-}" == "--sample" ]]; then
    use_sample=true
    sample_path="${2:-}"
    [[ -n "$sample_path" ]] || err "--sample requires a path to a PSI JSON file." 1
    [[ -f "$sample_path" ]] || err "Sample file not found: $sample_path" 1
    shift 2 || true
  fi

  local url="${1:-}"
  local strategy="${2:-mobile}"
  local locale="${3:-en}"

  if $use_sample; then
    url="$(jq -r '._wpProMaxMeta.url // .id // "sample"' "$sample_path")"
    strategy="${1:-$(jq -r '._wpProMaxMeta.strategy // "mobile"' "$sample_path")}"
    locale="${2:-$(jq -r '._wpProMaxMeta.locale // "en"' "$sample_path")}"
  else
    [[ -n "${PAGESPEED_API_KEY:-}" ]] || err "PAGESPEED_API_KEY is not set. Export it before running this script." 1
    validate_url "$url"
  fi

  validate_strategy "$strategy"

  local slug timestamp json_file md_file
  slug="$(url_to_slug "$url")"
  slug="${slug:-site}"
  timestamp="$(date +%Y%m%d-%H%M%S-%N)"
  json_file="${timestamp}-pagespeed-${slug}.json"
  md_file="${timestamp}-pagespeed-${slug}.md"

  if $use_sample; then
    cp "$sample_path" "$json_file"
    jq --arg strategy "$strategy" \
       --arg locale "$locale" \
       --arg fetchedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '._wpProMaxMeta.strategy = $strategy | ._wpProMaxMeta.locale = $locale | ._wpProMaxMeta.fetchedAt = $fetchedAt' \
       "$json_file" > "${json_file}.tmp" && mv "${json_file}.tmp" "$json_file"
  else
    local raw_json
    raw_json="$(fetch_psi "$url" "$strategy" "$locale" "$PAGESPEED_API_KEY")"
    {
      printf '%s' "$raw_json" | jq --arg url "$url" \
        --arg strategy "$strategy" \
        --arg fetchedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '. + {_wpProMaxMeta: {url: $url, strategy: $strategy, fetchedAt: $fetchedAt}}'
    } > "$json_file"
  fi

  generate_markdown "$json_file" "$md_file"

  echo "$json_file"
  echo "$md_file"
}

main "$@"
