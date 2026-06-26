#!/usr/bin/env node
// visual-diff.mjs — Playwright pixel diff between a source HTML page and the
// rendered WordPress page, across one or more viewports.
//
// Usage:
//   node visual-diff.mjs --source <urlOrFile> --target <wpUrl> \
//     [--viewports 1280,768,375] [--threshold 0.05] [--out diff/] \
//     [--full-page] [--name home]
//
// Examples:
//   node visual-diff.mjs --source ./optimized/index.html \
//     --target http://localhost:8888/ --viewports 1280,768,375 --out diff/home
//   node visual-diff.mjs --source https://acme.com/about \
//     --target http://localhost:8888/about/ --threshold 0.03
//
// Output (per viewport <w>, under <out>/):
//   <name>-<w>-source.png       source screenshot
//   <name>-<w>-target.png       WP screenshot
//   <name>-<w>-diff.png         per-pixel diff (changed pixels highlighted)
//   <name>-<w>-sidebyside.png   source | diff | target montage
//   <name>-report.json          { source, target, threshold, results[], passed }
//   The JSON report is also printed to stdout.
//
// Exit codes:
//   0  every viewport diffRatio <= threshold (PASS)
//   1  at least one viewport exceeded threshold (FAIL)
//   2  bad arguments / source unreachable / navigation failure
//   3  Playwright (or pixelmatch/pngjs) not installed — prints fix command
//
// Dependencies (installed on demand, not vendored):
//   npm i -D playwright pixelmatch pngjs
//   npx playwright install chromium
// If a dependency is missing the script prints the exact install command and
// exits 3 rather than throwing a raw stack trace.

import { mkdirSync, existsSync, readFileSync, writeFileSync } from "node:fs";
import { resolve, join, basename, extname } from "node:path";
import { pathToFileURL } from "node:url";

// ----------------------------------------------------------------------------
// Argument parsing — tiny, dependency-free flag parser.
// ----------------------------------------------------------------------------

function parseArgs(argv) {
  const args = {
    viewports: "1280,768,375",
    threshold: "0.05",
    out: "diff",
    fullPage: false,
    name: "",
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    switch (a) {
      case "--source": args.source = argv[++i]; break;
      case "--target": args.target = argv[++i]; break;
      case "--viewports": args.viewports = argv[++i]; break;
      case "--threshold": args.threshold = argv[++i]; break;
      case "--out": args.out = argv[++i]; break;
      case "--name": args.name = argv[++i]; break;
      case "--full-page": args.fullPage = true; break;
      case "-h": case "--help": args.help = true; break;
      default:
        console.error(`visual-diff: unknown argument "${a}"`);
        args._bad = true;
    }
  }
  return args;
}

function usage() {
  console.error(
    "Usage: node visual-diff.mjs --source <urlOrFile> --target <wpUrl> " +
    "[--viewports 1280,768,375] [--threshold 0.05] [--out diff/] [--full-page] [--name home]"
  );
}

// ----------------------------------------------------------------------------
// Lazy dependency loading — give a clear, copy-pasteable fix when missing.
// ----------------------------------------------------------------------------

async function loadDeps() {
  const missing = [];
  let chromium, pixelmatch, PNG;
  try { ({ chromium } = await import("playwright")); }
  catch { missing.push("playwright"); }
  try { pixelmatch = (await import("pixelmatch")).default; }
  catch { missing.push("pixelmatch"); }
  try { ({ PNG } = await import("pngjs")); }
  catch { missing.push("pngjs"); }

  if (missing.length) {
    console.error(
      "\nvisual-diff: missing dependencies: " + missing.join(", ") + "\n" +
      "Install them, then install the Chromium browser:\n\n" +
      "  npm i -D " + missing.join(" ") + "\n" +
      "  npx playwright install chromium\n"
    );
    process.exit(3);
  }
  return { chromium, pixelmatch, PNG };
}

// ----------------------------------------------------------------------------
// URL/file normalization. A local file path becomes a file:// URL so the same
// page.goto() path works for both source and target.
// ----------------------------------------------------------------------------

function toNavigable(target) {
  if (/^https?:\/\//i.test(target) || /^file:\/\//i.test(target)) return target;
  const abs = resolve(target);
  if (!existsSync(abs)) {
    console.error(`visual-diff: file not found: ${abs}`);
    process.exit(2);
  }
  return pathToFileURL(abs).href;
}

function deriveName(args) {
  if (args.name) return args.name;
  const src = args.source;
  if (/^https?:\/\//i.test(src)) {
    try {
      const p = new URL(src).pathname.replace(/\/+$/, "");
      return p ? p.split("/").filter(Boolean).join("-") : "home";
    } catch { return "page"; }
  }
  const b = basename(src, extname(src));
  return b === "index" ? "home" : b || "page";
}

// ----------------------------------------------------------------------------
// Screenshot a navigable URL at a given width. Waits for network idle + fonts so
// late-loading assets don't cause false diffs, disables animations/caret for
// determinism, and scrolls to trigger lazy-loaded media.
// ----------------------------------------------------------------------------

async function screenshot(browser, url, width, fullPage, outPath) {
  const context = await browser.newContext({
    viewport: { width, height: 900 },
    deviceScaleFactor: 1,
    reducedMotion: "reduce",
  });
  const page = await context.newPage();
  try {
    await page.goto(url, { waitUntil: "networkidle", timeout: 45000 });
  } catch (err) {
    await context.close();
    throw new Error(`navigation failed for ${url}: ${err.message}`);
  }
  await page.addStyleTag({
    content:
      "*,*::before,*::after{animation:none!important;transition:none!important;" +
      "caret-color:transparent!important;scroll-behavior:auto!important}",
  });
  try { await page.evaluate(() => document.fonts && document.fonts.ready); } catch {}
  await page.evaluate(async () => {
    await new Promise((res) => {
      let y = 0;
      const step = () => {
        window.scrollTo(0, y);
        y += window.innerHeight;
        if (y < document.body.scrollHeight) setTimeout(step, 50);
        else { window.scrollTo(0, 0); setTimeout(res, 150); }
      };
      step();
    });
  });
  await page.screenshot({ path: outPath, fullPage });
  await context.close();
}

// ----------------------------------------------------------------------------
// Compare two PNGs. Images of differing dimensions are normalized onto a shared
// canvas (max width x max height); out-of-bounds area counts as fully different,
// which correctly penalizes layout-size drift between source and WP.
// ----------------------------------------------------------------------------

function padTo(PNG, img, width, height) {
  if (img.width === width && img.height === height) return img;
  const out = new PNG({ width, height });
  out.data.fill(0); // unfilled (size-drift) regions register as diff
  PNG.bitblt(img, out, 0, 0, img.width, img.height, 0, 0);
  return out;
}

function diffPair(pixelmatch, PNG, srcPath, tgtPath, diffPath) {
  const a = PNG.sync.read(readFileSync(srcPath));
  const b = PNG.sync.read(readFileSync(tgtPath));
  const width = Math.max(a.width, b.width);
  const height = Math.max(a.height, b.height);
  const A = padTo(PNG, a, width, height);
  const B = padTo(PNG, b, width, height);
  const diff = new PNG({ width, height });
  const mismatched = pixelmatch(A.data, B.data, diff.data, width, height, {
    threshold: 0.1, // per-pixel color sensitivity (NOT the pass/fail gate)
    includeAA: false,
  });
  writeFileSync(diffPath, PNG.sync.write(diff));
  const ratio = mismatched / (width * height);
  return { ratio, width, height, mismatched, A, B, diff };
}

// Compose a source | diff | target montage for fast human review.
function writeSideBySide(PNG, A, B, diff, width, height, outPath) {
  const gap = 12;
  const total = width * 3 + gap * 2;
  const montage = new PNG({ width: total, height });
  montage.data.fill(255);
  PNG.bitblt(A, montage, 0, 0, width, height, 0, 0);
  PNG.bitblt(diff, montage, 0, 0, width, height, width + gap, 0);
  PNG.bitblt(B, montage, 0, 0, width, height, (width + gap) * 2, 0);
  writeFileSync(outPath, PNG.sync.write(montage));
}

// ----------------------------------------------------------------------------
// Main
// ----------------------------------------------------------------------------

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) { usage(); process.exit(0); }
  if (args._bad || !args.source || !args.target) {
    if (!args.source || !args.target) console.error("visual-diff: --source and --target are required");
    usage();
    process.exit(2);
  }

  const threshold = Number(args.threshold);
  if (!Number.isFinite(threshold) || threshold < 0 || threshold > 1) {
    console.error(`visual-diff: --threshold must be between 0 and 1 (got "${args.threshold}")`);
    process.exit(2);
  }
  const viewports = args.viewports
    .split(",").map((v) => parseInt(v.trim(), 10)).filter((n) => n > 0);
  if (!viewports.length) { console.error("visual-diff: no valid --viewports"); process.exit(2); }

  const { chromium, pixelmatch, PNG } = await loadDeps();

  const name = deriveName(args);
  const outDir = resolve(args.out);
  mkdirSync(outDir, { recursive: true });

  const sourceUrl = toNavigable(args.source);
  const targetUrl = /^https?:\/\//i.test(args.target) ? args.target : toNavigable(args.target);

  const browser = await chromium.launch();
  const results = [];
  try {
    for (const width of viewports) {
      const srcPath = join(outDir, `${name}-${width}-source.png`);
      const tgtPath = join(outDir, `${name}-${width}-target.png`);
      const diffPath = join(outDir, `${name}-${width}-diff.png`);
      const sbsPath = join(outDir, `${name}-${width}-sidebyside.png`);

      await screenshot(browser, sourceUrl, width, args.fullPage, srcPath);
      await screenshot(browser, targetUrl, width, args.fullPage, tgtPath);

      const { ratio, width: w, height: h, mismatched, A, B, diff } =
        diffPair(pixelmatch, PNG, srcPath, tgtPath, diffPath);
      writeSideBySide(PNG, A, B, diff, w, h, sbsPath);

      const passed = ratio <= threshold;
      results.push({
        viewport: width,
        diffRatio: Number(ratio.toFixed(5)),
        mismatchedPixels: mismatched,
        comparedPixels: w * h,
        threshold,
        passed,
        artifacts: { source: srcPath, target: tgtPath, diff: diffPath, sideBySide: sbsPath },
      });
      process.stderr.write(
        `  [${width}px] diffRatio=${ratio.toFixed(5)} ${passed ? "PASS" : "FAIL"}\n`
      );
    }
  } finally {
    await browser.close();
  }

  const passed = results.every((r) => r.passed);
  const report = {
    source: args.source, target: args.target, name,
    threshold, generatedAt: new Date().toISOString(),
    viewports, results, passed,
  };
  const reportPath = join(outDir, `${name}-report.json`);
  writeFileSync(reportPath, JSON.stringify(report, null, 2) + "\n");
  process.stdout.write(JSON.stringify(report, null, 2) + "\n");

  process.exit(passed ? 0 : 1);
}

main().catch((err) => {
  console.error(`visual-diff: ${err && err.message ? err.message : err}`);
  process.exit(2);
});
