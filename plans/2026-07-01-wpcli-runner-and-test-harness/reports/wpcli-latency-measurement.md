# WP-CLI latency — `wp-env run cli` vs `wpx` (`docker exec`)

**Date:** 2026-07-01
**Status:** Structural win shipped; per-call wall-clock measurement **PENDING a live
wp-env** (none provisioned in this session — numbers are NOT fabricated).

## What is already proven (structurally)

`wpx` resolves to `docker exec -i <project>-cli-1 wp …` against a **long-lived**
container when one is up (`scripts/wp-cli-runner.sh` → `wp_cli_resolve`), instead
of `wp-env run cli`, which boots a **fresh** container per invocation. The seed
batch engine already relies on this path; the gate (`test/run.sh`) and
`test/wpx.test.sh` prove resolution, stdin forwarding, exit-code propagation, and
the `*-tests-cli-1` exclusion. The number of fresh-container boots per heavy stage
(i18n ~20, security ~19, perf-backend ~17, seo ~15 calls) drops to zero once a
live `*-cli-1` resolves.

## How to capture the per-call numbers (run on a machine with a started wp-env)

```bash
# From the TARGET project root (has .wp-env.json), with `wp-env start` completed.
cd /path/to/target-wp-project

# Old path — fresh container per call.
time ( for i in $(seq 1 10); do npx wp-env run cli wp option get siteurl >/dev/null; done )

# New path — docker exec into the live container.
time ( for i in $(seq 1 10); do bash "${CLAUDE_PLUGIN_ROOT}/scripts/wpx.sh" option get siteurl >/dev/null; done )
```

Record below: total for 10 calls each, and the per-call mean (total ÷ 10).

| Path | 10-call total | per-call mean |
|------|---------------|---------------|
| `wp-env run cli wp option get siteurl` | _pending_ | _pending (~3.7s expected)_ |
| `wpx option get siteurl` (`docker exec`) | _pending_ | _pending (~0.1s expected)_ |

## Honest framing (Red Team #8)

This is the measurable win **contingent on**: (a) the model actually using the
`wpx` default the prose now documents, and (b) a live `*-cli-1` resolving. When no
container resolves, `wpx` transparently falls back to `wp-env run cli wp` and the
timing reverts to baseline — correctness is preserved either way. The contract
lint enforces *instruction consistency* (authors/model are told to use `wpx`), not
runtime interception of executed commands.
