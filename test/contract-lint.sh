#!/usr/bin/env bash
# contract-lint.sh — static assertions that make the manifest contract and the
# "all WP-CLI via wpx" rule mechanical instead of prose discipline. This is the
# regression guard for the wpx migration (Phase 3). It is INSTRUCTION-LEVEL
# enforcement (it lints what authors/the model are TOLD to run) — NOT runtime
# enforcement of executed commands (Red Team #8).
#
#   bash test/contract-lint.sh        # exits 1 if any FAIL finding
#
# Rules:
#   FAIL  1. A skills/*/SKILL.md missing frontmatter name/description/allowed-tools,
#            or whose `name` != its directory.
#   FAIL  2. A wpbuild_progress/wpbuild_is_done <id> using an id outside the
#            canonical stage set (the greppable signal — there is no `stage:`
#            field; Red Team #10). The canonical set is DERIVED from
#            references/manifest-contract.md (not hard-coded), so it can't drift.
#   FAIL  3. Any `wp-env run cli` outside the allowlist, over the shipped surface
#            (whole repo minus node_modules/vendor/.git AND the historical
#            plans/ + reports/ working-doc trees, which are finding-log artifacts,
#            not instruction surface). Matches Phase 3's done-grep scope.
#   FAIL  5. A bare `wp <sub>` command at line-start inside a bash fence in any
#            shipped .md (model execution surface) — it must route through wpx.
#            Rule 3 only sees `wp-env run cli`; this closes the bare-`wp` gap so
#            "all WP-CLI via wpx" is actually enforced, not just claimed. Prose
#            inline-code mentions are outside fences / not line-start, so exempt;
#            operator-facing host runbooks (where bare `wp` is correct) are too.
#   WARN  4. A `wpbuild_get '.<key>'` top-level key absent from the schema (LLM
#            prose varies — WARN, never FAIL).
#
# Kept in sync with scripts/validate-port.sh (which also asserts snippets use
# wpx): a future edit to one should prompt the other.
#
# zsh-safe: executed, not sourced; pure static (no Docker/WP); jq for schema.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONTRACT="references/manifest-contract.md"
SCHEMA="schemas/wp-build.schema.json"

FAILS=0
WARNS=0
fail() { printf '  \033[0;31mFAIL\033[0m %s\n' "$*"; FAILS=$((FAILS + 1)); }
warn() { printf '  \033[1;33mWARN\033[0m %s\n' "$*"; WARNS=$((WARNS + 1)); }
ok()   { printf '  \033[0;32mok\033[0m   %s\n' "$*"; }

# walk <ext> — files with extension <ext>, excluding dependency/VCS trees and the
# historical plans/ + reports/ working-doc trees (not the shipped instruction
# surface). Shared shape with test/run.sh's walk().
walk() {
  local ext="$1"
  find . \
    \( -path './node_modules' -o -path './vendor' -o -path './.git' \
       -o -path './plans' -o -path './reports' \
       -o -path '*/node_modules' -o -path '*/vendor' -o -path '*/.git' \) -prune \
    -o -type f -name "*.${ext}" -print
}

# --- canonical stage set, derived from the contract (Red Team #10) -------------
# The ids live as inline `code` spans in the "## Stage ids (canonical)" section
# (there is no fenced block); extract every backtick-wrapped token there.
derive_canonical_stages() {
  # Stop at the first blank line after the id list (the explanatory paragraph
  # below it also has backtick tokens), and keep only stage-id-shaped tokens
  # (lowercase + dashes) so prose like `/wp-pro-max:site-editor`,
  # `optimization.outputDir`, `source/` never enter the canonical set (review #2).
  awk '
    /^## Stage ids \(canonical\)/ { insec=1; next }
    insec && /^## / { exit }
    insec && started && /^[[:space:]]*$/ { exit }   # blank AFTER the id list ends it
    insec && /[^[:space:]]/ {
      started=1
      while (match($0, /`[^`]+`/)) {
        tok = substr($0, RSTART+1, RLENGTH-2)
        if (tok ~ /^[a-z][a-z0-9-]*$/) print tok
        $0 = substr($0, RSTART+RLENGTH)
      }
    }
  ' "$CONTRACT"
}

# --- allowlist for rule 3 ------------------------------------------------------
# Whole-file exemptions (reasoned — the Phase 3 table). No phantom wpx.sh entry
# (Red Team #13); wpx.sh carries no raw `wp-env run cli`.
WPENV_ALLOW_FILES=(
  "scripts/wp-cli-runner.sh"        # the runner lib (fallback string lives here)
  "scripts/seed-helpers.sh"         # script-internal runner (Red Team #6)
  "scripts/migrate-urls.sh"         # script-internal destructive runner (Red Team #7)
  "commands/env.md"                 # it IS the env wrapper command
  "commands/plugin.md"              # non-wp: composer/phpcs/tests-cli (Red Team #3)
  "references/wp-cli-cheatsheet.md" # documents both forms
  "references/manifest-contract.md" # canonical doc (reconciled in P5; explanatory)
  "README.md"                       # doc (reconciled in P5)
  "CLAUDE.md"                       # project convention doc (reconciled in P5)
  "docs/system-architecture.md"     # doc
  "docs/tech-stack.md"              # doc
  "skills/wp-ship/references/ssh-wpcli-runbook.md" # remote SSH WP_CLI_RUN idiom
  "skills/wp-ship/references/ai1wm-runbook.md"     # remote SSH WP_CLI_RUN idiom
  "test/contract-lint.sh"           # this linter greps the literal
  "test/run.sh"                     # the gate references the literal in comments
  "test/seeder/runner.test.sh"      # asserts the fallback string
  "test/seeder/seed-batch.test.sh"  # asserts the fallback string
)
# Path|line-pattern exemptions (a raw `wp` call OUTSIDE the pattern still FAILs).
WPENV_ALLOW_PATTERNS=(
  "skills/wp-security/references/vuln-scan.sh|WP_CLI_RUN" # script-internal default
)
# NOTE: WPENV_ALLOW_FILES whole-file entries (docs/README/CLAUDE.md/cheatsheet)
# are unpoliced for a NEWLY introduced raw `wp-env run cli` — accepted tradeoff
# (they are explanatory docs, reconciled in P5); narrow them if that changes.

# Operator-facing docs where bare `wp` is correct because the snippet runs on the
# PRODUCTION host (where `wp` IS on PATH), not via the local wp-env. Exempt from
# the bare-`wp`-in-fence rule only.
BARE_WP_ALLOW_FILES=(
  "skills/wp-ship/references/ssh-wpcli-runbook.md"   # remote host WP-CLI
  "skills/wp-ship/references/ai1wm-runbook.md"        # remote host WP-CLI
  "skills/wp-handoff/references/maintenance-runbook.md" # generated into target docs/
  "references/wp-cli-cheatsheet.md"                   # documents both forms
)

_wpenv_allowed() {
  local file="$1" line="$2" entry path pat
  for entry in "${WPENV_ALLOW_FILES[@]}"; do
    [ "$file" = "./$entry" ] || [ "$file" = "$entry" ] && return 0
  done
  for entry in "${WPENV_ALLOW_PATTERNS[@]}"; do
    path="${entry%%|*}"; pat="${entry#*|}"
    if { [ "$file" = "./$path" ] || [ "$file" = "$path" ]; } && printf '%s' "$line" | grep -Eq -- "$pat"; then
      return 0
    fi
  done
  return 1
}

# --- frontmatter slice ---------------------------------------------------------
frontmatter() {
  awk 'BEGIN{n=0} /^---[[:space:]]*$/{n++; next} n==1{print} n==2{exit}' "$1"
}
fm_has() { printf '%s\n' "$1" | grep -Eq "^${2}:"; }

# === Rule 1: SKILL.md frontmatter ============================================
lint_frontmatter() {
  local f dir fm name bad=0
  for f in skills/*/SKILL.md; do
    [ -f "$f" ] || continue
    dir="$(basename "$(dirname "$f")")"
    fm="$(frontmatter "$f")"
    for key in name description allowed-tools; do
      fm_has "$fm" "$key" || { fail "$f: missing frontmatter key '$key'"; bad=1; }
    done
    name="$(printf '%s\n' "$fm" | awk -F':' '/^name:/{gsub(/[[:space:]]/,"",$2); print $2; exit}')"
    if [ -n "$name" ] && [ "$name" != "$dir" ]; then
      fail "$f: frontmatter name '$name' != directory '$dir'"; bad=1
    fi
  done
  [ "$bad" -eq 0 ] && ok "SKILL.md frontmatter: name/description/allowed-tools present, name==dir"
}

# === Rule 2: stage ids ∈ canonical ===========================================
lint_stage_ids() {
  local canon id file line raw bad=0
  canon="$(derive_canonical_stages)"
  if [ -z "$canon" ]; then
    fail "could not derive canonical stage ids from $CONTRACT"
    return
  fi
  # grep literal-id calls; skip variable args ($VAR / "$VAR" / quotes).
  while IFS= read -r raw; do
    [ -n "$raw" ] || continue
    file="${raw%%:*}"; rest="${raw#*:}"
    # rest looks like: wpbuild_progress <id> ...
    id="$(printf '%s' "$rest" | sed -E 's/.*wpbuild_(progress|is_done)[[:space:]]+//; s/[^a-zA-Z0-9_-].*$//')"
    [ -n "$id" ] || continue
    case "$id" in ''|\$*) continue ;; esac
    if ! printf '%s\n' "$canon" | grep -qx -- "$id"; then
      fail "$file: stage id '$id' not in canonical set (see $CONTRACT)"; bad=1
    fi
  done < <(grep -rnE 'wpbuild_(progress|is_done)[[:space:]]+[a-zA-Z]' skills commands 2>/dev/null)
  [ "$bad" -eq 0 ] && ok "stage ids: all wpbuild_progress/is_done ids ∈ canonical set"
}

# === Rule 3: no raw wp-env run cli outside allowlist =========================
lint_no_raw_wpenv() {
  local hit file line content bad=0
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    file="${hit%%:*}"; rest="${hit#*:}"; line="${rest%%:*}"; content="${rest#*:}"
    _wpenv_allowed "$file" "$content" && continue
    fail "$file:$line raw 'wp-env run cli' outside allowlist — route through wpx"
    bad=1
  done < <( { walk md; walk sh; } | xargs grep -nH 'wp-env run cli' 2>/dev/null )
  [ "$bad" -eq 0 ] && ok "no raw 'wp-env run cli' outside the allowlist (shipped surface)"
}

# === Rule 5: no bare `wp <sub>` in shipped-surface bash fences ================
# Closes the gap that Rule 3 (which only sees `wp-env run cli`) cannot: a model
# copying a `wp <sub>` snippet from skill/agent prose has no bare `wp` on PATH in
# the wp-env-only target — it must go through wpx. Fence-aware + line-start only
# (a command position), so prose inline-code mentions ("guarded `wp db query`")
# never trip it. Operator-facing host runbooks are exempt (bare `wp` is correct
# on the production host).
_bare_wp_allowed() {
  local file="$1" entry
  for entry in "${BARE_WP_ALLOW_FILES[@]}"; do
    [ "$file" = "./$entry" ] || [ "$file" = "$entry" ] && return 0
  done
  return 1
}
lint_bare_wp() {
  local f bad=0 hit
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    _bare_wp_allowed "$f" && continue
    while IFS= read -r hit; do
      [ -n "$hit" ] || continue
      fail "$f:$hit bare 'wp' command in a bash fence — route through wpx"
      bad=1
    done < <(awk '
      /^[[:space:]]*```/ {
        if (inb) { inb=0 } else {
          lang=$0; sub(/^[[:space:]]*```/,"",lang); gsub(/[[:space:]]/,"",lang)
          if (lang=="bash"||lang=="sh"||lang=="shell"||lang=="") inb=1
        }
        next
      }
      inb && $0 ~ /^[[:space:]]*wp[[:space:]]+[a-z]/ { printf "%d:%s\n", NR, $0 }
    ' "$f")
  done < <(walk md)
  [ "$bad" -eq 0 ] && ok "no bare 'wp' command in bash fences (model surface routes through wpx)"
}

# === Rule 4 (WARN): manifest keys ⊆ schema ===================================
lint_manifest_keys() {
  local keys schema_keys k
  command -v jq >/dev/null 2>&1 || { warn "jq absent — manifest-key check skipped"; return; }
  schema_keys="$(jq -r '.properties | keys[]' "$SCHEMA" 2>/dev/null)"
  [ -n "$schema_keys" ] || { warn "could not read schema properties from $SCHEMA"; return; }
  keys="$( { walk md; walk sh; } | xargs grep -rhoE "wpbuild_get '\.[a-zA-Z0-9_]+" 2>/dev/null \
    | sed -E "s/wpbuild_get '\.//" | sort -u )"
  local any=0
  for k in $keys; do
    printf '%s\n' "$schema_keys" | grep -qx -- "$k" || { warn "manifest key '.$k' not a top-level schema property"; any=1; }
  done
  [ "$any" -eq 0 ] && ok "manifest keys: all top-level wpbuild_get keys present in schema"
}

echo "contract-lint.sh"
lint_frontmatter
lint_stage_ids
lint_no_raw_wpenv
lint_bare_wp
lint_manifest_keys

echo
printf 'contract-lint: %d FAIL, %d WARN\n' "$FAILS" "$WARNS"
[ "$FAILS" -eq 0 ] && exit 0 || exit 1
