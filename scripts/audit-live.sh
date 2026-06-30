#!/usr/bin/env bash
# audit-live.sh — run live performance/security/a11y probes and normalize findings.
#
# Usage:
#   bash audit-live.sh <local-url> <scope> <work-dir>
#
# Reads existing <work-dir>/{security,a11y}.json and appends live findings.
# Writes <work-dir>/performance.json.
set -euo pipefail

LOCAL_URL="${1:?usage: audit-live.sh <local-url> <scope> <work-dir>}"
SCOPE="${2:-self}"
WORK="${3:-./audit}"

command -v jq >/dev/null || { echo "audit-live: jq required" >&2; exit 1; }

if [ -n "${BASH_VERSION:-}" ]; then
  _AUDIT_LIVE_DIR="$(dirname "${BASH_SOURCE[0]}")"
elif [ -n "${ZSH_VERSION:-}" ]; then
  _AUDIT_LIVE_DIR="$(dirname "${(%):-%x}")"
fi
CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "${_AUDIT_LIVE_DIR}/.." && pwd)}"
CWV="${CLAUDE_PLUGIN_ROOT}/skills/wp-qa/references/core-web-vitals.mjs"
AXE="${CLAUDE_PLUGIN_ROOT}/skills/wp-qa/references/a11y-axe.mjs"
VULN_SCAN="${CLAUDE_PLUGIN_ROOT}/skills/wp-security/references/vuln-scan.sh"

mkdir -p "$WORK"

# -----------------------------------------------------------------------------
# 1. Performance (CWV + TTFB)
# -----------------------------------------------------------------------------
PERF_FINDINGS='[]'

CWV_FILE="${WORK}/cwv.json"
if command -v node >/dev/null && [ -f "$CWV" ]; then
  node "$CWV" "$LOCAL_URL" > "$CWV_FILE" 2>/dev/null || true
  if [ -s "$CWV_FILE" ] && jq -e --arg url "$LOCAL_URL" '.[$url]' "$CWV_FILE" >/dev/null 2>&1; then
    PERF_FINDINGS="$(jq --arg url "$LOCAL_URL" '
      .[$url] as $r |
      if $r == null then [] else
        [
          (if $r.lcp > $r.targets.lcp then [{
            id: "perf-lcp-high",
            category: "performance",
            severity: "high",
            file: $url, line: 0,
            message: "LCP \($r.lcp)ms exceeds target \($r.targets.lcp)ms",
            suggestion: "Optimize hero image, preload critical assets, reduce render-blocking CSS/JS.",
            external: false
          }] else [] end),
        (if $r.cls > $r.targets.cls then [{
          id: "perf-cls-high",
          category: "performance",
          severity: "high",
          file: $url, line: 0,
          message: "CLS \($r.cls) exceeds target \($r.targets.cls)",
          suggestion: "Reserve space for images/iframes, avoid inserting content above existing content.",
          external: false
        }] else [] end),
          (if $r.inp > $r.targets.inp then [{
            id: "perf-inp-high",
            category: "performance",
            severity: "medium",
            file: $url, line: 0,
            message: "INP proxy \($r.inp)ms exceeds target \($r.targets.inp)ms",
            suggestion: "Break up long JavaScript tasks, defer non-critical scripts.",
            external: false
          }] else [] end)
        ] | flatten
      end
    ' "$CWV_FILE")"
  fi
fi

if command -v curl >/dev/null; then
  TTFB_S="$(curl -o /dev/null -s -w '%{time_starttransfer}' "$LOCAL_URL" 2>/dev/null || echo '0')"
  TTFB_MS="$(awk "BEGIN { printf \"%.0f\", ($TTFB_S)*1000 }")"
  if [ "$TTFB_MS" -gt 600 ] 2>/dev/null; then
    PERF_FINDINGS="$(jq -c --arg url "$LOCAL_URL" --argjson ms "$TTFB_MS" '. + [{
      id: "perf-ttfb-high",
      category: "performance",
      severity: "medium",
      file: $url, line: 0,
      message: "TTFB \($ms)ms exceeds 600ms",
      suggestion: "Profile backend (wp-performance-backend), cache, reduce early work.",
      external: false
    }]' <<<"$PERF_FINDINGS")"
  fi
fi

printf '%s\n' "{\"findings\":$PERF_FINDINGS}" > "${WORK}/performance.json"

# -----------------------------------------------------------------------------
# 2. Security vulnerability scan
# -----------------------------------------------------------------------------
VULN_FILE="${WORK}/vuln.json"
if [ -f "$VULN_SCAN" ]; then
  bash "$VULN_SCAN" --out "$VULN_FILE" >/dev/null 2>&1 || true
fi
if [ -f "$VULN_FILE" ]; then
  SEC_LIVE="$(jq '
    (.findings // []) | map({
      id: ("sec-live-" + .component + "-" + .slug),
      category: "security",
      severity: .severity,
      file: (.component + "/" + .slug),
      line: 0,
      message: .title,
      suggestion: ("Update to " + (.fixedIn // "the latest version")),
      external: false
    }) | {findings:.}
  ' "$VULN_FILE")"
  if [ -f "${WORK}/security.json" ]; then
    jq --argjson live "$SEC_LIVE" '{findings: (.findings + $live.findings)}' "${WORK}/security.json" > "${WORK}/security.json.tmp"
    mv "${WORK}/security.json.tmp" "${WORK}/security.json"
  else
    printf '%s\n' "$SEC_LIVE" > "${WORK}/security.json"
  fi
fi

# -----------------------------------------------------------------------------
# 3. Live a11y (axe-core via Playwright)
# -----------------------------------------------------------------------------
AXE_FILE="${WORK}/axe.json"
AXE_LOG="${WORK}/axe.log"
if command -v node >/dev/null && [ -f "$AXE" ]; then
  # a11y-axe.mjs exits 0 (passed) or 1 (violations found) but writes the report
  # in both cases; only a real error (exit 2/3) leaves no file. Gate the merge on
  # the written report, not the exit code, and warn when the live probe failed so
  # static-only a11y findings are not silently presented as DOM-verified.
  rm -f "$AXE_FILE"
  node "$AXE" "$LOCAL_URL" --out "$AXE_FILE" >"$AXE_LOG" 2>&1 || true
  if [ -s "$AXE_FILE" ] && jq -e . "$AXE_FILE" >/dev/null 2>&1; then
    A11Y_LIVE="$(jq '
    (.violations // []) | map({
      id: ("a11y-axe-" + .id),
      category: "a11y",
      severity: (.impact | if . == "critical" then "critical"
                          elif . == "serious" then "high"
                          elif . == "moderate" then "medium"
                          else "low" end),
      file: .url,
      line: 0,
      message: .help,
      suggestion: ("See " + (.helpUrl // "axe-core documentation") + " for remediation."),
      external: false
    }) | {findings:.}
  ' "$AXE_FILE")"
    if [ -f "${WORK}/a11y.json" ]; then
      jq --argjson live "$A11Y_LIVE" '{findings: (.findings + $live.findings)}' "${WORK}/a11y.json" > "${WORK}/a11y.json.tmp"
      mv "${WORK}/a11y.json.tmp" "${WORK}/a11y.json"
    else
      printf '%s\n' "$A11Y_LIVE" > "${WORK}/a11y.json"
    fi
  else
    echo "audit-live: warning: live a11y (axe-core) probe produced no report; a11y findings are static-only, not DOM-verified. See ${AXE_LOG}" >&2
  fi
fi

echo "audit-live: wrote ${WORK}/performance.json and merged live security/a11y findings"
