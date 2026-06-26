---
name: wp-security
description: >-
  Hardens a WordPress build and scans it for vulnerabilities (stage `security`).
  Applies a hardening checklist via WP-CLI / wp-config (disable file editing,
  force SSL admin, security headers, limit login attempts, regenerate strong
  salts, file-permission guidance, hide version, disable XML-RPC if unused,
  least-privilege users) and runs a vulnerability scan of core/plugins/themes
  (wp core/plugin/theme check-update plus WPScan/Patchstack known-vuln lookup)
  and a secrets scan of the theme. Reports findings by severity. Use when
  hardening WordPress, applying security headers, scanning for vulnerable
  plugins/themes or leaked secrets, or when the pipeline reaches the `security`
  stage. Reuses the repo security-scan skill where available. Reads plugins,
  theme, project; writes security.{hardeningApplied,vulnScan}.
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# WP Security (stage `security`)

Two jobs: (1) **harden** the install with a concrete, idempotent checklist, and
(2) **scan** core/plugins/themes/secrets and report findings by severity. Apply
real configuration — do not just describe it. Destructive or environment-specific
items (file permissions on the host) are emitted as guidance, not run blindly.

## Inputs (from `wp-build.json`)

| Field | Use |
|-------|-----|
| `plugins[]` | Slugs/versions to vuln-check; is a security plugin present? |
| `theme.path` | Theme dir to scan for secrets + bad permissions. |
| `urls.production` | Whether SSL admin / HSTS should be forced (https target). |
| `project.themeSlug` | Locate the theme under `wp-content/themes/`. |

## 0. Resume guard + setup

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh"
wpbuild_is_done security && [[ "${1:-}" != "--force" ]] && { echo "security done"; exit 0; }
wpbuild_progress security in-progress
THEME_PATH="$(wpbuild_get '.theme.path // ""')"
PROD="$(wpbuild_get '.urls.production // ""')"
```

## 1. Hardening checklist (apply via WP-CLI / wp-config)

Apply each item; record the applied ids in `security.hardeningApplied[]`. Full
commands + rationale in `references/hardening-checklist.md`.

| id | Action | How |
|----|--------|-----|
| `disable-file-edit` | Block theme/plugin editor | `wp config set DISALLOW_FILE_EDIT true --raw` |
| `force-ssl-admin` | HTTPS admin/login | `wp config set FORCE_SSL_ADMIN true --raw` (only if prod is https) |
| `strong-salts` | Rotate auth keys/salts | `wp config shuffle-salts` (WP-CLI 2.x) |
| `disable-xmlrpc` | Turn off XML-RPC if unused | mu-plugin filter `xmlrpc_enabled` → `__return_false` |
| `hide-version` | Remove generator/version | remove `wp_generator`, strip `ver` query (mu-plugin) |
| `limit-login` | Brute-force protection | ensure `limit-login-attempts-reloaded` (or Wordfence) active |
| `security-headers` | HSTS, X-Frame, X-Content-Type, Referrer, CSP | mu-plugin `send_headers` (template provided) |
| `least-privilege` | No stray admins; editors get editor role | audit `wp user list --role=administrator` |
| `block-php-uploads` | Deny PHP execution in uploads | `.htaccess` / nginx guidance (host-specific) |
| `file-permissions` | 644 files / 755 dirs / locked wp-config | guidance + check command |

```bash
wp-env run cli wp config set DISALLOW_FILE_EDIT true --raw
[[ "$PROD" == https://* ]] && wp-env run cli wp config set FORCE_SSL_ADMIN true --raw
wp-env run cli wp config shuffle-salts || echo "shuffle-salts unavailable; rotate salts manually"
```

Emit the security mu-plugin (headers, xmlrpc, version hiding) into the target
project from `references/security-mu-plugin.php` and mount it (wp-env mappings or
`wp-content/mu-plugins/`). Re-running must be safe (config set is idempotent;
mu-plugin overwrite is fine).

## 2. Vulnerability scan (core / plugins / themes)

```bash
wp-env run cli wp core check-update --format=json   > sec/core-update.json
wp-env run cli wp plugin list --format=json         > sec/plugins.json
wp-env run cli wp theme list --format=json          > sec/themes.json
```

Cross-reference installed slugs+versions against known-vuln sources. Prefer the
repo's existing scanner and the WPScan/Patchstack databases:

- **WPScan API** (`https://wpscan.com/api/v3/`) — needs `WPSCAN_API_TOKEN`.
- **Patchstack** advisories — manual/API lookup by slug+version.
- If neither token is available, flag out-of-date components from
  `check-update` and `wp plugin list --field=update` as **needs-review** rather
  than passing silently.

Helper: `bash references/vuln-scan.sh` aggregates the three JSON files +
optional WPScan lookups into `sec/vuln-report.json`. Details:
`references/vuln-scan-sources.md`.

## 3. Secrets scan of the theme

Scan the generated theme (and any emitted scripts) for committed secrets — API
keys, tokens, DB creds, private keys accidentally carried over from the source
HTML/build:

```bash
# Reuse the repo security-scan skill when present (preferred):
#   invoke skill: security-scan  (scope: $THEME_PATH)
# Fallback regex sweep:
bash "${CLAUDE_PLUGIN_ROOT}/skills/wp-security/references/secrets-scan.sh" "$THEME_PATH" > sec/secrets.json
```

Any hit is at least **high** severity. Never print the secret value in the
report — record file + line + rule id only.

## 4. Report by severity → `security.vulnScan`

Aggregate everything into one report keyed by severity
(`critical|high|medium|low|info`):

```bash
wpbuild_set '.security.hardeningApplied' "$(cat sec/hardening-applied.json)"
wpbuild_set '.security.vulnScan' "$(jq -s '{
  generatedAt: now|todate,
  components: .[0], secrets: .[1],
  summary: { critical: 0, high: 0, medium: 0, low: 0 }
}' sec/vuln-report.json sec/secrets.json)"
wpbuild_progress security done "hardening applied; vuln+secrets scanned"
```

Print a human summary: counts per severity, the worst findings first, and
concrete remediation (update plugin X to ≥ version Y; rotate leaked key;
remove admin user Z). Critical/high findings should block ship — surface them to
the orchestrator (this stage reports; ship enforces alongside `qa.passed`).

## Threat model note

Before flagging, consider what this build actually exposes: a local wp-env demo
has a different risk surface than a public production site. Apply prod-grade
hardening when `urls.production` is set; for a throwaway local build, record
which items were deferred rather than forcing host-specific changes.

## Delegation

- Secrets/dependency scanning → repo **security-scan** skill (preferred).
- wp-config / mu-plugin / .htaccess edits beyond WP-CLI → **wp-theme-developer**
  or **wp-deployer** (host config) with the checklist ids, target paths, and
  acceptance criteria (DISALLOW_FILE_EDIT true; headers present; zero critical
  vulns; no secrets in theme).

See: `references/hardening-checklist.md`, `references/security-mu-plugin.php`,
`references/vuln-scan.sh`, `references/vuln-scan-sources.md`,
`references/secrets-scan.sh`.
