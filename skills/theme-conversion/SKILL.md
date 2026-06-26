---
name: theme-conversion
description: >-
  Converts analyzed static HTML into a WordPress theme (stage `convert`).
  Adaptive across three backends — classic-acf (PHP + Advanced Custom Fields),
  block-fse (theme.json + block templates/patterns), and page-builder
  (Elementor/Bricks). Use when building or scaffolding a WordPress theme from
  HTML, generating theme.json, template parts, block patterns, or mapping source
  pages to WordPress templates. Reads analysis, contentModel, designTokens, and
  strategy from wp-build.json; writes theme.{path,files,templateMap}.
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# Theme Conversion (stage `convert`)

Turn the analyzed HTML + derived model + tokens into a real WordPress theme,
choosing the backend that matches `strategy`. Heavy PHP / theme.json / pattern
authoring is delegated to the **wp-theme-developer** agent; this skill owns
routing, the template map, and writing manifest outputs.

## Inputs (read from `wp-build.json`)

| Field | Use |
|-------|-----|
| `strategy` | Selects the backend reference (required). |
| `project.themeSlug` / `project.textDomain` | Theme folder name + i18n text domain. |
| `analysis.pages[]` | Each page's `path`, `role`, `sections[]` → template map. |
| `analysis.components[]` | Repeated blocks (`header`,`footer`,`hero`,`card`…) → template parts / patterns. |
| `contentModel.postTypes/taxonomies/menus/fieldGroups` | What templates + registrations are needed. |
| `designTokens.colors/fonts/spacing/radius/breakpoints` | CSS variables (classic/builder) or `theme.json` (FSE). |

## Procedure

1. **Resume guard.** Source `manifest-lib.sh`; if `wpbuild_is_done convert` and
   no `--force`, stop. Otherwise `wpbuild_progress convert in-progress`.

   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh"
   wpbuild_is_done convert && [[ "${1:-}" != "--force" ]] && { echo "convert done"; exit 0; }
   wpbuild_progress convert in-progress
   STRATEGY="$(wpbuild_get '.strategy')"
   SLUG="$(wpbuild_get '.project.themeSlug')"
   ```

2. **Resolve theme path.** Theme lives at `<target>/wp-content/themes/<themeSlug>/`
   (mounted live via `.wp-env.json` `mappings`, set by the `env` stage). Create
   the directory.

3. **Route by strategy** and load the matching reference. Each reference has the
   concrete file set, real template content, and the build order:
   - `classic-acf` → `references/classic-acf.md`
   - `block-fse` → `references/block-fse.md`
   - `page-builder` → `references/page-builder.md`

4. **Build the template map** while creating templates. Map every
   `analysis.pages[].path` to the WordPress template that renders it. Roles:

   | `role` | classic-acf | block-fse | page-builder |
   |--------|-------------|-----------|--------------|
   | `home` | `front-page.php` | `templates/front-page.html` | page + `_elementor_data` |
   | `page` | `page.php` / `templates/<slug>.php` | `templates/page.html` | page + `_elementor_data` |
   | `landing` | `templates/landing.php` | `templates/page-landing.html` | page + `_elementor_data` |
   | `archive` | `archive-<cpt>.php` | `templates/archive.html` | builder archive template |
   | `single` | `single-<cpt>.php` | `templates/single.html` | builder single template |
   | `post` | `single.php` | `templates/single.html` | builder single template |

5. **CSS variables / tokens.** classic-acf and page-builder emit a
   `:root{ --color-…: … }` block (from `designTokens`) into the theme stylesheet;
   block-fse emits `theme.json` instead (no hand-written CSS vars).

6. **Delegate authoring.** Spawn **wp-theme-developer** with: theme path, the
   manifest path, the chosen reference path, the page/component lists, the token
   set, files it may create, and acceptance criteria (valid theme that activates
   with no PHP notices, escaping + i18n applied, template map complete).

7. **Write outputs + finish.**

   ```bash
   wpbuild_set '.theme.path' "\"wp-content/themes/${SLUG}\""
   # files = JSON array of theme-relative paths created
   wpbuild_set '.theme.files' "$FILES_JSON"
   # templateMap = { "index.html": "front-page.php", "about.html": "page.php", ... }
   wpbuild_set '.theme.templateMap' "$TEMPLATE_MAP_JSON"
   wpbuild_progress convert done "strategy=${STRATEGY}"
   ```

8. **Verify.** Activate and check for fatals:
   `wp-env run cli wp theme activate <themeSlug>` then
   `wp-env run cli wp theme list --status=active`. (Requires `env` stage first;
   if wp-env not yet running, defer activation to the `env`/`scaffold` stage.)

## Notes

- The `convert` stage produces the theme *skeleton* + template map. Registering
  CPTs/taxonomies, ACF field-group JSON, menu locations, enqueues, and image
  sizes is the **`scaffold`** stage (wp-scaffold) — it fills the wiring this
  stage stubbed. Keep `functions.php` minimal here; scaffold extends it.
- Always namespace PHP function names and the text domain with the theme slug to
  avoid collisions.
- Keep `SKILL.md` lean — the real template content lives in the references.
