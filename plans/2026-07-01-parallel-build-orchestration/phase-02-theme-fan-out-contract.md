---
phase: 2
title: "Theme fan-out contract"
status: pending
effort: ""
priority: P1
dependencies: [1]
---

# Phase 2: Theme fan-out contract

## Overview

Author `references/parallel-execution.md` — the single authoritative contract for
**theme `convert` fan-out** (only). `theme-conversion/SKILL.md` (Phase 3) and the
`convert` note in `commands/build.md` link it instead of restating rules. Scoped
to one concern: how to author a theme with N concurrent agents safely. No Wave-A,
no pipeline-wide waves (those were dropped after red-team).

## Requirements

- Functional: define the orchestrator-writes invariant (backed by the Phase-1
  flag), the file-ownership rule, the foundation→barrier→fan-out sequence, the
  N-derivation join, the agent return envelope, and crash-safety rules.
- Non-functional: concise (~110-140 lines), imperative, matches
  `references/manifest-contract.md` voice. References real symbols/paths.

## Architecture

Sections of `references/parallel-execution.md`:

1. **Purpose & scope.** Parallelizes theme `convert` authoring only. Explicitly
   states the rest of the pipeline runs sequentially (link `manifest-contract.md`
   for stage order). One line on why broader parallelism was dropped (no agent
   vehicle / unverified deps — see plan red-team log).
2. **Orchestrator-writes invariant.** The skill running `convert` is the sole
   writer of `wp-build.json`. It spawns every theme agent with
   `WP_BUILD_RETURN_FRAGMENT=1` (Phase 1), so agents physically cannot write the
   manifest. Agents return their results in-band; the orchestrator applies them.
3. **File-ownership rule.** Two concurrent agents never write the same file.
   Foundation owns all shared singletons; each template agent gets an explicit,
   disjoint writable file list; the orchestrator rejects any returned file
   outside that agent's assigned set.
4. **Foundation → barrier → fan-out.**
   - Pattern categories (validation V3): the **orchestrator pre-computes** the
     full block-pattern category list from `analysis.components` + `contentModel`
     and passes it to the foundation agent, which registers them; template agents
     reuse only those (never register new ones).
   - Foundation agent (1) writes shared singletons and returns the shared-file
     contract (paths + referenceable slots + the registered block-pattern
     categories).
   - Barrier: orchestrator verifies every promised shared file exists and is
     non-empty before fan-out; on partial/failed foundation, abort the wave and
     leave `convert` not-done (no template agents spawned).
   - Template agents (N, parallel): disjoint templates/patterns; read foundation
     READ-ONLY; forbidden to edit `functions.php`/shared parts; forbidden to run
     any `wp-env`/WP-CLI command (no activation).
5. **N-derivation (join).** N comes from joining `analysis.pages[]` (role) with
   `contentModel.postTypes[].slug` to bucket archive/single pages per CPT.
   Therefore the fan-out depends on a **merged `contentModel`** (the `model`
   stage must be done first — it already runs before `convert` in canonical
   order). Bucket heuristic + hard-cap 4 + single-agent fallback (defined in
   Phase 3; summarized here).
6. **Agent return envelope.** Each agent returns a fenced block the orchestrator
   parses: `{ "files": ["…"], "templateMap": { "src": "tmpl" } }` for template
   agents; the foundation returns `{ "files": […], "sharedContract": {…} }`.
   Orchestrator validates `files` ⊆ assigned set, asserts no `templateMap` key
   collisions across buckets, then writes once.
7. **Crash-safety (validation V2).** Orchestrator persists results as soon as each
   agent returns (still serial in the orchestrator) rather than one post-fan-out
   batch. On a resume of a **not-done** `convert`, the orchestrator **wipes the
   theme directory and rebuilds from scratch** (foundation, then fan-out) — chosen
   over surgical per-agent cleanup because it is fully safe even if N/bucketing
   changed between runs (e.g. `contentModel` was edited). A `done` `convert` is
   never wiped (resume skips it).
8. **Out of scope.** Wave-A stage-parallelism, `i18n‖security` overlap, `flock`,
   scaffold ACF-JSON fan-out — list so future readers don't re-add them.

## Related Code Files

- Create: `references/parallel-execution.md`
- Reference only: `references/manifest-contract.md`, `scripts/manifest-core.sh`
  (Phase-1 flag), `skills/theme-conversion/SKILL.md`,
  `agents/wp-theme-developer.md`, `schemas/wp-build.schema.json`

## Implementation Steps

1. Write `references/parallel-execution.md` with sections 1-8 above.
2. Name the Phase-1 flag (`WP_BUILD_RETURN_FRAGMENT`) and the
   `WPBUILD_FRAGMENT`/return-envelope shapes exactly as Phase 1/3 use them.
3. Keep the bucket heuristic summary in sync with Phase 3 (Phase 3 is canonical;
   link it rather than duplicating the full table).
4. Keep it lean; push procedure into the skill, keep rules here.

## Success Criteria

- [ ] `references/parallel-execution.md` exists; covers invariant, ownership,
      foundation/barrier/fan-out, N-join, return envelope, crash-safety, scope.
- [ ] References the Phase-1 flag by its exact name.
- [ ] States the fan-out depends on merged `contentModel` (N-join).
- [ ] Barrier failure path present; resume rule = wipe theme dir + rebuild on
      not-done `convert` (V2).
- [ ] Pattern categories pre-computed by orchestrator and passed to foundation (V3).
- [ ] OUT-of-scope list present (no Wave-A creep).
- [ ] `claude plugin validate .` passes (new reference is inert).

## Risk Assessment

- Risk: contract drifts from Phase 3 wording → Phase 3 is canonical for the
  procedure; this file links it for specifics and owns only the rules.
- Risk: doc reintroduces dropped scope → explicit OUT-of-scope section.
