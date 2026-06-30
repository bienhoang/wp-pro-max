# Multilingual content data (Polylang / WPML)

Configure multilingual content for **vi (default) / en / ja**, assign languages to
seeded pages, link translations, and add a switcher. All commands idempotent and
run via `bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh"`.

## Polylang (free, preferred)

### 1. Install + register languages (vi default, then en, ja)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" plugin install polylang --activate
# pll lang create <name> <slug> <locale>   — guard against duplicates
for entry in "Vietnamese vi vi" "English en en_US" "日本語 ja ja"; do
  set -- $entry
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" pll lang list --field=slug | grep -qx "$2" \
    || bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" pll lang create "$1" "$2" "$3"
done
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" pll option default_lang vi
```

### 2. Set a post's language

```bash
# wp pll post update <id> --lang=<slug>
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" pll post update 101 --lang=vi
```

### 3. Link translations into one group

```bash
# Link the vi/en/ja versions of the same page:
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" pll post connect 101 102   # connect en (102) to vi (101)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" pll post connect 101 103   # connect ja (103) to vi (101)
```

To create a translated copy of a page programmatically: duplicate the post
(`wp post create` with translated content), set its language, then `pll post
connect` it to the source. Key duplicated pages by a stable
`<source-slug>-<locale>` idempotency key so re-runs do not duplicate.

### 4. Language switcher

Add a Polylang switcher item to the primary menu:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" eval '
$menu = wp_get_nav_menu_object("primary");
if ($menu) {
  pll_the_languages(["raw"=>1]); // ensure plugin loaded
  // Polylang adds a "Language switcher" menu item type; add via menu UI or:
  wp_update_nav_menu_item($menu->term_id, 0, [
    "menu-item-title" => "Languages",
    "menu-item-type"  => "custom",
    "menu-item-url"   => "#pll_switcher",
    "menu-item-status"=> "publish",
  ]);
}'
```

(Polylang also exposes a dedicated "Language switcher" nav-menu metabox item; the
custom item above is the CLI-only fallback.)

## WPML (commercial — pinned zip)

WPML has no full official CLI. Configure via admin or `wp eval` against WPML APIs:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" plugin install /path/to/sitepress-multilingual-cms.zip --activate
# Languages + assignments set through WPML setup wizard or icl_* APIs via wp eval.
```

Prefer Polylang unless the client already owns WPML.

## Acceptance

- vi/en/ja registered; vi is the default/fallback.
- Each seeded page exists (or is linked) in all three languages and is connected.
- Switcher renders and routes correctly.
- Re-running the stage creates no duplicate posts or languages.
