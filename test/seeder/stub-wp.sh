#!/usr/bin/env bash
# stub-wp.sh — a fake `wp` for behavioral seeder tests. It records every
# invocation's argv to $SEED_TEST_LOG and returns canned output keyed by
# subcommand, so the seed ORCHESTRATION (one eval-file call, stdin delivery,
# sentinel summary parse, manifest merge) can be exercised with no live WordPress
# and no PHP. It deliberately does NOT model idempotency / zero-dup — that
# contract lives in PHP and is verified by the live wp-env acceptance run.
#
# Put this dir on PATH as `wp` (the test harness symlinks/aliases it). Env:
#   SEED_TEST_LOG  — file to append "<one argv per line>" call records to.
#   SEED_STUB_RUN  — "1" after first run, so `post list` can simulate "exists".
set -euo pipefail

log_file="${SEED_TEST_LOG:?SEED_TEST_LOG must be set}"

# Record the call: subcommand chain + args, tab-separated, one line per call.
printf '%s\n' "$*" >> "$log_file"

sub="${1:-}"; sub2="${2:-}"

case "$sub $sub2" in
  "eval-file "*)
    # Simulate the batch runtime: read the piped JSON payload from stdin, record
    # its byte length so the test can assert stdin was actually delivered
    # (guards red-team H6 silent-empty-stdin false success), then emit a
    # sentinel-wrapped JSON summary exactly as the real runtime would.
    payload="$(cat)"
    printf '%s' "$payload" | wc -c | tr -d ' ' > "${log_file}.stdin"
    # A WP_DEBUG-style notice on stdout BEFORE the sentinel — the parser must
    # still find the summary between the markers, not choke on this banner.
    printf 'Notice: wp_debug noise that must not break the parse\n'
    printf 'WPBUILD_SUMMARY{"created":2,"updated":0,"skipped":0,"completed":true,"errors":[],"idempotencyKeys":["page:home","menu:Primary"]}WPBUILD_END\n'
    ;;
  "option get")
    # Empty current value → driver/ helper will treat as "needs set".
    printf '\n'
    ;;
  "post list"*)
    if [ "${SEED_STUB_RUN:-0}" = "1" ]; then
      printf 'home\n'   # second run: slug exists (idempotency simulation)
    fi
    ;;
  "post create"*)
    printf '101\n'      # canned porcelain ID
    ;;
  *)
    : ;;               # unknown subcommands: no output, exit 0
esac
