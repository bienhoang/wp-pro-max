#!/usr/bin/env node
// pre-qa-html-validity.mjs — static HTML validity checks.
// Usage: node pre-qa-html-validity.mjs <html-file> [html-file...]
// Output: JSON { passed, errors[] }

import { readFileSync } from 'node:fs';
import { load } from 'cheerio';

const files = process.argv.slice(2);
if (files.length === 0) {
  console.error('Usage: pre-qa-html-validity.mjs <html-file> [html-file...]');
  process.exit(2);
}

const errors = [];

function check(file) {
  const raw = readFileSync(file, 'utf8');
  const $ = load(raw);

  if (!$('html').attr('lang')) {
    errors.push({ file, rule: 'html-lang', message: '<html> missing lang attribute' });
  }
  if (!$('title').length || $('title').text().trim() === '') {
    errors.push({ file, rule: 'title', message: '<title> missing or empty' });
  }
  if (!$('meta[charset]').length && !$('meta[http-equiv="content-type" i]').length) {
    errors.push({ file, rule: 'charset', message: 'character encoding meta tag missing' });
  }

  const ids = {};
  $('[id]').each((_, el) => {
    const id = $(el).attr('id');
    if (id) {
      ids[id] = (ids[id] || 0) + 1;
      if (ids[id] === 2) {
        errors.push({ file, rule: 'duplicate-id', message: `duplicate id: ${id}` });
      }
    }
  });
}

for (const file of files) check(file);
const passed = errors.length === 0;
console.log(JSON.stringify({ passed, errors }, null, 2));
process.exit(passed ? 0 : 1);
