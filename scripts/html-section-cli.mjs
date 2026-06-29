#!/usr/bin/env node
// html-section-cli.mjs — DOM-backed section ops for html-section-lib.sh
// Commands:
//   find     <html> <selector>
//   replace  <html> <selector> <new-html-file>
//   insert-before <html> <selector> <new-html-file>
//   insert-after  <html> <selector> <new-html-file>
//   remove   <html> <selector>
//   reorder  <html> <selectors-file>

import { readFileSync, writeFileSync } from 'node:fs';
import { load } from 'cheerio';

const [cmd, htmlFile, selector, third] = process.argv.slice(2);

function readHtml(path) {
  return readFileSync(path, 'utf8');
}

function loadDoc(path) {
  const raw = readHtml(path);
  const $ = load(raw);
  return { $, raw };
}

function preserveDoctype(raw, html) {
  if (/^\s*<!DOCTYPE/i.test(html)) return html;
  const doctype = raw.match(/<!DOCTYPE[^>]*>/i)?.[0] ?? '';
  return doctype ? `${doctype}\n${html}` : html;
}

function fail(message) {
  console.error(`html-section-cli: ${message}`);
  process.exit(1);
}

function commonAncestor($, $els) {
  if ($els.length === 0) return $.root();
  const lists = $els.toArray().map(el => {
    const list = [el];
    let cur = el;
    while (cur.parent && cur.parent.type === 'tag') {
      list.push(cur.parent);
      cur = cur.parent;
    }
    return list;
  });
  const firstList = lists[0];
  for (const el of firstList) {
    if (lists.every(list => list.includes(el))) {
      return $(el);
    }
  }
  return $.root();
}

if (!cmd || !htmlFile || !selector) {
  console.error('Usage: html-section-cli.mjs <find|replace|insert-before|insert-after|remove|reorder> <html-file> <selector|selectors-file> [new-html-file]');
  process.exit(2);
}

const { $, raw } = loadDoc(htmlFile);

switch (cmd) {
  case 'find': {
    const el = $(selector).first();
    if (!el.length) fail(`selector "${selector}" not found in ${htmlFile}`);
    console.log($.html(el));
    break;
  }
  case 'replace': {
    if (!third) fail('replace requires <new-html-file>');
    const newHtml = readHtml(third);
    const el = $(selector).first();
    if (!el.length) fail(`selector "${selector}" not found in ${htmlFile}`);
    el.replaceWith(newHtml);
    writeFileSync(htmlFile, preserveDoctype(raw, $.html()));
    break;
  }
  case 'insert-before': {
    if (!third) fail('insert-before requires <new-html-file>');
    const newHtml = readHtml(third);
    const el = $(selector).first();
    if (!el.length) fail(`selector "${selector}" not found in ${htmlFile}`);
    el.before(newHtml);
    writeFileSync(htmlFile, preserveDoctype(raw, $.html()));
    break;
  }
  case 'insert-after': {
    if (!third) fail('insert-after requires <new-html-file>');
    const newHtml = readHtml(third);
    const el = $(selector).first();
    if (!el.length) fail(`selector "${selector}" not found in ${htmlFile}`);
    el.after(newHtml);
    writeFileSync(htmlFile, preserveDoctype(raw, $.html()));
    break;
  }
  case 'remove': {
    $(selector).first().remove();
    writeFileSync(htmlFile, preserveDoctype(raw, $.html()));
    break;
  }
  case 'reorder': {
    if (!selector) fail('reorder requires <selectors-file>');
    const selectors = readHtml(selector).split(/\r?\n/).map(s => s.trim()).filter(Boolean);
    const matched = [];
    for (const sel of selectors) {
      $(sel).each((_, el) => matched.push($(el)));
    }
    if (matched.length === 0) fail('no elements matched for reorder');
    const $parent = commonAncestor($, $(matched.map($el => $el[0])));
    const moved = matched.map($el => $el.clone());
    matched.forEach($el => $el.remove());
    for (const $el of moved) {
      $parent.append($el);
    }
    writeFileSync(htmlFile, preserveDoctype(raw, $.html()));
    break;
  }
  default:
    fail(`unknown command: ${cmd}`);
}
