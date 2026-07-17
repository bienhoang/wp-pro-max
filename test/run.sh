#!/usr/bin/env bash
# run.sh — the single standing gate for the wp-pro-max plugin.
#
# Runs every static check, in order, WITHOUT stopping at the first failure, so one
# invocation surfaces all problems. Exits non-zero if any check FAILed.
#
#   bash test/run.sh
#
# Checks:
#   1. claude plugin validate .        (SKIP+warn if the `claude` CLI is absent)
#   2. bash -n   on every *.sh
#   3. node --check on every *.mjs
#   4. php -l    on every *.php via a throwaway `php:8.2-cli` container
#                (NOT wp-env — `php -l` needs only PHP; SKIP only if Docker absent)
#   5. scripts/validate-port.sh        (the existing snippet linter)
#   6. test/contract-lint.sh           (manifest / wpx contract enforcer)
#   7. test/seeder/run.sh              (seeder behavioral tests)
#
# File discovery excludes node_modules, vendor, .git (Red Team #4): these are
# dependency / VCS trees, never linted. Centralized in walk().
#
# zsh-safe: this file is EXECUTED (never sourced), so `set -euo pipefail` here is
# fine and does not leak into a caller's shell.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PHP_IMAGE="php:8.2-cli"   # pinned tag; syntax-only, matches the wp-env PHP target

PASS=0
FAIL=0
SKIP=0
FAILED_CHECKS=()

_say()  { printf '%s\n' "$*"; }
_pass() { printf '  \033[0;32mPASS\033[0m %s\n' "$*"; PASS=$((PASS + 1)); }
_skip() { printf '  \033[1;33mSKIP\033[0m %s\n' "$*"; SKIP=$((SKIP + 1)); }
_fail() { printf '  \033[0;31mFAIL\033[0m %s\n' "$*"; FAIL=$((FAIL + 1)); }

# run_check "<label>" <fn> — run a check function; it must return 0 (pass),
# 2 (skip), or non-zero/other (fail). Never early-exits the gate.
run_check() {
  local label="$1" fn="$2" rc
  printf '\n\033[1m==> %s\033[0m\n' "$label"
  "$fn"
  rc=$?
  case "$rc" in
    0) ;;                                  # check printed its own PASS lines
    2) ;;                                  # check printed its own SKIP line
    *) FAILED_CHECKS+=("$label") ;;        # check printed its own FAIL lines
  esac
}

# walk <ext> — print every tracked-or-untracked file with extension <ext>,
# excluding node_modules / vendor / .git. One path per line.
walk() {
  local ext="$1"
  find . \
    \( -path './node_modules' -o -path './vendor' -o -path './.git' \
       -o -path '*/node_modules' -o -path '*/vendor' -o -path '*/.git' \) -prune \
    -o -type f -name "*.${ext}" -print
}

# --- 1. claude plugin validate -------------------------------------------------
check_plugin_validate() {
  if ! command -v claude >/dev/null 2>&1; then
    _skip "claude CLI not found — plugin manifest not validated (install claude to enable)"
    return 2
  fi
  if claude plugin validate . ; then
    _pass "claude plugin validate ."
    return 0
  fi
  _fail "claude plugin validate . reported errors"
  return 1
}

# --- 2. bash -n ----------------------------------------------------------------
check_bash_syntax() {
  local f bad=0 n=0
  while IFS= read -r f; do
    n=$((n + 1))
    if ! bash -n "$f" 2>&1; then
      _fail "bash -n $f"
      bad=$((bad + 1))
    fi
  done < <(walk sh)
  if [ "$bad" -eq 0 ]; then
    _pass "bash -n clean across $n shell script(s)"
    return 0
  fi
  return 1
}

# --- 3. node --check -----------------------------------------------------------
check_node_check() {
  if ! command -v node >/dev/null 2>&1; then
    _skip "node not found — *.mjs not syntax-checked"
    return 2
  fi
  local f bad=0 n=0
  while IFS= read -r f; do
    n=$((n + 1))
    if ! node --check "$f" 2>&1; then
      _fail "node --check $f"
      bad=$((bad + 1))
    fi
  done < <(walk mjs)
  if [ "$bad" -eq 0 ]; then
    _pass "node --check clean across $n module(s)"
    return 0
  fi
  return 1
}

# --- 4. php -l via throwaway php:8.2-cli container ------------------------------
# Decoupled from wp-env (Red Team #5): `php -l` needs only PHP, not WordPress, so
# it runs in a disposable container anywhere Docker exists. SKIP only when Docker
# itself is absent — and say loudly how many files went unchecked.
check_php_lint() {
  local files n
  files="$(walk php)"
  n="$(printf '%s' "$files" | grep -c . || true)"
  if [ "$n" -eq 0 ]; then
    _pass "no .php files to lint"
    return 0
  fi
  if ! command -v docker >/dev/null 2>&1; then
    _skip "Docker absent — $n .php file(s) NOT syntax-checked"
    return 2
  fi
  # Lint every file inside one container; collect failures, never early-exit.
  if docker run --rm -v "$ROOT":/code -w /code "$PHP_IMAGE" \
       sh -c 'rc=0; while IFS= read -r f; do [ -n "$f" ] || continue; php -l "$f" || rc=1; done; exit $rc' \
       <<<"$files"; then
    _pass "php -l clean across $n file(s) (via $PHP_IMAGE)"
    return 0
  fi
  _fail "php -l reported errors (via $PHP_IMAGE)"
  return 1
}

# --- 5. validate-port.sh (existing snippet linter) -----------------------------
check_validate_port() {
  if [ ! -f scripts/validate-port.sh ]; then
    _skip "scripts/validate-port.sh not present"
    return 2
  fi
  if bash scripts/validate-port.sh ; then
    _pass "scripts/validate-port.sh"
    return 0
  fi
  _fail "scripts/validate-port.sh reported errors"
  return 1
}

# --- 6. contract-lint.sh (manifest / wpx contract) -----------------------------
check_contract_lint() {
  if [ ! -f test/contract-lint.sh ]; then
    _skip "test/contract-lint.sh not present"
    return 2
  fi
  if bash test/contract-lint.sh ; then
    _pass "test/contract-lint.sh"
    return 0
  fi
  _fail "test/contract-lint.sh reported FAIL findings"
  return 1
}

# --- 7. wpx shim test ----------------------------------------------------------
check_wpx() {
  if [ ! -f test/wpx.test.sh ]; then
    _skip "test/wpx.test.sh not present"
    return 2
  fi
  if bash test/wpx.test.sh ; then
    _pass "test/wpx.test.sh"
    return 0
  fi
  _fail "test/wpx.test.sh reported failures"
  return 1
}

# --- 9. wp-fix lib test --------------------------------------------------------
check_wp_fix() {
  if [ ! -f test/wp-fix.test.sh ]; then
    _skip "test/wp-fix.test.sh not present"
    return 2
  fi
  if bash test/wp-fix.test.sh ; then
    _pass "test/wp-fix.test.sh"
    return 0
  fi
  _fail "test/wp-fix.test.sh reported failures"
  return 1
}

# --- 8. seeder behavioral tests ------------------------------------------------
check_seeder() {
  if [ ! -f test/seeder/run.sh ]; then
    _skip "test/seeder/run.sh not present"
    return 2
  fi
  if bash test/seeder/run.sh ; then
    _pass "test/seeder/run.sh"
    return 0
  fi
  _fail "test/seeder/run.sh reported failures"
  return 1
}

run_check "claude plugin validate"   check_plugin_validate
run_check "bash -n (shell syntax)"   check_bash_syntax
run_check "node --check (mjs syntax)" check_node_check
run_check "php -l (php syntax)"      check_php_lint
run_check "validate-port.sh"         check_validate_port
run_check "contract-lint.sh"         check_contract_lint
run_check "wpx shim test"            check_wpx
run_check "seeder tests"             check_seeder
run_check "wp-fix lib test"          check_wp_fix

printf '\n\033[1m==> Summary\033[0m\n'
_say "  PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP"
if [ "${#FAILED_CHECKS[@]}" -gt 0 ]; then
  _say "  Failed checks:"
  for c in "${FAILED_CHECKS[@]}"; do _say "    - $c"; done
  exit 1
fi
_say "  All checks green."
exit 0
