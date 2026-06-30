# Journal — 2026-06-30

## Session

Brainstormed the `/wp-pro-max:audit` command and the behavior of the bare `/wp-pro-max` prefix.

## Key decisions

- `/wp-pro-max` with no subcommand is currently undefined. To give it behavior we need a new `commands/wp-pro-max.md`.
- New command `/wp-pro-max:audit` will be a **hybrid wrapper command**.
- Scope: self-authored theme + plugin only; skip core/vendor/third-party by default.
- Checklist: a11y (WCAG 2.2 AA), security, performance, code style / WordPress conventions.
- Output: Markdown + JSON report; writes `audit` entry to `wp-build.json`.
- No auto-fix; read-only audit.
- Runs static checks always; live checks only when wp-env is running.

## Artifacts

- `reports/brainstorm-2026-06-30-wp-pro-max-audit.md`

## Next step

Run `/ck:plan reports/brainstorm-2026-06-30-wp-pro-max-audit.md`.
