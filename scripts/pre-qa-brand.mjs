#!/usr/bin/env node
// pre-qa-brand.mjs — static brand-consistency check against designTokens.
// Usage: node pre-qa-brand.mjs <html-file>... --tokens <tokens-json-file>
// Output: JSON { passed, mismatches[] }

import { readFileSync, existsSync } from 'node:fs';
import { load } from 'cheerio';

const args = process.argv.slice(2);
const tokenIdx = args.indexOf('--tokens');
if (tokenIdx === -1 || tokenIdx + 1 >= args.length) {
  console.error('Usage: pre-qa-brand.mjs <html-file>... --tokens <tokens-json-file>');
  process.exit(2);
}

const tokenPath = args[tokenIdx + 1];
const files = args.filter((_, i) => i !== tokenIdx && i !== tokenIdx + 1);
if (files.length === 0) {
  console.error('Usage: pre-qa-brand.mjs <html-file>... --tokens <tokens-json-file>');
  process.exit(2);
}

let tokens = {};
if (existsSync(tokenPath)) {
  tokens = JSON.parse(readFileSync(tokenPath, 'utf8'));
} else {
  try {
    tokens = JSON.parse(tokenPath);
  } catch {
    console.error('pre-qa-brand: could not read tokens');
    process.exit(1);
  }
}

const tokenColors = (tokens.colors || []).map(c => parseColor(c.value)).filter(Boolean);
const tokenFonts = (tokens.fonts || []).map(f => normalizeFont(f.family));

function normalizeFont(value) {
  return value.toLowerCase().split(',')[0].trim();
}

function parseColor(value) {
  if (!value) return null;
  const s = value.trim().toLowerCase();
  if (s.startsWith('#')) {
    const hex = s.slice(1);
    if (hex.length === 3) {
      const [r, g, b] = hex.split('').map(c => parseInt(c + c, 16));
      return [r, g, b];
    }
    if (hex.length === 6) {
      return [parseInt(hex.slice(0, 2), 16), parseInt(hex.slice(2, 4), 16), parseInt(hex.slice(4, 6), 16)];
    }
  }
  const rgb = s.match(/rgba?\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)/);
  if (rgb) return [parseInt(rgb[1], 10), parseInt(rgb[2], 10), parseInt(rgb[3], 10)];
  return null;
}

function colorDistance(a, b) {
  return Math.sqrt(
    Math.pow(a[0] - b[0], 2) + Math.pow(a[1] - b[1], 2) + Math.pow(a[2] - b[2], 2)
  );
}

function isTokenColor(value) {
  const rgb = parseColor(value);
  if (!rgb) return false;
  if (tokenColors.length === 0) return true; // no tokens defined; allow anything
  return tokenColors.some(t => colorDistance(t, rgb) < 30);
}

function isTokenFont(value) {
  if (!value) return true;
  const family = normalizeFont(value);
  if (tokenFonts.length === 0) return true;
  // Allow generic fallbacks and variables that reference token names.
  if (['sans-serif', 'serif', 'monospace', 'cursive', 'fantasy'].includes(family)) return true;
  if (family.startsWith('var(--')) return true;
  return tokenFonts.some(t => family.includes(t) || t.includes(family));
}

const mismatches = [];

function check(file) {
  const raw = readFileSync(file, 'utf8');
  const $ = load(raw);

  $('[style*="color"], [style*="font-family"]').each((_, el) => {
    const style = $(el).attr('style') || '';
    const color = style.match(/color\s*:\s*([^;]+)/i)?.[1]?.trim();
    const bg = style.match(/background-color\s*:\s*([^;]+)/i)?.[1]?.trim();
    const font = style.match(/font-family\s*:\s*([^;]+)/i)?.[1]?.trim();

    if (color && !isTokenColor(color)) {
      mismatches.push({ file, type: 'color', value: color, context: $.html(el).slice(0, 120) });
    }
    if (bg && !isTokenColor(bg)) {
      mismatches.push({ file, type: 'background-color', value: bg, context: $.html(el).slice(0, 120) });
    }
    if (font && !isTokenFont(font)) {
      mismatches.push({ file, type: 'font-family', value: font, context: $.html(el).slice(0, 120) });
    }
  });
}

for (const file of files) check(file);
const passed = mismatches.length === 0;
console.log(JSON.stringify({ passed, mismatches }, null, 2));
process.exit(passed ? 0 : 1);
