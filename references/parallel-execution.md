# Parallel Execution — Theme `convert` Fan-out

The authoritative contract for authoring a WordPress theme with **N concurrent
agents** during the `convert` stage. The `theme-conversion` skill and the
`convert` note in `commands/build.md` link here instead of restating these rules.

## 1. Purpose & scope

This parallelizes **theme `convert` authoring only** — the one stage with a real
agent vehicle (`wp-theme-developer`) and disjoint, file-level work units. Every
other stage in the pipeline runs **sequentially** in canonical order; see
`references/manifest-contract.md` for stage ids and ordering.

Broader pipeline-wide parallelism was deliberately **dropped** after an
adversarial review: stage skills run inline (no owning agents to spawn
concurrently), and a stage-name dependency graph did not match each skill's
actual manifest reads. Do not reintroduce it (see §8).

## 2. Orchestrator-writes invariant

The skill running `convert` is the **sole writer** of `wp-build.json`. It spawns
every theme agent (foundation and template) with the environment variable
`WP_BUILD_RETURN_FRAGMENT=1`. Under that flag the manifest write helpers in
`scripts/manifest-core.sh` (`_manifest_set`, `_manifest_merge`,
`_manifest_progress`) refuse to mutate the file and instead print a single
`WPBUILD_FRAGMENT {json}` line per intended write. Agents therefore **physically
cannot** clobber the manifest. They return their results in-band (§6); the
orchestrator applies them itself, with the flag unset, one agent at a time.

In this narrowed scope the guard is **defense-in-depth**: the `wp-theme-developer`
contract already forbids manifest writes and the orchestrator is the single
writer, so the guard turns "don't clobber the manifest" from prose discipline
into an invariant that cannot regress — it is insurance, not the sole barrier.

## 3. File-ownership rule

Two concurrent agents never write the same file. **Foundation owns all shared
singletons** (see §4); each template agent receives an **explicit, disjoint
writable file list**. The orchestrator **rejects** any returned path outside that
agent's assigned set and fails the stage — out-of-set writes are a contract
violation, not a warning.

## 4. Foundation → barrier → fan-out

**Pattern categories (pre-computed).** Before spawning the foundation agent, the
orchestrator computes the **full** block-pattern category list from
`analysis.components` + `contentModel` and passes it into the foundation prompt.
The foundation registers exactly those categories; template agents may reference
only those and **never register new ones** (route additions back to the
orchestrator or defer to `scaffold`).

**Foundation agent (1, blocking).** One `wp-theme-developer` writes the strategy's
shared singletons and **all** `functions.php` content needed at convert time,
including the pre-computed pattern-category registrations. It runs **no**
`wp-env`/WP-CLI command (no activation). It returns
`{ files[], sharedContract: { paths, slots, patternCategories[], cssConventions } }`.

**Barrier (orchestrator).** Verify every path in `sharedContract` exists and is
non-empty before fan-out. If the foundation failed or returned a partial
contract → **abort**: spawn no template agents, leave `convert` not-done, and
surface the error. Never fan out onto a poisoned foundation.

**Template agents (N, parallel).** Each gets a disjoint writable file list, reads
foundation files **READ-ONLY**, must not edit `functions.php`/`style.css`/
`theme.json`/shared parts, must not register new pattern categories, and runs
**no** `wp-env`/WP-CLI command — author files and return paths only. Spawn them
in a single message so they run concurrently.

## 5. N-derivation (join)

N comes from joining `analysis.pages[]` (`role`) with
`contentModel.postTypes[].slug` — CPT identity lives in the content model, not in
`analysis.pages[].role`. The fan-out therefore depends on a **merged
`contentModel`**: the `model` stage must be done first (it precedes `convert` in
canonical order; assert `contentModel.postTypes` present, else error).

Bucket by role with a **hard cap of 4** (canonical table + fallback live in
`skills/theme-conversion/SKILL.md` — link it, do not duplicate). Collapse empty
buckets; if ≤1 non-empty bucket remains, spawn a **single** template agent (no
fan-out overhead).

## 6. Agent return envelope

Each agent returns a fenced block the orchestrator parses:

- Foundation: `{ "files": [...], "sharedContract": { ... } }`
- Template: `{ "files": [...], "templateMap": { "src": "tmpl" } }`

The orchestrator validates `files ⊆ assignedSet` for every agent, asserts no
`templateMap` key collisions across buckets, then writes once via the normal
`wpbuild_set` path (its own process, flag **unset**): concatenate `theme.files`,
merge `templateMap`, set `.theme.path` / `.theme.files` / `.theme.templateMap`.

## 7. Crash-safety

The orchestrator **persists each agent's result as it returns** (still serial in
the orchestrator), not as one post-fan-out batch — this narrows the crash window.

On a resume of a **not-done** `convert`, the orchestrator **wipes the theme
directory and rebuilds from scratch** (foundation, then fan-out). This is chosen
over surgical per-agent cleanup because it is fully safe even if N or bucketing
changed between runs (e.g. `contentModel` was edited) — no orphan `.php`/template
can survive to hijack WordPress template resolution. A **`done`** `convert` is
skipped by the resume guard and never wiped.

## 8. Out of scope (do not re-add)

- Wave-A stage-parallelism (`optimize`/`model`/`tokens`/`plugins` stay serial).
- `i18n ‖ security` overlap (both mutate shared DB/theme state; stay serial).
- Moving `env` to t0 or reordering `plugins`.
- `flock`-based manifest locking; `scaffold` ACF-JSON fan-out.
