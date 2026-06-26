# Visual Regression & Responsive — mapping and triage

How to drive `scripts/visual-diff.mjs` from the manifest and how to read results.

## Source → WP URL mapping

Build the target URL from each `analysis.pages[]` entry and `urls.local`:

| `role` | Source | WP URL |
|--------|--------|--------|
| `home` | `index.html` | `<local>/` |
| `page` | `<slug>.html` | `<local>/<slug>/` |
| `post` / `single` | `<slug>.html` | `<local>/<slug>/` (or the CPT permalink) |
| `archive` | `<type>.html` | `<local>/<type>/` |
| `landing` | `<slug>.html` | `<local>/<slug>/` |

The source side is the **optimized** HTML when `optimization.outputDir` is set;
otherwise fall back to `source.htmlPaths` (or the live `source.url` page).

## Viewports = responsive coverage

Run the three standard breakpoints in one call so responsive layout is checked
alongside the pixel diff:

- `1280` desktop
- `768`  tablet
- `375`  mobile

A page that passes at `1280` but fails badly at `375` indicates a responsive
breakage (overflow, unstacked grid, off-canvas nav not collapsing). Flag these
specifically; they usually map to a missing media query in the converted theme.

## Reading the report

`<name>-report.json` per page:

```json
{
  "source": "...", "target": "...", "threshold": 0.05,
  "results": [
    { "viewport": 1280, "diffRatio": 0.012, "passed": true,  "artifacts": {...} },
    { "viewport": 375,  "diffRatio": 0.089, "passed": false, "artifacts": {...} }
  ],
  "passed": false
}
```

Aggregate every page report into `qa.visualDiff[]` — keep `{name, viewport,
diffRatio, passed, sideBySide}` so a human can open the montage for any failure.

## Triaging false positives

Pixel diffs are noisy. Before calling a diff a real regression, rule out:

- **Web fonts** still swapping at screenshot time → the script waits for
  `document.fonts.ready`, but a slow CDN can still flash. Re-run; if stable,
  it is real.
- **Lazy images** below the fold → the script scrolls the page to force-load;
  ensure the WP side actually serves the imported media (not 404 placeholders).
- **Dynamic content** (dates, “3 hours ago”, randomized testimonials, cookie
  banners) → mask by raising `--threshold` for that page only, or note it as an
  accepted diff in the summary. Do not globally inflate the gate tolerance.
- **Scrollbar width** differences between source and WP chrome → minor, ignore
  if the diff band is only at the right edge.

## Tuning the gate

`qa.tolerance` (default `0.05` = 5% of pixels) is the global gate. For a single
volatile page, pass a looser `--threshold` on its individual run and record the
exception in the summary rather than weakening the global tolerance for all
pages.
