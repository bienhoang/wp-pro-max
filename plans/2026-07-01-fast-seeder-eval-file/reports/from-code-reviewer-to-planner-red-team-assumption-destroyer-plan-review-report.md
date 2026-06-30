# Red-Team Plan Review — Fast Seeder (eval-file PHP batch)

**Reviewer role:** Assumption Destroyer / Scope Auditor (hostile)
**Plan:** `plans/2026-07-01-fast-seeder-eval-file/`
**Verdict:** Several load-bearing assumptions are false or unverified. The central
concatenation mechanism (Finding 1) does not work as written — proven empirically
against the live `cli` container. Two contracts the plan claims to "preserve" are
silently narrowed (Findings 3, 4). A sibling plan is invalidated without
acknowledgement (Finding 5). Do not start implementation until 1, 2, 3, 4 are
resolved.

Note on assumptions that *held* (tested in `wp-env-wp-cf4859fc-cli-1`): `wp eval-file -`
reads stdin (exit 0, `STDIN_OK`); `php -l` lints piped stdin and returns non-zero on
syntax error (the plan's container-lint step is valid); wp-env keeps long-lived
`*-cli-1` containers, so the `docker exec` speed premise is real. stdin (a pipe, not
argv) is not subject to `ARG_MAX`, so "embed all bodies" does not hit an argv limit —
the design choice is sound on that axis.

---

## Finding 1: The runtime+payload concatenation, as specified, is a hard PHP parse error AND calls `seed_run($SEED_PAYLOAD)` before the payload defines it

**Severity:** Critical

**Location:** `phase-02-batch-runtime.md:49-53`; `brainstorm-fast-seeder-eval-file.md:57`;
`plan.md:24-25`.

**Flaw:** The plan states two mutually contradictory things and the literal
description is unparseable:
- "the generator **prepends** it [the runtime] to the data payload" (phase-02:50-51,
  brainstorm:57).
- "The runtime reads its data from a `$SEED_PAYLOAD` array the payload defines
  **before** the runtime's `seed_run($SEED_PAYLOAD)` driver executes" (phase-02:52-53).

If the runtime is prepended and the runtime ends with `seed_run($SEED_PAYLOAD)`, then
`$SEED_PAYLOAD` is referenced *before* the appended payload defines it → undefined
variable, `seed_run` receives null. Worse, each shipped `.php` file starts with
`<?php`; concatenating runtime + payload puts a second `<?php` mid-stream, which is a
fatal parse error, not output text (only text *after* a `?>` is echoed; there is no
`?>`).

**Failure scenario:** Phase 3 generates `seed-content-payload.php`, the driver `cat`s
runtime + payload into `wp eval-file -`, and the whole batch dies with
`PHP Parse error: syntax error, unexpected token "<"` before a single record is
seeded — on every run. Zero pages created; the headline "seconds, idempotent" outcome
is unreachable.

**Evidence (empirical, `docker exec -i wp-env-wp-cf4859fc-cli-1 php -l`):**
- Plan's stated order (runtime first calling `seed_run($SEED_PAYLOAD)`, payload with
  its own `<?php` appended): `Errors parsing Standard input code` /
  `unexpected token "<" ... on line 4`, exit 255.
- Any second `<?php` in a tag-opened stream: `unexpected token "<", expecting end of
  file`, exit 255.
- Working order (payload-first defines `$SEED_PAYLOAD`, **no** second open tag, runtime
  functions + final `seed_run` call appended): `No syntax errors detected`, exit 0.

**Suggested fix:** Specify the exact stream contract: one `<?php` only. Either (a)
payload is a *data-only* fragment with no open tag and the driver wraps it, runtime
appended last calling `seed_run`; or (b) runtime defines functions only (no trailing
`seed_run`), payload comes second (open tag stripped) and ends with the
`seed_run($SEED_PAYLOAD)` call. State who strips the payload's `<?php`. Add a
concatenation test to `seed-batch.test.sh` that pipes the real concat through
container `php -l` (already proven to catch this).

---

## Finding 2: `docker ps --filter name=cli` matches the tests container too; `head -n1` is nondeterministic → batch may seed the wrong database

**Severity:** Critical

**Location:** `phase-01-test-harness-runner.md:34-36` (`docker ps --filter name=cli
--format '{{.Names}}' | head -n1`); `brainstorm:44-46,86`.

**Flaw:** `--filter name=cli` is a substring match. wp-env runs two cli services per
project: the dev `*-cli-1` (bound to the dev DB) and `*-tests-cli-1` (bound to the
separate tests DB). The filter returns both; `head -n1` picks whichever Docker lists
first, which is not guaranteed to be the dev container.

**Failure scenario:** Runner resolves to `*-tests-cli-1`. The batch seeds 42 pages into
the **tests** database. `wp post list` against the dev site shows nothing; the operator
sees an empty front end after a "successful" run and re-runs, compounding confusion.
The plan's idempotency/verify steps all query through the same mis-resolved runner, so
they look green.

**Evidence (live `docker ps --filter name=cli --format '{{.Names}}'`):**
returns both `wp-env-wp-cf4859fc-cli-1` and `wp-env-wp-cf4859fc-tests-cli-1`. Memory
note ["build env has Docker/Node/Composer"] confirms verifying behaviorally here.

**Suggested fix:** Anchor the match: exclude tests (`grep -v tests`) and pin to the
`-cli-1` suffix, e.g. `docker ps --format '{{.Names}}' | grep -E -- '-cli-1$' | grep -v
-- '-tests-cli-1$'`. Add a `runner.test.sh` case feeding a stub `docker` that lists both
names and asserting the dev container is chosen, not `head -n1`.

---

## Finding 3: ACF postmeta fallback drops the `_field` reference row, and `update_field` is not guaranteed available inside `eval-file` — both contradict the documented ACF contract

**Severity:** High

**Location:** `phase-02-batch-runtime.md:46` (acf row: "`function_exists('update_field')
? update_field : update_post_meta` (field-key fallback)"); `brainstorm:53,73`;
`phase-04:35`.

**Flaw:** The existing skill reference is explicit that an ACF value requires **two**
meta rows — the value (`subtitle`) *and* the field-key reference (`_subtitle =
field_xxx`) — or `get_field()`/admin fidelity breaks
(`skills/plugin-data-seeding/references/acf-seeding.md:26-46`). The plan's non-ACF
fallback is described as "update_post_meta (field-key fallback)" but the helper writes a
single value; nothing in the plan pairs the `_field` reference row. Separately,
`update_field()` only resolves a field *name* to its key if the field group is
registered in the DB — and the same reference says registration happens via
`wp acf sync` *or* "loading any admin page triggers the sync"
(`acf-seeding.md:18-20`). A headless `wp eval-file` batch triggers neither, so on a
fresh DB `update_field('subtitle', …)` can write the value without the `_field`
reference, the exact failure the fallback was meant to avoid.

**Failure scenario:** Batch seeds ACF values on a freshly scaffolded site where the
group JSON has not yet synced. Templates using `get_field()` render empty; admin shows
the fields as unset. Re-running does not fix it because the value row exists, so the
idempotency check skips.

**Evidence:** `skills/plugin-data-seeding/references/acf-seeding.md:26-46` (two-row
requirement, `_subtitle = field key`), `:18-20` (sync requires `wp acf` or admin load),
`:74-82` (`update_field` "writes the `_field` reference for you" — i.e. plain
`update_post_meta` does not). Plan never restates the two-row rule for the fallback.

**Suggested fix:** Make the fallback write both rows (value + `field_<key>`), require the
payload to carry the field key (it is already in `acf-json/*.json` `fields[].key`), and
either run `wp acf sync --all` (or `acf_get_field` resolution) inside the batch before
values, or assert the group is registered and fail loudly otherwise. Carry the
two-row + key fidelity into the Phase 4 test, not just a generic "ACF values set".

---

## Finding 4: Elementor helper drops the required `_elementor_template_type` meta key

**Severity:** High

**Location:** `phase-02-batch-runtime.md:47` (elementor write = `update_post_meta(
'_elementor_data', wp_slash($json)) + _elementor_edit_mode=builder`);
`brainstorm:53,74`; `phase-04:21-22`.

**Flaw:** The plan sets only two keys. The existing reference documents **three**
required keys per Elementor page: `_elementor_data`, `_elementor_edit_mode=builder`, and
`_elementor_template_type=wp-page` (`elementor-data.md:9-14`). Omitting
`_elementor_template_type` is a known cause of Elementor failing to treat the page as a
builder page / rendering the classic content instead of the layout.

**Failure scenario:** `seed-plugin-data` runs for a `page-builder` strategy build; pages
get `_elementor_data` but no template type. Front end renders the (often empty) classic
post body, not the Elementor layout. QA visual diff fails and the cause is invisible
because `_elementor_data` "is set".

**Evidence:** `skills/plugin-data-seeding/references/elementor-data.md:9-14` (table of
required postmeta, `_elementor_template_type | wp-page | … required`), `:22-23`
(sets all three in the current flow via `ensure_acf_value`). Plan writes two.

**Suggested fix:** Have `seed_set_elementor_data` write all three keys
(`_elementor_template_type` defaulting to `wp-page`, `wp-post` for posts), matching the
reference. The Phase 2/4 round-trip fixture should assert all three, not just
`_elementor_data`.

---

## Finding 5: Phase 5 deletes `seed-helpers.sh` and Phase 4 rewrites `plugin-data-seeding` to PHP — both invalidate the pending WooCommerce extension plan, which is built directly on them. Unacknowledged.

**Severity:** High

**Location:** `phase-05-retire-bash-docs.md:36,46-47,63-67` (delete `seed-helpers.sh`;
risk section only checks "ship runbooks", concludes "ship uses `migrate-urls.sh`, not
seed-helpers; confirmed out-of-scope"); `phase-04:19-29` (rewrites `plugin-data-seeding`
to per-strategy PHP payloads).

**Flaw:** A sibling pending plan, `plans/2026-06-26-woocommerce-catalog-build-extension/`
(status: pending), explicitly *extends* `seed-helpers.sh` and the *bash*
`plugin-data-seeding` skill: "`seed-helpers.sh` gains `ensure_wc_product` … extends
`ensure_term` with an optional `[parent-slug]` … `plugin-data-seeding` adds a WooCommerce
branch routed like the forms branch" (woo `phase-06-seeding.md:23-26`), and lists
`Modify: scripts/seed-helpers.sh` (woo `phase-06-seeding.md:95`). Deleting the file and
converting the skill to a PHP-payload generator removes the foundation that plan's Phase
6 is written against. This plan's Phase 5 risk assessment enumerates only ship runbooks
and never mentions the WooCommerce plan, even though its own grep step 1
(`grep -rn 'seed-helpers' .`) surfaces those files (verified: woo files appear in the
grep output).

**Failure scenario:** This plan lands; WooCommerce plan is then picked up and its entire
Phase 6 (`ensure_wc_product`, `ensure_term [parent-slug]`, bash forms-branch routing) no
longer has a host file or skill shape to attach to — silent rework or a broken
half-merge that reintroduces `seed-helpers.sh`.

**Evidence:** woo `plans/2026-06-26-woocommerce-catalog-build-extension/phase-06-seeding.md:23-26,78-83,95-96`;
this plan `phase-05-retire-bash-docs.md:63-67` (dependency-scan scope omits it).

**Suggested fix:** Add a cross-plan dependency note (like the parallel-build "soft
overlap" in `plan.md:67-72`): either define how WooCommerce product/term/forms seeding
maps onto the new `$SEED_PAYLOAD` (`commerce` section + `seed_ensure_wc_product` helper)
so the woo plan can target the PHP engine, or sequence the woo plan to land first. Do
not present `seed-helpers.sh` deletion as risk-free.

---

## Finding 6: Dropping `content/<slug>.html` breaks the documented QA URL-rewrite and post-update paths, not just "human review"

**Severity:** Medium

**Location:** `phase-03-content-seeding-migration.md:21-22` ("page body HTML embedded
directly (drops the `content/*.html` round-trip; optional debug-write retained behind a
flag)"); `:88-93` (treats the loss as traceability only, mitigated by
`SEED_DEBUG_BODIES=1`).

**Flaw:** The content-extraction reference uses `content/<slug>.html` as a live input to
two downstream operations, not merely for human inspection: (1) image `src` rewriting
"post-import with `wp search-replace` (guarded, dry-run first) **during QA**"
(`content-extraction.md:28-29`), and (2) the documented way to push edited content into
an existing page: `wp post update <ID> --post_content="$(cat content/<slug>.html)"`
(`content-extraction.md:75`). If the files are no longer written by default, the QA
search-replace flow and the update path lose their source of truth; an optional debug
flag does not restore them for the standard run.

**Failure scenario:** A build seeds with bodies embedded only in the payload. During QA,
the operator follows the documented `wp post update … "$(cat content/home.html)"` to fix
a page; the file is absent, the command writes an empty body, and the page content is
wiped.

**Evidence:** `skills/content-seeding/references/content-extraction.md:28-29,75`;
`skills/content-seeding/SKILL.md:57-61` (extraction writes `content/<slug>.html` as the
contract). Plan demotes this file to optional.

**Suggested fix:** Either keep writing `content/<slug>.html` by default (embed *and*
write — cheap) and only treat the bash `ensure_page` call-site as removed, or update
`content-extraction.md` to move the QA rewrite + post-update flows onto the payload as
the new source of truth. Resolve the brainstorm's open question (`brainstorm:98`) before
implementation rather than deferring.

---

## Finding 7: Only the `docker exec -i` stdin path is validated; the `wp-env run cli wp` fallback for `eval-file -` is asserted, never proven

**Severity:** Medium

**Location:** `phase-01-test-harness-runner.md:34-36` (fallback `wp-env run cli wp`; `-i`
added only to the docker-exec branch); `phase-02-batch-runtime.md:88` ("`wp eval-file -`
stdin support / `docker exec -i` needed → asserted in the live run; runner already adds
`-i`").

**Flaw:** The plan's stdin proof covers exactly one of the three runner branches. The
`-i` flag and the live acceptance assertion are specific to `docker exec`. The fallback
`wp-env run cli wp eval-file -` goes through `docker-compose run`, whose default TTY/stdin
handling differs (often needs `-T` to pipe cleanly); the plan never tests piping a stream
into the wp-env path. The fallback exists precisely for environments without a live
container — the case where it is least tested.

**Failure scenario:** On a host where the live-container detection misses (or in CI that
provisions wp-env fresh), the runner falls back to `wp-env run cli wp eval-file -`, the
piped PHP never reaches stdin (TTY allocation), and `eval-file -` reads empty input or
hangs. The "20× faster" path silently produces a no-op run.

**Evidence:** Existing default runner is `wp-env run cli wp` (`scripts/migrate-urls.sh:45`,
`scripts/seed-helpers.sh:48,51`), so the fallback is the historical norm, not a rare edge.
The docker-exec stdin path was verified here (`wp eval-file -` → `STDIN_OK`, exit 0); the
wp-env path was not (wp-env not installed on this host: `which wp-env` → not found).

**Suggested fix:** Add a `seed-batch.test.sh`/live assertion for the wp-env fallback
specifically (pipe a fixture, assert `created>0`), or have `wp-cli-runner.sh` add `-T`
(or `cat | wp-env run --… cli wp eval-file -` with documented flags) for the fallback.
Do not claim stdin works for a branch you never exercised.

---

## Finding 8: "Orchestrator (not the heavy agent) executes the batch" has no wiring in `commands/build.md`; the command only invokes skills and currently delegates seeding to the agent

**Severity:** Medium

**Location:** `plan.md:61` + `phase-03:24-26,71,81` (acceptance: "Orchestrator … executes
the batch and merges the summary"; agent "only authors the payload").

**Flaw:** `commands/build.md` is a thin coordinator: "Invoke the matching skill in order.
After each stage, read `wp-build.json` progress" (`build.md:32-33`), and its Delegation
section routes seeding to the agent: "`wp-data-engineer` (seeding/DB)"
(`build.md:65-68`). The current `content-seeding` skill also hands heavy work to the
agent (`content-seeding/SKILL.md:138-143`). The plan asserts the *orchestrator* runs
`seed-batch-run.sh`, captures stdout JSON, and `jq`-merges once — but build.md has no
step that runs a script, captures stdout, or merges JSON, and the plan does not specify
whether "orchestrator" means build.md or the (inline) seed skill. Without that
clarification the death-resilience claim ("agent death cannot lose a run", `plan.md:61`)
is unsubstantiated wiring.

**Failure scenario:** Implementer wires `seed-batch-run.sh` invocation inside the
`wp-data-engineer` agent (matching the *existing* delegation in build.md:65 and
SKILL.md:138-143), reproducing the exact agent-death failure the plan exists to fix.

**Evidence:** `commands/build.md:32-33,63-68`; `skills/content-seeding/SKILL.md:138-143`.
Project memory ["build stages run inline, no Wave agents"] indicates seed skills *can*
run inline — but build.md and the skill currently say otherwise, so the plan must specify
the change explicitly.

**Suggested fix:** Name the exact owner of `seed-batch-run.sh` execution (the inline seed
skill, or a new build.md step), show the build.md edit that runs the driver + merges the
summary, and update `content-seeding/SKILL.md:138-143` + `build.md:65-68` so the agent's
deliverable is the payload file only. Then the "survives agent death" criterion is
testable.

---

Status: DONE | Summary: 2 Critical (parse-error concat order; tests-cli mis-detection), 3 High (ACF/Elementor contract narrowing; unacknowledged WooCommerce-plan invalidation), 3 Medium (content/*.html QA dependency; untested wp-env stdin fallback; missing orchestrator wiring) — all with file:line + empirical evidence; block on 1–4.
