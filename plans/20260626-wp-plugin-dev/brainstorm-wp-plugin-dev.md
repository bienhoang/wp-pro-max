# Brainstorm — Add WordPress Plugin Development capability

**Date:** 2026-06-26 · **Repo:** wp-pro-max · **Mode:** standalone, opt-in
**Next step:** `/ck:plan` (design + phased plan, no coding this round)

## Problem statement

WP Pro Max today only produces **themes**. All custom data wiring (CPTs,
taxonomies, ACF fields, menus, image sizes) is scaffolded **into the theme**
(`wp-scaffold` → `inc/*.php`). It *selects* third-party plugins and emits
mu-plugins for cross-cutting concerns, but has **no capability to author a
brand-new, distributable WordPress plugin from scratch**.

Goal: add a **standalone, opt-in** skill that scaffolds and develops new
WordPress plugins (own folder, header, hooks, OOP architecture, Gutenberg
block, full build/test/dev loop) — independent of the HTML→site pipeline.

## Requirements (locked with user)

| # | Decision |
|---|----------|
| Interpretation | Standalone WP plugin builder (scaffold new plugins from scratch). |
| Integration | Standalone opt-in skill; **NOT** wired into default build order; leaves `wp-scaffold` untouched. |
| Structure | **Approach B** — skill + dedicated agent + script (mirrors theme side). |
| Generated plugin | **OOP + autoloader + core features + Gutenberg block.** Core generators: CPT/taxonomy, admin settings page (Settings API), REST route, shortcode; plus a block generator (block.json + @wordpress/scripts). |
| Tooling | **Full dev loop** — Composer + PHPCS (WPCS) + PHPUnit via wp-env + readme.txt + `.zip` packaging (`--no-dev`). |
| Reuse/state | Reuse `wp-env-setup` for local test WP; track state in a small **`wp-plugin.json`** manifest (resumable/idempotent, optional). |
| Output this round | Design + phased plan via `/ck:plan`, stop before coding. |

## Approaches evaluated

- **A — One comprehensive skill.** Cohesive single entry. ➖ SKILL.md balloons; one skill does too much. *Rejected.*
- **B — Skill + agent + script (chosen).** Mirrors repo convention exactly: theme side is `wp-scaffold` skill → `wp-theme-developer` agent → `scripts/*.sh`. Plugin side mirrors it. ➕ Convention-consistent, files stay under the 200-line budget, extensible. ➖ More files up front.
- **C — Minimal stamper.** Skeleton only, no tooling. ➖ Under-delivers vs the requested build tooling. *Rejected.*

## Recommended solution

New components (all opt-in, sibling to the existing pipeline):

1. **`skills/wp-plugin-dev/SKILL.md`** — decision logic + procedure; delegates
   heavy PHP to the new agent, calls the scaffold script, reads/writes
   `wp-plugin.json`. Detail pushed into `references/` to respect modularization.
2. **`agents/wp-plugin-developer.md`** — expert WP plugin author (OOP, namespaced,
   WPCS, zero notices, security: nonces/caps/sanitize/escape/prepared SQL).
   `model: sonnet`; tools Read/Write/Edit/Bash/Glob/Grep.
3. **`scripts/plugin-scaffold.sh`** — deterministic, idempotent boilerplate
   (folder tree, header, composer.json, phpcs.xml.dist, readme.txt, uninstall.php,
   autoloader, package.json when block). **zsh-safe** (per repo memory).
4. **`scripts/plugin-package.sh`** — build distributable `.zip` (`composer install
   --no-dev`, exclude tests/dev configs/node_modules).
5. **`commands/plugin.md`** → `/wp-pro-max:plugin` — opt-in entry:
   `new <slug>` · `add <cpt|tax|settings|rest|shortcode|block>` · `lint` · `test` · `package`.
6. **`schemas/wp-plugin.schema.json`** + manifest helpers — light `wp-plugin.json`
   (slug, namespace, textdomain, architecture, features[], tooling flags, stage
   progress). Reuse `manifest-lib.sh` pattern, zsh-safe.
7. **`references/`** under the skill — `plugin-architecture.md`,
   `feature-generators.md` (secure templates per feature), `block-build.md`,
   `tooling.md` (composer/phpcs/phpunit/packaging), `wp-plugin-manifest.md`, plus
   template files (`plugin-main.php`, `uninstall.php`, `readme.txt`,
   `composer.json`, `phpcs.xml.dist`, `block.json`…).

### Generated plugin shape

```
my-plugin/
  my-plugin.php          # header + bootstrap (autoload + instantiate Plugin)
  uninstall.php
  readme.txt
  composer.json          # PSR-4 Namespace\ → src/ ; dev: WPCS, phpunit
  phpcs.xml.dist         # WordPress Coding Standards ruleset
  package.json           # @wordpress/scripts — only when a block is added
  .gitignore
  src/
    Plugin.php           # bootstrap singleton, registers hooks
    PostTypes/  Rest/  Admin/SettingsPage.php  Shortcodes/  Blocks/
  blocks/<block>/        # block.json + src/index.js → build/
  languages/             # .pot
  tests/                 # PHPUnit via wp-env harness
```

No-composer fallback: simple PSR-4 `require` autoloader so a generated plugin
runs without Composer; Composer only needed for dev tooling/packaging.

### Reuse & boundaries

- Reuse `wp-env-setup` / `wp-env-bootstrap.sh` for the local test WordPress
  (mount plugin via `.wp-env.json` plugins[]).
- Reuse `manifest-lib.sh` pattern for the light manifest.
- **Boundary:** does not touch `wp-build.json` or the default `build` stage
  order. Clearly a separate capability.

## Risks & mitigations

| Risk | Mitigation |
|------|-----------|
| PHP/Composer/Node not installed in this env (per roadmap) | Scaffolding stays toolchain-free; lint/test/build/package degrade gracefully + verified on a toolchained machine. |
| Block build pulls a Node dependency | Gate behind opt-in `add block`; core plugins stay dependency-light. |
| SKILL.md size vs modularization budget | Detail lives in `references/`; SKILL.md holds procedure only. |
| Sourced shell scripts broke under zsh before | All new sourced helpers zsh-safe (no `status`/`BASH_SOURCE`/`set -e` traps). |
| Scope creep into theme `wp-scaffold` | Keep standalone; no `wp-build.json` entanglement. |

## Success metrics / acceptance

- `/wp-pro-max:plugin new acme-widgets` → plugin **activates with zero PHP
  notices** in wp-env.
- Generated plugin passes its own **PHPCS (WPCS)** clean.
- `add cpt|tax|settings|rest|shortcode|block` each inject working secure code;
  block builds via `@wordpress/scripts`.
- `package` → installable `.zip` with no dev files.
- `claude plugin validate .` still passes; new shell `bash -n` clean, node
  `node --check` clean; manifest idempotent/resumable.

## Phased plan preview (for /ck:plan)

1. **Foundation** — `wp-plugin.json` schema + zsh-safe manifest helpers + skill
   skeleton + opt-in command.
2. **Scaffold engine** — `plugin-scaffold.sh` + core templates + autoloader +
   `wp-plugin-developer` agent.
3. **Feature generators** — CPT/tax, settings page, REST, shortcode (secure
   templates + agent prompts).
4. **Gutenberg block** — block.json + `@wordpress/scripts` wiring + PHP render.
5. **Dev loop** — PHPCS lint, PHPUnit via wp-env, `plugin-package.sh` (.zip,
   `--no-dev`).
6. **Docs + validation** — README/docs/roadmap update, `claude plugin validate`,
   `bash -n` / `node --check` sweep.

## Out of scope (this round)

Wiring into the default HTML→site pipeline; premium-plugin scaffolds;
multisite-specific features; WordPress.org SVN submission automation.

## Unresolved questions

1. **No-composer fallback autoloader** — ship a hand-rolled PSR-4 `require`
   loader, or require Composer for all generated plugins? (Plan assumes fallback.)
2. **Manifest helper** — extend `manifest-lib.sh` to be plugin-aware, or add a
   parallel `plugin-manifest-lib.sh`? (Leaning parallel for separation.)
3. **Test harness depth** — minimal WP-PHPUnit smoke test only, or a fuller
   fixture set in v1?
