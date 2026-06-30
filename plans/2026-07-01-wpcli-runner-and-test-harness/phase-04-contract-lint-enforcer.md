---
phase: 4
title: "Contract lint enforcer"
status: done
effort: "M"
---

# Phase 4: Contract lint enforcer

## Overview

Add `test/contract-lint.sh` — static assertions over skills/agents/commands that
make the manifest contract and the "always use wpx" rule mechanical instead of
prose discipline. This is the enforcer that locks Phase 3.

## Requirements

- Functional, the lint FAILs on any of:
  1. A `skills/*/SKILL.md` missing frontmatter `name` / `description` /
     `allowed-tools`, or whose `name` ≠ its directory.
  2. A `wpbuild_progress <id>` / `wpbuild_is_done <id>` / `wpbuild_progress <id> …`
     call using an `<id>` outside the canonical stage set. **This is the
     greppable signal — there is no `stage:` frontmatter field** (Red Team #10);
     stage ids only appear as literal args to these helpers, which IS grep-able.
     The canonical set is **derived from `references/manifest-contract.md:16-23`**
     at lint time (parse the fenced id list), not hard-coded, so it can't drift.
  3. Any `wp-env run cli` occurrence outside the **allowlist** (the Phase 3
     table), scanned over the **whole repo minus `node_modules`/`vendor`/`.git`**
     — the SAME scope as Phase 3's done-grep (Red Team #2/#4).
  4. (WARN, not FAIL) a `wpbuild_get '.X…'` top-level manifest key absent from
     `schemas/wp-build.schema.json` — LLM prose varies; WARN avoids false fails.
- Non-functional: pure static (no Docker/WP), fast, zsh-safe; `jq` for schema +
  frontmatter parsing (host has jq); deterministic exit codes.

## Architecture

A single bash script, one function per rule, each appending to a findings list
with a tier (`FAIL`/`WARN`). Frontmatter parsed by slicing the leading `---`…`---`
block (simple `key: value`). `test/run.sh` calls this as a check.

**Canonical stage set is derived, not duplicated (Red Team #10).** Read the
fenced id list under "Stage ids (canonical)" in `manifest-contract.md` and build
the set at runtime. A comment pins the source. This avoids a second copy drifting
from the contract.

**Allowlist = the Phase 3 table, encoded as `path:reason` entries** (Red Team
#9/#13). Prefer path-scoped entries; for files that mix migratable and
non-migratable lines (e.g. `vuln-scan.sh`), allowlist by an explicit
`path + line-pattern` (e.g. lines matching `composer|phpcs|tests-cli`) rather
than blanket-exempting the whole file, so a genuinely raw `wp` call there is
still caught. Ship SSH runbooks stay path-scoped (their raw form is the remote
`WP_CLI_RUN` idiom, documented). Do NOT include a phantom `wpx.sh` fallback
entry; DO include `seed-helpers.sh` + `migrate-urls.sh` (real script runners).

**Consistency with `validate-port.sh` (Red Team #1).** That linter (updated in
Phase 3) now also asserts `wpx`. The two must not re-diverge: this lint and
`validate-port.sh` both enforce "snippets use `wpx`, raw `wp-env run cli` only in
the allowlist." Note the relationship in a comment so a future edit to one
prompts the other.

## Related Code Files

- Create: `test/contract-lint.sh`
- Modify: `test/run.sh` (add `check_contract_lint`)
- Reference (canonical stage ids): `references/manifest-contract.md`
- Reference (schema keys): `schemas/wp-build.schema.json`

## Implementation Steps

1. `derive_canonical_stages`: parse the fenced id list under "Stage ids
   (canonical)" in `references/manifest-contract.md` into a set (do NOT hard-code).
2. Define `WPENV_ALLOWLIST` as `path` / `path:line-pattern` entries from the
   Phase 3 table (incl. `seed-helpers.sh`, `migrate-urls.sh`, `commands/env.md`,
   `commands/plugin.md`, `vuln-scan.sh` non-`wp` pattern, ship SSH runbooks,
   cheatsheet, `wp-cli-runner.sh` fallback line). No phantom `wpx.sh` entry.
3. `walk()` helper excludes `node_modules`/`vendor`/`.git` (shared with `test/run.sh`).
4. `lint_frontmatter`: each `skills/*/SKILL.md` — required keys + name == dir.
5. `lint_stage_ids`: grep `wpbuild_(progress|is_done) <id>` args across skills;
   assert each `<id>` ∈ derived canonical set.
6. `lint_no_raw_wpenv`: `walk` for `wp-env run cli`; for each hit not matched by
   the allowlist (path or path:line-pattern) → FAIL with file:line.
7. `lint_manifest_keys` (WARN): extract `wpbuild_get '.<key>'` first segments;
   warn if not a top-level property in `wp-build.schema.json`.
8. Print findings grouped by tier; exit 1 if any FAIL.
9. Wire into `test/run.sh`; run the gate.

## Success Criteria

- [ ] `test/contract-lint.sh` passes on the migrated tree (Phase 3 complete),
      scanning the whole repo minus excludes — matching Phase 3's done-grep.
- [ ] Canonical stage set is derived from `manifest-contract.md` (edit the
      contract → lint picks it up; no second hard-coded copy).
- [ ] Adding a raw `wp-env run cli wp x` to any non-allowlisted file FAILs with file:line.
- [ ] A raw `wp` call inside `vuln-scan.sh` (outside the non-`wp` pattern) still FAILs.
- [ ] A `wpbuild_progress bogus-id` FAILs; a corrupted SKILL frontmatter key FAILs.
- [ ] A bogus `wpbuild_get` key WARNs (not FAIL).
- [ ] `node_modules`/`vendor` contents never trigger findings.
- [ ] Invoked by `test/run.sh`; `bash -n` clean; agrees with `validate-port.sh`.

## Risk Assessment

- *Deriving canonical from prose* → the contract's fenced block is stable and
  greppable; if parsing fails, FAIL loudly (don't silently accept all ids).
- *Frontmatter parsing brittleness* → line-based on the simple `key:` block; no
  full YAML.
- *Allowlist over-broad* → path:line-pattern entries (not blanket file exempt)
  keep dangerous raw `wp` calls catchable even in mixed files (Red Team #9).
- *Manifest-key false positives* → WARN-only by design.
- *Re-divergence from validate-port.sh* → both reference the same canonical rule;
  comment cross-links them (Red Team #1).
