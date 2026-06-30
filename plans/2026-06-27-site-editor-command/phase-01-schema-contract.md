---
phase: 1
title: "Schema & Contract"
status: done
priority: P1
dependencies: []
---

# Phase 1: Schema & Contract

## Overview

Extend `schemas/wp-build.schema.json` with a new top-level `siteEditor` object that records the outputs and state of the three new child skills. Update `references/manifest-contract.md` to list the three new stage ids and their contract.

## Requirements

- Functional: `schemas/wp-build.schema.json` gains a `siteEditor` object with `redesign`, `contentEnrichment`, and `preConversionQa` sub-trees matching the brainstorm contract.
- Functional: `references/manifest-contract.md` documents `section-redesign`, `content-enrichment`, and `pre-conversion-qa` as non-gating, optional stages that operate on `optimization.outputDir`.
- Non-functional: backward compatible — `siteEditor` is optional; existing manifests validate unchanged (`additionalProperties: true` at root).

## Architecture

`siteEditor` shape:

```json
"siteEditor": {
  "type": "object",
  "description": "Output of /wp-pro-max:site-editor child skills. Edits happen on optimization.outputDir only.",
  "properties": {
    "redesign": {
      "type": "object",
      "properties": {
        "appliedChanges": { "type": "array", "items": { "type": "object" } },
        "backupDir": { "type": "string" },
        "lastModified": { "type": "string" }
      }
    },
    "contentEnrichment": {
      "type": "object",
      "properties": {
        "addedPages": { "type": "array", "items": { "type": "object" } },
        "changes": { "type": "array", "items": { "type": "object" } },
        "lastModified": { "type": "string" }
      }
    },
    "preConversionQa": {
      "type": "object",
      "properties": {
        "passed": { "type": "boolean" },
        "mode": { "enum": ["quick", "thorough"] },
        "a11y": { "type": "object" },
        "responsive": { "type": "object" },
        "brandConsistency": { "type": "object" },
        "htmlValidity": { "type": "object" },
        "lastRun": { "type": "string" }
      }
    }
  }
}
```

Stage ids added to the contract:
- `section-redesign` — manipulates sections in optimized HTML.
- `content-enrichment` — adds pages and enriches copy.
- `pre-conversion-qa` — lightweight checks before `theme-conversion`.

## Related Code Files

- Modify: `schemas/wp-build.schema.json`
- Modify: `references/manifest-contract.md`
- Create: `plans/2026-06-27-site-editor-command/fixtures/site-editor-manifest.json` (test fixture)

## Implementation Steps

1. **TDD — write the fixture first.** Create a manifest JSON sample containing `siteEditor.redesign`, `siteEditor.contentEnrichment`, and `siteEditor.preConversionQa` populated with realistic sample data.
2. **Run validation before schema changes** to confirm it currently fails (expected failure proves the test is useful).
3. Edit `schemas/wp-build.schema.json`:
   - Add `"siteEditor": { ... }` under `properties`.
   - Ensure no `required` field references `siteEditor`.
4. Re-run validation; fixture should now pass.
5. Edit `references/manifest-contract.md`:
   - Add the three stage ids to the canonical list.
   - Add a short paragraph that these stages are optional, run outside the main pipeline, do not gate `ship`, and must not mutate `source/`.

## Test-First Structure

```bash
# Fixture exists and currently FAILS validation
node -e "const Ajv=require('ajv'); const ajv=new Ajv(); const validate=ajv.compile(require('./schemas/wp-build.schema.json')); const fixture=require('./plans/.../fixtures/site-editor-manifest.json'); if(!validate(fixture)) { console.error(validate.errors); process.exit(1); }"
```

After schema edits, the same command must exit 0. Also assert `siteEditor` is absent from the top-level `required` array.

## Success Criteria

- [ ] `schemas/wp-build.schema.json` contains a documented `siteEditor` object.
- [ ] The test fixture validates cleanly against the updated schema.
- [ ] `references/manifest-contract.md` lists the three new stage ids and their non-gating, source-read-only contract.
- [ ] Existing manifests without `siteEditor` still validate.

## Risk Assessment

- **Risk:** Schema edit collides with pending WooCommerce catalog plan (`commerce` block addition).  
  **Mitigation:** Keep the `siteEditor` block independent; use `jq` or small targeted JSON edits; do not reformat the whole file in a way that creates merge conflicts.
