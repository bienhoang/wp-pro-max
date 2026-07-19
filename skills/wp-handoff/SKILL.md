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
- `docs/guides/` — step-by-step `wp-admin` guides **with real screenshots**, one
  per admin flow, in the confirmed language (see section 6 + `references/admin-guides.md`).
- `docs/handoff-site/` — **optional** single-file HTML render of the handoff
  package (`index.html` + `assets/`), produced only on `--html` or user opt-in
  (see section 7 + `references/html-export.md`).

Then `wpbuild_progress handoff done`.

## 0. Resume guard + summary

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh"
# Skip only when fully done AND the admin guides were actually captured. A
# placeholder-guides run (wp-env was down) re-enters so a later run can upgrade
# the screenshots without --force (section 6).
GUIDES_MODE="$(wpbuild_get '.handoff.guides.mode // "none"')"
wpbuild_is_done handoff && [[ "${1:-}" != "--force" ]] && [[ "$GUIDES_MODE" != "placeholder" ]] \
  && { echo "handoff done"; exit 0; }
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
- **Step-by-step guides**: link to `docs/guides/README.md` — the screenshot
  walkthroughs authored in section 6 ("Full step-by-step guides with screenshots").
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

## 6. Admin guides + screenshots

Author step-by-step `wp-admin` guides with **real screenshots** into
`docs/guides/`, one per admin flow, in a language confirmed for this run. Full
contract in `references/admin-guides.md` — the flow, in order:

1. **Confirm the language** (`AskUserQuestion`, options from `i18n.locales`,
   default `i18n.defaultLocale`; `--auto`/non-interactive → `defaultLocale`). Record
   as `handoff.guides.locale`.
2. **Set the admin UI locale — user-locale only** (NOT site-wide `WPLANG`, no
   `--activate`), so screenshots match the prose without touching the front-end:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" language core install <wp-locale>
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" user meta update admin locale <wp-locale>
   ```
3. **Ensure wp-env is up** (`wp-env-bootstrap.sh` if Docker present) and probe
   `wpx option get siteurl`. Probe fails → **placeholder mode** (step 6), don't block.
4. **Enumerate + capture**: `handoff-guide-spec.sh --locale <loc>` → the spec, then
   `admin-capture.mjs --spec … --base-url <url> --out docs/guides/assets/<loc>`.
   Handle the engine exit code (`3` install Playwright + retry; `4` → placeholder).
5. **Author** one guide doc per flow (prose in `<loc>`, screenshots embedded with
   relative paths, only after checking the capture manifest lists them), a
   `docs/guides/README.md` index, and the `site-handbook.md` link. Customizer detail
   branches by `strategy` (classic-acf = per-control; block-fse/page-builder = panel).
6. **Placeholder fallback** (wp-env down): still author every doc + README from the
   spec, embed the `_pending.svg` placeholder + the exact re-run command, keep the
   spec, set `mode: "placeholder"`.
7. **Record** `handoff.guides` via `wpbuild_set '.handoff.guides' …` (locale, mode,
   `generatedAt`, `flows[]` with `id`/`title`/`category`/`doc`/`screenshots[]`).
   **Resume**: skip flows already `captured` with screenshots unless `--force`.

## 7. HTML export (optional)

Offer a single self-contained HTML site of the whole handoff package (guides +
the other client docs) so everything shares one style. Full contract in
`references/html-export.md`. Flow:

1. **Decide whether to run.** If invoked with `--html` → run. Else, in an
   interactive run → `AskUserQuestion` ("Export the handoff into a single HTML
   site?" · yes/no). In `--auto`/non-interactive without `--html` → skip + log.
2. **Resolve the target origin** (links must never point at localhost) — else
   the script defaults it: `ORIGIN="$(wpbuild_get '.urls.production // "<your-domain>"')"`.
3. **Render** (the script does all the work):
   ```bash
   node "${CLAUDE_PLUGIN_ROOT}/scripts/handoff-html-export.mjs" \
     --manifest wp-build.json --docs docs --out docs/handoff-site \
     --domain "$ORIGIN" --generated-at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
   ```
   Exit `2` → docs missing (run earlier steps first); `5` → a localhost URL
   survived (report, don't record). Parse the summary line for the counts + mode.
4. **Link it** from `docs/site-handbook.md` ("Browse the full handoff as a
   website: `docs/handoff-site/index.html`").
5. **Record** `handoff.htmlExport` (`generatedAt`, `output`, `domainMode`,
   `sections[]`, `imagesCopied`) via `wpbuild_set` — see `references/html-export.md`.

The credentials doc is excluded from the HTML by design; it stays markdown-only.

## Acceptance

- All five core docs exist in the target `docs/`, populated from the manifest (no
  empty placeholders).
- Credentials doc contains pointers only — zero real secret values.
- Runbook links rollback to `deploy.rollbackPoint` and the `wp-ship` procedure.
- `docs/guides/` has a README index + one guide per enumerated flow (every CPT,
  taxonomy, customizer control/panel, plugin, plus auth/menu/media/settings). Prose
  and the admin UI in the screenshots share the confirmed language.
- `handoff.guides` records `locale`, `mode`, and per-flow `doc` + `screenshots`.
  wp-env down → `mode: "placeholder"` with a re-run command, pipeline not blocked.
- If the HTML export ran: `docs/handoff-site/index.html` + `assets/` exist, no
  `localhost` in the HTML, the credentials doc is absent, and `handoff.htmlExport`
  is recorded. Skipped cleanly (logged) when neither `--html` nor opt-in applies.

See: `references/maintenance-runbook.md`, `references/admin-guides.md`,
`references/html-export.md`.
