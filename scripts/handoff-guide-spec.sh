#!/usr/bin/env bash
# handoff-guide-spec.sh — pure (no wp-env) flow-spec builder for the handoff stage's
# admin guides. Reads wp-build.json and emits a DETERMINISTIC spec JSON to stdout
# enumerating every wp-admin flow to capture + author a guide for.
#
# Usage (from the target project root, where wp-build.json lives):
#   bash "${CLAUDE_PLUGIN_ROOT}/scripts/handoff-guide-spec.sh" [manifest] [--locale <loc>]
#   WP_BUILD_FILE=./wp-build.json bash scripts/handoff-guide-spec.sh --locale vi
#
# Output shape (consumed by scripts/admin-capture.mjs and the wp-handoff skill):
#   { "locale": "vi", "strategy": "classic-acf", "themeSlug": "acme",
#     "flows": [ { "id","title","category","adminUrl","strategyNote","steps":[
#                    { "id","label","url"[, "preAuth":true] } ] } ] }
#
# Every step `url` is relative to the SITE ROOT (e.g. "wp-admin/edit.php",
# "wp-login.php") so the engine resolves it with `new URL(step.url, baseUrl)`.
#
# Determinism (Phase 1 gate): no timestamps, no randomness — same manifest + locale
# => byte-identical output, so `--force` regenerates a stable spec. Flow order is
# fixed and array flows preserve manifest order. The stage `generatedAt` timestamp
# is stamped by the skill into wp-build.json, never here.
#
# zsh-safe: the runtime Bash tool is zsh. This file does NOT enable
# `set -euo pipefail` at the top level (that would leak into a sourcing caller),
# avoids the zsh-reserved name `status`, and guards execution-vs-sourcing at the
# bottom the same way manifest-lib.sh / wpx.sh do.

WP_BUILD_FILE="${WP_BUILD_FILE:-./wp-build.json}"

_hgs_usage() {
  echo "usage: handoff-guide-spec.sh [manifest] [--locale <loc>]" >&2
}

# The jq program that turns wp-build.json into the flow spec. Kept as a single
# transform (no bash loops) so output is deterministic and jq validates the JSON.
_hgs_jq_program() {
  cat <<'JQ'
def mkflow($id; $title; $cat; $url; $note; $steps):
  { id: $id, title: $title, category: $cat, adminUrl: $url, strategyNote: $note, steps: $steps };

. as $m
| ($m.strategy // "classic-acf")            as $strategy
| ($m.project.themeSlug // "theme")         as $slug
| ($m.contentModel.postTypes // [])         as $cpts
| ($m.contentModel.taxonomies // [])        as $taxes
| ($m.designTokens.colors // [])            as $colors
| ($m.plugins // [])                        as $plugins
| ($m.i18n // {})                           as $i18n

# --- fixed content flows -----------------------------------------------------
| [
    mkflow("auth"; "Sign in & your profile"; "auth"; "wp-admin/index.php"; "";
      [ {id:"login",     label:"Login screen", url:"wp-login.php", preAuth:true},
        {id:"dashboard", label:"Dashboard",    url:"wp-admin/index.php"},
        {id:"profile",   label:"Your profile", url:"wp-admin/profile.php"} ]),
    mkflow("post-crud"; "Posts — create, edit, delete"; "content"; "wp-admin/edit.php"; "";
      [ {id:"list",    label:"All posts",     url:"wp-admin/edit.php"},
        {id:"add-new", label:"Add new post",  url:"wp-admin/post-new.php"} ]),
    mkflow("page-crud"; "Pages — create, edit, delete"; "content"; "wp-admin/edit.php?post_type=page"; "";
      [ {id:"list",    label:"All pages",    url:"wp-admin/edit.php?post_type=page"},
        {id:"add-new", label:"Add new page", url:"wp-admin/post-new.php?post_type=page"} ]),
    mkflow("tax-category"; "Categories"; "taxonomy"; "wp-admin/edit-tags.php?taxonomy=category"; "";
      [ {id:"manage", label:"Manage categories", url:"wp-admin/edit-tags.php?taxonomy=category"} ])
  ]
# --- custom taxonomies (skip the built-ins already covered) -------------------
+ ( $taxes
    | map(select((.slug // "") | (. != "" and . != "category" and . != "post_tag")))
    | map( . as $t
        | ($t.objectType[0] // "") as $ot
        | (if $ot == "" then "wp-admin/edit-tags.php?taxonomy=\($t.slug)"
           else "wp-admin/edit-tags.php?taxonomy=\($t.slug)&post_type=\($ot)" end) as $url
        | mkflow("tax-\($t.slug)"; "Taxonomy: \($t.slug)"; "taxonomy"; $url; "";
            [ {id:"manage", label:"Manage \($t.slug)", url:$url} ]) ) )
# --- custom post types -------------------------------------------------------
+ ( $cpts
    | map(select((.slug // "") != ""))
    | map( . as $p
        | (if $strategy == "classic-acf"
           then "This type's ACF field group appears as meta boxes in the editor, below the title."
           else "" end) as $note
        | mkflow("cpt-\($p.slug)"; "Custom type: \($p.slug)"; "content"; "wp-admin/edit.php?post_type=\($p.slug)"; $note;
            [ {id:"list",    label:"All \($p.slug)",    url:"wp-admin/edit.php?post_type=\($p.slug)"},
              {id:"add-new", label:"Add new \($p.slug)", url:"wp-admin/post-new.php?post_type=\($p.slug)"} ]) ) )
# --- customizer / branding (branch by strategy) ------------------------------
# classic-acf: one flow per control (header logo, footer logo, each color, reset),
# deep-linked via customize.php?autofocus[control]=<id> (graceful: an unknown id
# just opens the customizer root). block-fse / page-builder: a Styles/Builder
# panel flow + the separate footer-logo control; per-color detail lives in prose.
+ ( if $strategy == "classic-acf"
    then
      [ mkflow("customizer-logo-header"; "Branding — header logo"; "branding";
          "wp-admin/customize.php?autofocus[control]=custom_logo";
          "Appearance → Customize → Branding & Colors → Logos → Header logo.";
          [ {id:"control", label:"Header logo control", url:"wp-admin/customize.php?autofocus[control]=custom_logo"} ]),
        mkflow("customizer-logo-footer"; "Branding — footer logo"; "branding";
          "wp-admin/customize.php?autofocus[control]=\($slug)_footer_logo";
          "Appearance → Customize → Branding & Colors → Logos → Footer logo (separate from the header).";
          [ {id:"control", label:"Footer logo control", url:"wp-admin/customize.php?autofocus[control]=\($slug)_footer_logo"} ]) ]
      + ( $colors
          | map(select((.slug // "") != ""))
          | map( . as $c
              | mkflow("customizer-color-\($c.slug)"; "Branding — color: \($c.slug)"; "branding";
                  "wp-admin/customize.php?autofocus[control]=\($slug)_color_\($c.slug)";
                  "Branding & Colors → Colors → \($c.slug). Previews live and saves to the front-end.";
                  [ {id:"control", label:"Color control: \($c.slug)", url:"wp-admin/customize.php?autofocus[control]=\($slug)_color_\($c.slug)"} ]) ) )
      + [ mkflow("customizer-reset"; "Branding — reset to defaults"; "branding";
            "wp-admin/customize.php";
            "Branding & Colors → Reset returns every logo and color to the original design.";
            [ {id:"panel", label:"Customizer panel", url:"wp-admin/customize.php"} ]) ]
    elif $strategy == "block-fse"
    then
      [ mkflow("customizer-styles"; "Branding — colors in Global Styles"; "branding";
          "wp-admin/site-editor.php";
          "Site Editor → Styles: edit colors; Styles → Reset to defaults reverts. Each brand color is a Styles color, not a Customizer control.";
          [ {id:"styles", label:"Global Styles", url:"wp-admin/site-editor.php"} ]),
        mkflow("customizer-logo-footer"; "Branding — footer logo"; "branding";
          "wp-admin/customize.php?autofocus[control]=\($slug)_footer_logo";
          "Block themes hide the Customizer menu — open /wp-admin/customize.php directly → Site Identity → Footer Logo.";
          [ {id:"control", label:"Footer logo control", url:"wp-admin/customize.php?autofocus[control]=\($slug)_footer_logo"} ]) ]
    else
      [ mkflow("customizer-global-colors"; "Branding — global colors"; "branding";
          "wp-admin/admin.php?page=elementor";
          "Elementor → Site Settings → Global Colors; header logo in Site Identity. Each brand color is a Global Color.";
          [ {id:"panel", label:"Builder site settings", url:"wp-admin/admin.php?page=elementor"} ]),
        mkflow("customizer-logo-footer"; "Branding — footer logo"; "branding";
          "wp-admin/customize.php?autofocus[control]=\($slug)_footer_logo";
          "Footer logo via the host-theme Customizer control (or the builder's footer logo widget when the footer is builder-managed).";
          [ {id:"control", label:"Footer logo control", url:"wp-admin/customize.php?autofocus[control]=\($slug)_footer_logo"} ]) ]
    end )
# --- extra flows: menus, media ----------------------------------------------
+ [
    mkflow("menu"; "Menus"; "navigation"; "wp-admin/nav-menus.php"; "";
      [ {id:"edit",      label:"Edit menus",     url:"wp-admin/nav-menus.php"},
        {id:"locations", label:"Menu locations", url:"wp-admin/nav-menus.php?action=locations"} ]),
    mkflow("media"; "Media & featured images"; "media"; "wp-admin/upload.php";
      "Set a featured image from the post editor's Featured image panel.";
      [ {id:"library", label:"Media library", url:"wp-admin/upload.php"},
        {id:"add",     label:"Upload media",  url:"wp-admin/media-new.php"} ])
  ]
# --- plugin config (per plugin; best-effort deep link to its settings) --------
+ ( $plugins
    | map(select((.slug // "") != ""))
    | map( . as $pl
        | ( { "wordpress-seo":"wp-admin/admin.php?page=wpseo_dashboard",
              "wordpress-seo-premium":"wp-admin/admin.php?page=wpseo_dashboard",
              "seo-by-rank-math":"wp-admin/admin.php?page=rank-math",
              "seopress":"wp-admin/admin.php?page=seopress-option",
              "contact-form-7":"wp-admin/admin.php?page=wpcf7",
              "wpforms-lite":"wp-admin/admin.php?page=wpforms-overview",
              "wpforms":"wp-admin/admin.php?page=wpforms-overview",
              "elementor":"wp-admin/admin.php?page=elementor",
              "advanced-custom-fields":"wp-admin/edit.php?post_type=acf-field-group",
              "advanced-custom-fields-pro":"wp-admin/edit.php?post_type=acf-field-group",
              "wordfence":"wp-admin/admin.php?page=Wordfence",
              "w3-total-cache":"wp-admin/admin.php?page=w3tc_dashboard",
              "wp-super-cache":"wp-admin/options-general.php?page=wpsupercache",
              "polylang":"wp-admin/admin.php?page=mlang",
              "wp-mail-smtp":"wp-admin/admin.php?page=wp-mail-smtp" }[$pl.slug]
            // "wp-admin/plugins.php" ) as $url
        | mkflow("plugin-\($pl.slug)"; "Plugin: \($pl.slug)"; "plugin"; $url;
            ($pl.rationale // "");
            [ {id:"settings", label:"\($pl.slug) settings", url:$url} ]) ) )
# --- settings & users --------------------------------------------------------
+ [
    mkflow("settings-users"; "Settings & Users"; "admin"; "wp-admin/options-general.php"; "";
      [ {id:"general",    label:"General settings",    url:"wp-admin/options-general.php"},
        {id:"reading",    label:"Reading (front page)", url:"wp-admin/options-reading.php"},
        {id:"permalinks", label:"Permalinks",          url:"wp-admin/options-permalink.php"},
        {id:"users",      label:"Users",               url:"wp-admin/users.php"} ])
  ]
# --- translations (only when i18n is enabled) --------------------------------
+ ( if ($i18n.enabled // false)
    then
      ( ( { "polylang":"wp-admin/admin.php?page=mlang",
            "wpml":"wp-admin/admin.php?page=sitepress-multilingual-cms/menu/languages.php" }[$i18n.plugin // ""]
          // "wp-admin/plugins.php" ) as $url
        | [ mkflow("i18n-translate"; "Translations"; "i18n"; $url;
              "Add and manage translations for pages, posts, categories, and menus.";
              [ {id:"languages", label:"Languages", url:$url} ]) ] )
    else [] end )

# --- envelope ----------------------------------------------------------------
| { locale: $locale, strategy: $strategy, themeSlug: $slug, flows: . }
JQ
}

hgs_main() {
  local manifest="" locale=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --locale)    locale="${2:-}"; shift 2 ;;
      --locale=*)  locale="${1#--locale=}"; shift ;;
      -h|--help)   _hgs_usage; return 0 ;;
      --*)         echo "handoff-guide-spec: unknown option '$1'" >&2; _hgs_usage; return 2 ;;
      *)           manifest="$1"; shift ;;
    esac
  done

  manifest="${manifest:-$WP_BUILD_FILE}"
  command -v jq >/dev/null 2>&1 || { echo "handoff-guide-spec: 'jq' is required" >&2; return 3; }
  [ -f "$manifest" ] || { echo "handoff-guide-spec: manifest not found: $manifest" >&2; return 2; }

  # Default the guide locale to the manifest's i18n.defaultLocale, else English.
  if [ -z "$locale" ]; then
    locale="$(jq -r '.i18n.defaultLocale // "en"' "$manifest")"
  fi

  jq --arg locale "$locale" "$(_hgs_jq_program)" "$manifest"
}

# Sourcing-vs-execution guard (bash + zsh). Mirrors manifest-lib.sh / wpx.sh:
# only enable strict mode and run when EXECUTED, never when sourced.
_hgs_sourced=1
if [ -n "${BASH_VERSION:-}" ]; then
  [ "${BASH_SOURCE[0]}" = "$0" ] && _hgs_sourced=0
elif [ -n "${ZSH_VERSION:-}" ]; then
  case "${ZSH_EVAL_CONTEXT:-}" in *:file*) _hgs_sourced=1 ;; *) _hgs_sourced=0 ;; esac
fi

if [ "$_hgs_sourced" = "0" ]; then
  set -euo pipefail
  hgs_main "$@"
fi
