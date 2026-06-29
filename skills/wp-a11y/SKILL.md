---
name: wp-a11y
description: >-
  Condensed WCAG 2.2 AA rules for auditing WordPress theme templates and CSS.
  Used by the a11y-checker agent. Examples are written in plain PHP so they
  apply to classic, block, and page-builder themes.
user-invocable: false
allowed-tools: [Read, Grep, Glob]
---

# WordPress A11y Rules Reference

Target **WCAG 2.2 AA** for every WP Pro Max build. This skill is a rule set for the `a11y-checker` agent. It does not perform automated scans itself; it defines what to look for and how to report issues.

## Output format

For each issue, report:

1. **File and line** where the issue is located.
2. **WCAG rule violated** (e.g., `1.3.1 Info and Relationships`).
3. **Severity**: `critical` (total barrier), `important` (significant impact), `minor` (improvement).
4. **Suggested fix** with a short code example.

Return a structured summary:

- Total issues by severity.
- Issues list sorted by severity.
- Top 3 most urgent issues.

## 1. Semantic markup

- Exactly one `<h1>` per page.
- Heading levels must not skip (e.g., do not jump from `<h2>` to `<h4>`).
- Use landmark regions: `<header>`, `<nav>`, `<main>`, `<footer>`, `<section>`, `<article>`.
- When multiple `<nav>` elements exist, label each with `aria-label`.
- Prefer native semantic tags over generic `<div>` wrappers.

```php
<!-- Good -->
<nav aria-label="Primary">
  <ul>...</ul>
</nav>
<nav aria-label="Footer">
  <ul>...</ul>
</nav>

<!-- Bad -->
<div class="menu"><ul>...</ul></div>
```

## 2. Forms and interactions

- Every form control has an associated `<label>` (explicit `for`/`id` link).
- Mark required fields with `required` and `aria-required="true"`.
- Group related radio/checkbox sets with `<fieldset>` + `<legend>`.
- Link help text and errors with `aria-describedby`.
- Mark invalid fields with `aria-invalid="true"`.

```php
<!-- Good -->
<label for="email">Email</label>
<input type="email" id="email" name="email" required aria-required="true" aria-describedby="email-error">
<div id="email-error" class="error">Please enter a valid email.</div>

<!-- Bad -->
<input type="email" placeholder="Email">
```

## 3. Images and icons

- Informative `<img>` elements need descriptive `alt` text.
- Decorative `<img>` elements use `alt=""`.
- Decorative SVGs use `aria-hidden="true" focusable="false"`.
- Informative SVGs use `role="img"` and `aria-label`.

```php
<!-- Good: informative -->
<img src="team.jpg" alt="Three team members reviewing a project board.">

<!-- Good: decorative -->
<img src="divider.svg" alt="">

<!-- Good: decorative SVG -->
<svg aria-hidden="true" focusable="false">...</svg>
```

## 4. Keyboard and focus

- Never remove `:focus` outline without a visible replacement (`:focus-visible`).
- Use native interactive elements (`<button>`, `<a href>`) instead of `<div onclick>`.
- Only use `tabindex="0"` or `tabindex="-1"`; never positive values.
- Toggle widgets need `aria-expanded`, `aria-controls`, and `aria-haspopup` where appropriate.

```php
<!-- Good -->
<button class="menu-toggle" aria-expanded="false" aria-controls="primary-menu">Menu</button>

<!-- Bad -->
<div class="menu-toggle" onclick="toggleMenu()">Menu</div>
```

## 5. Colors and contrast

- Normal text contrast ratio ≥ 4.5:1; large text ≥ 3:1.
- UI components and graphics ≥ 3:1 against adjacent colors.
- Do not rely on color alone to convey meaning.
- Prefer relative units (`rem`, `em`, `%`) over fixed `px` for typography and spacing.

```php
/* Good */
.error { color: #c00000; }
.error::before { content: "Error: "; }

/* Bad */
.error { color: red; }
```

## 6. Links and navigation

- Skip link before repeated navigation: `<a href="#main">Skip to main content</a>`.
- Mark the current page link with `aria-current="page"`.
- Links that open in a new tab (`target="_blank"`) warn screen-reader users.

```php
<!-- Good -->
<a href="#main" class="skip-link">Skip to main content</a>
<a href="/" aria-current="page">Home</a>
<a href="https://example.com" target="_blank" rel="noopener noreferrer">External site <span class="screen-reader-text">(opens in new window)</span></a>

<!-- Bad -->
<a href="https://example.com" target="_blank">External site</a>
```

## 7. Dynamic content

- Announce live regions politely with `aria-live="polite"`.
- Trap focus inside modals while open; restore focus on close.
- Respect `prefers-reduced-motion` for animations.

```php
<div aria-live="polite" class="sr-only" id="cart-notice"></div>
```

## Severity guidance

- **Critical**: keyboard trap, missing form label on a required field, no accessible name on an interactive element, autoplaying media without pause.
- **Important**: skipped heading level, missing alt on informative image, low contrast on body text, missing skip link.
- **Minor**: redundant ARIA role, decorative image missing empty alt, non-semantic wrapper that does not affect navigation.

---

*Ported and rewritten for WP Pro Max from `alessioarzenton/claude-code-wp-toolkit` (GPL-3.0). Target license: MIT.*
