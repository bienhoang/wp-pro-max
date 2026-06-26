#!/usr/bin/env bash
# vuln-scan.sh — aggregate WordPress core/plugin/theme version + update state and
# (optionally) cross-reference the WPScan vulnerability database.
#
# Usage:
#   bash vuln-scan.sh [--out sec/vuln-report.json]
# Env:
#   WP_CLI_RUN     override the wp invocation (default: "wp-env run cli wp")
#   WPSCAN_API_TOKEN  if set, look up known vulns per plugin/theme/core via WPScan
#
# Output (stdout + --out): JSON
#   { "core": {...}, "plugins": [...], "themes": [...], "findings": [ ... ] }
# Each finding: { component, slug, version, severity, source, title, fixedIn }
#
# No token? The scan still flags out-of-date components as severity "medium"
# (needs-review) so nothing passes silently.
set -euo pipefail

WP="${WP_CLI_RUN:-wp-env run cli wp}"
OUT=""
[[ "${1:-}" == "--out" ]] && OUT="${2:?path}"

command -v jq >/dev/null || { echo "vuln-scan: jq required" >&2; exit 1; }
mkdir -p sec

# --- Inventory --------------------------------------------------------------
core_ver="$($WP core version 2>/dev/null || echo "unknown")"
core_update="$($WP core check-update --format=json 2>/dev/null || echo '[]')"
plugins="$($WP plugin list --format=json --fields=name,status,version,update,update_version 2>/dev/null || echo '[]')"
themes="$($WP theme list --format=json --fields=name,status,version,update,update_version 2>/dev/null || echo '[]')"

# --- WPScan lookup (optional) ----------------------------------------------
# Returns a JSON array of findings for one component, or [] on miss/no token.
wpscan_lookup() {
  local kind="$1" slug="$2" version="$3"   # kind: plugins|themes|wordpresses
  [[ -n "${WPSCAN_API_TOKEN:-}" ]] || { echo '[]'; return 0; }
  command -v curl >/dev/null || { echo '[]'; return 0; }
  local ref="$slug"
  [[ "$kind" == "wordpresses" ]] && ref="${version//./}"
  local resp
  resp="$(curl -s --max-time 25 \
    -H "Authorization: Token token=${WPSCAN_API_TOKEN}" \
    "https://wpscan.com/api/v3/${kind}/${ref}" 2>/dev/null || echo '{}')"
  # WPScan returns { "<slug>": { vulnerabilities: [ { title, fixed_in, references{cve}} ] } }
  printf '%s' "$resp" | jq --arg slug "$slug" --arg ver "$version" '
    (.[$slug].vulnerabilities // []) | map({
      title: .title,
      fixedIn: (.fixed_in // null),
      cve: ((.references.cve // []) | join(",")),
      affectsCurrent: (if .fixed_in == null then true
                       else ($ver != "" and ($ver | split(".")) as $v
                             | (.fixed_in | split(".")) as $f | true) end)
    })' 2>/dev/null || echo '[]'
}

findings='[]'
add_finding() {  # component slug version severity source title fixedIn
  findings="$(jq -c \
    --arg c "$1" --arg s "$2" --arg v "$3" --arg sev "$4" --arg src "$5" --arg t "$6" --arg f "$7" \
    '. + [{component:$c, slug:$s, version:$v, severity:$sev, source:$src, title:$t, fixedIn:$f}]' \
    <<<"$findings")"
}

# Core: out of date?
if [[ "$(jq 'length' <<<"$core_update")" -gt 0 ]]; then
  add_finding core wordpress "$core_ver" medium check-update "WordPress core update available" \
    "$(jq -r '.[0].version // ""' <<<"$core_update")"
fi
for v in $(jq -r '.[]?.title // empty' <<<"$(wpscan_lookup wordpresses core "$core_ver")"); do
  add_finding core wordpress "$core_ver" high wpscan "$v" ""
done

# Plugins + themes loop
scan_components() {  # kind json
  local kind="$1" json="$2"
  local n; n="$(jq 'length' <<<"$json")"
  for ((i=0; i<n; i++)); do
    local name ver upd
    name="$(jq -r ".[$i].name" <<<"$json")"
    ver="$(jq -r ".[$i].version // \"\"" <<<"$json")"
    upd="$(jq -r ".[$i].update // \"none\"" <<<"$json")"
    [[ "$upd" == "available" ]] && add_finding "$kind" "$name" "$ver" medium check-update \
      "Update available for $name" "$(jq -r ".[$i].update_version // \"\"" <<<"$json")"
    local hits; hits="$(wpscan_lookup "${kind}s" "$name" "$ver")"
    local m; m="$(jq 'length' <<<"$hits")"
    for ((j=0; j<m; j++)); do
      add_finding "$kind" "$name" "$ver" high wpscan \
        "$(jq -r ".[$j].title" <<<"$hits")" "$(jq -r ".[$j].fixedIn // \"\"" <<<"$hits")"
    done
  done
}
scan_components plugin "$plugins"
scan_components theme "$themes"

report="$(jq -n \
  --arg cv "$core_ver" --argjson cu "$core_update" \
  --argjson pl "$plugins" --argjson th "$themes" --argjson fnd "$findings" \
  '{ core:{version:$cv, updateAvailable:($cu|length>0)},
     plugins:$pl, themes:$th, findings:$fnd,
     summary:{
       critical: ($fnd|map(select(.severity=="critical"))|length),
       high:     ($fnd|map(select(.severity=="high"))|length),
       medium:   ($fnd|map(select(.severity=="medium"))|length),
       low:      ($fnd|map(select(.severity=="low"))|length)
     },
     scanner: (if env.WPSCAN_API_TOKEN then "wpscan+check-update" else "check-update-only" end) }')"

if [[ -n "$OUT" ]]; then printf '%s\n' "$report" > "$OUT"; fi
printf '%s\n' "$report"
