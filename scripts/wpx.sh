#!/usr/bin/env bash
# wpx.sh — the one canonical WP-CLI entry every skill/agent prose uses.
#
#   bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" option get siteurl
#   printf '%s' "$payload_json" | bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" eval-file -
#
# It is a near-trivial shim over wp_cli() in wp-cli-runner.sh, which resolves the
# runner once (WP_CLI_RUN override → live `*-cli-1` `docker exec -i` fast path →
# wp-env fallback) and forwards this process's stdin. Pass the WP
# SUBCOMMAND only — wp_cli prepends `wp` itself (so `wpx option get …`, not
# `wpx wp option get …`).
#
# What wpx does and does NOT guarantee (Red Team #8): it changes the DEFAULT
# command the prose tells the model to run. It does not intercept commands the
# model actually issues and cannot force compliance. The measurable speed win
# (~3.7s fresh-container boot → ~0.1s `docker exec`) lands only when (a) the model
# uses it and (b) a live `*-cli-1` resolves; otherwise it transparently falls back
# to the wp-env runner with identical behavior.
#
# Readiness, not just presence (Red Team #14): wp_cli's container detection keys
# on the name appearing in `docker ps`, NOT on WordPress being provisioned. A raw
# `docker exec` against an up-but-unready container (mid `wp-env start`, DB not
# migrated) can fail. wpx propagates that non-zero exit verbatim — it NEVER
# swallows a failure into a silent wrong result. Stage skills gate real work
# behind an explicit readiness probe (`wpx option get siteurl` first). No
# auto-retry / health-loop here by design (YAGNI): the loud failure tells the
# operator to finish `wp-env start`.
#
# zsh-safe: the runtime shell is zsh. No top-level `set -euo pipefail` (it would
# leak into a sourcing caller); no `status`/`path` locals; sourcing-vs-execution
# guard at the bottom mirrors wp-cli-runner.sh.

_wpx_dir() {
  # Resolve this script's directory under both bash and zsh. The zsh-only
  # `${(%):-%x}` is wrapped in eval so bash never parses it (it would be a bad
  # substitution); bash takes the BASH_SOURCE branch.
  local src
  if [ -n "${BASH_SOURCE:-}" ]; then
    src="${BASH_SOURCE[0]}"
  elif [ -n "${ZSH_VERSION:-}" ]; then
    eval 'src="${(%):-%x}"'
  else
    src="$0"
  fi
  cd "$(dirname "$src")" >/dev/null 2>&1 && pwd
}

# Source the resolution + stdin-forwarding library (single source of truth — do
# NOT duplicate its logic here).
# shellcheck source=scripts/wp-cli-runner.sh
. "$(_wpx_dir)/wp-cli-runner.sh"

# ---------------------------------------------------------------------------
# Sourcing-vs-execution guard (bash + zsh). When EXECUTED, run the WP subcommand
# through wp_cli and propagate ITS exit code (not the wrapper's). wp_cli forwards
# this process's stdin, so `wpx.sh eval-file -` keeps working (contract pinned by
# the seeder + test/wpx.test.sh).
# ---------------------------------------------------------------------------
_wpx_sourced=1
if [ -n "${BASH_VERSION:-}" ]; then
  [ "${BASH_SOURCE[0]}" = "$0" ] && _wpx_sourced=0
elif [ -n "${ZSH_VERSION:-}" ]; then
  case "${ZSH_EVAL_CONTEXT:-}" in *:file*) _wpx_sourced=1 ;; *) _wpx_sourced=0 ;; esac
fi

if [ "$_wpx_sourced" = "0" ]; then
  wp_cli "$@"
  exit $?
fi
