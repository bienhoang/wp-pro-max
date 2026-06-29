#!/usr/bin/env node
// pre-qa-a11y.mjs — static accessibility scan of one or more HTML files.
// Usage: node pre-qa-a11y.mjs <html-file> [html-file...]
// Output: JSON { passed, violations[], byRule{} }

import { readFileSync } from 'node:fs';
import { load } from 'cheerio';

const files = process.argv.slice(2);
if (files.length === 0) {
  console.error('Usage: pre-qa-a11y.mjs <html-file> [html-file...]');
  process.exit(2);
}

const rules = {
  imgAlt: { severity: 'error', message: 'Image missing alt text' },
  headingOrder: { severity: 'error', message: 'Heading order problem' },
  singleH1: { severity: 'error', message: 'Page should have exactly one h1' },
  mainLandmark: { severity: 'error', message: 'Page should have exactly one main landmark' },
  navLabel: { severity: 'warning', message: 'Nav landmark missing aria-label' },
  formLabel: { severity: 'error', message: 'Form control missing label' },
  contrast: { severity: 'warning', message: 'Inline color contrast may be insufficient' },
  lang: { severity: 'warning', message: 'html element missing lang attribute' }
};

const violations = [];
const byRule = {};

function add(rule, file, context) {
  const r = rules[rule];
  violations.push({ rule, severity: r.severity, file, message: r.message, context });
  byRule[rule] = (byRule[rule] || 0) + 1;
}

// Convert color to RGB array.
function parseColor(value) {
  const s = value.trim().toLowerCase();
  if (s.startsWith('#')) {
    const hex = s.slice(1);
    if (hex.length === 3) {
      const [r, g, b] = hex.split('').map(c => parseInt(c + c, 16));
      return [r, g, b];
    }
    if (hex.length === 6) {
      const r = parseInt(hex.slice(0, 2), 16);
      const g = parseInt(hex.slice(2, 4), 16);
      const b = parseInt(hex.slice(4, 6), 16);
      return [r, g, b];
    }
  }
  const rgb = s.match(/rgba?\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)/);
  if (rgb) return [parseInt(rgb[1], 10), parseInt(rgb[2], 10), parseInt(rgb[3], 10)];
  return null;
}

function luminance([r, g, b]) {
  const a = [r, g, b].map(v => {
    v /= 255;
    return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
  });
  return a[0] * 0.2126 + a[1] * 0.7152 + a[2] * 0.0722;
}

function contrastRatio(c1, c2) {
  const l1 = luminance(c1) + 0.05;
  const l2 = luminance(c2) + 0.05;
  return l1 > l2 ? l1 / l2 : l2 / l1;
}

function scan(file) {
  const raw = readFileSync(file, 'utf8');
  const $ = load(raw);

  // html lang
  const htmlLang = $('html').attr('lang');
  if (!htmlLang) add('lang', file, '<html>');

  // main landmark
  const mainCount = $('main').length;
  if (mainCount !== 1) add('mainLandmark', file, `main count = ${mainCount}`);

  // nav labels
  $('nav').each((_, el) => {
    const $el = $(el);
    const label = $el.attr('aria-label') || $el.attr('aria-labelledby');
    if (!label) add('navLabel', file, $.html(el).slice(0, 120));
  });

  // images alt
  $('img').each((_, el) => {
    const $el = $(el);
    const alt = $el.attr('alt');
    const role = $el.attr('role');
    if (alt === undefined && role !== 'presentation') {
      add('imgAlt', file, $el.attr('src') || '<img>');
    }
  });

  // headings
  const headings = [];
  $('h1, h2, h3, h4, h5, h6').each((_, el) => {
    const level = parseInt(el.tagName[1], 10);
    headings.push({ level, text: $(el).text().trim().slice(0, 60) });
  });
  const h1s = headings.filter(h => h.level === 1);
  if (h1s.length !== 1) add('singleH1', file, `h1 count = ${h1s.length}`);
  let prev = 0;
  for (const h of headings) {
    if (h.level > prev + 1 && prev !== 0) {
      add('headingOrder', file, `h${prev} → h${h.level}: ${h.text}`);
    }
    prev = h.level;
  }

  // form labels
  $('input, select, textarea').each((_, el) => {
    const $el = $(el);
    const id = $el.attr('id');
    const type = $el.attr('type') || el.tagName.toLowerCase();
    if (type === 'hidden' || type === 'submit' || type === 'button' || type === 'image') return;
    const aria = $el.attr('aria-label') || $el.attr('aria-labelledby') || $el.attr('title');
    let hasLabel = !!aria;
    if (id && !hasLabel) {
      hasLabel = $(`label[for="${id}"]`).length > 0;
    }
    if (!hasLabel) {
      add('formLabel', file, `<${el.tagName}> ${$el.attr('name') || ''}`.trim());
    }
  });

  // inline contrast
  $('[style*="color"]').each((_, el) => {
    const style = $(el).attr('style') || '';
    const fg = parseColor(style.match(/color\s*:\s*([^;]+)/i)?.[1] || '');
    const bg = parseColor(style.match(/background-color\s*:\s*([^;]+)/i)?.[1] || '');
    if (fg && bg) {
      const ratio = contrastRatio(fg, bg);
      if (ratio < 4.5) {
        add('contrast', file, `color=${style.match(/color\s*:\s*([^;]+)/i)[1]} bg=${style.match(/background-color\s*:\s*([^;]+)/i)[1]} ratio=${ratio.toFixed(2)}`);
      }
    }
  });
}

for (const file of files) {
  scan(file);
}

const passed = !violations.some(v => v.severity === 'error');
console.log(JSON.stringify({ passed, violations, byRule }, null, 2));
process.exit(passed ? 0 : 1);
