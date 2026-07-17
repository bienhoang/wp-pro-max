---
name: wp-fix
description: >-
  Remediate WordPress issues that /wp-pro-max:audit recorded in
  `audit.findings`. Triages each static PHP finding against the real source,
  proposes a diff for explicit approval, applies only what the user approves,
  verifies by static re-scan, and records the outcome in `fix.*` in
  `wp-build.json`. Propose-only: it never edits a file without an approved diff.
  Also diagnoses free-text WordPress symptoms (white screen, wrong template, ACF
  field empty) via a fault taxonomy. Covers the nine static PHP rules; a11y,
  live performance, live vulnerability, and third-party findings are reported to
  `fix.unsupported[]` with a pointer to the skill that owns them.
user-invocable: true
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion]
---

# WP Fix (`wp-fix`)

The remediation counterpart to `wp-audit`. `audit` finds (read-only); `fix`
proposes, applies on approval, and verifies.

## When to use

- The user asks to fix, remediate, or clean up what an audit found.
- The user describes a WordPress symptom in their own words ("trắng trang sau
  khi activate theme", "ACF field không hiện ra").

Not for authoring: "fix the header template" (build me a header) is
`wp-theme-developer` work, not a finding-driven remediation.

## HARD GATES — non-negotiable

<HARD-GATE-APPROVAL>
No file is edited without a diff the user explicitly approved, one finding at a
time, via `AskUserQuestion`. There is no auto-apply lane, no `--yes`, no "these
are low-risk so I batched them". The entire safety story of v1 is *the user
approved this exact diff*, so the actor that showed the diff must be the actor
that applies it — never delegate the edit to an agent.
</HARD-GATE-APPROVAL>

<HARD-GATE-BACKUP>
Every approved write is preceded by `fix_backup <file>`. No backup → no write.
"I can revert that" is only true if a snapshot exists.
</HARD-GATE-BACKUP>

<HARD-GATE-VERIFY>
A failed, missing, or unparseable re-scan is **never** reported as success.
`fix_verify` returns `status: scanner-failed` for exactly this case — report it as
unverified and say so plainly. `audit-static.sh` swallows scanner errors (`|| true`
at `:232`, `|| echo '{}'` at `:272`) and degrades to an empty finding set with exit
0, which is indistinguishable from a clean scan and happens to satisfy "targeted
findings gone AND nothing new" perfectly.
</HARD-GATE-VERIFY>

## Scope — what v1 fixes

The **nine static PHP rules** (`scripts/audit-static.sh:98-107` + `:184`) — the
only findings with a real line number to anchor a diff to:

| id | severity | category | real risk |
|---|---|---|---|
| `sec-eval` | critical | security | arbitrary code execution |
| `sec-unsafe-include` | critical | security | LFI/RFI |
| `sec-unserialize` | high | security | object injection |
| `sec-file-write-user-input` | high | security | arbitrary file write |
| `sec-base64-decode` | medium | security | obfuscation (usually a false positive) |
| `wpcs-output-not-escaped` | high | **code-style** | **XSS** |
| `wpcs-direct-db-no-prepare` | high | **code-style** | **SQL injection** |
| `wpcs-missing-sanitize` | high | **code-style** | unvalidated input |
| `wpcs-missing-nonce` | high | **code-style** | **CSRF** |

**`category` does not track risk.** XSS, SQLi, and CSRF are all `code-style`.
Never key any policy, lane, or filter on `category` — use the explicit id list
`FIX_SUPPORTED_RULES_JSON` in `scripts/wp-fix-lib.sh`.

Everything else goes to `fix.unsupported[]` **with a pointer, never dropped**:
a11y (`line: 0` — no anchor, and most rules need authored content), live
performance and vulnerability findings (`file` is a URL or `plugin/<slug>`), and
`external: true` third-party code (an edit there is reverted by the next update).

## Flags

- `--severity critical|high|medium|low` — minimum threshold, inclusive.
- `--category security|code-style` — v1's two fixable categories.
- `--dry-run` — print the plan and every proposed diff, write nothing.
- `"<free text>"` — a symptom to diagnose; routes via `references/fault-taxonomy.md`.

## Procedure

### 0. Load

```bash
set -e
source "${CLAUDE_PLUGIN_ROOT}/scripts/wp-fix-lib.sh"

# Locate the manifest: ./wp-build.json, else ./wp/wp-build.json.
if [ ! -f "${WP_BUILD_FILE:-./wp-build.json}" ] && [ -f "./wp/wp-build.json" ]; then
  cd ./wp || { echo "wp-fix: cannot enter ./wp" >&2; exit 1; }
fi
[ -f "${WP_BUILD_FILE:-./wp-build.json}" ] || { echo "wp-fix: no wp-build.json. Run /wp-pro-max:init first." >&2; exit 1; }

fix_parse_args "$@" || exit 2      # "$@" — free-text is multi-word
wpbuild_progress fix in-progress "triage starting"

fix_audit_age_warn || { echo "Run /wp-pro-max:audit --static first." >&2; exit 1; }

fix_backup_dir_init            # REQUIRED before any fix_backup — sets FIX_BACKUP_DIR
fix_init "audit:$(wpbuild_get '.audit.generatedAt')"   # stamps fix.{generatedAt,trigger,backupDir,verified:false}

PARTITION="$(fix_load_findings)"
```

If `FIX_FREE_TEXT` is set → **free-text branch**: route the symptom via
`references/fault-taxonomy.md` to one playbook, gather that playbook's evidence
**before** proposing anything, then rejoin at step 3 (propose → approve → backup
→ apply). A symptom names a fault *class*, not a cause — a white screen is twenty
different bugs. If the symptom matches no row, say it is unroutable and ask; do
not pick the nearest-looking playbook.

The free-text branch carries **no `category` and no `severity`** — those come
from `audit.findings`. It therefore takes the strictest policy by default, never
a laxer one. Gate 3 also degrades here: there is no baseline finding to diff
against, so verification is `php -l` + "no new static findings" + the symptom
being gone. Say which of those you actually checked.

Report `.unsupported[]` to the user **immediately**, with each finding's
`pointer`, before any triage. They see the whole picture up front rather than
discovering the gap after approving ten diffs. Record them:
`fix_record unsupported '<json>'`.

### 1. Triage → `references/triage-findings.md`

For each `.supported[]` finding: `Read` the file at `line` and decide whether the
defect is **real in context**. The scanner is a grep; it has no idea whether the
value was escaped two lines up.

- **confirmed** → carry to step 2.
- **false positive** → `fix_record dismissed` with a **mandatory reason**.
- **needs a human** → `fix_record remaining` with a reason.

### 2. Plan

```bash
fix_group_by_file "$PARTITION"     # line-DESCENDING within each file
```

Line-descending is load-bearing: fixing line 10 first can change the file's line
count, leaving the already-computed line 42 pointing at unrelated code.

If `FIX_DRY_RUN=1` → print the plan and the diffs, then **exit. Write nothing.**

### 3. Propose + apply — one finding at a time

```
show the unified diff  →  AskUserQuestion  →  approved?
  yes → fix_backup <file>   THEN   Edit    →  fix_record addressed
  no  → fix_record remaining '{"reason":"declined by user"}'
```

Apply the edit **in this skill** (`allowed-tools` deliberately excludes `Task`).
`agents/wp-theme-developer.md:10` grants unconstrained `Edit`/`Write` and carries
no approval or ordering contract — a delegated agent can rewrite the file its own
way, breaking both guarantees.

Runtime ops (`option update`, `rewrite flush`, plugin bisect, DB writes) →
`references/fix-runtime.md`.

### 4. Verify — Gate 3

```bash
# 1. Syntax first — cheap and decisive.
php -l <each changed file>

# 2. One call. CHANGED is the repo-relative files you actually edited.
CHANGED='["wp-content/themes/acme/header.php"]'
RESULT="$(fix_verify "$CHANGED")" || echo "fix: re-scan failed — UNVERIFIED" >&2
```

Use `fix_verify` — **not** `fix_static_rescan` + `fix_verify_diff` by hand. It
wraps baseline → re-scan → diff so the three inputs cannot be mis-wired, and so
every path stays in **one space: repo-relative**. Mixing spellings silently
breaks the diff — an absolute re-scan against a repo-relative baseline shares no
keys, so every finding reads as both `resolved` and `new`, and `unresolved[]` is
always empty (i.e. a broken fix reports clean).

`CHANGED` must hold the same repo-relative paths as `fix.filesChanged`.

`fix_verify` compares **static findings only** — live findings can never be
reproduced by a static scan, so an unfiltered diff reports them all "gone" and
verifies a run that fixed nothing. It also re-scans at the **same scope the
baseline audit used** (`audit.scope`); narrowing `all` → `self` would make every
finding outside the theme read as fixed.

`verified: true` means **no regression, and every targeted finding whose rule can
actually clear did clear.**

- `status: pass` → no regressions, no un-cleared clearing rules.
- `status: fail` → a new static finding appeared, **or** a targeted clearing-rule
  finding is still there (`unresolved[]` — the fix did not work). Restore from
  `fix.backupDir` (`fix_restore <file>`) and report.
- `status: scanner-failed` → **report unverified.** Never PASS. See HARD-GATE-VERIFY.

### A correct fix usually does NOT clear the finding

`audit-static.sh` greps for risky **constructs**, not defects. Only `sec-eval`
(the fix deletes `eval()`) and `wpcs-missing-nonce` (an absence check) clear. The
other seven still match after a correct fix — `sanitize_text_field( wp_unslash(
$_GET['q'] ) )` still matches `wpcs-missing-sanitize`'s pattern `\$_(GET|…)`.

They return as `stillFlagged[]` — **expected, not a failure.** Do not re-fix them,
do not report the run as failed, and never delete the superglobal to silence the
scanner. Say plainly: *"the finding still appears because the rule flags any
`$_GET` read; the value is now sanitised."* Detail:
`references/triage-findings.md`.

Known v1 limitation, stated rather than hidden: the diff key is `id + file` by
count, so a same-count substitution at one `id + file` is not detectable.

### 5. Record

```bash
VERIFIED="$(jq -r '.verified // false' <<<"$RESULT")"   # from step 4; false if the scan failed
wpbuild_set '.fix.verified' "$VERIFIED"
wpbuild_progress fix done "addressed=$N dismissed=$D remaining=$R unsupported=$U verified=$VERIFIED"
```

Then tell the user, in plain terms: what was changed, what was dismissed and why,
what remains, what is unsupported (and which skill owns it), and — honestly —
whether it is **verified**. If `status` was `scanner-failed`, say the fix is
unverified rather than reporting success.

## Output

`wp-build.json` gains a `fix` object: `generatedAt`, `trigger`, `addressed[]`,
`dismissed[]`, `remaining[]`, `unsupported[]`, `filesChanged[]`, `backupDir`,
`runtimeChanges[]`, `verified`.

All paths are **repo-relative**. `runtimeChanges[]` records the option **name**
only — never its value: option values hold SMTP/API credentials and
`wp-build.json` is committed (`skills/wp-security/references/secrets-scan.sh:8`
never prints a matched secret; do not invert that here).

## References

- `references/triage-findings.md` — per-rule false-positive signatures + fix patterns.
- `references/fix-runtime.md` — WP-CLI runtime ops, DB safety, plugin bisect.
- `references/fault-taxonomy.md` — free-text symptom → fault class → playbook.
- `references/fix-php-fatal.md` · `fix-template.md` · `fix-data.md` — playbooks.
