# Component Reuse

The `analysis.components[]` list records repeated blocks detected during
`html-analysis`. When redesigning a section, reuse these canonical shapes to keep
the conversion stage simple.

## Reuse rules

- `header`, `footer`, `nav` → edit once and mirror the change to every page that
  shares the component.
- `hero`, `card`, `grid`, `cta`, `form` → clone an existing occurrence as the
  base for a new section, then customize.
- `other` → inspect occurrences; if the component appears on multiple pages,
  keep the markup consistent.

## Procedure

1. Read `analysis.components[]`.
2. Find a representative occurrence with `section_find`.
3. Copy the outer HTML as the scaffold for the new/rewritten section.
4. Replace content and classes; preserve structure.
