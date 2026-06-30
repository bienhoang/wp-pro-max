#!/usr/bin/env bash
# run.sh — run every seeder behavioral test (*.test.sh) and exit non-zero if any
# fails. No framework: plain bash. These are the host-side ORCHESTRATION tests
# (stub WP-CLI, no PHP). The idempotency / zero-dup contract is verified by the
# live wp-env acceptance runs documented in phase-02/03/04, not here.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0

for t in "$HERE"/*.test.sh; do
  [ -f "$t" ] || continue
  echo "=================================================================="
  bash "$t" || fails=$((fails + 1))
  echo
done

echo "=================================================================="
if [ "$fails" -eq 0 ]; then
  echo "ALL SEEDER TESTS PASSED"
  exit 0
fi
echo "$fails TEST FILE(S) FAILED"
exit 1
