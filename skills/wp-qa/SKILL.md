---
name: wp-qa
description: >-
  Quality gate for a WP Pro Max build (stage `qa`). Runs visual regression of the
  rendered WordPress site against the source HTML per page and viewport
  (scripts/visual-diff.mjs), checks responsive layout at mobile/tablet/desktop,
  crawls internal links for 404s, runs WCAG accessibility checks (alt text, form
  labels, color contrast, landmarks, heading order), and measures Core Web Vitals
  (LCP/CLS/INP) via Lighthouse or Playwright. Summarizes pass/fail against a
  tolerance gate and sets qa.passed — this stage GATES ship. Use when validating a
  WordPress build, running visual diff or accessibility or performance checks, or
  when the pipeline reaches the `qa` stage. Reads analysis.pages, urls.local,
  source; writes qa.{visualDiff,tolerance,brokenLinks,a11y,coreWebVitals,passed}.
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# WP QA (stage `qa`) — the ship gate

Validate that the live WordPress site faithfully reproduces the source and meets
quality bars before deploy. This stage **gates ship**: `wp-ship` must refuse to
run unless `qa.passed == true` (or the user explicitly overrides). Be honest —
never set `passed` to satisfy the pipeline; report real failures.

## Inputs (from `wp-build.json`)

| Field | Use |
|-------|-----|
| `analysis.pages[]` | Pages to compare (path → title/role/slug). |
| `urls.local` | Base URL of the running WP site (e.g. `http://localhost:8888`). |
| `source` (`htmlPaths` / `optimization.outputDir`) | Source pages to diff against. |
| `qa.tolerance` | Max allowed per-pixel diff ratio (default `0.05`). |

## 0. Resume guard + setup

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh"
wpbuild_is_done qa && [[ "${1:-}" != "--force" ]] && { echo "qa done"; exit 0; }
wpbuild_progress qa in-progress
LOCAL="$(wpbuild_get '.urls.local // .env.localUrl // "http://localhost:8888"')"
TOL="$(wpbuild_get '.qa.tolerance // 0.05')"
OUTDIR="$(wpbuild_get '.optimization.outputDir // "."')"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" option get siteurl >/dev/null || { echo "wp-env not reachable — start it first"; exit 1; }
```

Ensure tooling once (Node deps for the visual diff + Lighthouse):
`npm i -D playwright pixelmatch pngjs lighthouse && npx playwright install chromium`.
If install is not possible, record which checks were skipped in the report
(do **not** silently pass).

## 1. Visual regression + responsive (per page × viewport)

For each `analysis.pages[]` entry, map the source file/URL to its WP URL
(home → `/`, page slug → `/<slug>/`), then run the shared diff at the three
responsive breakpoints (desktop `1280`, tablet `768`, mobile `375`):

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/visual-diff.mjs" \
  --source "$OUTDIR/about.html" \
  --target "$LOCAL/about/" \
  --viewports 1280,768,375 \
  --threshold "$TOL" \
  --name about \
  --out qa/diff
```

The script exits non-zero if any viewport exceeds the threshold and writes
`qa/diff/<name>-report.json` (per-viewport `diffRatio`/`passed`) plus
side-by-side images. Collect every page report into `qa.visualDiff[]`.
Responsive coverage is satisfied by the mobile/tablet/desktop viewports above —
flag any page whose mobile diff is much worse than desktop (layout breakage).

See `references/responsive-and-visual.md` for URL mapping and triage of false
positives (fonts, lazy media, dynamic dates).

## 2. Broken-link crawl (internal 404s)

Crawl internal links starting from `urls.local`, record any non-2xx/3xx target.
Use the bundled crawler:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/wp-qa/references/crawl-links.sh" "$LOCAL" > qa/links.json
```

Write the failing URLs to `qa.brokenLinks[]`. Any internal 404 is a gate
failure. External links are reported as warnings, not gate failures.

## 3. Accessibility (WCAG)

Run automated WCAG checks per page and aggregate. Prefer axe-core injected via
Playwright (`references/a11y-axe.mjs`); fall back to the manual checklist in
`skills/accessibility/references/accessibility-checklist.md`. For remediation
guidance before re-running QA, invoke `/wp-pro-max:accessibility`. Cover at
minimum:

- **Images** have meaningful `alt` (decorative → empty `alt=""`).
- **Form controls** have associated `<label>` / `aria-label`.
- **Color contrast** ≥ 4.5:1 for body text, 3:1 for large text.
- **Landmarks** present (`header`/`nav`/`main`/`footer` or ARIA roles), one `main`.
- **Heading order** has a single `h1` and no skipped levels.

Write `qa.a11y = { violations: [...], byImpact: {critical,serious,moderate,minor},
passed }`. Critical/serious violations fail the gate.

## 4. Core Web Vitals (LCP / CLS / INP)

Measure field-proxy metrics per key page (home + top templates). Prefer
Lighthouse for lab CWV; use the Playwright PerformanceObserver fallback in
`references/core-web-vitals.mjs` when Lighthouse is unavailable:

```bash
npx lighthouse "$LOCAL/" --only-categories=performance \
  --output=json --output-path=qa/cwv-home.json --chrome-flags="--headless" --quiet
```

Targets (good thresholds): **LCP ≤ 2.5s**, **CLS ≤ 0.1**, **INP ≤ 200ms**.
Write `qa.coreWebVitals = { "<url>": { lcp, cls, inp, passed }, ... }`.
CWV are reported and gate by default, but the tolerance gate (step 5) lets the
user downgrade them to warnings for a local-only build.

## 5. Tolerance gate → `qa.passed`

Aggregate all checks into a single verdict. Default gating rules:

| Check | Gates ship? |
|-------|-------------|
| Visual diff per viewport ≤ tolerance | Yes |
| Internal broken links == 0 | Yes |
| A11y critical/serious == 0 | Yes |
| CWV within targets | Yes (downgrade-able) |

```bash
wpbuild_set '.qa.tolerance' "$TOL"
wpbuild_set '.qa.visualDiff'   "$(cat qa/visual-summary.json)"
wpbuild_set '.qa.brokenLinks'  "$(jq '[.[] | select(.status>=400) | .url]' qa/links.json)"
wpbuild_set '.qa.a11y'         "$(cat qa/a11y-summary.json)"
wpbuild_set '.qa.coreWebVitals' "$(cat qa/cwv-summary.json)"

PASSED=true
# ... compute from the four checks above; set false on any hard failure ...
wpbuild_set '.qa.passed' "$PASSED"
if [[ "$PASSED" == "true" ]]; then
  wpbuild_progress qa done "visual+links+a11y+cwv passed (tol=$TOL)"
else
  wpbuild_progress qa failed "see qa.* for failing checks"
fi
```

Print a concise human summary: per-page worst diffRatio, broken-link count,
a11y violations by impact, CWV per page, and the final PASS/FAIL. On FAIL, list
the top offending pages/checks so the orchestrator can route fixes back to
`html-optimization`, `theme-conversion`, or `seed-content`.

## Delegation

Heavy fix work (theme markup for a11y/CLS, template diffs) → **wp-theme-developer**
agent with the failing report, target theme path, and acceptance criteria
(diffRatio ≤ tolerance; zero critical a11y; CWV targets). QA itself only
measures and gates — it does not edit the theme.

See: `references/responsive-and-visual.md`,
`skills/accessibility/references/accessibility-checklist.md`,
`references/a11y-axe.mjs`, `references/core-web-vitals.mjs`,
`references/crawl-links.sh`, `skills/accessibility/SKILL.md`.
