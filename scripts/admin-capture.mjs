#!/usr/bin/env node
// admin-capture.mjs — Playwright engine that logs into wp-admin and captures
// step-by-step screenshots for the handoff stage's admin guides.
//
// This is NEW infrastructure: visual-diff.mjs / the wp-qa capture scripts only
// screenshot the FRONT-END with no authentication. This one logs in through
// wp-login.php, then walks the flow spec built by scripts/handoff-guide-spec.sh
// and screenshots each step's admin screen.
//
// Usage:
//   node admin-capture.mjs --spec <spec.json|-> --base-url <url> --out <dir> \
//     [--locale <loc>] [--user <u>] [--pass <p>] [--dry-run]
//
//   # spec on stdin:
//   bash handoff-guide-spec.sh | node admin-capture.mjs --spec - \
//     --base-url http://localhost:8888 --out docs/guides/assets/vi
//
// The admin UI locale is set by the wp-handoff SKILL via wpx (user-locale only,
// no site-wide WPLANG change) BEFORE this runs — the engine only assumes the
// admin UI is already in the right language and captures it. `--locale` is
// recorded in the output manifest, not applied here.
//
// Credentials: default to the wp-env admin (admin/password); override with
// --user/--pass or env WP_ADMIN_USER / WP_ADMIN_PASS. The password is never
// echoed to stdout/stderr or written to the manifest.
//
// Output:
//   <out>/<flow-id>/NN-<step-id>.png     one screenshot per step
//   <out>/capture-manifest.json          { baseUrl, locale, mode:"captured",
//                                           flows: { <flow-id>: [relPaths...] } }
//   The manifest JSON is also printed to stdout.
//
// Exit codes (distinct so the skill can branch — Phase 4 fallback keys on 4):
//   0  captured (login OK; per-step nav failures are logged + skipped, not fatal)
//   2  bad arguments / spec parse failure / --dry-run validation failure
//   3  Playwright not installed — prints the exact install command
//   4  wp-env/site unreachable or admin login failed → caller falls back to
//      placeholder guides and leaves the spec for a re-run
//
// Dependency (installed on demand, not vendored):
//   npm i -D playwright && npx playwright install chromium

import { mkdirSync, readFileSync, writeFileSync, existsSync, unlinkSync } from "node:fs";
import { resolve, join } from "node:path";

// ----------------------------------------------------------------------------
// Argument parsing — tiny, dependency-free flag parser (mirrors visual-diff.mjs).
// ----------------------------------------------------------------------------

function parseArgs(argv) {
  const args = { locale: "", user: "", pass: "", dryRun: false };
  for (let i = 0; i < argv.length; i++) {
    // Accept both "--flag value" and "--flag=value" (parity with handoff-guide-spec.sh).
    let a = argv[i];
    let inline = null;
    if (a.startsWith("--") && a.includes("=")) {
      const eq = a.indexOf("=");
      inline = a.slice(eq + 1);
      a = a.slice(0, eq);
    }
    const val = () => (inline !== null ? inline : argv[++i]);
    switch (a) {
      case "--spec": args.spec = val(); break;
      case "--base-url": args.baseUrl = val(); break;
      case "--out": args.out = val(); break;
      case "--locale": args.locale = val(); break;
      case "--user": args.user = val(); break;
      case "--pass": args.pass = val(); break;
      case "--dry-run": args.dryRun = true; break;
      case "-h": case "--help": args.help = true; break;
      default:
        console.error(`admin-capture: unknown argument "${argv[i]}"`);
        args._bad = true;
    }
  }
  return args;
}

function usage() {
  console.error(
    "Usage: node admin-capture.mjs --spec <spec.json|-> --base-url <url> --out <dir> " +
    "[--locale <loc>] [--user <u>] [--pass <p>] [--dry-run]\n" +
    "  Prefer WP_ADMIN_USER / WP_ADMIN_PASS over --user/--pass (flag values are " +
    "visible in the process table)."
  );
}

// ----------------------------------------------------------------------------
// Spec loading + validation. Accepts a file path or "-" for stdin.
// ----------------------------------------------------------------------------

function loadSpec(specArg) {
  let raw;
  try {
    raw = specArg === "-" ? readFileSync(0, "utf8") : readFileSync(resolve(specArg), "utf8");
  } catch (err) {
    console.error(`admin-capture: cannot read spec "${specArg}": ${err.message}`);
    process.exit(2);
  }
  let spec;
  try {
    spec = JSON.parse(raw);
  } catch (err) {
    console.error(`admin-capture: spec is not valid JSON: ${err.message}`);
    process.exit(2);
  }
  if (!spec || !Array.isArray(spec.flows) || spec.flows.length === 0) {
    console.error("admin-capture: spec has no flows[] — nothing to capture");
    process.exit(2);
  }
  for (const f of spec.flows) {
    if (!f || typeof f.id !== "string" || !Array.isArray(f.steps)) {
      console.error(`admin-capture: malformed flow (needs string id + steps[]): ${JSON.stringify(f)}`);
      process.exit(2);
    }
  }
  return spec;
}

// ----------------------------------------------------------------------------
// Lazy dependency loading — clear, copy-pasteable fix when Playwright is absent.
// ----------------------------------------------------------------------------

async function loadChromium() {
  try {
    const { chromium } = await import("playwright");
    return chromium;
  } catch {
    console.error(
      "\nadmin-capture: Playwright is not installed.\n" +
      "Install it, then the Chromium browser:\n\n" +
      "  npm i -D playwright\n" +
      "  npx playwright install chromium\n"
    );
    process.exit(3);
  }
}

// ----------------------------------------------------------------------------
// Filename helpers.
// ----------------------------------------------------------------------------

function pad2(n) { return String(n).padStart(2, "0"); }

// Sanitize a spec-provided id for use as a path segment (defense-in-depth; the
// builder already emits safe slugs, but the spec may be hand-edited).
function safeSeg(s) {
  return String(s).replace(/[^a-zA-Z0-9._-]+/g, "-").replace(/^-+|-+$/g, "") || "x";
}

// ----------------------------------------------------------------------------
// Screenshot one navigable admin URL. Waits for network idle + fonts and
// disables animations for stable images (same discipline as visual-diff.mjs).
// Returns true on success, false if navigation failed (non-fatal per step).
// ----------------------------------------------------------------------------

// A stable container present on the target screen — list/settings (#wpbody-content),
// the sign-in page (#login), the block editor which runs fullscreen with the admin
// chrome hidden (#editor / .block-editor), or the Customizer, which is a separate
// app with none of the above (#customize-controls / .wp-full-overlay).
// Waited for as `attached`, NOT `visible`: the block editor hides #wpbody-content
// via CSS, so a visibility wait would time out on exactly the screens we need.
// Do NOT wait for "networkidle" either — autosave/heartbeat keep the editor and
// Dashboard from ever going idle.
const ADMIN_LANDMARK =
  "#wpbody-content, #wpadminbar, #login, #editor, .block-editor, " +
  "#customize-controls, .wp-full-overlay";

async function shoot(page, url, outPath) {
  try {
    await page.goto(url, { waitUntil: "domcontentloaded", timeout: 45000 });
    // Real admin screens attach their landmark in <1s; a long wait here only ever
    // burns time on a genuinely-absent screen (e.g. an "Invalid post type" wp_die
    // page with no admin chrome), which we skip. 10s is generous for the slowest
    // real screen (the block editor) without dragging on misses.
    await page.waitForSelector(ADMIN_LANDMARK, { state: "attached", timeout: 10000 });
  } catch (err) {
    process.stderr.write(`    ! nav failed: ${url} (${err.message.split("\n")[0]})\n`);
    return false;
  }
  await page.addStyleTag({
    content:
      "*,*::before,*::after{animation:none!important;transition:none!important;" +
      "caret-color:transparent!important;scroll-behavior:auto!important}",
  }).catch(() => {});
  try { await page.evaluate(() => document.fonts && document.fonts.ready); } catch {}
  await page.waitForTimeout(400); // brief settle for late layout/fonts
  try {
    await page.screenshot({ path: outPath, fullPage: true });
  } catch (err) {
    process.stderr.write(`    ! screenshot failed: ${outPath} (${err.message.split("\n")[0]})\n`);
    return false;
  }
  return true;
}

// ----------------------------------------------------------------------------
// Log into wp-admin. Returns { ok, loginScreenshotPath } — loginScreenshotPath is
// set when a preAuth "login" step asked to capture the sign-in page first.
// ----------------------------------------------------------------------------

async function login(page, baseUrl, user, pass, preAuthShot) {
  const loginUrl = new URL("wp-login.php", baseUrl).href;
  try {
    await page.goto(loginUrl, { waitUntil: "domcontentloaded", timeout: 45000 });
  } catch (err) {
    process.stderr.write(`admin-capture: site unreachable at ${loginUrl} (${err.message.split("\n")[0]})\n`);
    return { ok: false };
  }

  // Already authenticated (goto redirected to the dashboard)?
  if (await page.$("#wpadminbar")) {
    return { ok: true };
  }

  // Capture the sign-in screen BEFORE filling credentials, if requested.
  if (preAuthShot) {
    try { await page.screenshot({ path: preAuthShot, fullPage: true }); } catch {}
  }

  const userField = await page.$("#user_login");
  const passField = await page.$("#user_pass");
  if (!userField || !passField) {
    process.stderr.write("admin-capture: wp-login.php has no login form — site not ready\n");
    return { ok: false };
  }
  await userField.fill(user);
  await passField.fill(pass);
  await page.click("#wp-submit");
  try {
    await page.waitForSelector("#wpadminbar", { timeout: 20000 });
  } catch {
    // Still on the login form or an error box → bad creds / not provisioned.
    process.stderr.write("admin-capture: admin login failed (check credentials / wp-env readiness)\n");
    return { ok: false };
  }
  return { ok: true };
}

// ----------------------------------------------------------------------------
// Dry run: validate the spec + report the planned screenshot count. No browser.
// ----------------------------------------------------------------------------

function dryRun(spec) {
  const perFlow = {};
  let total = 0;
  for (const f of spec.flows) {
    const n = f.steps.length;
    perFlow[f.id] = n;
    total += n;
  }
  const report = {
    mode: "dry-run",
    locale: spec.locale || null,
    flows: spec.flows.length,
    screenshots: total,
    perFlow,
  };
  process.stdout.write(JSON.stringify(report, null, 2) + "\n");
  process.exit(0);
}

// ----------------------------------------------------------------------------
// Main
// ----------------------------------------------------------------------------

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) { usage(); process.exit(0); }
  if (args._bad || !args.spec) {
    if (!args.spec) console.error("admin-capture: --spec is required");
    usage();
    process.exit(2);
  }

  const spec = loadSpec(args.spec);

  if (args.dryRun) dryRun(spec);

  if (!args.baseUrl || !args.out) {
    console.error("admin-capture: --base-url and --out are required (unless --dry-run)");
    usage();
    process.exit(2);
  }

  const locale = args.locale || spec.locale || null;
  const user = args.user || process.env.WP_ADMIN_USER || "admin";
  const pass = args.pass || process.env.WP_ADMIN_PASS || "password";

  // Step URLs are site-root-relative ("wp-admin/edit.php"). new URL(rel, base)
  // resolves relative to the base's directory, so a base without a trailing slash
  // and with a path (e.g. a subdirectory install http://host/wp) would drop its
  // last segment. Normalize once so subdirectory installs resolve correctly.
  const base = args.baseUrl.endsWith("/") ? args.baseUrl : args.baseUrl + "/";

  const chromium = await loadChromium();
  const outDir = resolve(args.out);
  mkdirSync(outDir, { recursive: true });

  const browser = await chromium.launch();
  const flowsOut = {};
  try {
    const context = await browser.newContext({
      viewport: { width: 1440, height: 900 },
      deviceScaleFactor: 1,
      reducedMotion: "reduce",
    });
    const page = await context.newPage();

    // A preAuth step (the login screen) is captured during login().
    let preAuthTarget = null;
    for (const f of spec.flows) {
      const idx = f.steps.findIndex((s) => s && s.preAuth);
      if (idx >= 0) {
        const flowDir = join(outDir, safeSeg(f.id));
        mkdirSync(flowDir, { recursive: true });
        const rel = `${safeSeg(f.id)}/${pad2(idx + 1)}-${safeSeg(f.steps[idx].id)}.png`;
        preAuthTarget = { flowId: f.id, rel, abs: join(outDir, rel) };
        break; // only one login screen
      }
    }

    const auth = await login(page, base, user, pass, preAuthTarget ? preAuthTarget.abs : null);
    if (!auth.ok) {
      // Drop the pre-auth login screenshot taken before creds were validated —
      // on the exit-4 path the skill falls back to placeholders, so it's an orphan.
      if (preAuthTarget && existsSync(preAuthTarget.abs)) {
        try { unlinkSync(preAuthTarget.abs); } catch {}
      }
      await browser.close();
      process.exit(4); // wp-env/login unreachable → placeholder fallback
    }
    if (preAuthTarget) {
      (flowsOut[preAuthTarget.flowId] ||= []).push(preAuthTarget.rel);
    }

    for (const f of spec.flows) {
      const flowDir = join(outDir, safeSeg(f.id));
      mkdirSync(flowDir, { recursive: true });
      process.stderr.write(`  [${f.id}]\n`);
      for (let i = 0; i < f.steps.length; i++) {
        const step = f.steps[i];
        if (!step || !step.url) continue;
        if (step.preAuth) continue; // already captured during login
        const rel = `${safeSeg(f.id)}/${pad2(i + 1)}-${safeSeg(step.id || String(i + 1))}.png`;
        const abs = join(outDir, rel);
        const url = new URL(step.url, base).href;
        const ok = await shoot(page, url, abs);
        if (ok) (flowsOut[f.id] ||= []).push(rel);
      }
      // Keep flow order stable in the manifest even if a step was skipped.
      if (flowsOut[f.id]) flowsOut[f.id].sort();
    }

    await context.close();
  } finally {
    await browser.close();
  }

  const manifest = {
    baseUrl: args.baseUrl,
    locale,
    mode: "captured",
    generatedAt: new Date().toISOString(),
    flows: flowsOut,
  };
  const manifestPath = join(outDir, "capture-manifest.json");
  writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + "\n");
  process.stdout.write(JSON.stringify(manifest, null, 2) + "\n");

  process.exit(0);
}

main().catch((err) => {
  // Never leak a raw stack trace or a password; give a one-line reason.
  console.error(`admin-capture: ${err && err.message ? err.message.split("\n")[0] : err}`);
  process.exit(2);
});
