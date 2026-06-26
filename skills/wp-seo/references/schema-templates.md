# schema.org JSON-LD Templates

Emit these as `<script type="application/ld+json">` blocks. Prefer generating via
`claude-seo:seo-schema` (validates against Google's rich-results requirements);
these templates are the fallback and the contract for what `seo.schemaTypes`
should contain. Omit any field you cannot populate from real data — never invent
ratings, prices, or dates.

## Organization (site-wide, once)

```json
{
  "@context": "https://schema.org",
  "@type": "Organization",
  "@id": "https://acme.com/#organization",
  "name": "Acme Studio",
  "url": "https://acme.com/",
  "logo": "https://acme.com/logo.png",
  "sameAs": ["https://facebook.com/acme", "https://twitter.com/acme"]
}
```

## WebSite (site-wide, once; enables sitelinks search box)

```json
{
  "@context": "https://schema.org",
  "@type": "WebSite",
  "@id": "https://acme.com/#website",
  "url": "https://acme.com/",
  "name": "Acme Studio",
  "publisher": { "@id": "https://acme.com/#organization" },
  "potentialAction": {
    "@type": "SearchAction",
    "target": "https://acme.com/?s={search_term_string}",
    "query-input": "required name=search_term_string"
  }
}
```

## BreadcrumbList (every non-home page, from menu/IA)

```json
{
  "@context": "https://schema.org",
  "@type": "BreadcrumbList",
  "itemListElement": [
    { "@type": "ListItem", "position": 1, "name": "Home", "item": "https://acme.com/" },
    { "@type": "ListItem", "position": 2, "name": "About", "item": "https://acme.com/about/" }
  ]
}
```

## Article (post / single)

```json
{
  "@context": "https://schema.org",
  "@type": "Article",
  "headline": "Post title (<=110 chars)",
  "image": ["https://acme.com/wp-content/uploads/hero.jpg"],
  "datePublished": "2026-06-26T08:00:00+07:00",
  "dateModified": "2026-06-26T08:00:00+07:00",
  "author": { "@type": "Person", "name": "Author Name" },
  "publisher": { "@id": "https://acme.com/#organization" },
  "mainEntityOfPage": { "@type": "WebPage", "@id": "https://acme.com/post-slug/" }
}
```

## Product (product CPT — only fields you actually have)

```json
{
  "@context": "https://schema.org",
  "@type": "Product",
  "name": "Product name",
  "image": ["https://acme.com/wp-content/uploads/product.jpg"],
  "description": "Real product description.",
  "brand": { "@type": "Brand", "name": "Acme" },
  "offers": {
    "@type": "Offer",
    "priceCurrency": "VND",
    "price": "1990000",
    "availability": "https://schema.org/InStock",
    "url": "https://acme.com/product-slug/"
  }
}
```

`aggregateRating`/`review` only when real review data exists in the content
model — Google penalizes fabricated review markup.

## Injection

- With an SEO plugin: Yoast/Rank Math already output Organization/WebSite/
  Breadcrumb graph — configure their entity settings instead of double-emitting.
  Add Article/Product via the plugin's schema feature or a head filter.
- Without a plugin: emit via the head template in `theme-head-fallback.php`,
  keyed by page role. Validate with `claude-seo:seo-schema` or the Rich Results
  Test before recording `seo.schemaTypes`.
