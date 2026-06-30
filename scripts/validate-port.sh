#!/usr/bin/env bash
set -euo pipefail

# validate-port.sh — TDD harness for WP Kit extras port.
# Usage:
#   bash scripts/validate-port.sh [file1] [file2] ...
# If no arguments are supplied, validates the whole port set.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RESET='\033[0m'

ERRORS=0
WARNINGS=0

log_error() { printf "${RED}✗${RESET} %s\n" "$1"; ((ERRORS++)) || true; }
log_warn()  { printf "${YELLOW}!${RESET} %s\n" "$1"; ((WARNINGS++)) || true; }
log_ok()    { printf "${GREEN}✓${RESET} %s\n" "$1"; }

# Default set of files to validate when no arguments are given.
DEFAULT_FILES=(
  "skills/wp-performance-backend/SKILL.md"
  "skills/wp-a11y/SKILL.md"
  "agents/a11y-checker.md"
  "commands/a11y-audit.md"
  "skills/figma-bridge/SKILL.md"
  "skills/figma-bridge/references/figma-mcp-setup.md"
  "agents/figma-analyzer.md"
  "commands/figma.md"
  "commands/component.md"
)

FILES=("${@:-}")
if [[ ${#FILES[@]} -eq 0 || -z "${FILES[0]:-}" ]]; then
  FILES=("${DEFAULT_FILES[@]}")
fi

# Allowed tools for agents/commands in this project.
ALLOWED_TOOLS=(
  Read Write Edit Bash Glob Grep
  mcp__figma__get_design_context
  mcp__figma__get_screenshot
  mcp__figma__get_variable_defs
  mcp__figma__get_metadata
)

is_allowed_tool() {
  local tool="$1"
  for allowed in "${ALLOWED_TOOLS[@]}"; do
    [[ "$tool" == "$allowed" ]] && return 0
  done
  return 1
}

# Extract YAML frontmatter block into a temp-safe string.
extract_frontmatter() {
  local file="$1"
  awk 'BEGIN{found=0} /^---$/{found++; next} found==1{print} found==2{exit}' "$file"
}

# Check whether a frontmatter key exists and is non-empty.
has_key() {
  local fm="$1" key="$2"
  echo "$fm" | grep -Eq "^${key}:" || return 1
  local value
  value="$(echo "$fm" | awk -v k="$key" 'BEGIN{FS="[[:space:]]*:[[:space:]]*"} $1==k{print $2; exit}')"
  [[ -n "${value// }" ]]
}

# Resolve internal markdown links of the form [text](path).
resolve_internal_links() {
  local file="$1"
  local dir
  dir="$(dirname "$file")"
  local links
  links="$(grep -oE '\[([^\]]+)\]\(([^)]+)\)' "$file" | grep -oE '\([^)]+\)' | tr -d '()' | grep -vE '^(https?://|mailto:|#|www\.)' || true)"
  for link in $links; do
    # Strip fragment and query.
    link="${link%%#*}"
    link="${link%%\?*}"
    [[ -z "$link" ]] && continue
    local target
    if [[ "$link" == /* ]]; then
      target="${ROOT}${link}"
    else
      target="${dir}/${link}"
    fi
    if [[ ! -e "$target" ]]; then
      log_error "[$file] broken internal link: $link"
    fi
  done
}

validate_file() {
  local file="$1"
  local rel="${file#${ROOT}/}"
  local base
  base="$(basename "$file")"
  local type=""

  if [[ "$rel" == skills/*/references/* ]]; then type="reference"; fi
  if [[ "$rel" == skills/* && "$type" != "reference" ]]; then type="skill"; fi
  if [[ "$rel" == agents/* ]]; then type="agent"; fi
  if [[ "$rel" == commands/* ]]; then type="command"; fi

  if [[ ! -f "$file" ]]; then
    log_error "[$rel] file not found"
    return
  fi

  log_ok "[$rel] file exists"

  local fm
  fm="$(extract_frontmatter "$file" || true)"
  if [[ -z "$fm" ]]; then
    log_error "[$rel] missing or empty YAML frontmatter"
    return
  fi

  # Frontmatter key checks (reference files are informational and skip this).
  case "$type" in
    skill)
      for key in name description user-invocable; do
        has_key "$fm" "$key" || log_error "[$rel] missing frontmatter key: $key"
      done
      ;;
    agent|command)
      has_key "$fm" description || log_error "[$rel] missing frontmatter key: description"
      ;;
    reference)
      # No frontmatter required for reference documents.
      ;;
  esac

  # Agents must declare only allowed tools.
  if [[ "$type" == "agent" ]]; then
    local declared
    # Try inline array first: tools: [Read, Grep, Glob]
    if echo "$fm" | grep -qE '^tools:[[:space:]]*\['; then
      declared="$(echo "$fm" | awk -F':' '/^tools:/{gsub(/^[[:space:]]*tools:[[:space:]]*\[/,""); gsub(/\][[:space:]]*$/,""); gsub(/,/," "); print}')"
    else
      # Multi-line list.
      declared="$(echo "$fm" | awk '/^tools:/{flag=1; next} /^[a-zA-Z]/{if(flag && $0 !~ /^  - /){flag=0}} flag{print}' | sed 's/^  - //' | tr '\n' ' ' || true)"
    fi
    if [[ -z "${declared// }" ]]; then
      log_warn "[$rel] agent frontmatter has no tools list"
    else
      for tool in $declared; do
        is_allowed_tool "$tool" || log_error "[$rel] agent declares disallowed tool: $tool"
      done
    fi
  fi

  # Placeholder scan.
  if grep -Eq '\{\{[A-Z_][A-Z0-9_]*\}\}' "$file"; then
    log_error "[$rel] contains {{VAR}} placeholders"
    grep -nE '\{\{[A-Z_][A-Z0-9_]*\}\}' "$file" | while read -r line; do
      echo "    $line"
    done
  fi

  # Bedrock-only path warnings (optional mentions are OK, default paths are not).
  if grep -Eq '(^|[^/\w])web/(app|wp)(/|$)' "$file"; then
    log_warn "[$rel] contains Bedrock-only path (web/app/ or web/wp/)"
  fi

  # WP-CLI pattern check for the performance skill.
  if [[ "$rel" == "skills/wp-performance-backend/SKILL.md" ]]; then
    local in_block=0
    local line_no=0
    while IFS= read -r line; do
      ((line_no++)) || true
      case "$line" in
        '```'*)
          if (( in_block == 0 )); then
            in_block=1
          else
            in_block=0
          fi
          continue
          ;;
      esac
      if (( in_block == 1 )) && [[ "$line" =~ ^[[:space:]]*wp[[:space:]]+(db|profile|plugin|cron|doctor|eval|core) ]]; then
        # Canonical WP-CLI entry is wpx (kept in sync with test/contract-lint.sh):
        # a bare `wp <sub>` snippet must route through scripts/wpx.sh.
        if [[ ! "$line" =~ wpx\.sh ]]; then
          log_error "[$rel:$line_no] WP-CLI snippet should route through wpx (bash \${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh ...): $line"
        fi
      fi
    done < "$file"
  fi

  # WordPress 7.x mention in performance skill.
  if [[ "$rel" == "skills/wp-performance-backend/SKILL.md" ]]; then
    if ! grep -iq 'wordpress 7' "$file"; then
      log_error "[$rel] should mention WordPress 7.x"
    fi
  fi

  # Internal link resolution.
  resolve_internal_links "$file"
}

# --- Main loop ---
for rel in "${FILES[@]}"; do
  file="$rel"
  if [[ "$rel" != /* ]]; then
    file="${ROOT}/${rel}"
  fi
  validate_file "$file"
done

printf "\n"
if [[ $ERRORS -gt 0 ]]; then
  printf "${RED}Validation failed:${RESET} %d error(s), %d warning(s)\n" "$ERRORS" "$WARNINGS"
  exit 1
else
  printf "${GREEN}Validation passed${RESET} (%d warning(s))\n" "$WARNINGS"
  exit 0
fi
