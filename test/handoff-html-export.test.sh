#!/usr/bin/env bash
# handoff-html-export.test.sh — behavioral test for scripts/handoff-html-export.mjs.
# Builds a throwaway target project (manifest + docs + fake screenshots) in a
# temp dir, runs the real export, and asserts the acceptance criteria: correct
# sections in order, guides expanded, credentials excluded, no localhost, images
# re-homed, nav hrefs resolve, placeholder-domain fallback, and idempotency.
# No wp-env / Docker needed — the script is pure node stdlib.
# No `-e`: this file is its own reporter; some assertions expect non-zero rc.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$(cd "$HERE/../scripts" && pwd)/handoff-html-export.mjs"

fails=0
ok()  { printf '  ok   - %s\n' "$1"; }
bad() { printf '  FAIL - %s\n' "$1"; fails=$((fails + 1)); }
has()   { grep -q "$2" "$1" && ok "$3" || bad "$3"; }
hasnt() { grep -q "$2" "$1" && bad "$3" || ok "$3"; }

echo "handoff-html-export.test.sh"

command -v node >/dev/null 2>&1 || { printf '  SKIP - node not available\n'; exit 0; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

mkdir -p docs/guides/assets/vi/post
printf '\x89PNG\r\n\x1a\n' > docs/guides/assets/vi/post/01-list.png
printf '\x89PNG\r\n\x1a\n' > docs/guides/assets/vi/post/02-edit.png

cat > wp-build.json <<'JSON'
{
  "project": { "name": "Acme & Co" },
  "urls": { "local": "http://localhost:8888", "production": "https://acme.com" },
  "env": { "localUrl": "http://localhost:8888", "port": 8888 },
  "handoff": { "guides": { "locale": "vi", "flows": [
    { "id": "post", "title": "Bài viết", "category": "content", "doc": "docs/guides/02-post.md" }
  ] } }
}
JSON

cat > docs/site-handbook.md <<'MD'
# Site Handbook
Welcome to **Acme**. Sign in at http://localhost:8888/wp-login.php.
Uppercase host HTTP://LOCALHOST:8888/x and loopback http://127.0.0.1:8888/y.
A [bad link](javascript:alert(document.cookie)) and an ![x](javascript:alert(1)) image.
An out-of-tree image ![secret](../../../../etc/hostname).
## Editing
1. Go to Pages
2. Click *Edit*
| Plugin | Purpose |
|--------|---------|
| Yoast  | SEO     |
> Tip: back up first.
```bash
wp plugin list
```
MD

cat > docs/guides/02-post.md <<'MD'
# Bài viết
Đăng nhập tại http://localhost:8888/wp-login.php
1. Vào Bài viết
   ![Danh sách](assets/vi/post/01-list.png)
2. Ảnh thiếu
   ![missing](assets/vi/post/99-missing.png)
MD

cat > docs/maintenance-runbook.md   <<'MD'
# Maintenance Runbook
Rollback steps.
MD
cat > docs/monitoring-checklist.md  <<'MD'
# Monitoring Checklist
Uptime on https://acme.com.
MD
cat > docs/credentials-handoff.md   <<'MD'
# Credentials
CREDS_MARKER admin password lives in the vault.
MD

# --- 1. production-domain run --------------------------------------------------
out="$(node "$SCRIPT" --domain https://acme.com --generated-at 2026-07-18 2>/dev/null)"
rc=$?
H="docs/handoff-site/index.html"
[ "$rc" = "0" ] && ok "exit 0 on valid run" || bad "exit 0 on valid run (got $rc)"
[ -f "$H" ] && ok "index.html written" || bad "index.html written"

hasnt "$H" "localhost"            "no localhost in HTML"
hasnt "$H" "CREDS_MARKER"         "credentials doc excluded"
has   "$H" "https://acme.com/wp-login.php" "localhost rewritten to production"
has   "$H" 'id="handbook"'        "handbook section"
has   "$H" 'id="guide-post"'      "guide flow section"
has   "$H" 'id="maintenance"'     "maintenance section"
has   "$H" 'id="monitoring"'      "monitoring section"
hasnt "$H" 'id="a11y"'            "a11y absent when no file"
has   "$H" "nav-group"            "guides nav group"
has   "$H" "assets/img/vi-post-01-list.png" "screenshot re-homed"
has   "$H" "img-missing"          "missing image degraded, no crash"
has   "$H" "<table>"              "table rendered"
has   "$H" "<blockquote>"         "blockquote rendered"
has   "$H" "<pre><code>"          "code block rendered"
has   "$H" "Acme &amp; Co"        "project name html-escaped"
hasnt "$H" "javascript:"          "javascript: scheme dropped (no XSS href)"
hasnt "$H" "LOCALHOST"            "uppercase localhost rewritten"
has   "$H" "https://acme.com/y"   "127.0.0.1 loopback rewritten"
has   "$H" "img-missing"          "out-of-tree image skipped, not copied"
[ -f docs/handoff-site/assets/img/etc-hostname ] && bad "out-of-tree file was copied" || ok "out-of-tree file not copied"
[ -f docs/handoff-site/assets/css/handoff.css ] && ok "css copied" || bad "css copied"
[ -f docs/handoff-site/assets/js/handoff.js ]   && ok "js copied"  || bad "js copied"
[ -f docs/handoff-site/assets/img/vi-post-01-list.png ] && ok "image copied" || bad "image copied"

# nav href integrity — every href="#id" resolves to id="id"
missing=""
for id in $(grep -oE 'href="#[a-z0-9-]+"' "$H" | sed 's/href="#//;s/"//'); do
  grep -q "id=\"$id\"" "$H" || missing="$missing $id"
done
[ -z "$missing" ] && ok "every nav href resolves to a section" || bad "unresolved nav hrefs:$missing"

# --- 2. idempotency -----------------------------------------------------------
cp "$H" first.html
node "$SCRIPT" --domain https://acme.com --generated-at 2026-07-18 >/dev/null 2>&1
diff -q first.html "$H" >/dev/null && ok "byte-identical on re-run (idempotent)" || bad "not idempotent"

# --- 3. placeholder-domain fallback (no urls.production, no --domain) ----------
node -e 'const fs=require("fs");const m=JSON.parse(fs.readFileSync("wp-build.json"));delete m.urls.production;fs.writeFileSync("wp-build.json",JSON.stringify(m))'
node "$SCRIPT" >/dev/null 2>&1
has   "$H" "&lt;your-domain&gt;/wp-login.php" "placeholder domain substituted + escaped"
hasnt "$H" "localhost"            "no localhost in placeholder run"

# --- 4. bad manifest exits 2 --------------------------------------------------
node "$SCRIPT" --manifest does-not-exist.json >/dev/null 2>&1
[ "$?" = "2" ] && ok "exit 2 on missing manifest" || bad "exit 2 on missing manifest"

echo ""
if [ "$fails" -gt 0 ]; then
  printf '  %d assertion(s) FAILED\n' "$fails"
  exit 1
fi
printf '  all assertions passed\n'
