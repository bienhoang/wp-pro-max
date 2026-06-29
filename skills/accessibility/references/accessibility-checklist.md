# Accessibility Checklist (WCAG 2.2 AA)

Consolidated pass/fail checklist for WP Pro Max builds. Use during
`html-optimization` (fix what you can) and `wp-qa` (verify before ship).

## Perceivable

### Text alternatives
- [ ] Every `<img>` has an `alt` attribute. Informative images describe content;
      decorative images use `alt=""`.
- [ ] SVG icons are `aria-hidden="true"` when decorative; meaningful SVGs have
      `role="img"` and a `<title>` (or `aria-label`).
- [ ] `<video>` / `<audio>` have captions/transcripts or a noted plan to add them.
- [ ] Complex charts/infographics have a text alternative nearby.

### Adaptable
- [ ] Content does not lose meaning or functionality when zoomed to 200%.
- [ ] Text can be resized up to 200% without assistive tech.
- [ ] Tables use `<th>` and `scope` (or `headers`/`id`) for data tables.

### Distinguishable
- [ ] Body text contrast ≥ **4.5:1** against its background.
- [ ] Large text (≥24px or ≥19px bold) contrast ≥ **3:1**.
- [ ] UI components and graphical objects have contrast ≥ **3:1**.
- [ ] Information is not conveyed by color alone.
- [ ] Text can be spaced (line-height ≥ 1.5, paragraph spacing ≥ 2× font-size) without clipping.

**Contrast quick formula (sRGB relative luminance):**

```
L = 0.2126*R + 0.7152*G + 0.0722*B   # each channel linearized:
                                       # c<=0.03928 ? c/12.92 : ((c+0.055)/1.055)^2.4
ratio = (Llighter + 0.05) / (Ldarker + 0.05)
```

When a brand color fails, record the pair and the nearest compliant adjustment
in `optimization.notes` or `qa.a11y.violations` for approval. Do not silently
overwrite brand values.

## Operable

### Keyboard accessible
- [ ] All functionality is available from a keyboard.
- [ ] No keyboard traps in custom widgets (modal, carousel, menu).
- [ ] Custom controls use expected keys: `Enter`/`Space` to activate,
      `Esc` to close, arrow keys for radios/tabs/menus.

### Enough time
- [ ] Auto-updating content can be paused, stopped, or hidden.
- [ ] Session timeouts can be extended.

### Seizures and physical reactions
- [ ] No content flashes more than 3 times per second.

### Navigable
- [ ] Page `<title>` is unique and describes the page.
- [ ] Focus order follows the visual/logical order.
- [ ] Focus indicator is visible on every focusable element.
- [ ] A "Skip to main content" link is the first focusable element before nav.
- [ ] Page purpose is clear from headings and links.

### Input modalities
- [ ] Target sizes are at least 24×24 CSS pixels (minimum; 44×44 preferred for
      touch).

## Understandable

### Readable
- [ ] `<html lang="...">` matches the primary page language.
- [ ] Language changes within content are marked with `lang`.

### Predictable
- [ ] Navigation appears in the same place across pages.
- [ ] Components with the same function are labelled consistently.
- [ ] Form submissions do not change context unexpectedly.

### Input assistance
- [ ] Required fields are indicated visually and programmatically.
- [ ] Error messages identify the field and describe how to fix it.
- [ ] Errors are associated with inputs via `aria-describedby` or `aria-errormessage`.

## Robust

- [ ] HTML validates without critical parsing errors.
- [ ] ARIA roles, states, and properties are valid and not redundant with native
      semantics.
- [ ] Custom components expose name, role, and value/state to assistive tech.

## WordPress-specific callouts

| Strategy | Check |
|----------|-------|
| Classic + ACF | Field labels map to visible `<label>`; help/error text uses `aria-describedby`. |
| Block / FSE | Core blocks supply most semantics; inspect custom blocks for empty toggles. |
| Page builder | Verify output HTML is not `div`-soup; disable motion widgets under reduced motion. |
| Sage / Roots | Keep Blade components semantic; test Alpine/Livewire focus management. |

## Output mapping

During optimization, append each fix to `optimization.a11yFixes`:

```json
{ "rule": "img-alt", "selector": "#hero img", "before": "missing", "after": "alt=\"…\"" }
```

During QA, aggregate into `qa.a11y`:

```json
{
  "byImpact": { "critical": 0, "serious": 0, "moderate": 1, "minor": 2 },
  "violations": [
    { "url": "http://localhost:8888/contact/", "id": "label",
      "impact": "serious", "help": "Form elements must have labels",
      "nodes": ["#message"] }
  ],
  "passed": false
}
```

`passed = (critical == 0 && serious == 0)`.

---

*Conventions adapted from [alessioarzenton/claude-code-wp-toolkit](https://github.com/alessioarzenton/claude-code-wp-toolkit) (GPL-3.0), rewritten for WP Pro Max (MIT).*
