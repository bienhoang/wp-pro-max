---
name: wp-handoff
description: >-
  Produces the client handoff package for a finished WordPress site (stage
  `handoff`). Reads the whole wp-build.json and generates, into the target
  project's docs/: a client-facing site handbook (how to edit content, manage
  menus, add posts, use the chosen plugins/builder), a credentials handoff
  template (pointers only — never real secrets), an update + backup strategy, a
  monitoring/uptime checklist, and a maintenance runbook with a rollback pointer
  to wp-ship. Use when wrapping up a WordPress build, handing a site to a client
  or team, or documenting maintenance and operations for a WordPress project.
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# WordPress Handoff (stage `handoff`)

Turn the build manifest into a maintenance-ready package the client or ops team
can run with. Everything is generated FROM `wp-build.json`, so it reflects what
was actually built.

## Inputs (from `wp-build.json`)

Reads broadly: `project`, `strategy`/`builder`, `analysis.pages`,
`contentModel` (CPTs, taxonomies, menus), `plugins`, `i18n`, `theme`, `seo`,
`security`, `env`, `urls`, `deploy`.

## Outputs

Written into the **target project's** `docs/` (not the plugin repo):

- `docs/site-handbook.md` — client-facing editing guide.
- `docs/credentials-handoff.md` — where secrets live (template; no real values).
- `docs/maintenance-runbook.md` — operations + rollback (see reference).
- `docs/update-backup-strategy.md` — cadence + procedures.
- `docs/monitoring-checklist.md` — uptime/health checks.
- `docs/a11y-known-issues.md` — outstanding accessibility issues from
  `skills/accessibility/references/known-issues-template.md` (optional; include
  if `qa.a11y` has open moderate/minor items).

Then `wpbuild_progress handoff done`.

## 0. Resume guard + summary

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh"
wpbuild_is_done handoff && [[ "${1:-}" != "--force" ]] && { echo "handoff done"; exit 0; }
wpbuild_progress handoff in-progress
mkdir -p docs
NAME="$(wpbuild_get '.project.name')"
STRATEGY="$(wpbuild_get '.strategy')"
```

Build a "what was built" summary from the manifest to open the handbook:
pages (`analysis.pages[].title`), CPTs (`contentModel.postTypes[].slug`),
plugins (`plugins[].slug` + category), locales (`i18n.locales`), deploy target
(`deploy.target`/`deploy.host`).

## 1. Site handbook (client-facing)

Plain-language, task-oriented. Tailor to `strategy`:

- **Editing pages/posts**: where content lives, how to publish/update. For
  `classic-acf`: which ACF fields drive which sections. For `block-fse`: editing
  in the Site Editor + patterns. For `page-builder`: editing in Elementor/Bricks.
- **Menus**: how to add/reorder items (Appearance → Menus), the registered
  locations from `contentModel.menus`.
- **Media**: uploading + the registered image sizes.
- **Custom content**: each CPT/taxonomy from `contentModel`, in client terms.
- **Plugins**: a short "what each plugin does + where to manage it" list from
  `plugins[]` (SEO, forms, cache, security, i18n…).
- **Languages** (if `i18n.enabled`): how to switch + add translations (Polylang/WPML).
- **Branding & Colors** (logos + colors + reset) — branch by `strategy`:
  - `classic-acf` → **Appearance → Customize → Branding & Colors**: upload the
    header logo and the separate footer logo (Logos), edit every brand color
    (Colors), and use **Reset** to return to the original design. Changes preview
    live and save to the front-end.
  - `block-fse` → colors in **Site Editor → Styles** (and **Styles → Reset to
    defaults** to revert). The separate **footer logo** lives in the Customizer,
    whose menu WordPress hides for block themes — reach it directly at
    **`/wp-admin/customize.php`** → Site Identity → Footer Logo.
  - `page-builder` → colors in **Elementor → Site Settings → Global Colors**;
    header logo in **Site Identity**; the footer logo via the host-theme
    Customizer control (or the Elementor footer logo widget if the footer is
    builder-managed — whichever the build used).

## 2. Credentials handoff (template — NO secrets)

Generate a TEMPLATE listing WHERE each credential lives, never the values:
WordPress admin URL + who holds the admin account, hosting/SSH access, DB
location, plugin license keys (e.g. ACF PRO/WPML), SMTP, CDN/DNS, and any API
keys. Explicitly instruct: store real secrets in a password manager; never commit
them. Add a checklist for rotating credentials at handoff.

## 3. Update & backup strategy

→ `docs/update-backup-strategy.md`: core/plugin/theme update cadence (test on
staging first), automatic + manual backup schedule (DB + uploads), retention, and
the staging→prod promotion workflow (reuses `wp-ship`). Pull `deploy.*` for the
concrete host.

## 4. Monitoring checklist

→ `docs/monitoring-checklist.md`: uptime monitor on `urls.production`, SSL expiry,
form-submission delivery test, broken-link recheck (reuse `wp-qa`), Core Web
Vitals recheck, security/login alerts (from `security` plugins), disk/DB growth.

## 5. Maintenance runbook + rollback

→ `docs/maintenance-runbook.md` from `references/maintenance-runbook.md`: common
tasks (add a page/CPT entry, update a plugin safely, clear cache, regenerate
thumbnails), troubleshooting (white screen, plugin conflict, cache issues), and
the **rollback pointer**: `deploy.rollbackPoint` + the `wp-ship` rollback steps.

## Acceptance

- All five docs exist in the target `docs/`, populated from the manifest (no
  empty placeholders).
- Credentials doc contains pointers only — zero real secret values.
- Runbook links rollback to `deploy.rollbackPoint` and the `wp-ship` procedure.

See: `references/maintenance-runbook.md`.
