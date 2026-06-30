#!/usr/bin/env bash
# seed-batch-run.sh — run ONE seed stage as a single PHP batch and merge the
# result into wp-build.json.
#
#   bash "${CLAUDE_PLUGIN_ROOT}/scripts/seed-batch-run.sh" <payload.json> [runtime.php]
#
# It pipes the PURE-JSON payload to `wp eval-file seed-batch-runtime.php` (the
# runtime reads it from php://stdin), recovers the sentinel-wrapped JSON summary
# the runtime prints, then merges into the manifest:
#   - seed.idempotencyKeys  (APPEND + unique — never jq `*`, which replaces arrays)
#   - seed.lastRun          (UTC timestamp)
#   - seed.lastSummary      (the run summary, for observability)
#
# Transport: `wp eval-file <path>` needs the runtime file reachable INSIDE the WP
# container, but the plugin lives on the host. So when a project cli container is
# resolved, the driver `docker cp`s the runtime in and `docker exec -i`s it (the
# fast, stdin-forwarding path). With a $WP_CLI_RUN override (local wp / ssh) it
# pipes directly. The wp-env fallback is best-effort (the file must already be
# reachable by that runner).
#
# Fails LOUDLY (non-zero) when the summary is missing or when the payload had ops
# but nothing was created/updated/skipped — an empty/zero-op run must never read
# as a silent "done" (red-team H6).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wp-cli-runner.sh"

WP_BUILD_FILE="${WP_BUILD_FILE:-./wp-build.json}"

_run_log() { printf 'seed-batch-run: %s\n' "$*" >&2; }
_run_die() { _run_log "ERROR: $*"; exit 1; }

PAYLOAD="${1:?usage: seed-batch-run.sh <payload.json> [runtime.php]}"
RUNTIME="${2:-${SCRIPT_DIR}/seed-batch-runtime.php}"

command -v jq >/dev/null 2>&1 || _run_die "jq is required"
[ -f "$PAYLOAD" ]  || _run_die "payload not found: $PAYLOAD"
[ -f "$RUNTIME" ]  || _run_die "runtime not found: $RUNTIME"
jq -e . "$PAYLOAD" >/dev/null 2>&1 || _run_die "payload is not valid JSON: $PAYLOAD"

# How many ops does the payload actually carry? Used to catch a silent zero-op run.
op_count="$(jq -r '
  ((.options // {}) | length)
  + ((.media // []) | length) + ((.posts // []) | length)
  + ((.terms // []) | length) + ((.menus // []) | length)
  + ((.acf // []) | length)  + ((.elementor // []) | length)
  + (if (.frontPage // "") == "" then 0 else 1 end)
' "$PAYLOAD")"

# ---- Choose transport + execute ------------------------------------------
raw=""
if [ -n "${WP_CLI_RUN:-}" ]; then
  # Honor the override verbatim; assume the runtime path is reachable by it.
  _run_log "transport: WP_CLI_RUN override ($WP_CLI_RUN)"
  raw="$(wp_cli eval-file "$RUNTIME" < "$PAYLOAD")"
else
  container=""; det_rc=0
  container="$(_wpcli_detect_container)" || det_rc=$?
  if [ "$det_rc" -eq 2 ]; then
    _run_die "ambiguous wp-env cli container — set WP_CLI_RUN to choose explicitly"
  fi
  if [ "$det_rc" -eq 0 ] && [ -n "$container" ]; then
    # docker transport: stage the runtime into the container, then exec it.
    runtime_tmp="/tmp/seed-batch-runtime.$$.php"
    _run_log "transport: docker exec ($container)"
    docker cp "$RUNTIME" "${container}:${runtime_tmp}" >/dev/null \
      || _run_die "docker cp of runtime into $container failed"
    raw="$(docker exec -i "$container" wp eval-file "$runtime_tmp" < "$PAYLOAD")" \
      || { docker exec "$container" rm -f "$runtime_tmp" >/dev/null 2>&1 || true; _run_die "batch execution failed in $container"; }
    docker exec "$container" rm -f "$runtime_tmp" >/dev/null 2>&1 || true
  else
    # No project cli container resolved. Honor the strict mode explicitly here
    # (rather than relying on the fallback's resolve failing under set -e).
    if [ "${WP_CLI_REQUIRE_CONTAINER:-}" = "1" ]; then
      _run_die "no project '*-cli-1' container found and WP_CLI_REQUIRE_CONTAINER=1"
    fi
    # wp-env fallback (best-effort): the runtime path must be reachable by it.
    _run_log "transport: wp-env fallback (runtime path must be container-reachable)"
    raw="$(wp_cli eval-file "$RUNTIME" < "$PAYLOAD")"
  fi
fi

# ---- Recover the sentinel-wrapped summary --------------------------------
# grep -o isolates the JSON span even when WP_DEBUG notices share the stream.
span="$(printf '%s\n' "$raw" | grep -o 'WPBUILD_SUMMARY.*WPBUILD_END' | head -n1 || true)"
[ -n "$span" ] || { _run_log "raw output was:"; printf '%s\n' "$raw" >&2; _run_die "no WPBUILD_SUMMARY…WPBUILD_END sentinel in output"; }
summary="${span#WPBUILD_SUMMARY}"
summary="${summary%WPBUILD_END}"

echo "$summary" | jq -e . >/dev/null 2>&1 || _run_die "summary between sentinels is not valid JSON: $summary"

created="$(jq -r '.created // 0' <<<"$summary")"
updated="$(jq -r '.updated // 0' <<<"$summary")"
skipped="$(jq -r '.skipped // 0' <<<"$summary")"
nerr="$(jq -r '(.errors // []) | length' <<<"$summary")"
completed="$(jq -r '.completed // false' <<<"$summary")"

# Silent-success guard (red-team H6): a run that created/updated/skipped NOTHING
# and reported NO errors is either an empty payload or a generation bug — never a
# legitimate "done". (A re-run has skipped>0; a real first run has created/updated
# >0; a failed op surfaces via errors and the completed gate below.)
if [ "$((created + updated + skipped))" -eq 0 ] && [ "${nerr:-0}" -eq 0 ]; then
  _run_log "summary was: $summary"
  _run_die "payload carried ${op_count} ops but produced no activity and no errors (silent zero-op run)"
fi

# ---- Merge into the manifest (append + unique; never jq `*`) --------------
if [ -f "$WP_BUILD_FILE" ]; then
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  tmp="$(mktemp)"
  jq \
    --argjson sum "$summary" \
    --arg ts "$ts" \
    '.seed = (.seed // {})
     | .seed.idempotencyKeys = (((.seed.idempotencyKeys // []) + ($sum.idempotencyKeys // [])) | unique)
     | .seed.lastRun = $ts
     | .seed.lastSummary = $sum' \
    "$WP_BUILD_FILE" > "$tmp" && mv "$tmp" "$WP_BUILD_FILE"
else
  _run_log "manifest $WP_BUILD_FILE not found — skipping merge (summary printed below)"
fi

_run_log "done — created:${created} updated:${updated} skipped:${skipped} errors:${nerr}"
printf '%s\n' "$summary"

# Surface op errors as a non-fatal warning (the batch still completed).
[ "${nerr:-0}" -gt 0 ] && _run_log "WARNING: ${nerr} op error(s) — see .seed.lastSummary.errors"

# An incomplete run (a fatal interrupted the batch) is reported LOUDLY — but only
# after the partial idempotencyKeys above were merged, so a re-run resumes safely.
if [ "$completed" != "true" ]; then
  _run_die "batch did NOT complete (fatal mid-run); partial state merged — safe to re-run"
fi
exit 0
