# Red-Team Review — Fast Seeder eval-file Plan (Security Adversary / Fact Checker)

Plan: `plans/2026-07-01-fast-seeder-eval-file/` (plan.md + phase-01..05 + brainstorm)
Reviewer posture: hostile security adversary. Verification role: fact checker.
Verdict up front: the plan converts a **data channel** (today: WP-CLI argv) into a
**code channel** (generated PHP piped to `wp eval-file -`) and nowhere specifies
how arbitrary, third-party-controlled source strings are encoded into PHP. That is
a PHP-injection / RCE-class design hole baked into Phases 2–4. Multiple blocking
findings below.

---

## Finding 1: No PHP-literal encoding scheme defined — arbitrary source HTML/titles become executable PHP

**Severity: Critical**

**Location:** Phase 3, "Architecture / Payload shape" (`phase-03-content-seeding-migration.md:32-50`);
Phase 2, "Architecture / Self-contained execution" (`phase-02-batch-runtime.md:48-53`);
Phase 4 acf/elementor entries (`phase-04-plugin-data-migration.md:19-37`).

**Flaw:** The payload is shown as PHP source with values inlined as **single-quoted
PHP literals**, e.g. `phase-03-content-seeding-migration.md:37-39`:

```php
'posts' => [['slug'=>'home','title'=>'Home','type'=>'page',
             'template'=>'front-page.php','content'=>'<h1>…</h1>', ...
```

This generated `.php` is then prepended with the runtime and piped to
`wp eval-file -` (`phase-02-batch-runtime.md:48-53`, `phase-03:46-47`). The plan
**never** states how `$content`, `$title`, ACF values, etc. are serialized into the
literal. Searched the whole plan dir for `var_export|base64|addslashes|escapeshellarg`:
**zero hits** (grep over `plans/2026-07-01-fast-seeder-eval-file/`). The only
escaping primitive named anywhere is `wp_slash` (Elementor, DB layer — see Finding 3).

The input is attacker-influenced by design: `content-seeding` extracts the body from
arbitrary third-party static HTML (`skills/content-seeding/SKILL.md:49-61`,
`references/content-extraction.md:18-51`). HTML body copy routinely contains `'`
(apostrophes: "we're", `class='x'` attributes). A single apostrophe terminates the
PHP string literal early — at best a parse fatal that kills the whole batch
(defeating the plan's own "no whole-batch abort" goal, `phase-02:30-31`), at worst
code execution.

**Failure scenario:** Source page body contains:
`<p>'.file_put_contents(ABSPATH.'shell.php',$_GET['c']).'</p>`
Embedded into `'content'=>'<p>...'.file_put_contents(...).'...</p>'`, the literal
closes, the injected `file_put_contents` runs inside the WordPress container (full
filesystem + DB + `$wpdb` + `system()` access), planting a webshell in the docroot.
`wp eval-file` executes **arbitrary** PHP; there is no sandbox. Converting an
untrusted HTML scrape into a generated, executed PHP file is remote code execution
by construction.

**Evidence (file:line):**
- `phase-03-content-seeding-migration.md:33-44` (literal payload, no encoding)
- `phase-02-batch-runtime.md:48-53` (prepend runtime + pipe to `eval-file -`)
- `skills/content-seeding/references/content-extraction.md:18-51` (body from third-party HTML)
- `scripts/seed-helpers.sh:144-149` (today's SAFE model — content is `cat`'d and passed as a single argv element `--post_content="$content"`, never parsed as code)

**Suggested fix:** Mandate that **no source string is ever emitted as PHP source**.
Two safe options, pick one and make it a hard acceptance criterion:
(a) Emit the entire payload as **JSON** in a separate file/stdin channel and have the
shipped runtime `json_decode(file_get_contents('php://stdin'))` it — runtime is the
only PHP; data is never code. (b) If values must live in the `.php`, encode every
scalar with `base64_encode` host-side and `base64_decode` in-runtime, or build the
array with `var_export` of an already-structured value. Add a fixture whose body
contains `'`, `"`, `</?php`, `${`, backslash, and `'.system("id").'` and assert the
batch treats it as inert text. Until an encoding contract exists, Phases 2–4 are
not buildable safely.

---

## Finding 2: `eval-file` of generated PHP silently demolishes the repo's "WP-CLI / no raw SQL / dry-run" safety posture — and the plan's compliance claim is factually false

**Severity: Critical**

**Location:** Brainstorm "Constraints" and approach table
(`brainstorm-fast-seeder-eval-file.md:27` and `:36`); plan Overview
(`plan.md:24-25`).

**Flaw:** The brainstorm asserts the design is safe because
*"WP-CLI only (no raw SQL — `eval-file` runs PHP via WP API, compliant)"*
(`brainstorm:27`) and *"WP-CLI-compliant"* (`brainstorm:36`). This is false. The
repo's stated safety invariant is that DB writes prefer WP-CLI and **destructive
`wp db query` requires a `--dry-run` preview first** (`CLAUDE.md:80`,
`references/manifest-contract.md:62`, `docs/system-architecture.md:150`). That
guard exists precisely to stop unreviewed destructive SQL. `wp eval-file` executes
**arbitrary PHP** — including `$wpdb->query('DELETE …')`, `dbDelta`, `system()`,
`unlink()` — with **no dry-run gate, no preview, no WP-CLI subcommand boundary**.
Nothing constrains the generated PHP to "the WP API." The plan moves the single
most dangerous capability in the system (arbitrary code) inside the one stage that
used to be a fixed set of audited WP-CLI verbs, and labels it "compliant."

**Failure scenario:** A future contributor (or a hallucinating authoring agent)
emits a payload that, to "fix" idempotency, runs `$wpdb->query("TRUNCATE ...")`
inside the runtime. It executes unreviewed. The `--dry-run` discipline that
`migrate-urls.sh` and `wp-deployer` enforce (`scripts/migrate-urls.sh:137-149`,
`agents/wp-deployer.md:27`) is structurally unreachable for this path because there
is no SQL subcommand to intercept — it is opaque PHP on stdin.

**Evidence (file:line):**
- `brainstorm-fast-seeder-eval-file.md:27` and `:36` (false "compliant" claim)
- `CLAUDE.md:80` ("destructive `wp db query` requires a `--dry-run` preview first")
- `references/manifest-contract.md:62`; `docs/system-architecture.md:150` (same invariant)
- `scripts/migrate-urls.sh:137-149` (the dry-run pattern the repo actually relies on)

**Suggested fix:** Drop the "WP-CLI-compliant" framing — it is not. If `eval-file`
is kept, the plan must (1) restrict the runtime to a documented allowlist of WP API
calls and explicitly **ban** `$wpdb` raw queries / shell / filesystem writes outside
the mounted assets dir in the runtime; (2) add a review gate equivalent to the
dry-run rule (e.g. the orchestrator dumps the concatenated stream for inspection
before execution, or runs `php -l` + a static check that rejects `system`/`exec`/
`$wpdb->query`/`eval`/`base64_decode`-then-`eval` in the **payload** region). State
this as an acceptance criterion in Phase 2.

---

## Finding 3: Elementor/ACF escaping is specified at the wrong layer — `wp_slash` guards the DB but not the PHP literal

**Severity: High**

**Location:** Phase 2 Architecture table elementor row + Risk
(`phase-02-batch-runtime.md:47` and `:91-92`); Phase 4 Architecture + Risk
(`phase-04-plugin-data-migration.md:35` and `:68-69`).

**Flaw:** The plan's *only* named escaping concern is
*"Elementor JSON must be `wp_slash`'d or it corrupts"* (`phase-02:91`), handled via
`update_post_meta('_elementor_data', wp_slash($json))` (`phase-02:47`). `wp_slash`
runs **inside** the runtime and protects the value on the way **into the DB**. It
does nothing for the step before that: getting the JSON string into the PHP payload
literal in the first place. `_elementor_data` is built from analyzed HTML and
contains user/source text — including quote-bearing `editor` HTML and `title`
settings (`skills/plugin-data-seeding/references/elementor-data.md:46-53`,
`:80-90`). Today this JSON is passed as **argv** via `"$(cat ./elementor/home.json)"`
(`references/elementor-data.md:19-23`; `scripts/seed-helpers.sh:298-304`) — inert.
Under the plan it must be embedded as a PHP literal first, where its `"` / `'` /
`\` break the literal exactly as in Finding 1. The plan congratulates itself for
solving the DB-layer footgun while leaving the code-layer footgun unaddressed.

**Failure scenario:** A `text-editor` widget whose `editor` setting is
`<p>O\'Brien said "hi"</p>` produces JSON containing `'` and `\`. Embedded as a PHP
literal in the payload, the backslash + quote terminate/escape the string before
`wp_slash` is ever reached — parse fatal or injection. The Phase 4 "dedicated
quote-bearing fixture + `get_post_meta` round-trip" test (`phase-04:68-69`) only
asserts the DB round-trip; it will not catch a literal that was mis-encoded into the
payload unless the fixture is run through the *generator*, which the plan does not
require.

**Evidence (file:line):**
- `phase-02-batch-runtime.md:47`, `:91-92` (wp_slash = DB layer only)
- `skills/plugin-data-seeding/references/elementor-data.md:46-53`, `:80-90` (source-derived quote-bearing JSON)
- `scripts/seed-helpers.sh:298-304` (current argv path — value never code)

**Suggested fix:** Same as Finding 1 — encode the JSON into the payload via
base64/JSON-channel, then `json_decode` + `wp_slash` in-runtime. Make the
quote-bearing fixture flow through the **generator → eval-file** path end-to-end,
not just an in-runtime `update_post_meta` call, so the literal-encoding step is
actually exercised.

---

## Finding 4: Untrusted input is never validated/sanitized at the trust boundary — only "non-empty" is checked

**Severity: High**

**Location:** Phase 3 (body embed, `phase-03-content-seeding-migration.md:21-28`);
content extraction recipe (`skills/content-seeding/references/content-extraction.md:35-51`).

**Flaw:** The boundary where third-party HTML enters the system performs no security
validation. The extraction recipe is regex `match(/<main[^>]*>([\s\S]*?)<\/main>/i)`
with strip of script/style/header/footer, and the only gate is
*"Validate output is non-empty before writing"* (`content-extraction.md:51`). There
is no escaping, no character allowlist, no length bound, and explicitly no parser
guarantee (regex fallback). That raw blob is then embedded into executable PHP
(Finding 1). The behavioral checklist item "validate all external inputs at system
boundaries, not just UI" is unmet: the boundary check is presence, not safety.

**Failure scenario:** Source HTML with a deliberately unbalanced `<main>` and an
embedded `'.eval($_POST[0]).'` payload passes the non-empty check, is written to the
payload, and executes. Even absent malice, any legitimate page with an apostrophe in
the copy triggers a batch-killing parse error — a reliability failure on normal
input.

**Evidence (file:line):**
- `skills/content-seeding/references/content-extraction.md:35-51` (regex extract, only non-empty validation)
- `phase-03-content-seeding-migration.md:21-24` ("page body HTML embedded directly")
- `scripts/seed-helpers.sh:144-149` (today: content stays data, so lack of sanitization was tolerable)

**Suggested fix:** Treat extracted HTML as untrusted bytes end-to-end: encode (never
inline) into the payload, bound the size (Phase 3 already flags huge bodies at
`:87-89` — fold that into a hard limit), and add the malicious-input fixture from
Finding 1 to the boundary test rather than only a non-empty assertion.

---

## Finding 5: Secret-bearing values (form recipients, SMTP/mail config, ACF values) get materialized into a generated `.php` file on disk in the target project

**Severity: Medium**

**Location:** Phase 4 forms section (`phase-04-plugin-data-migration.md:24-25`,
`:35-37`); Phase 3 payload file `seed-content-payload.php`
(`phase-03-content-seeding-migration.md:21`); debug-write flag
(`phase-03:92-93`).

**Flaw:** The plan writes the full payload — options, ACF values, and CF7/WPForms
config — inline into `seed-content-payload.php` / `seed-plugin-data-payload.php` in
the **target project**. CF7 form config carries `_mail` settings, i.e. recipient
addresses and mail routing (`skills/plugin-data-seeding/references/forms-seeding.md`
mail block; `skills/plugin-data-seeding/SKILL.md:83-86`). ACF/option values can hold
API keys, recipient emails, or third-party tokens depending on the source site.
Today these values also appear in `seed-content.sh`, but the plan **amplifies**
exposure: it consolidates *all* body + ACF + Elementor + form data into one
persisted PHP artifact, plus an optional `SEED_DEBUG_BODIES=1` that writes bodies
into the **mounted theme dir** (`phase-03:92-93`) — which is typically committed in
the target repo. The plan never says these generated payloads must be git-ignored or
deleted post-run, and `development-rules.md` forbids committing secrets/credentials.

**Failure scenario:** A converted site whose contact form routes to an internal
distribution list, or whose ACF "API key" field holds a live token, gets written to
`seed-plugin-data-payload.php`; the target project is committed; the secret is now in
version control history.

**Evidence (file:line):**
- `phase-04-plugin-data-migration.md:24-25`, `:35-37` (forms/CF7 mail + ACF into payload)
- `skills/plugin-data-seeding/SKILL.md:83-86` (CF7 `_mail`/`_form` meta)
- `phase-03-content-seeding-migration.md:21`, `:92-93` (payload file + debug-write into mounted theme dir)
- `~/.claude/rules/development-rules.md` Quality Gates ("Never commit secrets … credentials")

**Suggested fix:** Require generated payloads to be written to a git-ignored path (or
stream via stdin and never persist), and add a Phase 5 cleanup/`.gitignore` step.
Explicitly state the debug-write target must be git-ignored and off by default.
Add an acceptance criterion: "no generated payload or debug body is committed to the
target repo."

---

## Finding 6: The runtime+payload concatenation order and driver invocation are contradictory — undefined execution = a place where injected code wins

**Severity: Medium**

**Location:** Phase 2 "Self-contained execution"
(`phase-02-batch-runtime.md:48-53`); Phase 1 fixture
(`phase-01-test-harness-runner.md:55`).

**Flaw:** Phase 2 says the generator *"**prepends** it [runtime] to the data payload"*
(`:50-51`) **and** that *"the runtime reads its data from a `$SEED_PAYLOAD` array the
payload defines **before** the runtime's `seed_run($SEED_PAYLOAD)` driver executes"*
(`:52-53`). These conflict: if the runtime is prepended (comes first) and ends by
calling `seed_run($SEED_PAYLOAD)`, then `$SEED_PAYLOAD` is undefined at call time
because the payload that defines it comes *after*. The actual safe ordering
(payload defines data, then runtime executes) is the **reverse** of "prepend." An
undefined order means the concatenation contract is unspecified, which is exactly
where a payload that "happens" to define functions or call code first can take
control of execution. For an eval'd stream this ambiguity is security-relevant, not
just a bug.

**Failure scenario:** Generator prepends runtime; `seed_run($SEED_PAYLOAD)` runs
against `null` → either fatal (batch dead) or, if the runtime defends by reading a
global the payload sets via side effect, the payload region gains a foothold to run
arbitrary top-level statements before/after the intended driver.

**Evidence (file:line):**
- `phase-02-batch-runtime.md:48-53` (contradicts itself: prepend vs. "payload defines before driver executes")
- `phase-01-test-harness-runner.md:55` (`fixtures/payload.sample.php` exists but the stream-assembly contract is not pinned)

**Suggested fix:** Define one canonical assembly: payload (data only, no executable
top-level statements) first, runtime second, runtime owns the single
`seed_run($SEED_PAYLOAD)` call at end-of-stream. Better: the payload defines **only**
a JSON/array constant and the runtime is the sole code — assert in Phase 1 that the
payload region contains no function/`eval`/`system`/statement tokens.

---

## Finding 7: `wp db query` dry-run guard is preserved in name but undermined in practice by the surrounding eval-file path

**Severity: Medium**

**Location:** Phase 4 requirement + success criterion
(`phase-04-plugin-data-migration.md:24-25`, `:64`).

**Flaw:** Credit where due: Phase 4 explicitly keeps *"guarded `wp db query` stays a
last resort with the existing `--dry-run` preview rule"* (`:24-25`) and asserts it as
a success criterion (`:64`). That matches the repo convention (`CLAUDE.md:80`,
`references/manifest-contract.md:62`). **But** the guard is now porous: the same
stage gains an unguarded arbitrary-PHP execution path (Findings 1–2). Keeping the
dry-run rule on the rarely-used `wp db query` branch while opening a no-gate
`eval-file` highway next to it is security theater — an author needing a DB write
will reach for the unguarded PHP path, not the guarded SQL one, precisely because
it is easier. The control is bypassable by design.

**Failure scenario:** Form config that "can't be set via WP-CLI" (the documented
trigger for `wp db query`, `skills/plugin-data-seeding/SKILL.md:88-90`) is instead
done with a raw `$wpdb->query` inside the runtime payload — no dry-run, convention
satisfied on paper, defeated in practice.

**Evidence (file:line):**
- `phase-04-plugin-data-migration.md:24-25`, `:64` (dry-run preserved for `wp db query`)
- `skills/plugin-data-seeding/SKILL.md:88-90` (the WP-CLI-can't-do-it branch that motivates raw writes)
- `CLAUDE.md:80`; `references/manifest-contract.md:62` (the convention being half-kept)

**Suggested fix:** Extend the dry-run/no-raw-SQL invariant to the runtime itself
(Finding 2 fix). Ban `$wpdb` raw queries in the payload/runtime via static check, so
the only DB-write doors are guarded WP-CLI verbs or the documented dry-run path.

---

## Finding 8: `docker exec -i` runner auto-detection picks the first container named `cli` with no ownership check

**Severity: Medium**

**Location:** Phase 1 runner detection
(`phase-01-test-harness-runner.md:24-26`, `:34-36`); brainstorm runner design
(`brainstorm-fast-seeder-eval-file.md:44-48`).

**Flaw:** The shared runner resolves to `docker exec -i <name> wp` where
`<name> = docker ps --filter name=cli --format '{{.Names}}' | head -n1`
(`phase-01:34-36`). The filter `name=cli` is a substring match across **all**
running containers on the host, and `head -n1` blindly takes the first. There is no
verification that the selected container belongs to *this* wp-env / target project.
The plan then pipes a freshly generated arbitrary-PHP stream into it via stdin
(`-i`). On a multi-project dev box, the eval-file batch can execute against the wrong
WordPress.

**Failure scenario:** Developer has two wp-env projects up (`projectA_cli_1`,
`projectB-cli`). `head -n1` selects whichever Docker lists first; the seed batch —
which now includes option overwrites and possibly DB writes — runs against the wrong
site, corrupting it. With Finding 1's injection, code executes in an unintended
container.

**Evidence (file:line):**
- `phase-01-test-harness-runner.md:24-26`, `:34-36` (substring `name=cli` + `head -n1`, no ownership check)
- `brainstorm-fast-seeder-eval-file.md:44-48` (same detection logic)
- `CLAUDE.md` wp-env conventions ("CWD = target project with `.wp-env.json`") — the runner ignores CWD/project binding

**Suggested fix:** Bind detection to the current project: derive the wp-env instance
from the target `.wp-env.json` / project hash, or require a tighter filter
(`label=com.docker.compose.project=<proj>` or the wp-env-computed name), and **fail
loudly if more than one match** instead of silently `head -n1`. Add a runner test
asserting multi-container ambiguity errors rather than guesses.

---

## Cross-cutting note (not a separate finding)

The root design choice — "generate PHP, execute via eval-file" — is the source of
Findings 1–4 and 7. A JSON-data-channel + fixed-runtime design (runtime is the only
code; data is `json_decode`'d from stdin/file) eliminates the entire PHP-injection
class while keeping the performance win (still one container invocation per stage).
That is the recommended pivot; it does not change the speed thesis (single
`eval-file` call) but removes the code/data conflation. Phase 2's "DRY: runtime
authored once" goal is actually *easier* to honor when the runtime never has data
spliced into it.

---

Status: DONE | Summary: Critical PHP-injection/RCE design hole — generated PHP embeds untrusted source strings with no encoding scheme defined (Findings 1,3,4), eval-file bypasses the repo's no-raw-SQL/dry-run safety posture while the plan falsely calls it "compliant" (Findings 2,7), plus secret materialization (5), undefined stream-assembly order (6), and unsafe container auto-detection (8).
