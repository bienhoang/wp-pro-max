#!/usr/bin/env bash
# audit-aggregate.sh — aggregate per-category audit findings into reports.
#
# Usage:
#   bash audit-aggregate.sh \
#     [--work-dir <dir>] [--report-dir <dir>] [--docs-dir <dir>] \
#     [--timestamp <ts>] [--mode static|live] [--scope self|all]
#
# Reads:
#   <work-dir>/{code-style,a11y,security,performance}.json
#   Each file: { "findings": [ { id, category, severity, file, line, message, suggestion, external } ] }
#
# Writes:
#   <report-dir>/audit-<timestamp>.json
#   <docs-dir>/audit-<timestamp>.md
#
# stdout: the audit object (generatedAt, mode, scope, summary, findings) ready
#         to be merged into wp-build.json.
set -euo pipefail

command -v jq >/dev/null || { echo "audit-aggregate: jq required" >&2; exit 1; }

WORK_DIR="./audit"
REPORT_DIR="."
DOCS_DIR="./docs"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
MODE="static"
SCOPE="self"
FORMAT="both"

while [ $# -gt 0 ]; do
  case "$1" in
    --work-dir)    WORK_DIR="$2"; shift 2 ;;
    --report-dir)  REPORT_DIR="$2"; shift 2 ;;
    --docs-dir)    DOCS_DIR="$2"; shift 2 ;;
    --timestamp)   TIMESTAMP="$2"; shift 2 ;;
    --mode)        MODE="$2"; shift 2 ;;
    --scope)       SCOPE="$2"; shift 2 ;;
    --format)      FORMAT="$2"; shift 2 ;;
    *) echo "audit-aggregate: unknown option $1" >&2; exit 2 ;;
  esac
done

mkdir -p "$REPORT_DIR" "$DOCS_DIR"

ISO_TS="${TIMESTAMP:0:4}-${TIMESTAMP:4:2}-${TIMESTAMP:6:2}T${TIMESTAMP:9:2}:${TIMESTAMP:11:2}:${TIMESTAMP:13:2}Z"

read_findings() {
  local f="$1"
  if [ -f "$f" ]; then
    jq -c '.findings // []' "$f"
  else
    echo '[]'
  fi
}

CODE_STYLE="$(read_findings "${WORK_DIR}/code-style.json")"
A11Y="$(read_findings "${WORK_DIR}/a11y.json")"
SECURITY="$(read_findings "${WORK_DIR}/security.json")"
PERFORMANCE="$(read_findings "${WORK_DIR}/performance.json")"

AUDIT_JSON="$(jq -n \
  --arg iso "$ISO_TS" --arg mode "$MODE" --arg scope "$SCOPE" \
  --argjson code "$CODE_STYLE" --argjson a11y "$A11Y" \
  --argjson sec "$SECURITY" --argjson perf "$PERFORMANCE" '
  {
    generatedAt: $iso,
    mode: $mode,
    scope: $scope,
    findings: (
      ($code + $a11y + $sec + $perf) |
      if $scope == "self" then map(select(.external != true)) else . end
    )
  } |
  .summary = {
    total: (.findings | length),
    critical: (.findings | map(select(.severity == "critical")) | length),
    high:     (.findings | map(select(.severity == "high")) | length),
    medium:   (.findings | map(select(.severity == "medium")) | length),
    low:      (.findings | map(select(.severity == "low")) | length),
    passed:   ((.findings | map(select(.severity == "critical" or .severity == "high")) | length) == 0)
  }
')"

REPORT_FILE="${REPORT_DIR}/audit-${TIMESTAMP}.json"
MD_FILE="${DOCS_DIR}/audit-${TIMESTAMP}.md"

if [ "$FORMAT" = "json" ] || [ "$FORMAT" = "both" ]; then
  printf '%s\n' "$AUDIT_JSON" > "$REPORT_FILE"
fi

if [ "$FORMAT" = "md" ] || [ "$FORMAT" = "both" ]; then
# Build Markdown report.
jq -r \
  --arg iso "$ISO_TS" --arg mode "$MODE" --arg scope "$SCOPE" \
  --arg report "$REPORT_FILE" --arg md "$MD_FILE" '
  ("a11y security performance code-style" / " ") as $cats |
  def severity_rank:
    if . == "critical" then 0
    elif . == "high" then 1
    elif . == "medium" then 2
    elif . == "low" then 3
    else 4 end;
  def fmt_item:
    "- [" + .severity + "] `" + .id + "` " + .message +
    (if .file then " — `" + .file + "`" else "" end) +
    (if .line and .line != 0 then ":" + (.line | tostring) else "" end) +
    (if .external then " *(external)*" else "" end) +
    (if .suggestion then "\n  - *Suggestion:* " + .suggestion else "" end);
  def section($cat):
    "### " + $cat + "\n\n" +
    (
      [ .findings[] | select(.category == $cat) ] |
      sort_by([ (.severity | severity_rank), .file ]) |
      if length == 0 then "_No findings._"
      else map(fmt_item) | join("\n")
      end
    );
  "# WP Pro Max Audit Report\n\n" +
  "- **Generated:** " + $iso + "\n" +
  "- **Mode:** " + $mode + "\n" +
  "- **Scope:** " + $scope + "\n" +
  "- **Reports:** `" + $report + "`, `" + $md + "`\n\n" +
  "## Summary\n\n" +
  "| Metric | Count |\n|---|---|\n" +
  "| total | " + (.summary.total | tostring) + " |\n" +
  "| critical | " + (.summary.critical | tostring) + " |\n" +
  "| high | " + (.summary.high | tostring) + " |\n" +
  "| medium | " + (.summary.medium | tostring) + " |\n" +
  "| low | " + (.summary.low | tostring) + " |\n" +
  "| passed | " + (if .summary.passed then "✅ yes" else "❌ no" end) + " |\n\n" +
  "## Findings by category\n\n" +
  (if (.findings | length) == 0 then "No findings.\n" else "" end) +
  (. as $audit | $cats | map(. as $cat | $audit | section($cat)) | join("\n\n"))
' <<<"$AUDIT_JSON" > "$MD_FILE"

# Emit the audit object (for wp-build.json) on stdout.
  echo "audit-aggregate: wrote $MD_FILE" >&2
fi

# Always emit the audit object (for wp-build.json) on stdout.
printf '%s\n' "$AUDIT_JSON"

if [ "$FORMAT" = "json" ] || [ "$FORMAT" = "both" ]; then
  echo "audit-aggregate: wrote $REPORT_FILE" >&2
fi
