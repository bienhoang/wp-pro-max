---
phase: 3
title: "Test"
status: completed
priority: P2
dependencies: [2]
---

# Phase 3: Test

## Overview

Validate the helper script with syntax checks, negative cases, and a realistic
response. Because the user does not have a `PAGESPEED_API_KEY` ready for this
plan, Phase 3 uses a checked-in sample PSI response to verify parsing and
report generation. A live call is documented as a final manual step once a key
is available.

## Requirements

- Functional: script exits correctly and produces valid reports for happy path
  and common error cases.
- Non-functional: tests run quickly; no persistent side effects except report
  files in the working directory.

## Architecture

Tests are shell-level and manual (no test harness exists for bash helpers yet):

```bash
# Syntax check
bash -n skills/wp-pagespeed/references/run-pagespeed.sh

# Missing API key
bash skills/wp-pagespeed/references/run-pagespeed.sh https://example.com
# Expected: exit 1, error mentions PAGESPEED_API_KEY

# Missing URL
PAGESPEED_API_KEY=dummy bash skills/wp-pagespeed/references/run-pagespeed.sh
# Expected: exit 1, error mentions URL

# Bad scheme
PAGESPEED_API_KEY=dummy bash skills/wp-pagespeed/references/run-pagespeed.sh ftp://example.com
# Expected: exit 1, error mentions http:// or https://

# URL with embedded credentials (rejected)
PAGESPEED_API_KEY=dummy bash skills/wp-pagespeed/references/run-pagespeed.sh \
  https://user:pass@example.com
# Expected: exit 1, error mentions credentials not allowed

# URL with shell metacharacters (rejected)
PAGESPEED_API_KEY=dummy bash skills/wp-pagespeed/references/run-pagespeed.sh \
  'https://example.com;id'
# Expected: exit 1, error mentions invalid URL

# Sample-response parsing (no live API key needed)
PAGESPEED_API_KEY=dummy bash skills/wp-pagespeed/references/run-pagespeed.sh \
  --sample skills/wp-pagespeed/references/sample-psi-response.json
# Expected: Markdown report created from sample JSON

# Live call (requires a real key)
PAGESPEED_API_KEY=xxx bash skills/wp-pagespeed/references/run-pagespeed.sh \
  https://example.com mobile
# Expected: two files created, Markdown contains score + metrics + opportunities
```

## Related Code Files

- Test: `skills/wp-pagespeed/references/run-pagespeed.sh`
- Inspect: generated `*.json` and `*.md` report files

## Implementation Steps

1. Run `bash -n` and, if available, `zsh -n` on the helper script.
2. Run the negative cases (missing key, missing URL, bad scheme, URL with
   credentials, URL with shell metacharacters) and assert non-zero exit codes
   and clear error messages.
3. Run the sample-response parsing test using
   `references/sample-psi-response.json` (no live key needed).
4. Verify the generated Markdown report contains:
   - Overall performance score
   - LCP, CLS, FCP, TBT, SI, INP (or n/a)
   - Top 5 opportunities with estimated savings
   - Command used and timestamp
5. (Optional, requires real key) Run the live call against `https://example.com`
   with `strategy=mobile`, then again with `strategy=desktop` and `locale=vi`.
6. If any jq path fails, fix the script and re-run from step 1.
7. Mark phase complete and move to Phase 4.

## Success Criteria

- [ ] `bash -n` (and `zsh -n` if available) passes with no errors.
- [ ] Missing `PAGESPEED_API_KEY` exits non-zero with a clear message.
- [ ] Missing URL exits non-zero with a clear message.
- [ ] Bad URL scheme exits non-zero with a clear message.
- [ ] URL with embedded credentials is rejected.
- [ ] URL with shell metacharacters is rejected.
- [ ] Sample-response test produces a Markdown report with all required fields
      (score, CWV metrics, opportunities, timestamp).
- [ ] Live call instructions are documented for when a real key is available.
- [ ] `desktop` strategy and non-default locale parameters work (verified via
      sample or live call).

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| No Google API key available for live test | Ask user for a temporary key or skip live test with a note; do not commit a key. |
| PSI API rate-limits during testing | Use `example.com` once per strategy; cache response if re-running. |
| Report output varies by Lighthouse version | Do not hardcode exact values; assert presence of fields, not numeric equality. |
