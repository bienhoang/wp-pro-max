# Theme Strategy Decision Rubric

The `analyze` stage recommends one backend. The `theme-conversion` stage later
loads a matching reference (`classic-acf`, `block-fse`, `page-builder`).

## The three strategies

| Strategy | What it produces | Best when |
|----------|------------------|-----------|
| `classic-acf` | PHP templates + `get_template_part` + ACF field groups (JSON in `acf-json/`) | Marketing/brochure sites with clear repeated record types; client edits structured fields; dev owns layout |
| `block-fse` | `theme.json` + block templates + patterns; content in native block editor | Content/editorial sites; want global styles + Site Editor; modern WP-native maintenance |
| `page-builder` | Elementor/Bricks templates; layout data in `_elementor_data` postmeta | Heavy bespoke visual layouts; non-technical maintainers already using a builder |

## Scoring

Tally signals from the analysis; highest bucket wins. Ties break toward
`classic-acf` (most portable) unless interactivity is high.

**classic-acf signals**
- 2+ repeated record components (team, services, portfolio, events).
- Structured, field-like content (label/value pairs, metadata badges).
- Requirement: "client should edit text/images but not layout."

**block-fse signals**
- Content-led pages, long-form articles, blog-centric IA.
- Few unique layouts; reuse via patterns is natural.
- Requirement: "use the native editor / Site Editor / global styles."

**page-builder signals**
- Many one-off, visually rich sections; animation-heavy.
- Source already exported from a builder, or maintainers expect drag-drop.
- Requirement: "marketing team edits pages visually without code."

## Interactivity modifier

Heavy JS (sliders, tabs, modals, scroll animation via GSAP/Swiper/Alpine):
- pushes away from plain `classic-acf` static templates;
- favors `block-fse` (interactive blocks) or `page-builder` (built-in widgets).

## Output

Set `strategy` only if the user has not already chosen one. Always record the
rationale in `progress.analyze.notes` and the human summary, e.g.:

> strategy=classic-acf — 3 repeated record types (service, team, testimonial),
> low interactivity, client wants field editing not layout control.

If a user-set `strategy` conflicts with the recommendation, keep the user's
choice and note the disagreement for the orchestrator to surface.
