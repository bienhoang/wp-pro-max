# Accessibility Checklist (WCAG 2.1 AA, pragmatic pass)

Apply during the `optimize` stage. Each fix applied is appended to
`optimization.a11yFixes`; unresolved risks go to `optimization.notes`.

## Images & media
- [ ] Every `<img>` has `alt`. Informative → describes content; decorative →
      `alt=""` (and `role="presentation"` if needed).
- [ ] SVG icons: `aria-hidden="true"` when decorative; `role="img"` + `<title>`
      when meaningful.
- [ ] `<video>`/`<audio>`: captions/track noted if present.

## Document structure
- [ ] Exactly one `<h1>` per page.
- [ ] Heading levels increase by one; no skips.
- [ ] `lang` on `<html>`.
- [ ] Page `<title>` is unique and descriptive.

## Landmarks
- [ ] `<main>` wraps primary content (one per page).
- [ ] `<nav>` has `aria-label` when multiple navs exist.
- [ ] `<header>`/`<footer>` used for banner/contentinfo.
- [ ] Skip-to-content link before nav.

## Forms
- [ ] Each control has a programmatic label (`<label for>`/`aria-label`).
- [ ] Related controls grouped in `<fieldset>` with `<legend>`.
- [ ] Required fields marked with `required` + visible indicator.
- [ ] Error messaging associated via `aria-describedby`.

## Interactive
- [ ] Actions use `<button>`; navigation uses `<a href>`. No click-only `<div>`.
- [ ] Visible focus indicator on all focusable elements.
- [ ] Toggles expose `aria-expanded` / `aria-controls`.
- [ ] Keyboard operable (no hover-only menus without focus equivalent).

## Color & contrast
- [ ] Body text ≥ 4.5:1; large text (≥24px or ≥19px bold) ≥ 3:1.
- [ ] UI/graphical boundaries ≥ 3:1.
- [ ] Information not conveyed by color alone.

Contrast formula (sRGB relative luminance):

```
L = 0.2126*R + 0.7152*G + 0.0722*B   # each channel linearized:
                                       # c<=0.03928 ? c/12.92 : ((c+0.055)/1.055)^2.4
ratio = (Llighter + 0.05) / (Ldarker + 0.05)
```

When a brand color fails, do not overwrite it. Record the failing pair and the
nearest compliant adjustment in `notes` for user approval.

## Motion & timing
- [ ] Respect `prefers-reduced-motion` for animations.
- [ ] No content auto-refresh/flashing faster than 3x/sec.
