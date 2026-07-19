#!/usr/bin/env node
// handoff-html-export.mjs — render the handoff package into ONE self-contained
// HTML site (index.html + assets/) for the client.
//
// Reads the markdown the handoff stage already generated into the target
// project's docs/ (site handbook, per-flow guides, maintenance, backups,
// monitoring, a11y) plus the captured guide screenshots, then:
//   - converts each doc to HTML (scripts/lib/markdown-mini.mjs — no deps),
//   - copies referenced screenshots into <out>/assets/img/ and re-points them,
//   - rewrites every local/localhost URL to the target domain (never localhost),
//   - assembles a left-nav / right-content page from the shipped template.
//
// The credentials handoff doc is DELIBERATELY excluded — it stays markdown-only.
//
// Usage:
//   node handoff-html-export.mjs [--manifest wp-build.json] [--docs docs] \
//     [--out docs/handoff-site] [--domain <origin>] [--generated-at <iso>]
//
//   --domain  target origin for links; defaults to urls.production, else the
//             literal "<your-domain>". Path/slug after the origin is preserved.
//
// Deterministic: given the same inputs it emits a byte-identical index.html
// (no Date.now() in the render; the timestamp is passed in via --generated-at).
//
// Exit codes:
//   0  exported
//   2  bad arguments / manifest missing or invalid
//   5  residual localhost URL detected after rewrite (guard failed)
//
// No external dependencies: node stdlib only (fs, path, url).

import {
  readFileSync, writeFileSync, mkdirSync, copyFileSync, existsSync, rmSync,
} from "node:fs";
import { resolve, join, dirname, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { markdownToHtml, escapeHtml } from "./lib/markdown-mini.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const TEMPLATE_DIR = resolve(HERE, "../skills/wp-handoff/templates/handoff-site");
const PLACEHOLDER_DOMAIN = "<your-domain>";
const OUTPUT_MARKER = "wp-pro-max:handoff-site"; // present in the template head
// Case-insensitive, covers scheme + optional port + IPv6 loopback. Used for
// both the rewrite and the residual guard so nothing local reaches the client.
const LOCAL_URL_RE = /https?:\/\/(?:localhost|127\.0\.0\.1|\[::1\])(?::\d+)?/gi;

// Small deterministic hash (djb2) for disambiguating flattened image names on
// collision — keeps re-runs byte-stable without a crypto import.
function shortHash(s) {
  let h = 5381;
  for (let i = 0; i < s.length; i++) h = ((h << 5) + h + s.charCodeAt(i)) >>> 0;
  return h.toString(36).slice(0, 6);
}

// Is `abs` inside `root` (or equal to it)? Prevents `![](../../.env)` escapes.
function isInside(root, abs) {
  return abs === root || abs.startsWith(root.endsWith(sep) ? root : root + sep);
}

// ---------------------------------------------------------------------------
// Args
// ---------------------------------------------------------------------------

function parseArgs(argv) {
  const args = { manifest: "wp-build.json", docs: "docs", out: "docs/handoff-site",
    domain: "", generatedAt: "" };
  for (let i = 0; i < argv.length; i++) {
    let a = argv[i], inline = null;
    if (a.startsWith("--") && a.includes("=")) {
      const eq = a.indexOf("="); inline = a.slice(eq + 1); a = a.slice(0, eq);
    }
    const val = () => (inline !== null ? inline : argv[++i]);
    switch (a) {
      case "--manifest": args.manifest = val(); break;
      case "--docs": args.docs = val(); break;
      case "--out": args.out = val(); break;
      case "--domain": args.domain = val(); break;
      case "--generated-at": args.generatedAt = val(); break;
      case "-h": case "--help": args.help = true; break;
      default:
        console.error(`handoff-html-export: unknown argument "${argv[i]}"`);
        args._bad = true;
    }
  }
  return args;
}

function usage() {
  console.error(
    "Usage: node handoff-html-export.mjs [--manifest wp-build.json] [--docs docs] " +
    "[--out docs/handoff-site] [--domain <origin>] [--generated-at <iso>]");
}

function die(code, msg) { if (msg) console.error(`handoff-html-export: ${msg}`); process.exit(code); }

// ---------------------------------------------------------------------------
// Manifest + origin
// ---------------------------------------------------------------------------

function readManifest(path) {
  let raw;
  try { raw = readFileSync(resolve(path), "utf8"); }
  catch (err) { die(2, `cannot read manifest "${path}": ${err.message}`); }
  try { return JSON.parse(raw); }
  catch (err) { die(2, `manifest is not valid JSON: ${err.message}`); }
}

function get(obj, dotted, fallback) {
  return dotted.split(".").reduce((o, k) => (o == null ? o : o[k]), obj) ?? fallback;
}

// The set of local origins to rewrite away. Explicit manifest values plus a
// generic localhost/127.0.0.1 net so nothing local leaks into a client doc.
function localOrigins(m) {
  const set = new Set();
  const add = (v) => { if (v && typeof v === "string") set.add(v.replace(/\/+$/, "")); };
  add(get(m, "urls.local"));
  add(get(m, "env.localUrl"));
  const port = get(m, "env.port");
  if (port) { add(`http://localhost:${port}`); add(`http://127.0.0.1:${port}`); }
  add("http://localhost:8888");
  return [...set];
}

function resolveOrigin(m, cliDomain) {
  const prod = get(m, "urls.production");
  if (cliDomain) return { origin: cliDomain.replace(/\/+$/, ""), mode: cliDomain.includes(PLACEHOLDER_DOMAIN) ? "placeholder" : "production" };
  if (prod && typeof prod === "string") return { origin: prod.replace(/\/+$/, ""), mode: "production" };
  return { origin: PLACEHOLDER_DOMAIN, mode: "placeholder" };
}

// ---------------------------------------------------------------------------
// Section collection
// ---------------------------------------------------------------------------

// Fixed order. credentials-handoff is intentionally NOT listed. a11y is
// conditional on the file existing. Guides expand from handoff.guides.flows[].
const CORE_DOCS = [
  { id: "handbook", title: "Site Handbook", file: "site-handbook.md", required: true },
  { id: "maintenance", title: "Maintenance Runbook", file: "maintenance-runbook.md", required: false },
  { id: "update-backup", title: "Updates & Backups", file: "update-backup-strategy.md", required: false },
  { id: "monitoring", title: "Monitoring Checklist", file: "monitoring-checklist.md", required: false },
  { id: "a11y", title: "Accessibility — Known Issues", file: "a11y-known-issues.md", required: false },
];

function collectSections(m, docsDir) {
  const sections = [];
  const handbook = CORE_DOCS[0];
  const handbookPath = join(docsDir, handbook.file);
  if (existsSync(handbookPath)) {
    sections.push({ ...handbook, group: null, path: handbookPath });
  }

  // Guides group — one sub-section per recorded flow, in flow order.
  const flows = get(m, "handoff.guides.flows", []) || [];
  for (const f of flows) {
    if (!f || !f.doc) continue;
    const p = resolve(f.doc);
    if (!existsSync(p)) continue;
    sections.push({
      id: `guide-${f.id}`,
      title: f.title || f.id,
      group: "guides",
      path: p,
    });
  }

  // Remaining core docs (skip handbook, already added).
  for (const d of CORE_DOCS.slice(1)) {
    const p = join(docsDir, d.file);
    if (existsSync(p)) sections.push({ ...d, group: null, path: p });
  }
  return sections;
}

// ---------------------------------------------------------------------------
// Image re-homing + URL rewrite
// ---------------------------------------------------------------------------

// Rewrite <img src> that point at on-disk files (relative to the doc) into
// copies under <out>/assets/img/, queuing the copies. External/absolute URLs
// are left untouched. Missing files: drop the <img>, keep alt as text.
function rehomeImages(html, docDir, docsRoot, imgOutDir, copies, warnings) {
  return html.replace(/<img src="([^"]+)" alt="([^"]*)"([^>]*)>/g, (m, src, alt, rest) => {
    if (/^(https?:)?\/\//i.test(src) || src.startsWith("data:")) return m; // external
    const abs = resolve(docDir, src);
    // Never read/copy a file outside the docs tree (blocks ../../.env escapes).
    if (!isInside(docsRoot, abs)) {
      warnings.push(`skipped out-of-tree image ${src} (referenced from ${docDir})`);
      return alt ? `<p class="img-missing">[${escapeHtml(alt)}]</p>` : "";
    }
    if (!existsSync(abs)) {
      warnings.push(`missing image ${src} (referenced from ${docDir})`);
      return alt ? `<p class="img-missing">[${escapeHtml(alt)}]</p>` : "";
    }
    // Flatten the relative path into a collision-safe name.
    const rel = src.replace(/^\.\/+/, "").replace(/^assets\//, "").replace(/[\\/]/g, "-");
    let name = rel.replace(/[^A-Za-z0-9._-]/g, "_");
    let dest = join(imgOutDir, name);
    // Distinct sources that flatten to the same name must not clobber.
    if (copies.has(dest) && copies.get(dest) !== abs) {
      name = `${shortHash(abs)}-${name}`;
      dest = join(imgOutDir, name);
    }
    copies.set(dest, abs);
    return `<img src="assets/img/${name}" alt="${alt}"${rest}>`;
  });
}

// Replace every local origin with the target origin, plus a generic localhost /
// 127.0.0.1 net. Preserves the path after the origin.
function rewriteUrls(html, origins, target) {
  let out = html;
  for (const o of origins) {
    if (!o) continue;
    out = out.split(o).join(target);
  }
  // Generic net: any remaining localhost / loopback origin (any case, IPv6 too).
  out = out.replace(LOCAL_URL_RE, target);
  return out;
}

// ---------------------------------------------------------------------------
// Nav + template
// ---------------------------------------------------------------------------

// Emit the nav in the SAME order as the content: each non-guide section inline,
// and the whole collapsible Guides group at the position of the first guide.
function buildNav(sections) {
  const guides = sections.filter((s) => s.group === "guides");
  const parts = ['<ul class="sidenav__list">'];
  let guidesEmitted = false;
  for (const s of sections) {
    if (s.group === "guides") {
      if (!guidesEmitted) {
        parts.push('<li class="nav-group">');
        parts.push('<button class="nav-group__toggle" aria-expanded="true">Step-by-step guides <span class="chevron">▾</span></button>');
        parts.push('<ul class="nav-group__items">');
        for (const g of guides) parts.push(`<li><a href="#${g.id}">${escapeHtml(g.title)}</a></li>`);
        parts.push("</ul></li>");
        guidesEmitted = true;
      }
      continue; // individual guides live inside the group
    }
    parts.push(`<li><a href="#${s.id}">${escapeHtml(s.title)}</a></li>`);
  }
  parts.push("</ul>");
  return parts.join("\n");
}

function renderTemplate(tpl, slots) {
  return tpl
    .replace(/\{\{PROJECT_NAME\}\}/g, slots.projectName)
    .replace(/\{\{GENERATED_AT\}\}/g, slots.generatedAt)
    .replace(/\{\{DOMAIN_NOTE\}\}/g, slots.domainNote)
    .replace(/\{\{NAV\}\}/g, slots.nav)
    .replace(/\{\{CONTENT\}\}/g, slots.content);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) { usage(); process.exit(0); }
  if (args._bad) { usage(); process.exit(2); }

  const m = readManifest(args.manifest);
  const docsDir = resolve(args.docs);
  const outDir = resolve(args.out);
  const imgOutDir = join(outDir, "assets", "img");
  const { origin, mode } = resolveOrigin(m, args.domain);
  const origins = localOrigins(m);
  const projectName = escapeHtml(get(m, "project.name", "Website"));

  const sections = collectSections(m, docsDir);
  if (sections.length === 0) die(2, `no handoff docs found under ${args.docs} — run the handoff stage first`);

  const copies = new Map(); // destPath -> srcPath
  const warnings = [];
  const rendered = [];

  for (const s of sections) {
    const md = readFileSync(s.path, "utf8");
    let html = markdownToHtml(md);
    html = rehomeImages(html, dirname(s.path), docsDir, imgOutDir, copies, warnings);
    // The target is inserted into already-escaped HTML, so escape it too — this
    // is a no-op for real domains but makes the "<your-domain>" placeholder
    // render as text instead of being parsed as an unknown tag.
    html = rewriteUrls(html, origins, escapeHtml(origin));
    rendered.push(`<section id="${s.id}" class="doc-section">\n${html}\n</section>`);
  }

  const content = rendered.join("\n\n");

  // Guard: nothing local must survive into the client HTML (same matcher as the
  // rewrite, so this only fires on a form the rewrite genuinely missed).
  LOCAL_URL_RE.lastIndex = 0;
  if (LOCAL_URL_RE.test(content)) {
    die(5, "residual localhost URL after rewrite — refusing to emit");
  }

  const domainNote = mode === "placeholder"
    ? `Links use <code>${escapeHtml(PLACEHOLDER_DOMAIN)}</code> as a placeholder — replace it with your live domain.`
    : `Links point to <code>${escapeHtml(origin)}</code>.`;

  const tpl = readFileSync(join(TEMPLATE_DIR, "index.template.html"), "utf8");
  const indexHtml = renderTemplate(tpl, {
    projectName,
    generatedAt: escapeHtml(args.generatedAt || "from the site build manifest"),
    domainNote,
    nav: buildNav(sections),
    content,
  });

  // Safety: --out is caller-supplied and we rmSync its assets/img below. Refuse
  // if outDir already holds an index.html we did NOT generate (no marker), so a
  // stray `--out .` can never wipe a real directory's images.
  const outIndex = join(outDir, "index.html");
  if (existsSync(outIndex) && !readFileSync(outIndex, "utf8").includes(OUTPUT_MARKER)) {
    die(2, `refusing to overwrite ${args.out}: it has a non-generated index.html — pass a dedicated --out dir`);
  }

  // Write out. Fresh assets/img so removed screenshots do not linger.
  mkdirSync(join(outDir, "assets", "css"), { recursive: true });
  mkdirSync(join(outDir, "assets", "js"), { recursive: true });
  if (existsSync(imgOutDir)) rmSync(imgOutDir, { recursive: true, force: true });
  mkdirSync(imgOutDir, { recursive: true });

  copyFileSync(join(TEMPLATE_DIR, "assets/css/handoff.css"), join(outDir, "assets/css/handoff.css"));
  copyFileSync(join(TEMPLATE_DIR, "assets/js/handoff.js"), join(outDir, "assets/js/handoff.js"));
  // Copy images deterministically (sorted by dest) so re-runs are stable.
  for (const dest of [...copies.keys()].sort()) copyFileSync(copies.get(dest), dest);
  writeFileSync(join(outDir, "index.html"), indexHtml);

  for (const w of warnings) console.error(`handoff-html-export: warning: ${w}`);
  console.log(
    `handoff-html-export: wrote ${join(args.out, "index.html")} — ` +
    `${sections.length} sections, ${copies.size} images, domain ${mode} (${origin})`);
}

try {
  main();
} catch (err) {
  die(2, err && err.message ? err.message : String(err));
}
