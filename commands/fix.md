---
description: Fix WordPress issues found by /wp-pro-max:audit — triage each finding against the real source, propose a diff for approval, verify no regression. Propose-only; covers static PHP findings.
argument-hint: "[--severity critical|high|medium|low] [--category security|code-style] [--dry-run] [\"issue description\"]"
allowed-tools: [Read, Bash, Skill]
---

# /wp-pro-max:fix

Remediate what `/wp-pro-max:audit` found. Every change is **proposed as a diff and
applied only after you approve it** — there is no auto-apply mode.

## Flags

- `--severity critical|high|medium|low` — minimum severity, inclusive. `high`
  keeps critical + high.
- `--category security|code-style` — v1's two fixable categories. XSS, SQL
  injection, and CSRF live in `code-style`, not `security` — the audit's
  `category` field does not track risk.
- `--dry-run` — print the plan and every proposed diff; write nothing.
- `"<issue description>"` — a symptom to diagnose instead of a finding list, e.g.
  `/wp-pro-max:fix "trắng trang sau khi activate theme"`.

## What v1 covers

The nine static PHP rules from `scripts/audit-static.sh` — the only findings with
a real line number to anchor a diff to.

Reported but **not** fixed (each lands in `fix.unsupported[]` with a pointer):
accessibility findings (no line number, and most need authored content →
`/wp-pro-max:a11y-audit`), live performance and vulnerability findings (their
`file` is a URL or a plugin slug, not a path), and third-party code
(`external: true` — an edit is reverted by the next update).

## Procedure

```bash
set -e
source "${CLAUDE_PLUGIN_ROOT}/scripts/wp-fix-lib.sh"

# 1. Locate the manifest (mirrors commands/audit.md).
PROJECT_ROOT="$(pwd)"
if [ ! -f "${WP_BUILD_FILE:-./wp-build.json}" ] && [ -f "./wp/wp-build.json" ]; then
  cd ./wp || { echo "fix: cannot enter ./wp" >&2; exit 1; }
fi
[ -f "${WP_BUILD_FILE:-./wp-build.json}" ] || { echo "fix: no wp-build.json found. Run /wp-pro-max:init or /wp-pro-max:build first." >&2; exit 1; }

# 2. An audit must have run — fix remediates findings, it does not discover them.
if [ "$(jq -r '.audit.generatedAt // ""' "${WP_BUILD_FILE:-./wp-build.json}")" = "" ]; then
  echo "fix: no audit findings in wp-build.json. Run /wp-pro-max:audit --static first." >&2
  exit 1
fi

# 3. Hand the request to the skill VERBATIM, as one quoted string.
REQUEST="${ARGUMENTS:-}"
```

Then dispatch:

```
Skill(name="wp-pro-max:wp-fix", arguments="$REQUEST")
```

### Why `"${ARGUMENTS:-}"` and not `$ARGUMENTS`

`commands/audit.md:35` can afford unquoted `$ARGUMENTS` because
`wp-audit-lib.sh:52` rejects positional arguments outright — flags only, so
word-splitting is harmless. `fix` accepts a **multi-word free-text positional**,
which changes the calculus:

- Unquoted, `"trắng trang sau khi activate"` word-splits into `trắng`, `trang`, …
  and only the first word survives.
- Unquoted, a `$(…)` in user input is spliced into shell syntax and executed.

Quoting it (the `commands/wp-pro-max.md:30` pattern for free-text) makes it one
inert string: no word-splitting, and the value is never re-parsed as shell.

The skill then separates flags from free-text and calls
`fix_parse_args "$@"` with properly quoted positional parameters. **Never** run
`eval` on this string to recover shell-style quoting — that is the injection this
quoting exists to prevent.

## Output

A per-finding approval loop, then a summary: how many findings were addressed,
dismissed as false positives, left remaining, and unsupported — plus whether the
static re-scan **verified** the result. The `fix` object is written to
`wp-build.json`; every changed file is backed up under `fix.backupDir` first.
