#!/usr/bin/env bash
# secrets-scan.sh — regex sweep of a theme/source directory for committed secrets.
# A lightweight fallback for when the repo `security-scan` skill is unavailable.
#
# Usage:  bash secrets-scan.sh <dir>
# Output (stdout): JSON  { "findings": [ { rule, file, line, severity } ], "summary": {...} }
#
# Never prints the matched secret value — only file + line + rule id, so the
# report itself does not leak credentials. Skips vendor/build/binary noise.
set -euo pipefail

DIR="${1:?usage: secrets-scan.sh <dir>}"
command -v grep >/dev/null || { echo "secrets-scan: grep required" >&2; exit 1; }
command -v jq   >/dev/null || { echo "secrets-scan: jq required"   >&2; exit 1; }

[[ -d "$DIR" ]] || { jq -n '{findings:[],summary:{high:0,medium:0},note:"dir not found"}'; exit 0; }

# rule id | severity | extended-regex
RULES=$'aws-access-key|high|AKIA[0-9A-Z]{16}
aws-secret-key|high|(?i)aws.{0,20}[\'"][0-9a-zA-Z/+]{40}[\'"]
private-key-block|high|-----BEGIN (RSA|EC|OPENSSH|DSA|PGP) PRIVATE KEY-----
google-api-key|high|AIza[0-9A-Za-z_\\-]{35}
slack-token|high|xox[baprs]-[0-9A-Za-z-]{10,}
stripe-secret|high|sk_(live|test)_[0-9a-zA-Z]{16,}
github-token|high|gh[pousr]_[0-9A-Za-z]{36,}
jwt|medium|eyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}
generic-password|medium|(?i)(password|passwd|pwd|secret|api[_-]?key|token)\\s*[:=]\\s*[\'"][^\'" ]{6,}[\'"]
db-dsn|medium|(mysql|postgres|postgresql)://[^\\s\'"]+:[^\\s\'"]+@'

# Directories/extensions to skip (vendored, build artifacts, binaries).
PRUNE='-name node_modules -o -name vendor -o -name .git -o -name dist -o -name build'

findings='[]'
high=0; medium=0

while IFS='|' read -r rule sev pattern; do
  [[ -z "$rule" ]] && continue
  # -P (PCRE) for (?i) and lookarounds; fall back to -E if grep lacks -P.
  GFLAG="-rPInH"
  grep -qP '' <<<"" 2>/dev/null || GFLAG="-rEInH"
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    file="${hit%%:*}"; rest="${hit#*:}"; line="${rest%%:*}"
    findings="$(jq -c --arg r "$rule" --arg f "$file" --arg l "$line" --arg s "$sev" \
      '. + [{rule:$r, file:$f, line:($l|tonumber? // 0), severity:$s}]' <<<"$findings")"
    [[ "$sev" == "high" ]] && high=$((high+1)) || medium=$((medium+1))
  done < <(find "$DIR" \( $PRUNE \) -prune -o -type f \
              ! -name '*.png' ! -name '*.jpg' ! -name '*.jpeg' ! -name '*.gif' \
              ! -name '*.webp' ! -name '*.woff*' ! -name '*.ttf' ! -name '*.ico' \
              -print0 2>/dev/null \
            | xargs -0 grep $GFLAG -- "$pattern" 2>/dev/null || true)
done <<< "$RULES"

jq -n --argjson f "$findings" --argjson h "$high" --argjson m "$medium" \
  '{findings:$f, summary:{high:$h, medium:$m}}'
