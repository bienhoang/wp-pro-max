---
name: wp-i18n
description: >-
  Makes the generated WordPress theme translation-ready and sets up multilingual
  content (stage `i18n`). Part A wraps every theme string in i18n functions
  (__(), _e(), esc_html__(), esc_attr__(), _n(), _x()) bound to
  project.textDomain, adds load_theme_textdomain, and generates the .pot template
  with `wp i18n make-pot`, then documents creating vi/en/ja .po/.mo (with
  Japanese font-stack and layout specifics). Part B configures Polylang (free,
  preferred) or WPML: registers vi (default)/en/ja, assigns the language of
  seeded posts/pages, links translations, and adds a language switcher to a menu
  via idempotent `wp pll` / `wp eval` commands through wp-env. Reads i18n.* and
  project.textDomain; writes i18n results + i18n.potPath. Use when localizing a
  WordPress theme, adding Vietnamese/English/Japanese, generating a POT/PO/MO, or
  when the pipeline reaches the `i18n` stage.
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# WordPress i18n (stage `i18n`)

Two jobs, run in order:

1. **Translation-ready theme** — every user-facing string is wrapped in an i18n
   function with the project text domain, the theme loads its text domain, and a
   `.pot` template is generated. → `references/translation-ready.md`
2. **Multilingual data** — install + configure Polylang (or WPML), register the
   three languages, set language on the seeded posts/pages, link translations,
   and add a language switcher. → `references/multilingual-data.md`

All WordPress CLI runs go through wp-env: `wp-env run cli wp <command>`.

## Inputs (from `wp-build.json`)

| Field | Use | Default |
|-------|-----|---------|
| `i18n.enabled` | Skip stage entirely when `false`. | `true` if `i18n` present |
| `i18n.locales` | Languages to set up. | `["vi","en","ja"]` |
| `i18n.defaultLocale` | Site default / fallback language. | `"vi"` |
| `i18n.plugin` | `polylang` \| `wpml` \| `none`. | `polylang` |
| `project.textDomain` | The text domain for every i18n call. | `project.themeSlug` |
| `theme.path` | Theme dir to scan/wrap and `make-pot` against. | — |
| `theme.files` | PHP/template files to audit for hard-coded strings. | — |
| `seed.idempotencyKeys` | Slugs of seeded pages/posts to assign a language. | — |

WordPress locale codes used: **`vi` → `vi`**, **`en` → `en_US`**, **`ja` → `ja`**.

## 0. Resume guard + setup

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh"
wpbuild_is_done i18n && [[ "${1:-}" != "--force" ]] && { echo "i18n done"; exit 0; }
wpbuild_progress i18n in-progress
[[ "$(wpbuild_get '.i18n.enabled // true')" == "false" ]] && { wpbuild_progress i18n skipped "i18n disabled"; exit 0; }

THEME="$(wpbuild_get '.theme.path')"
TD="$(wpbuild_get '.project.textDomain // .project.themeSlug')"
PLUGIN="$(wpbuild_get '.i18n.plugin // "polylang"')"
DEFAULT_LOCALE="$(wpbuild_get '.i18n.defaultLocale // "vi"')"
mapfile -t LOCALES < <(wpbuild_get '.i18n.locales[]? // empty'); [[ ${#LOCALES[@]} -eq 0 ]] && LOCALES=(vi en ja)
```

## 1. Make the theme translation-ready

Audit `theme.path` for hard-coded user-facing strings and wrap each in the
correct function with the text domain `"$TD"`. Quick scan for likely misses:

```bash
# echo/print of literal text, and i18n calls missing/with wrong text domain
grep -rnE "echo\s+['\"]|esc_html\(\s*['\"]|>[A-Za-z].*</" "$THEME" --include='*.php' | head
grep -rnE "__\(|_e\(|esc_html__\(|esc_attr__\(|_n\(|_x\(" "$THEME" --include='*.php' \
  | grep -vE "['\"]$TD['\"]\s*\)" | head    # calls NOT bound to the text domain
```

Function picker (full table + `_n`/`_x`/`printf` patterns in the reference):

| Context | Use |
|---------|-----|
| Return a string | `__( 'Read more', '<td>' )` |
| Echo a string | `_e( 'Read more', '<td>' )` |
| Echo into HTML body | `esc_html_e( 'Read more', '<td>' )` |
| Return, escaped for HTML | `esc_html__( 'Read more', '<td>' )` |
| Into an attribute | `esc_attr_e( 'Search', '<td>' )` |
| Plurals | `_n( '%s comment', '%s comments', $n, '<td>' )` |
| Disambiguation | `_x( 'Post', 'noun', '<td>' )` |

Then ensure the theme **loads its text domain** in `functions.php` (idempotent —
add only if absent):

```php
add_action( 'after_setup_theme', function () {
    load_theme_textdomain( 'your-text-domain', get_template_directory() . '/languages' );
} );
```

Heavy string-wrapping across many template files → delegate to the
**wp-theme-developer** agent (see Delegation). Full guidance, including Japanese
font stack (Noto Sans JP), full-width punctuation, no word-wrap assumptions, and
string-length layout slack, is in `references/translation-ready.md`.

## 2. Generate the .pot template

```bash
mkdir -p "$THEME/languages"
wp-env run cli wp i18n make-pot "wp-content/themes/$(basename "$THEME")" \
  "wp-content/themes/$(basename "$THEME")/languages/${TD}.pot" \
  --domain="$TD" --skip-audit
wpbuild_set '.i18n.potPath' "\"languages/${TD}.pot\""
```

Sample `.pot` header the theme should carry (full block in the reference):

```
msgid ""
msgstr ""
"Project-Id-Version: <Theme Name> 1.0.0\n"
"Report-Msgid-Bugs-To: https://wordpress.org/support/theme/<text-domain>\n"
"MIME-Version: 1.0\n"
"Content-Type: text/plain; charset=UTF-8\n"
"Content-Transfer-Encoding: 8bit\n"
"Language-Team: vi en ja\n"
"X-Generator: WP-CLI\n"
"X-Domain: <text-domain>\n"
```

Then create the per-locale catalogs from the POT — file names must be
`<text-domain>-<locale>.po/.mo` (e.g. `your-td-vi.po`, `your-td-en_US.po`,
`your-td-ja.po`). Exact `msginit` + translate + `wp i18n make-mo` commands are in
`references/translation-ready.md`.

## 3. Multilingual content (plugin)

If `i18n.plugin == "none"`, skip this section (theme is still translation-ready).
Otherwise follow `references/multilingual-data.md` to:

- Install + activate the plugin (Polylang free, or WPML from a pinned zip).
- Register the languages: **vi (default)**, **en**, **ja** — created in
  `defaultLocale`-first order so the fallback is correct.
- Set the language of each seeded page/post (keyed by `seed.idempotencyKeys`).
- Link the translations of each page into one translation group.
- Add a language switcher (Polylang nav-menu switcher item, or WPML widget/menu).

All commands are idempotent (`wp pll` checks before create, `wp eval` guards) and
run through wp-env. Minimal Polylang bootstrap:

```bash
wp-env run cli wp plugin install polylang --activate
wp-env run cli wp pll lang list >/dev/null 2>&1 || true   # ensure CLI present
# create vi (default) first, then en, then ja  — full block in the reference
wp-env run cli wp pll lang create Vietnamese vi vi          # name slug locale
wp-env run cli wp pll lang create English    en en_US
wp-env run cli wp pll lang create 日本語       ja ja
wp-env run cli wp pll option default_lang vi
```

## 4. Record outputs

```bash
wpbuild_merge "$(jq -nc --arg pot "languages/${TD}.pot" --arg pl "$PLUGIN" '{
  i18n: { enabled: true, potPath: $pot, plugin: $pl, translationReady: true }
}')"
wpbuild_progress i18n done "theme i18n-ready; POT generated; ${PLUGIN} languages vi/en/ja configured"
```

## Delegation

- Bulk wrapping of strings across theme PHP / template parts and any
  `functions.php` edits → **wp-theme-developer** agent. Pass: `theme.path`, the
  text domain, the file list, and acceptance criteria (no echoed literals remain;
  `make-pot` extracts every string; theme loads its text domain).
- Setting post languages / linking translations / `wp db query` guards →
  **wp-data-engineer** agent. Pass: target path, manifest path, the page slug →
  language map, and acceptance criteria (each page exists in all locales, linked,
  switcher renders, re-run creates no duplicates).

Never pass full conversation history; give exact paths and the manifest path.

See also: `references/translation-ready.md`, `references/multilingual-data.md`.
