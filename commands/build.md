---
description: Run the full WP Pro Max pipeline — static HTML (or a brief) to a production WordPress site.
argument-hint: <source-html-dir | url | brief.md> [--strategy classic-acf|block-fse|page-builder] [--from <stage>] [--to <stage>] [--auto]
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Task, Skill]
---

# /wp-pro-max:build

Orchestrate the end-to-end pipeline that turns `$ARGUMENTS` (a folder of static
HTML, a URL, or a requirements brief) into a working WordPress site. State lives
in `wp-build.json` in the current project, so the run is **resumable** and
**idempotent** — re-running skips completed stages unless `--force`.

## Input

- `$1` = source: a directory of HTML/CSS/JS, a URL, or a `.md` brief.
- `--strategy` = theme backend (default: auto-detected by `html-analysis`).
- `--from <stage>` / `--to <stage>` = run a sub-range of the pipeline.
- `--auto` = run without per-stage gates (still gates ship on confirmation).
- In an `init`-scaffolded parent-wrapper project, inputs live at the project root
  and the manifest is in `wp/`. `build` auto-descends into `wp/` when the manifest
  is not in the current dir.

## Stage order

```
env? → analyze → optimize → model → tokens → convert → plugins →
scaffold → seed-content → seed-plugin-data → i18n → seo → security →
qa → ship → handoff
```

Each stage is owned by a skill (`wp-pro-max:<skill>`). Invoke the matching skill
in order. After each stage, read `wp-build.json` progress and report briefly.

`convert` is internally parallel: it authors the theme with a foundation agent
then N parallel template agents and merges their outputs (see
`references/parallel-execution.md`). This is an in-stage detail — the canonical
stage order, gates, and `--from/--to` ranges above are unchanged.

## Procedure

1. **Init / resume.** Resolve project root: if `wp-build.json` is not in the
   current dir but `./wp/wp-build.json` exists (the `init`-scaffolded
   parent-wrapper layout), run subsequent stages from `./wp/` (`cd ./wp`).
   If `wp-build.json` is still absent, derive project name + theme slug from
   the source and create it:
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh"` helpers, or write a
   minimal manifest (`version:"1"`, `project`, `strategy`, `progress:{}`). Record
   `source.*`. If present, print `wpbuild_status` and continue from the first
   non-`done` stage.
2. **Provision env first.** Run the `wp-env-setup` skill (`env` stage) so later
   stages have a live WordPress: scaffolds `.wp-env.json`, `wp-env start`.
3. **Run each stage in order** by invoking its skill. Honor `--from/--to`. Stop
   and surface the error if a stage fails (its progress is marked `failed`).
4. **Gate (interactive mode).** After analysis/design-affecting stages (analyze,
   convert, plugins), summarize and ask the user to confirm before continuing.
   In `--auto`, skip gates except ship.
5. **QA gate before ship.** `ship` refuses unless `qa.passed == true`. If QA
   fails, report the diffs/links/a11y issues and stop.
6. **Ship** only after explicit confirmation of host + path (always, even `--auto`).
7. **Handoff.** Generate the client docs package into the target `docs/`.

## Delegation

Heavy work goes to agents (keep this command as the coordinator):
`wp-theme-developer` (theme code), `wp-data-engineer` (seeding/DB),
`wp-deployer` (ship/migration). Give each: target paths, the manifest path,
files it may modify, and acceptance criteria — never full history.

## Output

A short progress report after each stage and a final summary: pages built, theme
strategy, plugins, locales, QA result, and (if shipped) the production URL +
rollback point. List any failed/skipped stages and how to resume
(`/wp-pro-max:build --from <stage>`).
