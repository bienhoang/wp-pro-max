---
phase: 5
title: "Validation + docs reconcile"
status: pending
effort: "S"
---

# Phase 5: Validation + docs reconcile

## Overview

Prove the speed win, make the gate authoritative in docs, and fix the two
doc-drift items the review surfaced. Closes the plan.

## Requirements

- Functional: a documented before/after of WP-CLI latency; one canonical "all
  WP-CLI via `wpx`" rule in the contract; corrected seeding delegation prose.
- Non-functional: no new runtime behavior — docs + a measurement note only.

## Architecture

Speed validation is behavioral, not a unit test (it needs a live wp-env). Record
a manual measurement in the plan's `reports/`: time N `wp option get siteurl`
calls via old `wp-env run cli` vs `wpx` (`docker exec`) and note the per-call
delta (expected ~3.7s → ~0.1s). This is acceptance evidence, not a CI gate.

Docs reconcile (all four files that carry `wp-env run cli` prose — Red Team #2):
- `references/manifest-contract.md` "wp-env / WP-CLI invocation" section → state
  the canonical rule honestly: *skill/agent prose uses `scripts/wpx.sh` for `wp`
  subcommands* (fast default; falls back to `wp-env run cli`); scripts keep their
  own runners; non-`wp` commands and the allowlist are the exceptions. Make clear
  this is an **authoring convention enforced at instruction level by the lint**,
  not a runtime interception (Red Team #8).
- `docs/tech-stack.md` (`:8`) + any `README.md`/`docs/system-architecture.md`
  lines showing `wp-env run cli` as THE way → update to `wpx` (or mark
  explanatory), so docs and lint agree.
- `README.md` + `docs/system-architecture.md` seeding rows → correct to: the
  `wp-data-engineer` agent **authors the JSON payload**; the **skill runs the
  batch inline** (agent death cannot lose a run). Aligns docs with the shipped
  fast-seeder reality.

## Related Code Files

- Create: `plans/2026-07-01-wpcli-runner-and-test-harness/reports/wpcli-latency-measurement.md`
- Modify: `references/manifest-contract.md`, `docs/tech-stack.md`, `README.md`,
  `docs/system-architecture.md`
- Reference: `scripts/wpx.sh`, `test/run.sh`

## Implementation Steps

1. On a live wp-env, time `for i in $(seq 1 10)` of `option get siteurl` via both
   paths; capture totals + per-call mean into the report.
2. Update `manifest-contract.md` invocation section to the `wpx` canonical rule
   (honest instruction-level framing); link the allowlist concept.
3. Update `docs/tech-stack.md:8` and reconcile the seeding delegation prose in
   `README.md` + `docs/system-architecture.md` (payload-agent / inline-skill).
4. Run `test/run.sh` one final time; confirm green (validate + contract-lint +
   validate-port + syntax + seeder) at the whole-repo scope.
5. `ck plan check` phases as complete; mark plan done.

## Success Criteria

- [ ] `reports/wpcli-latency-measurement.md` shows measured old vs new per-call
      time (or records the exact command + "pending live wp-env" — never fabricated).
- [ ] `manifest-contract.md` names `wpx` as the canonical prose entry for `wp`
      subcommands (honest instruction-level framing; scripts/allowlist noted as
      exceptions); no contradictory "use `wp-env run cli`" instruction remains
      outside the allowlist.
- [ ] `docs/tech-stack.md` updated; README/architecture seeding prose matches
      inline-skill / payload-agent reality.
- [ ] `test/run.sh` green; `claude plugin validate .` passes (or SKIPs cleanly).

## Risk Assessment

- *No live wp-env available at validation time* → record the measurement as
  pending with the exact command to run; do not fabricate numbers. The
  functional wins (fewer container boots) are already proven structurally.
- *Doc edits reintroduce raw command examples* → Phase-4 lint covers prose, so a
  stray `wp-env run cli` in docs is caught unless allowlisted.
