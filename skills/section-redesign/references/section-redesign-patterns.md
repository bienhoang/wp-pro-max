# Section Redesign Patterns

Common transformations for the optimized HTML copy.

## Reorder sections

Use `section_reorder` with a selectors file listing sections in the desired order:

```bash
printf 'section.services\nsection.hero\n' > /tmp/order.txt
section_reorder "$OUTDIR/index.html" /tmp/order.txt
```

Update `analysis.pages[].sections[]` to match.

## Remove a section

```bash
section_remove "$OUTDIR/index.html" "section.testimonials"
```

Remove the corresponding entry from `analysis.pages[].sections[]`.

## Rewrite markup

1. `section_find` the existing section.
2. Build the new markup (preserve accessibility: headings, alt text, landmarks).
3. Write to a temp file and `section_replace`.

## Add a section

1. Choose an insertion point with a selector.
2. Write the new section HTML to a temp file.
3. `section_insert_before` or `section_insert_after`.
4. Append the new section id to `analysis.pages[].sections[]`.

## CSS-only changes

If the request is purely visual (e.g. "make hero full-bleed"), prefer editing the
optimized stylesheet rather than the markup. Keep selectors specific and avoid
`!important`.
