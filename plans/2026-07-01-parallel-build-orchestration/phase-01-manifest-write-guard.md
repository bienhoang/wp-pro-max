---
phase: 1
title: "Manifest write-guard"
status: pending
effort: ""
priority: P1
dependencies: []
---

# Phase 1: Manifest write-guard

## Overview

Make the "only the orchestrator writes `wp-build.json`" rule **mechanical** instead
of advisory. When `WP_BUILD_RETURN_FRAGMENT=1` is set in the environment, the
manifest write helpers refuse to mutate the file and instead print the
fragment/operation they would have applied to stdout. The orchestrator spawns
concurrent theme agents with this flag set, so a template/foundation agent
**cannot** clobber the manifest even if it (or its underlying `wp-theme-developer`
contract) tries to call `wpbuild_set`.

Addresses red-team **C1** (orchestrator-writes was unenforced prose; the
`manifest-core.sh:33` `jq > tmp && mv` race was still live under concurrency).

## Requirements

- Functional: `_manifest_set`, `_manifest_merge`, `_manifest_progress` become
  no-write + emit-fragment when `WP_BUILD_RETURN_FRAGMENT=1`. Read helpers
  (`_manifest_get`, `_manifest_is_done`, `_manifest_status`) are unaffected.
- Non-functional: zsh-safe (sourced helpers must not enable `set -e` / use
  reserved names — match existing guards); zero behavior change when the flag is
  unset; harmless for the plugin pipeline (`plugin-manifest-lib.sh`) which never
  sets the flag.

## Architecture

Choke point: the three writers in `scripts/manifest-core.sh`
(`_manifest_set:29-34`, `_manifest_merge:38-43`, `_manifest_progress:47-55`).
All three currently do `jq … > tmp && mv tmp file`. Add a single early-return
guard at the top of each writer:

```bash
# When running as a spawned fragment worker, never touch the shared file.
# Emit the intended mutation to stdout for the orchestrator to apply, then return.
if [ "${WP_BUILD_RETURN_FRAGMENT:-}" = "1" ]; then
    printf 'WPBUILD_FRAGMENT %s\n' "<op + args as a single JSON line>"
    return 0
fi
```

- The emitted line uses a stable, greppable prefix (`WPBUILD_FRAGMENT`) so the
  orchestrator can extract it from agent output. Encode op + path + value (for
  `set`/`merge`) or stage + state + notes (for `progress`) as one JSON object,
  e.g. `{"op":"set","path":".theme.files","value":[…]}`.
- Guard lives in `manifest-core.sh` (the shared writer), so both
  `wpbuild_*` and any future wrapper inherit it. It only activates on the
  explicit env flag, so `plugin-manifest-lib.sh` is unaffected.
- Keep `_manifest_require_jq` ordering sane: the guard returns before requiring
  jq for the write (jq still needed by the orchestrator that applies fragments,
  not by the guarded worker).

Note: in the narrowed scope the concurrent writers are the **theme fan-out
agents** only. The guard is intentionally general (any stage spawned as a
fragment worker), so if Wave-A parallelism is ever revisited it already has a
safe primitive — but this plan does not spawn Wave-A workers.

**Defense-in-depth (validation V1).** The `wp-theme-developer` agent contract
already states the calling skill writes manifest outputs and the agent must not
(`agents/wp-theme-developer.md:72-75`), and the `convert` orchestrator is the
single writer. So in this narrowed plan the guard is **insurance, not the sole
barrier** — it makes "an agent (or a future edit) calls `wpbuild_set` and
clobbers the manifest" impossible to regress into, rather than fixing a live
race. Kept because it is cheap and honors red-team C1 (turn the invariant into a
mechanism). This is the honest framing — do not overstate it as "fixes a current
clobber" in the contract/skill prose.

## Related Code Files

- Modify: `scripts/manifest-core.sh` (add guard to the 3 writers)
- Reference only: `scripts/manifest-lib.sh`, `scripts/plugin-manifest-lib.sh`,
  CLAUDE.md (zsh-safety rules)

## Implementation Steps

1. Add the `WP_BUILD_RETURN_FRAGMENT` early-return guard to `_manifest_set`,
   `_manifest_merge`, `_manifest_progress` in `manifest-core.sh`.
2. Define the one-line `WPBUILD_FRAGMENT {json}` stdout envelope and document it
   inline (the orchestrator + Phase 2 contract consume it).
3. Ensure read helpers and the sub-command dispatcher are untouched.
4. `bash -n scripts/manifest-core.sh`; source it in both bash and zsh with the
   flag set and unset to confirm no `set -e` leakage and correct branch.
5. Smoke test: `WP_BUILD_RETURN_FRAGMENT=1` then call `wpbuild_set '.x' '1'` on a
   throwaway manifest copy → file unchanged, fragment printed; unset → file
   updated as before.

## Success Criteria

- [ ] With `WP_BUILD_RETURN_FRAGMENT=1`, the 3 writers do NOT modify the file and
      print a single `WPBUILD_FRAGMENT {json}` line each.
- [ ] With the flag unset, behavior is byte-identical to today.
- [ ] Read helpers unaffected; plugin pipeline unaffected.
- [ ] `bash -n` clean; sources cleanly in bash and zsh (no `set -e` leak).
- [ ] `claude plugin validate .` passes.

## Risk Assessment

- Risk: guard placed in a wrapper (`manifest-lib.sh`) instead of core → some
  write path bypasses it. Mitigation: put it in the core writers, the single
  choke point all wrappers call.
- Risk: fragment stdout pollutes normal sub-command output. Mitigation: only
  emitted under the explicit flag, which the orchestrator sets solely for
  spawned workers — never for its own writes.
- Risk: zsh `return` outside function / `set -e` leakage. Mitigation: guard sits
  inside the existing functions; reuse the file's established zsh-safe patterns;
  test sourced in both shells.
