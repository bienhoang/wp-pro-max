---
phase: 3
title: "Theme-convert fan-out"
status: pending
effort: ""
priority: P1
dependencies: [1, 2]
---

# Phase 3: Theme-convert fan-out

## Overview

Rewrite step 6 of `skills/theme-conversion/SKILL.md` from "spawn one
`wp-theme-developer`" into foundation→barrier→fan-out, with hard file-ownership,
no agent self-activation, a CPT-aware N-derivation, and crash-safety. Add a
one-line note to `commands/build.md` that `convert` is internally parallel
(canonical stage order otherwise unchanged). This is the actual speedup.

Applies red-team **H7** (ownership + self-activation), **H8** + barrier-failure
(crash-safety), and **M10** (N-derivation join). Uses Phase-1 guard + Phase-2
contract.

## Requirements

- Functional: foundation barrier → N parallel template agents (disjoint files,
  READ-ONLY foundation, no WP-CLI) → orchestrator validates + merges → single
  activation post-merge. Works across `classic-acf`, `block-fse`, `page-builder`.
- Non-functional: `SKILL.md` ≤ ~200 lines; heavy template content stays in the
  strategy references; link `references/parallel-execution.md` for rules.

## Architecture

Current `theme-conversion/SKILL.md`: step 6 spawns one `wp-theme-developer`;
step 7 writes `theme.path/files/templateMap`; step 8 activates + fatal-checks.
The Notes already keep `functions.php` minimal. Problems found by red-team:
`wp-theme-developer` self-activates (`agents/wp-theme-developer.md:85-86`) and is
told to register in `functions.php`/`inc/` (`:36,:78`); block-fse registers
**pattern categories in `functions.php` during convert**
(`skills/theme-conversion/references/block-fse.md:263`); `analysis.pages[].role`
has no CPT slug (`schemas/wp-build.schema.json:57`) — CPT identity is in
`contentModel.postTypes[].slug` (`:104-117`).

New step 6 — **foundation → barrier → fan-out**:

0. **Pre-compute pattern categories (orchestrator, validation V3).** Before
   spawning foundation, derive the full block-pattern category list from
   `analysis.components` + `contentModel` and pass it into the foundation prompt.
   Foundation registers exactly these; template agents may use only these.

1. **Foundation agent (1, blocking).** Spawn one `wp-theme-developer` (with
   `WP_BUILD_RETURN_FRAGMENT=1`) to write shared singletons for the strategy and
   **all** `functions.php` content needed at convert time, including the
   orchestrator-supplied block-pattern **category registrations**:
   - classic-acf / page-builder: `style.css` (`:root{ --… }` token block),
     minimal `functions.php` (text domain, enqueues stub, pattern categories),
     `header.php`, `footer.php`, shared parts.
   - block-fse: `theme.json` (tokens), `templates/parts/header.html`,
     `templates/parts/footer.html`, minimal `functions.php` with
     `register_block_pattern_category(...)` for every category templates will use.
   Constraint: **do NOT run any wp-env/WP-CLI command** (no activation). Returns
   `{ files[], sharedContract: { paths, slots, patternCategories[], cssConventions } }`
   — `cssConventions` (class-naming pattern, escaping/i18n style, partial-include
   convention) is passed to every template bucket for consistency (V4).
2. **Barrier (orchestrator).** Verify every path in the returned `sharedContract`
   exists and is non-empty. If foundation failed or is partial → **abort**: do
   not spawn template agents, leave `convert` not-done, surface the error. (No
   poisoned fan-out — red-team FMA8.)
3. **Derive N (join) + bucket.** Join `analysis.pages[]` (role) with
   `contentModel.postTypes[].slug` to assign archive/single pages to their CPT.
   Requires `model` done (it precedes `convert` in canonical order). Bucket by
   role, **hard-cap 4**:
   - bucket 1: `home` + `landing`
   - bucket 2: static `page` templates
   - bucket 3: `archive-{cpt}` + `single-{cpt}` (grouped by the joined CPT slug)
   - bucket 4: `post`/blog templates (only if distinct from CPT singles)
   Collapse empties; if ≤1 non-empty bucket → single template agent (no fan-out
   overhead).
4. **Template agents (N, parallel, single message).** Spawn each `wp-theme-developer`
   with `WP_BUILD_RETURN_FRAGMENT=1` and a prompt that includes: theme path,
   manifest path, chosen reference path, its bucket's pages/components, the token
   set, the foundation `sharedContract`, **its exact writable file list**, and
   these hard constraints:
   - Author ONLY files in your writable list; create no others.
   - Read foundation files READ-ONLY; never edit `functions.php`, `style.css`,
     `theme.json`, or shared parts.
   - Use ONLY pattern categories declared in `sharedContract.patternCategories`;
     do not register new categories (route additions back to the orchestrator).
   - **Run NO `wp-env`/WP-CLI command. Do not activate the theme. Author files
     and return paths only.** (Overrides the agent's default self-activation
     step — red-team H7/AD4.)
   - **Consistency (validation V4):** follow the `sharedContract` (slots, shared
     parts, CSS class conventions) and the chosen strategy reference for naming,
     escaping, i18n, and partial usage — these two inputs (passed to every
     bucket) keep independently-authored templates stylistically uniform. No
     separate post-merge normalization pass.
   Each returns `{ files[], templateMap }` for its bucket.
5. **Validate + merge (orchestrator).** For each returned agent: assert
   `files ⊆ assignedSet` (reject + fail the stage on out-of-set writes); assert
   no `templateMap` key collisions across buckets. Persist incrementally as each
   agent returns (orchestrator writes via normal `wpbuild_set`, flag NOT set for
   the orchestrator's own process). Concatenate `theme.files`; merge
   `templateMap`; set `.theme.path/.files/.templateMap`.
6. **Activate once (orchestrator).** After merge, the orchestrator (not any
   agent) runs `wp-env run cli wp theme activate <slug>` + fatal check a single
   time. (Existing step 8, made explicitly orchestrator-only.)

Crash-safety (red-team H8; validation V2): on resume of a **not-done** `convert`,
the orchestrator **wipes the theme directory and rebuilds from scratch**
(foundation → fan-out) before re-authoring. Chosen over surgical per-agent
cleanup because it is safe even if N/bucketing changed between runs (e.g.
`contentModel` edited) — no orphan `.php`/template can survive to hijack WP
template resolution. A `done` `convert` is skipped by the resume guard and never
wiped.

`build.md` change: one line in the `convert` description — "`convert` authors the
theme with a foundation agent then parallel template agents; see
`references/parallel-execution.md`." Canonical stage order, gates, `--from/--to`
unchanged.

## Related Code Files

- Modify: `skills/theme-conversion/SKILL.md` (step 6 rewrite; steps 7-8 reflect
  merge-then-activate-once), `commands/build.md` (one-line convert note)
- Reference only: `agents/wp-theme-developer.md`,
  `skills/theme-conversion/references/{classic-acf,block-fse,page-builder}.md`,
  `references/parallel-execution.md` (Phase 2), `schemas/wp-build.schema.json`

## Implementation Steps

1. Replace step 6 with foundation→barrier→fan-out; link `parallel-execution.md`.
2. Add the join-based N-derivation + bucket table + cap-4 + single-agent fallback.
3. Specify per-strategy foundation file sets incl. pattern-category registration
   in `functions.php`/`theme.json`.
4. Write the template-agent spawn constraints verbatim (no-WP-CLI, no-activate,
   disjoint files, READ-ONLY foundation, no new categories), each spawned with
   `WP_BUILD_RETURN_FRAGMENT=1`.
5. Update steps 7-8: orchestrator validates `files ⊆ assignedSet`, asserts no
   `templateMap` collisions, persists incrementally, activates once post-merge.
6. Add the resume rule: not-done `convert` wipes the theme dir and rebuilds (V2).
7. Add the one-line `convert` note to `commands/build.md`.
8. Re-read; confirm ≤ ~200 lines and template bodies still live in references.

## Success Criteria

- [ ] Step 6 = foundation agent → barrier (verify shared contract, abort on
      partial) → N parallel template agents.
- [ ] Template agents: disjoint writable list, READ-ONLY foundation, no
      `functions.php` edits, no new pattern categories, **no WP-CLI/activation**,
      spawned with `WP_BUILD_RETURN_FRAGMENT=1`.
- [ ] Foundation owns `functions.php` incl. all pattern-category registrations,
      for all three strategies.
- [ ] N derived via `analysis.pages × contentModel.postTypes` join; cap 4;
      single-agent fallback.
- [ ] Orchestrator validates `files ⊆ assignedSet`, asserts no `templateMap`
      collisions, persists incrementally, activates once post-merge.
- [ ] Resume rule present: not-done `convert` wipes theme dir + rebuilds (V2);
      `done` is skipped. Pattern categories pre-computed by orchestrator (V3).
- [ ] `commands/build.md` notes convert is internally parallel; canonical order
      unchanged.
- [ ] `claude plugin validate .` passes.

## Risk Assessment

- Risk: agent ignores no-WP-CLI constraint and self-activates → constraint stated
  explicitly + orchestrator is sole activator; if an agent activates anyway, the
  single post-merge activation still corrects final state (idempotent activate).
- Risk: out-of-set file write slips through → orchestrator validates returned
  `files ⊆ assignedSet` and fails the stage, surfacing the violation.
- Risk: new pattern category needed mid-fan-out → forbidden in template agents;
  must be declared by foundation up front or deferred to `scaffold`.
- Risk: over-split tiny site → single-agent fallback when ≤1 non-empty bucket.
- Risk: `model` not done before `convert` (N-join needs it) → canonical order has
  `model` before `convert`; assert `contentModel.postTypes` present, else error.
