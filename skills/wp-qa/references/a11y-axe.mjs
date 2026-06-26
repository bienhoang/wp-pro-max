#!/usr/bin/env node
// a11y-axe.mjs — run axe-core WCAG checks against one or more URLs via Playwright.
//
// Usage:
//   node a11y-axe.mjs <url...> [--tags wcag2a,wcag2aa] [--out a11y.json]
//
// Output (stdout + --out file): JSON
//   {
//     "byImpact": { "critical": N, "serious": N, "moderate": N, "minor": N },
//     "violations": [ { url, id, impact, help, nodes: ["<selector>", ...] } ],
//     "passed": <no critical/serious>
//   }
//
// Dependencies (installed on demand):
//   npm i -D playwright @axe-core/playwright
//   npx playwright install chromium
// Missing deps → exit 3 with the install command (no raw stack trace).

import { writeFileSync } from "node:fs";

function parse(argv) {
  const out = { urls: [], tags: "wcag2a,wcag2aa", out: "" };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--tags") out.tags = argv[++i];
    else if (a === "--out") out.out = argv[++i];
    else if (a === "-h" || a === "--help") out.help = true;
    else out.urls.push(a);
  }
  return out;
}

async function loadDeps() {
  const missing = [];
  let chromium, AxeBuilder;
  try { ({ chromium } = await import("playwright")); } catch { missing.push("playwright"); }
  try { AxeBuilder = (await import("@axe-core/playwright")).default; }
  catch { missing.push("@axe-core/playwright"); }
  if (missing.length) {
    console.error(
      "\na11y-axe: missing dependencies: " + missing.join(", ") + "\n\n" +
      "  npm i -D " + missing.join(" ") + "\n  npx playwright install chromium\n"
    );
    process.exit(3);
  }
  return { chromium, AxeBuilder };
}

async function main() {
  const args = parse(process.argv.slice(2));
  if (args.help || !args.urls.length) {
    console.error("Usage: node a11y-axe.mjs <url...> [--tags wcag2a,wcag2aa] [--out a11y.json]");
    process.exit(args.help ? 0 : 2);
  }
  const { chromium, AxeBuilder } = await loadDeps();
  const tags = args.tags.split(",").map((t) => t.trim()).filter(Boolean);

  const byImpact = { critical: 0, serious: 0, moderate: 0, minor: 0 };
  const violations = [];
  const browser = await chromium.launch();
  try {
    for (const url of args.urls) {
      const page = await browser.newPage();
      await page.goto(url, { waitUntil: "networkidle", timeout: 45000 });
      const results = await new AxeBuilder({ page }).withTags(tags).analyze();
      for (const v of results.violations) {
        const impact = v.impact || "minor";
        if (impact in byImpact) byImpact[impact] += 1;
        violations.push({
          url, id: v.id, impact, help: v.help,
          helpUrl: v.helpUrl,
          nodes: v.nodes.map((n) => n.target.join(" ")).slice(0, 10),
        });
      }
      await page.close();
    }
  } finally {
    await browser.close();
  }

  const passed = byImpact.critical === 0 && byImpact.serious === 0;
  const report = { byImpact, violations, passed };
  const json = JSON.stringify(report, null, 2) + "\n";
  if (args.out) writeFileSync(args.out, json);
  process.stdout.write(json);
  process.exit(passed ? 0 : 1);
}

main().catch((err) => {
  console.error(`a11y-axe: ${err && err.message ? err.message : err}`);
  process.exit(2);
});
