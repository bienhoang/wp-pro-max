---
phase: 1
title: "Foundation"
status: done
effort: ""
priority: P1
dependencies: []
---

# Phase 1: Foundation

## Overview

Establish the standalone manifest, **shared** manifest helpers, skill skeleton,
and a dispatch-capable opt-in command — the spine every later phase fills in. No
PHP authoring yet.

<!-- Updated: Validation Session 1 - output location pinned to ./<slug>/ in CWD; namespace auto-derived PascalCase; shared manifest-core confirmed -->


## Requirements

- Functional: a `wp-plugin.json` manifest contract; a shared `manifest-core.sh`
  reused by both `wpbuild_*` and `wpplugin_*` wrappers; a `wp-plugin-dev` skill
  skeleton that is genuinely opt-in; a `/wp-pro-max:plugin` command able to invoke
  the skill and agent.
- Non-functional: zero entanglement with `wp-build.json`; scripts source cleanly
  in **bash and zsh**; the existing theme pipeline keeps working after the core
  refactor; SKILL.md procedure-only (bodies deferred to `references/`).

## Architecture

`wp-plugin.json` (in the target plugin project root) is the single source of
truth for a plugin build — slug, namespace, textdomain, architecture, enabled
`features[]`, tooling flags, per-stage `progress`.

**No duplicated manifest library (Red-team #19).** Extract the generic helpers
from `manifest-lib.sh` into `scripts/manifest-core.sh`, parameterized by
`$MANIFEST_FILE`. `manifest-lib.sh` keeps its `wpbuild_*` names as thin wrappers
(back-compat); `plugin-manifest-lib.sh` adds `wpplugin_*` wrappers + the only
genuinely different function, `init`. One zsh-safe core, fixed once.

The command is a thin router and **must declare `Task` + `Skill`** (Red-team #3)
— `commands/env.md`'s `[Read, Bash, Glob]` list was wrong to copy because that
command dispatches nothing, whereas `commands/build.md` (which invokes
skills/agents) declares `[Read, Write, Edit, Bash, Glob, Grep, Task, Skill]`.

**Opt-in is enforced in the skill body (Red-team #10), not by command omission**
— skills auto-invoke by description in this kit (README: "Skills are also
auto-invoked by name when relevant"). So the description is scoped to "build a
standalone WordPress plugin from scratch" and the skill body no-ops (with a clear
message) when `wp-build.json` is present and `wp-plugin.json` is absent — i.e.
mid-theme-build — to avoid colliding with `wp-scaffold`'s CPT/`register_post_type`
trigger surface.

## Related Code Files

- Create: `scripts/manifest-core.sh` — generic `_manifest_get/set/progress/is_done` on `$MANIFEST_FILE`.
- Modify: `scripts/manifest-lib.sh` — source the core; keep `wpbuild_*` as wrappers (no API change).
- Create: `scripts/plugin-manifest-lib.sh` — `wpplugin_init` + `wpplugin_*` wrappers over the core.
- Create: `schemas/wp-plugin.schema.json` — draft-07, mirrors `wp-build.schema.json` style.
- Create: `skills/wp-plugin-dev/SKILL.md` — frontmatter + procedure skeleton + opt-in guard.
- Create: `skills/wp-plugin-dev/references/wp-plugin-manifest.md` — manifest field contract.
- Create: `commands/plugin.md` — `/wp-pro-max:plugin` router (allowed-tools incl. `Task`, `Skill`).

## Implementation Steps

1. **Shared core** — extract `manifest-lib.sh`'s generic body into
   `manifest-core.sh` operating on `$MANIFEST_FILE` (default unset → caller sets
   it). Keep the dual sourced/sub-command pattern and the exact zsh-safety guards
   (no top-level `set -e`, no `status`/`BASH_SOURCE` reliance). Refactor
   `manifest-lib.sh` to `source` the core and define `wpbuild_*` wrappers binding
   `MANIFEST_FILE=${WP_BUILD_FILE:-./wp-build.json}`. **Re-run the existing
   pipeline's manifest checks (bash+zsh, idempotent mock) to prove no regression.**
2. **Plugin wrappers** — `plugin-manifest-lib.sh` sources the core, binds
   `MANIFEST_FILE=${WP_PLUGIN_FILE:-./wp-plugin.json}`, defines `wpplugin_get/set/
   progress/is_done` wrappers, and `wpplugin_init <slug> [namespace] [name]`.
   **Define derivation (Red-team #14):** `namespace := PascalCase(slug)` when
   omitted, `textDomain := slug`, `name := TitleCase(slug)` — all validated
   against the schema before write so `wpplugin_init acme-widgets` alone yields a
   schema-valid manifest.
3. **Schema** — `wp-plugin.schema.json`. Required: `version` (`"1"`), `plugin`
   (`{slug, name, namespace, textDomain}`; slug/textDomain `^[a-z0-9-]+$`,
   namespace `^[A-Za-z][A-Za-z0-9_]*$`), `architecture` (`"oop"`), `progress`.
   Optional: `features[]` (enum `cpt|taxonomy|settings|rest|shortcode|block`,
   each entry may carry per-feature options e.g. CPT `restExposed: bool`),
   `tooling` (`{composer, phpcs, phpunit, blockBuild}` booleans), `env`
   (port/php/wp).
4. **Skill skeleton** — `SKILL.md` frontmatter `name: wp-plugin-dev`, description
   scoped to *standalone plugin from scratch* (avoid bare "register_post_type"
   phrasing that overlaps `wp-scaffold`), `allowed-tools: [Read, Write, Edit,
   Bash, Glob, Grep]`. Body: opt-in guard (no-op when `wp-build.json` present &&
   `wp-plugin.json` absent), subcommand map, the `source
   "${CLAUDE_PLUGIN_ROOT}/scripts/plugin-manifest-lib.sh"` preamble, placeholders
   to later-phase references.
5. **Command** — `commands/plugin.md` frontmatter (`description`, `argument-hint:
   "[new <slug> [namespace]|add <feature>|lint|test|package]"`, `allowed-tools:
   [Read, Bash, Glob, Task, Skill]`). Body routes `$1`; `new <slug>` scaffolds
   **into `./<slug>/` in the CWD** (Validation: output location) — `wp-plugin.json`
   at `./<slug>/wp-plugin.json` — running `wpplugin_init` there then invoking the
   skill via `Skill`; feature/dev subcommands operate on the plugin in CWD (the
   dir containing `wp-plugin.json`) and delegate to the agent via `Task`.
6. **Manifest reference** — `references/wp-plugin-manifest.md` documents every
   field + the derivation rules + a complete example `wp-plugin.json`.

## Success Criteria

- [ ] `bash -n` clean for all three scripts; `manifest-core.sh` + both wrappers
      source in **bash and zsh** without altering the caller shell.
- [ ] Existing theme pipeline manifest ops still pass after the refactor
      (regression check on `wpbuild_*`).
- [ ] `jq empty schemas/wp-plugin.schema.json` valid; required keys present.
- [ ] `wpplugin_init acme-widgets` (slug only) creates a **schema-valid**
      `wp-plugin.json` with derived namespace/textDomain/name; progress helpers
      round-trip.
- [ ] `commands/plugin.md` declares `Task` + `Skill`; `claude plugin validate .`
      passes (manifest-shape check only — not behavioral proof).
- [ ] Opt-in guard verified: invoking intent inside a dir with `wp-build.json` and
      no `wp-plugin.json` no-ops with a clear message.

## Risk Assessment

- **Refactoring the completed `manifest-lib.sh`** (Red-team #19) risks the live
  theme pipeline → keep `wpbuild_*` signatures identical; gate on the regression
  check; the recorded zsh incident makes the dedupe worth it (fix-once).
- **zsh breakage of sourced helpers** → copy the exact guards; test both shells.
- **Schema drift vs `wp-build.json`** → separate `$id`; no shared fields.
