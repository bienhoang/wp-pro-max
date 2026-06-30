# Stage Contract & Skill Authoring Conventions

All WP Pro Max stages obey this contract so the pipeline stays composable,
resumable, and idempotent. Read this before authoring any stage skill.

## The manifest

- Single source of truth: `wp-build.json` in the **target WordPress project** root.
- Schema: `schemas/wp-build.schema.json`. Helpers: `scripts/manifest-lib.sh`.
- Every stage: (1) reads inputs from the manifest, (2) does work, (3) writes its
  outputs back, (4) records progress via `wpbuild_progress <stage-id> <status>`.
- Stages must be **resumable**: if `wpbuild_is_done <stage-id>`, skip unless `--force`.

## Stage ids (canonical)

`analyze` · `optimize` · `model` · `tokens` · `convert` · `plugins` ·
`scaffold` · `seed-content` · `seed-plugin-data` · `qa` · `seo` · `security` ·
`i18n` · `ship` · `env` · `handoff` · `audit` · `section-redesign` ·
`content-enrichment` · `pre-conversion-qa`

Three additional stage ids are owned by `/wp-pro-max:site-editor` and run
**outside the main pipeline**: `section-redesign`, `content-enrichment`, and
`pre-conversion-qa`. They are optional, non-gating (they do not block `ship`),
and operate only on `optimization.outputDir`. They must never mutate `source/`
or `assets/`; all edits target the optimized working copy.

## Skill layout (each skill folder)

```
skills/<skill-name>/
  SKILL.md            # frontmatter + instructions (≤ ~200 lines; link refs)
  references/*.md     # deep detail loaded on demand
  templates/*         # code templates the skill emits (optional)
```

## SKILL.md frontmatter

```yaml
---
name: <skill-name>            # becomes wp-pro-max:<skill-name>
description: <when to invoke — third person, includes trigger words>
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]   # restrict sensibly
---
```

Write `description` so the model auto-invokes correctly (mention "WordPress",
the stage verb, and inputs/outputs). Keep instructions imperative and concrete.

## wp-env / WP-CLI invocation

- All WordPress CLI runs go through wp-env:
  `wp-env run cli wp <command>` (CWD = target project with `.wp-env.json`).
- Mount the generated theme via `.wp-env.json` `mappings` so edits are live.
- Never hardcode container paths; rely on wp-env defaults.

## Idempotency rules

- Content/data seeding runs as a **single PHP batch** per stage: the skill emits a
  pure-JSON payload and `scripts/seed-batch-run.sh` applies it via
  `wp eval-file scripts/seed-batch-runtime.php` (payload on stdin). Every op
  **checks before create** in-process via the WP API, so re-runs produce zero
  duplicates (the re-run summary reports `created:0`).
- Use stable idempotency keys (post slugs, option names, menu names, media titles,
  Elementor element ids) recorded in `seed.idempotencyKeys` (merged append+unique).
- The driver also records `seed.lastRun` and `seed.lastSummary` (counts + errors)
  and fails loudly on a zero-op or incomplete run — never a silent "done".
- DB writes use the WP API (no raw `$wpdb` writes in the runtime). A raw
  `wp db query` is a documented last resort with explicit guards; destructive ops
  require a `--dry-run`/`SELECT` preview first.

## Delegation

- Heavy code authoring → `wp-theme-developer` agent.
- Seeding / DB work → `wp-data-engineer` agent.
- Deploy / migration → `wp-deployer` agent.
- Pass the agent: target paths, the manifest path, files it may modify,
  acceptance criteria, constraints. Never pass full conversation history.

## Theme customization (cross-stage conventions)

End-user branding (header + footer logo, deep `:root` colors, reset-to-defaults)
is baked into every generated theme. It spans `convert` and `scaffold`, so these
conventions are authoritative here (deep detail:
`skills/wp-scaffold/references/theme-customization.md`).

- **Gate:** `theme.customization.enabled` (boolean, default true). The registry
  itself lives in-theme, not in the manifest.
- **`--color-<slug>` verbatim contract.** Each editable color var name is
  `--color-` + the token `slug`, emitted **verbatim** by `convert` (no
  abbreviation: `foreground` ⇒ `--color-foreground`, never `--color-fg`). The
  in-theme registry carries the resulting `cssVar`; Customizer controls, the
  inline-CSS emitter, and reset all read that one `cssVar`. Never re-apply a
  `--color-<slug>` template downstream.
- **`main.css` is `:root`-color-free.** `convert` keeps all `:root` color vars in
  `style.css` and strips them from `assets/css/main.css` (which enqueues after),
  so reset reverts to the token default, not a raw source color.
- **Inline-style handle = `<slug>-main`.** The customizer emitter attaches its
  `:root` override via `wp_add_inline_style( '<slug>-main', … )` (the `main.css`
  style handle). The emitter checks the handle and falls back to `<slug>-style`,
  but no-ops if neither is registered — so both this stage contract and any
  convert-rewrite plan MUST keep the `<slug>-main` handle registered.
- **Footer logo key = `<slug>_footer_logo`**, stored as an **attachment ID**
  (`WP_Customize_Media_Control` + `absint`). A **guarded** render helper
  `<slug>_the_footer_logo()` is defined in `convert` (foundation, behind a
  `function_exists`/empty-mod guard) — `wp_get_attachment_image()` if set, else
  `the_custom_logo()`, else site title — so an activated-but-not-yet-scaffolded
  theme never fatals. The footer render slot must stay in the foundation agent's
  writable set.
- **convert → scaffold re-chain.** `convert` wipes + recreates the theme dir and
  activates it. Customizer code lives in `scaffold`, so the orchestrator MUST
  re-run `scaffold` after any `convert` re-run when customization is enabled, or
  the customizer code is lost (theme_mod *state* is DB-resident and survives the
  wipe, but the *code* does not).
- **theme_mod state migrates on ship.** Branding lives in `theme_mods_<slug>`
  (DB), not files — `ship` must export/import it (and remap the footer-logo
  attachment ID after media reseed) or branding is lost on deploy.

## Scripts (shared, via `${CLAUDE_PLUGIN_ROOT}/scripts/`)

- `manifest-lib.sh` — manifest read/write/progress (Phase 01).
- `seed-batch-runtime.php` — the single shipped PHP seed runtime (reads JSON from
  stdin, applies idempotently via the WP API).
- `seed-batch-run.sh` — seed driver (pipe payload → `wp eval-file`, parse the
  sentinel summary, append+unique merge into `seed.*`).
- `wp-cli-runner.sh` — resolves the WP-CLI runner; binds to this project's
  `*-cli-1` container (never `*-tests-cli-1`).
- `seed-helpers.sh` — **deprecated** create-if-missing shim, superseded by the
  batch engine; retained only for the pending WooCommerce plan.
- `wp-env-bootstrap.sh` — scaffold + start wp-env (Phase 03); mounts
  `optimization.outputDir` so the seed batch reaches media by absolute path.
- `extract-tokens.mjs` — HTML/CSS → design tokens (Phase 02).
- `visual-diff.mjs` — Playwright pixel diff WP vs source (Phase 05).
- `migrate-urls.sh` — `wp search-replace` wrapper for ship (Phase 06).
