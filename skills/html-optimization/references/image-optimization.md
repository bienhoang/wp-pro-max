# Image Optimization Plan

The `optimize` stage emits a plan; transcoding happens later (scaffold/seed,
where image tooling and WP media import exist). Keep this stage planning-only.

## Per-image entry

```json
{
  "src": "assets/images/team-1.jpg",
  "role": "card",
  "formats": ["avif", "webp", "jpg"],
  "responsiveSizes": [320, 480, 768, 1024],
  "lazyLoad": true,
  "fetchPriority": "auto",
  "decoding": "async",
  "intrinsic": { "width": 1200, "height": 800 }
}
```

## Decision rules

| Image role | formats | sizes | loading | fetchpriority |
|------------|---------|-------|---------|---------------|
| hero / LCP | avif, webp, jpg | 768/1024/1600/1920 | eager | high |
| above-fold logo | svg or webp | intrinsic | eager | high |
| card / grid | avif, webp, jpg | 320/480/768 | lazy | auto |
| gallery / below-fold | avif, webp, jpg | 480/768/1024 | lazy | low |
| icon | svg | intrinsic | eager | auto |

## Format guidance
- Prefer **AVIF** then **WebP**, with the original format as `<picture>` fallback.
- Photographs → AVIF/WebP lossy ~q60-75. Flat graphics/logos → SVG or lossless.
- Strip metadata on export; keep color profile for photography.

## Responsive output

Generate `srcset` + `sizes` keyed to `designTokens.breakpoints` when present:

```html
<picture>
  <source type="image/avif" srcset="team-1-480.avif 480w, team-1-768.avif 768w" sizes="(max-width:768px) 100vw, 33vw">
  <source type="image/webp" srcset="team-1-480.webp 480w, team-1-768.webp 768w" sizes="(max-width:768px) 100vw, 33vw">
  <img src="team-1-768.jpg" width="1200" height="800" alt="…" loading="lazy" decoding="async">
</picture>
```

## CLS prevention
- Always emit `width`/`height` (or `aspect-ratio`) so layout is reserved.
- Reserve space for late-loading media (fonts, embeds) too.

## Hand-off
- WordPress side: the scaffold/seed stage imports via `wp media import` and can
  rely on a responsive-images/AVIF plugin (recorded in `plugins`) to serve the
  generated sizes. The plan here tells that stage exactly what to produce.
