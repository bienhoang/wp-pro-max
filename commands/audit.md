---
description: Run a best-practice audit on the current WP Pro Max target project. Checks a11y, security, performance, and code-style / WordPress conventions, then writes a report plus an audit entry into wp-build.json.
argument-hint: [--scope self|all] [--live|--static] [--format md|json|both] [--out <dir>]
allowed-tools: [Read, Bash, Skill]
---

# /wp-pro-max:audit

Run a best-practice audit on the current WP Pro Max target project. Static scans
always run; live scans run only when `wp-env` is reachable (unless you force
`--static` or `--live`).

## Flags

- `--scope self|all` — default `self`. `self` audits the active theme and any
  project-owned plugin; `all` includes third-party code as `external`.
- `--live` — require wp-env and run live performance/security/a11y probes.
- `--static` — skip live probes even if wp-env is running.
- `--format md|json|both` — default `both`.
- `--out <dir>` — directory for `audit-<timestamp>.json`; default `.`.

## Procedure

```bash
set -e
source "${CLAUDE_PLUGIN_ROOT}/scripts/wp-audit-lib.sh"

# Locate the manifest.
PROJECT_ROOT="$(pwd)"
if [ ! -f "${WP_BUILD_FILE:-./wp-build.json}" ] && [ -f "./wp/wp-build.json" ]; then
  cd ./wp || { echo "audit: cannot enter ./wp" >&2; exit 1; }
fi
[ -f "${WP_BUILD_FILE:-./wp-build.json}" ] || { echo "audit: no wp-build.json found. Run /wp-pro-max:init or /wp-pro-max:build first." >&2; exit 1; }

audit_parse_args $ARGUMENTS || exit 2

# Resolve output paths relative to the original project root.
REPORT_DIR="$AUDIT_OUT_DIR"
[ "${REPORT_DIR:0:1}" != "/" ] && REPORT_DIR="${PROJECT_ROOT}/${REPORT_DIR}"
DOCS_DIR="${PROJECT_ROOT}/docs"

# Build the argument string for the skill.
ARGS="--scope $AUDIT_SCOPE"
[ "$AUDIT_MODE" = "live" ] && ARGS="$ARGS --live"
[ "$AUDIT_MODE" = "static" ] && ARGS="$ARGS --static"
ARGS="$ARGS --format $AUDIT_FORMAT"
ARGS="$ARGS --out $REPORT_DIR"
ARGS="$ARGS --docs-dir $DOCS_DIR"

Skill(name="wp-pro-max:wp-audit", arguments="$ARGS")
```

## Output

A concise summary of total findings by severity, the `audit` object written to
`wp-build.json`, and paths to `audit-<timestamp>.json` plus
`docs/audit-<timestamp>.md`.
