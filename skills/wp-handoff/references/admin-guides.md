# Admin guides + screenshots (handoff sub-step 6)

The contract for the screenshot-based `wp-admin` guides the handoff stage authors
into the target project's `docs/guides/`. `SKILL.md` section 6 orchestrates; this
file holds the detail (layout, flow→doc mapping, image + placeholder conventions,
resume rules) so `SKILL.md` stays lean.

Everything is enumerated FROM `wp-build.json` by `scripts/handoff-guide-spec.sh`,
captured by `scripts/admin-capture.mjs`, then written up by Claude in the confirmed
language. Screenshots and guide markdown go into the **target** project only.

## Language: confirm once, apply to admin UI + prose

The screenshots and the guide prose MUST be in the **same** language.

1. **Confirm the language** with `AskUserQuestion`, offering `i18n.locales`
   (default/first = `i18n.defaultLocale`). In `--auto` or any non-interactive run,
   skip the question and use `i18n.defaultLocale` (log the choice). Record it as
   `handoff.guides.locale`.
2. **Set the admin UI locale — user-locale ONLY** (never site-wide `WPLANG`, never
   `--activate`, so the front-end and Polylang content are untouched). Map the
   short locale to a WordPress locale code, then:

   ```bash
   # <wp-locale>: vi -> vi | ja -> ja | en -> en_US (default; install is a no-op)
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" language core install <wp-locale>
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" user meta update admin locale <wp-locale>
   ```

   `admin` is the login the engine signs in as (override with `WP_ADMIN_USER`). The
   `locale` user-meta changes only that admin's dashboard language — the screens the
   engine captures — so the shots match the prose. Reset later with
   `user meta delete admin locale` if desired.

## wp-env readiness (auto-start; fall back cleanly)

Guides need a live site. Before capturing:

1. If Docker is available and wp-env is not up, start it:
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/wp-env-bootstrap.sh"` (idempotent).
2. Probe readiness: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" option get siteurl`.
   If the probe fails (no Docker, wp-env down) → **skip capture, go to placeholder
   mode** (below). Do not block the stage.

Resolve the base URL from the manifest: `env.localUrl` → else `urls.local` → else
`http://localhost:<env.port>` → else `http://localhost:8888`.

## Build the spec, then capture

```bash
# 1. Enumerate the flows for the confirmed locale (deterministic, no wp-env):
bash "${CLAUDE_PLUGIN_ROOT}/scripts/handoff-guide-spec.sh" wp-build.json --locale <loc> \
  > docs/guides/assets/<loc>/capture-spec.json

# 2. Capture (login + per-flow screenshots). Reuses the wp-env admin creds by
#    default (admin/password); override with WP_ADMIN_USER / WP_ADMIN_PASS.
node "${CLAUDE_PLUGIN_ROOT}/scripts/admin-capture.mjs" \
  --spec docs/guides/assets/<loc>/capture-spec.json \
  --base-url <base-url> --out docs/guides/assets/<loc> --locale <loc>
```

Engine exit codes: `0` captured · `2` bad args/spec · `3` Playwright missing (prints
the install command; install then retry) · `4` wp-env/login unreachable → **placeholder
mode**. Per-step navigation failures are logged and skipped, not fatal (e.g. a plugin
settings page that 404s because the plugin is inactive).

Read `docs/guides/assets/<loc>/capture-manifest.json` — `{ flows: { <id>: [relPaths] } }`
— to know which screenshots each flow actually produced.

## Output layout

```
docs/guides/
  README.md                              # index, grouped by category, in <loc>
  01-auth.md, 02-post.md, 03-page.md ...  # one doc per flow, numbered by spec order
  assets/<loc>/capture-spec.json          # the spec (kept for re-runs)
  assets/<loc>/capture-manifest.json      # engine output
  assets/<loc>/<flow-id>/NN-<step>.png    # screenshots
```

Add a link from `docs/site-handbook.md` to `docs/guides/README.md` ("Step-by-step
guides with screenshots").

## Flow → doc mapping + guide template

One markdown doc per spec flow, numbered by the flow's position in the spec (stable
because the spec is deterministic). Write the prose in `<loc>`; embed each screenshot
with a **relative** path and only after confirming the file exists in the capture
manifest. Skeleton (translate headings/body into `<loc>`):

```markdown
# <flow.title, localized>

<one sentence: what this lets the client do>

**Before you start:** sign in at `<base-url>/wp-login.php`.

## Steps
1. <action for step 1, localized>
   ![<localized alt>](assets/<loc>/<flow-id>/01-<step>.png)
2. <action for step 2 …>
   ![…](assets/<loc>/<flow-id>/02-<step>.png)

**Tips:** <flow.strategyNote localized; warnings; where saved>
```

- **CRUD flows** (post, page, each CPT): the list screen + the editor screen are the
  captured screens; describe fill → publish → edit → trash in prose around them. For
  `classic-acf` CPTs, mention the ACF field group in the editor (`flow.strategyNote`).
- **Customizer / branding** — branch by `strategy`:
  - `classic-acf` → one doc per control (header logo, footer logo, **each** color,
    reset), each with its deep-linked screenshot.
  - `block-fse` / `page-builder` → the Styles/Builder **panel** screenshot + prose
    describing each color/logo action (no per-color screenshot; the colors are
    native Global Styles / Global Colors, not discrete Customizer controls).
- **Extra flows**: Menus, Media + featured image, each plugin's config (from
  `plugins[]`), Settings & Users, and Translations when `i18n.enabled`.

## Placeholder fallback (wp-env down)

When the readiness probe fails or the engine exits `4`:

1. Still author every guide doc + the README, in `<loc>`, from the spec.
2. Where a screenshot would go, embed the shared placeholder and a re-run note:

   ```markdown
   > 📸 Screenshot pending — capture was skipped because the local WordPress
   > environment was not running. Re-run to fill them in (see README).

   ![pending](assets/<loc>/_pending.svg)
   ```

   Write `assets/<loc>/_pending.svg` once from the template at the bottom of this file.
3. Keep `capture-spec.json` in place (it already is).
4. Put the exact re-run command at the top of `docs/guides/README.md`:

   ```bash
   node "${CLAUDE_PLUGIN_ROOT}/scripts/admin-capture.mjs" \
     --spec docs/guides/assets/<loc>/capture-spec.json \
     --base-url <base-url> --out docs/guides/assets/<loc> --locale <loc>
   # then re-run /wp-pro-max:handoff --force to embed the new screenshots
   ```

5. Set `handoff.guides.mode = "placeholder"` and leave each flow's `screenshots: []`.

## Resume + idempotency

- Store per-flow state in `handoff.guides.flows[]` (`id`, `title`, `category`, `doc`,
  `screenshots[]`). The `id` is the stable resume key from the spec.
- On re-run **without `--force`**: skip any flow already recorded with
  `mode == "captured"` and a non-empty `screenshots[]` — reuse its doc + images. Only
  capture flows that are new (manifest grew) or still placeholder.
- On re-run **with `--force`**: re-capture and re-author every flow.
- **Placeholder → captured upgrade**: because a placeholder run does not fully satisfy
  the guides, `SKILL.md` section 0 lets the stage re-enter when
  `handoff.guides.mode == "placeholder"` even if `handoff` is marked done — so a later
  run (with wp-env up) upgrades the placeholders. Filter the spec down to the
  not-yet-captured flows before invoking the engine to avoid re-shooting captured ones.

## Manifest write

```bash
wpbuild_set '.handoff.guides' '{
  "locale": "<loc>", "mode": "captured", "generatedAt": "<iso8601>",
  "flows": [ { "id": "auth", "title": "…", "category": "auth",
               "doc": "docs/guides/01-auth.md",
               "screenshots": ["docs/guides/assets/<loc>/auth/01-login.png", "…"] } ]
}'
```

Paths are repo-relative to the target project root (never absolute host paths).

## `_pending.svg` template (placeholder image)

Write verbatim to `docs/guides/assets/<loc>/_pending.svg` in placeholder mode:

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="960" height="360" role="img" aria-label="Screenshot pending">
  <rect width="960" height="360" fill="#f1f5f9"/>
  <rect x="1" y="1" width="958" height="358" fill="none" stroke="#cbd5e1" stroke-width="2" stroke-dasharray="8 6"/>
  <text x="480" y="170" text-anchor="middle" font-family="sans-serif" font-size="34" fill="#475569">Screenshot pending</text>
  <text x="480" y="215" text-anchor="middle" font-family="sans-serif" font-size="20" fill="#64748b">Re-run the capture command in README to generate it</text>
</svg>
```
