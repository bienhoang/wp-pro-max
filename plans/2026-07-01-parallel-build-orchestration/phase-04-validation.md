---
phase: 4
title: "Validation"
status: pending
effort: ""
priority: P2
dependencies: [1, 2, 3]
---

# Phase 4: Validation

## Overview

Verify the changes are internally consistent, the one script change is correct,
and the plugin still validates. The repo has no test runner; validation =
plugin gate + behavioral check of the write-guard + a manual sweep of the
fan-out ownership/crash-safety invariants.

## Requirements

- Functional: plugin manifest validates; write-guard behaves per Phase 1; all
  new/edited files cross-link correctly; no contradictions across contract +
  skill + command + agent constraints.
- Non-functional: cheap, repeatable.

## Architecture

Gates (from CLAUDE.md):
- `claude plugin validate .` — authoritative manifest gate.
- `bash -n scripts/manifest-core.sh` — the one changed script.
- Behavioral write-guard check with a mocked/throwaway manifest (no WP needed).

Manual review checklist (the real safety net):
- **Write-guard:** with `WP_BUILD_RETURN_FRAGMENT=1`, `wpbuild_set/merge/progress`
  do not modify the file and emit `WPBUILD_FRAGMENT {json}`; unset → unchanged
  behavior; read helpers + plugin pipeline unaffected.
- **Ownership:** foundation owns all shared singletons incl. `functions.php`
  pattern categories; template-agent spawn prompt forbids `functions.php` edits,
  new categories, and any WP-CLI/activation; orchestrator validates
  `files ⊆ assignedSet`.
- **N-join:** derivation reads `contentModel.postTypes`, not just
  `analysis.pages`; fan-out asserts `contentModel` present.
- **Crash-safety (V2):** barrier aborts on partial foundation; a not-done
  `convert` resume wipes the theme dir and rebuilds; activation happens once,
  orchestrator-only, post-merge.
- **No scope creep:** no Wave-A parallelism, no `i18n‖security` overlap, no
  env/plugins reorder reintroduced; canonical stage order in `build.md`
  unchanged.
- **Cross-links:** every reference to `references/parallel-execution.md` resolves;
  the Phase-1 flag name matches across core script, contract, and skill.

## Related Code Files

- Read/verify: `scripts/manifest-core.sh`, `references/parallel-execution.md`,
  `skills/theme-conversion/SKILL.md`, `commands/build.md`,
  `agents/wp-theme-developer.md`
- No code modified in this phase.

## Implementation Steps

1. `bash -n scripts/manifest-core.sh`; source in bash and zsh with the flag set
   and unset; run the throwaway-manifest write-guard smoke test.
2. `claude plugin validate .`; fix any manifest errors.
3. Grep for the flag name + `parallel-execution.md` links; confirm all resolve
   and names match across files.
4. Walk the manual checklist; reconcile any wording contradiction across edited
   files (whole-plan consistency).
5. Confirm `git diff --stat` touches only `scripts/manifest-core.sh`,
   `references/`, `skills/theme-conversion/`, `commands/build.md`, `plans/`.

## Success Criteria

- [ ] `claude plugin validate .` passes.
- [ ] `bash -n scripts/manifest-core.sh` clean; guard verified both flag states.
- [ ] No broken cross-links; Phase-1 flag name consistent everywhere.
- [ ] Ownership / N-join / crash-safety invariants consistent between
      `parallel-execution.md` and `theme-conversion/SKILL.md`.
- [ ] No dropped-scope feature reintroduced; canonical stage order intact.
- [ ] `git diff --stat` shows only the expected files.

## Risk Assessment

- Risk: "passes validate" but operationally wrong → the manual checklist + the
  write-guard smoke test are the real gate; treat contradictions as blockers.
- Risk: future concurrent stages added without the guard flag → out of scope;
  `parallel-execution.md` documents the guard so new concurrent work inherits it.
