# Component Detection — heuristics & examples

Goal: identify reusable UI components and content-bearing repeated structures so
later stages can map them to template parts, blocks/patterns, or CPTs.

## Repetition signal

A block is a **component candidate** when the same DOM shape (tag + class
skeleton) appears multiple times. Track two flavors:

- **Chrome components** (1–2 occurrences, structural): header, footer, nav, hero.
  → become `get_template_part` / block templates / global header-footer.
- **Record components** (3+ occurrences, content-bearing): cards in a grid.
  → flag as CPT/repeater candidates for the `model` stage.

## Grep patterns (starting points)

```bash
# Headers / footers / nav
grep -rEoi '<(header|footer|nav)[^>]*>' SRC
grep -rEoi 'role="(banner|contentinfo|navigation)"' SRC

# Card-like repeated blocks (class contains card/item/tile/box + has heading)
grep -rEoi 'class="[^"]*(card|item|tile|box|feature|service|member|portfolio)[^"]*"' SRC

# Grids
grep -rEoi 'class="[^"]*(grid|row|columns|cards|list)[^"]*"' SRC

# Heroes / CTAs
grep -rEoi 'class="[^"]*(hero|banner|jumbotron|masthead)[^"]*"' SRC
grep -rEoi 'class="[^"]*(cta|call-to-action)[^"]*"' SRC

# Forms
grep -rEoi '<form[^>]*>' SRC
```

## Counting occurrences

Count distinct rendered instances, not class string matches. For a grid of 6
cards, `occurrences = 6`. Use a quick pass:

```bash
grep -rEoi 'class="[^"]*service-card[^"]*"' SRC | wc -l
```

When the same component appears on several pages, sum across files and note the
page list in the component `name` context.

## Field inference (preview for `model` stage)

For each record component, list the fields you see inside one instance:

| Visible element | Likely field |
|-----------------|--------------|
| `<img>` | image / featured image |
| top `<h2>/<h3>` | title |
| paragraph | description / excerpt |
| `<a href>` button | link / cta_url |
| price / number badge | meta (number) |
| `<ul>` of tags | taxonomy terms |
| icon + label rows | repeater |

Record these as informal notes in the component entry so `content-modeling` can
turn them into ACF fields, block bindings, or builder dynamic tags.

## False positives to avoid

- Utility wrappers (`.container`, `.wrapper`, `.row`) with no content identity.
- Single-use layout sections counted as repeated components.
- Decorative `<div>` soup — prefer landmark and heading structure as the spine.
