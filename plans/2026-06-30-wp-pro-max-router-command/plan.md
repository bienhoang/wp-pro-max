---
title: "WP Pro Max Natural-Language Router Command"
description: "Add a root `/wp-pro-max` command that classifies a free-form user request and dispatches to the appropriate existing command, skill, or agent."
status: done
priority: P2
branch: "main"
tags: [command, routing, natural-language, agent, skill]
blockedBy: []
blocks: []
created: "2026-06-30T13:30:00.000+07:00"
createdBy: "ck:cook"
source: skill
---

# WP Pro Max Natural-Language Router Command

## Overview

Add a root command `/wp-pro-max <request>` that acts as a natural-language entry point for the kit. It classifies the request, then dispatches to one of the existing commands (`build`, `status`, `env`, `init`, `plugin`, `a11y-audit`, `figma`, `component`, `site-editor`), directly invokes a skill (`wp-pro-max:<skill>`), or spawns an agent (`wp-theme-developer`, `wp-data-engineer`, `wp-deployer`, `wp-plugin-developer`, `a11y-checker`, `figma-analyzer`).

The router is a thin coordinator: it does not reimplement business logic, it only decides *who* should handle the request.

## Boundaries & Scope Decisions

| In scope | Out of scope (deferred) |
|----------|------------------------|
| `commands/wp-pro-max.md` | Reimplementing existing skills/agents |
| `scripts/wp-pro-max-router-lib.sh` helper | Modifying `commands/build.md` or other commands |
| LLM-based intent classifier via `Task(subagent_type="coder")` | Persistent learning / training data |
| Dispatch to commands, skills, and agents | Multi-turn conversational router state |
| Validation with `claude plugin validate .` | Marketplace listing changes |

## Non-negotiable constraints

- Must follow existing command conventions: YAML frontmatter, bash body, manifest-driven where relevant.
- Must use existing invocation primitives: `Skill(name="wp-pro-max:<skill>", arguments="...")` and `Task(subagent_type="coder", prompt="...")`.
- Must not change `wp-build.schema.json` or `wp-plugin.schema.json`.
- Must be safe: classify-only subagent has no write tools; the command itself only dispatches.
- Must pass `claude plugin validate .`.

## Routing targets

| Category | Examples |
|----------|----------|
| Commands | `build`, `status`, `env`, `init`, `plugin`, `a11y-audit`, `figma`, `component`, `site-editor` |
| Skills | `html-analysis`, `html-optimization`, `theme-conversion`, `plugin-selection`, `wp-scaffold`, `content-seeding`, `plugin-data-seeding`, `wp-i18n`, `wp-seo`, `wp-security`, `wp-qa`, `wp-ship`, `wp-handoff`, `wp-env-setup`, `section-redesign`, `content-enrichment`, `pre-conversion-qa` |
| Agents | `wp-theme-developer`, `wp-data-engineer`, `wp-deployer`, `wp-plugin-developer`, `a11y-checker`, `figma-analyzer` |

## Proposed flow

1. Parse `$ARGUMENTS`.
2. If empty, print a concise help/status suggestion (same as `/wp-pro-max:status` when a manifest exists).
3. Spawn a lightweight classifier subagent with the user phrase + the routing table above; return exactly one target slug + optional reasoning.
4. Validate the returned slug against an allowlist.
5. Dispatch:
   - Commands → re-issue as `/wp-pro-max:<command> <remaining-args>` via `Skill(name="wp-pro-max:<command>", arguments="...")`.
   - Skills → `Skill(name="wp-pro-max:<skill>", arguments="...")`.
   - Agents → `Task(subagent_type="coder", description="...", prompt="You are the <agent-name> agent...")`.
6. If classification is uncertain, ask the user for clarification instead of guessing.

## Phases

| Phase | Name | Status | Priority | Dependencies |
|-------|------|--------|----------|--------------|
| 1 | [Design](./phase-01-design.md) | planned | P1 | — |
| 2 | [Router helper script](./phase-02-router-lib.md) | planned | P1 | 1 |
| 3 | [Command authoring](./phase-03-command.md) | planned | P1 | 1, 2 |
| 4 | [Validation](./phase-04-validation.md) | planned | P2 | 3 |

## Acceptance criteria

- `claude plugin validate .` passes.
- `/wp-pro-max` with no arguments shows helpful next steps.
- `/wp-pro-max "build a site from ./examples/sample-site"` dispatches to `/wp-pro-max:build ./examples/sample-site`.
- `/wp-pro-max "audit accessibility"` dispatches to `/wp-pro-max:a11y-audit all`.
- `/wp-pro-max "fix the header template"` spawns `wp-theme-developer` agent.
- `/wp-pro-max "seed the team members"` spawns `wp-data-engineer` agent.
- Unknown/ambiguous requests produce a clarifying question, not a wrong dispatch.
