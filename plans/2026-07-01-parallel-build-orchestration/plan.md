---
title: "Theme-Convert Fan-out (parallel theme authoring)"
description: ""
status: pending
priority: P2
branch: "main"
tags: []
blockedBy: []
blocks: []
created: "2026-06-30T18:26:43.701Z"
createdBy: "ck:plan"
source: skill
---

# Theme-Convert Fan-out (parallel theme authoring)

## Overview

Speed up `/wp-pro-max:build` by parallelizing the **one stage that actually
benefits and has a real agent vehicle**: theme `convert`. A foundation agent
writes shared singletons, then N `wp-theme-developer` agents author disjoint
templates concurrently, and the orchestrator merges their returned outputs.

This plan is the **narrowed, red-teamed** successor to an earlier
"parallelize the whole pipeline" idea. Adversarial review (3 reviewers, see
`## Red Team Review`) showed the broader Wave-A stage-parallelism had no
execution vehicle (skills run inline; no owning agents; Task subagents return
prose) and rested on a dependency graph derived from stage *names* rather than
each skill's actual `wpbuild_get` reads. Per the user's decision, **Wave-A
stage-parallelism and the i18n‖security overlap are dropped** — those stages
stay sequential exactly as they are today. Only theme `convert` parallelizes.

The enabling safety mechanism is a **mechanical manifest write-guard**: when the
orchestrator spawns concurrent theme agents it sets `WP_BUILD_RETURN_FRAGMENT=1`,
and `manifest-lib.sh` write helpers then refuse to mutate `wp-build.json` and
emit the fragment to stdout instead. Concurrency-safety stops being prose
discipline and becomes impossible to violate.

Brainstorm: `./brainstorm-parallel-build-orchestration.md`.

## Scope

In scope:
- Theme `convert` fan-out: foundation → barrier → N parallel template agents.
- Mechanical write-guard in the manifest libs (the only script change).
- Hard file-ownership + no-self-activation for template agents.
- Crash-safety (incremental persist, orphan cleanup, barrier-failure abort).
- N-derivation via a `analysis.pages` × `contentModel.postTypes` join.

Out of scope (dropped after red-team):
- Wave-A stage-parallelism (`optimize`/`model`/`tokens`/`plugins` stay serial).
- `i18n ‖ security` overlap (stay serial; i18n remains a DB-touching stage).
- Moving `env` to t0 / reordering `plugins`.
- `flock`, scaffold ACF-JSON fan-out.

## Acceptance criteria

- `claude plugin validate .` passes.
- `bash -n` clean on any changed shell script.
- Build stays resumable: `--from <stage>` works; `done` stages skip on re-run.
- Concurrent theme agents cannot write `wp-build.json` (guard refuses under
  `WP_BUILD_RETURN_FRAGMENT=1`); only the orchestrator writes it, sequentially.
- Template agents write only their assigned files; foundation owns all shared
  singletons incl. `functions.php` and block-pattern-category registrations.
- No template agent runs wp-env/WP-CLI; theme activates once, post-merge, no
  PHP fatals.
- A crash mid-fan-out leaves no orphan template that hijacks WP template
  resolution on resume.
- Canonical stage order in `commands/build.md` is unchanged (no silent reorder).

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Manifest write-guard](./phase-01-manifest-write-guard.md) | Pending |
| 2 | [Theme fan-out contract](./phase-02-theme-fan-out-contract.md) | Pending |
| 3 | [Theme-convert fan-out](./phase-03-theme-convert-fan-out.md) | Pending |
| 4 | [Validation](./phase-04-validation.md) | Pending |

## Dependencies

- Phase 1 (write-guard) is independent and should land first — Phase 3 relies on
  it to make the orchestrator-writes invariant mechanical.
- Phase 2 (contract doc) depends on Phase 1's flag name; Phase 3 links Phase 2.
- Phase 4 (validation) runs last.

No cross-plan blockers. Sibling plans in `./plans/` touch other stages/skills;
none change the manifest libs or the convert orchestration this plan edits.

## Red Team Review

### Session — 2026-07-01
**Reviewers:** 3 (Security Adversary, Failure Mode Analyst, Assumption Destroyer)
via `code-reviewer`, hostile lenses, codebase-evidence required.
**Findings:** 10 consolidated (from 24 raw), all evidence-filtered with
`file:line` citations, all **Accepted**. **Severity:** 4 Critical, 4 High, 2 Medium.

**Disposition outcome:** the user accepted every finding, then chose to **drop
Wave-A stage-parallelism** (resolving C2). That decision makes C2/C3/C4/H5/H6/M9
**moot by scope** — the unsafe reordering is simply not introduced; those stages
stay sequential as in today's pipeline. The remaining findings (C1, H7, H8 +
barrier-failure, M10) are applied in the phases below.

| # | Finding | Sev | Disposition | Resolution |
|---|---------|-----|-------------|------------|
| C1 | orchestrator-writes was unenforced prose (`manifest-core.sh:33` race still live) | Critical | Accept | Phase 1 — mechanical write-guard |
| C2 | no execution vehicle for Wave-A (skills run inline; no owning agents; Task returns prose) | Critical | Accept | Resolved by dropping Wave-A; theme fan-out uses real `wp-theme-developer` agent |
| C3 | `i18n` is DB-mutating + depends on seeded posts (`wp-i18n/SKILL.md:138,146`) | Critical | Accept | Moot by scope — i18n stays serial after seed chain (status quo) |
| C4 | `i18n‖security` overlap false — both mutate shared state (`wp-security/SKILL.md:62-66`, `wp-i18n:146`) | Critical | Accept | Moot by scope — overlap dropped |
| H5 | env@t0 + plugins-in-Wave-A → plugins never installed (`wp-env-bootstrap.sh`) | High | Accept | Moot by scope — env/plugins keep canonical order |
| H6 | hidden `optimize→tokens` dep (`design-tokens/SKILL.md:35`) + optimize set+merge | High | Accept | Moot by scope — optimize precedes tokens serially (status quo) |
| H7 | theme fan-out ownership unenforceable; `wp-theme-developer` self-activates + registers in `functions.php` (`agents/wp-theme-developer.md:36,78,85-86`); block-fse registers pattern categories in `functions.php` (`references/block-fse.md:263`) | High | Accept | Phase 3 — foundation owns `functions.php`+categories; template agents disjoint, no wp-cli; orchestrator validates returned files |
| H8 | post-wave persistence widens crash window → orphan templates (`manifest-core.sh:47-55`) | High | Accept | Phase 3 — persist each fragment on collection; not-done resume wipes theme dir + rebuilds (validation V2) |
| FMA8 | foundation→fanout barrier has no failure path | High* | Accept | Phase 3 — barrier verifies shared-file contract before fan-out; abort on partial |
| M10 | N-derivation underspecified — `analysis.pages[].role` has no CPT slug (`schemas/wp-build.schema.json:57` vs `:104-117`) | Medium | Accept | Phase 3 — derive N via pages×postTypes join; fan-out depends on merged `contentModel` |

\* FMA8 grouped under the H8 crash-safety theme during review.

## Validation Log

### Session — 2026-07-01
Verification pass skipped per the validate guard (`## Red Team Review` already
supplies `file:line` evidence). No `[UNVERIFIED]` tags in the plan. 4
decision-point questions asked; all confirmed.

| # | Decision point | Choice | Affects |
|---|----------------|--------|---------|
| V1 | Phase-1 write-guard necessity (agent `wp-theme-developer.md:72-75` already forbids manifest writes; orchestrator is single writer) | **Keep the mechanical guard** (defense-in-depth; honors C1; cheap regression protection) | Phase 1 (unchanged) |
| V2 | Crash-resume orphan-template strategy | **Wipe theme dir + rebuild** on a not-done `convert` resume (simple, fully safe even if bucketing changed between runs) | Phase 2, Phase 3 |
| V3 | block-fse pattern-category discovery | **Orchestrator pre-computes** the full category list from `analysis.components` + `contentModel` and passes it to the foundation agent | Phase 3, Phase 2 |
| V4 | Cross-bucket convention consistency | **`sharedContract` + strategy reference** in every spawn prompt (no separate normalization pass) | Phase 3 |

Note: V1 keeps the write-guard, but the plan now states honestly that in the
narrowed scope it is defense-in-depth — the agent contract + single-orchestrator
writer already prevent a manifest clobber; the guard makes that property
impossible to regress.

### Whole-Plan Consistency Sweep
Re-read `plan.md` + all 4 phase files after propagation. Reconciled the H8
crash-safety resolution (Red Team table + Phase 4 checklist) from the original
"clean owned files" wording to the validated **wipe-theme-dir + rebuild** (V2).
Propagated V3 (orchestrator pre-computes pattern categories) into Phase 2 §4 and
Phase 3 step 0, and V4 (`cssConventions` in `sharedContract`) into Phase 2 §6 and
Phase 3 steps 1/4. No remaining contradictions; the only surviving "surgical
per-agent cleanup" mentions are the deliberate "chosen over" rationale in
Phase 2/3. **Zero unresolved contradictions — eligible for implementation.**
