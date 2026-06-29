---
name: accessibility
description: >-
  Accessibility audit and remediation guide for WP Pro Max builds. Use when the
  user asks about WCAG compliance, keyboard navigation, screen-reader support,
  color contrast, alt text, heading order, focus indicators, or accessibility
  fixes. Reads source/optimized HTML or theme templates; produces a checklist and
  optional known-issues handoff. Delegates heavy markup changes to
  wp-theme-developer or html-optimization.
user-invocable: true
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# Accessibility (`a11y`)

Make the WordPress build usable for everyone. Target **WCAG 2.2 AA** and
separate what automated tools can prove from what a human must review.

## When to use

- The user mentions "accessibility", "a11y", "WCAG", "screen reader",
  "keyboard navigation", "contrast", "alt text", or "focus".
- The pipeline reaches the `optimize` or `qa` stage and a11y checks need
  interpretation.
- A handoff needs a documented list of outstanding accessibility issues.

## Relationship to other skills

- `html-optimization` owns the `optimize` stage and applies concrete a11y fixes
  (alt text, heading order, landmarks, form labels, contrast notes).
- `wp-qa` owns the `qa` gate and runs automated checks (`references/a11y-axe.mjs`)
  plus the manual checklist.
- `wp-handoff` can emit a `docs/a11y-known-issues.md` report from the template in
  this skill.

## WCAG 2.2 AA target

Organize work around the **POUR** principles:

| Principle | What it means for WordPress |
|-----------|-----------------------------|
| **Perceivable** | Text alternatives for images, captions/transcripts for media, adaptable layout, distinguishable colors (contrast ≥ 4.5:1, large text ≥ 3:1). |
| **Operable** | Keyboard access, visible focus, no keyboard traps, skip links, enough time, no seizures/flashing, clear navigation. |
| **Understandable** | Readable language, predictable behavior, helpful error identification and labels. |
| **Robust** | Valid HTML, correct ARIA, names/roles/values exposed to assistive tech. |

## Automated vs manual

**Automated tools can catch:**

- Missing `alt` attributes on `<img>`.
- Form controls without labels.
- Color-contrast ratios (computed).
- Missing page language or title.
- Duplicate or skipped heading levels.
- Missing landmarks or multiple `<main>` elements.

**Manual review is required for:**

- Whether `alt` text is *meaningful* (not just present).
- Focus order and logical tab path.
- Screen-reader flow and verbosity.
- Whether motion/resizing breaks content.
- Whether complex widgets (tabs, modals, carousels) expose the right state.

## WordPress-relevant rules

1. **Semantic landmarks** — one `<main>`, labelled `<nav aria-label>` when more
   than one nav exists, `<header>` and `<footer>` for banner/contentinfo.
2. **Heading order** — exactly one `<h1>` per page; levels increase by one.
3. **ARIA only when necessary** — prefer native HTML (`<button>`, `<nav>`,
   `<details>`); avoid redundant roles (`role="button"` on a `<button>`).
4. **Keyboard support** — every interactive element reachable via Tab; custom
   controls listen to `Enter`, `Space`, and arrow keys.
5. **Skip links** — a "Skip to main content" link before repeated navigation.
6. **Focus visibility** — never remove `:focus` outline without a replacement;
   ensure `:focus-visible` is obvious.
7. **Links vs buttons** — use `<a href>` for navigation, `<button>` for actions.

## Strategy notes

- **Classic + ACF** — templates control markup. Ensure field labels in ACF map to
  visible labels and `aria-describedby` for help/error text.
- **Block / FSE** — rely on core blocks' built-in a11y (headings, lists,
  navigation block). Avoid custom blocks that emit empty buttons or div-based
  toggles.
- **Page builder (Elementor/Bricks)** — inspect output HTML; disable motion
  widgets when `prefers-reduced-motion` is set; verify nav markup is not
  div-soup.
- **Sage / Roots** — keep Blade components semantic; test keyboard focus through
  Alpine/Livewire interactions.

## Testing commands

Run the automated axe check (preferred):

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/wp-qa/references/a11y-axe.mjs" \
  --url "http://localhost:8888" \
  --out qa/a11y-summary.json
```

Manual fallback when axe cannot run:

```bash
curl -s "http://localhost:8888/" | grep -E '<(img|input|select|textarea|button|a |h[1-6]|main|nav|header|footer|html)'
```

Then walk the checklist in `references/accessibility-checklist.md`.

## Output

- `qa.a11y` — aggregated violations from automated + manual checks.
- `optimization.a11yFixes` — fixes applied during optimization.
- `docs/a11y-known-issues.md` — handoff report from
  `references/known-issues-template.md`.

## References

- `references/accessibility-checklist.md` — consolidated WCAG 2.2 AA pass/fail
  checklist.
- `references/known-issues-template.md` — handoff template for outstanding
  issues.
- `skills/wp-qa/SKILL.md` — QA gate and automated checks.
- `skills/html-optimization/SKILL.md` — optimization-stage fixes.

---

*Conventions adapted from [alessioarzenton/claude-code-wp-toolkit](https://github.com/alessioarzenton/claude-code-wp-toolkit) (GPL-3.0), rewritten for WP Pro Max (MIT).*
