---
description: Scaffold a target WordPress project directory (inputs + wp/ + starter wp-build.json) for the WP Pro Max pipeline.
argument-hint: <project-name> [--slug <theme-slug>] [--strategy classic-acf|block-fse|page-builder]
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# /wp-pro-max:init

Scaffold a new WP Pro Max project with the parent-wrapper layout: inputs live at
the project root and the WordPress project (manifest, theme, wp-env) lives under
`wp/`.

## Usage

```bash
/wp-pro-max:init acme-studio
/wp-pro-max:init "Acme Studio" --slug acme-studio --strategy block-fse
```

## Procedure

```bash
set -e

NAME=""
SLUG=""
STRATEGY="classic-acf"

# Parse arguments --------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --slug)
      [ $# -ge 2 ] || { echo "init: --slug requires a value" >&2; exit 2; }
      SLUG="$2"; shift 2 ;;
    --strategy)
      [ $# -ge 2 ] || { echo "init: --strategy requires a value" >&2; exit 2; }
      STRATEGY="$2"; shift 2 ;;
    --)
      shift; break ;;
    -*)
      echo "init: unknown option $1" >&2; exit 2 ;;
    *)
      if [ -z "$NAME" ]; then NAME="$1"; shift
      else echo "init: unexpected argument $1" >&2; exit 2; fi ;;
  esac
done

if [ -z "$NAME" ]; then
  echo "Usage: /wp-pro-max:init <project-name> [--slug <theme-slug>] [--strategy classic-acf|block-fse|page-builder]" >&2
  exit 2
fi

# Derive kebab-case slug from name if not provided -----------------------------
if [ -z "$SLUG" ]; then
  SLUG="$(printf '%s' "$NAME" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-' | sed -E 's/-+/-/g; s/^-|-$//g')"
fi

ROOT="./${SLUG}"

# Create parent-wrapper tree ---------------------------------------------------
mkdir -p "$ROOT"/{requirements,source,assets,design,mockups,wp}
for d in source assets design mockups; do
  [ -f "$ROOT/$d/.gitkeep" ] || : > "$ROOT/$d/.gitkeep"
done

# Create the manifest in wp/ (idempotent) --------------------------------------
source "${CLAUDE_PLUGIN_ROOT}/scripts/manifest-lib.sh"
export WP_BUILD_FILE="$ROOT/wp/wp-build.json"
wpbuild_init "$NAME" "$SLUG" "$STRATEGY"
# source.type is intentionally omitted — the analyze stage auto-detects it.
wpbuild_merge '{"source":{"htmlPaths":["../source"],"assetDirs":["../assets"],"briefPath":"../requirements/brief.md"}}'

# Initialize git repo at project root (idempotent) -----------------------------
[ -d "$ROOT/.git" ] || git -C "$ROOT" init -q

# Emit templates only when absent ----------------------------------------------
[ -f "$ROOT/requirements/brief.md" ] || cat > "$ROOT/requirements/brief.md" <<'EOF'
# Project brief

## Goal
<!-- What is this site for? Who is it for? -->

## Pages
<!-- List each page and its role: home, about, services, contact, blog, etc. -->

## Content & data
<!-- Repeated content types (team, services, portfolio, testimonials, FAQs, …). -->
<!-- Custom fields, taxonomies, or CPTs you already know about. -->

## Brand & design
<!-- Colors, fonts, logos, references in design/ and mockups/. -->

## Plugins / integrations
<!-- Must-have plugins: SEO, forms, multilingual, e-commerce, etc. -->

## Locales
<!-- e.g. vi/en/ja -->

## Out of scope
<!-- What this build will NOT cover. -->
EOF

[ -f "$ROOT/.gitignore" ] || cat > "$ROOT/.gitignore" <<'EOF'
node_modules/
wp/.wp-env/
wp/wp-cli.local.yml
*.log
.DS_Store
EOF

[ -f "$ROOT/README.md" ] || cat > "$ROOT/README.md" <<EOF
# ${NAME}

WP Pro Max project scaffold.

## Layout

| Folder | Stage |
|--------|-------|
| \`requirements/\` | Brief + constraints (read by \`analyze\`) |
| \`source/\` | Static HTML/CSS/JS (read by \`analyze\` + \`optimize\`) |
| \`assets/\` | Images, fonts, downloads (read by \`optimize\` + \`convert\`) |
| \`design/\` | Brand docs, tokens, references (read by \`tokens\`) |
| \`mockups/\` | Screenshots / design files (reference) |
| \`wp/\` | WordPress project root — manifest, theme, wp-env |

## Next step

\`\`\`bash
cd wp && /wp-pro-max:build
\`\`\`
EOF

echo "Initialized $ROOT — next: cd \"$ROOT/wp\" && /wp-pro-max:build (or run /wp-pro-max:build from $ROOT, it auto-descends)"
```

## Output

A project directory with a starter manifest, input folders, `.gitkeep` files, a
`.gitignore`, a brief template, and a README. Re-running on an existing project
leaves the manifest and templates untouched.
