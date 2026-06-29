#!/usr/bin/env node
// pre-qa-responsive.mjs — Playwright-based responsive check.
// Usage: node pre-qa-responsive.mjs <html-file> [html-file...]
// Output: JSON { passed, viewports: [{file,width,height,overflow,consoleErrors}] }

import { readFileSync, existsSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';

const files = process.argv.slice(2);
if (files.length === 0) {
  console.error('Usage: pre-qa-responsive.mjs <html-file> [html-file...]');
  process.exit(2);
}

async function ensurePlaywright() {
  try {
    await import('playwright');
    return;
  } catch {
    console.error('pre-qa-responsive: installing playwright + chromium (one-time)…');
    const npm = process.platform === 'win32' ? 'npm.cmd' : 'npm';
    spawnSync(npm, ['install', 'playwright', '--no-save'], { stdio: 'inherit' });
    spawnSync(npm, ['exec', 'playwright', 'install', 'chromium'], { stdio: 'inherit' });
  }
}

const viewports = [
  { width: 375, height: 812 },
  { width: 768, height: 1024 },
  { width: 1280, height: 800 }
];

const results = [];
let passed = true;

async function checkFile(file) {
  const { chromium } = await import('playwright');
  const browser = await chromium.launch({ headless: true });

  for (const vp of viewports) {
    const context = await browser.newContext({ viewport: vp });
    const page = await context.newPage();
    const consoleErrors = [];
    const handler = msg => {
      if (msg.type() === 'error') consoleErrors.push(msg.text());
    };
    page.on('console', handler);
    await page.goto(pathToFileURL(file).href, { waitUntil: 'networkidle' });

    const overflow = await page.evaluate(() => {
      const root = document.documentElement;
      return root.scrollWidth > window.innerWidth;
    });
    page.off('console', handler);

    const hasErrors = consoleErrors.length > 0;
    const ok = !overflow && !hasErrors;
    if (!ok) passed = false;
    results.push({ file, width: vp.width, height: vp.height, overflow, consoleErrors, passed: ok });
    await context.close();
  }

  await browser.close();
}

(async () => {
  await ensurePlaywright();
  for (const file of files) {
    if (!existsSync(file)) {
      console.error(`pre-qa-responsive: file not found: ${file}`);
      process.exit(1);
    }
    await checkFile(file);
  }
  console.log(JSON.stringify({ passed, viewports: results }, null, 2));
  process.exit(passed ? 0 : 1);
})();
