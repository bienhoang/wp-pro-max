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

2. **Resolve theme path + resume-wipe.** Theme lives at
   `<target>/wp-content/themes/<themeSlug>/` (mounted live via `.wp-env.json`
   `mappings`, set by the `env` stage). Step 1 only continues for a **not-done**
   `convert`, so **wipe the theme directory and recreate it empty** before
   authoring. A clean rebuild leaves no orphan template from a crashed prior run
   to hijack WordPress template resolution (a `done` convert never reaches here).

3. **Route by strategy** and load the matching reference. Each reference has the
   concrete file set, real template content, and the build order:
   - `classic-acf` → `${CLAUDE_PLUGIN_ROOT}/references/classic-acf.md`
   - `block-fse` → `references/block-fse.md`
   - `page-builder` → `references/page-builder.md`

   For `classic-acf`, read `references/classic-acf.md` before authoring any
   classic theme files; it defines the canonical file set, naming conventions,
   template patterns, and anti-patterns.

4. **Template-map reference.** Each `analysis.pages[].path` maps to the WordPress
   template that renders it; template agents follow this table and return their
   bucket's entries, which the orchestrator merges in step 7. Roles:

   | `role` | classic-acf | block-fse | page-builder |
   |--------|-------------|-----------|--------------|
   | `home` | `front-page.php` | `templates/front-page.html` | page + `_elementor_data` |
   | `page` | `page.php` (or `page-{slug}.php`) | `templates/page.html` | page + `_elementor_data` |
   | `landing` | `landing.php` (or `templates/landing.php`) | `templates/page-landing.html` | page + `_elementor_data` |
   | `archive` | `archive-<cpt>.php` | `templates/archive.html` | builder archive template |
   | `single` | `single-<cpt>.php` | `templates/single.html` | builder single template |
   | `post` | `single.php` | `templates/single.html` | builder single template |

   Root templates are the default for `classic-acf`; use `templates/` only for
   custom page templates that need a `Template Name:` header.

5. **CSS variables / tokens.** classic-acf and page-builder emit a
   `:root{ --color-…: … }` block (from `designTokens`) into the theme stylesheet;
   block-fse emits `theme.json` instead (no hand-written CSS vars).

6. **Author the theme — foundation → barrier → fan-out.** `convert` authors the
   theme with concurrent **wp-theme-developer** agents. Spawn **every** agent
   (foundation and template) with `WP_BUILD_RETURN_FRAGMENT=1` so it cannot write
   the manifest — this skill is the sole writer. Full rules:
   `${CLAUDE_PLUGIN_ROOT}/references/parallel-execution.md`.

   a. **Pre-compute pattern categories.** Derive the full block-pattern category
      list from `analysis.components` + `contentModel`; pass it to the foundation.

   b. **Foundation agent (1, blocking).** Spawn one wp-theme-developer to write the
      shared singletons + all convert-time `functions.php`, including the
      pre-computed pattern-category registrations:
      - classic-acf / page-builder: `style.css` (`:root{ --… }` tokens), minimal
        `functions.php` (text domain, enqueue stub, pattern categories),
        `header.php`, `footer.php`, shared template parts.
      - block-fse: `theme.json` (tokens), `templates/parts/header.html`,
        `templates/parts/footer.html`, minimal `functions.php` with a
        `register_block_pattern_category()` for every category templates will use.

      Constraint: **no wp-env/WP-CLI, no activation.** Returns
      `{ files[], sharedContract: { paths, slots, patternCategories[], cssConventions } }`.

   c. **Barrier.** Verify every `sharedContract` path exists and is non-empty. If
      the foundation failed or is partial → **abort**: spawn no template agents,
      leave `convert` not-done, surface the error.

   d. **Derive N + bucket.** Join `analysis.pages[]` (`role`) with
      `contentModel.postTypes[].slug` to place archive/single pages on their CPT
      (requires `model` done — assert `contentModel.postTypes` present, else
      error). Bucket by role, **hard-cap 4**:

      | Bucket | Templates |
      |--------|-----------|
      | 1 | `home` + `landing` |
      | 2 | static `page` templates |
      | 3 | `archive-{cpt}` + `single-{cpt}` (grouped by the joined CPT slug) |
      | 4 | `post`/blog templates (only if distinct from CPT singles) |

      Collapse empty buckets; if ≤1 non-empty bucket remains → a **single**
      template agent (no fan-out overhead).

   e. **Template agents (N, parallel, single message).** Spawn each
      wp-theme-developer with `WP_BUILD_RETURN_FRAGMENT=1` and: theme path,
      manifest path, the chosen reference, its bucket's pages/components, the
      token set, the foundation `sharedContract`, and **its exact writable file
      list**. State these hard constraints in the prompt:
      - Author ONLY files in your writable list; create no others.
      - Read foundation files READ-ONLY; never edit `functions.php`, `style.css`,
        `theme.json`, or shared parts.
      - Use ONLY `sharedContract.patternCategories`; register no new categories.
      - **Run NO `wp-env`/WP-CLI command and do NOT activate the theme** — author
        files and return paths only (overrides the agent's default self-activation).
      - Follow `sharedContract` (slots, shared parts, `cssConventions`) + the
        strategy reference for naming, escaping, i18n, and partials, so
        independently authored templates stay uniform (no post-merge normalization).

      Each returns `{ files[], templateMap }` for its bucket.

7. **Validate + merge (orchestrator) + finish.** For each returned agent: assert
   `files ⊆ assignedSet` (reject + fail the stage on any out-of-set path); assert
   no `templateMap` key collisions across buckets. Persist **incrementally** as
   each agent returns (this skill writes via the normal `wpbuild_set`, flag unset):

   ```bash
   wpbuild_set '.theme.path' "\"wp-content/themes/${SLUG}\""
   # files = JSON array of theme-relative paths, concatenated across buckets
   wpbuild_set '.theme.files' "$FILES_JSON"
   # templateMap = merged across buckets, e.g. { "index.html": "front-page.php", ... }
   wpbuild_set '.theme.templateMap' "$TEMPLATE_MAP_JSON"
   wpbuild_progress convert done "strategy=${STRATEGY}"
   ```

8. **Activate once (orchestrator only).** After merge, this skill — never an
   agent — activates and checks for fatals a single time:
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" theme activate <themeSlug>` then
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" theme list --status=active`. (Requires `env` stage first;
   if wp-env not yet running, defer activation to the `env`/`scaffold` stage.)

## Notes

- Before converting, warn if `siteEditor.preConversionQa.passed == false` and
  summarize the failing checks. Do **not** block conversion; just surface the
  warning so the user can decide whether to fix the optimized copy first.
- The `convert` stage produces the theme *skeleton* + template map. Registering
  CPTs/taxonomies, ACF field-group JSON, menu locations, enqueues, and image
  sizes is the **`scaffold`** stage (wp-scaffold) — it fills the wiring this
  stage stubbed. Keep `functions.php` minimal here; scaffold extends it.
- Always namespace PHP function names and the text domain with the theme slug to
  avoid collisions.
- Keep `SKILL.md` lean — the real template content lives in the references.
