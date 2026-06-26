# Delegating to the installed `claude-seo` plugin

`claude-seo` is a full SEO skill suite. When present, it is the source of truth
for analysis, schema generation, sitemap validation, and technical audits — this
stage orchestrates it and applies results to WordPress, rather than duplicating
its logic.

## Detect

`claude-seo` ships skills under the plugin namespace `claude-seo:*`. Check for
them before deciding fallback:

```bash
# Plugin-installed skills location (varies by Claude Code version):
ls "$HOME/.claude/plugins"/*/skills/seo* 2>/dev/null
ls "$HOME/.claude/skills"/seo* 2>/dev/null
# Or simply: if a claude-seo:* skill is listed as available, delegate.
```

## Skill → task map

| Our need | Delegate to | What it returns |
|----------|-------------|-----------------|
| Site/page audit, E-E-A-T, GEO | `claude-seo:seo` (or `seo-audit` for crawl) | Findings + health score |
| JSON-LD detect/validate/generate | `claude-seo:seo-schema` | Validated JSON-LD blocks |
| robots, canonicals, indexability, CWV crossover | `claude-seo:seo-technical` | Technical issue list + fixes |
| XML sitemap validate/generate | `claude-seo:seo-sitemap` | Sitemap status + generated XML |
| Page meta/title quality | `claude-seo:seo-page` | Per-page on-page recommendations |

## Orchestration pattern

1. **Plan here**: build the per-page meta map and the entity facts
   (Organization name/logo/socials from `project` + manifest, page roles → schema
   type) — these are inputs the claude-seo skills need.
2. **Generate** structured data with `claude-seo:seo-schema`; pass the entity
   facts and page list. Receive validated JSON-LD.
3. **Apply** to WordPress: write meta via the SEO plugin postmeta keys
   (`seo-plugin-config.md`) or the head fallback; inject the returned JSON-LD.
4. **Validate**: run `claude-seo:seo` (single-page or audit) against `urls.local`
   to score the applied result; capture findings.
5. **Sitemap/technical**: confirm with `claude-seo:seo-sitemap` and
   `claude-seo:seo-technical`; fix reachability/robots issues they surface.
6. **Record**: set `seo.metaApplied`, `seo.schemaTypes` (exactly what was
   emitted), `seo.sitemap`. Keep the claude-seo findings in the stage notes so
   the orchestrator can route content fixes if E-E-A-T/quality gaps were found.

## When NOT to delegate

- `claude-seo` not installed → use the direct WP-CLI + `theme-head-fallback.php`
  path in `SKILL.md`.
- Throwaway local demo where SEO is out of scope → set `seo` progress `skipped`.

Never re-implement schema validation or audit scoring here when `claude-seo`
can do it — that duplicates a maintained capability (DRY).
