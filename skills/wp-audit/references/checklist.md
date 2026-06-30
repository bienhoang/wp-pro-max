---
title: "WP Pro Max Audit Checklist"
description: "Rule definitions for /wp-pro-max:audit across a11y, security, performance, and code-style / WordPress conventions."
---

# WP Pro Max Audit Checklist

Each rule has an `id`, `category`, `severity`, `scope` (`self|all`), `detection`
method, and a `messageTemplate` used in reports. Findings from live scanners are
normalized to this shape by `scripts/audit-aggregate.sh`.

## a11y

| id | severity | scope | detection | messageTemplate | suggestion |
|---|---|---|---|---|---|
| `a11y-missing-alt` | high | self/all | static (`pre-qa-a11y.mjs`) | Informative `<img>` is missing alt text. | Add descriptive `alt` or `alt=""` if decorative. |
| `a11y-heading-order` | high | self/all | static | Heading levels skip a level. | Ensure headings increase by one level at a time. |
| `a11y-single-h1` | high | self/all | static | Page should have exactly one `<h1>`. | Provide a single page-level `<h1>`. |
| `a11y-main-landmark` | high | self/all | static | Page should have exactly one `<main>` landmark. | Wrap primary content in `<main>`. |
| `a11y-nav-label` | medium | self/all | static | `<nav>` landmark is missing an accessible label. | Add `aria-label` or `aria-labelledby`. |
| `a11y-form-label` | high | self/all | static | Form control is missing an associated label. | Use `<label for>` or `aria-label`. |
| `a11y-contrast` | medium | self/all | static | Inline color contrast may be insufficient. | Verify contrast ratio ≥ 4.5:1 (3:1 for large text). |
| `a11y-html-lang` | medium | self/all | static | `<html>` element is missing a `lang` attribute. | Add `lang="..."` to `<html>`. |
| `a11y-axe-violation` | varies | self/all | live (`a11y-axe.mjs`) | axe-core detected a WCAG violation. | Follow the axe helpUrl and remediation guidance. |

## security

| id | severity | scope | detection | messageTemplate | suggestion |
|---|---|---|---|---|---|
| `sec-eval` | critical | self/all | static regex | `eval()` or equivalent dynamic code execution found. | Remove `eval()`; use safe parsing or whitelists. |
| `sec-unsafe-include` | critical | self/all | static regex | `include`/`require` depends on user input. | Never include files from `$_GET`/`$_POST`; use hardcoded allowlists. |
| `sec-unserialize` | high | self/all | static regex | `unserialize()` on potentially untrusted data. | Use `json_decode()` or `unserialize()` with `allowed_classes`. |
| `sec-file-write-user-input` | high | self/all | static regex | File write depends on user input. | Validate and restrict file paths. |
| `sec-base64-decode` | medium | self/all | static regex | `base64_decode()` present; review for obfuscation. | Avoid obfuscation; validate any decoded data. |
| `sec-committed-secret` | high/medium | self/all | static (`secrets-scan.sh`) | Possible committed secret/token. | Rotate the secret and remove it from source control. |
| `sec-live-*` | varies | all | live (`vuln-scan.sh`) | Vulnerability or available update from live scan. | Update to the fixed version or replace the component. |
| `sec-core-update` | medium | all | live (`vuln-scan.sh`) | WordPress core update available. | Apply the core update. |
| `sec-plugin-update` | medium | all | live (`vuln-scan.sh`) | Plugin update available. | Update or remove the plugin. |
| `sec-theme-update` | medium | all | live (`vuln-scan.sh`) | Theme update available. | Update or remove the theme. |
| `sec-wpscan-vuln` | high | all | live (`vuln-scan.sh` + WPScan) | Known vulnerability reported by WPScan. | Update to the fixed version or replace the component. |

## performance

| id | severity | scope | detection | messageTemplate | suggestion |
|---|---|---|---|---|---|
| `perf-lcp-high` | high | self/all | live (`core-web-vitals.mjs`) | Largest Contentful Paint exceeds target. | Optimize hero image, preload critical assets, reduce render-blocking CSS/JS. |
| `perf-cls-high` | high | self/all | live (`core-web-vitals.mjs`) | Cumulative Layout Shift exceeds target. | Reserve space for images/iframes, avoid inserting content above existing content. |
| `perf-inp-high` | medium | self/all | live (`core-web-vitals.mjs`) | Interaction to Next Paint proxy exceeds target. | Break up long JavaScript tasks, defer non-critical scripts. |
| `perf-ttfb-high` | medium | self/all | live (curl TTFB) | Time to First Byte exceeds target. | Profile backend (`wp-performance-backend`), cache, reduce early work. |

## code-style / WordPress conventions

| id | severity | scope | detection | messageTemplate | suggestion |
|---|---|---|---|---|---|
| `wpcs-missing-sanitize` | high | self/all | static regex | Superglobal passed to a WordPress function without sanitization. | Use `sanitize_*()` and `wp_unslash()` before use. |
| `wpcs-missing-nonce` | high | self/all | static regex (ajax handlers) | AJAX handler missing nonce verification. | Add `check_ajax_referer()` or `wp_verify_nonce()`. |
| `wpcs-direct-db-no-prepare` | high | self/all | static regex | `$wpdb` query uses string concatenation. | Use `$wpdb->prepare()` or parameterized queries. |
| `wpcs-output-not-escaped` | high | self/all | static regex | Output not escaped before echo/print. | Use `esc_html()`, `esc_attr()`, `esc_url()`, etc. |

## Severity meaning

- **critical** — Exploitable security flaw or broken access control; blocks release.
- **high** — Security risk, accessibility blocker, or WPCS hard error; must fix.
- **medium** — Should fix; may gate release depending on policy.
- **low** / **info** — Polish, documentation, or optional improvements.

## Tool inventory

| Category | Primary | Fallback |
|---|---|---|
| a11y static | `scripts/pre-qa-a11y.mjs` (Cheerio) | Manual checklist walk |
| a11y live | `skills/wp-qa/references/a11y-axe.mjs` (Playwright + axe-core) | Manual checklist |
| security static | `skills/wp-security/references/secrets-scan.sh` + regex | Manual review |
| security live | `skills/wp-security/references/vuln-scan.sh` | WP-CLI `plugin list` / `theme list` |
| performance live | `skills/wp-qa/references/core-web-vitals.mjs` + curl TTFB | `wp doctor` if available |
| code-style | PHPCS/WPCS inside wp-env when available | Static regex patterns above |
