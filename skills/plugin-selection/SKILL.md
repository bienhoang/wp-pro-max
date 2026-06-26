---
name: plugin-selection
description: >-
  Selects the minimal set of WordPress plugins for the build (stage `plugins`).
  Recommends plugins by detected need — SEO, forms, caching, security, page
  builder, custom fields, i18n, media — each with a rationale and category, then
  pins their slugs into .wp-env.json. Use when choosing or installing WordPress
  plugins, deciding between Yoast/SEOPress, CF7/WPForms, enabling Elementor or
  ACF. Reads requirements, analysis, and strategy; writes plugins[] and updates
  the .wp-env.json plugin list.
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# Plugin Selection (stage `plugins`)

Pick the smallest plugin set that satisfies real, detected needs (YAGNI). Each
selection records `slug`, `source`, `category`, `rationale`, and `required`.

## Inputs (from `wp-build.json`)

- `strategy` — `page-builder` ⇒ a builder is required; `classic-acf` ⇒ ACF required.
- `analysis.components[]` — a `form` component ⇒ a forms plugin; many images ⇒ media.
- `analysis.pages[]` roles — `post`/`archive` ⇒ SEO + sitemap matter more.
- `source.briefPath` / requirements — explicit asks (e-commerce, multilingual…).
- `i18n.enabled` / `i18n.locales` — multilingual ⇒ i18n plugin.

## Procedure

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh"
wpbuild_is_done plugins && [[ "${1:-}" != "--force" ]] && { echo "plugins done"; exit 0; }
wpbuild_progress plugins in-progress
STRATEGY="$(wpbuild_get '.strategy')"
BUILDER="$(wpbuild_get '.builder // "none"')"
```

1. Map each detected need → exactly one plugin (table below). Skip needs that
   are not present. Prefer free wordpress.org plugins (`source: wporg`) unless a
   premium builder (Bricks) is chosen.
2. Build the `plugins[]` JSON array and write it.
3. Update `.wp-env.json` `plugins` with the wordpress.org slugs (premium ZIPs go
   in as local/remote paths, not bare slugs).
4. Record progress.

## Selection table (need → plugin)

| Need | Default slug | Alternative | Category | When to include |
|------|--------------|-------------|----------|-----------------|
| SEO + sitemap + schema | `wordpress-seo` (Yoast) | `seo-by-rank-math`, `wp-seopress` | `seo` | Almost always (sites need meta + sitemap). Prefer reusing installed `claude-seo` for audits; this plugin handles on-page output. |
| Forms | `contact-form-7` | `wpforms-lite` | `forms` | When `analysis.components[]` has a `form`. |
| Caching / performance | `w3-total-cache` | `wp-super-cache` | `cache` | For production-bound sites; skip if host provides caching. |
| Security hardening | `wordfence` | `limit-login-attempts-reloaded` | `security` | Public sites. Use the lighter `limit-login-attempts-reloaded` when Wordfence is too heavy for the host. |
| Page builder | `elementor` | `bricks` (premium ZIP) | `builder` | **Required** when `strategy=page-builder`; match `builder`. |
| Custom fields | `advanced-custom-fields` | — | `other` | **Required** when `strategy=classic-acf`. |
| Multilingual | `polylang` | `wpml` (premium) | `i18n` | When `i18n.enabled=true` / multiple `locales`. |
| Media / thumbnails | `regenerate-thumbnails` | — | `media` | When the theme adds custom image sizes or many images detected. |

Keep the set minimal: do not add caching/security to a throwaway local demo;
do not add a forms plugin if no form exists. `required: true` only for plugins
the strategy cannot function without (builder, ACF).

## Example output

For `strategy=classic-acf` with a contact form and SEO need:

```bash
wpbuild_set '.plugins' '[
  { "slug": "advanced-custom-fields", "source": "wporg", "category": "other",  "required": true,  "rationale": "classic-acf strategy stores custom fields via ACF; theme loads acf-json/." },
  { "slug": "wordpress-seo",          "source": "wporg", "category": "seo",    "required": false, "rationale": "On-page meta, titles, XML sitemap, schema." },
  { "slug": "contact-form-7",         "source": "wporg", "category": "forms",  "required": false, "rationale": "Form component detected in analysis." },
  { "slug": "limit-login-attempts-reloaded", "source": "wporg", "category": "security", "required": false, "rationale": "Lightweight brute-force protection." }
]'
```

For `strategy=page-builder` + `builder=elementor`: include
`{ "slug": "elementor", "category": "builder", "required": true, ... }` instead of ACF.

## Mapping slugs → `.wp-env.json`

`.wp-env.json` accepts wordpress.org slugs directly in its `plugins` array
(wp-env resolves and installs them). Merge selected wporg slugs in; the
`wp-env-setup` stage / `wp-env-bootstrap.sh` regenerates `.wp-env.json` from the
manifest, so writing `plugins[]` is sufficient — but if `.wp-env.json` already
exists, update it in place:

```bash
WPENV=".wp-env.json"
if [[ -f "$WPENV" ]]; then
  SLUGS="$(wpbuild_get '[.plugins[] | select(.source=="wporg") | .slug]')"
  tmp="$(mktemp)"
  jq --argjson s "$SLUGS" '.plugins = $s' "$WPENV" > "$tmp" && mv "$tmp" "$WPENV"
fi
wpbuild_progress plugins done "selected $(wpbuild_get '.plugins | length') plugins"
```

Premium plugins (e.g. Bricks) are NOT bare slugs — add their ZIP path/URL to
`.wp-env.json` `plugins` and set `source: "zip"` / `"premium"` in the manifest.

## Verify

`wp-env run cli wp plugin list --status=active` (after env start) should show the
required plugins active.
