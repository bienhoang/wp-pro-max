# Theme customization — logos + deep colors + reset

The canonical contract for the end-user branding features baked into every
generated theme: a **header + separate footer logo**, **deep color editing**
(every `:root` color token), and a **reset-to-defaults** path. Defaults come from
`designTokens`. Strategy-native:

- `classic-acf` → a custom WordPress **Customizer** UI (Phase 2).
- `block-fse` → native **Global Styles** for colors/reset + a small custom
  **footer-logo** control (Phase 3).
- `page-builder` → native **Global Colors / Site Identity** + a host-theme
  **footer-logo** control (Phase 3).

This file is the single source of design. Phase 2/3 reference it instead of
re-explaining; the strategy references carry the actual PHP/JS templates.

---

## 1. The color-token registry

`scaffold` derives one registry from `designTokens.colors[]` and passes it to the
theme agent. It is the **single source** feeding control registration, the
inline-CSS emitter, and reset.

### Source entry (curated, from the `tokens` stage)

`designTokens.colors[]` entries have the shape `{ name, slug, value, role }`
(design-tokens/SKILL.md). The schema now requires `slug` + `value`.

### Derivation (per entry)

| Registry field | Derivation | Notes |
|----------------|-----------|-------|
| `slug`   | `sanitize_key( entry.slug )` | kebab; the only trusted source for keys |
| `cssVar` | `"--color-" . slug` | **verbatim** — equals the var `convert` emitted |
| `default`| `entry.value` | hex / `rgb(a)` / `hsl(a)` (validated) |
| `label`  | humanize(slug) — pure function | deterministic, NOT free-form |
| `group`  | role→group lookup — pure function | `brand` / `text` / `surface` / `state` |

```
colorTokens[] = [
  { cssVar: "--color-primary",    slug: "primary",    label: "Primary",
    default: "#1a73e8", group: "brand" },
  { cssVar: "--color-foreground", slug: "foreground", label: "Foreground",
    default: "#0f172a", group: "text" },
  …
]
```

- **Defensive:** skip + warn on any entry missing `slug` or `value` (never emit a
  control for a half-defined token).
- **Editable set = `:root` color tokens only** (curated-complete), NOT every color
  literal in `main.css`.

### Var-name verbatim contract (F1)

`cssVar` MUST equal the var `convert` actually wrote to `:root`. The token
reference historically abbreviated some slugs (`foreground`→`--color-fg`,
`background`→`--color-bg`). Resolved by making `convert` emit `--color-<slug>`
**verbatim** (hard contract, no abbreviation/collapse — see
`skills/theme-conversion/references/classic-acf.md` and
`skills/design-tokens/references/theme-json-mapping.md`) AND carrying the result
as `cssVar`. Registry / emitter / reset read that one `cssVar`. **Never** re-apply
a `--color-<slug>` template downstream — that is how edits hit a phantom var.

### Slug safety (F6)

Keys (`cssVar`, the `<slug>_color_<slug>` mod key) derive **only** from the
`sanitize_key()`'d slug. The raw token `name` is NEVER echoed into CSS — an
untrusted source-CSS property name could inject a `</style>` / CSS breakout.

### Determinism (F10)

`label` and `group` are **pure functions of the slug** — a fixed lookup/rule
computed by the scaffold script, not authored ad-hoc by the agent — so
`scaffold --force` rewrites byte-identical files.

---

## 2. Color value contract — function-color sanitizer (F2)

Token values may be `#hex`, `rgb(a)`, or `hsl(a)` (`extract-tokens.mjs` harvests
all three). Use a **function-color allowlist**, NOT bare `sanitize_hex_color`
(which nukes `rgba()`/`hsl()`):

```php
/**
 * Allow #hex (3/4/6/8), rgb()/rgba(), hsl()/hsla(); else ''. Namespaced per theme.
 */
function acme_sanitize_color( $value ) {
	$value = trim( (string) $value );
	if ( preg_match( '/^#(?:[0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})$/i', $value ) ) {
		return strtolower( $value );
	}
	if ( preg_match( '/^(?:rgba?|hsla?)\(\s*[0-9.,%\/\sdega]+\)$/i', $value ) ) {
		return $value;
	}
	return '';
}
```

Apply it **on save** (the setting `sanitize_callback`) AND **re-apply on output**
in the emitter — `theme_mod`s set by DB import / `wp eval` bypass the save
callback, so the emitter is the real guard against a malformed/hostile value.
Drop on fail.

---

## 3. Inline-CSS emitter + reset

### Defaults

Defaults live in the theme's `style.css` `:root` (block-fse: `theme.json`),
emitted by `convert`. `convert` keeps `assets/css/main.css` **`:root`-color-free**
(it enqueues after `style.css`) so reset reverts to the token default, not a raw
source color. (Alternative if a stray `:root` survives: emit the FULL default
`:root` always — but the strip is the contract.)

### Override emit

On `wp_enqueue_scripts` (after the main style), build a `:root{}` block **only**
for tokens whose stored mod ≠ default, run each value back through the
function-color sanitizer, escape for **CSS context** (not `esc_attr`), and attach:

```php
function acme_customizer_css() {
	$css = '';
	foreach ( acme_color_tokens() as $t ) {
		$val = get_theme_mod( 'acme_color_' . $t['slug'], $t['default'] );
		if ( $val === $t['default'] ) {
			continue;                       // default → no override
		}
		$val = acme_sanitize_color( $val ); // re-validate on output (F2/F6)
		if ( '' === $val ) {
			continue;                       // drop hostile/malformed
		}
		$css .= sprintf( '%s:%s;', $t['cssVar'], $val ); // CSS-context safe
	}
	if ( '' === $css ) {
		return;
	}
	$handle = wp_style_is( 'acme-main', 'registered' ) ? 'acme-main' : 'acme-style';
	wp_add_inline_style( $handle, ':root{' . $css . '}' );
}
add_action( 'wp_enqueue_scripts', 'acme_customizer_css', 20 );
```

- **Handle check (F8):** the emitter checks `<slug>-main` is registered and falls
  back to `<slug>-style`; if neither is registered `wp_add_inline_style` no-ops
  (the override silently vanishes), so `convert` MUST keep the `<slug>-main`
  handle registered.
- Values are constrained to the function-color grammar, so they cannot break out
  of the `:root{}` block.

### Reset = full revert (colors + logos)

"Reset to defaults" reverts **colors AND logos**:

- Colors → each control `setting.set( default )` (live), and on save any mod equal
  to its default is removed (`remove_theme_mod`) so the DB stays clean and the
  emitter emits nothing → defaults reapply.
- Logos → clear `custom_logo` and `<slug>_footer_logo` (live + on save) → header
  falls back to title, footer to the helper fallback chain.

### Orphan-mod GC (F10)

On scaffold, prune any `<slug>_color_*` theme_mod absent from the current registry
(orphans left by a token rename) so a stale mod can't silently override.

---

## 4. Footer-logo convention (F3 / F7)

- **Key:** `<slug>_footer_logo`, stored as an **attachment ID**
  (`WP_Customize_Media_Control`, `sanitize_callback = 'absint'`).
- **Guarded render helper, defined in `convert`** (foundation), behind a
  `function_exists` guard so an activated-but-not-yet-scaffolded theme never
  fatals (F3):

```php
if ( ! function_exists( 'acme_the_footer_logo' ) ) {
	/**
	 * Footer logo: uploaded footer logo → site/header logo → site title.
	 */
	function acme_the_footer_logo() {
		$id = absint( get_theme_mod( 'acme_footer_logo', 0 ) );
		if ( $id && wp_get_attachment_image( $id, 'full' ) ) {
			printf(
				'<span class="footer-logo">%s</span>',
				wp_get_attachment_image( $id, 'full', false, array( 'class' => 'footer-logo__img' ) )
			);
			return;
		}
		if ( function_exists( 'the_custom_logo' ) && has_custom_logo() ) {
			the_custom_logo();
			return;
		}
		printf(
			'<a class="site-title" href="%1$s" rel="home">%2$s</a>',
			esc_url( home_url( '/' ) ),
			esc_html( get_bloginfo( 'name' ) )
		);
	}
}
```

`scaffold` only adds the **control** that sets the mod; `convert`'s `footer.php`
calls the helper (stable wrapper id for the preview JS).

---

## 5. Per-strategy file matrix

| File | classic-acf | block-fse | page-builder |
|------|-------------|-----------|--------------|
| `inc/customizer.php` (panel/sections/controls + reset + emitter + GC) | ✅ full | ✅ footer-logo only | ✅ footer-logo only (host theme) |
| `assets/js/customizer-preview.js` (color→cssVar, logo swap) | ✅ | logo only | logo only |
| `assets/js/customizer-controls.js` (reset button) | ✅ | — | — |
| guarded `<slug>_the_footer_logo()` helper | ✅ in `convert` | ✅ in `convert` | ✅ in `convert` (host theme) |
| `footer.php` / `parts/footer.html` render slot | ✅ `footer.php` | ✅ `parts/footer.html` (block-bindings) | ✅ host `footer.php` (or Elementor widget) |
| color UI | custom Customizer | **native Global Styles** | **native Global Colors** |
| color reset | custom reset button | native Styles → Reset | native (Site Settings) |

- **block-fse (F5/F11):** FSE has no `inc/` and a tiny `functions.php`. Phase 3
  authors a customizer file + `add_action('customize_register')` for the footer
  logo, plus a registered **image block-bindings source** resolving the mod to an
  image URL, bound on a `wp:image`/`wp:site-logo` attribute in `parts/footer.html`
  (fallback: a PHP-rendered footer pattern if image-attribute binding is
  unsupported on the target WP). WP hides the Customizer menu for block themes →
  handoff gives the owner `/wp-admin/customize.php`.
- **page-builder (F12):** default = guarded helper in the host theme's `footer.php`
  shell, set by a host-theme Customizer Media control (same as classic). If the
  footer is fully builder-managed (Elementor replaces `get_footer()` output) there
  is **no shared-mod path** — the footer logo is an Elementor logo widget only. The
  reference states which applies; no "identical render / shared key" promise for the
  builder-managed case.

---

## 6. Pipeline placement & cross-stage rules

- `scaffold` adds the customization step (routes by `strategy`).
- `convert` gains the guarded footer-logo helper + render slot, emits
  `--color-<slug>` verbatim, and keeps `main.css` `:root`-color-free.
- **convert → scaffold re-chain:** `convert` wipes + recreates the theme dir and
  activates it; customizer code lives in `scaffold`, so the orchestrator MUST
  re-run `scaffold` after any `convert` re-run when customization is enabled.
- **`<slug>-main` style handle** is a contract value both this plan and any
  convert-rewrite plan must preserve.
- **theme_mod state** (`theme_mods_<slug>`) is DB-resident: survives the convert
  wipe but is not in files; `ship` migrates it (see `skills/wp-ship/SKILL.md`).

---

## 7. WP-CLI verification recipe

Run against a generated `classic-acf` theme (the only strategy with custom code).
The **static greps + cross-stage activation + injection check are mandatory gates**
and run without a full behavioral environment; only the live `wp eval` run defers
when wp-env is absent (flag it, don't skip). Substitute `acme` with the theme slug.

### Static gates (no wp-env needed)

```bash
THEME="wp-content/themes/acme"
# F1 — every registry cssVar exists in the emitted :root (no phantom vars):
grep -oE '\-\-color-[a-z0-9-]+' "$THEME/inc/customizer.php" | sort -u > /tmp/reg.vars
grep -oE '\-\-color-[a-z0-9-]+' "$THEME/style.css" | sort -u > /tmp/root.vars
comm -23 /tmp/reg.vars /tmp/root.vars   # MUST be empty (every editable var is in :root)
# F9 — main.css carries no :root color vars (else reset reverts to source color):
! grep -qE ':root[^}]*--color-' "$THEME/assets/css/main.css"   # MUST succeed (absent)
```

### Cross-stage activation (F3 — convert-only, before scaffold)

```bash
# Activate the convert output (no inc/customizer.php yet) and hit the front-end:
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" theme activate acme
curl -fsS -o /dev/null -w '%{http_code}\n' http://localhost:8888/   # 200, NOT a fatal
# The guarded helper must exist from convert (not scaffold):
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" eval 'var_export( function_exists("acme_the_footer_logo") );'  # true
```

### Behavioral run (wp-env; classic-acf)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" theme activate acme            # no PHP notices/fatals

# Color mod incl. an rgba() value → correct-cssVar :root override appears:
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" eval 'set_theme_mod("acme_color_primary","rgba(0,0,0,0.5)");'
curl -s http://localhost:8888/ | grep -o '\-\-color-primary:[^;]*'   # rgba(0,0,0,0.5)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" eval 'remove_theme_mod("acme_color_primary");'
curl -s http://localhost:8888/ | grep -c '\-\-color-primary:'        # 0 (back to default)

# F6 injection — set a hostile value via wp eval (bypasses the save sanitizer):
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" eval 'set_theme_mod("acme_color_primary","red} body{display:none");'
curl -s http://localhost:8888/ | grep -c 'display:none'              # 0 (emitter dropped it)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" eval 'remove_theme_mod("acme_color_primary");'

# Footer logo (attachment ID) → renders via wp_get_attachment_image; bad ID falls back:
MID="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" media import https://example.com/logo.png --porcelain)"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" eval "set_theme_mod('acme_footer_logo', ${MID});"
curl -s http://localhost:8888/ | grep -c 'footer-logo__img'         # 1
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" eval 'set_theme_mod("acme_footer_logo", 999999);' # bad ID
curl -s http://localhost:8888/ | grep -c 'site-title\|custom-logo'  # fallback rendered

# Reset = colors + logos:
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" eval 'remove_theme_mod("acme_footer_logo"); remove_theme_mod("custom_logo");'
# → token-default colors + no custom logos.
```

### Idempotency + orphan GC (F10)

```bash
# Byte-identical re-scaffold:
sha1sum "$THEME/inc/customizer.php" > /tmp/before
# (re-run the scaffold stage with --force)
sha1sum "$THEME/inc/customizer.php" > /tmp/after
diff /tmp/before /tmp/after          # identical
# Token rename orphans a mod → GC removes it on next scaffold/save:
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" eval 'set_theme_mod("acme_color_removed","#123456"); do_action("customize_save_after");'
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" eval 'var_export( get_theme_mod("acme_color_removed", "GONE") );'  # "GONE"
```

### Ship state (F4)

```bash
# Export the customizer state, import on a second site, confirm reproduction:
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" option get theme_mods_acme --format=json > /tmp/mods.json
# (on the second site) wp option update theme_mods_acme "$(cat /tmp/mods.json)" --format=json
# → logos + colors reproduce; footer-logo attachment ID resolves (or was remapped).
```

Pass criteria: static greps empty/absent as noted, convert-only front-end is 200
(not a fatal), the rgba mod yields the correct `--color-primary` override, the
injection mod produces no `display:none` in output, the footer logo renders and
falls back, reset clears colors + logos, re-scaffold is byte-identical, the orphan
mod is GC'd, and the exported `theme_mods_acme` reproduces branding on a second site.
