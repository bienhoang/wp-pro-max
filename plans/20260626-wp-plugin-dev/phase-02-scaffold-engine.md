---
phase: 2
title: "Scaffold engine"
status: done
effort: ""
priority: P1
dependencies: [1]
---

# Phase 2: Scaffold engine

## Overview

Generate a working, activatable OOP plugin skeleton from `wp-plugin.json` — the
deterministic boilerplate plus the agent that authors the real PHP — with a
**correct PSR-4 fallback autoloader** and a **registrar marker invariant**.

## Requirements

- Functional: `plugin-scaffold.sh` stamps the folder tree + boilerplate
  (per-file check-before-write); a **real PSR-4** no-Composer autoloader; a
  bootstrap that prefers `vendor/autoload.php`; the `wp-plugin-developer` agent
  authors secure OOP code but **not** the registrar region.
- Non-functional: WPCS-compliant output, zero PHP notices on activation, every
  generated source file under the modularization budget.

## Architecture

The script does deterministic file creation; the `wp-plugin-developer` agent
fills contextual PHP. (**Correction, Red-team #20:** the theme side has *no*
`theme-scaffold.sh` — `wp-scaffold` is skill+agent only. The script here exists
because the user locked skill+agent+script; it stays minimal: dir creation +
token interpolation of bodies read from the reference `.md`, **not** a separate
`templates/` tree — Red-team #11.)

```
<slug>/
  <slug>.php          # header + bootstrap: prefer vendor/autoload.php else inc/autoload.php
  uninstall.php       # guarded (defined('WP_UNINSTALL_PLUGIN') || exit)
  readme.txt          # filled Phase 5
  inc/autoload.php    # real PSR-4 require autoloader (namespace tail → subdir)
  src/Plugin.php      # singleton bootstrap + registrar with a LITERAL marker
  languages/
  .gitignore
```

Template bodies live in `skills/wp-plugin-dev/references/plugin-architecture.md`
as fenced blocks (kit convention, per `theme-conversion`).

The tree above is scaffolded under **`./<slug>/` in the CWD** (Validation: output
location); `wp-plugin.json` sits at `./<slug>/wp-plugin.json` and the scaffold
script resolves all paths relative to that plugin root.

## Related Code Files

- Create: `scripts/plugin-scaffold.sh` — dir tree + header/token interpolation + idempotent writes.
- Create: `agents/wp-plugin-developer.md` — expert WP plugin author, **standards only** (model: sonnet).
- Create: `skills/wp-plugin-dev/references/plugin-architecture.md` — canonical layout, bootstrap, autoloader contract, registrar-marker spec, **and the template bodies** (`<slug>.php`, `uninstall.php`, `autoload.php`, `Plugin.php`, `.gitignore`).
- Modify: `skills/wp-plugin-dev/SKILL.md` — wire the `new` procedure to script + agent.

## Implementation Steps

1. **Scaffold script** — reads `wp-plugin.json` via `plugin-manifest-lib.sh`.
   Per-file check-before-write (Red-team #18: per-file idempotency is the source
   of truth; the coarse `wpplugin_is_done scaffold` guard only skips re-invoking
   the agent, never blocks restoring a deleted file). Interpolate header tokens
   (Plugin Name, Text Domain, Namespace, version) into files from
   `plugin-architecture.md`; never overwrite existing files.
2. **Real PSR-4 fallback autoloader (Red-team #1, #12)** — `inc/autoload.php`:
   `spl_autoload_register` that (a) `return`s early unless the class starts with
   the plugin namespace prefix; (b) strips the prefix, replaces `\` → `/`, appends
   `.php` under `src/` (so `Acme\PostTypes\FooPostType` → `src/PostTypes/
   FooPostType.php`); (c) `realpath`-contains the result under `src/` before
   `require` (no traversal). **Not** shortname→flat `src/`.
3. **Autoloader precedence baked into the bootstrap (Red-team #4)** — `<slug>.php`
   template loads `vendor/autoload.php` when it exists, else `inc/autoload.php`.
   This conditional is in the Phase 2 template so Phase 5 (Composer) needs no edit
   to `<slug>.php`.
4. **Bootstrap + registrar marker (Red-team #8)** — `src/Plugin.php` template:
   singleton `instance()`, `register()` wiring `init`/activation hooks, path/url/
   version constants, and a **literal sentinel comment** (e.g.
   `/* wp-plugin-dev:registrar */`) marking the feature-registration insertion
   point. The agent may refine constructors/constants but **must not** author or
   move the registrar region/marker; the reference states this as a hard rule.
5. **Agent** — `wp-plugin-developer.md` frontmatter (name, description scoped to
   plugin authoring, `tools: [Read, Write, Edit, Bash, Glob, Grep]`, `model:
   sonnet`). Body carries **standards only** (Red-team #11/#6-of-scope): WPCS
   (tabs, docblocks, snake_case funcs), security (nonces, capability checks,
   sanitize input / escape output, `$wpdb->prepare`, `defined('ABSPATH') ||
   exit`), and the marker rule — **not** per-feature code bodies (those live once
   in the references).
6. **Architecture reference** — author `plugin-architecture.md` with the file
   set, bootstrap pattern, autoloader contract, marker spec, and template bodies.

## Success Criteria

- [ ] Scaffold on a fresh `wp-plugin.json` produces the tree; re-run is a per-file
      no-op; deleting a file and re-running **restores** it.
- [ ] **In-env (Docker/wp-env) behavioral check:** plugin activates with **zero
      PHP notices**; a sub-namespaced class (`…\PostTypes\…`) autoloads via
      `inc/autoload.php` with no Composer present.
- [ ] Autoloader rejects a non-prefixed/`..`-bearing class name (no `require`).
- [ ] `<slug>.php` prefers `vendor/autoload.php` when present (verified by adding
      a stub vendor dir).
- [ ] `src/Plugin.php` contains the literal registrar marker; agent output leaves
      it intact.
- [ ] `bash -n scripts/plugin-scaffold.sh` clean; `claude plugin validate .` passes.

## Risk Assessment

- **Agent dropping/moving the marker** (Red-team #8) → forbid in the reference;
  Phase 3 fails loud if absent (defense in depth).
- **Autoloader correctness** (Red-team #1) → the sub-namespaced-class activation
  test is a required gate, not optional.
- **Overwriting user edits on re-run** → strict per-file check-before-write.
