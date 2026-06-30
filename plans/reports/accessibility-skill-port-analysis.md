# Xia Analysis: Accessibility Skill Port

## Source Manifest

| Field | Value |
|-------|-------|
| Repository | `alessioarzenton/claude-code-wp-toolkit` |
| Ref | `main` |
| Resolved SHA | `9a90d123f330fa29ad887363299abc71832226c1` |
| Scope | Accessibility skill artifacts |

### Source files inventoried

1. `core/claude/skills/community/accessibility/SKILL.md`  
   - Frontmatter: `name: accessibility`, user-invocable, GPL-3.0  
   - Focus: general WCAG 2.1 guidelines, POUR principles, code examples, testing commands, impact-ranked issues.

2. `core/claude/skills/core/accessibility/SKILL.md`  
   - Frontmatter: `name: accessibility`, `user-invocable: false`  
   - Focus: always-active WCAG 2.2 AA rules for Blade/Sage + Tailwind 4 generated markup.

3. `core/claude/skills/core/accessibility/a11y-checklist.md`  
   - Focus: pre-release manual checklist (12 sections, WCAG 2.2 AA).

## Local Map

- **Project**: `wp-pro-max` — a Claude Code plugin that drives a manifest-driven pipeline (`wp-build.json`) to convert static HTML into a production WordPress site.
- **Pipeline stages**: `analyze → optimize → model → tokens → convert → plugins → scaffold → seed-content → seed-plugin-data → i18n → seo → security → qa → ship → handoff`.
- **Existing a11y coverage**:
  - `skills/html-optimization/SKILL.md` — applies a11y fixes during `optimize` stage.
  - `skills/wp-qa/SKILL.md` — runs WCAG checks as part of the QA gate.
  - `skills/wp-qa/references/accessibility-checklist.md` — manual fallback checklist (WCAG 2.1 AA).
  - `skills/html-optimization/references/accessibility-checklist.md` — optimize-stage checklist (WCAG 2.1 AA).
- **No dedicated `accessibility` skill exists**.
- **Skill format convention**: `skills/<name>/SKILL.md` with YAML frontmatter (`name`, `description`, `allowed-tools`) plus optional `references/*.md` and `templates/`.

## Source Anatomy

| Layer | Source Behavior | Local Equivalent |
|-------|-----------------|------------------|
| Core rules | Markdown reference guide for generated markup | Currently embedded in `html-optimization` and `wp-qa` |
| Checklist | Manual pre-release checklist (WCAG 2.2 AA) | Exists as WCAG 2.1 AA in two places |
| Code examples | HTML, CSS, JS, Blade/Tailwind snippets | Need WordPress/strategy-aware examples |
| Testing guidance | Lighthouse, axe-core, screen reader commands | Not present as a skill-level reference |
| Known-issues tracker | `docs/a11y-known-issues.md` template | Not present |

## Dependency Matrix

| Component | Source | Local Project | Status |
|-----------|--------|---------------|--------|
| Skill file format (markdown + frontmatter) | `SKILL.md` | `SKILL.md` | **EXISTS** |
| WCAG 2.2 AA guidance | Core skill + checklist | WCAG 2.1 only | **ADAPT** |
| Generic a11y audit skill (user-invocable) | Community skill | None | **NEW** |
| Always-active markup rules | Core skill | Embedded in stage skills | **ADAPT** |
| Sage/Blade/Tailwind examples | Core skill | Multi-strategy pipeline | **ADAPT** |
| Manual pre-release checklist | `a11y-checklist.md` | Partial, duplicated in two skills | **CONSOLIDATE** |
| Known-issues tracker | `docs/a11y-known-issues.md` template | None | **OPTIONAL** |
| License/attribution | GPL-3.0 in frontmatter | Unknown/unspecified | **FLAG** |

## Challenge Questions

### 1. Which WCAG version should the ported skill target?
- **Source answer**: Mixed — community skill is WCAG 2.1; core skill and checklist are WCAG 2.2 AA.
- **Local answer**: Existing checklists are WCAG 2.1 AA.
- **Risk if wrong**: Staying on 2.1 may miss newer requirements (e.g., focus not obscured, pointer gesture cancellation) that clients increasingly expect. Adopting 2.2 without checking downstream tooling may cause false confidence if `a11y-axe.mjs` rules do not yet cover all 2.2 criteria.

### 2. How stack-specific should the ported skill be?
- **Source answer**: Core skill is tightly bound to Sage + Blade + Tailwind 4 (`app.blade.php`, `{{PREFIX}}:` utilities, `language_attributes()`).
- **Local answer**: wp-pro-max supports `classic-acf`, `block-fse`, and `page-builder` strategies.
- **Risk if wrong**: Copying Blade/Tailwind examples verbatim makes the skill irrelevant for classic/block-builder projects. Making it too generic loses concrete copy-paste value for Sage users.

### 3. Should this be a user-invocable skill, an always-active rule skill, or a pipeline stage?
- **Source answer**: Both — community skill is user-invocable; core skill is always-active (`user-invocable: false`).
- **Local answer**: Skills are stage-oriented and auto-invoked by name (`wp-pro-max:<name>`). No "always-active" skill mechanism is currently used.
- **Risk if wrong**: Modeling it as a new pipeline stage (`a11y`) inserts work between `optimize` and `qa`, changing the manifest contract. Leaving it only user-invocable means automated builds will not benefit from it.

### 4. How should the new skill relate to existing a11y content in `html-optimization` and `wp-qa`?
- **Source answer**: Standalone skill with its own checklist and known-issues doc.
- **Local answer**: A11y is distributed across `optimize` and `qa` stages with duplicated checklists.
- **Risk if wrong**: Adding a third source of a11y guidance creates drift and conflicting instructions. Replacing existing checklists with references to the new skill requires careful editing to preserve stage-specific output contracts.

### 5. What is the license implication of porting GPL-3.0 skill content?
- **Source answer**: Frontmatter states `license: GPL-3.0`.
- **Local answer**: No `LICENSE` file or license section was found in the local repo root or README.
- **Risk if wrong**: If the local project is not GPL-3.0-compatible, embedding the source skill content may create a license conflict. Even for documentation, retaining attribution and matching license is the conservative path.

### 6. Should the known-issues tracker be ported as well?
- **Source answer**: Source installer generates `.claude/docs/a11y-known-issues.md`.
- **Local answer**: wp-pro-max writes project docs into the *target* WordPress project's `docs/`, not into this plugin repo.
- **Risk if wrong**: Porting the doc template into the plugin repo would violate the convention that `docs/` is working output only. Skipping it loses a useful handoff artifact.

## Decision Matrix

| Decision | Source's Way | Our Way | Recommendation |
|----------|--------------|---------|----------------|
| WCAG target | 2.1 (community) / 2.2 (core) | 2.1 AA | **Adopt WCAG 2.2 AA** and note which criteria are manual-only |
| Stack examples | Sage/Blade/Tailwind 4 | Multi-strategy | **Generic HTML/CSS/JS + strategy callouts** (classic/block/Sage) |
| Invocation | User-invocable + always-active | Stage skills | **User-invocable skill** referenced by `optimize` and `qa` |
| Integration | Standalone | Distributed | **Consolidate checklists** in the new skill; existing stages reference it |
| Known-issues doc | Project doc template | Not present | **Add reference template** for the handoff stage to emit into target `docs/` |
| License | GPL-3.0 | Unknown | **Preserve GPL-3.0 attribution** and recommend adding a top-level `LICENSE` |

## Risk Score

**Medium-Low**

- No runtime code or manifest schema changes required.
- Main risks: (1) creating a third source of a11y truth if existing skills are not updated, (2) license/attribution gap, (3) stack examples mismatch.
- Rollback is trivial: delete `skills/accessibility/` and revert the two reference edits.
