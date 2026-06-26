---
phase: 4
title: "Gutenberg block"
status: done
effort: ""
priority: P2
dependencies: [2, 3]
---

# Phase 4: Gutenberg block

## Overview

Add `block` as one more `add <feature>` generator — `block.json`, a
`@wordpress/scripts` build, and a PHP render callback — **reusing Phase 3's
dispatcher and registrar marker**, gated so the Node toolchain is pulled only when
a block is requested.

## Requirements

- Functional: `/wp-pro-max:plugin add block <name>` scaffolds a block (block.json
  + `src/index.js`/`edit.js` + PHP `render_callback`), wires `package.json` with
  `@wordpress/scripts`, and registers via `register_block_type` at the **same
  Plugin.php marker** Phase 3 uses.
- Non-functional: core (non-block) plugins stay Node-free; block build is the
  only path introducing `package.json`/`node_modules`.

## Architecture

Block is the `block` member of the existing `features[]` enum, so it **extends
Phase 3's `add` dispatch and atomic ordering (Red-team #22)** rather than
re-implementing them — avoiding a second independent editor of `Plugin.php`.
Sources under `blocks/<name>/src/` compile via `wp-scripts build` to
`blocks/<name>/build/`. First `add block` creates `package.json`; later blocks
reuse it. `wp-plugin.json` `tooling.blockBuild` flips true. Bodies live in
`references/block-build.md` (no `templates/` tree, Red-team #11).

```
blocks/<name>/
  block.json            # apiVersion 3; render via PHP callback
  src/index.js          # registerBlockType
  src/edit.js           # editor component
  src/style.scss / editor.scss
package.json            # @wordpress/scripts: scripts.build/start
src/Blocks/<Name>Block.php   # register_block_type( build dir ), render_callback (registered at marker)
```

## Related Code Files

- Modify: `scripts/plugin-scaffold.sh` — `add block` branch of the Phase 3 dispatch; create `package.json` on first block.
- Create: `skills/wp-plugin-dev/references/block-build.md` — `@wordpress/scripts` setup, build/start, registration, **and bodies** (`block.json`, `index.js`, `edit.js`, `Block.php`, `package.json`).
- Modify: `skills/wp-plugin-dev/SKILL.md` — document `add block` + the Node prerequisite.
- Modify: `agents/wp-plugin-developer.md` — block render-callback escaping note (standards only).

## Implementation Steps

1. **Reuse the Phase 3 path** — `add block` runs through the same dispatcher,
   marker precondition (fail-loud if absent), verified insert, and
   manifest-append-last ordering; only the generated artifacts differ.
2. **Bodies** — `block.json` (`apiVersion: 3`, `textdomain`, `editorScript`,
   `style`, dynamic via PHP `render` callback), `src/index.js`
   (`registerBlockType`), `src/edit.js` (`useBlockProps`), SCSS stubs.
3. **PHP registration** — `src/Blocks/<Name>Block.php` calls
   `register_block_type( plugin_dir . '/blocks/<name>/build' )` on `init` at the
   marker; dynamic `render_callback` escapes all output.
4. **Node tooling** — on first `add block`, write `package.json` with
   `@wordpress/scripts` and `scripts: { build: "wp-scripts build", start:
   "wp-scripts start" }`; idempotent if present.
5. **Gating + packaging awareness (Red-team #15)** — `.gitignore` excludes
   `node_modules/` and `blocks/*/build/`; record in `block-build.md` that the
   compiled `build/` is git-ignored but is **runtime-required**, so Phase 5
   packaging must force-include it (cross-reference Phase 5 step).

## Success Criteria

- [ ] `add block hero` scaffolds `blocks/hero/` + `package.json` + `Blocks/HeroBlock.php` via the Phase 3 dispatcher (no duplicate dispatch code).
- [ ] **In-env:** `npm i && npm run build` produces `blocks/hero/build/`; block
      appears in the editor and renders on the front end via the PHP callback with
      escaped output.
- [ ] Plugins without a block have **no** `package.json`/`node_modules`.
- [ ] Marker precondition + manifest-append-last apply to `block` exactly as the
      other features.

## Risk Assessment

- **Two phases editing `Plugin.php` independently** (Red-team #22) → block reuses
  Phase 3's dispatcher/marker/ordering; no separate registrar editor.
- **JSX not parseable by `node --check`** → rely on `wp-scripts build` for JS
  validation; keep any pure-`.js` helpers checkable.
- **Dependency bloat** → strictly gated behind `add block`.
- **Compiled `build/` dropped from package** → handled in Phase 5 (force-include
  + assertion).
