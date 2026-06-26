#!/usr/bin/env bash
# crawl-links.sh — breadth-first crawl of internal links from a base URL,
# reporting the HTTP status of every discovered same-host link.
#
# Usage:  bash crawl-links.sh <base-url> [max-pages]
# Output (stdout): JSON array  [ { "url": "...", "status": 200, "internal": true }, ... ]
#
# Requires: curl, jq, grep, sed. No headless browser — this finds <a href> in the
# served HTML, which is enough to catch internal 404s after seeding/conversion.
# JS-injected links are out of scope (use the Playwright a11y crawl for those).
set -euo pipefail

BASE="${1:?usage: crawl-links.sh <base-url> [max-pages]}"
MAX="${2:-100}"
BASE="${BASE%/}"
HOST="$(printf '%s' "$BASE" | sed -E 's#^https?://([^/]+).*#\1#')"

command -v curl >/dev/null || { echo "crawl-links: curl required" >&2; exit 1; }
command -v jq   >/dev/null || { echo "crawl-links: jq required"   >&2; exit 1; }

# Visited + queue tracked as newline-delimited temp files (portable, no assoc arrays).
seen="$(mktemp)"; queue="$(mktemp)"; results="$(mktemp)"
trap 'rm -f "$seen" "$queue" "$results"' EXIT
printf '%s\n' "$BASE/" > "$queue"

# Normalize an href (relative or absolute) against BASE into an absolute URL,
# or print nothing if it is off-host / non-http (mailto:, tel:, #anchor, etc.).
normalize() {
  local href="$1"
  case "$href" in
    ""|"#"*|"mailto:"*|"tel:"*|"javascript:"*) return 0 ;;
    http://*|https://*)
      printf '%s' "$href" | grep -qE "^https?://${HOST}([/:?#]|$)" && printf '%s' "${href%%#*}" ;;
    //*) : ;;                                   # protocol-relative off-host → skip
    /*)  printf '%s' "${BASE}${href%%#*}" ;;    # root-relative
    *)   printf '%s' "${BASE}/${href%%#*}" ;;   # path-relative (approx)
  esac
}

count=0
while [[ -s "$queue" && "$count" -lt "$MAX" ]]; do
  url="$(head -n1 "$queue")"; sed -i.bak '1d' "$queue" 2>/dev/null || sed -i '' '1d' "$queue"
  rm -f "${queue}.bak" 2>/dev/null || true
  grep -qxF "$url" "$seen" && continue
  printf '%s\n' "$url" >> "$seen"
  count=$((count+1))

  # Status of this URL.
  status="$(curl -s -o /dev/null -w '%{http_code}' -L --max-time 20 "$url" || echo 000)"
  jq -n --arg u "$url" --argjson s "${status:-0}" \
    '{url:$u, status:$s, internal:true}' >> "$results"

  # Only parse HTML bodies of OK internal pages for more links.
  [[ "$status" =~ ^2 ]] || continue
  body="$(curl -s -L --max-time 20 "$url" || true)"
  printf '%s' "$body" \
    | grep -oiE 'href="[^"]*"' \
    | sed -E 's/href="([^"]*)"/\1/I' \
    | while read -r href; do
        abs="$(normalize "$href")"
        [[ -n "$abs" ]] || continue
        grep -qxF "$abs" "$seen" || printf '%s\n' "$abs" >> "$queue"
      done
done

jq -s '.' "$results"
