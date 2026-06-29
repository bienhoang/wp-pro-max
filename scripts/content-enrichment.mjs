#!/usr/bin/env node
// content-enrichment.mjs — mechanical helpers for adding/enriching pages on the optimized copy.
// Usage:
//   node content-enrichment.mjs <manifest-path> --add-pages "Contact, Portfolio" [--force]
//   node content-enrichment.mjs <manifest-path> --from-brief [--force]
//   node content-enrichment.mjs <manifest-path> --approve
// Writes new HTML files and updates the manifest.

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { load } from 'cheerio';
import { join, dirname } from 'node:path';

const manifestPath = process.argv[2];
const mode = process.argv[3];
const arg = process.argv[4];
const force = process.argv.includes('--force');

if (!manifestPath || !mode) {
  console.error('Usage: content-enrichment.mjs <manifest-path> <--add-pages <list>|--from-brief|--approve> [--force]');
  process.exit(2);
}

const baseDir = dirname(manifestPath);
const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
const outDir = manifest.optimization?.outputDir || './.wp-pro-max/optimized';
const briefPath = manifest.source?.briefPath || './requirements/brief.md';

function slugify(title) {
  return title.toLowerCase().trim()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '');
}

function now() {
  return new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
}

function resolveOut(...parts) {
  return join(baseDir, outDir, ...parts);
}

function loadTemplate() {
  const candidates = ['index.html', 'home.html'];
  for (const c of candidates) {
    const p = resolveOut(c);
    if (existsSync(p)) return readFileSync(p, 'utf8');
  }
  const pages = manifest.analysis?.pages || [];
  for (const page of pages) {
    const p = resolveOut(page.path);
    if (existsSync(p)) return readFileSync(p, 'utf8');
  }
  throw new Error('content-enrichment: no template page found in ' + resolveOut());
}

function writeManifest() {
  writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
}

function updateNavLinks($, newPath, title) {
  const nav = $('nav').first();
  if (!nav.length) return;
  const links = nav.find('a');
  const existing = links.toArray().some(a => $(a).attr('href') === newPath);
  if (existing) return;
  const last = links.last();
  const item = `<a href="${newPath}">${title}</a>`;
  if (last.length) last.after(item);
  else nav.append(item);
}

function addPage(title) {
  const slug = slugify(title);
  const filePath = resolveOut(`${slug}.html`);
  if (existsSync(filePath) && !force) {
    console.error(`content-enrichment: ${filePath} already exists (use --force to overwrite)`);
    return null;
  }

  const templateHtml = loadTemplate();
  const $ = load(templateHtml);

  // Update page-level metadata
  $('title').text(title);
  const h1 = $('h1').first();
  if (h1.length) h1.text(title);

  // Replace main content with a draft placeholder section
  const main = $('main').first();
  if (main.length) {
    main.html(`<section class="page-content" data-wp-pro-max="draft">\n      <h1>${title}</h1>\n      <p>This page is a draft. Replace this content with the final copy.</p>\n    </section>`);
  }

  updateNavLinks($, `${slug}.html`, title);

  writeFileSync(filePath, $.html());

  const record = { path: `${slug}.html`, title, role: 'page', source: mode === '--from-brief' ? 'brief' : 'cli' };
  manifest.analysis.pages = manifest.analysis.pages || [];
  if (!manifest.analysis.pages.some(p => p.path === record.path)) {
    manifest.analysis.pages.push(record);
  }

  manifest.contentModel = manifest.contentModel || {};
  manifest.contentModel.menus = manifest.contentModel.menus || [];
  let menu = manifest.contentModel.menus.find(m => m.location === 'primary');
  if (!menu) {
    menu = { name: 'Primary', location: 'primary', items: [] };
    manifest.contentModel.menus.push(menu);
  }
  if (!menu.items.some(i => i.url === `/${slug}/` || i.url === `${slug}.html`)) {
    menu.items.push({ title, url: `${slug}.html` });
  }

  manifest.siteEditor = manifest.siteEditor || {};
  manifest.siteEditor.contentEnrichment = manifest.siteEditor.contentEnrichment || { addedPages: [], changes: [] };
  manifest.siteEditor.contentEnrichment.addedPages.push({ ...record, timestamp: now() });
  manifest.siteEditor.contentEnrichment.lastModified = now();

  return record;
}

function parseBrief() {
  const pages = [];
  const fullBriefPath = join(baseDir, briefPath);
  if (!existsSync(fullBriefPath)) return pages;
  const text = readFileSync(fullBriefPath, 'utf8');
  const sectionMatch = text.match(/##\s*Pages\s*\n([\s\S]*?)(?=\n##\s|$)/i);
  if (!sectionMatch) return pages;
  const lines = sectionMatch[1].split(/\r?\n/);
  for (const line of lines) {
    const m = line.match(/^\s*[-*]\s*([^:\n]+?)(?::\s*(.*))?\s*$/);
    if (m) pages.push({ title: m[1].trim(), description: (m[2] || '').trim() });
  }
  return pages;
}

function approveDrafts() {
  const pages = manifest.analysis?.pages || [];
  for (const page of pages) {
    const filePath = resolveOut(page.path);
    if (!existsSync(filePath)) continue;
    const html = readFileSync(filePath, 'utf8');
    const cleaned = html.replace(/\s*data-wp-pro-max="draft"/g, '');
    if (cleaned !== html) writeFileSync(filePath, cleaned);
  }
  manifest.siteEditor = manifest.siteEditor || {};
  manifest.siteEditor.contentEnrichment = manifest.siteEditor.contentEnrichment || {};
  manifest.siteEditor.contentEnrichment.approvedAt = now();
  console.log(JSON.stringify({ approved: true, pages: pages.length }));
}

if (mode === '--add-pages') {
  if (!arg) { console.error('--add-pages requires a list'); process.exit(2); }
  const titles = arg.split(',').map(t => t.trim()).filter(Boolean);
  const added = [];
  for (const title of titles) {
    const r = addPage(title);
    if (r) added.push(r);
  }
  writeManifest();
  console.log(JSON.stringify({ added, count: added.length }, null, 2));
  process.exit(added.length ? 0 : 1);
}

if (mode === '--from-brief') {
  const pages = parseBrief();
  const added = [];
  for (const page of pages) {
    const r = addPage(page.title);
    if (r) added.push(r);
  }
  writeManifest();
  console.log(JSON.stringify({ added, count: added.length }, null, 2));
  process.exit(added.length ? 0 : 1);
}

if (mode === '--approve') {
  approveDrafts();
  writeManifest();
  process.exit(0);
}

console.error('Unknown mode:', mode);
process.exit(2);
