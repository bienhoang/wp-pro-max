# Xia Analysis: WP Plugin Development Skill Port

## Source Manifest

| Field | Value |
|-------|-------|
| Repository | `alessioarzenton/claude-code-wp-toolkit` |
| Ref | `main` |
| Resolved SHA | `9a90d123f330fa29ad887363299abc71832226c1` |
| Scope | `core/claude/skills/core/wp-plugin-development/SKILL.md` and related context (`wp-rest-api`, `wp-cli-ops`) |

### Source files inventoried

1. `core/claude/skills/core/wp-plugin-development/SKILL.md`
   - Frontmatter: `name: wp-plugin-development`, `user-invocable: false`, always-active rules for plugin work.
   - Focus: plugin architecture, lifecycle (activation/deactivation/uninstall), Settings API, security baseline, data storage, cron, verification checklist, common errors, anti-patterns.

2. `core/claude/skills/core/wp-rest-api/SKILL.md` (context)
   - Frontmatter: `name: wp-rest-api`, `user-invocable: false`.
   - Focus: REST route registration, permission callbacks, schema validation, authentication.

3. `core/claude/skills/community/wp-cli-ops/SKILL.md` (context)
   - Frontmatter: `name: wp-cli-ops`.
   - Focus: WP-CLI safe operations, migrations, cron, cache, DB backup/restore.

## Local Map

- **Project**: `wp-pro-max` — a Claude Code plugin that drives a manifest-driven pipeline (`wp-build.json`) to convert static HTML into a production WordPress site.
- **Pipeline stages**: `analyze → optimize → model → tokens → convert → plugins → scaffold → seed-content → seed-plugin-data → i18n → seo → security → qa → ship → handoff`.
- **Existing plugin development coverage**:
  - `skills/wp-plugin-dev/SKILL.md` — opt-in standalone plugin builder driven by `wp-plugin.json`.
  - `skills/wp-plugin-dev/references/plugin-architecture.md` — skeleton layout, bootstrap, autoloader, registrar marker.
  - `skills/wp-plugin-dev/references/feature-generators.md` — canonical bodies for CPT, taxonomy, settings, REST, shortcode.
  - `skills/wp-plugin-dev/references/block-build.md` — Gutenberg block scaffolding.
  - `skills/wp-plugin-dev/references/tooling.md` — Composer, PHPCS, PHPUnit, packaging.
  - `skills/wp-plugin-dev/references/wp-plugin-manifest.md` — `wp-plugin.json` contract.
  - `commands/plugin.md` — `/wp-pro-max:plugin` command entry point.
  - `agents/wp-plugin-developer.md` — heavy-lifter agent with non-negotiable standards.
  - `schemas/wp-plugin.schema.json` — manifest schema.
  - `scripts/plugin-scaffold.sh`, `plugin-manifest-lib.sh`, `plugin-env-bootstrap.sh`, `plugin-package.sh`.
- **No dedicated always-active plugin-development rules skill exists**.
- **Skill format convention**: `skills/<name>/SKILL.md` with YAML frontmatter (`name`, `description`, `allowed-tools`) plus optional `references/*.md` and `templates/`.

## Source Anatomy

| Layer | Source Behavior | Local Equivalent |
|-------|-----------------|------------------|
| Always-active rules | Markdown skill loaded whenever plugin work is detected | None dedicated; standards live in `agents/wp-plugin-developer.md` |
| Architecture guidance | Single bootstrap, no side-effects on load, dedicated loader, separate admin code | `plugin-architecture.md` covers layout + autoloader; prose guidance is lighter |
| Lifecycle guidance | Activation, deactivation, uninstall, `flush_rewrite_rules`, `uninstall.php` | Not explicitly covered in a reference |
| Settings API guidance | `register_setting` + `sanitize_callback`, sections/fields | `feature-generators.md` has a `SettingsPage` template |
| Security baseline | Input sanitize, output escape, nonce, capability checks, prepared SQL | Embedded in `wp-plugin-developer` agent standards |
| Data storage guidance | Options vs postmeta vs custom tables vs transients; migrations; cron idempotency | Not present as a reference |
| Verification checklist | Pre-ship plugin checklist | Not present |
| Common errors & anti-patterns | Troubleshooting table + "What NOT to do" list | Not present |

## Dependency Matrix

| Component | Source | Local Project | Status |
|-----------|--------|---------------|--------|
| Skill file format (markdown + frontmatter) | `SKILL.md` | `SKILL.md` | **EXISTS** |
| Always-active plugin rules skill | `wp-plugin-development` | None | **NEW** |
| Plugin builder skill | N/A (rules only) | `wp-plugin-dev` | **EXISTS** |
| Plugin architecture reference | In skill body | `plugin-architecture.md` | **EXISTS** |
| Lifecycle guidance | In skill body | Not present | **NEW** |
| Data storage & migrations guidance | In skill body | Not present | **NEW** |
| Settings API reference | In skill body | `feature-generators.md` | **EXISTS** |
| Security baseline | In skill body | Agent standards | **ADAPT** |
| Verification checklist | In skill body | Not present | **NEW** |
| Common errors / anti-patterns | In skill body | Not present | **NEW** |
| License/attribution | GPL-3.0 in repo | MIT in `README.md` | **FLAG** |

## Challenge Questions

### 1. Should the ported feature be a new always-active skill or merged into the existing `wp-plugin-dev` builder skill?
- **Source answer**: Standalone always-active skill (`user-invocable: false`) loaded automatically when plugin work is detected.
- **Local answer**: `wp-plugin-dev` is an opt-in builder skill invoked via `/wp-pro-max:plugin` and delegates to scripts/agents.
- **Risk if wrong**: Merging into `wp-plugin-dev` would overload a command-routing skill with prose rules and break its lean, imperative style. Keeping it separate but not cross-referenced creates two plugin guidance silos and risks conflicting instructions.

### 2. How should the source's PHP 8.2+/modern-closure examples be adapted to local conventions?
- **Source answer**: `declare(strict_types=1);`, closures in main file, spaces for indentation, PHP 8.2+ features.
- **Local answer**: WP Pro Max plugin templates target PHP 7.4+, use WPCS (tabs, Yoda conditions, class-based OOP), and avoid `strict_types` in generated files.
- **Risk if wrong**: Copying source examples verbatim would generate WPCS violations and raise the minimum PHP requirement beyond the project's stated support. Adapting incorrectly could lose the educational value of the examples.

### 3. Should the source's security/lifecycle guidance replace or supplement the existing `wp-plugin-developer` agent standards?
- **Source answer**: Comprehensive security baseline, lifecycle rules, verification checklist, and common errors all in one skill body.
- **Local answer**: `agents/wp-plugin-developer.md` already lists non-negotiable standards but lacks a dedicated reference for lifecycle, data storage, migrations, cron idempotency, and troubleshooting.
- **Risk if wrong**: Replacing agent standards could destabilize the existing feature generators. Supplementing without updating the agent to reference the new skill leaves the guidance disconnected from actual code generation.

### 4. How should placeholder tokens be handled?
- **Source answer**: Uses runtime placeholders like `{{PROJECT_NAME}}` and `{{TEXT_DOMAIN}}` intended to be resolved by Claude at runtime.
- **Local answer**: Scaffolding system uses tokenization tokens like `__SLUG__`, `__NAMESPACE__`, `__TEXTDOMAIN__`, `__CONST_PREFIX__` extracted from reference files.
- **Risk if wrong**: Inconsistent tokens would break `plugin-scaffold.sh` if any examples are extracted as templates, or confuse agents reading the skill.

### 5. What is the license implication of porting GPL-3.0 skill content into the MIT project?
- **Source answer**: Repository is licensed GPL-3.0; skill content is part of the repo.
- **Local answer**: `README.md` states MIT license.
- **Risk if wrong**: Embedding GPL-3.0 documentation into an MIT project may create a license conflict unless the ported content is clearly attributed and the combined work complies with GPL-3.0 terms. The conservative path is to add attribution and keep the ported content self-contained.

### 6. Should the new skill be auto-invoked (always-active) in WP Pro Max?
- **Source answer**: `user-invocable: false` implies always-active when Claude detects relevant context.
- **Local answer**: WP Pro Max skills are typically invoked by name (`/wp-pro-max:<name>`) or auto-invoked by matching description, not declared always-active.
- **Risk if wrong**: Declaring always-active behavior without a project convention for it may cause the skill to fire on theme work or conflict with `wp-plugin-dev`. Leaving it user-invocable only reduces its value for plugin tasks.

## Decision Matrix

| Decision | Source's Way | Our Way | Recommendation |
|----------|--------------|---------|----------------|
| Skill packaging | Always-active core skill in `.claude/skills/core/` | Opt-in builder skill in `skills/wp-plugin-dev/` | **Create a new `skills/wp-plugin-development/` skill** as always-active rules; keep the existing builder untouched |
| PHP conventions | PHP 8.2+, `strict_types`, spaces | PHP 7.4+, WPCS tabs, class OOP | **Adapt examples** to local WPCS/PHP conventions; do not raise minimum PHP version |
| Content integration | Single skill body | Builder + references | **Port as standalone skill** and cross-reference it from `wp-plugin-dev` and `wp-plugin-developer` |
| Placeholder tokens | `{{VAR}}` | `__VAR__` | **Use local `__VAR__` style** only if examples become templates; otherwise use literal example slugs |
| License | GPL-3.0 | MIT | **Add clear GPL-3.0 attribution** in the new skill frontmatter and top-level `LICENSE` note |
| Invocation | Always-active (`user-invocable: false`) | Invoked by name/command | **Keep `user-invocable: false`** to mirror source intent; rely on Claude's skill auto-invocation for plugin-related work |

## Risk Score

**Medium-Low**

- No runtime code, manifest schema, or script changes required.
- Single markdown skill file plus possible reference updates.
- Main risks: (1) creating a second plugin guidance silo if not cross-referenced, (2) license/attribution gap, (3) PHP convention mismatch in examples.
- Rollback is trivial: delete `skills/wp-plugin-development/` and revert any cross-reference edits.
