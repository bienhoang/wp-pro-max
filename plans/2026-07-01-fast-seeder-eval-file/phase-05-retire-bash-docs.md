---
phase: 5
title: "Retire Bash + Docs"
status: done
priority: P2
dependencies: [3, 4]
---

# Phase 5: Retire Bash + Docs

## Overview

Both seed stages now run on the PHP batch engine, so the bash engine is dead
weight. Remove `scripts/seed-helpers.sh`, finalize the `wp-data-engineer` agent
role, and update the docs/CLAUDE references that still describe the old flow.
Final validation gate.

## Requirements

- Functional: `scripts/seed-helpers.sh` removed; zero references remain in
  skills, agents, scripts, references, docs, **or pending plans**.
- Functional (red-team H5): the WooCommerce plan
  (`plans/2026-06-26-woocommerce-catalog-build-extension/phase-06-seeding.md`)
  extends `seed-helpers.sh`. It is marked `blockedBy` this plan. **Do not delete
  the bash helpers until** that plan has rebased its seeding onto the JSON batch
  engine, or a deliberate decision is recorded to keep a shim. The reference scan
  in this phase must cover pending plans, not just ship runbooks.
- Functional: `wp-data-engineer` agent description + body reflect the
  author-payload / orchestrator-execute split.
- Non-functional: `claude plugin validate .` passes; full behavioral seed (both
  stages) against a live wp-env sample passes with zero-dup re-run.

## Architecture

Grep-driven cleanup: every `seed-helpers.sh`, `ensure_page`/`ensure_post`/
`ensure_acf_value` mention is either deleted or repointed at the batch helpers.
`references/manifest-contract.md` seed-stage rows updated to describe the
single-batch + summary-merge contract and the new `seed.lastSummary` field.

## Related Code Files

- Delete: `scripts/seed-helpers.sh`
- Modify: `CLAUDE.md` (Scripts section: `seed-helpers.sh` → `seed-batch-runtime.php`
  + `seed-batch-run.sh` + `wp-cli-runner.sh`)
- Modify: `README.md` (components list), `references/manifest-contract.md`
  (seed-content / seed-plugin-data rows, `seed.*` fields)
- Modify: `agents/wp-data-engineer.md` (final role wording)
- Verify: any remaining `grep -rn seed-helpers` hits across the repo

## Implementation Steps

1. `grep -rn 'seed-helpers' .` (including `plans/`) → enumerate every reference;
   repoint or remove. Confirm the WooCommerce plan's seeding has rebased (or a
   shim decision is recorded) before proceeding — it is the one `blockedBy` consumer.
2. Delete `scripts/seed-helpers.sh`.
3. Update `CLAUDE.md`, `README.md`, `references/manifest-contract.md`,
   `agents/wp-data-engineer.md`.
4. Run full test suite (`test/seeder/run.sh`) + `claude plugin validate .`.
5. End-to-end live seed of a real sample build (both stages) → verify counts,
   re-run zero-dup, site renders.

## Success Criteria

- [ ] `grep -rn 'seed-helpers' .` returns nothing (outside this plan's history).
- [ ] `claude plugin validate .` passes; `test/seeder/run.sh` all green.
- [ ] Live end-to-end seed (content + plugin-data) passes; re-run 0 dup.
- [ ] CLAUDE.md / README / manifest-contract describe the batch engine accurately.

## Risk Assessment

- A skill / runbook / **pending plan** references `seed-helpers.sh` outside the
  obvious paths → the repo-wide grep (incl. `plans/`) in step 1 is the backstop;
  do not delete before grep is clean AND the WooCommerce consumer has rebased.
- Removing the bash engine while a downstream consumer still expects it → ship
  uses `migrate-urls.sh` (out-of-scope), but the WooCommerce plan's `phase-06`
  does use it (red-team H5) — that is the gating dependency, not ship.
