---
phase: 3
title: "Feature generators"
status: done
effort: ""
priority: P1
dependencies: [2]
---

# Phase 3: Feature generators

## Overview

Implement `add <feature>` for the four core generators — CPT/taxonomy, admin
settings page (Settings API), REST route, shortcode — injecting secure OOP
classes into an existing plugin **atomically** and recording them in
`wp-plugin.json`.

## Requirements

- Functional: each `add` creates a namespaced class, registers it at the
  `Plugin.php` marker, and appends to `features[]` **only after** the registry
  edit is verified. Idempotent: re-adding is a guarded no-op; a half-finished add
  is recoverable (manifest not yet written).
- Non-functional: each class WPCS-clean and security-correct (caps, nonces,
  sanitize/escape, prepared queries); REST/CPT exposure is explicit, not
  accidentally public.

## Architecture

Each feature is a class under `src/` registered at the `Plugin.php` registrar
marker (Phase 2). The scaffold script writes the class from the **single
canonical body in `feature-generators.md`** (Red-team #11 — no `templates/` tree,
no agent-duplicated bodies); the agent specializes only labels/field-defs/route
schema within the security envelope.

```
src/PostTypes/<Name>PostType.php     # register_post_type; show_in_rest from manifest flag
src/PostTypes/<Name>Taxonomy.php     # register_taxonomy bound to a CPT
src/Admin/SettingsPage.php           # Settings API: settings_fields()→options.php (built-in nonce)
src/Rest/<Name>Controller.php        # register_rest_route, capability permission_callback, schema
src/Shortcodes/<Name>Shortcode.php   # add_shortcode, escaped output, attr sanitize
```

**Atomic add order (Red-team #9):** (1) write class file; (2) edit `Plugin.php`
at the marker and **verify** the insert (re-grep); (3) only then append to
`features[]`. Any failure before step 3 leaves the manifest unchanged, so a
re-run retries cleanly instead of being blocked by a premature `features[]` entry.

## Related Code Files

- Modify: `scripts/plugin-scaffold.sh` — `add <feature>` dispatch + class stamping + verified marker insert.
- Create: `skills/wp-plugin-dev/references/feature-generators.md` — **single source** of the secure body + registration line per feature.
- Modify: `skills/wp-plugin-dev/SKILL.md` — document the `add` procedure + feature table.
- Modify: `agents/wp-plugin-developer.md` — only if standards need feature-specific notes (no bodies).

## Implementation Steps

1. **Marker precondition (Red-team #8)** — before any insert, assert the
   `Plugin.php` registrar marker exists; if absent, **fail loud (non-zero)** with
   a clear message rather than guessing a location.
2. **CPT + taxonomy** — full `labels`, `supports`, rewrite slug from args.
   **`show_in_rest` is driven by a manifest flag (Red-team #16), default `false`**
   for new CPTs; document that `show_in_rest: true` publishes the type on the
   public REST API (`/wp-json/wp/v2/<cpt>`). Taxonomy bound to the CPT.
3. **Settings page (Red-team #17)** — pin to the standard Settings API flow:
   `register_setting` with a `sanitize_callback`, `add_settings_section/field`,
   and a form using `settings_fields()` + `do_settings_sections()` posting to
   `options.php` (built-in nonce/CSRF protection). **Forbid hand-rolled
   `admin-post.php` handlers** unless they call `wp_verify_nonce`. Render
   callbacks escape output and gate on `current_user_can('manage_options')`.
4. **REST route** — `register_rest_route` with explicit `methods`, a
   capability-checking `permission_callback` (**never `__return_true` for
   writes**), `args` schema with `sanitize_callback`/`validate_callback`,
   responses via `rest_ensure_response`.
5. **Shortcode** — `add_shortcode`, `shortcode_atts` defaults, sanitized attrs,
   escaped return string (no echo).
6. **Registry wiring** — insert each feature's registration at the literal marker,
   additively (anchored), then verify by re-reading; idempotency guard on
   `features[]` prevents double-insert on a clean re-run.
7. **Manifest (last)** — append the feature key (+ per-feature options like CPT
   `restExposed`) to `features[]` only after steps 1–6 succeed.
8. **Reference** — `feature-generators.md` carries the canonical secure code for
   each feature (one place).

## Success Criteria

- [ ] Each `add` on a scaffolded plugin creates the class + a verified marker
      insert; re-running is a no-op; a simulated mid-add failure leaves
      `features[]` unchanged and is recoverable on re-run.
- [ ] Missing marker → `add` fails loud, does not corrupt `Plugin.php`.
- [ ] **In-env (wp-env):** CPT/taxonomy appear in admin; REST route enforces its
      `permission_callback`; settings save sanitized via `options.php`; shortcode
      renders escaped. Generated classes pass PHPCS/WPCS (Phase 5 tooling).
- [ ] A CPT scaffolded without the REST flag is **not** exposed at
      `/wp-json/wp/v2/<cpt>`.
- [ ] `features[]` reflects exactly what was added, with options.

## Risk Assessment

- **Insecure defaults** (open REST writes, public CPT, unescaped output, CSRF)
  (Red-team #16/#17 + Security) → templates encode security by default; explicit
  REST-exposure flag; `options.php` settings flow; final security pass in Phase 6.
- **Partial-failure corruption** (Red-team #9) → manifest-append-last + verified
  insert + recoverable re-run.
- **Registry edit corrupting `Plugin.php`** → anchored insert at the literal
  marker with post-insert verification; fail loud if marker missing.
