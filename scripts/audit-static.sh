#!/usr/bin/env bash
# audit-static.sh — static code-style, a11y, and security scanner for wp-audit.
#
# Usage:
#   bash audit-static.sh <project-root> [theme-path] [scope] [outdir]
#
# Args:
#   project-root  directory containing wp-build.json (and usually wp-content/)
#   theme-path    optional self-authored theme directory (relative or absolute)
#   scope         self|all (default self)
#   outdir        directory for per-category JSON files (default ./audit)
#
# Output files:
#   <outdir>/code-style.json
#   <outdir>/a11y.json
#   <outdir>/security.json
#
# Each file has the shape:
#   { "findings": [ { id, category, severity, file, line, message, suggestion, external } ] }
set -euo pipefail

ROOT="${1:?usage: audit-static.sh <project-root> [theme-path] [scope] [outdir]}"
THEME="${2:-}"
SCOPE="${3:-self}"
OUTDIR="${4:-./audit}"

command -v jq >/dev/null || { echo "audit-static: jq required" >&2; exit 1; }
command -v grep >/dev/null || { echo "audit-static: grep required" >&2; exit 1; }

# Resolve CLAUDE_PLUGIN_ROOT for reusable scanners.
if [ -n "${BASH_VERSION:-}" ]; then
  _AUDIT_STATIC_DIR="$(dirname "${BASH_SOURCE[0]}")"
elif [ -n "${ZSH_VERSION:-}" ]; then
  _AUDIT_STATIC_DIR="$(dirname "${(%):-%x}")"
fi
CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "${_AUDIT_STATIC_DIR}/.." && pwd)}"
PRE_QA_A11Y="${CLAUDE_PLUGIN_ROOT}/scripts/pre-qa-a11y.mjs"
SECRETS_SCAN="${CLAUDE_PLUGIN_ROOT}/skills/wp-security/references/secrets-scan.sh"

mkdir -p "$OUTDIR"
ROOT="$(cd "$ROOT" && pwd)"

# Resolve theme path to an absolute path rooted in the project.
if [ -n "$THEME" ]; then
  if [ ! -d "$THEME" ] && [ -d "${ROOT}/${THEME}" ]; then
    THEME="${ROOT}/${THEME}"
  fi
  if [ "${THEME:0:1}" != "/" ]; then
    THEME="${ROOT}/${THEME}"
  fi
fi

# Directories considered "self-authored".
SELF_DIRS=()
[ -n "$THEME" ] && [ -d "$THEME" ] && SELF_DIRS+=("$THEME")
while IFS= read -r plugin_json; do
  [ -n "$plugin_json" ] && SELF_DIRS+=("$(dirname "$plugin_json")")
done < <(find "$ROOT" -maxdepth 4 -name 'wp-plugin.json' -print 2>/dev/null)

# JSON array of self-directory prefixes for jq checks.
SELF_PREFIXES_JSON='[]'
if [ ${#SELF_DIRS[@]} -gt 0 ]; then
for d in "${SELF_DIRS[@]}"; do
  SELF_PREFIXES_JSON="$(jq -c --arg p "$d" '. + [$p]' <<<"$SELF_PREFIXES_JSON")"
done
fi

is_self_file() {
  local f="$1"
  if [ ${#SELF_DIRS[@]} -eq 0 ]; then return 1; fi
  for d in "${SELF_DIRS[@]}"; do
    case "$f" in "${d}"/*) return 0 ;; esac
  done
  return 1
}

# Common file-exclusion prune expression (avoids vendor/build/binary noise).
PRUNE='-name node_modules -o -name vendor -o -name .git -o -name dist -o -name build -o -name .wp-env'

# -----------------------------------------------------------------------------
# 1. Static PHP scan (security + code-style / WPCS)
# -----------------------------------------------------------------------------
STATIC_JSON='{"findings":[]}'

add_static_finding() {
  local id="$1" category="$2" severity="$3" message="$4" suggestion="$5" file="$6" line="$7"
  local ext
  ext="$(if [ "$SCOPE" = "all" ] && ! is_self_file "$file"; then printf 'true'; else printf 'false'; fi)"
  STATIC_JSON="$(jq -c \
    --arg id "$id" --arg cat "$category" --arg sev "$severity" \
    --arg file "$file" --argjson line "${line:-0}" \
    --arg msg "$message" --arg sug "$suggestion" --argjson ext "$ext" \
    '.findings += [{id:$id, category:$cat, severity:$sev, file:$file, line:$line, message:$msg, suggestion:$sug, external:$ext}]' \
    <<<"$STATIC_JSON")"
}

# Parallel arrays (patterns may contain `|`).
IDS=(
  sec-eval
  sec-unsafe-include
  sec-unserialize
  sec-file-write-user-input
  sec-base64-decode
  wpcs-output-not-escaped
  wpcs-direct-db-no-prepare
  wpcs-missing-sanitize
)
SEVS=(
  critical critical high high medium high high high
)
CATS=(
  security security security security security code-style code-style code-style
)
PATTERNS=(
  '\beval\s*\('
  '(include|require)(_once)?\s*\(?\s*.*\$_'
  '\bunserialize\s*\('
  '\bfile_put_contents\s*\(.*\$_(GET|POST|REQUEST|COOKIE|SERVER)'
  '\bbase64_decode\s*\('
  '\becho\s+.*\$_(GET|POST|REQUEST|COOKIE)'
  '\$wpdb->(get_results|get_col|get_var|query)\s*\(.*\$'
  '\$_(GET|POST|REQUEST|COOKIE|SERVER)'
)
MSGS=(
  'eval() or equivalent dynamic execution found'
  '(include|require) depends on user input'
  'unserialize() on potentially untrusted data'
  'File write depends on user input'
  'base64_decode() present'
  'User input echoed without escaping'
  'SQL built with interpolated variables'
  'Superglobal used directly'
)
SUGS=(
  'Remove eval(); use safe parsing or whitelists.'
  'Never include files from $_GET/$_POST; use hardcoded allowlists.'
  'Use json_decode() or unserialize() with allowed_classes.'
  'Validate and restrict file paths.'
  'Avoid obfuscation; validate any decoded data.'
  'Use esc_html(), esc_attr(), or wp_kses_post().'
  'Use $wpdb->prepare() with placeholders.'
  'Sanitize with sanitize_*() or wp_unslash().'
)

PHP_FILES=()
if [ "$SCOPE" = "self" ]; then
  if [ ${#SELF_DIRS[@]} -gt 0 ]; then
    for d in "${SELF_DIRS[@]}"; do
      [ -d "$d" ] && while IFS= read -r f; do PHP_FILES+=("$f"); done < <(find "$d" -type f -name '*.php' 2>/dev/null)
    done
  fi
else
  while IFS= read -r f; do PHP_FILES+=("$f"); done < <(
    find "$ROOT" \
      \( $PRUNE \) -prune -o \
      -type f -name '*.php' \
      -path '*/wp-content/*' \
      -print 2>/dev/null
  )
fi

if [ ${#PHP_FILES[@]} -gt 0 ]; then
for f in "${PHP_FILES[@]}"; do
  for idx in "${!IDS[@]}"; do
    id="${IDS[$idx]}"
    category="${CATS[$idx]}"
    sev="${SEVS[$idx]}"
    pattern="${PATTERNS[$idx]}"
    msg="${MSGS[$idx]}"
    sug="${SUGS[$idx]}"
    while IFS= read -r hit; do
      [ -z "$hit" ] && continue
      file="${hit%%:*}"
      rest="${hit#*:}"
      line="${rest%%:*}"
      add_static_finding "$id" "$category" "$sev" "$msg" "$sug" "$file" "$line"
    done < <(grep -HnIE -- "$pattern" "$f" 2>/dev/null || true)
  done

  # AJAX nonce check: flag files that register wp_ajax_* actions without verifying nonces.
  if grep -qE $'add_action\\s*\\(\\s*[\x27"]wp_ajax_' "$f" 2>/dev/null; then
    if ! grep -qE '(check_ajax_referer|wp_verify_nonce)' "$f" 2>/dev/null; then
      line="$(grep -HnE $'add_action\\s*\\(\\s*[\x27"]wp_ajax_' "$f" | head -1 | cut -d: -f2)"
      add_static_finding "wpcs-missing-nonce" "code-style" "high" \
        "AJAX handler registered without nonce verification" \
        "Add check_ajax_referer() or wp_verify_nonce() to AJAX callbacks." \
        "$f" "$line"
    fi
  fi
done
fi

printf '%s\n' "$(jq '[.findings[] | select(.category == "code-style")] | {findings:.}' <<<"$STATIC_JSON")" > "$OUTDIR/code-style.json"
STATIC_SEC_JSON="$(jq '[.findings[] | select(.category == "security")] | {findings:.}' <<<"$STATIC_JSON")"

# -----------------------------------------------------------------------------
# 2. Static a11y scan (HTML + PHP templates)
# -----------------------------------------------------------------------------
A11Y_FILES=()
if [ "$SCOPE" = "self" ]; then
  if [ ${#SELF_DIRS[@]} -gt 0 ]; then
    for d in "${SELF_DIRS[@]}"; do
      [ -d "$d" ] && while IFS= read -r f; do A11Y_FILES+=("$f"); done < <(
        find "$d" -type f \( -name '*.html' -o -name '*.php' \) 2>/dev/null
      )
    done
  fi
else
  while IFS= read -r f; do A11Y_FILES+=("$f"); done < <(
    find "$ROOT" \
      \( $PRUNE \) -prune -o \
      -type f \( -name '*.html' -o -name '*.php' \) \
      -path '*/wp-content/*' \
      -print 2>/dev/null
  )
fi

# Skip template fragments that are not full HTML documents.
A11Y_FILTERED=()
if [ ${#A11Y_FILES[@]} -gt 0 ]; then
for f in "${A11Y_FILES[@]}"; do
  grep -qi '<html' "$f" 2>/dev/null && A11Y_FILTERED+=("$f")
done
fi
A11Y_FILES=()
if [ ${#A11Y_FILTERED[@]} -gt 0 ]; then
  for f in "${A11Y_FILTERED[@]}"; do A11Y_FILES+=("$f"); done
fi

A11Y_JSON='{"findings":[]}'
if [ ${#A11Y_FILES[@]} -gt 0 ] && [ -f "$PRE_QA_A11Y" ] && command -v node >/dev/null; then
  RAW_A11Y="$(node "$PRE_QA_A11Y" "${A11Y_FILES[@]}" 2>/dev/null)" || true
  if [ -n "$RAW_A11Y" ] && echo "$RAW_A11Y" | jq -e '.violations' >/dev/null 2>&1; then
    A11Y_JSON="$(jq \
      --argjson self "$SELF_PREFIXES_JSON" '
      (.violations // []) | map(
        . as $v |
        (if $v.severity == "error" then "high" else "medium" end) as $sev |
        {
          id: ("a11y-" + $v.rule),
          category: "a11y",
          severity: $sev,
          file: $v.file,
          line: 0,
          message: $v.message,
          suggestion: (
            $v.rule |
            if . == "imgAlt" then "Add descriptive alt or alt=\"\" if decorative."
            elif . == "headingOrder" then "Ensure headings increase by one level at a time."
            elif . == "singleH1" then "Provide exactly one page-level <h1>."
            elif . == "mainLandmark" then "Wrap primary content in <main>."
            elif . == "navLabel" then "Add aria-label or aria-labelledby to <nav>."
            elif . == "formLabel" then "Use <label for> or aria-label."
            elif . == "contrast" then "Verify color contrast ratio ≥ 4.5:1."
            elif . == "lang" then "Add lang=\"...\" to <html>."
            else "Review the accessibility guideline for this rule."
            end
          ),
          external: (if ($self | length) == 0 then false else ($v.file as $f | $self | map(. as $p | $f | startswith($p)) | any | not) end)
        }
      ) | {findings:.}
    ' <<<"$RAW_A11Y")"
  fi
fi
printf '%s\n' "$A11Y_JSON" > "$OUTDIR/a11y.json"

# -----------------------------------------------------------------------------
# 3. Security secrets scan
# -----------------------------------------------------------------------------
SECURITY_JSON='{"findings":[]}'
if [ -f "$SECRETS_SCAN" ]; then
  RAW_SEC="$(bash "$SECRETS_SCAN" "$ROOT" 2>/dev/null || echo '{}')"
  if [ -n "$RAW_SEC" ] && echo "$RAW_SEC" | jq -e '.findings' >/dev/null 2>&1; then
    SECURITY_JSON="$(jq \
      --arg scope "$SCOPE" \
      --argjson self "$SELF_PREFIXES_JSON" '
      (.findings // []) | map(
        {
          id: "sec-committed-secret",
          category: "security",
          severity: .severity,
          file: .file,
          line: .line,
          message: ("Possible committed secret: " + .rule),
          suggestion: "Rotate the secret and remove it from source control; use environment variables or a secret manager.",
          external: (if ($self | length) == 0 then false else (.file as $f | $self | map(. as $p | $f | startswith($p)) | any | not) end)
        }
      ) | if $scope == "self" then map(select(.external == false)) else . end | {findings:.}
    ' <<<"$RAW_SEC")"
  fi
fi
# Merge static security findings with secrets-scan findings.
if [ -n "${STATIC_SEC_JSON:-}" ]; then
  SECURITY_JSON="$(jq -s '.[0].findings + .[1].findings | {findings:.}' <(echo "$SECURITY_JSON") <(echo "$STATIC_SEC_JSON"))"
fi

printf '%s\n' "$SECURITY_JSON" > "$OUTDIR/security.json"

echo "audit-static: wrote $OUTDIR/{code-style,a11y,security}.json"
