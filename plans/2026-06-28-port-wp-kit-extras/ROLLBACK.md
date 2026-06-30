# Rollback Instructions — Port WP Kit extras

This plan is additive. To revert, delete the created files and reverse the small documentation edits listed below.

## Files to delete

```text
scripts/validate-port.sh
skills/wp-performance-backend/SKILL.md
skills/wp-a11y/SKILL.md
agents/a11y-checker.md
commands/a11y-audit.md
skills/figma-bridge/SKILL.md
skills/figma-bridge/references/figma-mcp-setup.md
agents/figma-analyzer.md
commands/figma.md
commands/component.md
```

After deleting, remove empty directories:

```bash
rmdir skills/wp-performance-backend skills/wp-a11y skills/figma-bridge/references skills/figma-bridge 2>/dev/null || true
```

## Documentation edits to reverse

### `README.md`

1. In **Components > Commands**, remove `, a11y-audit, figma, component` and restore the previous command list.
2. In **Components > Skills**, change `(22)` back to `(19)` and remove `wp-a11y`, `wp-performance-backend`, and `figma-bridge` from the list.
3. In **Components > Agents**, change `(6)` back to `(4)` and remove `a11y-checker` and `figma-analyzer`.

### `docs/codebase-summary.md`

1. In **Layout > commands/**, remove `, a11y-audit.md, figma.md, component.md`.
2. In **Layout > skills/**, change `23 skills` back to `20 stage skills`.
3. In **Layout > agents/**, remove `, a11y-checker, figma-analyzer`.
4. In **Skills → stage ids**, delete the rows for `wp-performance-backend`, `wp-a11y`, and `figma-bridge`.
5. In **Scripts**, delete the `validate-port.sh` row.

### `docs/project-roadmap.md`

1. Delete the row `| 13 WP Kit extras port | ... | ✅ done |`.

## Verification after rollback

```bash
bash scripts/validate-port.sh
# Expected: fails because the port files are gone.

claude plugin validate .
# Expected: passes (the plugin core is unchanged).
```
