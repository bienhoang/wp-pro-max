---
name: wp-audit
description: >-
  Run a best-practice audit on the current WP Pro Max target project. Scans
  self-authored theme/plugin code for a11y, security, performance, and code-style
  issues. Produces a Markdown + JSON report and writes an `audit` entry into
  `wp-build.json`. Static scans always run; live scans (Core Web Vitals,
  vulnerability check, axe-core a11y) run only when wp-env is available and
  degrade to static mode with a warning otherwise.
user-invocable: true
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# WP Audit (`wp-audit`)

Run a best-practice audit on the current WP Pro Max target project. The audit is
read-only by default: it never edits theme/plugin files, only reports findings.

## When to use

- The user asks for an audit, health check, or best-practice review.
- Before QA or ship to catch security, a11y, performance, or WPCS-style issues.
- After theme conversion or plugin development to validate output quality.

## Inputs

- `wp-build.json` in the current project (or `./wp/wp-build.json`).
- `theme.path` to locate the self-authored theme.
- Optional `wp-plugin.json` under the project root to locate self-authored plugins.

## Flags

- `--scope self|all` — default `self`. `self` scans the active theme and any
  project-owned plugin. `all` also includes third-party themes/plugins and marks
  them `external: true`.
- `--live` — fail fast if wp-env is not reachable.
- `--static` — never attempt live checks.
- `--format md|json|both` — default `both`.
- `--out <dir>` — directory for `audit-<timestamp>.json`; default `.`.

## Procedure

```bash
set -e
source "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh"
source "${CLAUDE_PLUGIN_ROOT}/scripts/wp-audit-lib.sh"

# 1. Locate the manifest.
PROJECT_ROOT="$(pwd)"
if [ ! -f "${WP_BUILD_FILE:-./wp-build.json}" ] && [ -f "./wp/wp-build.json" ]; then
  cd ./wp || { echo "wp-audit: cannot enter ./wp" >&2; exit 1; }
fi
[ -f "${WP_BUILD_FILE:-./wp-build.json}" ] || { echo "wp-audit: no wp-build.json found. Run /wp-pro-max:build or /wp-pro-max:init first." >&2; exit 1; }

audit_parse_args $ARGUMENTS || exit 2

THEME_PATH="$(wpbuild_get '.theme.path // ""')"
[ -n "$THEME_PATH" ] || { echo "wp-audit: theme.path missing from wp-build.json" >&2; exit 1; }

# Resolve output paths relative to the original project root.
REPORT_DIR="$AUDIT_OUT_DIR"
[ "${REPORT_DIR:0:1}" != "/" ] && REPORT_DIR="${PROJECT_ROOT}/${REPORT_DIR}"
DOCS_DIR="${AUDIT_DOCS_DIR:-${PROJECT_ROOT}/docs}"

mkdir -p "$AUDIT_WORK_DIR" "$REPORT_DIR" "$DOCS_DIR"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"

# 2. Detect wp-env and decide mode.
LIVE=false
if [ "$AUDIT_MODE" = "static" ]; then
  LIVE=false
elif [ "$AUDIT_MODE" = "live" ]; then
  if ! audit_wp_env_reachable; then
    echo "wp-audit: --live requested but wp-env is not reachable. Start it with /wp-pro-max:env start." >&2
    exit 1
  fi
  LIVE=true
else
  if audit_wp_env_reachable; then
    LIVE=true
    AUDIT_MODE="live"
  else
    echo "wp-audit: warning: wp-env not reachable; running in static mode only." >&2
    AUDIT_MODE="static"
  fi
fi

# 3. Static phase (always runs).
wpbuild_progress audit in-progress "static scan starting"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/audit-static.sh" . "$THEME_PATH" "$AUDIT_SCOPE" "$AUDIT_WORK_DIR"

# 4. Live phase (only when wp-env is available and not --static).
if [ "$LIVE" = true ]; then
  LOCAL_URL="$(wpbuild_get '.urls.local // .env.localUrl // "http://localhost:8888"')"
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/audit-live.sh" "$LOCAL_URL" "$AUDIT_SCOPE" "$AUDIT_WORK_DIR"
fi

# 5. Aggregate and write reports + wp-build.json entry.
AUDIT_OBJ="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/audit-aggregate.sh" \
  --work-dir "$AUDIT_WORK_DIR" \
  --report-dir "$REPORT_DIR" \
  --docs-dir "$DOCS_DIR" \
  --timestamp "$TIMESTAMP" \
  --mode "$AUDIT_MODE" \
  --scope "$AUDIT_SCOPE" \
  --format "$AUDIT_FORMAT")"

wpbuild_merge "$(jq -n --argjson audit "$AUDIT_OBJ" '{audit:$audit}')"
TOTAL="$(jq -r '.summary.total' <<<"$AUDIT_OBJ")"
PASSED="$(jq -r '.summary.passed' <<<"$AUDIT_OBJ")"
wpbuild_progress audit done "mode=$AUDIT_MODE scope=$AUDIT_SCOPE total=$TOTAL passed=$PASSED"

# 6. Print concise summary.
REPORT_FILE="${REPORT_DIR}/audit-${TIMESTAMP}.json"
MD_FILE="${DOCS_DIR}/audit-${TIMESTAMP}.md"
echo ""
echo "WP Pro Max Audit — $AUDIT_MODE mode, $AUDIT_SCOPE scope"
jq -r '"  total: \(.summary.total)  critical: \(.summary.critical)  high: \(.summary.high)  medium: \(.summary.medium)  low: \(.summary.low)  passed: \(.summary.passed)"' <<<"$AUDIT_OBJ"
echo "  report: $REPORT_FILE"
echo "  docs:   $MD_FILE"
if [ "$PASSED" != "true" ]; then
  echo ""
  echo "Top issues:"
  jq -r '.findings | sort_by(.severity | if . == "critical" then 0 elif . == "high" then 1 elif . == "medium" then 2 else 3 end) | .[0:5] | .[] | "  [" + .severity + "] " + .id + " — " + .message' <<<"$AUDIT_OBJ"
fi
```

## Output

- `wp-build.json` receives an `audit` object with `generatedAt`, `mode`, `scope`,
  `summary`, and `findings[]`.
- `audit-<timestamp>.json` is written to `--out` (default project root).
- `docs/audit-<timestamp>.md` is written for human review.

## Delegation

- Heavy fixes → **wp-theme-developer** or **wp-plugin-developer** agents with the
  report paths and acceptance criteria.
- Security remediation guidance → **wp-security** skill.
- Performance optimization → **wp-performance-backend** or **wp-qa** skills.
- A11y remediation → **accessibility** skill.
