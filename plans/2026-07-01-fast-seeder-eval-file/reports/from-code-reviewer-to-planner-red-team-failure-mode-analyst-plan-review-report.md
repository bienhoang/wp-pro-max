# Red-Team Plan Review — Fast Seeder (single `wp eval-file` batch)

**Reviewer role:** Failure Mode Analyst / Flow Tracer (hostile)
**Plan:** `plans/2026-07-01-fast-seeder-eval-file/`
**Verdict:** Plan has the right shape but glosses over several failure modes that
break its two headline guarantees — *zero-dup idempotency* and *survives mid-run
death*. Three Critical issues block the success criteria as written.

Flow traced end-to-end: skill authors `$SEED_PAYLOAD` → orchestrator concats
`seed-batch-runtime.php` + payload → pipes to `wp eval-file -` (one container) →
PHP runs in-process idempotent helpers → `echo json_encode(summary)` on stdout →
bash captures stdout → `jq` merges `seed.idempotencyKeys`/`lastRun`/`lastSummary`
into `wp-build.json`. The breaks are at the stdin boundary, the single end-of-run
JSON emit, the jq merge semantics, and the test that supposedly locks all this.

---

## Finding 1: The behavioral harness cannot exercise idempotency — phantom regression test
**Severity:** Critical
**Location:** phase-01 §Architecture / Implementation Steps 3 (lines 38-49, 60-66); phase-02 step 1 & Success Criteria (lines 63-66, 79)

**Flaw:** The stub is defined as a fake `wp` on `PATH` that returns canned
responses *keyed by subcommand* — phase-01:41-42 literally scripts
`post create --porcelain → incrementing int` and `post list → empty first run,
created slug second run`. But the new architecture issues **exactly one**
subcommand: `wp eval-file -`. There are no `post create` / `post list` calls for
the stub to intercept — all idempotency logic (`get_posts(name)`,
`term_exists`, menu-item title walk) executes *inside the PHP that the stub never
runs*. The stub can only canned-return the whole JSON summary for the single
`eval-file` call. So `seed-batch.test.sh` asserting "second run reports
`created:0`" (phase-01:48) tests that the stub returns the string the test author
hardcoded — it proves nothing about `seed-batch-runtime.php`'s real dedupe.

**Failure scenario:** A future edit changes `get_posts` to omit
`post_status=any`. Drafts/private pages stop matching → re-run creates duplicates
in production. `seed-batch.test.sh` stays green (stub still returns `created:0`).
The plan's "idempotency is the regression contract carried over from
seed-helpers.sh" (plan.md:36-37) is unenforced; the only real check is the
*optional, Docker-dependent* live acceptance run (phase-02:74), which is not a CI
gate (`claude plugin validate .` does not run PHP — verified: no PHP in the
validate gate per CLAUDE.md "Validate / check" section).

**Evidence:** phase-01-test-harness-runner.md:41-49; phase-02-batch-runtime.md:79;
no host PHP per plan.md:39-43 and CLAUDE.md validate section.

**Suggested fix:** Drop the per-subcommand stub for the batch test. Make the
idempotency contract a *live-only* test that hard-fails (not skips) when Docker is
absent, and gate the phase on it. The stub is fine for the single-invocation
count assertion only — relabel it so it is not mistaken for an idempotency test.

---

## Finding 2: PHP fatal mid-batch loses the summary entirely — whole-batch abort is NOT mitigated
**Severity:** Critical
**Location:** phase-02 Requirements & step "End: echo json_encode" (lines 28-32, 54-55 of brainstorm); plan.md Acceptance (line 59)

**Flaw:** The plan's mitigation is "wrap each op in try/catch, collect errors,
continue" (phase-02:31; brainstorm:71). Two holes:
1. `try/catch` in PHP catches `Throwable` only. A true fatal — memory exhaustion
   on a large media import, `max_execution_time` timeout, or a fatal emitted by
   third-party plugin code (ACF/Elementor hooks firing inside `wp_insert_post`) —
   is **not** catchable and aborts the process.
2. The summary is emitted **once at the very end** (`echo json_encode([...])`,
   phase-02:54-55 / brainstorm:55). If the process dies before that line, the
   orchestrator captures **no JSON** (or partial). The `jq` merge then has nothing
   to merge → `seed.idempotencyKeys` / `lastSummary` for the records that *did*
   get created are never written to the manifest.

**Failure scenario:** Batch creates 30 of 42 posts, then OOMs importing a 12 MB
hero. Posts exist in WP, but `wp-build.json` records zero new keys and the stage
is not marked done. Re-run is *functionally* safe (live `get_posts` dedupe), but
the manifest's idempotency ledger silently diverges from WP state — the exact
"idempotency drift" the contract forbids — and `seed.lastSummary` observability
is blank for a partial failure, the case it exists for. Acceptance criterion
"partial run re-runnable" (plan.md:59) holds only by luck of live queries, not by
the recorded state the plan claims to preserve.

**Evidence:** phase-02-batch-runtime.md:28-32, 54; brainstorm:55,71;
contrast bash `_seed_record_key` writes the manifest **per op** (seed-helpers.sh:66-75, 153),
so a bash mid-run death preserves every key created so far.

**Suggested fix:** Emit progress incrementally — either append each stable key to
the manifest as it is created (matching seed-helpers.sh per-op semantics) via a
fast secondary channel, or have PHP `register_shutdown_function` flush a partial
summary on fatal. Set/raise `memory_limit` and `set_time_limit(0)` at batch top.

---

## Finding 3: `jq` summary merge clobbers prior `idempotencyKeys` (array replace, not union)
**Severity:** Critical
**Location:** phase-02 step 3 (lines 70-72); brainstorm §4 (line 65)

**Flaw:** The plan says "merges `idempotencyKeys` into `wp-build.json` once via
`jq`" but never specifies *union*. The repo's deep-merge helper does a jq spread:
`jq ". * (${value})"` (manifest-core.sh:85). For JSON arrays, `*` **replaces** —
it does not concatenate. The bash engine was explicit about this and used
`((existing + [k]) | unique)` (seed-helpers.sh:71-74).

**Failure scenario:** `seed-content` writes
`seed.idempotencyKeys = ["page:home", "menu:Primary", ...]`. Then
`seed-plugin-data` runs its batch and merges its own summary array
`["meta:12:subtitle", ...]`. If implemented with `wpbuild_merge` (the obvious
choice), the second stage's array **overwrites** the first's → content-stage keys
vanish from the ledger. Same loss on any second partial run of one stage. The
"`seed.idempotencyKeys` still recorded" acceptance criterion (plan.md:60) is
violated by the most natural implementation of the step as written.

**Evidence:** scripts/manifest-core.sh:85 (`jq ". * (${value})"`);
scripts/seed-helpers.sh:71-74 (union+unique, the behavior being replaced).

**Suggested fix:** Specify the merge as an explicit union:
`jq --argjson new "$keys" '.seed.idempotencyKeys = ((.seed.idempotencyKeys // []) + $new | unique)'`.
Do **not** route the keys array through `wpbuild_merge`.

---

## Finding 4: Media path resolution — only the theme dir is mounted; content/CPT assets are not, and the stdin batch has no usable CWD
**Severity:** High
**Location:** phase-02 media row & Risk (lines 44, 93-94); phase-03 Requirements (line 28); brainstorm:60,74

**Flaw:** The plan repeatedly asserts media imports "from the **mounted** theme
assets path." Verified mount reality: `.wp-env.json` is generated with
`mappings: { (themedest): theme }` and `themes: [ $theme ]`
(wp-env-bootstrap.sh:81,89) — **only the theme directory is mounted.** But
content-seeding extracts bodies and media from `optimization.outputDir`
(content-seeding SKILL §Inputs, lines 30,43), which is *not* the theme dir and is
*not* mounted. Worse: the runtime is piped via `wp eval-file -` (stdin), so its
working directory inside the container is the WP root, not the project — a payload
entry `'file' => 'assets/images/hero.jpg'` (phase-03:36-38) resolves to
`/var/www/html/assets/images/hero.jpg`, which does not exist. The current bash
`import_media` already documents this exact hazard and provides
`WP_MEDIA_PATH_PREFIX` to prepend a mapped container path (seed-helpers.sh:256-260,273).
The plan **drops that mechanism** and replaces it with an unverified assumption.

**Failure scenario:** Every `seed_import_media` call fails to find its file →
`wp_insert_attachment` errors → caught and collected → batch reports
`media created:0, errors:[...]` and continues. Pages seed with no featured images
and broken `<img>` src. Looks like a successful run; site renders imageless.

**Evidence:** scripts/wp-env-bootstrap.sh:81,89 (theme-only mount);
scripts/seed-helpers.sh:256-260,273 (`WP_MEDIA_PATH_PREFIX`, the dropped escape
hatch); skills/content-seeding/SKILL.md:30,43 (assets come from
`optimization.outputDir`, not the theme).

**Suggested fix:** Decide and document the container-visible media root. Either
add a mapping for the assets dir to `.wp-env.json`, or carry forward an absolute
container-path prefix into payload `file` entries, or sideload via
`media_sideload_image` from a served URL. Add a live-run assertion that imported
attachment count == expected, not just "no exception."

---

## Finding 5: Single-line stdout JSON has no sentinel — WP notices/banner pollute the parse
**Severity:** High
**Location:** phase-02 step 3 (line 71); brainstorm §4 (line 65)

**Flaw:** The orchestrator "captures stdout JSON" and pipes it to `jq`. `wp
eval-file` shares stdout with everything WordPress emits during bootstrap: PHP
deprecation/notice output, plugin "headers already sent" chatter, ACF/Elementor
admin-notice echoes, and any stray `echo`/`var_dump` left in a payload. wp-env is
provisioned with `WP_DEBUG=true` (wp-env-bootstrap.sh:85) — display is off, but
WP-CLI still surfaces warnings on stdout in many cases, and third-party code
echoes regardless of `WP_DEBUG_DISPLAY`. There is no delimiter isolating the JSON
line.

**Failure scenario:** ACF prints a deprecation notice before the final
`json_encode`. Orchestrator stdout = `Deprecated: ...\n{"created":42,...}`. `jq`
fails to parse → summary merge silently no-ops or the stage errors after WP was
fully and correctly seeded. Re-run then re-evaluates everything; if any helper's
live check has an edge gap (Finding 1 territory), you get dupes.

**Evidence:** scripts/wp-env-bootstrap.sh:85 (`WP_DEBUG: true`); phase-02:71
(raw stdout → jq, no framing).

**Suggested fix:** Frame the summary with a unique sentinel
(`echo "@@SEED_SUMMARY@@" . json_encode(...)`) and have bash extract the line
after the sentinel, or write the JSON to a known file path inside a mounted dir
and read that instead of stdout. Send all diagnostics to stderr.

---

## Finding 6: `wp-env run` fallback may not forward stdin — empty program → false "success"
**Severity:** High
**Location:** phase-01 Architecture (lines 32-36); phase-02 Risk (lines 87-88)

**Flaw:** The runner resolves to `docker exec -i <cli> wp` when a cli container is
detected, else falls back to `wp-env run cli wp` (phase-01:24-26,32-36). The whole
design depends on `eval-file -` reading the concatenated program from **stdin**.
`docker exec -i` forwards stdin; `npx @wordpress/env run` (the fallback,
wp-env-bootstrap.sh:30-31) wraps docker and is not guaranteed to pipe stdin
through cleanly (it has historically allocated a TTY / consumed stdin). The plan
defers this to "asserted in the live run" (phase-02:87) — i.e., unverified.

**Failure scenario:** Container name filter `--filter name=cli` returns empty (a
custom wp-env project prefix, or container not yet named at detection time) →
fallback path taken → `eval-file -` receives empty stdin → PHP runs an empty
program → no ops, no error → `json_encode` of empty counters →
`created:0, errors:[]` → orchestrator marks stage done. **The pipeline reports a
clean idempotent run while seeding nothing.** This is the most dangerous failure:
silent and indistinguishable from a correct no-op re-run.

**Evidence:** phase-01-test-harness-runner.md:24-26,32-36;
scripts/wp-env-bootstrap.sh:30-31 (`npx --yes @wordpress/env`).

**Suggested fix:** If the resolved runner is the `wp-env run` fallback, do not use
stdin — write the program to a mounted temp file and `wp eval-file <path>`. Add a
guard: if the summary shows `created+skipped == 0` but the payload was non-empty,
fail loudly rather than marking the stage done.

---

## Finding 7: `commands/build.md` has no seed-stage anchor to edit; "orchestrator runs the batch" contradicts the thin-coordinator architecture
**Severity:** Medium
**Location:** phase-03 step 3 & Related Files (lines 58, 70-71); phase-04 step 3 (lines 43, 54); plan.md Acceptance (line 61)

**Flaw:** Three phases call for "Update `commands/build.md` seed-content stage to
run the driver + merge summary." Verified: `build.md` mentions "seed" only in the
stage-order list (build.md:28) and the delegation line (build.md:66) — there is
**no per-stage seed section** to modify. build.md is explicitly a thin
coordinator ("orchestrator coordinates and delegates — it does not do heavy work
itself", CLAUDE.md Component layers). Putting `eval-file` execution + jq merge
into build.md contradicts that. Conversely, the seed *skills* run inline in the
main session (per project memory: "Build stages run inline, no Wave agents") and
already `bash ./seed-content.sh` themselves (content-seeding SKILL §4, lines
119-124). So the correct home for "orchestrator (not agent) executes" is the
**skill**, not build.md — the agent-death fix is to stop delegating execution to
the spawned `wp-data-engineer` agent, which is a *skill* edit.

**Failure scenario:** Implementer takes the plan literally, grows build.md with
per-stage execution logic, duplicating what the skill does, and creating two
places that run the batch. Plus: build.md is **currently uncommitted-modified**
(`git diff --stat`: build.md +5, the parallel-build plan's convert note already
landed in build.md:35-38). Two concurrent uncommitted plans editing the same file
with no committed baseline = the "rebase carefully" hand-wave (plan.md:67-70) has
no merge base. Real conflict hole.

**Evidence:** commands/build.md:28,66 (only seed refs; no stage block);
build.md:35-38 (parallel-build's convert note already present, uncommitted);
git diff --stat = build.md modified; skills/content-seeding/SKILL.md:119-124
(skill already runs the script inline).

**Suggested fix:** Relocate the execution/merge change into the seed *skills*
(remove the "delegate execution to agent" instruction; skill runs the batch
inline and merges). Limit build.md edits to at most a one-line note, and land it
on a committed baseline to give the parallel-build plan a real merge base.

---

## Finding 8: Cutover window (phase-03 done, phase-04 pending) mixes two idempotency-ledger writers; agent contract still mandates the deleted helpers
**Severity:** Medium
**Location:** phase-03 / phase-04 dependency ordering; phase-05 Requirements (lines 20-23)

**Flaw:** Phases 3 and 4 cut the two stages over independently (phase-04
`dependencies: [2,3]`). Between them, `seed-content` records keys via the new PHP
summary path (Finding 3 union semantics) while `seed-plugin-data` still sources
`seed-helpers.sh` and records via `_seed_record_key`'s union+unique. A re-run of a
sample build in that window has two writers with different array-merge semantics
touching `seed.idempotencyKeys` — drift risk during the migration itself, not just
after. Separately, the `wp-data-engineer` agent's **non-negotiable rule #1**
hard-codes "Prefer the `ensure_*` helpers in `seed-helpers.sh`; they encode this
and record keys into `seed.idempotencyKeys`" (agents/wp-data-engineer.md). Deleting
the file in phase-05 leaves the agent's binding instructions pointing at a
nonexistent script unless the agent body is rewritten in lockstep — phase-03/04
only touch the agent's *role* wording, and phase-05 does the final pass, so an
agent invoked mid-migration is told to use a half-removed engine.

**Failure scenario:** Operator runs `seed-plugin-data --force` after phase-03
lands but before phase-04 — bash engine union-writes keys; if the content stage
already replaced the array via the new path, plugin-data's union restores stale
keys, producing an inconsistent ledger that neither engine fully owns.

**Evidence:** agents/wp-data-engineer.md (rule #1 cites `seed-helpers.sh` +
`ensure_*` by name); seed-helpers.sh:66-75 (union semantics) vs Finding 3's new
path; plugin-data-seeding/SKILL.md:94-99 + references (acf/forms/elementor) all
still `source seed-helpers.sh` until phase-04.

**Suggested fix:** Update the `wp-data-engineer` rule #1 and the four
plugin-data references in the same phase that removes their engine, not in a
trailing cleanup. Consider feature-flagging both stages onto the new engine in one
phase, or freeze `--force` re-runs of the not-yet-migrated stage during the
window.

---

## Secondary notes (not numbered findings)
- **Parallel runner reimplementation:** phase-01 adds `scripts/wp-cli-runner.sh`,
  but `scripts/migrate-urls.sh:42` already carries its own inline runner "same
  convention as seed-helpers.sh," and seed-helpers.sh:47-57 has a third. The plan
  claims DRY yet leaves two inline copies un-consolidated. Low, but the new file
  should subsume them or the DRY claim is hollow.
- **Strategy "fail loudly if unset"** (phase-04:73): `wpbuild_get '.strategy'`
  returns the literal string `"null"` (jq -r) when absent, not empty
  (manifest-core.sh:57). The guard must test for `null`/empty both.

---

## Verification summary (what I traced against source)
- Mount reality: only theme dir mounted — wp-env-bootstrap.sh:81,89. ✔ confirms Finding 4.
- Array merge clobber: manifest-core.sh:85 `jq ". * (value)"`. ✔ confirms Finding 3.
- Per-op manifest write in bash (death-safety baseline): seed-helpers.sh:66-75,153. ✔ confirms Finding 2.
- build.md has no seed stage block; already uncommitted-modified by parallel plan: build.md:28,35-38,66 + git diff. ✔ confirms Finding 7.
- Agent rule binds to seed-helpers.sh by name: agents/wp-data-engineer.md rule #1. ✔ confirms Finding 8.

Status: DONE | Summary: Plan is directionally sound but 3 Critical gaps (phantom idempotency test, end-of-run-only summary loses partial state on PHP fatal, array-replace key merge) plus media-mount, stdout-framing, and stdin-fallback High risks must be closed before implementation.
