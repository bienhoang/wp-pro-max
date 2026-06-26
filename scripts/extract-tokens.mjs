#!/usr/bin/env node
// extract-tokens.mjs — derive a design system from raw CSS/HTML.
//
// Usage:
//   node extract-tokens.mjs <css-or-html-glob...>
//   node extract-tokens.mjs "src/**/*.css" "src/**/*.html"
//   node extract-tokens.mjs ./styles/main.css ./index.html
//
// Output (stdout): JSON { colors, fonts, spacing, breakpoints, radius }
// Each token list is deduplicated and ranked by frequency (most-used first),
// so downstream theme.json / CSS-variable generation can pick the dominant
// values for the palette and typography scale.
//
// No external dependencies: uses Node stdlib only (fs, path, url). CSS is
// parsed with deliberately scoped regexes rather than a full AST — this is
// resilient to malformed markup and fast enough for whole-site sweeps. The
// regex approach is documented inline at each extractor.

import { readFileSync, statSync, readdirSync } from "node:fs";
import { join, extname, resolve } from "node:path";

// ----------------------------------------------------------------------------
// File collection — expand args into a concrete file list. Supports literal
// paths, directories (recursed), and simple globs (`*`, `**`, `?`).
// ----------------------------------------------------------------------------

const TEXT_EXT = new Set([".css", ".scss", ".sass", ".less", ".html", ".htm", ".vue", ".svelte"]);

function globToRegExp(glob) {
  // Translate a shell-style glob into a RegExp. `**` => any depth, `*` => any
  // run without a slash, `?` => single char. Everything else is escaped.
  let re = "";
  for (let i = 0; i < glob.length; i++) {
    const c = glob[i];
    if (c === "*") {
      if (glob[i + 1] === "*") { re += ".*"; i++; if (glob[i + 1] === "/") i++; }
      else re += "[^/]*";
    } else if (c === "?") re += "[^/]";
    else if ("+.()|[]{}^$\\".includes(c)) re += "\\" + c;
    else re += c;
  }
  return new RegExp("^" + re + "$");
}

function walk(dir, out) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === "node_modules" || entry.name.startsWith(".")) continue;
    const full = join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else if (TEXT_EXT.has(extname(entry.name).toLowerCase())) out.push(full);
  }
}

function collectFiles(patterns) {
  const files = new Set();
  for (const pattern of patterns) {
    let st;
    try { st = statSync(pattern); } catch { st = null; }
    if (st?.isFile()) { files.add(resolve(pattern)); continue; }
    if (st?.isDirectory()) { const out = []; walk(pattern, out); out.forEach((f) => files.add(resolve(f))); continue; }
    // Treat as glob: walk from the static prefix, filter by regex.
    const slash = pattern.lastIndexOf("/", pattern.search(/[*?]/));
    const base = slash > 0 ? pattern.slice(0, slash) : ".";
    const rx = globToRegExp(resolve(pattern));
    let baseStat;
    try { baseStat = statSync(base); } catch { baseStat = null; }
    if (baseStat?.isDirectory()) {
      const out = [];
      walk(base, out);
      out.forEach((f) => { if (rx.test(resolve(f))) files.add(resolve(f)); });
    }
  }
  return [...files];
}

// ----------------------------------------------------------------------------
// Frequency counter — tracks occurrence counts and emits a ranked array.
// ----------------------------------------------------------------------------

class Counter {
  constructor() { this.map = new Map(); }
  add(key, n = 1) { if (!key) return; this.map.set(key, (this.map.get(key) || 0) + n); }
  ranked() {
    return [...this.map.entries()]
      .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
      .map(([value, count]) => ({ value, count }));
  }
}

// ----------------------------------------------------------------------------
// Color extraction — hex, rgb()/rgba(), hsl()/hsla(). Normalizes hex to
// lowercase and expands 3-digit shorthand so duplicates collapse.
// ----------------------------------------------------------------------------

const RE_HEX = /#([0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})\b/g;
const RE_FUNC_COLOR = /\b(rgba?|hsla?)\(\s*[^)]+\)/gi;

function normHex(hex) {
  let h = hex.toLowerCase();
  if (h.length === 4) h = "#" + h[1] + h[1] + h[2] + h[2] + h[3] + h[3];
  if (h.length === 5) h = "#" + h[1] + h[1] + h[2] + h[2] + h[3] + h[3] + h[4] + h[4];
  return h;
}

function extractColors(text, counter) {
  for (const m of text.matchAll(RE_HEX)) counter.add(normHex(m[0]));
  for (const m of text.matchAll(RE_FUNC_COLOR)) {
    // Collapse internal whitespace so "rgb(0, 0, 0)" == "rgb(0,0,0)".
    counter.add(m[0].replace(/\s+/g, "").toLowerCase());
  }
}

// ----------------------------------------------------------------------------
// Font extraction — font-family declarations + Google Fonts <link> hrefs and
// @import url(...) statements. Splits stacks into individual family names and
// strips quotes. Returns the leading (preferred) family for each declaration
// separately so the primary brand font ranks highest.
// ----------------------------------------------------------------------------

const RE_FONT_FAMILY = /font-family\s*:\s*([^;}{]+)[;}]/gi;
const RE_FONT_SHORT = /\bfont\s*:\s*[^;}{]*?\b(?:\d|normal|bold|italic)[^;}{]*?\s([A-Za-z][^;}{]+)[;}]/gi;
const RE_GOOGLE_LINK = /fonts\.googleapis\.com\/css2?\?([^"'\s)]+)/gi;
const RE_FONT_FACE = /@font-face\s*\{[^}]*?font-family\s*:\s*([^;}]+)/gi;

const GENERIC_FONTS = new Set([
  "serif", "sans-serif", "monospace", "cursive", "fantasy", "system-ui",
  "ui-serif", "ui-sans-serif", "ui-monospace", "ui-rounded", "inherit",
  "initial", "unset", "revert", "emoji", "math", "fangsong",
  "-apple-system", "blinkmacsystemfont",
]);

function cleanFamily(raw) {
  return raw.trim().replace(/^["']|["']$/g, "").replace(/\s+/g, " ").trim();
}

function extractFonts(text, counter) {
  const families = [];
  for (const m of text.matchAll(RE_FONT_FAMILY)) families.push(m[1]);
  for (const m of text.matchAll(RE_FONT_SHORT)) families.push(m[1]);
  for (const m of text.matchAll(RE_FONT_FACE)) families.push(m[1]);
  for (const stack of families) {
    const parts = stack.split(",").map(cleanFamily).filter(Boolean);
    parts.forEach((fam, idx) => {
      if (GENERIC_FONTS.has(fam.toLowerCase())) return;
      // Preferred (first) family in a stack carries more weight.
      counter.add(fam, idx === 0 ? 3 : 1);
    });
  }
  // Google Fonts links — strongest signal for the real font name.
  for (const m of text.matchAll(RE_GOOGLE_LINK)) {
    const query = m[1];
    for (const fm of query.matchAll(/family=([^&:]+)/gi)) {
      const fam = decodeURIComponent(fm[1].replace(/\+/g, " ")).trim();
      if (fam) counter.add(fam, 5);
    }
  }
}

// ----------------------------------------------------------------------------
// Spacing extraction — px / rem / em values from margin, padding, gap, and the
// `--space*` / `--gap*` custom properties. Only the common layout dimensions
// are kept (skip 0 and absurdly large outliers).
// ----------------------------------------------------------------------------

const RE_SPACING_PROP = /\b(?:margin|padding|gap|row-gap|column-gap|inset|top|right|bottom|left)(?:-[a-z]+)?\s*:\s*([^;}{]+)[;}]/gi;
const RE_SPACING_VAR = /--(?:space|spacing|gap|gutter|size)[\w-]*\s*:\s*([^;}{]+)[;}]/gi;
const RE_LEN = /(-?\d*\.?\d+)(px|rem|em)\b/g;

function extractSpacing(text, counter) {
  const scan = (re) => {
    for (const m of text.matchAll(re)) {
      for (const lm of m[1].matchAll(RE_LEN)) {
        const num = parseFloat(lm[1]);
        const unit = lm[2];
        if (num === 0) continue;
        if (unit === "px" && (num < 2 || num > 320)) continue; // skip hairlines & jumbo
        if ((unit === "rem" || unit === "em") && num > 24) continue;
        counter.add(`${num}${unit}`);
      }
    }
  };
  scan(RE_SPACING_PROP);
  scan(RE_SPACING_VAR);
}

// ----------------------------------------------------------------------------
// Breakpoint extraction — min-width / max-width values inside @media queries.
// Grouped into a single object keyed by a friendly label (sm/md/lg/xl/2xl)
// derived from the px value.
// ----------------------------------------------------------------------------

const RE_MEDIA = /@media[^{]*?\((?:min|max)-width\s*:\s*(\d+(?:\.\d+)?)(px|rem|em)\)/gi;

function labelForBreakpoint(px) {
  if (px <= 480) return "sm";
  if (px <= 768) return "md";
  if (px <= 1024) return "lg";
  if (px <= 1280) return "xl";
  return "2xl";
}

function extractBreakpoints(text, counter) {
  for (const m of text.matchAll(RE_MEDIA)) {
    let px = parseFloat(m[1]);
    if (m[2] === "rem" || m[2] === "em") px = Math.round(px * 16);
    counter.add(`${px}px`);
  }
}

// ----------------------------------------------------------------------------
// Radius extraction — border-radius values + `--radius*` custom properties.
// ----------------------------------------------------------------------------

const RE_RADIUS = /\bborder-radius\s*:\s*([^;}{]+)[;}]/gi;
const RE_RADIUS_VAR = /--(?:radius|rounded|corner)[\w-]*\s*:\s*([^;}{]+)[;}]/gi;

function extractRadius(text, counter) {
  const scan = (re) => {
    for (const m of text.matchAll(re)) {
      const val = m[1].trim();
      if (/^(?:9999px|50%|100%|9999rem)$/.test(val)) { counter.add("full"); continue; }
      for (const lm of val.matchAll(RE_LEN)) counter.add(`${parseFloat(lm[1])}${lm[2]}`);
    }
  };
  scan(RE_RADIUS);
  scan(RE_RADIUS_VAR);
}

// ----------------------------------------------------------------------------
// Custom-property color pass — capture `--brand: #...` style declarations so
// named palette entries survive even when the literal also appears elsewhere.
// ----------------------------------------------------------------------------

const RE_COLOR_VAR = /(--[\w-]*(?:color|colour|brand|primary|secondary|accent|bg|background|fg|text|border|surface)[\w-]*)\s*:\s*([^;}{]+)[;}]/gi;

function extractNamedColors(text, namedColors) {
  for (const m of text.matchAll(RE_COLOR_VAR)) {
    const name = m[1].trim();
    const value = m[2].trim();
    if (RE_HEX.test(value) || /\b(rgba?|hsla?)\(/i.test(value)) {
      namedColors.set(name, value.replace(/\s+/g, " "));
    }
    RE_HEX.lastIndex = 0; // reset because RE_HEX is global and `.test` advances it
  }
}

// ----------------------------------------------------------------------------
// Main
// ----------------------------------------------------------------------------

function main() {
  const patterns = process.argv.slice(2);
  if (patterns.length === 0) {
    process.stderr.write("usage: node extract-tokens.mjs <css-or-html-glob...>\n");
    process.exit(2);
  }

  const files = collectFiles(patterns);
  if (files.length === 0) {
    process.stderr.write(`extract-tokens: no matching files for: ${patterns.join(", ")}\n`);
    process.exit(1);
  }

  const colors = new Counter();
  const fonts = new Counter();
  const spacing = new Counter();
  const breakpoints = new Counter();
  const radius = new Counter();
  const namedColors = new Map();

  for (const file of files) {
    let text;
    try { text = readFileSync(file, "utf8"); } catch { continue; }
    extractColors(text, colors);
    extractFonts(text, fonts);
    extractSpacing(text, spacing);
    extractBreakpoints(text, breakpoints);
    extractRadius(text, radius);
    extractNamedColors(text, namedColors);
  }

  // Sort spacing numerically (ascending) once ranked, so it reads as a scale.
  const spacingRanked = spacing.ranked().sort((a, b) => {
    const pa = parseFloat(a.value), pb = parseFloat(b.value);
    return pa - pb;
  });

  // Build a labelled breakpoints object from the ranked px values.
  const bpObject = {};
  for (const { value } of breakpoints.ranked()) {
    const px = parseInt(value, 10);
    const label = labelForBreakpoint(px);
    // Keep the most frequent value per label (ranked() is freq-desc, so first wins).
    if (!(label in bpObject)) bpObject[label] = value;
  }

  const result = {
    colors: colors.ranked().map((c, i) => ({
      ...c,
      name: namedForColor(c.value, namedColors) || `color-${i + 1}`,
    })),
    fonts: fonts.ranked().map((f) => ({
      ...f,
      googleFont: looksLikeGoogleFont(f.value),
      role: undefined, // role (heading/body) is assigned by the design-tokens skill
    })),
    spacing: spacingRanked,
    breakpoints: bpObject,
    radius: radius.ranked(),
    meta: { filesScanned: files.length, namedColors: Object.fromEntries(namedColors) },
  };

  process.stdout.write(JSON.stringify(result, null, 2) + "\n");
}

function namedForColor(value, namedColors) {
  for (const [name, v] of namedColors) {
    if (v.toLowerCase().replace(/\s+/g, "") === value.toLowerCase().replace(/\s+/g, "")) {
      return name.replace(/^--/, "");
    }
  }
  return null;
}

// Heuristic: multi-word title-case names are almost always real (often Google)
// font families; single generic tokens are not.
function looksLikeGoogleFont(name) {
  if (GENERIC_FONTS.has(name.toLowerCase())) return false;
  return /^[A-Z]/.test(name);
}

main();
