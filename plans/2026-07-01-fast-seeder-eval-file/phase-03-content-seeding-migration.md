---
phase: 3
title: "Content-Seeding Migration"
status: done
priority: P1
dependencies: [2]
---

# Phase 3: Content-Seeding Migration

## Overview

Cut the `seed-content` stage over to the batch engine. The skill generates a
**pure-JSON payload** (`seed-content-payload.json`, never PHP), runs it via the
Phase-2 driver **inline (the skill itself, preserving the thin-coordinator
model)**, and the agent — if used — only authors the payload. Author/execute are
decoupled so an agent death can't lose a run.

## Requirements

- Functional: `content-seeding` SKILL generates `seed-content-payload.json` — a
  JSON object of options/media/pages/posts/terms/menus/front-page. Page body HTML
  is a JSON **string value** (not a PHP literal).
- Functional (red-team M2/AD6): **keep writing `content/<slug>.html`** — the
  documented QA `wp search-replace` and `wp post update … "$(cat …)"` paths
  depend on them (`references/content-extraction.md:28-29,75`). The payload's body
  string is sourced from these files; do not drop them.
- Functional (red-team M3): the **skill** runs `scripts/seed-batch-run.sh` inline
  and merges the summary + marks progress. Do NOT push run-logic into
  `commands/build.md` (it is a thin coordinator that delegates to the inline skill
  — `build.md:32-33,63-68`), and do NOT have the heavy agent run the batch. The
  agent's deliverable is the JSON payload only.
- Functional (red-team M1/S5): the generated payload + any debug body files are
  **git-ignored** in the target project; never embed real secrets (CF7 mail
  recipients, tokens) — pointers only, consistent with the handoff stage.
- Non-functional: idempotency contract preserved exactly; media path resolved per
  Phase 2 (mount/prefix), not assumed reachable.

## Architecture

Payload shape (`seed-content-payload.json` — pure JSON):
```json
{
  "mediaPathPrefix": "…optional…",
  "options":  {"blogname": "…", "permalink_structure": "/%postname%/"},
  "media":    [{"file": "assets/images/hero.jpg", "title": "hero"}],
  "posts":    [{"slug": "home", "title": "Home", "type": "page",
                "template": "front-page.php", "content": "<h1>…</h1>",
                "meta": {}, "featured": "hero"}],
  "terms":    [{"tax": "service_cat", "name": "…", "slug": "…"}],
  "menus":    [{"name": "Primary", "location": "primary",
                "items": [{"post": "home", "title": "Home"}]}],
  "frontPage": "home"
}
```
Execution: `seed-batch-run.sh seed-content-payload.json` → pipe JSON to stdin of
`wp eval-file seed-batch-runtime.php` → parse sentinel summary → append+unique
merge into manifest. Body extraction logic (selectors, strategy-aware) stays as
documented in `skills/content-seeding/references/content-extraction.md`; the body
is still written to `content/<slug>.html` (kept) and the payload references its
text as a JSON string. Only the **emit target** changes from bash calls to JSON
payload entries.

## Related Code Files

- Modify: `skills/content-seeding/SKILL.md` (replace §3 bash skeleton + §4 run
  with JSON-payload generation + **inline** `seed-batch-run.sh` call + summary
  merge; update §0/§5; keep `content/<slug>.html` writing)
- Modify: `skills/content-seeding/references/content-extraction.md` (emit to JSON
  payload; keep writing the per-page HTML files — do not drop them)
- Verify (likely **no edit**): `commands/build.md` already delegates the
  seed-content stage to the inline skill (`build.md:32-33,63-68`); run-logic
  stays in the skill, not the orchestrator. Touch only if the delegation wording
  needs to name the new driver.
- Modify: `agents/wp-data-engineer.md` (author-payload role; no long WP-CLI loops)
- Modify: target-project `.gitignore` guidance (ignore generated payload + debug bodies)
- Reference: `scripts/seed-batch-run.sh`, `scripts/seed-batch-runtime.php` (Phase 2)

## Implementation Steps

1. **(test-first)** Add `test/seeder/content-payload.test.sh`: a fixture manifest
   + a minimal optimized HTML page → assert the generated payload is **valid JSON**
   (`jq -e`) containing the expected posts/menus/front-page, that `content/<slug>.html`
   is written, and (orchestration) a single inline driver invocation. Zero-dup is
   verified by the live run, not the stub.
2. Rewrite `content-seeding/SKILL.md` §3–§5 to author the JSON payload and invoke
   `seed-batch-run.sh` **inline**, merge the summary, update resume/record steps;
   keep the `content/<slug>.html` write.
3. Add `.gitignore` guidance so the generated payload + debug bodies aren't committed.
4. Update `agents/wp-data-engineer.md`: deliverable is the JSON payload; remove
   "run hundreds of WP-CLI" expectations.
5. Run the content payload test + a **live** wp-env seed of a real sample; verify
   visually (front page set, menus assigned, pages published) and re-run zero-dup.

## Success Criteria

- [ ] Payload is valid JSON (no PHP); `content/<slug>.html` files still written.
- [ ] `seed-content` runs as one `eval-file` call; full sample seeds in seconds.
- [ ] Re-run (live): 0 duplicate pages/menu items; `created:0` in summary.
- [ ] Agent authors payload only; **the skill** runs the batch inline + merges summary (build.md untouched logic-wise).
- [ ] Generated payload + debug bodies git-ignored; no real secrets embedded.
- [ ] `content-payload.test.sh` green; `claude plugin validate .` passes.
- [ ] No remaining `source … seed-helpers.sh` in the content-seeding path.

## Risk Assessment

- Large bodies as JSON strings → fine (stdin pipe, no ARG_MAX per red-team); JSON
  string-escaping is automatic and safe, unlike PHP-literal embedding.
- build.md: since run-logic stays in the inline skill, this plan should **not**
  edit the same build.md sections as the parallel-build plan (theme-`convert`
  fan-out). If a delegation-wording touch is unavoidable, coordinate (plan Dependencies).
- `content/<slug>.html` retained → no traceability loss; QA `search-replace` /
  `post update` paths keep working (red-team M2/AD6).
