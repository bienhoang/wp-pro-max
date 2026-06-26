# Translation-ready theme (vi / en / ja)

Make every user-facing theme string translatable, load the text domain, generate
the `.pot`, and create per-locale catalogs. `<td>` = `project.textDomain`.

## i18n function reference

| Context | Function |
|---------|----------|
| Return a string | `__( 'text', '<td>' )` |
| Echo a string | `_e( 'text', '<td>' )` |
| Echo escaped into HTML | `esc_html_e( 'text', '<td>' )` |
| Return escaped for HTML | `esc_html__( 'text', '<td>' )` |
| Attribute value (echo) | `esc_attr_e( 'text', '<td>' )` |
| Attribute value (return) | `esc_attr__( 'text', '<td>' )` |
| Plurals | `_n( '%s item', '%s items', $count, '<td>' )` |
| Disambiguation | `_x( 'Post', 'verb', '<td>' )` |
| printf with placeholder | `printf( esc_html__( 'Hello %s', '<td>' ), $name )` |

Rules: text domain must be a **string literal** (not a variable) or `make-pot`
misses it. Never wrap HTML markup inside the string — keep tags outside.

## Load the text domain (functions.php, idempotent)

```php
add_action( 'after_setup_theme', function () {
    load_theme_textdomain( 'your-text-domain', get_template_directory() . '/languages' );
} );
```

## Generate the .pot

```bash
TD=your-text-domain; THEME=wp-content/themes/your-theme
wp-env run cli wp i18n make-pot "$THEME" "$THEME/languages/$TD.pot" --domain="$TD"
```

Sample header:

```
msgid ""
msgstr ""
"Project-Id-Version: Your Theme 1.0.0\n"
"MIME-Version: 1.0\n"
"Content-Type: text/plain; charset=UTF-8\n"
"Content-Transfer-Encoding: 8bit\n"
"Language-Team: vi en ja\n"
"X-Generator: WP-CLI\n"
"X-Domain: your-text-domain\n"
```

## Per-locale catalogs

File names: `<td>-<locale>.po/.mo` → `your-td-vi.po`, `your-td-en_US.po`, `your-td-ja.po`.

```bash
cd "$THEME/languages"
for L in vi en_US ja; do
  msginit --no-translator -l "$L" -i "$TD.pot" -o "$TD-$L.po" 2>/dev/null \
    || cp "$TD.pot" "$TD-$L.po"
done
# ...translate the .po files (msgstr), then compile:
wp-env run cli wp i18n make-mo "$THEME/languages"
```

## Japanese (ja) specifics

- **Font stack**: include Japanese fonts so glyphs render —
  `"Noto Sans JP", "Hiragino Kaku Gothic ProN", "Yu Gothic", Meiryo, sans-serif`.
  Load Noto Sans JP via the theme (theme.json `fontFamilies` for FSE, or enqueue).
- **No word-wrap by spaces**: Japanese has no spaces between words. Use
  `word-break: normal; overflow-wrap: anywhere;` and `line-break: strict;`; never
  rely on `word-wrap` to break long English-style runs.
- **Full-width punctuation**: 、。（）！？ — do not substitute ASCII equivalents.
- **Length variance**: ja strings are often shorter than en, vi often longer.
  Design buttons/nav with slack; avoid fixed-width text containers.
- **Locale code**: WordPress uses `ja` (not `ja_JP`).

## Acceptance

- No echoed string literals remain in templates (`grep` for `echo '...'`).
- `make-pot` extracts every visible string.
- `<td>-vi.po`, `<td>-en_US.po`, `<td>-ja.po` exist and compile to `.mo`.
- Theme loads its text domain; switching site language changes UI strings.
