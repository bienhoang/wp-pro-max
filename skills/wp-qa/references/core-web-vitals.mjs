#!/usr/bin/env node
// core-web-vitals.mjs — measure LCP / CLS / INP-proxy for one or more URLs using
// Playwright + PerformanceObserver. A dependency-light fallback for when
// Lighthouse is unavailable. Lighthouse remains the preferred lab tool; this
// produces comparable lab-CWV numbers from the same Chromium engine.
//
// Usage:
//   node core-web-vitals.mjs <url...> [--out cwv.json]
//
// Output (stdout + --out): JSON
//   { "<url>": { lcp, cls, inp, passed }, ..., "passed": <all passed> }
//   lcp in ms, cls unitless, inp in ms. Targets: LCP<=2500, CLS<=0.1, INP<=200.
//
// Notes on INP: true INP needs real interactions. We approximate it by
// dispatching a few synthetic clicks and recording the worst event-processing
// duration via the Event Timing API. Treat it as a smoke signal, not field INP.
//
// Dependencies: npm i -D playwright && npx playwright install chromium

import { writeFileSync } from "node:fs";

const TARGETS = { lcp: 2500, cls: 0.1, inp: 200 };

function parse(argv) {
  const out = { urls: [], out: "" };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--out") out.out = argv[++i];
    else if (a === "-h" || a === "--help") out.help = true;
    else out.urls.push(a);
  }
  return out;
}

async function loadChromium() {
  try { return (await import("playwright")).chromium; }
  catch {
    console.error(
      "\ncore-web-vitals: playwright not installed\n\n" +
      "  npm i -D playwright\n  npx playwright install chromium\n"
    );
    process.exit(3);
  }
}

async function measure(browser, url) {
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  // Install observers BEFORE navigation so we catch the first paint/layout.
  await page.addInitScript(() => {
    window.__cwv = { lcp: 0, cls: 0, inp: 0 };
    try {
      new PerformanceObserver((l) => {
        const e = l.getEntries();
        const last = e[e.length - 1];
        if (last) window.__cwv.lcp = last.renderTime || last.loadTime || last.startTime;
      }).observe({ type: "largest-contentful-paint", buffered: true });
    } catch {}
    try {
      new PerformanceObserver((l) => {
        for (const entry of l.getEntries()) {
          if (!entry.hadRecentInput) window.__cwv.cls += entry.value;
        }
      }).observe({ type: "layout-shift", buffered: true });
    } catch {}
    try {
      new PerformanceObserver((l) => {
        for (const entry of l.getEntries()) {
          const dur = entry.duration || 0;
          if (dur > window.__cwv.inp) window.__cwv.inp = dur;
        }
      }).observe({ type: "event", buffered: true, durationThreshold: 16 });
    } catch {}
  });

  await page.goto(url, { waitUntil: "networkidle", timeout: 45000 });

  // Synthetic interactions to elicit event-timing samples for the INP proxy.
  try {
    const targets = await page.$$("a, button, [role=button], input, summary");
    for (const t of targets.slice(0, 5)) {
      await t.click({ trial: false, timeout: 1000 }).catch(() => {});
    }
  } catch {}
  await page.waitForTimeout(500);

  const cwv = await page.evaluate(() => window.__cwv);
  await page.close();

  const lcp = Math.round(cwv.lcp || 0);
  const cls = Number((cwv.cls || 0).toFixed(3));
  const inp = Math.round(cwv.inp || 0);
  const passed = lcp <= TARGETS.lcp && cls <= TARGETS.cls && inp <= TARGETS.inp;
  return { lcp, cls, inp, targets: TARGETS, passed };
}

async function main() {
  const args = parse(process.argv.slice(2));
  if (args.help || !args.urls.length) {
    console.error("Usage: node core-web-vitals.mjs <url...> [--out cwv.json]");
    process.exit(args.help ? 0 : 2);
  }
  const chromium = await loadChromium();
  const browser = await chromium.launch();
  const report = {};
  try {
    for (const url of args.urls) report[url] = await measure(browser, url);
  } finally {
    await browser.close();
  }
  report.passed = Object.values(report).every((v) => v.passed !== false);
  const json = JSON.stringify(report, null, 2) + "\n";
  if (args.out) writeFileSync(args.out, json);
  process.stdout.write(json);
  process.exit(report.passed ? 0 : 1);
}

main().catch((err) => {
  console.error(`core-web-vitals: ${err && err.message ? err.message : err}`);
  process.exit(2);
});
