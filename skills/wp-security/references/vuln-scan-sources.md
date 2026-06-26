# Vulnerability Scan Sources & Severity Mapping

How `vuln-scan.sh` and the stage decide what is vulnerable and how severe it is.

## Sources (in priority order)

1. **WP-CLI update state** (always available, no token):
   - `wp core check-update` — core behind latest.
   - `wp plugin list --field=update` / `wp theme list --field=update` — components
     with an available update. An outdated component is `medium` (needs-review):
     it may carry a patched CVE.

2. **WPScan API** (`https://wpscan.com/api/v3/`, needs `WPSCAN_API_TOKEN`):
   - Endpoints: `/plugins/<slug>`, `/themes/<slug>`, `/wordpresses/<version-no-dots>`.
   - Returns `vulnerabilities[]` with `title`, `fixed_in`, `references.cve`.
   - A match where the installed version `< fixed_in` (or `fixed_in == null`) is
     `high` (or `critical` if the CVE is RCE/auth-bypass — bump manually).
   - Free tier: 25 requests/day. Cache results; scan only active components.

3. **Patchstack** (`https://patchstack.com/database/`): manual or API lookup by
   slug + version. Use when WPScan misses a component or for premium plugins
   (Bricks, etc.). Record the advisory URL in the finding.

4. **Repo `security-scan` skill**: prefer it for the secrets sweep and for any
   dependency/OWASP coverage it already implements — do not duplicate.

## Severity rubric

| Severity | Criteria |
|----------|----------|
| `critical` | Unauthenticated RCE, auth bypass, SQLi on an **active** component; leaked private key / live cloud credential. |
| `high` | Known CVE affecting the installed version (WPScan/Patchstack match); leaked API token/password in theme. |
| `medium` | Out-of-date component with no confirmed exploit yet; weak config; JWT/DSN in source. |
| `low` | Informational version disclosure, missing non-critical header. |
| `info` | Hardening suggestions already applied; defense-in-depth notes. |

## Gating

Critical/high findings should **block ship** (surfaced to the orchestrator
alongside `qa.passed`). Medium → fix-before-prod recommendation. Always provide
the remediation: target version to update to (`fixedIn`), the user to downgrade,
or the secret to rotate + remove from history.

## Token setup

```bash
export WPSCAN_API_TOKEN="<token>"   # free account at wpscan.com/api
WPSCAN_API_TOKEN="$WPSCAN_API_TOKEN" bash references/vuln-scan.sh --out sec/vuln-report.json
```

No token → the scan runs in `check-update-only` mode (recorded in
`scanner` field) and flags out-of-date components as `medium` so nothing passes
unreviewed.
