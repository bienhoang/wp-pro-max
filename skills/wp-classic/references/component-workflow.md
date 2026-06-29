# Component Workflow — Classic WordPress Theme

Generic workflow for turning a design requirement or optimized HTML section into
a reusable classic PHP component. This version is Figma-free; use it inside WP
Pro Max when the source design has already been analyzed and tokenized.

Conventions adapted from [alessioarzenton/claude-code-wp-toolkit](https://github.com/alessioarzenton/claude-code-wp-toolkit) (GPL-3.0), rewritten for WP Pro Max (MIT).

## 11-Step Process

### 1–3. Design analysis

Read the relevant inputs before writing code:

- `wp-build.json` — strategy, `designTokens`, `analysis.components[]`, `contentModel`.
- The optimized HTML section that this component replaces.
- Any existing `parts/` or `templates/` in the target theme to match conventions.

Identify the component type (hero, card, cta, section, etc.), the tokens it
uses, and whether it is reusable or page-specific.

### 4. Check existing components

- Check `templates/` for page templates (if the theme uses them).
- Check `parts/` for reusable template partials.
- Check `inc/` for helper functions.
- Decide: reuse an existing partial with `get_template_part()` or create a new one.

### 5. Decomposition rules

**Reusable partials** — if the section can be broken into reusable pieces, create
partials in `parts/` and include them with:

```php
get_template_part( 'parts/name', 'variant', $args );
```

**Cards** — if the component is a card, place it in `parts/card/card-{type}.php`.

### 5.5. Token mapping

Translate design values to project tokens before writing CSS or HTML.

#### Spacing

| Source px | Tailwind (if configured) | rem |
|-------------------|--------------------------|-----|
| 4px  | `*-1`  | 0.25rem |
| 8px  | `*-2`  | 0.5rem |
| 12px | `*-3`  | 0.75rem |
| 16px | `*-4`  | 1rem |
| 24px | `*-6`  | 1.5rem |
| 32px | `*-8`  | 2rem |
| 48px | `*-12` | 3rem |
| 64px | `*-16` | 4rem |

If Tailwind is **not** configured, use CSS custom properties or direct rem values.

#### Colors

1. Find the source hex (e.g. `#164d7f`).
2. Search the theme CSS for the matching CSS variable.
3. Use the semantic variable (`var(--color-primary)`) or the utility class.

**Priority**: CSS variable > utility class > direct hex. Never hardcode a hex if
a variable exists.

### 6. Create CSS

- Location: `assets/css/components/` or the project's component folder.
- Use CSS variables from `designTokens` for colors, spacing, radius, fonts.
- Use BEM naming if the project uses it (`block__element--modifier`).

### 7. Create PHP template

- Location: `parts/{name}.php` or `templates/{name}.php` for page-specific layouts.
- Use a root `<section>` tag for ACF blocks and macro components (excluding
  header/footer).
- Include a header docblock documenting `$args`.
- Set defaults: `$title = isset( $args['title'] ) ? $args['title'] : '';`.
- Escape all output: `esc_html()`, `esc_attr()`, `esc_url()`, `wp_kses_post()`.
- Use semantic tags and `aria-*` attributes where needed.

### 8. Automatic validation

Run sequentially — do not skip steps:

a. **Build** — `npm run build` (if configured). Verify it succeeds.

b. **Quick a11y check** on the generated template:
   - Correct semantic tags (no `<div>` where `<button>`, `<a>`, `<nav>` is needed).
   - `aria-*` attributes present where needed.
   - Decorative SVGs use `aria-hidden="true" focusable="false"`.
   - Focus ring is not removed (`outline: none` only with an alternative).
   - Root `<section>` tag is used where applicable.
   - All outputs are escaped.
   - Fix violations before proceeding.

### 9. Visual verification

- If the site is running in wp-env, load the page and compare to the source section.
- If Storybook is configured, add an example.
- Otherwise, tell the user how to test the component.

### 10. Update memory

Record new reusable patterns or missing tokens so later stages can reuse them:

- Append novel reusable patterns to `.claude/agent-memory/` or `wp-build.json`
  notes under **Learned patterns**.
- Append missing or mismatched tokens to `wp-build.json` notes under
  `designTokens.notes` (or `.claude/agent-memory/` **Recurring errors to avoid**).
- Do not overwrite existing data — only append.

### 11. Completion

Report back with:

- Created/modified files (CSS, PHP template, helpers).
- Source section reference.
- Validation result (build + a11y).
- Any warnings (missing tokens, optional `templates/` vs root decision).

## PHP template example

```php
<?php
/**
 * Component: Service Card
 *
 * @package Acme
 *
 * @param array $args {
 *     @type string $title    Optional. Card title.
 *     @type string $excerpt  Optional. Excerpt.
 *     @type string $link     Optional. Destination URL.
 *     @type string $variant  Optional. primary|secondary.
 * }
 */

$title   = isset( $args['title'] ) ? $args['title'] : '';
$excerpt = isset( $args['excerpt'] ) ? $args['excerpt'] : '';
$link    = isset( $args['link'] ) ? $args['link'] : '#';
$variant = isset( $args['variant'] ) ? $args['variant'] : 'primary';

$classes = 'card-service';
if ( 'primary' !== $variant ) {
    $classes .= ' card-service--' . esc_attr( $variant );
}
?>
<section class="<?php echo esc_attr( $classes ); ?>">
    <h3 class="card-service__title">
        <a href="<?php echo esc_url( $link ); ?>"><?php echo esc_html( $title ); ?></a>
    </h3>
    <?php if ( $excerpt ) : ?>
        <p class="card-service__excerpt"><?php echo esc_html( $excerpt ); ?></p>
    <?php endif; ?>
</section>
```

## Component checklist

**Design & code**:
- [ ] CSS naming is consistent (BEM or project convention).
- [ ] Colors use CSS variables — no hardcoded hex.
- [ ] PHP template documents `$args` in the header docblock.
- [ ] Defaults are set and all output is escaped.
- [ ] Root `<section>` tag is used for ACF blocks and macro components.

**Accessibility**:
- [ ] SVG icons use `aria-hidden="true" focusable="false"`.
- [ ] Visible focus ring is preserved.
- [ ] Semantic tags are used (no `<div onclick>`, no `<a role="button">`).
- [ ] `aria-*` attributes are present where needed.

**Validation**:
- [ ] Build succeeds (if a bundler is configured).
- [ ] Quick a11y check passes.

**Memory**:
- [ ] `.claude/agent-memory/` or `wp-build.json` notes are updated if new patterns
      or missing tokens are discovered.
