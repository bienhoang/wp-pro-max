# SEO Plugin Configuration via WP-CLI

Postmeta keys and option commands for the three common SEO plugins. Resolve the
post ID first: `wp post list --post_type=page --name=<slug> --field=ID`.

## Per-page meta keys by plugin

| Field | Yoast (`wordpress-seo`) | Rank Math (`seo-by-rank-math`) | SEOPress (`wp-seopress`) |
|-------|-------------------------|-------------------------------|--------------------------|
| Title | `_yoast_wpseo_title` | `rank_math_title` | `_seopress_titles_title` |
| Description | `_yoast_wpseo_metadesc` | `rank_math_description` | `_seopress_titles_desc` |
| OG title | `_yoast_wpseo_opengraph-title` | `rank_math_facebook_title` | `_seopress_social_fb_title` |
| OG description | `_yoast_wpseo_opengraph-description` | `rank_math_facebook_description` | `_seopress_social_fb_desc` |
| OG image | `_yoast_wpseo_opengraph-image` | `rank_math_facebook_image` | `_seopress_social_fb_img` |
| Twitter title | `_yoast_wpseo_twitter-title` | `rank_math_twitter_title` | `_seopress_social_twitter_title` |
| Twitter desc | `_yoast_wpseo_twitter-description` | `rank_math_twitter_description` | `_seopress_social_twitter_desc` |
| Canonical | `_yoast_wpseo_canonical` | `rank_math_canonical_url` | `_seopress_robots_canonical` |
| Noindex | `_yoast_wpseo_meta-robots-noindex` (`1`/`0`) | `rank_math_robots` (`["noindex"]`) | `_seopress_robots_index` (`yes`=noindex) |

Yoast template variables `%%sep%%`, `%%sitename%%`, `%%title%%` are expanded by
the plugin at render time — safe to store literally.

## Site-wide options

Yoast knowledge-graph (Organization/Person) + social:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" option patch update wpseo_titles company_or_person "company"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" option patch update wpseo_titles company_name "Acme Studio"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" option patch update wpseo_titles company_logo "https://acme.com/logo.png"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" option patch update wpseo_social facebook_site "https://facebook.com/acme"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" option patch update wpseo_social twitter_site "acme"
```

Rank Math stores titles/meta defaults in `rank-math-options-titles`;
SEOPress in `seopress_titles_option_name` / `seopress_social_option_name`.
Use `wp option get <name> --format=json` to inspect before patching.

## Sitemap endpoints

| Plugin | XML sitemap URL |
|--------|-----------------|
| Yoast | `/sitemap_index.xml` |
| Rank Math | `/sitemap_index.xml` |
| SEOPress | `/sitemaps.xml` |
| WP core (no plugin) | `/wp-sitemap.xml` (default since WP 5.5) |

Enable Yoast sitemap (on by default; force on):
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" option patch update wpseo enable_xml_sitemap 1` (key varies by
version; verify with `wp option get wpseo --format=json`).

## robots.txt

WordPress serves a virtual robots.txt. Override via the SEO plugin UI/option or a
filter. Baseline:

```
User-agent: *
Disallow: /wp-admin/
Allow: /wp-admin/admin-ajax.php
Sitemap: https://acme.com/sitemap_index.xml
```

After ship, the sitemap line must use the **production** host (the `ship` stage's
`wp search-replace` handles URL bodies; confirm robots/sitemap host post-migrate).
