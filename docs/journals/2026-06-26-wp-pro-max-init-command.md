# Journal — 2026-06-26

## wp-pro-max:init project scaffolder command

### What changed
- Added `commands/init.md` — `/wp-pro-max:init <project-name> [--slug <slug>] [--strategy classic-acf|block-fse|page-builder]`.
- Scaffold produces the parent-wrapper layout: inputs (`requirements/`, `source/`, `assets/`, `design/`, `mockups/`) at the project root and the WordPress project (`wp/wp-build.json`) under `wp/`.
- `wp/wp-build.json` is written via `scripts/manifest-lib.sh` (`wpbuild_init` + `wpbuild_merge`); `source.type` is intentionally omitted for the analyze stage to detect.
- `git init` at project root, idempotent.
- `commands/build.md` auto-descends into `wp/` when `./wp-build.json` is absent but `./wp/wp-build.json` exists.
- `skills/html-analysis/SKILL.md` step 1 now auto-detects `source.type` from `source.htmlPaths` (HTML present → `html-files`) or a non-empty brief (→ `brief`).
- Docs updated: `README.md`, `docs/codebase-summary.md`, `docs/system-architecture.md`.

### Key decisions
- Directory name uses the derived kebab-case slug rather than the raw project name (fixes an inconsistency in the plan’s success criteria and avoids spaces in paths).
- Detection logic resolves `source.htmlPaths` / `source.briefPath` relative to the manifest directory, matching the layout where build runs from `wp/`.
- Validation is behavioral (scratchpad `mktemp`), consistent with the repo’s no-test-suite convention.

### Validation
- `bash -n` clean on extracted scaffold script.
- Scaffold for `"Acme Studio"` created expected tree, manifest shape (incl. absent `source.type`), templates, and git repo.
- Idempotency verified via file-hash snapshot.
- Auto-descend guard and relative path resolution verified.
- Analyze `source.type` detection verified for both `brief` and `html-files`.
- `claude plugin validate .` passed.

### Commit
- `f685d26` — `feat(commands): add /wp-pro-max:init project scaffolder`

### Risks / follow-ups
- `init` checks only `$ROOT/.git` for idempotency; monorepo users working inside an existing git tree may get a nested `.git`. Acceptable for current scope.
- Non-ASCII project names are stripped from the derived slug; users must pass `--slug` for non-Latin names.
