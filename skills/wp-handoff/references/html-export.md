# HTML export (handoff sub-step 7)

The contract for the optional single-file HTML render of the handoff package.
`SKILL.md` section 7 orchestrates (trigger + record); this file holds the detail
so `SKILL.md` stays lean. All work is done by `scripts/handoff-html-export.mjs`
(node, zero dependencies) against the markdown the earlier handoff steps already
wrote into the **target** project's `docs/`.

## What it produces

```
docs/handoff-site/
  index.html                 # the ONE html file (nav left, content right)
  assets/
    css/handoff.css          # shipped verbatim from the skill template
    js/handoff.js            # nav smooth-scroll + scrollspy + drawer
    img/<flattened>.png      # screenshots copied out of docs/guides/assets/…
```

Template source: `skills/wp-handoff/templates/handoff-site/` (an
`index.template.html` with `{{PROJECT_NAME}}`, `{{NAV}}`, `{{CONTENT}}`,
`{{GENERATED_AT}}`, `{{DOMAIN_NOTE}}` placeholders, plus the css/js copied into
the output `assets/`). One template ⇒ every guide/doc shares the same style.

## What goes in (and what does NOT)

Included, in this fixed order, each as one `<section id>`:

1. `site-handbook.md` → `#handbook`
2. **Guides** group — one sub-section per `handoff.guides.flows[]` (in flow
   order), `#guide-<flow.id>`, titled `flow.title`. Rendered as a collapsible
   nav group.
3. `maintenance-runbook.md` → `#maintenance`
4. `update-backup-strategy.md` → `#update-backup`
5. `monitoring-checklist.md` → `#monitoring`
6. `a11y-known-issues.md` → `#a11y` (only if the file exists)

**`credentials-handoff.md` is deliberately excluded** — it stays markdown-only so
the shared HTML can be handed around without carrying a "where the secrets live"
section. Missing optional docs are simply skipped.

## URL rewrite (never localhost)

Every local origin in the doc text is replaced with the target origin, path/slug
preserved:

- Origins rewritten: `urls.local`, `env.localUrl`, `http://localhost:<env.port>`,
  `http://127.0.0.1:<env.port>`, `http://localhost:8888`, plus a generic
  `http(s)://localhost[:port]` / `127.0.0.1[:port]` net.
- Target origin = `--domain` if passed, else `urls.production` if set, else the
  literal `<your-domain>` placeholder (rendered escaped, so it shows as text).
- After assembly the script asserts no `localhost`/`127.0.0.1` URL survived; if
  one does it exits `5` and writes nothing (defense-in-depth).

Screenshots are page-content captures (no browser URL bar), so no localhost
leaks through the images — only text is rewritten.

## Image re-homing

Each `![alt](rel)` whose target resolves to a real file (relative to its own
doc) is copied into `assets/img/` under a flattened, collision-safe name
(`assets/vi/post/01.png` → `vi-post-01.png`) and its `<img src>` re-pointed.
External/`data:` images are left untouched. A missing source degrades to
`[alt]` text (logged as a warning) — never a crash. In guides **placeholder
mode** the `_pending.svg` placeholder is copied the same way.

## Invocation

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/handoff-html-export.mjs" \
  --manifest wp-build.json --docs docs --out docs/handoff-site \
  --domain "<origin>" [--generated-at "<iso8601>"]
```

`--generated-at` is the only source of the footer timestamp — the script never
calls `Date.now()`, so a re-run with the same inputs yields a **byte-identical**
`index.html` (idempotent, safe to overwrite). `assets/img/` is rebuilt each run
so deleted screenshots do not linger.

Exit codes: `0` exported · `2` bad args / missing or invalid manifest / no docs
found · `5` residual localhost after rewrite.

## Manifest record

```bash
wpbuild_set '.handoff.htmlExport' '{
  "generatedAt": "<iso8601>",
  "output": "docs/handoff-site/index.html",
  "domainMode": "production",   // or "placeholder"
  "sections": ["handbook", "guide-post", "maintenance", "monitoring"],
  "imagesCopied": 12
}'
```

Read the script's summary line (`… N sections, M images, domain <mode> (<origin>)`)
to fill `sections`/`imagesCopied`/`domainMode`.

## Notes

- No new stage id — this is a sub-step of `handoff` (like the guides in
  section 6). The stage set in `references/manifest-contract.md` is unchanged.
- If the guides ran in **placeholder mode**, the export still renders fully; the
  guide images just resolve to the shared `_pending.svg`. Re-run the export
  after a `--force` handoff upgrades those images.
