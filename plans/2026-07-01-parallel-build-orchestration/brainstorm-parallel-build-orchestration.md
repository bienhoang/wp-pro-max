# Brainstorm — Parallel Build Orchestration + Theme-Convert Fan-out

> **⚠️ Superseded in part by red-team (2026-07-01).** This report records the
> brainstorm-stage design, which proposed Wave-A stage-parallelism +
> `i18n‖security` overlap. Adversarial review of the planned implementation
> found those had no execution vehicle and rested on an unverified dependency
> graph. The **final, narrowed plan drops them** and keeps only the theme
> `convert` fan-out + a mechanical write-guard. See `plan.md` (`## Red Team
> Review`) for the authoritative scope. Sections below are kept as the
> historical brainstorm record.

- **Date:** 2026-07-01
- **Topic:** Pipeline stages run sequentially; parallelize safe stages + split slow `convert` across multiple `wp-theme-developer` agents.
- **Mode:** brainstorm (no flags)
- **Decisions:** Scope = safe wins only · Manifest = orchestrator-writes · Theme split = foundation-then-fanout

## Problem statement

`/wp-pro-max:build` runs 16 stages strictly linearly (`commands/build.md`). The
`convert` stage delegates ALL theme authoring to a single `wp-theme-developer`
agent — the slowest stage. Goal: cut wall-clock by running independent stages
concurrently and by splitting `convert` scope across multiple theme agents,
without breaking resumability/idempotency.

## Scout findings (constraints discovered)

- 16-stage linear pipeline; every stage reads/writes shared `wp-build.json`.
- Manifest writer is non-atomic read-modify-write (`manifest-core.sh:33`,
  `jq … > tmp && mv tmp file`) → concurrent writers clobber. **#1 blocker.**
- One shared wp-env DB; seeding idempotency is check-before-create
  (`seed-helpers.sh`) → TOCTOU-unsafe under concurrency.
- `theme-conversion/SKILL.md` step 6 = one agent authors every template/part/pattern.
- `convert` already keeps `functions.php` minimal; registrations live in `scaffold`.

## Dependency graph (what can parallelize)

```
env ──────────────(runs t0, hidden under analyze)
analyze ─┬─ optimize ┐
         ├─ model ───┤
         ├─ tokens ──┤→ convert → scaffold ─┬─ seed-content → seed-plugin-data → seo ┐
         └─ plugins ─┘  (split N agents)    ├─ i18n (theme files) ──────────────────┤→ qa → ship → handoff
                                            └─ security (wp-config) ────────────────┘
```

- **Safe parallel:** Wave A fan-out (optimize/model/tokens/plugins); convert split; i18n‖security.
- **Keep serial:** seed-content → seed-plugin-data → seo (one DB, TOCTOU-unsafe). qa→ship→handoff.

## Evaluated approaches

### Axis A — manifest write-safety
- **A1 Orchestrator-writes (CHOSEN):** parallel workers return fragments; orchestrator writes sequentially. Zero script change, matches existing contract.
- A2 `flock` in manifest-core.sh — real concurrency, but flock portability (zsh/macOS) cost.
- A3 staging files + merge — more moving parts.

### Axis B — theme convert split
- **B1 Foundation-then-fanout (CHOSEN):** 1 agent writes shared singletons → barrier → N agents own disjoint templates/patterns. Clean ownership.
- B2 by-page — `functions.php`/header/footer contention.
- B3 by-component — awkward page assembly.

### Axis C — scope
- **Safe wins only (CHOSEN).** Aggressive (DB stages) and convert-only rejected.

## Recommended solution

### 1. Orchestrator-writes invariant
Parallel workers never call `wpbuild_set`/`wpbuild_progress`; they return a
manifest fragment. Orchestrator applies fragments sequentially, then records
per-stage progress. Skills keep standalone self-write behavior; switch to
return-fragment mode only inside a wave.

### 2. Three waves (replaces linear list)
- **Wave A:** spawn optimize/model/tokens/plugins in ONE message; env from t0;
  orchestrator writes 4 fragments + progress sequentially.
- **Wave B:** convert (split, §3) → scaffold (single agent; edits shared functions.php).
- **Wave C:** serial DB chain seed-content→seed-plugin-data→seo; i18n‖security
  overlap (different surfaces, no DB writes); qa→ship→handoff serial.

### 3. Theme convert = foundation-then-fanout
- **Foundation (1 agent, barrier):** theme.json/style.css `:root` vars,
  minimal functions.php skeleton, header.php/footer.php/shared parts. Returns the
  shared-file contract.
- **Templates (N agents, parallel):** each owns a DISJOINT set (front-page,
  page-{slug}, archive-{cpt}, single-{cpt}, that page's patterns). Reads
  foundation READ-ONLY; never edits functions.php. Returns `{files[], templateMap slice}`.
- **N:** derive from role-groups (static pages / CPT archives+singles / home+landing),
  hard-cap 4.
- **Merge:** orchestrator concats `theme.files`, merges `templateMap`, single
  `wpbuild_set`; activate + fatal-check once after merge.

### 4. Touchpoints (all markdown)
- `commands/build.md` — linear list → 3-wave protocol + orchestrator-writes rule.
- `skills/theme-conversion/SKILL.md` — rewrite step 6 (foundation→barrier→fanout).
- **NEW** `references/parallel-execution.md` — dependency graph, wave defs,
  fragment-return contract, file-ownership rules (single source, linked by both).
- One-line return-fragment-mode note in html-optimization, content-modeling,
  design-tokens, plugin-selection skills.

## Risks

- Orchestration complexity in build.md ↑. Mitigate: push detail into
  `references/parallel-execution.md`; keep build.md a thin coordinator.
- Resume/idempotency: record per-stage progress AFTER fragment write so `--from`
  resume still works (per-stage granularity unchanged).
- Theme fan-out collision: enforce disjoint file ownership + READ-ONLY foundation;
  functions.php untouched by template agents (registrations are scaffold's job).
- i18n‖security marginal win; drop if it complicates the orchestrator.

## Success metrics / validation

- Wall-clock: Wave A collapses 4 stages → ~1; convert ~N× faster on multi-template sites.
- `claude plugin validate .` passes.
- A full build still resumable: `--from <stage>` works; re-run skips `done` stages.
- No clobbered `wp-build.json` across a parallel run; final manifest has all
  fragments (optimization, contentModel, designTokens, plugins, theme.files/templateMap).
- Theme activates with no PHP fatals after fan-out merge.

## Next steps

- Hand off to `/ck:plan` (default mode) with this report.
- Plan phases: (1) parallel-execution.md contract; (2) build.md wave protocol +
  orchestrator-writes; (3) theme-conversion foundation-then-fanout; (4) fan-out
  skill return-mode notes; (5) validation pass.

## Unresolved questions

- Theme split N: confirmed derive-by-role-group + cap 4 (not fixed N). Revisit if
  most target sites are single-template (then split yields little).
